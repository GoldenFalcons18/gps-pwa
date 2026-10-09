package com.goldenfalcons.sailinggps

import android.Manifest
import android.content.*
import android.content.pm.PackageManager
import android.graphics.Color
import android.hardware.*
import android.location.Location
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.Surface
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.goldenfalcons.sailinggps.databinding.ActivityMainBinding
import kotlin.math.abs
import kotlin.math.roundToInt

class MainActivity : AppCompatActivity(), SensorEventListener {

    private lateinit var b: ActivityMainBinding
    private lateinit var waypointStore: WaypointStore
    private val waypoints = mutableListOf<Waypoint>()
    private var activeWaypoint: Waypoint? = null

    private lateinit var sensorManager: SensorManager
    private var accel = FloatArray(3)
    private var magnetic = FloatArray(3)
    private var haveAccel = false
    private var haveMagnetic = false
    private var magneticHeading: Double? = null

    private var latestLat: Double? = null
    private var latestLon: Double? = null
    private var latestSpeedMps: Double? = null
    private var latestGpsBearing: Double? = null
    private var pointCount = 0
    private var running = false

    private var navigatorMode = false
    private var mapPanel: NavigationMapPanel? = null
    private val displayPrefs by lazy { getSharedPreferences("display", MODE_PRIVATE) }

    private val logBuffer = ArrayDeque<String>()
    private lateinit var updateChecker: GitHubUpdateChecker

    companion object {
        private const val REQ_LOCATION = 10
        private const val REQ_NOTIFICATIONS = 11
        // One decimal display: values >= 0.05 kt round to 0.1 kt.
        private const val GPS_COURSE_THRESHOLD_KT = 0.05
    }

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                GpsLoggingService.ACTION_LOCATION -> {
                    latestLat = intent.getDoubleExtra(GpsLoggingService.EXTRA_LAT, Double.NaN).takeIf { it.isFinite() }
                    latestLon = intent.getDoubleExtra(GpsLoggingService.EXTRA_LON, Double.NaN).takeIf { it.isFinite() }
                    latestSpeedMps = intent.getFloatExtra(GpsLoggingService.EXTRA_SPEED, Float.NaN).toDouble().takeIf { it.isFinite() }
                    latestGpsBearing = intent.getDoubleExtra(GpsLoggingService.EXTRA_BEARING, Double.NaN).takeIf { it.isFinite() }
                    pointCount = intent.getIntExtra(GpsLoggingService.EXTRA_COUNT, pointCount)
                    updateMap()
                    updateNavigationUi()
                    debug("GPS update lat=${latestLat} lon=${latestLon} speed=${latestSpeedMps} bearing=${latestGpsBearing}")
                }
                GpsLoggingService.ACTION_STATUS -> {
                    running = intent.getBooleanExtra(GpsLoggingService.EXTRA_RUNNING, false)
                    pointCount = intent.getIntExtra(GpsLoggingService.EXTRA_COUNT, pointCount)
                    updateStatusUi()
                    debug("Service status running=$running count=$pointCount")
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        b = ActivityMainBinding.inflate(layoutInflater)
        setContentView(b.root)

        waypointStore = WaypointStore(this)
        waypoints += waypointStore.loadAll()
        val activeId = waypointStore.getActiveId()
        activeWaypoint = waypoints.find { it.id == activeId } ?: waypoints.firstOrNull()
        activeWaypoint?.let { waypointStore.setActiveId(it.id) }

        setupDisplayModes()
        updateChecker = GitHubUpdateChecker(this) { debug(it) }
        b.btnCheckUpdate.text = "更新を確認（${BuildConfig.VERSION_NAME}）"
        b.btnCheckUpdate.setOnClickListener { updateChecker.check(manual = true) }
        setupSpinners()
        setupButtons()
        setupSensors()
        renderWaypointList()
        updateNavigationUi()
        updateStatusUi()
        requestNeededPermissions()

        debug("MainActivity onCreate / waypoints=${waypoints.size}")
    }

    override fun onStart() {
        super.onStart()
        val filter = IntentFilter().apply {
            addAction(GpsLoggingService.ACTION_LOCATION)
            addAction(GpsLoggingService.ACTION_STATUS)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(receiver, filter)
        }
    }

    override fun onStop() {
        runCatching { unregisterReceiver(receiver) }
        super.onStop()
    }

