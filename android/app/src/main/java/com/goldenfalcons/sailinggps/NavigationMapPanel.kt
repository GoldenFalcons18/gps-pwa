package com.goldenfalcons.sailinggps

import android.content.Context
import android.graphics.Color
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.drawable.BitmapDrawable
import android.view.MotionEvent
import android.widget.FrameLayout
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.GeoPoint
import org.osmdroid.util.BoundingBox
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.Polyline
import java.io.File

/** Uses the logger's fixes; never starts a second GPS provider. */
class NavigationMapPanel(
    context: Context,
    container: FrameLayout,
    private val log: (String) -> Unit,
    private val createWaypoint: (Double, Double) -> Unit,
    private val selectWaypoint: (Waypoint) -> Unit
) {
    private val map: MapView
    private val boat: Marker
    private val trail: Polyline
    private val points = mutableListOf<GeoPoint>()
    private val waypointMarkers = mutableListOf<Marker>()
    private val targetLine = Polyline()
    private var target: GeoPoint? = null
    private val course = Polyline()
    private val courseDots = mutableListOf<Marker>()
    private var lastHeading: Double? = null
    private var lastRecorded: GeoPoint? = null
    private var current: GeoPoint? = null
    private var following = true
    private var destroyed = false
    private var loadGeneration = 0

    init {
        Configuration.getInstance().apply {
            userAgentValue = context.packageName
            osmdroidBasePath = File(context.cacheDir, "maps").apply { mkdirs() }
            osmdroidTileCache = File(osmdroidBasePath, "tiles").apply { mkdirs() }
        }
        map = MapView(context).apply {
            setTileSource(TileSourceFactory.MAPNIK)
            setMultiTouchControls(true)
            controller.setZoom(15.0)
            // No invented current location before the first GPS fix.
            controller.setCenter(GeoPoint(35.30, 139.48))
            setOnTouchListener { _, event ->
                container.parent.requestDisallowInterceptTouchEvent(
                    event.actionMasked != MotionEvent.ACTION_UP && event.actionMasked != MotionEvent.ACTION_CANCEL
                )
                if (event.actionMasked == MotionEvent.ACTION_MOVE) following = false
                false
            }
        }
        map.overlays.add(org.osmdroid.views.overlay.MapEventsOverlay(object : org.osmdroid.events.MapEventsReceiver {
            override fun singleTapConfirmedHelper(p: GeoPoint) = false
            override fun longPressHelper(p: GeoPoint): Boolean {
                following = false
                createWaypoint(p.latitude, p.longitude)
                return true
            }
        }))
        container.addView(map, FrameLayout.LayoutParams(-1, -1))
        trail = Polyline(map).apply {
            outlinePaint.color = Color.rgb(255, 170, 0)
            outlinePaint.strokeWidth = 6f
        }
        boat = Marker(map).apply {
            title = "現在地"
            val density = map.resources.displayMetrics.density
            val size = (28 * density).toInt()
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val arrow = android.graphics.Path().apply {
                moveTo(size / 2f, 2f * density)
                lineTo(size - 3f * density, size - 3f * density)
                lineTo(size / 2f, size * 0.7f)
                lineTo(3f * density, size - 3f * density)
                close()
            }
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; style = Paint.Style.STROKE; strokeWidth = 3f * density }
            canvas.drawPath(arrow, paint)
            paint.style = Paint.Style.FILL; paint.color = Color.rgb(10, 25, 45)
            canvas.drawPath(arrow, paint)
            icon = BitmapDrawable(map.resources, bitmap)
            setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
            isEnabled = false
        }
        map.overlays.add(trail)
        course.outlinePaint.color = Color.BLACK
        course.outlinePaint.strokeWidth = 2f * map.resources.displayMetrics.density
        targetLine.outlinePaint.color = Color.GREEN
        targetLine.outlinePaint.strokeWidth = 3f * map.resources.displayMetrics.density
        map.overlays.add(targetLine)
        map.overlays.add(course)
        for (distance in 100..500 step 100) {
            val density = map.resources.displayMetrics.density
            val size = (14 * density).toInt()
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            paint.color = Color.WHITE
            canvas.drawCircle(size / 2f, size / 2f, 6f * density, paint)
            paint.color = Color.BLACK
            canvas.drawCircle(size / 2f, size / 2f, 4f * density, paint)
            courseDots.add(Marker(map).apply {
                icon = BitmapDrawable(map.resources, bitmap)
                title = "${distance} m"
                setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
                isEnabled = false
            })
        }
        map.overlays.addAll(courseDots)
        map.overlays.add(boat)
        log("Map initialized / OpenStreetMap")
    }

    fun updateLocation(lat: Double, lon: Double, bearing: Double?, recordTrack: Boolean = true) {
        val point = GeoPoint(lat, lon)
        current = point
        lastHeading = bearing
        boat.position = point
        boat.isEnabled = true
        boat.snippet = bearing?.let { "COG %.0f°".format(it) } ?: "COG 未取得"
        if (recordTrack && points.lastOrNull()?.let { it.latitude != lat || it.longitude != lon } != false) {
            lastRecorded = point
            points.add(point)
            if (points.size > 10000) points.removeAt(0)
            trail.setPoints(points)
        }
        if (bearing != null) {
            val projected = (100..500 step 100).map { distance ->
                DisplayNavigation.destination(lat, lon, bearing, distance.toDouble()).let { GeoPoint(it.first, it.second) }
            }
            course.setPoints(listOf(point) + projected)
            courseDots.forEachIndexed { index, marker -> marker.position = projected[index]; marker.isEnabled = true }
        } else { course.setPoints(emptyList()); courseDots.forEach { it.isEnabled = false } }
        updateTargetLine()
        if (following) applyFollow()
        map.invalidate()
    }

    private fun updateTargetLine() {
        targetLine.setPoints(if (current != null && target != null) listOf(current!!, target!!) else emptyList())
    }

    fun setWaypoints(waypoints: List<Waypoint>, active: Waypoint?) {
        target = active?.let { GeoPoint(it.lat, it.lon) }
        updateTargetLine()
        map.overlays.removeAll(waypointMarkers.toSet())
        waypointMarkers.clear()
        waypoints.forEach { wp ->
            waypointMarkers.add(Marker(map).apply {
                icon = waypointIcon(wp.name, wp.id == active?.id)
                position = GeoPoint(wp.lat, wp.lon)
                title = (if (wp.id == active?.id) "★ " else "") + wp.name
                snippet = "${NavigationUtils.formatDm(wp.lat, true)} / ${NavigationUtils.formatDm(wp.lon, false)}"
                setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
                setOnMarkerClickListener { _, _ ->
                    selectWaypoint(wp)
                    waypointMarkers.firstOrNull { it.position == GeoPoint(wp.lat, wp.lon) }?.showInfoWindow()
                    true
                }
                alpha = if (wp.id == active?.id) 1f else 0.6f
            })
        }
        map.overlays.addAll(waypointMarkers)
        map.invalidate()
    }

    private fun waypointIcon(name: String, active: Boolean): BitmapDrawable {
        val density = map.resources.displayMetrics.density
        val label = name.take(24)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 12f * density }
        val width = (paint.measureText(label) + 16f * density).toInt().coerceAtLeast((60 * density).toInt())
        val bitmap = Bitmap.createBitmap(width, (44 * density).toInt(), Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        paint.color = Color.rgb(15, 15, 15)
        canvas.drawRoundRect(0f, 0f, width.toFloat(), 26f * density, 4f * density, 4f * density, paint)
        paint.color = if (active) Color.rgb(255, 170, 0) else Color.WHITE
        paint.textAlign = Paint.Align.CENTER
        canvas.drawText(label, width / 2f, 18f * density, paint)
        paint.color = if (active) Color.rgb(255, 170, 0) else Color.rgb(30, 140, 255)
        canvas.drawCircle(width / 2f, 36f * density, 7f * density, paint)
        return BitmapDrawable(map.resources, bitmap)
    }

    fun showWaypoints() {
        val positions = waypointMarkers.map { it.position }
        if (positions.isEmpty()) return
        following = false
        val visible = positions + listOfNotNull(current)
        map.post {
            if (destroyed) return@post
            if (visible.distinct().size == 1) {
                map.controller.setZoom(15.0)
                map.controller.animateTo(visible.first())
            } else {
                map.zoomToBoundingBox(BoundingBox.fromGeoPoints(visible), false, (32 * map.resources.displayMetrics.density).toInt(), 17.0, null)
            }
        }
        log("Map show waypoints / ${positions.size}")
    }

    private fun applyFollow() {
        val point = current ?: return
        val metrics = map.resources.displayMetrics
        val dpi = metrics.xdpi.takeIf { it.isFinite() && it > 50f } ?: metrics.densityDpi.toFloat()
        map.controller.setZoom(DisplayNavigation.zoom(point.latitude, dpi / 2.54).coerceIn(map.minZoomLevel, map.maxZoomLevel))
        map.mapOrientation = -(lastHeading ?: 0.0).toFloat()
        val center = lastHeading?.let { heading ->
            DisplayNavigation.destination(point.latitude, point.longitude, heading, 250.0).let { GeoPoint(it.first, it.second) }
        } ?: point
        map.controller.setCenter(center)
    }

    fun followLocation() {
        following = true
        applyFollow()
        log("Map follow enabled")
    }

    fun clearTrack() {
        loadGeneration++
        points.clear()
        lastRecorded = null
        trail.setPoints(points)
        map.invalidate()
    }

    // Restore points recorded while the screen was off, without blocking the UI.
    fun resume() {
        map.onResume()
        val generation = ++loadGeneration
        val file = GpsLoggingService.trackFile(map.context)
        Thread {
            val restored = ArrayDeque<GeoPoint>()
            runCatching {
                if (file.exists()) file.useLines { lines ->
                    lines.forEach { line ->
                        val fields = line.split(',')
                        val lat = fields.getOrNull(1)?.toDoubleOrNull()
                        val lon = fields.getOrNull(2)?.toDoubleOrNull()
                        if (lat != null && lon != null && lat in -90.0..90.0 && lon in -180.0..180.0) {
                            restored.addLast(GeoPoint(lat, lon))
                            if (restored.size > 10000) restored.removeFirst()
                        }
                    }
                }
            }.onFailure { error -> map.post { if (!destroyed) log("Map track read error: ${error.message}") } }
            map.post {
                if (!destroyed && generation == loadGeneration) {
                    val liveTail = lastRecorded
                    points.clear()
                    points.addAll(restored)
                    if (liveTail != null && points.lastOrNull() != liveTail) points.add(liveTail)
                    trail.setPoints(points)
                    map.invalidate()
                    log("Map track restored / ${points.size} points")
                }
            }
        }.start()
    }

    fun pause() { map.onPause() }
    fun destroy() {
        destroyed = true
        loadGeneration++
        map.onDetach()
    }
}
