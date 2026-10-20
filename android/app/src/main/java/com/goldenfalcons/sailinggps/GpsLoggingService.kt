package com.goldenfalcons.sailinggps

import android.Manifest
import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Binder
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import java.io.File

class GpsLoggingService : Service(), LocationListener {

    companion object {
        const val ACTION_START = "com.goldenfalcons.sailinggps.START"
        const val ACTION_STOP = "com.goldenfalcons.sailinggps.STOP"
        const val ACTION_LOCATION = "com.goldenfalcons.sailinggps.LOCATION_UPDATE"
        const val ACTION_STATUS = "com.goldenfalcons.sailinggps.STATUS_UPDATE"
        const val CHANNEL_ID = "gps_logging"
        const val EXTRA_FIX_ELAPSED = "fixElapsed"
        const val EXTRA_LAT = "lat"
        const val EXTRA_LON = "lon"
        const val EXTRA_ALT = "alt"
        const val EXTRA_ACCURACY = "accuracy"
        const val EXTRA_SPEED = "speed"
        const val EXTRA_BEARING = "bearing"
        const val EXTRA_HAS_BEARING = "hasBearing"
        const val EXTRA_COUNT = "count"
        const val EXTRA_RUNNING = "running"
        const val EXTRA_GAP_SECONDS = "gapSeconds"

        fun sessionsDir(context: Context) = File(context.filesDir, "tracks").apply { mkdirs() }
        fun activeSessionFile(context: Context) = File(context.filesDir, "active_track.txt")
        fun trackFile(context: Context): File {
            val active = activeSessionFile(context).takeIf { it.exists() }?.readText()?.trim()
            return if (!active.isNullOrEmpty()) File(sessionsDir(context), active)
            else allTrackFiles(context).lastOrNull() ?: File(context.filesDir, "track_points.csv")
        }
        fun allTrackFiles(context: Context): List<File> {
            val legacy = File(context.filesDir, "track_points.csv")
            val files = sessionsDir(context).listFiles()?.filter { it.extension == "csv" }?.toMutableList() ?: mutableListOf()
            if (legacy.exists() && legacy.length() > 0) files.add(legacy)
            return files.sortedBy { it.name }
        }
    }

    private lateinit var locationManager: LocationManager
    private var wakeLock: PowerManager.WakeLock? = null
    private var count = 0
    private var previous: Location? = null
    private var largestGapSeconds = 0L