    override fun onResume() {
        super.onResume()
        mapPanel?.resume()
        sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)?.also {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME)
        }
        sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)?.also {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME)
        }
        debug("Compass sensors registered")
        updateChecker.check()
    }

    override fun onPause() {
        mapPanel?.pause()
        sensorManager.unregisterListener(this)
        debug("Compass sensors unregistered")
        super.onPause()
    }

    private fun setupDisplayModes() {
        b.btnSpeedMode.setOnClickListener { setDisplayMode(false) }
        b.btnNavigatorMode.setOnClickListener { setDisplayMode(true) }
        b.btnFollow.setOnClickListener { mapPanel?.followLocation() }
        setDisplayMode(displayPrefs.getBoolean("navigator", false))
    }

    private fun setDisplayMode(navigator: Boolean) {
        navigatorMode = navigator
        if (navigator && mapPanel == null) {
            mapPanel = NavigationMapPanel(this, b.mapContainer) { debug(it) }
            mapPanel?.setWaypoints(waypoints, activeWaypoint)
            updateMap()
            mapPanel?.resume()
        }
        b.speedPanel.visibility = if (navigator) android.view.View.GONE else android.view.View.VISIBLE
        b.navigatorPanel.visibility = if (navigator) android.view.View.VISIBLE else android.view.View.GONE
        b.tvModeTitle.text = if (navigator) "ナビゲーター" else "スピードメーター"
        b.btnSpeedMode.isEnabled = navigator
        b.btnNavigatorMode.isEnabled = !navigator
        displayPrefs.edit().putBoolean("navigator", navigator).apply()
        debug("Display mode=" + if (navigator) "NAVIGATOR" else "SPEEDOMETER")
    }

    private fun updateMap() {
        val lat = latestLat ?: return
        val lon = latestLon ?: return
        mapPanel?.updateLocation(lat, lon, latestGpsBearing)
    }

    override fun onDestroy() {
        if (::updateChecker.isInitialized) updateChecker.close()
        mapPanel?.destroy()
        super.onDestroy()
    }

    private fun setupSpinners() {
        b.spLatDir.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, listOf("N", "S"))
        b.spLonDir.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, listOf("E", "W"))
    }

    private fun setupButtons() {
        b.btnStart.setOnClickListener { startGpsLogging() }
        b.btnStop.setOnClickListener { stopGpsLogging() }
        b.btnExport.setOnClickListener { exportGpx() }
        b.btnClearTrack.setOnClickListener { clearTrack() }
        b.btnAddWp.setOnClickListener { addWaypointFromInputs() }
        b.btnCurrentWp.setOnClickListener { addCurrentLocationWaypoint() }

        b.btnRelativeMode.setOnClickListener {
            b.instrumentView.mode = InstrumentView.Mode.RELATIVE
            updateNavigationUi()
            debug("Instrument mode=RELATIVE")
        }
        b.btnAbsoluteMode.setOnClickListener {
            b.instrumentView.mode = InstrumentView.Mode.ABSOLUTE
            updateNavigationUi()
            debug("Instrument mode=ABSOLUTE")
        }
    }

    private fun setupSensors() {
        sensorManager = getSystemService(SENSOR_SERVICE) as SensorManager
        if (sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD) == null) {
            debug("Magnetic sensor not available")
        }
    }

    private fun requestNeededPermissions() {
        val fineGranted = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (!fineGranted) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                REQ_LOCATION
            )
        }
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIFICATIONS)
        }
    }

    private fun startGpsLogging() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            requestNeededPermissions()
            Toast.makeText(this, "位置情報を許可してください", Toast.LENGTH_LONG).show()
            return
        }
        val intent = Intent(this, GpsLoggingService::class.java).setAction(GpsLoggingService.ACTION_START)
        ContextCompat.startForegroundService(this, intent)
        running = true
        updateStatusUi()
        debug("Start GPS logging requested")
    }

    private fun stopGpsLogging() {
        startService(Intent(this, GpsLoggingService::class.java).setAction(GpsLoggingService.ACTION_STOP))
        running = false
        updateStatusUi()
        debug("Stop GPS logging requested")
    }

    private fun updateStatusUi() {
        b.tvStatus.text = "状態：${if (running) "記録中" else "停止中"} / 保存点数：$pointCount"
        b.tvStatus.setTextColor(if (running) Color.rgb(0, 255, 56) else Color.WHITE)
        b.btnStart.isEnabled = !running
        b.btnStop.isEnabled = running
    }

    private fun navigationHeading(): Pair<Double?, String> {
        val speedKt = latestSpeedMps?.times(NavigationUtils.MPS_TO_KT)
        val useGps = speedKt != null && speedKt >= GPS_COURSE_THRESHOLD_KT && latestGpsBearing != null
        return when {
            useGps -> latestGpsBearing to "GPS対地針路（COG）"
            magneticHeading != null -> magneticHeading to "磁気コンパス（MAG）"
            latestGpsBearing != null -> latestGpsBearing to "GPS（暫定）"
            else -> null to "未取得"
        }
    }

    private fun updateNavigationUi() {
        val speedKt = latestSpeedMps?.times(NavigationUtils.MPS_TO_KT)
        b.tvSog.text = if (speedKt != null) "%.1f kt".format(speedKt) else "-- kt"

        b.tvLargeSpeed.speedKnots = speedKt
        b.tvPosition.text = if (latestLat != null && latestLon != null)
            "${NavigationUtils.formatDm(latestLat!!, true)}   ${NavigationUtils.formatDm(latestLon!!, false)}"
            else "現在地：GPS受信待ち"
        val (heading, source) = navigationHeading()
        b.tvCog.text = heading?.let { "${it.roundToInt()}°" } ?: "--°"
        b.tvHeadingSource.text = "方位ソース：$source"

        val wp = activeWaypoint
        val lat = latestLat
        val lon = latestLon
        if (wp == null || lat == null || lon == null) {
            b.tvDistance.text = "-- NM"
            b.tvDistanceSub.text = "-- m"
            b.tvClock.text = "--時方向"
            b.tvWpName.text = wp?.name ?: "未設定"
            b.tvWpCoords.text = wp?.let { "${NavigationUtils.formatDm(it.lat, true)}\n${NavigationUtils.formatDm(it.lon, false)}" } ?: "--"
            b.instrumentView.update(null, null)
            return
        }

        val distanceM = NavigationUtils.distanceMeters(lat, lon, wp.lat, wp.lon)
        val bearing = NavigationUtils.bearingDegrees(lat, lon, wp.lat, wp.lon)
        b.tvDistance.text = "%.2f NM".format(distanceM * NavigationUtils.M_TO_NM)
        b.tvDistanceSub.text = if (distanceM < 1000) "${distanceM.roundToInt()} m" else "%.2f km".format(distanceM / 1000.0)
        b.tvWpName.text = wp.name
        b.tvWpCoords.text = "${NavigationUtils.formatDm(wp.lat, true)}\n${NavigationUtils.formatDm(wp.lon, false)}"

        if (heading != null) {
            val relative = NavigationUtils.normalize180(bearing - heading)
            b.tvClock.text = NavigationUtils.relativeClock(relative)
            b.instrumentView.update(relative, bearing)
        } else {
            b.tvClock.text = "方位待ち"
            b.instrumentView.update(null, bearing)
        }
    }

    private fun addWaypointFromInputs() {
        val latDeg = b.etLatDeg.text.toString().toIntOrNull()
        val latMin = b.etLatMin.text.toString().toDoubleOrNull()
        val lonDeg = b.etLonDeg.text.toString().toIntOrNull()
        val lonMin = b.etLonMin.text.toString().toDoubleOrNull()
        if (latDeg == null || latMin == null || lonDeg == null || lonMin == null) {
            Toast.makeText(this, "度・分を入力してください", Toast.LENGTH_LONG).show()
            return
        }
        val lat = NavigationUtils.dmToDecimal(latDeg, latMin, b.spLatDir.selectedItem.toString(), true)
        val lon = NavigationUtils.dmToDecimal(lonDeg, lonMin, b.spLonDir.selectedItem.toString(), false)
        if (lat == null || lon == null) {
            Toast.makeText(this, "正しい度分式座標を入力してください", Toast.LENGTH_LONG).show()
            return
        }
        val name = b.etWpName.text.toString().trim().ifEmpty { "Waypoint ${waypoints.size + 1}" }
        val wp = Waypoint(name = name, lat = lat, lon = lon)
        waypoints += wp
        activeWaypoint = wp
        waypointStore.saveAll(waypoints)
        waypointStore.setActiveId(wp.id)
        clearWaypointInputs()
        renderWaypointList()
        updateNavigationUi()
        debug("WP added $name ${NavigationUtils.formatDm(lat, true)} ${NavigationUtils.formatDm(lon, false)}")
    }

    private fun addCurrentLocationWaypoint() {
        val lat = latestLat
        val lon = latestLon
        if (lat == null || lon == null) {
            Toast.makeText(this, "GPS現在地を取得してから実行してください", Toast.LENGTH_LONG).show()
            return
        }
        val name = b.etWpName.text.toString().trim().ifEmpty { "現在地 ${waypoints.size + 1}" }
        val wp = Waypoint(name = name, lat = lat, lon = lon)
        waypoints += wp
        activeWaypoint = wp
        waypointStore.saveAll(waypoints)
        waypointStore.setActiveId(wp.id)
        clearWaypointInputs()
        renderWaypointList()
        updateNavigationUi()
        debug("Current location saved as WP $name")
    }

    private fun clearWaypointInputs() {
        b.etWpName.text?.clear()
        b.etLatDeg.text?.clear()
        b.etLatMin.text?.clear()
        b.etLonDeg.text?.clear()
        b.etLonMin.text?.clear()
        b.spLatDir.setSelection(0)
        b.spLonDir.setSelection(0)
    }

    private fun renderWaypointList() {
        mapPanel?.setWaypoints(waypoints, activeWaypoint)
        b.waypointContainer.removeAllViews()
        waypoints.forEach { wp ->
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(6, 6, 6, 6)
                setBackgroundColor(if (activeWaypoint?.id == wp.id) Color.rgb(35, 25, 0) else Color.rgb(10, 10, 10))
            }
            val text = TextView(this).apply {
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                setTextColor(Color.WHITE)
                textSize = 17f
                text = "${wp.name}\n${NavigationUtils.formatDm(wp.lat, true)} / ${NavigationUtils.formatDm(wp.lon, false)}"
            }
            val select = Button(this).apply {
                this.text = if (activeWaypoint?.id == wp.id) "選択中" else "選択"
                isEnabled = activeWaypoint?.id != wp.id
                setOnClickListener {
                    activeWaypoint = wp
                    waypointStore.setActiveId(wp.id)
                    renderWaypointList()
                    updateNavigationUi()
                    debug("WP selected ${wp.name}")
                }
            }
            val delete = Button(this).apply {
                this.text = "削除"
                setOnClickListener {
                    waypoints.removeAll { it.id == wp.id }
                    if (activeWaypoint?.id == wp.id) activeWaypoint = waypoints.firstOrNull()
                    waypointStore.saveAll(waypoints)
                    waypointStore.setActiveId(activeWaypoint?.id)
                    renderWaypointList()
                    updateNavigationUi()
                    debug("WP deleted ${wp.name}")
                }
            }
            row.addView(text)
            row.addView(select)
            row.addView(delete)
            b.waypointContainer.addView(row)
        }
    }

    private fun exportGpx() {
        try {
            val file = GpxExporter.export(this, waypoints)
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "application/gpx+xml"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(intent, "GPXを保存・共有"))
            debug("GPX exported ${file.absolutePath}")
        } catch (e: Exception) {
            debug("GPX export error ${e.message}")
            Toast.makeText(this, "GPX保存に失敗しました: ${e.message}", Toast.LENGTH_LONG).show()
        }
    }

    private fun clearTrack() {
        if (running) {
            Toast.makeText(this, "記録を停止してから削除してください", Toast.LENGTH_SHORT).show()
            return
        }
        GpsLoggingService.trackFile(this).delete()
        mapPanel?.clearTrack()
        pointCount = 0
        updateStatusUi()
        debug("Track data cleared")
        Toast.makeText(this, "記録データを削除しました", Toast.LENGTH_SHORT).show()
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> {
                accel = event.values.clone()
                haveAccel = true
            }
            Sensor.TYPE_MAGNETIC_FIELD -> {
                magnetic = event.values.clone()
                haveMagnetic = true
            }
        }
        if (!haveAccel || !haveMagnetic) return

        val rotation = FloatArray(9)
        val inclination = FloatArray(9)
        if (!SensorManager.getRotationMatrix(rotation, inclination, accel, magnetic)) return

        val remapped = FloatArray(9)
        @Suppress("DEPRECATION")
        val displayRotation = windowManager.defaultDisplay.rotation
        val rotationConstant = when (displayRotation) {
            Surface.ROTATION_90 -> SensorManager.AXIS_Y to SensorManager.AXIS_MINUS_X
            Surface.ROTATION_180 -> SensorManager.AXIS_MINUS_X to SensorManager.AXIS_MINUS_Y
            Surface.ROTATION_270 -> SensorManager.AXIS_MINUS_Y to SensorManager.AXIS_X
            else -> SensorManager.AXIS_X to SensorManager.AXIS_Y
        }
        SensorManager.remapCoordinateSystem(rotation, rotationConstant.first, rotationConstant.second, remapped)
        val orientation = FloatArray(3)
        SensorManager.getOrientation(remapped, orientation)
        val raw = NavigationUtils.normalize360(Math.toDegrees(orientation[0].toDouble()))

        magneticHeading = magneticHeading?.let { prev ->
            val delta = NavigationUtils.normalize180(raw - prev)
            NavigationUtils.normalize360(prev + delta * 0.35)
        } ?: raw

        updateNavigationUi()
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        debug("Sensor accuracy type=${sensor?.type} accuracy=$accuracy")
    }

    private fun debug(message: String) {
        val line = "[${java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.JAPAN).format(java.util.Date())}] $message"
        Log.d("SailingGpsLogger", line)
        logBuffer.addLast(line)
        while (logBuffer.size > 18) logBuffer.removeFirst()
        b.tvLog.text = logBuffer.joinToString("\n")
    }
}
