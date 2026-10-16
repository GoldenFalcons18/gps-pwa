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
    private var library = MapLibrary()
    private var pendingExport: ByteArray? = null

    private lateinit var sensorManager: SensorManager
    private var accel = FloatArray(3)
    private var magnetic = FloatArray(3)
    private var haveAccel = false
    private var haveMagnetic = false
    private var magneticHeading: Double? = null

    private var previewListener: android.location.LocationListener? = null
    private var foregroundActive = false
    private var metricUnits: Boolean
        get() = displayPrefs.getBoolean("metricUnits", false)
        set(value) { displayPrefs.edit().putBoolean("metricUnits", value).apply() }
    private var preferGpsHeading: Boolean
        get() = displayPrefs.getBoolean("preferGpsHeading", false)
        set(value) { displayPrefs.edit().putBoolean("preferGpsHeading", value).apply() }
    private var latestHeadingLogAt = 0L
    private var latestFixAt = 0L
    private val uiHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private var quickLocationListener: android.location.LocationListener? = null
    private val clockTick = object : Runnable {
        override fun run() {
            b.tvTime.text = "時間\n" + java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date())
            uiHandler.postDelayed(this, 1000)
        }
    }
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

    private val exportWaypointsDocument = registerForActivityResult(androidx.activity.result.contract.ActivityResultContracts.CreateDocument("application/octet-stream")) { uri ->
        if (uri != null) runCatching {
            val data = pendingExport ?: WaypointArchive.encode(waypoints)
            contentResolver.openOutputStream(uri, "wt")?.use { it.write(data) } ?: error("保存先を開けません")
            debug("Waypoints exported count=${waypoints.size}")
            Toast.makeText(this, "ウェイポイントを保存しました", Toast.LENGTH_LONG).show()
        }.onFailure { transferError(it) }
    }
    private val importWaypointsDocument = registerForActivityResult(androidx.activity.result.contract.ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) Thread {
            val result = runCatching {
                val data = contentResolver.openInputStream(uri)?.use { input ->
                    val bytes = java.io.ByteArrayOutputStream(); val buffer = ByteArray(8192)
                    while (true) { val count = input.read(buffer); if (count < 0) break
                        require(bytes.size() + count <= KmlArchive.MAX_BYTES) { "32MBを超えています" }; bytes.write(buffer, 0, count) }
                    bytes.toByteArray()
                } ?: error("ファイルを開けません")
                if(data.toString(Charsets.UTF_8).trimStart().startsWith("{")) KmlArchive.Import(WaypointArchive.decode(data),emptyList()) else KmlArchive.decode(data)
            }
            runOnUiThread { if (!isFinishing && !isDestroyed) result.onSuccess(::confirmWaypointImport).onFailure(::transferError) }
        }.start()
    }
    private fun transferError(error: Throwable) {
        debug("Waypoint transfer failed: ${error.message}")
        androidx.appcompat.app.AlertDialog.Builder(this).setTitle("ウェイポイントの入出力").setMessage("処理できませんでした。既存の地点は削除しません。\n${error.message}").setPositiveButton("OK", null).show()
    }
    private fun confirmWaypointImport(archive: KmlArchive.Import) {
        val incoming = archive.waypoints
        runCatching {
            val preview = WaypointArchive.merge(waypoints, incoming)
            androidx.appcompat.app.AlertDialog.Builder(this).setTitle("ウェイポイントを取り込みますか？")
                .setMessage("追加 ${preview.added}件・重複 ${preview.skipped}件・図形 ${archive.features.size}件\n${archive.warnings.joinToString("\n")}\n既存の地点と選択中の目標は保持します。")
                .setNegativeButton("キャンセル", null).setPositiveButton("追加する") { _, _ ->
                    runCatching {
                        val merged = WaypointArchive.merge(waypoints, incoming)
                        val mapping = incoming.associate { w -> w.id to (merged.items.firstOrNull { WaypointArchive.sameContent(it,w) }?.id ?: w.id) }
                        val imported = archive.features.map { f -> f.copy(waypointIds=f.waypointIds.map { mapping[it] ?: it }) }
                        val features=library.features.toMutableList()
                        for(f in imported) { if(features.any { it.name==f.name && it.kind==f.kind && it.points(merged.items)==f.points(merged.items) && it.radius==f.radius && it.group==f.group }) continue
                            features += if(features.any { it.id==f.id }) f.copy(id=java.util.UUID.randomUUID().toString()) else f }
                        val updated=library.copy(groups=(library.groups+incoming.map{it.group}+imported.map{it.group}).filter{it.isNotBlank()}.distinct(),features=features)
                        waypointStore.saveLibrary(merged.items,updated); library=updated
                        waypoints.clear(); waypoints.addAll(merged.items); renderWaypointList(); updateNavigationUi()
                        debug("Waypoints imported added=${merged.added} skipped=${merged.skipped}")
                        Toast.makeText(this, "追加 ${merged.added}件・重複 ${merged.skipped}件", Toast.LENGTH_LONG).show()
                    }.onFailure(::transferError)
                }.show()
        }.onFailure(::transferError)
    }

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
                    latestFixAt = intent.getLongExtra(GpsLoggingService.EXTRA_FIX_ELAPSED, 0L)
                    latestLat = intent.getDoubleExtra(GpsLoggingService.EXTRA_LAT, Double.NaN).takeIf { it.isFinite() }
                    latestLon = intent.getDoubleExtra(GpsLoggingService.EXTRA_LON, Double.NaN).takeIf { it.isFinite() }
                    latestSpeedMps = intent.getFloatExtra(GpsLoggingService.EXTRA_SPEED, Float.NaN).toDouble().takeIf { it.isFinite() }
                    latestGpsBearing = intent.getDoubleExtra(GpsLoggingService.EXTRA_BEARING, Double.NaN).takeIf { it.isFinite() }
                    pointCount = intent.getIntExtra(GpsLoggingService.EXTRA_COUNT, pointCount)
                    b.tvGpsInfo.text = "GPS\n精度 ±%.0f m\n高度 %.0f m".format(intent.getFloatExtra(GpsLoggingService.EXTRA_ACCURACY, 0f), intent.getDoubleExtra(GpsLoggingService.EXTRA_ALT, 0.0))
                    latestLat?.let { lat -> latestLon?.let { lon -> mapPanel?.updateLocation(lat, lon, mapHeading(), recordTrack = true) } }
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
        androidx.core.view.ViewCompat.setOnApplyWindowInsetsListener(b.root) { view, insets ->
            val bars = insets.getInsets(androidx.core.view.WindowInsetsCompat.Type.systemBars())
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }
        androidx.core.view.ViewCompat.requestApplyInsets(b.root)

        waypointStore = WaypointStore(this)
        library = waypointStore.loadLibrary()
        waypoints += waypointStore.loadAll()
        val activeId = waypointStore.getActiveId()
        activeWaypoint = if (activeId == "__none__") null else (waypoints.find { it.id == activeId } ?: waypoints.firstOrNull())
        activeWaypoint?.let { waypointStore.setActiveId(it.id) }

        setupDisplayModes()
        updateChecker = GitHubUpdateChecker(this) { debug(it) }
        b.btnCheckUpdate.text = "更新を確認（${BuildConfig.VERSION_NAME}）"
        b.btnCheckUpdate.setOnClickListener { updateChecker.check(manual = true) }
        setupSpinners()
        setupButtons()
        setupSensors()
        renderWaypointList()
        if (BuildConfig.DEBUG && intent.getBooleanExtra("previewLibraryOverlay", false)) {
            val selected=waypoints.take(3);val ids=selected.map{it.id}
            if(ids.size>=3) { library=MapLibrary(groups=listOf("デモ海域"),features=listOf(
                MapFeature(name="半径200m",kind="circle",waypointIds=ids.take(1),group="デモ海域"),
                MapFeature(name="囲みエリア",kind="area",waypointIds=ids,color="#CC44AA",group="デモ海域"),
                MapFeature(name="地点間の直線",kind="line",waypointIds=ids.take(2),color="#FFFF00",group="デモ海域")))
                waypointStore.saveLibrary(waypoints,library);renderWaypointList();updateNavigationUi();b.root.postDelayed({mapPanel?.showWaypoints()},1000) }
        }
        if (BuildConfig.DEBUG && intent.getBooleanExtra("previewLibrary", false)) b.root.post { showMapLibrary() }
        if (BuildConfig.DEBUG && intent.getBooleanExtra("previewMapOperations", false)) b.root.post { showMapOperations(35.318,139.467) }
        if (BuildConfig.DEBUG && intent.getBooleanExtra("previewNavigationOptions", false)) b.root.post { showNavigationOptions() }
        if (BuildConfig.DEBUG && intent.getBooleanExtra("clearTarget", false)) clearTarget()
        if (BuildConfig.DEBUG && intent.getBooleanExtra("previewAppearance", false)) b.root.post {
            WaypointAppearanceDialog.show(this, "灯台", "#12ABCD") { mark, color ->
                (waypoints.firstOrNull { it.name == "MAP_TEST" } ?: activeWaypoint)?.let { original ->
                    val changed = original.copy(mark = mark, color = color)
                    val index = waypoints.indexOfFirst { it.id == original.id }
                    if (index >= 0) waypoints[index] = changed
                    if (activeWaypoint?.id == original.id) activeWaypoint = changed
                    waypointStore.saveAll(waypoints); renderWaypointList(); updateNavigationUi()
                    debug("Appearance fixture saved")
                }
            }
        }

        updateNavigationUi()
        updateStatusUi()
        requestNeededPermissions()
        if (BuildConfig.DEBUG) {
            var previousBounds = ""
            b.root.viewTreeObserver.addOnGlobalLayoutListener {
                val button = android.graphics.Rect()
                val map = android.graphics.Rect()
                if (b.btnCurrentWp.getGlobalVisibleRect(button) && b.mapContainer.getGlobalVisibleRect(map)) {
                    val bounds = "UI current=${button.left},${button.top},${button.right},${button.bottom} map=${map.left},${map.top},${map.right},${map.bottom}"
                    if (bounds != previousBounds) {
                        previousBounds = bounds
                        Log.d("SailingUiBounds", bounds)
                    }
                }
            }
        }

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
        foregroundActive = true
        startPreview()
        uiHandler.removeCallbacks(clockTick)
        uiHandler.post(clockTick)
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
        foregroundActive = false
        stopPreview()
        uiHandler.removeCallbacks(clockTick)
        cancelQuickLocation()
        mapPanel?.pause()
        sensorManager.unregisterListener(this)
        debug("Compass sensors unregistered")
        super.onPause()
    }

    private fun setupDisplayModes() {
        b.btnSpeedMode.setOnClickListener { setDisplayMode(false) }
        b.btnNavigatorMode.setOnClickListener { setDisplayMode(true) }
        b.btnShowWaypoints.setOnClickListener { mapPanel?.showWaypoints() }
        b.btnMenu.setOnClickListener { showNavigationMenu() }
        b.btnSetTarget.setOnClickListener { showNavigationOptions() }
        b.btnFollow.setOnClickListener { mapPanel?.followLocation() }
        setDisplayMode(displayPrefs.getBoolean("navigator", false))
    }

    private fun setDisplayMode(navigator: Boolean) {
        navigatorMode = navigator
        if (navigator && mapPanel == null) {
            mapPanel = NavigationMapPanel(this, b.mapContainer, { debug(it) }, { lat, lon -> showMapOperations(lat, lon) }) { waypoint -> editWaypoint(waypoint) }
            mapPanel?.onFollowingChanged = { following -> b.btnFollow.text = if (following) "追従 1cm≒200m" else "再度中心に配置" }
            mapPanel?.setDisplayOptions(displayPrefs.getBoolean("showWaypoints", true), displayPrefs.getBoolean("showCourse", true))
            mapPanel?.setWaypoints(waypoints.filter { it.group !in library.hiddenGroups }, activeWaypoint)
        mapPanel?.setFeatures(library.features.filter { it.visible && it.group !in library.hiddenGroups },waypoints)
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
        mapPanel?.updateLocation(lat, lon, mapHeading(), recordTrack = false)
    }

    // Foreground preview never opens the recording file or starts a foreground service.
    private fun startPreview() {
        if (!foregroundActive || previewListener != null || ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) return
        val manager = getSystemService(LOCATION_SERVICE) as android.location.LocationManager
        val listener = object : android.location.LocationListener {
            override fun onLocationChanged(location: Location) {
                val age = android.os.SystemClock.elapsedRealtime() - location.elapsedRealtimeNanos / 1_000_000L
                if (age !in 0..30_000 || location.accuracy < 0) return
                latestLat = location.latitude; latestLon = location.longitude
                latestFixAt = location.elapsedRealtimeNanos / 1_000_000L
                latestSpeedMps = if (location.hasSpeed()) location.speed.toDouble().coerceAtLeast(0.0) else null
                latestGpsBearing = if (location.hasBearing()) location.bearing.toDouble() else null
                b.tvGpsInfo.text = "GPS\n精度 ±%.0f m\n高度 %.0f m".format(location.accuracy, location.altitude)
                updateMap(); updateNavigationUi()
            }
            override fun onProviderDisabled(provider: String) { debug("GPS preview provider disabled") }
            override fun onProviderEnabled(provider: String) { debug("GPS preview provider enabled") }
        }
        runCatching {
            manager.requestLocationUpdates(android.location.LocationManager.GPS_PROVIDER, 1000L, 0f, listener, android.os.Looper.getMainLooper())
            previewListener = listener
            debug("GPS preview started (no recording)")
        }.onFailure { debug("GPS preview: ${it.message}") }
    }

    private fun stopPreview() {
        previewListener?.let { listener -> (getSystemService(LOCATION_SERVICE) as android.location.LocationManager).removeUpdates(listener) }
        previewListener = null
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_LOCATION) startPreview()
    }

    private fun headingReference(): HeadingReference.Reading? {
        val declination = latestLat?.let { lat -> latestLon?.let { lon ->
            GeomagneticField(lat.toFloat(), lon.toFloat(), 0f, System.currentTimeMillis()).declination.toDouble()
        } }
        return HeadingReference.resolve(preferGpsHeading, magneticHeading, declination, latestGpsBearing, latestSpeedMps)
    }

    private fun mapHeading(): Double? = headingReference()?.trueHeading

    override fun onDestroy() {
        if (::updateChecker.isInitialized) updateChecker.close()
        mapPanel?.destroy()
        super.onDestroy()
    }

    private fun setupSpinners() {
        b.headingSelector.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, listOf("磁気コンパスで追従", "GPS進行方位で追従"))
        b.headingSelector.setSelection(if (preferGpsHeading) 1 else 0)
        b.headingSelector.onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
            override fun onNothingSelected(parent: android.widget.AdapterView<*>?) {}
            override fun onItemSelected(parent: android.widget.AdapterView<*>?, view: android.view.View?, position: Int, id: Long) {
                preferGpsHeading = position == 1
                updateNavigationUi(); updateMap()
                debug("Heading preference=" + if (preferGpsHeading) "GPS" else "MAG")
            }
        }
        b.unitSelector.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, listOf("knot / nm", "km/h / m・km"))
        b.unitSelector.setSelection(if (metricUnits) 1 else 0)
        b.unitSelector.onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
            override fun onNothingSelected(parent: android.widget.AdapterView<*>?) {}
            override fun onItemSelected(parent: android.widget.AdapterView<*>?, view: android.view.View?, position: Int, id: Long) {
                metricUnits = position == 1
                updateNavigationUi()
                debug("Units metric=$metricUnits")
            }
        }
        b.spLatDir.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, listOf("N", "S"))
        b.spLonDir.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, listOf("E", "W"))
    }

    private fun setupButtons() {
        b.btnStart.setOnClickListener { startGpsLogging() }
        b.btnStop.setOnClickListener { stopGpsLogging() }
        b.btnExport.setOnClickListener { exportGpx() }
        b.btnClearTrack.setOnClickListener { clearTrack() }
        b.btnAddWp.setOnClickListener { addWaypointFromInputs() }
        b.btnWpAppearance.setOnClickListener { chooseDraftAppearance() }
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
        b.btnStart.visibility = if (running) android.view.View.GONE else android.view.View.VISIBLE
        b.btnStop.visibility = if (running) android.view.View.VISIBLE else android.view.View.GONE
        b.btnStart.isEnabled = !running
        b.btnStop.isEnabled = running
    }

    private fun updateNavigationUi() {
        val speed = latestSpeedMps?.takeIf { it >= 0 }?.times(if (metricUnits) 3.6 else NavigationUtils.MPS_TO_KT)
        val unit = if (metricUnits) "km/h" else "knot"
        b.tvSpeedUnit.text = "SOG · $unit"
        b.tvSog.text = speed?.let { "%.1f %s".format(it, unit) } ?: "-- $unit"
        b.tvLargeSpeed.speedValue = speed
        b.tvLargeSpeed.contentDescription = "対地速度 ${b.tvSog.text}"
        b.tvPosition.text = if (latestLat != null && latestLon != null)
            "${NavigationUtils.formatDm(latestLat!!, true)}   ${NavigationUtils.formatDm(latestLon!!, false)}"
            else "現在地：GPS受信待ち"
        val reference = headingReference()
        val heading = reference?.heading
        val source = if (reference == null) "未取得" else if (reference.magnetic) "磁気コンパス（MAG）" else "GPS対地針路（COG）"
        b.tvCog.text = heading?.let { "${NavigationUtils.normalize360(it).roundToInt() % 360}°" } ?: "--°"
        b.tvHeadingSource.text = "方位ソース：$source"

        val wp = activeWaypoint
        b.tvEte.text = "ETE\n--:--:--"
        val lat = latestLat
        val lon = latestLon
        if (wp == null || lat == null || lon == null) {
            b.tvDistance.text = if (metricUnits) "-- m/km" else "-- nm"
            b.tvDistanceSub.text = "-- m"
            b.tvClock.text = "--時方向"
            b.tvWpName.text = wp?.name ?: "未設定"
            b.tvWpCoords.text = wp?.let { "${NavigationUtils.formatDm(it.lat, true)}\n${NavigationUtils.formatDm(it.lon, false)}" } ?: "--"
            b.instrumentView.update(null, null, heading, reference?.magnetic == true)
            return
        }

        val distanceM = NavigationUtils.distanceMeters(lat, lon, wp.lat, wp.lon)
        val bearing = NavigationUtils.bearingDegrees(lat, lon, wp.lat, wp.lon)
        b.tvEte.text = "ETE\n" + NavigationUtils.ete(distanceM, latestSpeedMps)
        b.tvDistance.text = DisplayNavigation.distance(distanceM, metricUnits)
        b.tvDistanceSub.text = ""
        b.tvWpName.text = wp.name
        b.tvWpCoords.text = "${NavigationUtils.formatDm(wp.lat, true)}\n${NavigationUtils.formatDm(wp.lon, false)}"

        val trueHeading = reference?.trueHeading
        if (heading != null && trueHeading != null) {
            val relative = HeadingReference.relative(bearing, trueHeading)
            val displayBearing = NavigationUtils.normalize360(heading + relative)
            val now = android.os.SystemClock.uptimeMillis()
            if (now - latestHeadingLogAt >= 500) {
                latestHeadingLogAt = now
                debug("Nav heading=$heading true=$trueHeading target=$displayBearing relative=$relative source=$source")
            }
            b.tvClock.text = NavigationUtils.relativeClock(relative)
            b.instrumentView.update(relative, displayBearing, heading, reference?.magnetic == true)
        } else {
            b.tvClock.text = "方位待ち"
            b.instrumentView.update(null, null, heading, reference?.magnetic == true)
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
        val wp = Waypoint(name = name, lat = lat, lon = lon, mark = draftMark, color = draftColor)
        waypoints += wp
        val shouldConfirm = pendingNavigation
        pendingNavigation = false
        if (!shouldConfirm) activeWaypoint = wp
        waypointStore.saveAll(waypoints)
        if (!shouldConfirm) waypointStore.setActiveId(wp.id)
        clearWaypointInputs()
        renderWaypointList()
        updateNavigationUi()
        if (shouldConfirm) confirmTarget(wp)
        debug("WP added $name ${NavigationUtils.formatDm(lat, true)} ${NavigationUtils.formatDm(lon, false)}")
    }

    private fun cancelQuickLocation() {
        quickLocationListener?.let { listener ->
            (getSystemService(LOCATION_SERVICE) as android.location.LocationManager).removeUpdates(listener)
        }
        quickLocationListener = null
        b.btnCurrentWp.isEnabled = true
    }

    private fun addCurrentLocationWaypoint() {
        if (quickLocationListener != null) return
        val lat = latestLat
        val lon = latestLon
        if (lat != null && lon != null && android.os.SystemClock.elapsedRealtime() - latestFixAt < 30000) {
            saveCurrentLocationWaypoint(lat, lon)
            return
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            requestNeededPermissions()
            Toast.makeText(this, "位置情報を許可してから現在地WPを押してください", Toast.LENGTH_LONG).show()
            return
        }
        val manager = getSystemService(LOCATION_SERVICE) as android.location.LocationManager
        if (!manager.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER)) {
            Toast.makeText(this, "端末の位置情報をONにしてください", Toast.LENGTH_LONG).show()
            return
        }
        val listener = object : android.location.LocationListener {
            override fun onLocationChanged(point: Location) {
                if (quickLocationListener !== this || point.accuracy < 0 ||
                    (android.os.SystemClock.elapsedRealtimeNanos() - point.elapsedRealtimeNanos) > 30_000_000_000L) return
                cancelQuickLocation()
                latestLat = point.latitude; latestLon = point.longitude
                latestFixAt = android.os.SystemClock.elapsedRealtime()
                latestSpeedMps = if (point.hasSpeed()) point.speed.toDouble() else null
                latestGpsBearing = if (point.hasBearing()) point.bearing.toDouble() else null
                b.tvGpsInfo.text = "GPS\n精度 ±%.0f m\n高度 %.0f m".format(point.accuracy, point.altitude)
                mapPanel?.updateLocation(point.latitude, point.longitude, mapHeading(), recordTrack = false)
                saveCurrentLocationWaypoint(point.latitude, point.longitude)
            }
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) { cancelQuickLocation() }
            @Deprecated("Deprecated in Android")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        }
        quickLocationListener = listener
        b.btnCurrentWp.isEnabled = false
        Toast.makeText(this, "現在地を取得しています", Toast.LENGTH_SHORT).show()
        try {
            manager.requestLocationUpdates(android.location.LocationManager.GPS_PROVIDER, 0L, 0f, listener, android.os.Looper.getMainLooper())
            uiHandler.postDelayed({
                if (quickLocationListener === listener) {
                    cancelQuickLocation()
                    Toast.makeText(this, "現在地を取得できません。屋外で再試行してください", Toast.LENGTH_LONG).show()
                }
            }, 20000)
        } catch (error: Exception) {
            cancelQuickLocation(); debug("Quick waypoint location error: ${error.message}")
        }
    }

    private var draftMark = "●"
    private var draftColor = "#FFAA00"
    private fun chooseDraftAppearance() {
        WaypointAppearanceDialog.show(this, draftMark, draftColor) { mark, color ->
            draftMark = mark; draftColor = color
            b.btnWpAppearance.text = "$mark マーク・色を選ぶ"
            b.btnWpAppearance.setTextColor(runCatching { Color.parseColor(color) }.getOrDefault(Color.WHITE))
        }
    }

    private var pendingNavigation = false
    private fun showSettings() {
        b.settingsPanel.visibility = android.view.View.VISIBLE
        b.root.post { (b.root as android.widget.ScrollView).smoothScrollTo(0, b.settingsPanel.top) }
    }
    private fun showActionPanel(title: String, actions: List<Pair<String, () -> Unit>>) {
        val dialog = com.google.android.material.bottomsheet.BottomSheetDialog(this)
        val column = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(12,12,12,12); setBackgroundColor(Color.rgb(15,15,15)) }
        column.addView(TextView(this).apply { text = title; textSize = 17f; setTextColor(Color.WHITE); setPadding(8,8,8,12) })
        val grid = android.widget.GridLayout(this).apply { columnCount = 2 }
        (actions + ("閉じる" to {})).forEach { (label, action) ->
            val button = Button(this).apply {
                text = label; textSize = 14f; setTextColor(Color.WHITE); isAllCaps = false
                background = android.graphics.drawable.GradientDrawable().apply { setColor(Color.rgb(40,40,40)); setStroke(2,Color.rgb(255,170,0)); cornerRadius = 8f }
                layoutParams = android.widget.GridLayout.LayoutParams().apply { width = 0; height = (76*resources.displayMetrics.density).toInt(); columnSpec = android.widget.GridLayout.spec(android.widget.GridLayout.UNDEFINED,1f); setMargins(4,4,4,4) }
                setOnClickListener { dialog.dismiss(); action() }
            }
            grid.addView(button)
            if (BuildConfig.DEBUG) button.viewTreeObserver.addOnGlobalLayoutListener {
                val xy=IntArray(2);button.getLocationOnScreen(xy)
                android.util.Log.d("SailingUiBounds", "ACTION label=$label bounds=${xy[0]},${xy[1]},${xy[0]+button.width},${xy[1]+button.height}")
            }
            if (BuildConfig.DEBUG && label == "ここにウェイポイントを作成") button.viewTreeObserver.addOnGlobalLayoutListener {
                val xy=IntArray(2);button.getLocationOnScreen(xy)
                android.util.Log.d("SailingUiBounds", "MAPOPS create=${xy[0]},${xy[1]},${xy[0]+button.width},${xy[1]+button.height}")
            }
        }
        column.addView(grid)
        dialog.setContentView(android.widget.ScrollView(this).apply { addView(column) }); dialog.show()
        dialog.behavior.state = com.google.android.material.bottomsheet.BottomSheetBehavior.STATE_EXPANDED
    }
    private fun showMapOperations(lat: Double, lon: Double) {
        val coords = NavigationUtils.formatDm(lat,true)+", "+NavigationUtils.formatDm(lon,false)
        val showWaypoints = displayPrefs.getBoolean("showWaypoints",true)
        val showCourse = displayPrefs.getBoolean("showCourse",true)
        showActionPanel("地図の操作\n$coords", listOf(
            "ここにウェイポイントを作成" to { createMapWaypoint(lat,lon) },
            "座標をコピー" to { (getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager).setPrimaryClip(android.content.ClipData.newPlainText("座標",coords)); Toast.makeText(this,"座標をコピーしました",Toast.LENGTH_SHORT).show() },
            (if (showWaypoints) "ウェイポイントを非表示" else "ウェイポイントを表示") to { displayPrefs.edit().putBoolean("showWaypoints",!showWaypoints).apply(); mapPanel?.setDisplayOptions(!showWaypoints,showCourse) },
            (if (showCourse) "進路ラインを隠す" else "進路ラインを表示") to { displayPrefs.edit().putBoolean("showCourse",!showCourse).apply(); mapPanel?.setDisplayOptions(showWaypoints,!showCourse) },
            "再度中心に配置" to { mapPanel?.followLocation() }
        ))
    }
    private fun showNavigationOptions() {
        showActionPanel("ナビゲーションのオプション", listOf(
            "新規ウェイポイント" to { pendingNavigation = true; showSettings(); b.etWpName.requestFocus() },
            "既存ウェイポイント（近い順）" to { showTargetList(true) },
            "既存ウェイポイント（最近）" to { showTargetList(false) },
            "目標なし" to { clearTarget() }
        ))
    }
    private fun showTargetList(nearest: Boolean, folder: String = "") {
        val lat = latestLat; val lon = latestLon
        val ordered = if (nearest && lat != null && lon != null) waypoints.sortedBy { NavigationUtils.distanceMeters(lat,lon,it.lat,it.lon) } else waypoints.asReversed()
        val actions = ordered.filter{it.group==folder}.map { waypoint ->
            val distance = if (lat != null && lon != null) " · "+DisplayNavigation.distance(NavigationUtils.distanceMeters(lat,lon,waypoint.lat,waypoint.lon), metricUnits) else ""
            ("${waypoint.mark} ${waypoint.name}$distance") to { confirmTarget(waypoint) }
        }
        val folders=(listOf("")+library.groups+waypoints.map{it.group}).distinct().sorted()
        val changeFolder:Pair<String,()->Unit> = ("フォルダ: ${folder.ifEmpty{"メインフォルダ"}} ▾") to { androidx.appcompat.app.AlertDialog.Builder(this).setTitle("フォルダ").setItems(folders.map{it.ifEmpty{"メインフォルダ"}}.toTypedArray()){_,i->showTargetList(nearest,folders[i])}.show();Unit }
        showActionPanel(if (nearest) "目標・近い順" else "目標・最近", listOf(changeFolder)+actions + ("目標なし" to { clearTarget() }))
    }
    private fun confirmTarget(waypoint: Waypoint) {
        androidx.appcompat.app.AlertDialog.Builder(this).setTitle(waypoint.name)
            .setMessage(NavigationUtils.formatDm(waypoint.lat,true)+", "+NavigationUtils.formatDm(waypoint.lon,false))
            .setNegativeButton("キャンセル",null).setPositiveButton("Go!") { _,_ ->
                activeWaypoint = waypoint; waypointStore.setActiveId(waypoint.id); renderWaypointList(); updateNavigationUi(); mapPanel?.followLocation()
            }.show().also { dialog ->
                if (BuildConfig.DEBUG) dialog.window?.decorView?.viewTreeObserver?.addOnGlobalLayoutListener {
                    val button=dialog.getButton(android.content.DialogInterface.BUTTON_POSITIVE);val xy=IntArray(2);button.getLocationOnScreen(xy)
                    android.util.Log.d("SailingUiBounds", "GO bounds=${xy[0]},${xy[1]},${xy[0]+button.width},${xy[1]+button.height}")
                }
            }
    }
    private fun showMapLibrary() {
        MapLibraryDialog(this,{waypoints.toList()},{library},{items,updated ->
            runCatching { waypointStore.saveLibrary(items,updated);waypoints.clear();waypoints.addAll(items);library=updated
                activeWaypoint=waypoints.firstOrNull{it.id==activeWaypoint?.id};renderWaypointList();updateNavigationUi();debug("Map library saved groups=${library.groups.size} features=${library.features.size}") }.onFailure(::transferError)
        },{items,features,format -> runCatching {
            require(items.isNotEmpty() || features.isNotEmpty()) { "出力する地点・図形を選んでください" }
            pendingExport=if(format=="json")WaypointArchive.encode(items)else KmlArchive.encode(items,features,format=="kmz")
            exportWaypointsDocument.launch("SailingGPS-waypoints-${System.currentTimeMillis()}.$format")
        }.onFailure(::transferError) },{importWaypointsDocument.launch(arrayOf("*/*"))}).show()
    }

    private fun showNavigationMenu() {
        showActionPanel("メニュー", listOf(
            "目標" to { showNavigationOptions() }, "新規ウェイポイント" to { pendingNavigation = false; showSettings() },
            "ウェイポイント（近い順）" to { showTargetList(true) }, "現在地に打つ" to { addCurrentLocationWaypoint() },
            "記録開始" to { startGpsLogging() }, "記録停止" to { stopGpsLogging() },
            "地点・グループ・エリア" to { showMapLibrary() },
            "WPインポート" to { importWaypointsDocument.launch(arrayOf("*/*")) },
            "GPX出力" to { exportGpx() }, "設定" to { showSettings() },
            "モード切替" to { setDisplayMode(!navigatorMode) }, "全ウェイポイント" to { mapPanel?.showWaypoints() }
        ))
    }

    private fun createMapWaypoint(lat: Double, lon: Double) {
        val input = android.widget.EditText(this).apply { hint = "ウェイポイント名"; setSingleLine(true) }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; addView(input)
            addView(Button(this@MainActivity).apply { text = "マーク・色を選ぶ"; setOnClickListener { chooseDraftAppearance() } })
        }
        androidx.appcompat.app.AlertDialog.Builder(this)
            .setTitle("地図の地点を追加")
            .setMessage("${NavigationUtils.formatDm(lat, true)} / ${NavigationUtils.formatDm(lon, false)}")
            .setView(content).setNegativeButton("キャンセル", null)
            .setPositiveButton("保存") { _, _ ->
                val wp = Waypoint(name = input.text.toString().trim().ifEmpty { "地点 ${waypoints.size + 1}" }, lat = lat, lon = lon, mark = draftMark, color = draftColor)
                waypoints += wp
                waypointStore.saveAll(waypoints)
                renderWaypointList(); updateNavigationUi()
                debug("Map waypoint saved / ${wp.id}")
                Toast.makeText(this, "${wp.name} を保存しました", Toast.LENGTH_SHORT).show()
            }.show().also { dialog ->
                if (BuildConfig.DEBUG) {
                    dialog.window?.decorView?.viewTreeObserver?.addOnGlobalLayoutListener {
                        fun bounds(view: android.view.View): String {
                            val xy = IntArray(2); view.getLocationOnScreen(xy)
                            return "${xy[0]},${xy[1]},${xy[0] + view.width},${xy[1] + view.height}"
                        }
                        android.util.Log.d("SailingUiBounds", "DIALOG input=${bounds(input)} save=${bounds(dialog.getButton(android.content.DialogInterface.BUTTON_POSITIVE))}")
                    }
                }
            }
    }

    private fun saveCurrentLocationWaypoint(lat: Double, lon: Double) {
        val name = b.etWpName.text.toString().trim().ifEmpty { "現在地 ${waypoints.size + 1}" }
        val wp = Waypoint(name = name, lat = lat, lon = lon, mark = draftMark, color = draftColor)
        waypoints += wp
        activeWaypoint = wp
        waypointStore.saveAll(waypoints)
        waypointStore.setActiveId(wp.id)
        clearWaypointInputs()
        renderWaypointList()
        updateNavigationUi()
        mapPanel?.showWaypoints()
        Toast.makeText(this, "$name を保存しました", Toast.LENGTH_SHORT).show()
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

    private fun clearTarget() {
        activeWaypoint = null; waypointStore.setActiveId(null)
        renderWaypointList(); updateNavigationUi(); debug("Target cleared")
    }

    private fun editWaypoint(original: Waypoint) {
        var mark = original.mark; var color = original.color
        val name = android.widget.EditText(this).apply { setText(original.name); setSingleLine(true) }
        val lat = android.widget.EditText(this).apply { setText(original.lat.toString()); hint = "緯度（十進度）"; inputType = 12290 }
        val lon = android.widget.EditText(this).apply { setText(original.lon.toString()); hint = "経度（十進度）"; inputType = 12290 }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; setPadding(24,8,24,8)
            addView(TextView(this@MainActivity).apply { text = "名前" }); addView(name)
            addView(TextView(this@MainActivity).apply { text = "緯度・経度（十進度）" }); addView(lat); addView(lon)
            addView(Button(this@MainActivity).apply { text = "マーク・色"; setOnClickListener { WaypointAppearanceDialog.show(this@MainActivity, mark, color) { m, c -> mark = m; color = c } } })
        }
        val dialog = androidx.appcompat.app.AlertDialog.Builder(this).setTitle("ウェイポイントを編集").setView(content)
            .setNegativeButton("キャンセル", null).setPositiveButton("保存", null).create()
        dialog.setOnShowListener {
            dialog.getButton(android.content.DialogInterface.BUTTON_POSITIVE).setOnClickListener {
                val latitude = lat.text.toString().toDoubleOrNull(); val longitude = lon.text.toString().toDoubleOrNull()
                if (latitude == null || !latitude.isFinite() || latitude !in -90.0..90.0) { lat.error = "-90〜90で入力"; return@setOnClickListener }
                if (longitude == null || !longitude.isFinite() || longitude !in -180.0..180.0) { lon.error = "-180〜180で入力"; return@setOnClickListener }
                val changed = original.copy(name = name.text.toString().trim().ifEmpty { original.name }, lat = latitude, lon = longitude, mark = mark, color = color)
                val index = waypoints.indexOfFirst { it.id == original.id }
                if (index >= 0) waypoints[index] = changed
                if (activeWaypoint?.id == original.id) activeWaypoint = changed
                waypointStore.saveAll(waypoints); renderWaypointList(); updateNavigationUi(); debug("WP edited ${original.id}"); dialog.dismiss()
            }
        }
        dialog.show()
        if (BuildConfig.DEBUG) dialog.window?.decorView?.viewTreeObserver?.addOnGlobalLayoutListener {
            fun bounds(view: android.view.View): String { val xy=IntArray(2);view.getLocationOnScreen(xy);return "${xy[0]},${xy[1]},${xy[0]+view.width},${xy[1]+view.height}" }
            android.util.Log.d("SailingUiBounds", "EDIT input=${bounds(name)} save=${bounds(dialog.getButton(android.content.DialogInterface.BUTTON_POSITIVE))}")
        }
    }

    private var waypointFolder = ""
    private fun renderWaypointList() {
        mapPanel?.setWaypoints(waypoints.filter { it.group !in library.hiddenGroups }, activeWaypoint)
        mapPanel?.setFeatures(library.features.filter { it.visible && it.group !in library.hiddenGroups },waypoints)
        b.waypointContainer.removeAllViews()
        b.waypointContainer.addView(Button(this).apply {
            text = if (activeWaypoint == null) "目標なし（選択中）" else "目標なし"
            setOnClickListener { clearTarget() }
        })
        val folders=(listOf("")+library.groups+waypoints.map{it.group}).distinct().sorted()
        b.waypointContainer.addView(Button(this).apply {
            text="フォルダ: ${waypointFolder.ifEmpty{"メインフォルダ"}} ▾"
            setOnClickListener { androidx.appcompat.app.AlertDialog.Builder(this@MainActivity).setTitle("フォルダ").setItems(folders.map{it.ifEmpty{"メインフォルダ"}}.toTypedArray()){_,i->waypointFolder=folders[i];renderWaypointList()}.show() }
        })
        waypoints.filter{it.group==waypointFolder}.forEach { wp ->
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(6, 6, 6, 6)
                setBackgroundColor(if (activeWaypoint?.id == wp.id) Color.rgb(35, 25, 0) else Color.rgb(10, 10, 10))
            }
            val text = TextView(this).apply {
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                setTextColor(Color.WHITE)
                textSize = 17f
                text = "${wp.mark} ${wp.name}\n${NavigationUtils.formatDm(wp.lat, true)} / ${NavigationUtils.formatDm(wp.lon, false)}"
            }
            val select = Button(this).apply {
                this.text = if (activeWaypoint?.id == wp.id) "選択中" else "選択"
                isEnabled = activeWaypoint?.id != wp.id
                setOnClickListener {
                    confirmTarget(wp)
                }
            }
            val appearance = Button(this).apply {
                this.text = "外観"
                setOnClickListener {
                    WaypointAppearanceDialog.show(this@MainActivity, wp.mark, wp.color) { mark, color ->
                        val changed = wp.copy(mark = mark, color = color)
                        val index = waypoints.indexOfFirst { it.id == wp.id }
                        if (index >= 0) waypoints[index] = changed
                        if (activeWaypoint?.id == wp.id) activeWaypoint = changed
                        waypointStore.saveAll(waypoints); renderWaypointList(); updateNavigationUi()
                        debug("WP appearance saved ${wp.id} / $color")
                    }
                }
            }
            val delete = Button(this).apply {
                this.text = "削除"
                setOnClickListener {
                    library=library.copy(features=library.features.map { f -> if(wp.id in f.waypointIds) f.copy(coordinates=f.points(waypoints),waypointIds=emptyList()) else f })
                    waypoints.removeAll { it.id == wp.id }
                    waypointStore.saveLibrary(waypoints,library)
                    if (activeWaypoint?.id == wp.id) activeWaypoint = null
                    waypointStore.saveAll(waypoints)
                    waypointStore.setActiveId(activeWaypoint?.id)
                    renderWaypointList()
                    updateNavigationUi()
                    debug("WP deleted ${wp.name}")
                }
            }
            row.addView(text)
            row.addView(select)
            row.addView(appearance)
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
        updateMap()
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
