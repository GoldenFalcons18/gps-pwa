package com.goldenfalcons.sailinggps

import android.content.Context
import okhttp3.Dispatcher
import okhttp3.OkHttpClient
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.geometry.LatLngBounds
import org.maplibre.android.http.HttpIdentifier
import org.maplibre.android.module.http.HttpRequestUtil
import org.maplibre.android.offline.OfflineManager
import org.maplibre.android.offline.OfflineRegion
import org.maplibre.android.offline.OfflineTilePyramidRegionDefinition
import org.json.JSONObject
import kotlin.math.floor
import kotlin.math.pow

/** OpenFreeMap allows no-key online use and bounded offline downloads. */
object OpenFreeMapConfig {
    const val STYLE_URL = "https://tiles.openfreemap.org/styles/liberty"
    const val MAX_TILES_PER_DOWNLOAD = 3000L
    const val MAX_BYTES_PER_DOWNLOAD = 50L * 1024L * 1024L
    // Keep 20% headroom for resources already in flight when pausing a download.
    const val PAUSE_AT_BYTES = 40L * 1024L * 1024L
    const val MAX_PARALLEL_REQUESTS = 4

    @Volatile private var configured = false

    @Synchronized
    fun configure(context: Context) {
        if (configured) return
        // MapLibre's default User-Agent includes the app package, version, and Android version.
        // Limit both the dispatcher and per-host concurrency to OpenFreeMap's allowed four.
        val dispatcher = Dispatcher().apply {
            maxRequests = MAX_PARALLEL_REQUESTS
            maxRequestsPerHost = MAX_PARALLEL_REQUESTS
        }
        HttpRequestUtil.setOkHttpClient(OkHttpClient.Builder().dispatcher(dispatcher).build())
        OfflineManager.getInstance(context).setOfflineMapboxTileCountLimit(MAX_TILES_PER_DOWNLOAD)
        configured = true
    }

    fun estimateTileCount(
        west: Double,
        south: Double,
        east: Double,
        north: Double,
        minZoom: Int,
        maxZoom: Int
    ): Long {
        require(west.isFinite() && east.isFinite() && south.isFinite() && north.isFinite())
        require(west in -180.0..180.0 && east in -180.0..180.0)
        require(south in -85.05112878..85.05112878 && north in -85.05112878..85.05112878 && south <= north)
        require(minZoom in 0..22 && maxZoom in minZoom..22)
        var total = 0L
        for (zoom in minZoom..maxZoom) {
            val n = 2.0.pow(zoom)
            val x0 = floor((west + 180.0) / 360.0 * n).toLong().coerceIn(0, n.toLong() - 1)
            val x1 = floor((east + 180.0) / 360.0 * n).toLong().coerceIn(0, n.toLong() - 1)
            fun tileY(latitude: Double): Long {
                val lat = latitude.coerceIn(-85.05112878, 85.05112878)
                val rad = Math.toRadians(lat)
                return floor((1.0 - kotlin.math.asinh(kotlin.math.tan(rad)) / Math.PI) / 2.0 * n)
                    .toLong().coerceIn(0, n.toLong() - 1)
            }
            val yNorth = tileY(north)
            val ySouth = tileY(south)
            val xCount = if (east >= west) x1 - x0 + 1 else (n.toLong() - x0) + x1 + 1
            total += xCount * (ySouth - yNorth + 1)
            if (total > MAX_TILES_PER_DOWNLOAD) return total
        }
        return total
    }

    fun styleUrl(style: String): String = when (style) {
        "bright", "positron", "liberty", "dark" -> "https://tiles.openfreemap.org/styles/$style"
        else -> STYLE_URL
    }
}

class OpenFreeMapOfflineStore(context: Context) {
    private val appContext = context.applicationContext
    private val manager: OfflineManager

    init {
        OpenFreeMapConfig.configure(appContext)
        manager = OfflineManager.getInstance(appContext)
    }

    fun createRegion(
        name: String,
        bounds: LatLngBounds,
        minZoom: Double,
        maxZoom: Double,
        styleUrl: String,
        onProgress: (OfflineRegion, Long, Long, Boolean) -> Unit,
        onError: (String) -> Unit
    ) {
        require(name.isNotBlank())
        require(minZoom >= 0.0 && maxZoom >= minZoom)
        val definition = OfflineTilePyramidRegionDefinition(
            styleUrl,
            bounds,
            minZoom,
            maxZoom,
            appContext.resources.displayMetrics.density,
            true
        )
        val metadata = JSONObject()
            .put("name", name)
            .put("style", styleUrl)
            .put("provider", "OpenFreeMap")
            .toString().toByteArray(Charsets.UTF_8)
        manager.createOfflineRegion(definition, metadata, object : OfflineManager.CreateOfflineRegionCallback {
            override fun onCreate(region: OfflineRegion) {
                region.setObserver(object : OfflineRegion.OfflineRegionObserver {
                    override fun onStatusChanged(status: org.maplibre.android.offline.OfflineRegionStatus) {
                        val size = status.completedResourceSize
                        if (size >= OpenFreeMapConfig.PAUSE_AT_BYTES &&
                            status.downloadState == OfflineRegion.STATE_ACTIVE) {
                            region.setDownloadState(OfflineRegion.STATE_INACTIVE)
                            onProgress(region, size, status.completedTileCount, true)
                        } else {
                            onProgress(region, size, status.completedTileCount, status.isComplete)
                        }
                    }

                    override fun onError(error: org.maplibre.android.offline.OfflineRegionError) {
                        onError(error.message ?: "地図の保存に失敗しました")
                    }

                    override fun mapboxTileCountLimitExceeded(limit: Long) {
                        region.setDownloadState(OfflineRegion.STATE_INACTIVE)
                        onProgress(region, OpenFreeMapConfig.PAUSE_AT_BYTES, limit, true)
                    }
                })
                region.setDownloadState(OfflineRegion.STATE_ACTIVE)
            }

            override fun onError(error: String) = onError(error)
        })
    }

    fun list(callback: (List<OfflineRegion>) -> Unit, onError: (String) -> Unit) {
        manager.listOfflineRegions(object : OfflineManager.ListOfflineRegionsCallback {
            override fun onList(regions: Array<OfflineRegion>) = callback(regions.toList())
            override fun onError(error: String) = onError(error)
        })
    }

    fun delete(region: OfflineRegion, onDone: () -> Unit, onError: (String) -> Unit) {
        region.delete(object : OfflineRegion.OfflineRegionDeleteCallback {
            override fun onDelete() = onDone()
            override fun onError(error: String) = onError(error)
        })
    }

    fun label(region: OfflineRegion): String =
        runCatching { JSONObject(String(region.metadata, Charsets.UTF_8)).optString("name", "保存地図") }
            .getOrDefault("保存地図")
}
