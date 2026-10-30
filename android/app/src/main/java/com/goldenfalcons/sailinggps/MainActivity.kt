package com.goldenfalcons.sailinggps

import android.Manifest
import android.content.*
import android.content.pm.PackageManager
import android.graphics.Color
import android.hardware.*
import android.location.Location
import android.media.AudioManager
import android.media.ToneGenerator
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
    private var magneticSampleAt=0L
    private var accelSampleAt=0L
    private var compassAccuracy=SensorManager.SENSOR_STATUS_UNRELIABLE

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
            b.tvTime.text = "時間\n" + java.text.SimpleDateFormat(if(displayPrefs.getBoolean("twelveHourClock",false)) "h:mm:ss a" else "HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date())
            if(currentDisplayMode>=2) updateNavigationUi()
            if(currentDisplayMode==4) updateSignalUi()
            uiHandler.postDelayed(this, 1000)
        }
    }
    private var latestLat: Double? = null
    private var latestLon: Double? = null
    private var latestSpeedMps: Double? = null
    private var latestGpsBearing: Double? = null
    private var pointCount = 0
    private var running = false
    private var gpsGapSeconds = 0L

    private var navigatorMode = false
    private var currentDisplayMode=0
    private val focusHiddenVisibility=mutableMapOf<android.view.View,Int>()
    private val signalRows=mutableListOf<LinearLayout>()
    private var signalActiveIndex=-1
    private var signalClockOffsetMs:Long
        get()=displayPrefs.getLong("signalClockOffsetMs",0L)
        set(value){displayPrefs.edit().putLong("signalClockOffsetMs",value).apply()}
    private lateinit var focusSog:TextView
    private lateinit var focusCog:TextView
    private lateinit var focusBearing:TextView
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
        val incoming = archive.waypoints.map{if(it.group.isBlank())it.copy(group=mainWaypointFolder)else it}
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
                    gpsGapSeconds = maxOf(gpsGapSeconds,intent.getLongExtra(GpsLoggingService.EXTRA_GAP_SECONDS,0L))
                    b.tvGpsInfo.text = "GPS\n精度 ±%.0f m\n高度 %.0f m".format(intent.getFloatExtra(GpsLoggingService.EXTRA_ACCURACY, 0f), intent.getDoubleExtra(GpsLoggingService.EXTRA_ALT, 0.0))
                    latestLat?.let { lat -> latestLon?.let { lon -> mapPanel?.updateLocation(lat, lon, mapHeading(), recordTrack = true) } }
                    updateNavigationUi()
                    debug("GPS update lat=${latestLat} lon=${latestLon} speed=${latestSpeedMps} bearing=${latestGpsBearing}")
                }
                GpsLoggingService.ACTION_STATUS -> {
                    running = intent.getBooleanExtra(GpsLoggingService.EXTRA_RUNNING, false)
                    pointCount = intent.getIntExtra(GpsLoggingService.EXTRA_COUNT, pointCount)
                    gpsGapSeconds = intent.getLongExtra(GpsLoggingService.EXTRA_GAP_SECONDS, gpsGapSeconds)
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
        if (BuildConfig.DEBUG && intent.getBooleanExtra("previewFolderSave",false)) {
            library=library.copy(groups=(library.groups+"港一覧").distinct());waypointStore.saveLibrary(waypoints,library)
            displayPrefs.edit().putString("mainWaypointFolder","港一覧").apply()
            draftMark="港";saveCurrentLocationWaypoint(35.318,139.467)
            b.root.post { editWaypoint(waypoints.last()) }
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
        if(displayPrefs.getBoolean("keepScreenAwake",false)) window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
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
        if(currentDisplayMode==4 && ::b.isInitialized) { buildSignalRows(); updateSignalUi() }
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
        setupFocusPanel()
        b.btnFocusMode.text="セーリング"
        b.tvModeTitle.setOnClickListener { setDisplayMode((currentDisplayMode+1)%5) }
        b.btnFocusMode.setOnClickListener { setDisplayMode(2) }
        b.btnTimerMode.setOnClickListener { setDisplayMode(3) }
        b.btnSignalMode.setOnClickListener { setDisplayMode(4) }
        b.btnFocusMenu.setOnClickListener { showNavigationMenu() }
        b.btnFocusNorth.setOnClickListener { displayPrefs.edit().putBoolean("instrumentMagnetic",!displayPrefs.getBoolean("instrumentMagnetic",false)).apply();updateNavigationUi() }
        b.btnSpeedMode.setOnClickListener { setDisplayMode(0) }
        b.btnNavigatorMode.setOnClickListener { setDisplayMode(true) }
        b.btnShowWaypoints.setOnClickListener { mapPanel?.showWaypoints() }
        b.btnMenu.setOnClickListener { showNavigationMenu() }
        b.btnSetTarget.setOnClickListener { showNavigationOptions() }
        b.startTimerPreset.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, listOf("1分","3分","5分","10分"))
        b.startTimerPreset.setSelection(2)
        b.btnCaptureOuterMark.setOnClickListener { captureStartLineEndpoint("outer") }
        b.btnCaptureSignalBoat.setOnClickListener { captureStartLineEndpoint("signal") }
        b.btnStartTimer.setOnClickListener { toggleStartTimer() }
        b.btnResetTimer.setOnClickListener { displayPrefs.edit().remove("startTimerEndAt").remove("startTimerPausedSeconds").apply(); updateStartTimerUi() }
        if(displayPrefs.getInt("signalProfileSchemaVersion",0)<1) {
            val oldProfile=displayPrefs.getInt("signalFlagProfileIndex",0)
            val newProfile=if(oldProfile<=0) 0 else (oldProfile+1).coerceAtMost(SignalSequence.profiles.lastIndex)
            val newDuration=if(displayPrefs.contains("signalDurationIndexV2")) (displayPrefs.getInt("signalDurationIndexV2",4)+1).coerceIn(0,5) else 0
            displayPrefs.edit().putInt("signalFlagProfileIndex",newProfile).putInt("signalDurationIndexV2",newDuration).putInt("signalProfileSchemaVersion",1).apply()
        }
        b.signalDuration.adapter=ArrayAdapter(this,android.R.layout.simple_spinner_dropdown_item,listOf("14分・帆走スタート","1分シーケンス","3分シーケンス","5分シーケンス","10分シーケンス","20分シーケンス"))
        b.signalDuration.setSelection(displayPrefs.getInt("signalDurationIndexV2",0).coerceIn(0,5))
        b.signalFlagProfile.adapter=ArrayAdapter(this,android.R.layout.simple_spinner_dropdown_item,SignalSequence.profiles.map{it.name})
        b.signalFlagProfile.setSelection(displayPrefs.getInt("signalFlagProfileIndex",0).coerceIn(0,SignalSequence.profiles.lastIndex))
        b.signalFlagProfile.onItemSelectedListener=object:android.widget.AdapterView.OnItemSelectedListener {
            override fun onNothingSelected(parent:android.widget.AdapterView<*>?) {}
            override fun onItemSelected(parent:android.widget.AdapterView<*>?,view:android.view.View?,position:Int,id:Long) { displayPrefs.edit().putInt("signalFlagProfileIndex",position).apply();if(position==0){displayPrefs.edit().putInt("signalDurationIndexV2",0).apply();b.signalDuration.setSelection(0)};buildSignalRows();updateSignalUi() }
        }
        b.signalDuration.onItemSelectedListener=object:android.widget.AdapterView.OnItemSelectedListener {
            override fun onNothingSelected(parent:android.widget.AdapterView<*>?) {}
            override fun onItemSelected(parent:android.widget.AdapterView<*>?,view:android.view.View?,position:Int,id:Long) { displayPrefs.edit().putInt("signalDurationIndexV2",position).apply();buildSignalRows();updateSignalUi() }
        }
        b.signalPrepFlag.adapter=ArrayAdapter(this,android.R.layout.simple_spinner_dropdown_item,listOf("準備信号：P旗","準備信号：I旗"))
        b.signalPrepFlag.setSelection(if(displayPrefs.getString("signalPrepFlag","P")=="I") 1 else 0)
        b.signalPrepFlag.onItemSelectedListener=object:android.widget.AdapterView.OnItemSelectedListener {
            override fun onNothingSelected(parent:android.widget.AdapterView<*>?) {}
            override fun onItemSelected(parent:android.widget.AdapterView<*>?,view:android.view.View?,position:Int,id:Long) {
                displayPrefs.edit().putString("signalPrepFlag",if(position==1) "I" else "P").apply()
                buildSignalRows();updateSignalUi()
            }
        }
        buildSignalRows()
        b.btnSignalSettings.setOnClickListener { startActivity(Intent(this, SignalSettingsActivity::class.java)) }
        b.btnSignalOrange.setOnClickListener {
            val current = if (displayPrefs.getBoolean("signalOrangeManualOverride", false))
                displayPrefs.getBoolean("signalOrangeManualUp", false)
            else displayPrefs.getBoolean("signalOrangeDisplayedUp", false)
            displayPrefs.edit().putBoolean("signalOrangeManualOverride", true)
                .putBoolean("signalOrangeManualUp", !current).apply()
            updateSignalUi()
        }
        b.btnSignalIndividualRecall.setOnClickListener { toggleIndividualRecall() }
        b.btnSignalGeneralRecall.setOnClickListener { toggleGeneralRecall() }
        b.btnSignalPostponement.setOnClickListener { togglePostponement() }
        b.btnSignalStart.setOnClickListener { toggleSignalSequence() }
        b.btnSignalReset.setOnClickListener { resetSignalSequence() }
        b.btnSignalZero.setOnClickListener {
            val events=SignalSequence.events(currentSignalDurationMinutes(),displayPrefs.getInt("signalFlagProfileIndex",0),displayPrefs.getString("signalPrepFlag","P") ?: "P")
            displayPrefs.edit().putBoolean("signalRestartMode",false).putBoolean("signalIndividualRecallFlagUp",false)
                .putBoolean("signalGeneralRecallFlagUp",false).putBoolean("signalPostponementFlagUp",false)
                .remove("signalRestartAt").remove("signalRestartPausedElapsedMs")
                .putLong("signalElapsedStartAt",signalNow()).remove("signalPausedElapsedMs").putInt("signalLastFiredIndex",0)
                .remove("signalOrangeManualOverride").remove("signalOrangeManualUp").apply()
            playSignalHorn(events.firstOrNull { it.secondsAfterStart==0 }?.hornPulses ?: emptyList());signalActiveIndex=-1;buildSignalRows();updateSignalUi()
        }
        b.btnNictSync.setOnClickListener { syncNictClock() }
        fun bindSignalSeek(seek:android.widget.SeekBar,label:android.widget.TextView,key:String,defaultValue:Int,step:Int,maxProgress:Int,suffix:String) {
            seek.max=maxProgress
            val stored=displayPrefs.getInt(key,defaultValue)
            seek.progress=if(key=="signalHornVolume") stored.coerceIn(0,100) else ((stored-100)/step).coerceIn(0,seek.max)
            fun render(progress:Int) {
                val value=if(key=="signalHornVolume") progress else 100+progress*step
                displayPrefs.edit().putInt(key,value).apply()
                label.text=if(key=="signalHornVolume") "音量 $value%" else "$suffix ${"%.2f".format(java.util.Locale.US,value/1000.0)}秒"
            }
            render(seek.progress)
            seek.setOnSeekBarChangeListener(object:android.widget.SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(seekBar:android.widget.SeekBar?,progress:Int,fromUser:Boolean)=render(progress)
                override fun onStartTrackingTouch(seekBar:android.widget.SeekBar?) {}
                override fun onStopTrackingTouch(seekBar:android.widget.SeekBar?) {}
            })
        }
        b.signalHornEnabled.isChecked=displayPrefs.getBoolean("signalHornEnabled",true)
        b.signalHornEnabled.setOnCheckedChangeListener { _,checked -> displayPrefs.edit().putBoolean("signalHornEnabled",checked).apply() }
        bindSignalSeek(b.signalHornLength,b.tvHornLength,"signalHornMs",700,100,49,"長音")
        bindSignalSeek(b.signalShortHorn,b.tvSignalShortHorn,"signalShortHornMs",220,50,18,"短音")
        bindSignalSeek(b.signalGap,b.tvSignalGap,"signalGapMs",180,50,38,"間隔")
        bindSignalSeek(b.signalVolume,b.tvSignalVolume,"signalHornVolume",80,1,100,"音量")
        b.btnFollow.setOnClickListener { mapPanel?.followLocation() }
        setDisplayMode(if(BuildConfig.DEBUG && intent.getBooleanExtra("previewFocus",false)) 2 else displayPrefs.getInt("displayMode",if(displayPrefs.getBoolean("navigator",false)) 1 else 0))
    }

    private fun setupFocusPanel() {
        fun card(label:String,color:Int):Pair<LinearLayout,TextView> {
            val column=LinearLayout(this).apply { orientation=LinearLayout.VERTICAL;gravity=android.view.Gravity.CENTER;setPadding(8,8,8,8)
                layoutParams=LinearLayout.LayoutParams(-1,0,1f).apply { setMargins(0,4,0,4) }
                background=android.graphics.drawable.GradientDrawable().apply {setColor(Color.BLACK);setStroke(2,Color.GRAY);cornerRadius=10f} }
            column.addView(TextView(this).apply{text=label;textSize=20f;setTextColor(Color.LTGRAY);gravity=android.view.Gravity.CENTER})
            val value=TextView(this).apply {text="—";setTextColor(color);textSize=100f;typeface=android.graphics.Typeface.MONOSPACE;gravity=android.view.Gravity.CENTER;setSingleLine()
                layoutParams=LinearLayout.LayoutParams(-1,0,1f);androidx.core.widget.TextViewCompat.setAutoSizeTextTypeUniformWithConfiguration(this,24,112,1,android.util.TypedValue.COMPLEX_UNIT_SP) }
            column.addView(value);b.focusPanel.addView(column);return column to value
        }
        focusSog=card("SOG / "+if(metricUnits) "km/h" else "knot",Color.GREEN).second
        focusCog=card("COG（真北）",Color.WHITE).second
        val targetCard=card("目標方位（真北）",Color.rgb(255,170,0));focusBearing=targetCard.second
        targetCard.first.setOnClickListener { showNavigationOptions() }
        targetCard.first.contentDescription="目標方位。タップして目標地点を変更"
        b.focusPanel.setOnLongClickListener {showNavigationMenu();true}
    }

    private fun signalNow():Long=System.currentTimeMillis()+signalClockOffsetMs
    private fun currentSignalDurationMinutes():Int =
        listOf(14,1,3,5,10,20).getOrElse(displayPrefs.getInt("signalDurationIndexV2",0)){14}

    private fun buildSignalRows() {
        b.signalSequenceContainer.removeAllViews();signalRows.clear();signalActiveIndex=-1
        currentSignalEvents().forEach { event ->
            val row=LinearLayout(this).apply {
                orientation=LinearLayout.HORIZONTAL;gravity=android.view.Gravity.CENTER_VERTICAL;setPadding(7,3,7,3)
                layoutParams=LinearLayout.LayoutParams(-1,0,1f).apply {setMargins(0,1,0,1)}
                background=android.graphics.drawable.GradientDrawable().apply {setColor(0xffeeeeee.toInt());cornerRadius=3f}
            }
            row.addView(TextView(this).apply {text=if(event.raised) "↑" else "↓";textSize=19f;setTextColor(Color.BLACK);gravity=android.view.Gravity.CENTER;layoutParams=LinearLayout.LayoutParams(32,-1)})
            row.addView(TextView(this).apply {
                text="";gravity=android.view.Gravity.CENTER;textSize=14f;setTextColor(Color.WHITE)
                background=android.graphics.drawable.GradientDrawable().apply {setColor(event.color);cornerRadius=1f}
                layoutParams=LinearLayout.LayoutParams(38,-1).apply {setMargins(2,0,8,0)}
            })
            row.addView(TextView(this).apply {text=event.title;textSize=13f;setTextColor(Color.BLACK);gravity=android.view.Gravity.CENTER_VERTICAL;layoutParams=LinearLayout.LayoutParams(0,-1,1f)})
            row.addView(TextView(this).apply {text=signalEventTimeLabel(event,displayPrefs.getBoolean("signalRestartMode",false));textSize=12f;setTextColor(Color.DKGRAY);typeface=android.graphics.Typeface.MONOSPACE})
            row.addView(TextView(this).apply { text=event.hornPulses.joinToString(""){if(it==0)"●" else "—"};textSize=12f;setTextColor(Color.DKGRAY);gravity=android.view.Gravity.CENTER;layoutParams=LinearLayout.LayoutParams(42,-1) })
            b.signalSequenceContainer.addView(row);signalRows+=row
        }
    }

    private fun currentSignalEvents():List<SignalEvent> {
        val prep=displayPrefs.getString("signalPrepFlag","P") ?: "P"
        val orange=displayPrefs.getBoolean("signalOrangeEnabled",true)
        val orangeRemoved=displayPrefs.getInt("signalOrangeRemovedAfterMinutes",4)
        val className=displayPrefs.getString("signalSelectedClassName","クラス旗") ?: "クラス旗"
        if(displayPrefs.getBoolean("signalRestartMode",false)) return SignalSequence.restartEvents(prep,orange,orangeRemoved,className)
        val profile=displayPrefs.getInt("signalFlagProfileIndex",0).coerceIn(0,SignalSequence.profiles.lastIndex)
        return SignalSequence.events(currentSignalDurationMinutes(),profile,prep,orange,orangeRemoved,className)
    }

    private fun signalEventTimeLabel(event:SignalEvent,restart:Boolean):String {
        val profile=SignalSequence.profiles.getOrElse(displayPrefs.getInt("signalFlagProfileIndex",0)){SignalSequence.profiles[0]}
        if(!restart && profile.id!="standard-start") return "%02d:%02d".format(event.secondsAfterStart/60,event.secondsAfterStart%60)
        val offset=event.secondsAfterStart-(if(restart) 300 else 600)
        if(offset==0) return "T+00:00"
        val value=abs(offset)
        return (if(offset<0) "T−" else "T+")+"%02d:%02d".format(value/60,value%60)
    }

    private fun pauseSignalForManualEvent() {
        val now=signalNow()
        if(displayPrefs.getBoolean("signalRestartMode",false)) {
            val restartAt=displayPrefs.getLong("signalRestartAt",0L)
            if(restartAt>0L && now>=restartAt) {
                displayPrefs.edit().putLong("signalRestartPausedElapsedMs",now-restartAt).remove("signalRestartAt").apply()
            } else if(restartAt>now) {
                displayPrefs.edit().putLong("signalRestartPausedElapsedMs",0L).remove("signalRestartAt").apply()
            }
        } else {
            val startAt=displayPrefs.getLong("signalElapsedStartAt",0L)
            if(startAt>0L) displayPrefs.edit().putLong("signalPausedElapsedMs",(now-startAt).coerceAtLeast(0L)).remove("signalElapsedStartAt").apply()
        }
    }

    private fun toggleIndividualRecall() {
        if(displayPrefs.getBoolean("signalGeneralRecallFlagUp",false) || displayPrefs.getBoolean("signalPostponementFlagUp",false)) return
        val wasUp=displayPrefs.getBoolean("signalIndividualRecallFlagUp",false)
        if(!wasUp) {
            displayPrefs.edit().putBoolean("signalIndividualRecallFlagUp",true).apply()
            playSignalHorn(SignalSequence.individualRecallRaise.hornPulses)
        } else displayPrefs.edit().putBoolean("signalIndividualRecallFlagUp",false).apply()
        updateSignalUi()
    }

    private fun toggleGeneralRecall() {
        val wasUp=displayPrefs.getBoolean("signalGeneralRecallFlagUp",false)
        if(!wasUp) {
            pauseSignalForManualEvent()
            displayPrefs.edit().putBoolean("signalIndividualRecallFlagUp",false).putBoolean("signalPostponementFlagUp",false)
                .putBoolean("signalRestartMode",false).putLong("signalRestartAt",0L).putBoolean("signalGeneralRecallFlagUp",true).apply()
            playSignalHorn(SignalSequence.generalRecallRaise.hornPulses)
        } else {
            displayPrefs.edit().putBoolean("signalGeneralRecallFlagUp",false).putBoolean("signalRestartMode",true)
                .putLong("signalRestartAt",signalNow()+60_000L).putLong("signalRestartPausedElapsedMs",-1L).putInt("signalLastFiredIndex",-1).apply()
            playSignalHorn(SignalSequence.generalRecallLower.hornPulses)
        }
        signalActiveIndex=-1;buildSignalRows();updateSignalUi()
    }

    private fun togglePostponement() {
        val wasUp=displayPrefs.getBoolean("signalPostponementFlagUp",false)
        if(!wasUp) {
            pauseSignalForManualEvent()
            displayPrefs.edit().putBoolean("signalIndividualRecallFlagUp",false).putBoolean("signalGeneralRecallFlagUp",false)
                .putBoolean("signalRestartMode",false).putLong("signalRestartAt",0L).putBoolean("signalPostponementFlagUp",true).apply()
            playSignalHorn(SignalSequence.postponementRaise.hornPulses)
        } else {
            displayPrefs.edit().putBoolean("signalPostponementFlagUp",false).putBoolean("signalRestartMode",true)
                .putLong("signalRestartAt",signalNow()+60_000L).putLong("signalRestartPausedElapsedMs",-1L).putInt("signalLastFiredIndex",-1).apply()
            playSignalHorn(SignalSequence.postponementLower.hornPulses)
        }
        signalActiveIndex=-1;buildSignalRows();updateSignalUi()
    }

    private fun resetSignalSequence() {
        displayPrefs.edit().remove("signalElapsedStartAt").remove("signalPausedElapsedMs").remove("signalLastFiredIndex")
            .remove("signalOrangeManualOverride").remove("signalOrangeManualUp")
            .remove("signalRestartAt").remove("signalRestartPausedElapsedMs")
            .putBoolean("signalRestartMode",false).putBoolean("signalIndividualRecallFlagUp",false)
            .putBoolean("signalGeneralRecallFlagUp",false).putBoolean("signalPostponementFlagUp",false).apply()
        signalActiveIndex=-1;buildSignalRows();updateSignalUi()
    }

    private fun toggleSignalSequence() {
        if(displayPrefs.getBoolean("signalGeneralRecallFlagUp",false) || displayPrefs.getBoolean("signalPostponementFlagUp",false)) return
        val now=signalNow()
        val events=currentSignalEvents()
        val totalMs=(events.lastOrNull()?.secondsAfterStart ?: 0)*1000L
        if(displayPrefs.getBoolean("signalRestartMode",false)) {
            val restartAt=displayPrefs.getLong("signalRestartAt",0L)
            val paused=displayPrefs.getLong("signalRestartPausedElapsedMs",-1L)
            when {
                restartAt>now -> return
                restartAt>0L && now-restartAt<totalMs -> displayPrefs.edit().putLong("signalRestartPausedElapsedMs",now-restartAt).remove("signalRestartAt").apply()
                paused>=0L && paused<totalMs -> displayPrefs.edit().putLong("signalRestartAt",now-paused).remove("signalRestartPausedElapsedMs").apply()
                else -> displayPrefs.edit().putLong("signalRestartAt",now).putLong("signalRestartPausedElapsedMs",-1L).putInt("signalLastFiredIndex",-1)
                    .remove("signalOrangeManualOverride").remove("signalOrangeManualUp").apply()
            }
        } else {
            val startAt=displayPrefs.getLong("signalElapsedStartAt",0L)
            val paused=displayPrefs.getLong("signalPausedElapsedMs",-1L)
            val elapsed=if(startAt>0L) (now-startAt).coerceAtLeast(0L) else paused
            when {
                startAt>0L && elapsed<totalMs -> displayPrefs.edit().putLong("signalPausedElapsedMs",elapsed).remove("signalElapsedStartAt").apply()
                paused>=0L && paused<totalMs -> displayPrefs.edit().putLong(
                    "signalElapsedStartAt",
                    if(paused==0L) SignalTiming.scheduledStartAt(now,displayPrefs.getInt("signalMinimumTimeToFirstAction",15))
                    else now-paused
                ).remove("signalPausedElapsedMs").apply()
                else -> {
                    val hadCompleted = paused>=totalMs || (startAt>0L && elapsed>=totalMs)
                    displayPrefs.edit().putLong("signalElapsedStartAt",SignalTiming.scheduledStartAt(now,displayPrefs.getInt("signalMinimumTimeToFirstAction",15)))
                        .remove("signalPausedElapsedMs").putInt("signalLastFiredIndex",-1).apply()
                    if(hadCompleted) displayPrefs.edit().remove("signalOrangeManualOverride").remove("signalOrangeManualUp").apply()
                }
            }
        }
        signalActiveIndex=-1
        updateSignalUi()
    }

    private fun playSignalHorn(pulses: List<Int>) {
        if (pulses.isEmpty() || !displayPrefs.getBoolean("signalHornEnabled",true)) return
        val volume=displayPrefs.getInt("signalHornVolume",80).coerceIn(0,100)
        if(volume==0) return
        val tone = ToneGenerator(AudioManager.STREAM_MUSIC, volume)
        val longMs = displayPrefs.getInt("signalHornMs", 700).coerceIn(100, 5000)
        val shortMs = displayPrefs.getInt("signalShortHornMs",220).coerceIn(100,1000)
        val gapMs = displayPrefs.getInt("signalGapMs",180).coerceIn(100,2000)
        val sequence = mutableListOf<Pair<Int, Int>>()
        pulses.forEachIndexed { index, pulse ->
            sequence += ToneGenerator.TONE_PROP_BEEP to (if (pulse == 0) shortMs else longMs)
            if (index < pulses.lastIndex) sequence += ToneGenerator.TONE_PROP_BEEP to gapMs
        }
        fun playAt(index: Int) {
            if (index >= sequence.size) {
                tone.release()
                return
            }
            val (toneType, duration) = sequence[index]
            tone.startTone(toneType, duration)
            uiHandler.postDelayed({ tone.stopTone(); playAt(index + 1) }, duration.toLong())
        }
        playAt(0)
    }

    private fun syncNictClock() {
        b.btnNictSync.isEnabled=false;b.tvNictStatus.text="ntp.nict.jp に接続中…"
        NictClock.query { result -> runOnUiThread {
            b.btnNictSync.isEnabled=true
            result.onSuccess { offset -> signalClockOffsetMs=offset;b.tvNictStatus.text="ntp.nict.jp 同期済み（差 ${if(offset>=0) "+" else ""}${offset} ms）";updateSignalUi() }
                .onFailure { b.tvNictStatus.text="NTP同期失敗・端末時刻を使用中";Toast.makeText(this,"NTP同期に失敗しました",Toast.LENGTH_LONG).show() }
        } }
    }
    private fun updateSignalUi() {
        if(!::b.isInitialized) return
        val now=signalNow()
        val restartMode=displayPrefs.getBoolean("signalRestartMode",false)
        val restartAt=displayPrefs.getLong("signalRestartAt",0L)
        val restartPaused=displayPrefs.getLong("signalRestartPausedElapsedMs",-1L)
        val waitingForRestart=restartMode && restartAt>now
        val profileIndex=displayPrefs.getInt("signalFlagProfileIndex",0).coerceIn(0,SignalSequence.profiles.lastIndex)
        val duration=currentSignalDurationMinutes()
        val prepFlag=displayPrefs.getString("signalPrepFlag","P") ?: "P"
        val events=currentSignalEvents()
        val totalSeconds=events.lastOrNull()?.secondsAfterStart ?: 0
        val normalStartAt=displayPrefs.getLong("signalElapsedStartAt",0L)
        val normalPaused=displayPrefs.getLong("signalPausedElapsedMs",-1L)
        val waitingForFirstSignal=!restartMode && normalStartAt>now
        val startAt=if(restartMode) restartAt else normalStartAt
        val elapsedMs=when {
            restartMode && restartAt>0L -> (now-restartAt).coerceAtLeast(0L)
            restartMode && restartPaused>=0L -> restartPaused
            normalStartAt>0L -> (now-normalStartAt).coerceAtLeast(0L)
            normalPaused>=0L -> normalPaused
            else -> 0L
        }
        val elapsedSeconds=elapsedMs/1000.0
        val started=restartMode || normalStartAt>0L || normalPaused>=0L
        val running=if(waitingForRestart) false else if(restartMode) restartAt>0L && elapsedSeconds<totalSeconds else normalStartAt>0L && elapsedSeconds<totalSeconds
        val completed=started && !waitingForRestart && elapsedSeconds>=totalSeconds
        val active=when {
            waitingForRestart -> 0
            waitingForFirstSignal || !started -> -1
            else -> SignalTiming.activeEventIndex(elapsedSeconds,events.map { it.secondsAfterStart }).coerceIn(0,events.lastIndex)
        }
        val event=events[active.coerceAtLeast(0)]
        if(started && !waitingForRestart && active!=signalActiveIndex && events.getOrNull(active)?.flag=="橙") {
            displayPrefs.edit().remove("signalOrangeManualOverride").remove("signalOrangeManualUp").apply()
        }
        val clock=java.text.SimpleDateFormat("HH:mm:ss",java.util.Locale.JAPAN).format(java.util.Date(now))
        val displayedStart=when {
            waitingForRestart -> restartAt
            restartMode && restartAt>0L -> restartAt
            restartMode && restartPaused>=0L -> now-restartPaused
            normalStartAt>0L -> normalStartAt
            normalPaused>=0L -> now-normalPaused
            else -> 0L
        }
        b.tvSignalClock.text=clock
        b.tvSignalStartAt.text="Start at  " + if(started) java.text.SimpleDateFormat("HH:mm:ss",java.util.Locale.JAPAN).format(java.util.Date(displayedStart)) else "TBD"
        b.tvSignalTitle.text=if(waitingForFirstSignal) "0秒待ち · ${event.title}" else event.title
        b.tvSignalTitle.setBackgroundColor(event.color)
        b.tvSignalTitle.setTextColor(if(android.graphics.Color.luminance(event.color)<0.45f) Color.WHITE else Color.BLACK)
        val shownSeconds=when {
            waitingForRestart -> (restartAt-now).coerceAtLeast(0L)/1000.0
            waitingForFirstSignal -> (normalStartAt-now).coerceAtLeast(0L)/1000.0
            else -> elapsedSeconds
        }
        b.tvSignalCountdown.text=if(!started) "--:--" else "%02d:%02d".format(shownSeconds.toInt()/60,shownSeconds.toInt()%60)
        b.tvSignalNextLabel.text=when {waitingForRestart->"次の予告信号まで";waitingForFirstSignal->"0秒まで";!started->"開始待ち";completed->"シーケンス終了";!running->"一時停止 · 経過時間";else->"経過時間"}
        val orangeEnabled=displayPrefs.getBoolean("signalOrangeEnabled",true)
        val raised=when {
            waitingForRestart && orangeEnabled -> mutableListOf(SignalFlagState("橙",0xFFF58A00.toInt(),true,false))
            waitingForFirstSignal || !started -> mutableListOf()
            else -> SignalSequence.flagsAtEvents(events,elapsedSeconds).filter { it.raised }.toMutableList()
        }
        val orangeDownAt=300 + displayPrefs.getInt("signalOrangeRemovedAfterMinutes",4).coerceIn(0,30)*60
        if(orangeEnabled && restartMode && !waitingForRestart && elapsedSeconds<orangeDownAt && raised.none { it.id=="橙" }) raised+=SignalFlagState("橙",0xFFF58A00.toInt(),true,false)
        if(displayPrefs.getBoolean("signalGeneralRecallFlagUp",false)) raised+=SignalFlagState("第一代表",0xFF1769FF.toInt(),true,false)
        if(displayPrefs.getBoolean("signalPostponementFlagUp",false)) raised+=SignalFlagState("AP",0xFFD71920.toInt(),true,false)
        if(displayPrefs.getBoolean("signalIndividualRecallFlagUp",false)) raised+=SignalFlagState("X",0xFFFFFFFF.toInt(),true,false)
        displayPrefs.edit().putBoolean("signalOrangeDisplayedUp",raised.any { it.id=="橙" }).apply()
        if(displayPrefs.getBoolean("signalOrangeManualOverride",false)) {
            raised.removeAll { it.id=="橙" }
            if(displayPrefs.getBoolean("signalOrangeManualUp",false)) raised+=SignalFlagState("橙",0xFFF58A00.toInt(),true,false)
        }
        b.btnSignalOrange.text=if(raised.any { it.id=="橙" }) "オレンジ旗 降下" else "オレンジ旗 掲揚"
        b.signalMast.show(raised,running)
        b.btnSignalStart.text=when {waitingForRestart->"再予告待ち";waitingForFirstSignal->"0秒合わせ中（取消）";running->"一時停止";started && !completed->"再開";completed->"再スタート";else->"開始"}
        b.btnSignalStart.isEnabled=!waitingForRestart && !displayPrefs.getBoolean("signalGeneralRecallFlagUp",false) && !displayPrefs.getBoolean("signalPostponementFlagUp",false)
        b.btnSignalIndividualRecall.text=if(displayPrefs.getBoolean("signalIndividualRecallFlagUp",false)) "X旗 降下" else "個別リコール X旗（$prepFlag）"
        b.btnSignalIndividualRecall.isEnabled=!displayPrefs.getBoolean("signalGeneralRecallFlagUp",false) && !displayPrefs.getBoolean("signalPostponementFlagUp",false)
        b.btnSignalGeneralRecall.text=if(displayPrefs.getBoolean("signalGeneralRecallFlagUp",false)) "第一代表旗 降下" else "ゼネラルリコール"
        b.btnSignalPostponement.text=if(displayPrefs.getBoolean("signalPostponementFlagUp",false)) "AP 降下" else "AP 掲揚"

        val lastFired=displayPrefs.getInt("signalLastFiredIndex",-1)
        if(running && active>lastFired) {
            for(index in (lastFired+1)..active) {
                if(index !in events.indices) continue
                val eventAt=startAt+events[index].secondsAfterStart*1000L
                if(now-eventAt in 0L..1500L) playSignalHorn(events[index].hornPulses)
            }
            displayPrefs.edit().putInt("signalLastFiredIndex",active).apply()
        }
        if(active!=signalActiveIndex) {
            signalRows.forEachIndexed { index,row ->
                row.setBackgroundColor(if(index==active) 0xff75c879.toInt() else 0xffeeeeee.toInt())
                row.animate().cancel()
                row.alpha=if(index==active && running) 0.78f else 1f
                if(index==active && running) row.animate().alpha(1f).setDuration(180).start()
            }
            signalActiveIndex=active
        }
        if(completed && !restartMode) displayPrefs.edit().remove("signalElapsedStartAt").putLong("signalPausedElapsedMs",totalSeconds*1000L).apply()
    }

    private fun setDisplayMode(navigator:Boolean)=setDisplayMode(if(navigator) 1 else 0)
    private fun setDisplayMode(requestedMode:Int) {
        val mode=requestedMode.coerceIn(0,4)
        val immersive=mode>=2
        val wasImmersive=currentDisplayMode>=2
        val content=b.focusPanel.parent as LinearLayout
        if(immersive && !wasImmersive) {
            focusHiddenVisibility.clear()
            for(index in 1 until content.childCount) {
                val view=content.getChildAt(index)
                if(view!=b.focusPanel && view!=b.timerPanel) focusHiddenVisibility[view]=view.visibility
            }
        }
        if(!immersive && wasImmersive) {
            focusHiddenVisibility.forEach{(view,visibility)->view.visibility=visibility}
            focusHiddenVisibility.clear()
        }
        currentDisplayMode=mode
        val navigator=mode==1
        navigatorMode = navigator
        if (navigator && mapPanel == null) {
            mapPanel = NavigationMapPanel(this, b.mapContainer, { debug(it) }, { lat, lon -> showMapOperations(lat, lon) }) { waypoint -> editWaypoint(waypoint) }
            mapPanel?.onFollowingChanged = { following -> b.btnFollow.text = if (following) "追従 1cm≒200m" else "再度中心に配置" }
            mapPanel?.setDisplayOptions(displayPrefs.getBoolean("showWaypoints", true), displayPrefs.getBoolean("showCourse", true))
            mapPanel?.setWaypoints(waypoints, activeWaypoint)
            mapPanel?.setFeatures(library.features.filter { it.visible && it.group !in library.hiddenGroups },waypoints)
            updateMap()
            mapPanel?.resume()
        }
        b.speedPanel.visibility = if (navigator || immersive) android.view.View.GONE else android.view.View.VISIBLE
        b.navigatorPanel.visibility = if (navigator) android.view.View.VISIBLE else android.view.View.GONE
        b.tvModeTitle.text = when(mode) { 1 -> "ナビゲーション"; 2 -> "セーリング"; 3 -> "タイマー"; 4 -> "シグナル"; else -> "スピードメーター" }
        if(immersive) focusHiddenVisibility.keys.forEach{it.visibility=android.view.View.GONE}
        b.focusPanel.visibility=if(mode==2) android.view.View.VISIBLE else android.view.View.GONE
        b.timerPanel.visibility=if(mode==3) android.view.View.VISIBLE else android.view.View.GONE
        b.signalPanel.visibility=if(mode==4) android.view.View.VISIBLE else android.view.View.GONE
        if(mode==2) b.focusPanel.layoutParams=b.focusPanel.layoutParams.apply {height=maxOf((480*resources.displayMetrics.density).toInt(),resources.displayMetrics.heightPixels-(150*resources.displayMetrics.density).toInt())}
        b.btnSpeedMode.isEnabled = mode!=0
        b.btnNavigatorMode.isEnabled = mode!=1
        b.btnFocusMode.isEnabled=mode!=2
        b.btnTimerMode.isEnabled=mode!=3
        b.btnSignalMode.isEnabled=mode!=4
        b.btnFocusNorth.visibility=if(mode==2) android.view.View.VISIBLE else android.view.View.GONE
        b.btnFocusMenu.visibility=if(immersive) android.view.View.VISIBLE else android.view.View.GONE
        displayPrefs.edit().putBoolean("navigator", navigator).putInt("displayMode",mode).apply()
        updateNavigationUi()
        debug("Display mode=" + when(mode){0->"SPEEDOMETER";1->"NAVIGATOR";2->"FOCUS";3->"START_TIMER";else->"SIGNAL"})
        if(mode==4) updateSignalUi()
    }

    private fun captureStartLineEndpoint(kind:String) {
        val age=(android.os.SystemClock.elapsedRealtime()-latestFixAt)/1000.0
        val lat=latestLat; val lon=latestLon
        if(lat==null || lon==null || age !in 0.0..15.0) {
            Toast.makeText(this,"現在地GPSを取得してから登録してください",Toast.LENGTH_LONG).show()
            return
        }
        val prefix=if(kind=="outer") "startLine.outer" else "startLine.signal"
        displayPrefs.edit().putBoolean("${prefix}.set",true).putString("${prefix}.lat",lat.toString()).putString("${prefix}.lon",lon.toString()).apply()
        val label=if(kind=="outer") "アウターマーク" else "シグナルボート"
        saveStartLineWaypoint(kind, lat, lon)
        Toast.makeText(this,"${label}をナビのウェイポイントに追加しました",Toast.LENGTH_SHORT).show()
        updateStartTimerUi()
    }

    private fun saveStartLineWaypoint(kind:String, lat:Double, lon:Double) {
        val isOuter = kind == "outer"
        val name = if(isOuter) "アウターマーク" else "シグナルボート"
        val idKey = "startLine.${kind}.waypointId"
        val id = displayPrefs.getString(idKey, null) ?: java.util.UUID.randomUUID().toString()
        val group = mainWaypointFolder
        val waypoint = Waypoint(
            id = id,
            name = name,
            lat = lat,
            lon = lon,
            mark = if(isOuter) "ブイ" else "🚢",
            color = if(isOuter) "#FFAA00" else "#00C8D7",
            note = "スタートライン基準点",
            archiveMark = if(isOuter) "symbol:marine.buoy" else "symbol:ferry.fill",
            group = group
        )
        val index = waypoints.indexOfFirst { it.id == id }
        if(index >= 0) {
            waypoints[index] = waypoint
            if(activeWaypoint?.id == id) activeWaypoint = waypoint
        } else {
            waypoints += waypoint
        }
        displayPrefs.edit().putString(idKey, id).apply()
        waypointStore.saveAll(waypoints)
        renderWaypointList()
        updateNavigationUi()
    }

    private fun toggleStartTimer() {
        val now=System.currentTimeMillis()
        val end=displayPrefs.getLong("startTimerEndAt",0L)
        val paused=displayPrefs.getLong("startTimerPausedSeconds",0L)
        if(end>now) {
            displayPrefs.edit().putLong("startTimerPausedSeconds",((end-now+999)/1000).coerceAtLeast(1)).remove("startTimerEndAt").apply()
        } else {
            val duration=if(paused>0) paused else listOf(1,3,5,10).getOrElse(b.startTimerPreset.selectedItemPosition){5}*60L
            displayPrefs.edit().putLong("startTimerEndAt",now+duration*1000).remove("startTimerPausedSeconds").apply()
        }
        updateStartTimerUi()
    }

    private fun updateStartTimerUi() {
        if(!::b.isInitialized) return
        val now=System.currentTimeMillis()
        val end=displayPrefs.getLong("startTimerEndAt",0L)
        val paused=displayPrefs.getLong("startTimerPausedSeconds",0L)
        val remaining=if(end>now) (end-now)/1000.0 else paused.toDouble()
        val running=end>now
        val finished=end>0L && !running && paused<=0L
        b.tvStartCountdown.text=if(finished) "START" else StartLineMath.countdown(remaining)
        b.tvStartCountdown.setTextColor(if(finished) Color.rgb(255,170,0) else Color.GREEN)
        b.btnStartTimer.text=if(running) "一時停止" else if(paused>0) "再開" else "開始"
        fun endpoint(prefix:String):StartLineCoordinate? {
            if(!displayPrefs.getBoolean("${prefix}.set",false)) return null
            val lat=displayPrefs.getString("${prefix}.lat",null)?.toDoubleOrNull() ?: return null
            val lon=displayPrefs.getString("${prefix}.lon",null)?.toDoubleOrNull() ?: return null
            return StartLineCoordinate(lat,lon)
        }
        val outer=endpoint("startLine.outer"); val signal=endpoint("startLine.signal")
        b.tvOuterMark.text=if(outer==null) "アウターマーク：未設定" else "アウターマーク：%.5f, %.5f".format(outer.latitude,outer.longitude)
        b.tvSignalBoat.text=if(signal==null) "シグナルボート：未設定" else "シグナルボート：%.5f, %.5f".format(signal.latitude,signal.longitude)
        val distance=if(latestLat!=null && latestLon!=null) StartLineMath.distanceMeters(StartLineCoordinate(latestLat!!,latestLon!!),outer,signal) else null
        b.tvStartLineDistance.text=distance?.let {
            if(metricUnits) "スタートラインまで %.0f m".format(it) else "スタートラインまで %.2f nm  ·  %.0f m".format(it/1852.0,it)
        } ?: "スタートラインまで --"
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
                ZoneAlerts.check(this@MainActivity,location)
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
        b.tvStatus.text = "状態：${if (running) "記録中" else "停止中"} / 保存点数：$pointCount" + if(gpsGapSeconds>0) " / GPS欠落あり（最大${gpsGapSeconds}秒）" else ""
        b.tvStatus.setTextColor(if (gpsGapSeconds>0) Color.YELLOW else if (running) Color.rgb(0, 255, 56) else Color.WHITE)
        b.btnStart.visibility = if (running) android.view.View.GONE else android.view.View.VISIBLE
        b.btnStop.visibility = if (running) android.view.View.VISIBLE else android.view.View.GONE
        b.btnStart.isEnabled = !running
        b.btnStop.isEnabled = running
    }

    private fun updateNavigationUi() {
        if(currentDisplayMode==3) updateStartTimerUi()
        val threshold=(displayPrefs.getString("zeroSpeedThreshold","0")?.toDoubleOrNull() ?: 0.0)/NavigationUtils.MPS_TO_KT
        val speed = latestSpeedMps?.takeIf { it.isFinite() && it >= 0 }?.let{if(it<threshold) 0.0 else it}?.times(if (metricUnits) 3.6 else NavigationUtils.MPS_TO_KT)
        val unit = if (metricUnits) "km/h" else "knot"
        b.tvSpeedUnit.text = "SOG · $unit"
        b.tvSog.text = speed?.let { "%.1f %s".format(it, unit) } ?: "-- $unit"
        b.tvLargeSpeed.largeDecimal=displayPrefs.getBoolean("largeDecimal",true)
        b.tvLargeSpeed.speedValue = if(BuildConfig.DEBUG && intent.hasExtra("previewSpeed")) intent.getStringExtra("previewSpeed")?.toDoubleOrNull() else speed
        b.tvLargeSpeed.contentDescription = "対地速度 ${b.tvSog.text}"
        b.tvPosition.text = if (latestLat != null && latestLon != null)
            "${displayCoordinate(latestLat!!, true)}   ${displayCoordinate(latestLon!!, false)}"
            else "現在地：GPS受信待ち"
        val reference = headingReference()
        val heading = reference?.heading
        val source = if (reference == null) "未取得" else if (reference.magnetic) "磁気コンパス（MAG）" else "GPS対地針路（COG）"
        b.tvCog.text = heading?.let { "${NavigationUtils.normalize360(it).roundToInt() % 360}°" } ?: "--°"
        b.tvHeadingSource.text = "方位ソース：$source"

        val age=(android.os.SystemClock.elapsedRealtime()-latestFixAt)/1000.0
        val fresh=latestFixAt>0 && age in 0.0..15.0
        val preview=BuildConfig.DEBUG && intent.getBooleanExtra("previewFocus",false)
        if(::focusSog.isInitialized) {
            val label=(focusSog.parent as LinearLayout).getChildAt(0) as TextView;label.text="SOG / $unit"
            focusSog.text=if(preview) "12.3" else if(fresh) speed?.let{"%.1f".format(java.util.Locale.US,it)} ?: "—" else "—"
            val useMagnetic=displayPrefs.getBoolean("instrumentMagnetic",false)
            b.btnFocusNorth.text=if(useMagnetic) "磁北" else "真北"
            val compassAge=(android.os.SystemClock.elapsedRealtime()-minOf(magneticSampleAt,accelSampleAt))/1000.0
            val compass=if(preview) 218.0 else magneticHeading?.takeIf{magneticSampleAt>0 && accelSampleAt>0 && compassAge in 0.0..15.0 && compassAccuracy>SensorManager.SENSOR_STATUS_UNRELIABLE}
            val correction=if(preview) -8.0 else if(latestLat!=null && latestLon!=null) GeomagneticField(latestLat!!.toFloat(),latestLon!!.toFloat(),0f,System.currentTimeMillis()).declination.toDouble() else null
            val reading=InstrumentHeading.resolve(if(preview) 82.0 else InstrumentSettings.course(latestGpsBearing,latestSpeedMps,age),if(preview) 3.0 else if(fresh) latestSpeedMps else null,compass,correction,useMagnetic)
            ((focusCog.parent as LinearLayout).getChildAt(0) as TextView).text=(if(reading?.compass==true) "コンパス方位" else "COG")+(if(useMagnetic) "（磁北）" else "（真北）")
            focusCog.text=reading?.value?.let{"${it.roundToInt()%360}°"} ?: "—"
            val target=activeWaypoint
            val targetBearing=if(preview) 144.0 else if(fresh && target!=null && latestLat!=null && latestLon!=null && NavigationUtils.distanceMeters(latestLat!!,latestLon!!,target.lat,target.lon)>1)
                NavigationUtils.bearingDegrees(latestLat!!,latestLon!!,target.lat,target.lon) else null
            ((focusBearing.parent as LinearLayout).getChildAt(0) as TextView).text="目標方位"+(if(useMagnetic) "（磁北）" else "（真北）")
            focusBearing.text=InstrumentHeading.bearing(targetBearing,useMagnetic,correction)?.let{"${it.roundToInt()%360}°"} ?: "—"
        }
        val wp = activeWaypoint
        b.tvEte.text = "ETE\n--:--:--"
        val lat = latestLat
        val lon = latestLon
        if (wp == null || lat == null || lon == null) {
            b.tvDistance.text = if (metricUnits) "-- m/km" else "-- nm"
            b.tvDistanceSub.text = "-- m"
            b.tvClock.text = "--時方向"
            b.tvWpName.text = wp?.name ?: "未設定"
            b.tvWpCoords.text = wp?.let { "${displayCoordinate(it.lat,true)}\n${displayCoordinate(it.lon,false)}" } ?: "--"
            b.instrumentView.update(null, null, heading, reference?.magnetic == true)
            return
        }

        val distanceM = NavigationUtils.distanceMeters(lat, lon, wp.lat, wp.lon)
        val bearing = NavigationUtils.bearingDegrees(lat, lon, wp.lat, wp.lon)
        val estimateSpeed=if(displayPrefs.getBoolean("arrivalUsesAverage",false)) tripAverageSpeed() else latestSpeedMps
        val eta=displayPrefs.getBoolean("showETA",false)
        b.tvEte.text = (if(eta) "ETA\n" else "ETE\n")+InstrumentSettings.arrival(distanceM,estimateSpeed,System.currentTimeMillis(),eta,displayPrefs.getBoolean("twelveHourClock",false))
        b.tvDistance.text = DisplayNavigation.distance(distanceM, metricUnits)
        b.tvDistanceSub.text = ""
        b.tvWpName.text = wp.name
        b.tvWpCoords.text = "${displayCoordinate(wp.lat,true)}\n${displayCoordinate(wp.lon,false)}"

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
        val wp = Waypoint(name = name, lat = lat, lon = lon, mark = draftMark, color = draftColor, group = mainWaypointFolder)
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
    private fun updateDefaultFolderSetting() {
        b.btnDefaultWaypointFolder.text = "デフォルトの保存先：$mainWaypointFolder ★デフォルト"
        b.btnDefaultWaypointFolder.setOnClickListener {
            val folders = waypointFolders
            androidx.appcompat.app.AlertDialog.Builder(this)
                .setTitle("デフォルトの保存先")
                .setSingleChoiceItems(folders.map { it + if (it == mainWaypointFolder) " ★デフォルト" else "" }.toTypedArray(), folders.indexOf(mainWaypointFolder)) { dialog, index ->
                    displayPrefs.edit().putString("mainWaypointFolder", folders[index]).apply()
                    renderWaypointList()
                    updateDefaultFolderSetting()
                    Toast.makeText(this, "新規ポイントの保存先：${folders[index]}", Toast.LENGTH_SHORT).show()
                    dialog.dismiss()
                }
                .setNegativeButton("キャンセル", null).show()
        }
    }
    private fun displayCoordinate(value:Double,isLat:Boolean)=InstrumentSettings.coordinate(value,isLat,displayPrefs.getString("coordinateFormat","dm") ?: "dm")
    private fun tripAverageSpeed():Double? {
        val counter=getSharedPreferences("tripCounter",MODE_PRIVATE)
        val duration=counter.getString("seconds","0")?.toDoubleOrNull() ?: 0.0
        val distance=counter.getString("distance","0")?.toDoubleOrNull() ?: 0.0
        return if(duration>0) distance/duration else null
    }
    private fun showSettings() {
        DetailedSettings(this,library,waypointFolders,mainWaypointFolder,b.tvGpsInfo.text.toString()) {
            if(displayPrefs.getBoolean("keepScreenAwake",false)) window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            else window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            mapPanel?.setDisplayOptions(displayPrefs.getBoolean("showWaypoints",true),displayPrefs.getBoolean("showCourse",true))
            updateDefaultFolderSetting();renderWaypointList();updateNavigationUi()
        }.show()
    }
    private fun showWaypointInputs() {
        updateDefaultFolderSetting()
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
            "新規ウェイポイント" to { pendingNavigation = true; showWaypointInputs(); b.etWpName.requestFocus() },
            "既存ウェイポイント（近い順）" to { showTargetList(true) },
            "既存ウェイポイント（最近）" to { showTargetList(false) },
            "目標なし" to { clearTarget() }
        ))
    }
    private fun showTargetList(nearest: Boolean, folder: String = mainWaypointFolder) {
        val lat = latestLat; val lon = latestLon
        val ordered = if (nearest && lat != null && lon != null) waypoints.sortedBy { NavigationUtils.distanceMeters(lat,lon,it.lat,it.lon) } else waypoints.asReversed()
        val actions = ordered.filter{it.group==folder}.map { waypoint ->
            val distance = if (lat != null && lon != null) " · "+DisplayNavigation.distance(NavigationUtils.distanceMeters(lat,lon,waypoint.lat,waypoint.lon), metricUnits) else ""
            ("${waypoint.mark} ${waypoint.name}$distance") to { confirmTarget(waypoint) }
        }
        val folders=waypointFolders
        val changeFolder:Pair<String,()->Unit> = ("フォルダ: ${folder.ifEmpty{"メインフォルダ"}} ▾") to { androidx.appcompat.app.AlertDialog.Builder(this).setTitle("フォルダ").setItems(folders.map{it + if(it==mainWaypointFolder)" ★デフォルト" else ""}.toTypedArray()){_,i->showTargetList(nearest,folders[i])}.show();Unit }
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
            runCatching { waypointStore.saveLibrary(items,updated);waypoints.clear();waypoints.addAll(items.map{if(it.group.isBlank())it.copy(group=mainWaypointFolder)else it});library=updated
                activeWaypoint=waypoints.firstOrNull{it.id==activeWaypoint?.id};renderWaypointList();updateNavigationUi();debug("Map library saved groups=${library.groups.size} features=${library.features.size}") }.onFailure(::transferError)
        },{items,features,format -> runCatching {
            require(items.isNotEmpty() || features.isNotEmpty()) { "出力する地点・図形を選んでください" }
            pendingExport=if(format=="json")WaypointArchive.encode(items)else KmlArchive.encode(items,features,format=="kmz")
            exportWaypointsDocument.launch("SailingGPS-waypoints-${System.currentTimeMillis()}.$format")
        }.onFailure(::transferError) },{importWaypointsDocument.launch(arrayOf("*/*"))}).show()
    }

    private fun showDisplayModePicker() {
        val names=listOf("スピードメーター","ナビゲーション","セーリング","タイマー","シグナル")
        androidx.appcompat.app.AlertDialog.Builder(this)
            .setTitle("モード選択")
            .setSingleChoiceItems(names.toTypedArray(),currentDisplayMode) { dialog, which ->
                setDisplayMode(which)
                dialog.dismiss()
            }
            .setNegativeButton("キャンセル",null)
            .show()
    }

    private fun showNavigationMenu() {
        showActionPanel("メニュー", listOf(
            "目標" to { showNavigationOptions() }, "新規ウェイポイント" to { pendingNavigation = false; showWaypointInputs() },
            "ウェイポイント（近い順）" to { showTargetList(true) }, "現在地に打つ（保存先：$mainWaypointFolder）" to { addCurrentLocationWaypoint() },
            "記録開始" to { startGpsLogging() }, "記録停止" to { stopGpsLogging() },
            "地点・グループ・エリア" to { showMapLibrary() },
            "WPインポート" to { importWaypointsDocument.launch(arrayOf("*/*")) },
            "GPX出力" to { exportGpx() }, "設定" to { showSettings() },
            "航跡一覧" to { showTrackList() },
            "モード" to { showDisplayModePicker() }, "全ウェイポイント" to { mapPanel?.showWaypoints() }
        ))
    }

    private fun showTrackList() {
        val files = GpsLoggingService.allTrackFiles(this).reversed()
        if (files.isEmpty()) { Toast.makeText(this, "保存済みの航跡はありません", Toast.LENGTH_SHORT).show(); return }
        val active = GpsLoggingService.activeSessionFile(this).takeIf { it.exists() }?.readText()?.trim()
        val list = android.widget.LinearLayout(this).apply { orientation = android.widget.LinearLayout.VERTICAL; setPadding(12, 8, 12, 8) }
        files.forEach { file ->
            val rows = runCatching { file.readLines().mapNotNull { line ->
                val p=line.split(','); if(p.size<8) null else {
                    val t=p[0].toLongOrNull();val lat=p[1].toDoubleOrNull();val lon=p[2].toDoubleOrNull();val speed=p[6].toDoubleOrNull()
                    if(t==null||lat==null||lon==null) null else listOf(t.toDouble(),lat,lon,speed ?: Double.NaN)
                }
            } }.getOrDefault(emptyList())
            val first=rows.firstOrNull();val last=rows.lastOrNull();var meters=0.0
            rows.zipWithNext().forEach { (a,bp) -> meters+=NavigationUtils.distanceMeters(a[1],a[2],bp[1],bp[2]) }
            val duration=if(first!=null&&last!=null) ((last[0]-first[0])/1000).toLong().coerceAtLeast(0) else 0L
            val speeds=rows.map{it[3]}.filter{it.isFinite()&&it>=0}.map{it*NavigationUtils.MPS_TO_KT}
            val date=first?.let{java.text.SimpleDateFormat("yyyy/MM/dd HH:mm",java.util.Locale.getDefault()).format(java.util.Date(it[0].toLong()))} ?: file.nameWithoutExtension
            val isRecording=running && active==file.name
            val card=android.widget.LinearLayout(this).apply { orientation=android.widget.LinearLayout.VERTICAL;setPadding(12,10,12,10);setBackgroundColor(Color.rgb(24,24,24)) }
            val info=android.widget.LinearLayout(this).apply { orientation=android.widget.LinearLayout.VERTICAL;setPadding(8,0,0,0) }
            info.addView(TextView(this).apply { text=(if(isRecording) "● 記録中  " else "")+date;setTextColor(if(isRecording) Color.GREEN else Color.WHITE);textSize=17f })
            info.addView(TextView(this).apply { text="${"%.2f".format(meters/1852.0)} nm   ${duration/3600}:${"%02d".format((duration/60)%60)}:${"%02d".format(duration%60)}   ${rows.size} 点\n平均 ${if(duration>0) "%.1f".format(meters/duration*NavigationUtils.MPS_TO_KT) else "--"} kt   MAX ${speeds.maxOrNull()?.let{"%.1f".format(it)} ?: "--"} kt";setTextColor(Color.LTGRAY);textSize=14f })
            val summary=android.widget.LinearLayout(this).apply { orientation=android.widget.LinearLayout.HORIZONTAL }
            val coords=rows.map{it[1] to it[2]}
            val thumbnail=object:android.view.View(this){
                private val paint=android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply{color=Color.rgb(238,35,150);strokeWidth=4f;style=android.graphics.Paint.Style.STROKE;strokeCap=android.graphics.Paint.Cap.ROUND;strokeJoin=android.graphics.Paint.Join.ROUND}
                override fun onDraw(canvas:android.graphics.Canvas){super.onDraw(canvas);canvas.drawColor(Color.rgb(10,75,95));if(coords.size<2)return
                    val minX=coords.minOf{it.second};val maxX=coords.maxOf{it.second};val minY=coords.minOf{it.first};val maxY=coords.maxOf{it.first};val dx=(maxX-minX).coerceAtLeast(1e-6);val dy=(maxY-minY).coerceAtLeast(1e-6);val scale=minOf((width-12)/dx,(height-12)/dy);val ox=((width-dx*scale)/2).toFloat();val oy=((height-dy*scale)/2).toFloat();val path=android.graphics.Path()
                    coords.forEachIndexed{i,p->val x=ox+((p.second-minX)*scale).toFloat();val y=height-oy-((p.first-minY)*scale).toFloat();if(i==0)path.moveTo(x,y)else path.lineTo(x,y)};canvas.drawPath(path,paint)
                }
            }
            summary.addView(thumbnail,android.widget.LinearLayout.LayoutParams((72*resources.displayMetrics.density).toInt(),(78*resources.displayMetrics.density).toInt()))
            summary.addView(info,android.widget.LinearLayout.LayoutParams(0,-2,1f));card.addView(summary)
            val actions=android.widget.LinearLayout(this).apply { orientation=android.widget.LinearLayout.HORIZONTAL }
            actions.addView(Button(this@MainActivity).apply { text="地図";setOnClickListener{setDisplayMode(1);mapPanel?.showTrackFile(file);Toast.makeText(this@MainActivity,date,Toast.LENGTH_SHORT).show()} })
            actions.addView(Button(this@MainActivity).apply { text="GPX";setOnClickListener{exportGpx(file)} })
            actions.addView(Button(this@MainActivity).apply { text="削除";isEnabled=!isRecording;setOnClickListener{androidx.appcompat.app.AlertDialog.Builder(this@MainActivity).setTitle("航跡を削除").setMessage("$date の航跡を削除しますか？").setNegativeButton("キャンセル",null).setPositiveButton("削除"){_,_->file.delete();showTrackList()}.show()} })
            card.addView(actions)
            list.addView(card,android.widget.LinearLayout.LayoutParams(-1,-2).apply{bottomMargin=10})
        }
        val scroll=android.widget.ScrollView(this).apply{addView(list)}
        androidx.appcompat.app.AlertDialog.Builder(this).setTitle("航跡一覧（${files.size}件）").setView(scroll).setNegativeButton("閉じる",null).show()
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
                val wp = Waypoint(name = input.text.toString().trim().ifEmpty { "地点 ${waypoints.size + 1}" }, lat = lat, lon = lon, mark = draftMark, color = draftColor, group = mainWaypointFolder)
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
        val wp = Waypoint(name = name, lat = lat, lon = lon, mark = draftMark, color = draftColor, group = mainWaypointFolder)
        waypoints += wp
        activeWaypoint = wp
        waypointStore.saveAll(waypoints)
        waypointStore.setActiveId(wp.id)
        clearWaypointInputs()
        renderWaypointList()
        updateNavigationUi()
        mapPanel?.showWaypoints()
        Toast.makeText(this, "$name を「${wp.group}」に保存しました", Toast.LENGTH_SHORT).show()
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
        val folders=(waypointFolders+listOf(original.group,mainWaypointFolder)).filter{it.isNotBlank()}.distinct().sorted()
        val folder=android.widget.Spinner(this).apply { adapter=android.widget.ArrayAdapter(this@MainActivity,android.R.layout.simple_spinner_dropdown_item,folders.map{it + if(it==mainWaypointFolder)" ★デフォルト" else ""});setSelection(folders.indexOf(original.group).coerceAtLeast(0)) }
        val name = android.widget.EditText(this).apply { setText(original.name); setSingleLine(true) }
        val lat = android.widget.EditText(this).apply { setText(original.lat.toString()); hint = "緯度（十進度）"; inputType = 12290 }
        val lon = android.widget.EditText(this).apply { setText(original.lon.toString()); hint = "経度（十進度）"; inputType = 12290 }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; setPadding(24,8,24,8)
            addView(TextView(this@MainActivity).apply { text = "名前" }); addView(name)
            addView(TextView(this@MainActivity).apply { text = "保存フォルダ" });addView(folder)
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
                val changed = original.copy(name = name.text.toString().trim().ifEmpty { original.name }, lat = latitude, lon = longitude, mark = mark, color = color, group = folders[folder.selectedItemPosition])
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
    private val waypointFolders: List<String> get() = (library.groups+waypoints.map{it.group}).filter{it.isNotBlank()}.distinct().sorted()
    private val mainWaypointFolder: String get() = DefaultWaypointFolder.resolve(displayPrefs.getString("mainWaypointFolder",null),library.groups,waypoints.map{it.group})
    private fun renderWaypointList() {
        mapPanel?.setWaypoints(waypoints, activeWaypoint)
        mapPanel?.setFeatures(library.features.filter { it.visible && it.group !in library.hiddenGroups },waypoints)
        if(waypointFolder !in waypointFolders)waypointFolder=mainWaypointFolder
        b.waypointContainer.removeAllViews()
        b.waypointContainer.addView(Button(this).apply {
            text = if (activeWaypoint == null) "目標なし（選択中）" else "目標なし"
            setOnClickListener { clearTarget() }
        })
        b.waypointContainer.addView(TextView(this).apply { text="現在地WPの保存先：$mainWaypointFolder";setTextColor(Color.rgb(255,170,0)) })
        val folders=waypointFolders
        b.waypointContainer.addView(Button(this).apply {
            text="フォルダ: ${waypointFolder.ifEmpty{"メインフォルダ"}} ▾"
            setOnClickListener { androidx.appcompat.app.AlertDialog.Builder(this@MainActivity).setTitle("フォルダ").setItems(folders.map{it + if(it==mainWaypointFolder)" ★デフォルト" else ""}.toTypedArray()){_,i->waypointFolder=folders[i];renderWaypointList()}.show() }
        })
        b.waypointContainer.addView(Button(this).apply { text=if(waypointFolder==mainWaypointFolder)"このフォルダがデフォルトです" else "このフォルダをデフォルトにする";isEnabled=waypointFolder!=mainWaypointFolder;setOnClickListener{displayPrefs.edit().putString("mainWaypointFolder",waypointFolder).apply();renderWaypointList()} })
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
                text = "${wp.mark} ${wp.name}\n${displayCoordinate(wp.lat,true)} / ${displayCoordinate(wp.lon,false)}"
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

    private fun exportGpx(source: java.io.File = GpsLoggingService.trackFile(this)) {
        try {
            val file = GpxExporter.export(this, waypoints, source)
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
        getSharedPreferences("tripCounter",MODE_PRIVATE).edit().clear().apply()
        mapPanel?.clearTrack()
        pointCount = 0
        updateStatusUi()
        debug("Track data cleared")
        Toast.makeText(this, "記録データを削除しました", Toast.LENGTH_SHORT).show()
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> {
                accelSampleAt=event.timestamp/1_000_000
                accel = event.values.clone()
                haveAccel = true
            }
            Sensor.TYPE_MAGNETIC_FIELD -> {
                compassAccuracy=event.accuracy
                magneticSampleAt=event.timestamp/1_000_000
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
        if(sensor?.type==Sensor.TYPE_MAGNETIC_FIELD) compassAccuracy=accuracy
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
