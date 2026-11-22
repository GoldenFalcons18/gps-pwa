package com.goldenfalcons.sailinggps

import android.content.Context
import android.graphics.Color
import android.graphics.PointF
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
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
        mapView.onCreate(null)
        mapView.getMapAsync { readyMap ->
            map = readyMap
            readyMap.setStyle(OpenFreeMapConfig.styleUrl(styleName)) { style ->
                if (destroyed) return@setStyle
                mapStyle = style
                installLayers(style)
                refreshAll()
                readyMap.cameraPosition = CameraPosition.Builder()
                    .target(LatLng(35.30, 139.48)).zoom(12.0).build()
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
                if (reason == MapLibreMap.OnCameraMoveStartedListener.REASON_API_GESTURE) setFollowing(false)
            }
            readyMap.addOnCameraIdleListener { logWaypointTouchLocations(readyMap) }
        }
        container.addView(mapView, FrameLayout.LayoutParams(-1, -1))
        val controls = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
        }
        listOf("＋" to "地図を拡大", "−" to "地図を縮小", "保存" to "オフライン地図").forEachIndexed { index, entry ->
            controls.addView(Button(context).apply {
                text = entry.first
                contentDescription = entry.second
                isAllCaps = false
                setOnClickListener {
                    when (index) {
                        0 -> zoomBy(1.0)
                        1 -> zoomBy(-1.0)
                        else -> showOfflineMenu()
                    }
                }
            }, LinearLayout.LayoutParams(
                (50 * context.resources.displayMetrics.density).toInt(),
                (48 * context.resources.displayMetrics.density).toInt()
            ))
        }
        container.addView(controls, FrameLayout.LayoutParams(-2, -2, Gravity.END or Gravity.CENTER_VERTICAL))

        val density = context.resources.displayMetrics.density
        val locate = Button(context).apply {
            text = "➤"
            textSize = 27f
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
            (48 * density).toInt(), (48 * density).toInt(),
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
        applyVisibility()
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
        setSource("course", if (current != null && lastHeading != null) {
            val origin = current!!
            val projected = (100..500 step 100).map { d ->
                DisplayNavigation.destination(origin.latitude, origin.longitude, lastHeading!!, d.toDouble())
                    .let { LatLng(it.first, it.second) }
            }
            listOfNotNull(lineFeature(listOf(origin) + projected))
        } else emptyList())
        setSource("course-dots", if (current != null && lastHeading != null) {
            (100..500 step 100).map { d ->
                val p = DisplayNavigation.destination(current!!.latitude, current!!.longitude, lastHeading!!, d.toDouble())
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
        if (this.waypoints.isNotEmpty() && !didInitialWaypointFit) {
            didInitialWaypointFit = true
            showWaypoints()
        }
    }

    private var didInitialWaypointFit = false

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
            val currentPosition = readyMap.cameraPosition
            readyMap.animateCamera(CameraUpdateFactory.newCameraPosition(
                CameraPosition.Builder(currentPosition).zoom((currentPosition.zoom + delta).coerceIn(2.0, 20.0)).build()
            ), 180)
        }
    }

    private fun applyFollow() {
        val readyMap = map ?: return
        val point = current ?: return
        val metrics = mapView.resources.displayMetrics
        val dpi = metrics.xdpi.takeIf { it.isFinite() && it > 50f } ?: metrics.densityDpi.toFloat()
        val zoom = DisplayNavigation.zoom(point.latitude, dpi / 2.54, metersPerCm).coerceIn(2.0, 20.0)
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

    private fun showOfflineMenu() {
        AlertDialog.Builder(appContext)
            .setTitle("オフライン地図")
            .setItems(arrayOf("この範囲を保存", "保存した地図")) { _, which ->
                if (which == 0) askOfflineZoom() else listOfflineMaps()
            }
            .setNegativeButton("閉じる", null)
            .show()
    }

    private fun askOfflineZoom() {
        val bounds = visibleBounds() ?: run {
            Toast.makeText(appContext, "地図の準備ができてからお試しください", Toast.LENGTH_SHORT).show()
            return
        }
        val readyMap = map ?: return
        val max = floor(readyMap.cameraPosition.zoom).toInt().coerceIn(6, 17)
        val candidates = (max downTo (max - 6).coerceAtLeast(0)).mapNotNull { high ->
            val low = (high - 2).coerceAtLeast(0)
            val tiles = OpenFreeMapConfig.estimateTileCount(
                bounds.longitudeWest, bounds.latitudeSouth, bounds.longitudeEast, bounds.latitudeNorth, low, high
            )
            if (tiles <= OpenFreeMapConfig.MAX_TILES_PER_DOWNLOAD) "${low}〜${high}（約${tiles}タイル）" to (low to high) else null
        }
        if (candidates.isEmpty()) {
            AlertDialog.Builder(appContext).setTitle("保存範囲が広すぎます")
                .setMessage("地図を拡大して範囲を小さくしてから、もう一度お試しください。")
                .setPositiveButton("閉じる", null).show()
            return
        }
        AlertDialog.Builder(appContext).setTitle("保存する地図の詳しさ")
            .setItems(candidates.map { it.first }.toTypedArray()) { _, index ->
                askOfflineName(bounds, candidates[index].second.first, candidates[index].second.second)
            }
            .setNegativeButton("キャンセル", null).show()
    }

    private fun askOfflineName(bounds: LatLngBounds, minZoom: Int, maxZoom: Int) {
        val input = AppCompatEditText(appContext).apply { hint = "保存名"; setSingleLine(true) }
        AlertDialog.Builder(appContext).setTitle("保存地図の名前")
            .setView(input)
            .setMessage("1回の保存は最大3,000タイル・50MBです。")
            .setPositiveButton("保存") { _, _ ->
                val name = input.text?.toString()?.trim().orEmpty().ifBlank { "保存地図" }
                offlineStore.createRegion(
                    name, bounds, minZoom.toDouble(), maxZoom.toDouble(),
                    OpenFreeMapConfig.styleUrl(styleName),
                    { _, bytes, tiles, pausedBySize ->
                        if (pausedBySize) Toast.makeText(
                            appContext,
                            "保存を安全のため一時停止しました（約${tiles}タイル / ${bytes / 1024 / 1024}MB）。範囲を小さくして再保存してください。",
                            Toast.LENGTH_LONG
                        ).show()
                        else if (tiles > 0 && tiles % 100L == 0L) log("Offline map / $name / $tiles tiles")
                    },
                    { error -> Toast.makeText(appContext, error, Toast.LENGTH_LONG).show() }
                )
                Toast.makeText(appContext, "地図の保存を開始しました", Toast.LENGTH_SHORT).show()
            }
            .setNegativeButton("キャンセル", null).show()
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
