package com.goldenfalcons.sailinggps

import android.content.Context
import android.graphics.Color
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
    private val selectWaypoint: (Waypoint) -> Unit
) {
    private val map: MapView
    private val boat: Marker
    private val trail: Polyline
    private val points = mutableListOf<GeoPoint>()
    private val waypointMarkers = mutableListOf<Marker>()
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
        container.addView(map, FrameLayout.LayoutParams(-1, -1))
        trail = Polyline(map).apply {
            outlinePaint.color = Color.rgb(255, 170, 0)
            outlinePaint.strokeWidth = 6f
        }
        boat = Marker(map).apply {
            title = "現在地"
            setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
            isEnabled = false
        }
        map.overlays.add(trail)
        map.overlays.add(boat)
        log("Map initialized / OpenStreetMap")
    }

    fun updateLocation(lat: Double, lon: Double, bearing: Double?) {
        val point = GeoPoint(lat, lon)
        current = point
        boat.position = point
        boat.isEnabled = true
        boat.snippet = bearing?.let { "COG %.0f°".format(it) } ?: "COG 未取得"
        if (points.lastOrNull()?.let { it.latitude != lat || it.longitude != lon } != false) {
            points.add(point)
            if (points.size > 10000) points.removeAt(0)
            trail.setPoints(points)
        }
        if (following) map.controller.setCenter(point)
        map.invalidate()
    }

    fun setWaypoints(waypoints: List<Waypoint>, active: Waypoint?) {
        map.overlays.removeAll(waypointMarkers.toSet())
        waypointMarkers.clear()
        waypoints.forEach { wp ->
            waypointMarkers.add(Marker(map).apply {
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

    fun followLocation() {
        following = true
        current?.let { map.controller.animateTo(it) }
        log("Map follow enabled")
    }

    fun clearTrack() {
        loadGeneration++
        points.clear()
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
                    val liveTail = current
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