    override fun onCreate() {
        super.onCreate()
        debug("Service onCreate")
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        createChannel()
        count = trackFile(this).takeIf { it.exists() }?.readLines()?.size ?: 0
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> stopLogging()
            else -> startLogging()
        }
        return START_STICKY
    }

    private fun startLogging() {
        val active = activeSessionFile(this)
        if (!active.exists()) {
            val name = "track-${java.text.SimpleDateFormat("yyyyMMdd-HHmmss", java.util.Locale.US).format(java.util.Date())}.csv"
            File(sessionsDir(this), name).apply { createNewFile() }
            active.writeText(name)
            count = 0
            largestGapSeconds = 0L
        }
        if (previous == null) runCatching {
            val last = trackFile(this).useLines { it.filter { line -> line.isNotBlank() }.lastOrNull() }
            val fields = last?.split(',') ?: emptyList()
            val timestamp = fields.getOrNull(0)?.toLongOrNull()
            val lat = fields.getOrNull(1)?.toDoubleOrNull()
            val lon = fields.getOrNull(2)?.toDoubleOrNull()
            if (timestamp != null && lat != null && lon != null) previous = Location("recovered").apply { time=timestamp;latitude=lat;longitude=lon }
        }.onFailure { debug("Previous GPS fix recovery failed: ${it.message}") }
        startForeground(1001, notification("GPS記録中 / $count 点"))

        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            debug("ACCESS_FINE_LOCATION not granted")
            stopSelf()
            return
        }

        if (wakeLock?.isHeld != true) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "SailingGpsLogger::GpsWakeLock").apply {
                setReferenceCounted(false)
                acquire()
            }
        }

        try {
            locationManager.removeUpdates(this)
            locationManager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000L, 0f, this)
            broadcastStatus(true)
            debug("GPS logging started")
        } catch (e: Exception) {
            debug("GPS start error: ${e.message}")
        }
    }

    private fun stopLogging() {
        try { locationManager.removeUpdates(this) } catch (_: Exception) {}
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = null
        previous=null
        activeSessionFile(this).delete()
        broadcastStatus(false)
        debug("GPS logging stopped")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onLocationChanged(location: Location) {
        ZoneAlerts.check(this,location)
        previous?.let { old ->
            val gap=((location.time-old.time)/1000L).coerceAtLeast(0L)
            if(gap>30L) { largestGapSeconds=maxOf(largestGapSeconds,gap);debug("GPS gap ${gap}s") }
        }
        var bearing = if (location.hasBearing()) location.bearing.toDouble() else Double.NaN
        if (!bearing.isFinite()) {
            previous?.let { prev ->
                val moved = NavigationUtils.distanceMeters(prev.latitude, prev.longitude, location.latitude, location.longitude)
                if (moved >= 0.05) bearing = prev.bearingTo(location).toDouble()
            }
        }

        previous?.let { previous ->
            val seconds=(location.elapsedRealtimeNanos-previous.elapsedRealtimeNanos)/1e9
            if(seconds in 0.001..30.0 && location.hasAccuracy() && location.accuracy>=0) {
                val counter=getSharedPreferences("tripCounter",Context.MODE_PRIVATE)
                val distance=(counter.getString("distance","0")?.toDoubleOrNull() ?: 0.0)+NavigationUtils.distanceMeters(previous.latitude,previous.longitude,location.latitude,location.longitude)
                val duration=(counter.getString("seconds","0")?.toDoubleOrNull() ?: 0.0)+seconds
                counter.edit().putString("distance",distance.toString()).putString("seconds",duration.toString()).apply()
            }
        }
        appendPoint(location, bearing)
        previous = Location(location)
        count++

        val intent = Intent(ACTION_LOCATION).setPackage(packageName).apply {
            putExtra(EXTRA_FIX_ELAPSED, location.elapsedRealtimeNanos / 1_000_000L)
            putExtra(EXTRA_LAT, location.latitude)
            putExtra(EXTRA_LON, location.longitude)
            putExtra(EXTRA_ALT, if (location.hasAltitude()) location.altitude else Double.NaN)
            putExtra(EXTRA_ACCURACY, if (location.hasAccuracy()) location.accuracy else Float.NaN)
            putExtra(EXTRA_SPEED, if (location.hasSpeed()) location.speed else Float.NaN)
            putExtra(EXTRA_BEARING, bearing)
            putExtra(EXTRA_HAS_BEARING, bearing.isFinite())
            putExtra(EXTRA_COUNT, count)
            putExtra(EXTRA_GAP_SECONDS, largestGapSeconds)
        }
        sendBroadcast(intent)

        val nm = NavigationUtils.MPS_TO_KT * if (location.hasSpeed()) location.speed else 0f
        val n = notification((if(largestGapSeconds>0) "GPS欠落 ${largestGapSeconds}秒 / " else "")+"SOG %.1f kt / %d 点".format(nm, count))
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(1001, n)
    }

    private fun appendPoint(location: Location, bearing: Double) {
        val f = trackFile(this)
        f.appendText(
            listOf(
                location.time,
                location.latitude,
                location.longitude,
                if (location.hasAccuracy()) location.accuracy else "",
                if (location.hasAltitude()) location.altitude else "",
                if (location.hasVerticalAccuracy()) location.verticalAccuracyMeters else "",
                if (location.hasSpeed()) location.speed else "",
                if (bearing.isFinite()) NavigationUtils.normalize360(bearing) else ""
            ).joinToString(",") + "\n"
        )
    }

    private fun broadcastStatus(running: Boolean) {
        sendBroadcast(Intent(ACTION_STATUS).setPackage(packageName).apply {
            putExtra(EXTRA_RUNNING, running)
            putExtra(EXTRA_COUNT, count)
            putExtra(EXTRA_GAP_SECONDS, largestGapSeconds)
        })
    }

    private fun createChannel() {
        val channel = NotificationChannel(CHANNEL_ID, "GPS記録", NotificationManager.IMPORTANCE_LOW).apply {
            description = "画面OFF中もGPS記録を継続します"
        }
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(channel)
    }

    private fun notification(text: String): Notification = NotificationCompat.Builder(this, CHANNEL_ID)
        .setContentTitle("Sailing GPS Logger")
        .setContentText(text)
        .setSmallIcon(android.R.drawable.ic_menu_mylocation)
        .setOngoing(true)
        .build()

    private fun debug(message: String) {
        android.util.Log.d("SailingGpsLogger", "[GpsService] $message")
    }

    override fun onDestroy() {
        try { locationManager.removeUpdates(this) } catch (_: Exception) {}
        if (wakeLock?.isHeld == true) wakeLock?.release()
        debug("Service onDestroy")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
