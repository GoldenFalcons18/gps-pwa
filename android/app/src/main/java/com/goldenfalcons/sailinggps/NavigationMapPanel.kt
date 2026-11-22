package com.goldenfalcons.sailinggps

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.widget.AppCompatEditText
import org.json.JSONObject
import kotlin.math.pow
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.geometry.LatLngBounds
import org.maplibre.android.MapLibre
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.style.expressions.Expression
import org.maplibre.android.style.layers.CircleLayer
import org.maplibre.android.style.layers.FillLayer
import org.maplibre.android.style.layers.LineLayer
import org.maplibre.android.style.layers.Property
import org.maplibre.android.style.layers.PropertyFactory
import org.maplibre.android.style.layers.SymbolLayer
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.geojson.Feature
import org.maplibre.geojson.FeatureCollection
import org.maplibre.geojson.LineString
import org.maplibre.geojson.Point as JsonPoint
import org.maplibre.geojson.Polygon
import java.io.File
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.roundToInt

/** OpenFreeMap rendering with the same navigation overlays and GPS samples as the recorder. */
class NavigationMapPanel(
    context: Context,
    container: FrameLayout,
    private val log: (String) -> Unit,
    private val createWaypoint: (Double, Double) -> Unit,
    private val editWaypoint: (Waypoint) -> Unit
) {
    private val appContext = context
    private val mapView: MapView
    private var map: MapLibreMap? = null
    private var mapStyle: Style? = null
    private val track = mutableListOf<LatLng>()
    private var trackRecording = false
    private var waypoints = emptyList<Waypoint>()
    private var features = emptyList<MapFeature>()
    private var activeWaypoint: Waypoint? = null
    private var hiddenGroups = emptySet<String>()
    private var target: LatLng? = null
    private var current: LatLng? = null
    private var lastHeading: Double? = null
    private var following = true
    private var showWaypoints = true
    private var showCourse = true
    private var metersPerCm = 200.0
    private var styleName: String
    private var paused = false
    private var destroyed = false
    private var lastTrackPoint: LatLng? = null
    private var lastFollowLogAt = 0L
    private var pendingManualZoom: Double? = null
    private var followZoomOffset = 0.0
    private val offlineStore by lazy { OpenFreeMapOfflineStore(appContext) }
    var onFollowingChanged: ((Boolean) -> Unit)? = null

    private fun setFollowing(value: Boolean) {
        following = value
        onFollowingChanged?.invoke(value)
    }

    init {
        OpenFreeMapConfig.configure(context)
        MapLibre.getInstance(context)
        styleName = context.getSharedPreferences("display", Context.MODE_PRIVATE)
            .getString("mapStyle", "liberty") ?: "liberty"
        mapView = MapView(context)
        // Keep pan, pinch and long-press map gestures inside the map instead of
        // letting the dashboard ScrollView steal the touch sequence.
        mapView.setOnTouchListener { view, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE ->
                    view.parent?.requestDisallowInterceptTouchEvent(true)
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL ->
                    view.parent?.requestDisallowInterceptTouchEvent(false)
            }
            false
        }
        mapView.onCreate(null)
        mapView.getMapAsync { readyMap ->
            map = readyMap
            readyMap.setStyle(OpenFreeMapConfig.styleUrl(styleName)) { style ->
                if (destroyed) return@setStyle
                mapStyle = style
                installLayers(style)
                refreshAll()
                if (following && current != null) {
                    applyFollow()
                } else {
                    readyMap.cameraPosition = CameraPosition.Builder()
                        .target(current ?: LatLng(35.30, 139.48)).zoom(12.0).build()
                }
            }
            readyMap.addOnMapLongClickListener { location ->
                setFollowing(false)
                val clicked = readyMap.projection.toScreenLocation(location)
                val hit = waypoints.asSequence()
                    .filter { (it.group ?: "") !in hiddenGroups }
                    .map { wp -> wp to readyMap.projection.toScreenLocation(LatLng(wp.lat, wp.lon)) }
                    .minByOrNull { (_, p) -> hypot((p.x - clicked.x).toDouble(), (p.y - clicked.y).toDouble()) }
                    ?.takeIf { (_, p) -> hypot((p.x - clicked.x).toDouble(), (p.y - clicked.y).toDouble()) <= 48.0 * context.resources.displayMetrics.density }
                    ?.first
                if (hit != null) editWaypoint(hit) else createWaypoint(location.latitude, location.longitude)
                true
            }
            readyMap.addOnCameraMoveStartedListener { reason ->
                if (reason == MapLibreMap.OnCameraMoveStartedListener.REASON_API_GESTURE) {
                    pendingManualZoom = null
                    setFollowing(false)
                }
            }
            readyMap.addOnCameraIdleListener {
                if (!following) synchronizeScaleFromCamera(readyMap)
                logWaypointTouchLocations(readyMap)
            }
        }
        container.addView(mapView, FrameLayout.LayoutParams(-1, -1))
        val controls = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
        }
        listOf("＋" to "地図を拡大", "−" to "地図を縮小").forEachIndexed { index, entry ->
            controls.addView(Button(context).apply {
                text = entry.first
                contentDescription = entry.second
                textSize = 20f
                isAllCaps = false
                setTextColor(Color.WHITE)
                background = android.graphics.drawable.GradientDrawable().apply {
                    cornerRadius = 8 * context.resources.displayMetrics.density
                    setColor(Color.argb(220, 20, 20, 20))
                }
                setPadding(0, 0, 0, 0)
                minWidth = 0
                minHeight = 0
                setOnClickListener { zoomBy(if (index == 0) 1.0 else -1.0) }
            }, LinearLayout.LayoutParams(
                (40 * context.resources.displayMetrics.density).toInt(),
                (40 * context.resources.displayMetrics.density).toInt()
            ).apply { bottomMargin = (4 * context.resources.displayMetrics.density).toInt() })
        }
        container.addView(controls, FrameLayout.LayoutParams(-2, -2, Gravity.END or Gravity.CENTER_VERTICAL))

        val density = context.resources.displayMetrics.density
        val locate = Button(context).apply {
            text = "➤"
            textSize = 22f
            rotation = -45f
            setTextColor(Color.WHITE)
            isAllCaps = false
            contentDescription = "現在地へ追従"
            background = android.graphics.drawable.GradientDrawable().apply {
                shape = android.graphics.drawable.GradientDrawable.OVAL
                setColor(Color.argb(230, 0, 0, 0))
            }
            setPadding(0, 0, 0, 0)
            setOnClickListener { followLocation() }
        }
        container.addView(locate, FrameLayout.LayoutParams(
            (40 * density).toInt(), (40 * density).toInt(),
            Gravity.BOTTOM or Gravity.START
        ).apply {
            leftMargin = (8 * density).toInt()
            bottomMargin = (8 * density).toInt()
        })

        log("Map initialized / OpenFreeMap / MapLibre")
    }

    private fun logWaypointTouchLocations(readyMap: MapLibreMap) {
        if (!BuildConfig.DEBUG || destroyed) return
        val origin = IntArray(2)
        mapView.getLocationOnScreen(origin)
        waypoints.filter { (it.group ?: "") !in hiddenGroups }.forEach { waypoint ->
            val point = readyMap.projection.toScreenLocation(LatLng(waypoint.lat, waypoint.lon))
            android.util.Log.d("SailingUiBounds", "WP_TOUCH id=${waypoint.id} x=${origin[0] + point.x.toInt()} y=${origin[1] + point.y.toInt()}")
        }
    }

    fun setMapStyle(name: String) {
        val normalized = name.takeIf { it in listOf("liberty", "bright", "positron", "dark") } ?: "liberty"
        if (normalized == styleName) return
        styleName = normalized
        appContext.getSharedPreferences("display", Context.MODE_PRIVATE).edit().putString("mapStyle", normalized).apply()
        map?.setStyle(OpenFreeMapConfig.styleUrl(normalized)) { style ->
            if (destroyed) return@setStyle
            mapStyle = style
            installLayers(style)
            refreshAll()
        }
    }

    fun setDisplayOptions(waypointsVisible: Boolean, courseVisible: Boolean) {
        showWaypoints = waypointsVisible
        showCourse = courseVisible
        refreshAll()
    }

    private fun installLayers(style: Style) {
        val empty = FeatureCollection.fromFeatures(emptyArray()).toJson()
        listOf("trail", "course", "target", "course-dots", "boat", "waypoints", "features").forEach { id ->
            if (style.getSource(id) == null) style.addSource(GeoJsonSource(id, empty))
        }
        if (style.getLayer("features-fill") == null) style.addLayer(
            FillLayer("features-fill", "features").withProperties(
                PropertyFactory.fillColor(Expression.get("color")),
                PropertyFactory.fillOpacity(0.22f)
            )
        )
        if (style.getLayer("features-line") == null) style.addLayer(
            LineLayer("features-line", "features").withProperties(
                PropertyFactory.lineColor(Expression.get("color")),
                PropertyFactory.lineWidth(3f)
            )
        )
        if (style.getLayer("trail-line") == null) style.addLayer(
            LineLayer("trail-line", "trail").withProperties(
                PropertyFactory.lineColor(Expression.get("color")),
                PropertyFactory.lineWidth(4f)
            )
        )
        if (style.getLayer("target-line") == null) style.addLayer(
            LineLayer("target-line", "target").withProperties(
                PropertyFactory.lineColor(Color.GREEN),
                PropertyFactory.lineWidth(3f)
            )
        )
        if (style.getLayer("course-line") == null) style.addLayer(
            LineLayer("course-line", "course").withProperties(
                PropertyFactory.lineColor(Color.BLACK),
                PropertyFactory.lineWidth(2f)
            )
        )
        if (style.getLayer("course-dots-layer") == null) style.addLayer(
            CircleLayer("course-dots-layer", "course-dots").withProperties(
                PropertyFactory.circleRadius(4f),
                PropertyFactory.circleColor(Color.BLACK),
                PropertyFactory.circleStrokeColor(Color.WHITE),
                PropertyFactory.circleStrokeWidth(1f)
            )
        )
        if (style.getLayer("waypoint-circles") == null) style.addLayer(
            CircleLayer("waypoint-circles", "waypoints").withProperties(
                PropertyFactory.circleRadius(7f),
                PropertyFactory.circleColor(Expression.get("color")),
                PropertyFactory.circleStrokeColor(Color.WHITE),
                PropertyFactory.circleStrokeWidth(1.5f)
            )
        )
        if (style.getLayer("waypoint-names") == null) style.addLayer(
            SymbolLayer("waypoint-names", "waypoints").withProperties(
                PropertyFactory.textField(Expression.get("name")),
                PropertyFactory.textSize(12f),
                PropertyFactory.textColor(Color.WHITE),
                PropertyFactory.textHaloColor(Color.BLACK),
                PropertyFactory.textHaloWidth(1.5f),
                PropertyFactory.textOffset(arrayOf(0f, 1.4f)),
                PropertyFactory.textAllowOverlap(false)
            )
        )
        if (style.getLayer("waypoint-marks") == null) style.addLayer(
            SymbolLayer("waypoint-marks", "waypoints").withProperties(
                PropertyFactory.textField(Expression.get("mark")),
                PropertyFactory.textSize(11f),
                PropertyFactory.textColor(Color.WHITE),
                PropertyFactory.textHaloColor(Color.BLACK),
                PropertyFactory.textHaloWidth(1f),
                PropertyFactory.textOffset(arrayOf(0f, -0.1f)),
                PropertyFactory.textAllowOverlap(false)
            )
        )
        if (style.getLayer("boat-dot") == null) style.addLayer(
            CircleLayer("boat-dot", "boat").withProperties(
                PropertyFactory.circleRadius(8f),
                PropertyFactory.circleColor(Color.rgb(10, 25, 45)),
                PropertyFactory.circleStrokeColor(Color.WHITE),
                PropertyFactory.circleStrokeWidth(2f)
            )
        )
        if (style.getLayer("boat-heading") == null) style.addLayer(
            SymbolLayer("boat-heading", "boat").withProperties(
                PropertyFactory.textField("▲"),
                PropertyFactory.textSize(16f),
                PropertyFactory.textColor(Color.WHITE),
                PropertyFactory.textHaloColor(Color.BLACK),
                PropertyFactory.textHaloWidth(1f),
                PropertyFactory.textRotate(Expression.get("bearing"))
            )
        )
        applyVisibility()
    }

    private fun setSource(id: String, features: List<Feature>) {
        val json = FeatureCollection.fromFeatures(features.toTypedArray()).toJson()
        (mapStyle?.getSource(id) as? GeoJsonSource)?.setGeoJson(json)
    }

    private fun pointFeature(lat: Double, lon: Double, props: JSONObject = JSONObject()): Feature =
        Feature.fromGeometry(JsonPoint.fromLngLat(lon, lat)).also { feature ->
            val keys = props.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                when (val value = props.get(key)) {
                    is String -> feature.addStringProperty(key, value)
                    is Number -> feature.addNumberProperty(key, value)
                    is Boolean -> feature.addBooleanProperty(key, value)
                }
            }
        }

    private fun lineFeature(points: List<LatLng>, props: JSONObject = JSONObject()): Feature? {
        if (points.size < 2) return null
        return Feature.fromGeometry(LineString.fromLngLats(points.map { JsonPoint.fromLngLat(it.longitude, it.latitude) })).also { feature ->
            val keys = props.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                feature.addStringProperty(key, props.optString(key))
            }
        }
    }

    private fun refreshAll() {
        setSource("trail", listOfNotNull(lineFeature(track, JSONObject().put("color", if (trackRecording) "#FFAA00" else "#808080"))))
        val targetPoints = listOfNotNull(current, target)
        setSource("target", listOfNotNull(lineFeature(targetPoints)))
        val displayPrefs = appContext.getSharedPreferences("display", Context.MODE_PRIVATE)
        val courseLength = displayPrefs.getInt("courseLineLengthMeters", 500).coerceIn(100, 5000)
        val markInterval = displayPrefs.getInt("courseMarkIntervalMeters", 100).coerceIn(25, courseLength)
        val markDistances = generateSequence(markInterval) { it + markInterval }.takeWhile { it <= courseLength }.toList()
        setSource("course", if (current != null && lastHeading != null) {
            val origin = current!!
            val projected = markDistances.map { distance ->
                DisplayNavigation.destination(origin.latitude, origin.longitude, lastHeading!!, distance.toDouble())
                    .let { LatLng(it.first, it.second) }
            }
            val end = DisplayNavigation.destination(origin.latitude, origin.longitude, lastHeading!!, courseLength.toDouble())
                .let { LatLng(it.first, it.second) }
            listOfNotNull(lineFeature(listOf(origin) + projected + end))
        } else emptyList())
        setSource("course-dots", if (current != null && lastHeading != null) {
            markDistances.map { distance ->
                val p = DisplayNavigation.destination(current!!.latitude, current!!.longitude, lastHeading!!, distance.toDouble())
                pointFeature(p.first, p.second)
            }
        } else emptyList())
        val displayed = waypoints.filter { (it.group ?: "") !in hiddenGroups }
        setSource("waypoints", displayed.map { wp ->
            val props = JSONObject()
                .put("name", wp.name)
                .put("mark", wp.mark.ifEmpty { "●" })
                .put("color", wp.color.ifEmpty { "#FFAA00" })
                .put("active", wp.id == activeWaypoint?.id)
            pointFeature(wp.lat, wp.lon, props)
        })
        val featureShapes = features.mapNotNull { feature ->
            val coords = feature.boundary(waypoints).map { JsonPoint.fromLngLat(it.lon, it.lat) }
            val geometry = if (feature.kind == "line") {
                if (coords.size < 2) null else LineString.fromLngLats(coords)
            } else {
                if (coords.size < 3) null else Polygon.fromLngLats(listOf(coords + coords.first()))
            } ?: return@mapNotNull null
            Feature.fromGeometry(geometry).also { it.addStringProperty("color", feature.color) }
        }
        setSource("features", featureShapes)
        val boatFeatures = current?.let {
            listOf(pointFeature(it.latitude, it.longitude, JSONObject().put("bearing", lastHeading ?: 0.0)))
        } ?: emptyList()
        setSource("boat", boatFeatures)
        applyVisibility()
    }

    private fun applyVisibility() {
        val style = mapStyle ?: return
        val waypointVisibility = if (showWaypoints) Property.VISIBLE else Property.NONE
        val courseVisibility = if (showCourse) Property.VISIBLE else Property.NONE
        listOf("waypoint-circles", "waypoint-names", "waypoint-marks").forEach { id ->
            style.getLayer(id)?.setProperties(PropertyFactory.visibility(waypointVisibility))
        }
        listOf("course-line", "course-dots-layer").forEach { id ->
            style.getLayer(id)?.setProperties(PropertyFactory.visibility(courseVisibility))
        }
        mapView.invalidate()
    }

    fun updateLocation(lat: Double, lon: Double, bearing: Double?, recordTrack: Boolean = true) {
        val point = LatLng(lat, lon)
        current = point
        lastHeading = bearing
        if (recordTrack && lastTrackPoint != point) {
            lastTrackPoint = point
            track.add(point)
        }
        refreshAll()
        if (following) applyFollow()
    }

    fun setFeatures(features: List<MapFeature>, waypoints: List<Waypoint>) {
        this.features = features.toList()
        refreshAll()
    }

    fun setWaypoints(waypoints: List<Waypoint>, active: Waypoint?, hiddenGroups: Set<String> = emptySet()) {
        this.waypoints = waypoints.toList()
        activeWaypoint = active
        this.hiddenGroups = hiddenGroups.toSet()
        target = active?.let { LatLng(it.lat, it.lon) }
        refreshAll()
    }

    fun showWaypoints() {
        val readyMap = map ?: return
        val points = waypoints.filter { (it.group ?: "") !in hiddenGroups }
            .map { LatLng(it.lat, it.lon) } + listOfNotNull(current)
        if (points.isEmpty()) return
        setFollowing(false)
        val bounds = LatLngBounds.Builder().apply { points.forEach { include(it) } }.build()
        readyMap.animateCamera(CameraUpdateFactory.newLatLngBounds(bounds, 32), 350)
        log("Map show waypoints / ${points.size}")
    }

    private fun zoomBy(delta: Double) {
        val readyMap = map ?: return
        if (following) {
            metersPerCm = (metersPerCm / 2.0.pow(delta)).coerceIn(12.5, 6400.0)
            applyFollow()
        } else {
            // Accumulate taps against the requested camera zoom, not the intermediate
            // camera position while MapLibre is still animating the previous tap.
            val currentPosition = readyMap.cameraPosition
            val targetZoom = ((pendingManualZoom ?: currentPosition.zoom) + delta).coerceIn(2.0, 20.0)
            pendingManualZoom = targetZoom
            readyMap.animateCamera(CameraUpdateFactory.newCameraPosition(
                CameraPosition.Builder(currentPosition).zoom(targetZoom).build()
            ), 180)
        }
    }

    private fun synchronizeScaleFromCamera(readyMap: MapLibreMap) {
        val camera = readyMap.cameraPosition
        val cameraTarget = camera.target ?: current ?: return
        val metrics = mapView.resources.displayMetrics
        val dpi = metrics.xdpi.takeIf { it.isFinite() && it > 50f } ?: metrics.densityDpi.toFloat()
        val pixelsPerCm = dpi / 2.54
        val metersPerCmAtCenter = 156543.033928 *
            kotlin.math.cos(Math.toRadians(cameraTarget.latitude)).coerceAtLeast(0.000001) *
            pixelsPerCm / 2.0.pow(camera.zoom)
        if (metersPerCmAtCenter.isFinite() && metersPerCmAtCenter > 0) {
            metersPerCm = metersPerCmAtCenter.coerceIn(12.5, 6400.0)
            val dpi = metrics.xdpi.takeIf { it.isFinite() && it > 50f } ?: metrics.densityDpi.toFloat()
            val baseZoom = DisplayNavigation.zoom(cameraTarget.latitude, dpi / 2.54, metersPerCm)
            followZoomOffset = camera.zoom - baseZoom
            pendingManualZoom = null
        }
    }

    private fun applyFollow() {
        val readyMap = map ?: return
        val point = current ?: return
        val metrics = mapView.resources.displayMetrics
        val dpi = metrics.xdpi.takeIf { it.isFinite() && it > 50f } ?: metrics.densityDpi.toFloat()
        val zoom = (DisplayNavigation.zoom(point.latitude, dpi / 2.54, metersPerCm) + followZoomOffset).coerceIn(2.0, 20.0)
        readyMap.cameraPosition = CameraPosition.Builder()
            .target(point)
            .zoom(zoom)
            .bearing(lastHeading ?: 0.0)
            .build()
        val now = android.os.SystemClock.uptimeMillis()
        if (now - lastFollowLogAt >= 500) {
            lastFollowLogAt = now
            log("Map follow / current location centered / heading=$lastHeading")
        }
    }

    fun followLocation() {
        setFollowing(true)
        applyFollow()
        log("Map follow enabled / heading-up / boat-at-72-percent")
    }

    fun setTrackRecording(active: Boolean) {
        if (trackRecording == active) return
        trackRecording = active
        refreshAll()
    }

    fun clearTrack() {
        track.clear()
        lastTrackPoint = null
        refreshAll()
    }

    fun resume() {
        paused = false
        mapView.onStart()
        mapView.onResume()
        loadTrackFile(GpsLoggingService.trackFile(appContext))
    }

    fun showTrackFile(file: File) {
        setFollowing(false)
        loadTrackFile(file)
    }

    private fun loadTrackFile(file: File) {
        Thread {
            val restored = ArrayDeque<LatLng>()
            runCatching {
                if (file.exists()) file.useLines { lines ->
                    lines.forEach { line ->
                        val fields = line.split(',')
                        val lat = fields.getOrNull(1)?.toDoubleOrNull()
                        val lon = fields.getOrNull(2)?.toDoubleOrNull()
                        if (lat != null && lon != null && lat in -90.0..90.0 && lon in -180.0..180.0) {
                            restored.addLast(LatLng(lat, lon))
                        }
                    }
                }
            }.onFailure { error -> mapView.post { if (!destroyed) log("Map track read error: ${error.message}") } }
            mapView.post {
                if (!destroyed) {
                    track.clear()
                    track.addAll(restored)
                    lastTrackPoint = track.lastOrNull()
                    refreshAll()
                    log("Map track restored / ${track.size} points / ${file.name}")
                }
            }
        }.start()
    }

    fun pause() {
        paused = true
        mapView.onPause()
        mapView.onStop()
    }

    fun destroy() {
        destroyed = true
        mapView.onDestroy()
    }

    private fun visibleBounds(): LatLngBounds? {
        val readyMap = map ?: return null
        if (mapView.width <= 0 || mapView.height <= 0) return null
        val nw = readyMap.projection.fromScreenLocation(PointF(0f, 0f))
        val se = readyMap.projection.fromScreenLocation(PointF(mapView.width.toFloat(), mapView.height.toFloat()))
        return LatLngBounds.Builder().include(nw).include(se).build()
    }

    fun openOfflineMapSettings() {
        showOfflineMenu()
    }

    private fun showOfflineMenu() {
        AlertDialog.Builder(appContext)
            .setTitle("オフライン地図")
            .setItems(arrayOf("この範囲を保存", "保存した地図")) { _, which ->
                if (which == 0) askOfflineZoom() else listOfflineMaps()
            }
            .setNegativeButton("閉じる", null)
            .show()
    }

    private fun askOfflineZoom() = showOfflineRegionPicker()

    private fun showOfflineRegionPicker() {
        val sourceMap = map ?: return
        val initialCamera = sourceMap.cameraPosition
        val density = appContext.resources.displayMetrics.density
        fun dp(value: Int) = (value * density).roundToInt()
        fun text(value: String, size: Float = 14f) = TextView(appContext).apply {
            this.text = value
            textSize = size
            setTextColor(Color.WHITE)
        }
        val root = ScrollView(appContext)
        val content = LinearLayout(appContext).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(8), dp(12), dp(12))
        }
        root.addView(content, android.view.ViewGroup.LayoutParams(-1, -2))
        val mapFrame = FrameLayout(appContext)
        val preview = MapView(appContext).apply {
            onCreate(null)
            setOnTouchListener { view, event ->
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE -> view.parent?.requestDisallowInterceptTouchEvent(true)
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> view.parent?.requestDisallowInterceptTouchEvent(false)
                }
                false
            }
        }
        mapFrame.addView(preview, FrameLayout.LayoutParams(-1, dp(250)))
        mapFrame.addView(OfflineRegionFrame(appContext), FrameLayout.LayoutParams(-1, -1))
        content.addView(mapFrame, LinearLayout.LayoutParams(-1, dp(250)))

        val boundsText = text("地図を読み込み中…", 12f)
        boundsText.setPadding(0, dp(6), 0, dp(4))
        content.addView(boundsText)
        var previewMinimumZoom = true
        var updateEstimateAction: (() -> Unit)? = null
        val previewSelector = LinearLayout(appContext).apply { orientation = LinearLayout.HORIZONTAL }
        lateinit var minPreviewButton: Button
        lateinit var maxPreviewButton: Button
        minPreviewButton = Button(appContext).apply {
            text = "最小ズーム"
            setOnClickListener { previewMinimumZoom = true; updateEstimateAction?.invoke() }
        }
        maxPreviewButton = Button(appContext).apply {
            text = "最大ズーム"
            setOnClickListener { previewMinimumZoom = false; updateEstimateAction?.invoke() }
        }
        previewSelector.addView(minPreviewButton, LinearLayout.LayoutParams(0, dp(42), 1f))
        previewSelector.addView(maxPreviewButton, LinearLayout.LayoutParams(0, dp(42), 1f))
        content.addView(previewSelector)
        val maxPreviewTitle = text("最小ズームの見え方", 13f)
        content.addView(maxPreviewTitle)
        val zoomPreviewFrame = FrameLayout(appContext)
        val zoomPreviewView = MapView(appContext).apply { onCreate(null) }
        zoomPreviewFrame.addView(zoomPreviewView, FrameLayout.LayoutParams(-1, dp(240)))
        val savedBoundsOverlay = OfflineZoomBoundsOverlay(appContext)
        zoomPreviewFrame.addView(savedBoundsOverlay, FrameLayout.LayoutParams(-1, dp(240)))
        content.addView(zoomPreviewFrame, LinearLayout.LayoutParams(-1, dp(240)))
        val previewHelp = text("地図全体がこのズームで一度に見える範囲です。オレンジ枠がダウンロード範囲です。", 12f).apply {
            setTextColor(Color.LTGRAY)
        }
        content.addView(previewHelp)
        var zoomPreviewMap: MapLibreMap? = null
        var selectedBounds: LatLngBounds? = null
        var minZoom = (floor(initialCamera.zoom).toInt() - 2).coerceIn(4, 18)
        var maxZoom = floor(initialCamera.zoom).toInt().coerceIn(4, 18)
        fun updateZoomPreview() {
            val shownZoom = if (previewMinimumZoom) minZoom else maxZoom
            maxPreviewTitle.text = (if (previewMinimumZoom) "最小" else "最大") + "ズーム " + shownZoom + " の一画面表示"
            minPreviewButton.isEnabled = !previewMinimumZoom
            maxPreviewButton.isEnabled = previewMinimumZoom
            val bounds = selectedBounds
            val center = bounds?.let {
                LatLng((it.latitudeNorth + it.latitudeSouth) / 2.0, (it.longitudeEast + it.longitudeWest) / 2.0)
            } ?: initialCamera.target ?: LatLng(35.30, 139.48)
            zoomPreviewMap?.cameraPosition = CameraPosition.Builder(initialCamera)
                .target(center).zoom(shownZoom.toDouble()).bearing(0.0).tilt(0.0).build()
            savedBoundsOverlay.update(zoomPreviewMap, bounds)
        }
        val nameInput = AppCompatEditText(appContext).apply {
            hint = "保存名"
            setSingleLine(true)
            setTextColor(Color.WHITE)
            setHintTextColor(Color.LTGRAY)
            setText("オフライン地図")
        }
        content.addView(nameInput, LinearLayout.LayoutParams(-1, dp(48)))

        val minLabel = text("最小ズーム: $minZoom")
        val minSeek = SeekBar(appContext).apply { max = 18; progress = minZoom }
        val maxLabel = text("最大ズーム: $maxZoom")
        val maxSeek = SeekBar(appContext).apply { max = 18; progress = maxZoom }
        val countLabel = text("保存タイル: -- / ${OpenFreeMapConfig.MAX_TILES_PER_DOWNLOAD}", 13f)
        content.addView(minLabel)
        content.addView(minSeek, LinearLayout.LayoutParams(-1, dp(36)))
        content.addView(maxLabel)
        content.addView(maxSeek, LinearLayout.LayoutParams(-1, dp(36)))
        content.addView(countLabel)

        fun updateEstimate() {
            updateZoomPreview()
            val bounds = selectedBounds
            if (bounds == null) {
                boundsText.text = "地図範囲を読み込み中…"
                countLabel.text = "保存タイル: -- / ${OpenFreeMapConfig.MAX_TILES_PER_DOWNLOAD}"
                return
            }
            boundsText.text = "枠内の範囲  南西 %.4f°, %.4f° 〜 北東 %.4f°, %.4f°".format(
                java.util.Locale.US, bounds.latitudeSouth, bounds.longitudeWest,
                bounds.latitudeNorth, bounds.longitudeEast
            )
            val tiles = OpenFreeMapConfig.estimateTileCount(
                bounds.longitudeWest, bounds.latitudeSouth, bounds.longitudeEast, bounds.latitudeNorth, minZoom, maxZoom
            )
            countLabel.text = if (tiles <= OpenFreeMapConfig.MAX_TILES_PER_DOWNLOAD)
                "保存タイル: $tiles / ${OpenFreeMapConfig.MAX_TILES_PER_DOWNLOAD}"
            else "保存タイル: $tiles（上限超過。範囲またはズームを小さくしてください）"
        }
        updateEstimateAction = { updateEstimate() }
        minSeek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                minZoom = progress.coerceAtMost(maxZoom)
                minLabel.text = "最小ズーム: $minZoom"
                updateEstimate()
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {}
        })
        maxSeek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                maxZoom = progress.coerceAtLeast(minZoom)
                maxLabel.text = "最大ズーム: $maxZoom"
                updateEstimate()
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {}
        })

        val dialog = AlertDialog.Builder(appContext)
            .setTitle("オフライン地図の保存範囲")
            .setView(root)
            .setNegativeButton("キャンセル", null)
            .setPositiveButton("ダウンロード開始", null)
            .create()
        dialog.setOnShowListener {
            dialog.window?.setLayout(-1, (appContext.resources.displayMetrics.heightPixels * 0.86).toInt())
            preview.onStart()
            preview.onResume()
            zoomPreviewView.onStart()
            zoomPreviewView.onResume()
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val bounds = selectedBounds
                if (bounds == null) {
                    Toast.makeText(appContext, "地図範囲を取得できませんでした", Toast.LENGTH_SHORT).show()
                    return@setOnClickListener
                }
                val tiles = OpenFreeMapConfig.estimateTileCount(
                    bounds.longitudeWest, bounds.latitudeSouth, bounds.longitudeEast, bounds.latitudeNorth, minZoom, maxZoom
                )
                if (tiles !in 1..OpenFreeMapConfig.MAX_TILES_PER_DOWNLOAD) {
                    Toast.makeText(appContext, "範囲またはズームを小さくしてください", Toast.LENGTH_SHORT).show()
                    return@setOnClickListener
                }
                val name = nameInput.text?.toString()?.trim().orEmpty().ifBlank { "オフライン地図" }
                offlineStore.createRegion(
                    name, bounds, minZoom.toDouble(), maxZoom.toDouble(),
                    OpenFreeMapConfig.styleUrl(styleName),
                    { _, bytes, count, pausedBySize ->
                        if (pausedBySize) Toast.makeText(
                            appContext,
                            "保存を安全のため一時停止しました（約${count}タイル / ${bytes / 1024 / 1024}MB）。範囲を小さくして再保存してください。",
                            Toast.LENGTH_LONG
                        ).show()
                        else if (count > 0 && count % 100L == 0L) log("Offline map / $name / $count tiles")
                    },
                    { error -> Toast.makeText(appContext, error, Toast.LENGTH_LONG).show() }
                )
                Toast.makeText(appContext, "「$name」の保存を開始しました", Toast.LENGTH_SHORT).show()
                dialog.dismiss()
            }
        }
        dialog.setOnDismissListener {
            preview.onPause()
            preview.onStop()
            preview.onDestroy()
            zoomPreviewView.onPause()
            zoomPreviewView.onStop()
            zoomPreviewView.onDestroy()
        }
        zoomPreviewView.getMapAsync { zoomMap ->
            zoomMap.setStyle(OpenFreeMapConfig.styleUrl(styleName)) {
                zoomPreviewMap = zoomMap
                zoomMap.addOnCameraIdleListener { savedBoundsOverlay.invalidate() }
                updateZoomPreview()
                zoomMap.uiSettings.setAllGesturesEnabled(false)
            }
        }
        preview.getMapAsync { previewMap ->
            previewMap.setStyle(OpenFreeMapConfig.styleUrl(styleName)) {
                previewMap.cameraPosition = CameraPosition.Builder(initialCamera).bearing(0.0).tilt(0.0).build()
                fun refreshBounds() {
                    if (preview.width <= 0 || preview.height <= 0) return
                    val insetX = preview.width * 0.08f
                    val insetY = preview.height * 0.10f
                    val nw = previewMap.projection.fromScreenLocation(PointF(insetX, insetY))
                    val se = previewMap.projection.fromScreenLocation(PointF(preview.width - insetX, preview.height - insetY))
                    selectedBounds = runCatching { LatLngBounds.Builder().include(nw).include(se).build() }.getOrNull()
                    updateEstimate()
                }
                previewMap.uiSettings.setRotateGesturesEnabled(false)
                previewMap.uiSettings.setTiltGesturesEnabled(false)
                previewMap.addOnCameraIdleListener { refreshBounds() }
                preview.post { refreshBounds() }
            }
        }
        dialog.show()
    }

    private fun listOfflineMaps() {
        offlineStore.list({ regions ->
            if (regions.isEmpty()) {
                AlertDialog.Builder(appContext).setTitle("保存した地図")
                    .setMessage("保存地図はありません。地図を表示して「保存」から範囲を選んでください。")
                    .setPositiveButton("閉じる", null).show()
                return@list
            }
            val names = regions.map { offlineStore.label(it) }.toTypedArray()
            AlertDialog.Builder(appContext).setTitle("保存した地図")
                .setItems(names) { _, index -> showOfflineRegionActions(regions[index]) }
                .setNegativeButton("閉じる", null).show()
        }, { error -> Toast.makeText(appContext, error, Toast.LENGTH_LONG).show() })
    }

    private fun showOfflineRegionActions(region: org.maplibre.android.offline.OfflineRegion) {
        region.getStatus(object : org.maplibre.android.offline.OfflineRegion.OfflineRegionStatusCallback {
            override fun onStatus(status: org.maplibre.android.offline.OfflineRegionStatus?) {
                status ?: return
                val size = status.completedResourceSize / 1024 / 1024
                val downloading = status.downloadState == org.maplibre.android.offline.OfflineRegion.STATE_ACTIVE
                val actions = if (downloading) arrayOf("一時停止", "削除") else arrayOf("ダウンロード再開", "削除")
                AlertDialog.Builder(appContext).setTitle(offlineStore.label(region))
                    .setMessage("${if (status.isComplete) "保存完了" else if (downloading) "保存中" else "一時停止中"} · ${status.completedTileCount}タイル · ${size}MB")
                    .setItems(actions) { _, which ->
                        if (which == 0) {
                            region.setDownloadState(
                                if (downloading) org.maplibre.android.offline.OfflineRegion.STATE_INACTIVE
                                else org.maplibre.android.offline.OfflineRegion.STATE_ACTIVE
                            )
                            listOfflineMaps()
                        } else confirmDeleteOfflineMap(region)
                    }
                    .setNegativeButton("閉じる", null).show()
            }
            override fun onError(error: String?) = Toast.makeText(appContext, error ?: "保存地図を確認できませんでした", Toast.LENGTH_LONG).show()
        })
    }

    private fun confirmDeleteOfflineMap(region: org.maplibre.android.offline.OfflineRegion) {
        AlertDialog.Builder(appContext).setTitle("保存地図を削除")
            .setMessage("${offlineStore.label(region)}と保存データを端末から削除します。")
            .setPositiveButton("削除") { _, _ ->
                offlineStore.delete(region, {
                    Toast.makeText(appContext, "保存地図を削除しました", Toast.LENGTH_SHORT).show()
                    listOfflineMaps()
                }, { error -> Toast.makeText(appContext, error, Toast.LENGTH_LONG).show() })
            }
            .setNegativeButton("キャンセル", null).show()
    }
}

    private class OfflineZoomBoundsOverlay(context: Context) : View(context) {
        private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(36, 255, 153, 0)
            style = Paint.Style.FILL
        }
        private val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(255, 153, 0)
            style = Paint.Style.STROKE
            strokeWidth = 3f * resources.displayMetrics.density
        }
        private var map: MapLibreMap? = null
        private var bounds: LatLngBounds? = null

        fun update(map: MapLibreMap?, bounds: LatLngBounds?) {
            this.map = map
            this.bounds = bounds
            invalidate()
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val currentMap = map ?: return
            val currentBounds = bounds ?: return
            val corners = listOf(
                LatLng(currentBounds.latitudeSouth, currentBounds.longitudeWest),
                LatLng(currentBounds.latitudeNorth, currentBounds.longitudeWest),
                LatLng(currentBounds.latitudeNorth, currentBounds.longitudeEast),
                LatLng(currentBounds.latitudeSouth, currentBounds.longitudeEast)
            )
            val pixels = corners.map { runCatching { currentMap.projection.toScreenLocation(it) }.getOrNull() ?: return }
            val path = Path().apply {
                moveTo(pixels.first().x, pixels.first().y)
                pixels.drop(1).forEach { lineTo(it.x, it.y) }
                close()
            }
            canvas.drawPath(path, fill)
            canvas.drawPath(path, border)
        }
    }

    private class OfflineRegionFrame(context: Context) : View(context) {
        private val density = resources.displayMetrics.density
        private val shade = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(145, 0, 0, 0); style = Paint.Style.FILL }
        private val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(255, 153, 0); style = Paint.Style.STROKE; strokeWidth = 2.5f * density
        }
        init { isClickable = false; isFocusable = false }
        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val insetX = width * 0.08f
            val insetY = height * 0.10f
            val mask = Path().apply {
                fillType = Path.FillType.EVEN_ODD
                addRect(0f, 0f, width.toFloat(), height.toFloat(), Path.Direction.CW)
                addRect(insetX, insetY, width - insetX, height - insetY, Path.Direction.CW)
            }
            canvas.drawPath(mask, shade)
            canvas.drawRect(insetX, insetY, width - insetX, height - insetY, border)
        }
    }
