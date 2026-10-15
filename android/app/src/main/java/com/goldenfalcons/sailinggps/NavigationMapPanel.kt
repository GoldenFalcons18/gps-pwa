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
    private val editWaypoint: (Waypoint) -> Unit
) {
    private val map: MapView
    private val boat: Marker
    private val trail: Polyline
    private val points = mutableListOf<GeoPoint>()
    private val waypointMarkers = mutableListOf<Marker>()
    private var waypointData = emptyList<Waypoint>()
    private val targetLine = Polyline()
    private var target: GeoPoint? = null
    private val course = Polyline()
    private val courseDots = mutableListOf<Marker>()
    private var lastHeading: Double? = null
    private var lastRecorded: GeoPoint? = null
    private var current: GeoPoint? = null
    private var following = true
    private var destroyed = false
    private var paused = false
    private var shownHeading: Double? = null
    private var frameQueued = false
    private var frameTime = 0L
    private var lastFollowLogAt = 0L
    private val followFrame = object : Runnable {
        override fun run() {
            frameQueued = false
            if (destroyed || paused || !following) return
            val targetHeading = lastHeading ?: return
            val now = android.os.SystemClock.uptimeMillis()
            val dt = if (frameTime == 0L) 0.016 else ((now - frameTime) / 1000.0).coerceIn(0.0, 0.05)
            frameTime = now
            val previous = shownHeading ?: targetHeading
            val delta = NavigationUtils.normalize180(targetHeading - previous)
            shownHeading = previous + delta * (1 - kotlin.math.exp(-dt / 0.12))
            applyFollow()
            map.invalidate()
            if (kotlin.math.abs(delta) > 0.05) queueFollowFrame()
        }
    }

    private fun queueFollowFrame() {
        if (!frameQueued && !destroyed && !paused && following && lastHeading != null) {
            frameQueued = true
            map.postOnAnimation(followFrame)
        }
    }
    private var touchX = 0f
    private var touchY = 0f
    private var longPressTriggered = false
    private fun fireLongPress() {
        following = false
        longPressTriggered = true
        val local = map.projection.unrotateAndScalePoint(touchX.toInt(), touchY.toInt(), null)
        val event = MotionEvent.obtain(0, 0, MotionEvent.ACTION_DOWN, local.x.toFloat(), local.y.toFloat(), 0)
        val marker = waypointMarkers.asReversed().firstOrNull { it.hitTest(event, map) }
        event.recycle()
        val index = waypointMarkers.indexOf(marker)
        if (index >= 0) editWaypoint(waypointData[index])
        else {
            val point = map.projection.fromPixels(local.x, local.y)
            createWaypoint(point.latitude, point.longitude)
        }
    }
    private val longPress = Runnable { fireLongPress() }
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
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        touchX = event.x; touchY = event.y
                        longPressTriggered = false
                        postDelayed(longPress, android.view.ViewConfiguration.getLongPressTimeout().toLong())
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val slop = android.view.ViewConfiguration.get(context).scaledTouchSlop
                        if (kotlin.math.hypot(event.x - touchX, event.y - touchY) > slop) {
                            removeCallbacks(longPress)
                            following = false
                        }
                    }
                    MotionEvent.ACTION_POINTER_DOWN, MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> removeCallbacks(longPress)
                }
                longPressTriggered
            }
        }
        map.overlays.add(org.osmdroid.views.overlay.MapEventsOverlay(object : org.osmdroid.events.MapEventsReceiver {
            override fun singleTapConfirmedHelper(p: GeoPoint) = false
            override fun longPressHelper(p: GeoPoint): Boolean {
                // The touch listener owns long press, including over navigation overlays.
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
        boat.snippet = bearing?.let { "表示方位（真北） %.0f°".format(it) } ?: "方位 未取得"
        // Flat markers rotate with the map; osmdroid rotations are counter-clockwise.
        boat.setFlat(true)
        boat.rotation = -(bearing ?: 0.0).toFloat()
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
        if (following) {
            if (shownHeading == null) shownHeading = bearing
            applyFollow()
            queueFollowFrame()
        }
        map.invalidate()
    }

    private fun updateTargetLine() {
        targetLine.setPoints(if (current != null && target != null) listOf(current!!, target!!) else emptyList())
    }

    fun setWaypoints(waypoints: List<Waypoint>, active: Waypoint?) {
        waypointData = waypoints.toList()
        target = active?.let { GeoPoint(it.lat, it.lon) }
        updateTargetLine()
        map.overlays.removeAll(waypointMarkers.toSet())
        waypointMarkers.clear()
        waypoints.forEach { wp ->
            waypointMarkers.add(Marker(map).apply {
                icon = waypointIcon(wp.name, wp.id == active?.id, wp.mark, wp.color)
                position = GeoPoint(wp.lat, wp.lon)
                title = (if (wp.id == active?.id) "★ " else "") + wp.name
                snippet = "${NavigationUtils.formatDm(wp.lat, true)} / ${NavigationUtils.formatDm(wp.lon, false)}"
                setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
                setOnMarkerClickListener { _, _ -> true }
                setInfoWindow(null)
                alpha = if (wp.id == active?.id) 1f else 0.6f
            })
        }
        map.overlays.addAll(waypointMarkers)
        map.invalidate()
        if (BuildConfig.DEBUG) map.post {
            if (!destroyed) waypointMarkers.forEachIndexed { index, marker ->
                val point = map.projection.toPixels(marker.position, null)
                val screen = map.projection.rotateAndScalePoint(point.x, point.y, null)
                val origin = IntArray(2); map.getLocationOnScreen(origin)
                android.util.Log.d("SailingUiBounds", "WP_TOUCH id=${waypointData[index].id} x=${origin[0]+screen.x} y=${origin[1]+screen.y-(14*map.resources.displayMetrics.density).toInt()}")
            }
        }
    }

    private fun waypointIcon(name: String, active: Boolean, mark: String, color: String): BitmapDrawable {
        val density = map.resources.displayMetrics.density
        val label = name.take(24)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 12f * density }
        val width = (paint.measureText(label) + 16f * density).toInt().coerceAtLeast((60 * density).toInt())
        val bitmap = Bitmap.createBitmap(width, (54 * density).toInt(), Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        paint.color = Color.rgb(15, 15, 15)
        canvas.drawRoundRect(0f, 0f, width.toFloat(), 26f * density, 4f * density, 4f * density, paint)
        paint.color = if (active) Color.rgb(255, 170, 0) else Color.WHITE
        paint.textAlign = Paint.Align.CENTER
        canvas.drawText(label, width / 2f, 18f * density, paint)
        val selectedColor = runCatching { Color.parseColor(color) }.getOrDefault(Color.rgb(255, 170, 0))
        paint.color = selectedColor
        canvas.drawCircle(width / 2f, 40f * density, 12f * density, paint)
        paint.color = if (Color.red(selectedColor) * 0.299 + Color.green(selectedColor) * 0.587 + Color.blue(selectedColor) * 0.114 > 160) Color.BLACK else Color.WHITE
        paint.textSize = 17f * density
        val glyph = mark.ifEmpty { "●" }
        val available = 23f * density
        if (paint.measureText(glyph) > available) paint.textSize *= available / paint.measureText(glyph)
        if (!MarineMarks.draw(canvas, glyph, width / 2f, 40f * density, 21f * density, paint.color)) {
            canvas.drawText(glyph, width / 2f, 40f * density - (paint.ascent() + paint.descent()) / 2, paint)
        }
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
        val zoom = DisplayNavigation.zoom(point.latitude, dpi / 2.54).coerceIn(map.minZoomLevel, map.maxZoomLevel)
        if (kotlin.math.abs(map.zoomLevelDouble - zoom) > 0.005) map.controller.setZoom(zoom)
        map.mapOrientation = -(shownHeading ?: lastHeading ?: 0.0).toFloat()
        val now = android.os.SystemClock.uptimeMillis()
        if (now - lastFollowLogAt >= 500) {
            lastFollowLogAt = now
            log("Map follow heading=$lastHeading shown=$shownHeading")
        }
        // Keep the boat at the rotation center, matching the reference recording.
        if (map.mapCenter.latitude != point.latitude || map.mapCenter.longitude != point.longitude) map.controller.setCenter(point)
    }

    fun followLocation() {
        following = true
        applyFollow()
        queueFollowFrame()
        log("Map follow enabled / heading-up / centered")
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
        paused = false
        frameTime = 0L
        queueFollowFrame()
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

    fun pause() {
        paused = true
        map.removeCallbacks(followFrame)
        frameQueued = false
        frameTime = 0L
        map.onPause()
    }
    fun destroy() {
        destroyed = true
        map.removeCallbacks(followFrame)
        loadGeneration++
        map.onDetach()
    }
}
