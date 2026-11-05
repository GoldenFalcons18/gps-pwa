package com.goldenfalcons.sailinggps

import android.content.Context
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.*
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity

class SignalSettingsActivity : AppCompatActivity() {
    private val prefs by lazy { getSharedPreferences("display", Context.MODE_PRIVATE) }
    private lateinit var list: LinearLayout
    private val white = Color.WHITE
    private val orange = 0xFFFFAA00.toInt()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = 0xFF111111.toInt()
        val page = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(0xFF1C1C1E.toInt()) }
        val header = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(16, 8, 16, 8) }
        header.addView(Button(this).apply { text = "‹"; textSize = 24f; setOnClickListener { finish() } })
        header.addView(TextView(this).apply { text = "Settings"; textSize = 22f; setTextColor(white); gravity = Gravity.CENTER; layoutParams = LinearLayout.LayoutParams(0,-2,1f) })
        header.addView(Button(this).apply { text = "完了"; setTextColor(orange); setOnClickListener { finish() } })
        page.addView(header)
        list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(12, 0, 12, 20) }
        page.addView(ScrollView(this).apply { addView(list) })
        setContentView(page)
        build()
    }

    private fun build() {
        list.removeAllViews()
        section("General Settings")
        row("Mode", "Fleet") {}
        row("Minimum lead time to zero", prefs.getInt("signalMinimumTimeToFirstAction", 15).toString() + "s") { number("次の分00秒までの最短時間", "signalMinimumTimeToFirstAction", 15, 0, 120) }
        row("Voice", prefs.getString("signalVoiceName", "Kyoko (Enhanced)") ?: "") { choose("Voice", listOf("Kyoko (Enhanced)", "端末の標準音声"), "signalVoiceName") }
        row("Notifications", "Management (Radio)") { notifications() }
        row("時刻同期（ntp.nict.jp）", "同期") {
            NictClock.query { result -> runOnUiThread {
                result.onSuccess { offset ->
                    prefs.edit().putLong("signalClockOffsetMs", offset).apply()
                    Toast.makeText(this, "時刻同期しました（差 ${if (offset >= 0) "+" else ""}${offset} ms）", Toast.LENGTH_LONG).show()
                }.onFailure {
                    Toast.makeText(this, "時刻同期に失敗しました。端末時刻を使用します", Toast.LENGTH_LONG).show()
                }
            } }
        }
        row("Horn", if (prefs.getBoolean("signalHornEnabled", true)) "Virtual" else "Disabled") { horn() }
        switch("Remote Flags (alpha)", "signalRemoteFlagsEnabled", false)
        switch("BuoyZone", "signalBuoyZoneLinked", false)
        switch("External Display", "signalExternalDisplayEnabled", true)
        row("Log", "記録設定") { simpleSwitch("Log", "signalLogEnabled", true) }

        section("Fleet Start Sequences")
        val names = prefs.getStringSet("signalFleetPresetNames", setOf("OP Au Bp")) ?: setOf("OP Au Bp")
        val activeFleet = prefs.getString("signalFleetStartName", "OP Au Bp") ?: "OP Au Bp"
        names.sorted().forEach { name -> row(name, if (name == activeFleet) "使用中・編集" else "選択・編集") { fleet(name) } }
        row("＋ Fleet Start", "Add") { addFleet() }

        section("$activeFleet · Starts")
        val storedStarts=prefs.getStringSet("signalStartEntries",setOf("Class · T−5:00 · 掲揚 · 短音")) ?: emptySet()
        val obsoletePrepRows=setOf("P","I","U","Z","BLACK")
        val starts=storedStarts.filterNot { it.substringBefore("·").trim().uppercase() in obsoletePrepRows }.toSet()
        if(starts!=storedStarts) prefs.edit().putStringSet("signalStartEntries",starts).apply()
        starts.forEach { row(it,"−") { val copy=starts.toMutableSet(); copy.remove(it); prefs.edit().putStringSet("signalStartEntries",copy).apply(); build() } }
        row("＋ Add Start…","›") { addStart() }
        section("Class Flags")
        row("クラス旗を編集","編集") { flagEditor() }
        row("International Flag","一覧") { internationalFlags() }
    }

    private fun section(title: String) {
        list.addView(TextView(this).apply { text=title; textSize=17f; setTextColor(0xFFB0B0B5.toInt()); setPadding(6,20,4,8) })
    }
    private fun row(title: String, value: String, click: () -> Unit) {
        val r=LinearLayout(this).apply { orientation=LinearLayout.HORIZONTAL; gravity=Gravity.CENTER_VERTICAL; minimumHeight=50; setPadding(6,4,4,4) }
        r.addView(TextView(this).apply { text=title; textSize=15f; setTextColor(white); layoutParams=LinearLayout.LayoutParams(0,-2,1f) })
        r.addView(TextView(this).apply { text=value+"  ›"; textSize=14f; setTextColor(0xFFAAAAAA.toInt()) })
        r.setOnClickListener { click() }; list.addView(r)
        list.addView(View(this).apply { setBackgroundColor(0xFF444448.toInt()) },LinearLayout.LayoutParams(-1,1))
    }
    private fun switch(title:String,key:String,default:Boolean) {
        val r=LinearLayout(this).apply { orientation=LinearLayout.HORIZONTAL; gravity=Gravity.CENTER_VERTICAL; minimumHeight=50; setPadding(6,4,4,4) }
        r.addView(TextView(this).apply { text=title; textSize=15f; setTextColor(white); layoutParams=LinearLayout.LayoutParams(0,-2,1f) })
        r.addView(android.widget.Switch(this).apply { isChecked=prefs.getBoolean(key,default); setOnCheckedChangeListener { _,v -> prefs.edit().putBoolean(key,v).apply() } })
        list.addView(r); list.addView(View(this).apply { setBackgroundColor(0xFF444448.toInt()) },LinearLayout.LayoutParams(-1,1))
    }
    private fun number(title:String,key:String,default:Int,min:Int,max:Int) {
        val input=EditText(this).apply { setText(prefs.getInt(key,default).toString()); inputType=2; setTextColor(white) }
        AlertDialog.Builder(this).setTitle(title).setView(input).setNegativeButton("キャンセル",null).setPositiveButton("保存") { _,_ ->
            prefs.edit().putInt(key,(input.text.toString().toIntOrNull()?:default).coerceIn(min,max)).apply(); build()
        }.show()
    }
    private fun choose(title:String,items:List<String>,key:String) {
        AlertDialog.Builder(this).setTitle(title).setItems(items.toTypedArray()) { _,i ->
            prefs.edit().putString(key,items[i]).apply()
            if(key=="signalStartRule") {
                val prep=SignalSequence.preparationFlagForStartRule(items[i])
                prefs.edit().putString("signalPrepFlag",prep).apply()
            }
            build()
        }.show()
    }
    private fun simpleSwitch(title:String,key:String,default:Boolean) {
        val cb=CheckBox(this).apply { text=title; setTextColor(white); isChecked=prefs.getBoolean(key,default) }
        AlertDialog.Builder(this).setTitle(title).setView(cb).setNegativeButton("キャンセル",null).setPositiveButton("保存"){_,_->prefs.edit().putBoolean(key,cb.isChecked).apply()}.show()
    }
    private fun addFleet() {
        val input=EditText(this).apply { hint="Fleet Start name"; setTextColor(white) }
        AlertDialog.Builder(this).setTitle("新規フリート手順").setView(input).setNegativeButton("キャンセル",null).setPositiveButton("作成"){_,_->
            val name=input.text.toString().trim().ifEmpty{"Fleet Start"}
            val names=prefs.getStringSet("signalFleetPresetNames",setOf("OP Au Bp"))?.toMutableSet()?:mutableSetOf()
            val current=prefs.getString("signalFleetStartName","OP Au Bp") ?: "OP Au Bp"
            saveFleetConfig(current)
            names.add(name); prefs.edit().putStringSet("signalFleetPresetNames",names).putString("signalFleetStartName",name).apply()
            saveFleetConfig(name)
            build()
        }.show()
    }
    private fun fleet(name:String) {
        val previous = prefs.getString("signalFleetStartName", "OP Au Bp") ?: "OP Au Bp"
        if (name != previous) saveFleetConfig(previous)
        loadFleetConfig(name)
        prefs.edit().putString("signalFleetStartName",name).apply()

        val content = LinearLayout(this).apply { orientation=LinearLayout.VERTICAL; setPadding(18,8,18,12) }
        val scroller = ScrollView(this).apply { addView(content) }
        fun label(text:String) { content.addView(TextView(this).apply { this.text=text; setTextColor(white); setPadding(0,10,0,4) }) }
        fun field(title:String, value:String):EditText {
            label(title)
            return EditText(this).apply { setText(value); setTextColor(white); setSingleLine(true); content.addView(this) }
        }
        val nameField=field("Name",name)
        label("Defaults · Start sequence")
        content.addView(TextView(this).apply { text="Rule 26 · 5 min"; setTextColor(0xFFBBBBBB.toInt()); textSize=16f })
        label("Start rule / preparation signal (paired)")
        val ruleSpinner=Spinner(this)
        val rules=listOf("P","I","U","Z","Black","Default")
        ruleSpinner.adapter=ArrayAdapter(this,android.R.layout.simple_spinner_dropdown_item,rules)
        val selectedRule=prefs.getString("signalStartRule","P") ?: "P"
        ruleSpinner.setSelection(rules.indexOf(selectedRule).coerceAtLeast(0)); content.addView(ruleSpinner)
        label("Class flag")
        val classes=SignalClassLogoAssets.availableClassNames(this)
        val classSpinner=Spinner(this)
        classSpinner.adapter=ArrayAdapter(this,android.R.layout.simple_spinner_dropdown_item,classes)
        val currentClass=prefs.getString("signalSelectedClassName", "420") ?: "420"
        classSpinner.setSelection(classes.indexOf(currentClass).coerceAtLeast(0)); content.addView(classSpinner)
        val orangeEnabled=CheckBox(this).apply { text="Orange flag enabled"; setTextColor(white); isChecked=prefs.getBoolean("signalOrangeEnabled",true); content.addView(this) }
        val orangeMinutes=field("Orange flag: raise to warning interval (minutes)",prefs.getInt("signalOrangeDisplayedMinutes",5).toString())
        val orangeRemove=field("Lower orange flag after start (minutes)",prefs.getInt("signalOrangeRemovedAfterMinutes",4).toString())
        val delayEnabled=CheckBox(this).apply { text="Custom race delay"; setTextColor(white); isChecked=prefs.getBoolean("signalRaceDelayEnabled",false); content.addView(this) }
        val delay=field("Time between races (minutes)",prefs.getInt("signalRaceDelayMinutes",0).toString())
        val limitEnabled=CheckBox(this).apply { text="Time limit enabled"; setTextColor(white); isChecked=prefs.getBoolean("signalTimeLimitEnabled",false); content.addView(this) }
        val raceLimit=field("Race limit (minutes)",prefs.getInt("signalRaceLimitMinutes",50).toString())
        val finishWindow=field("Finish window (minutes)",prefs.getInt("signalFinishWindowMinutes",20).toString())
        val rule42=CheckBox(this).apply { text="Rule 42 override"; setTextColor(white); isChecked=prefs.getBoolean("signalRule42Override",false); content.addView(this) }
        val startRows=prefs.getStringSet("signalStartEntries",setOf("Class · T−5:00 · 掲揚 · 短音")) ?: emptySet()
        label("Starts")
        startRows.sorted().forEach { action ->
            val actionRow=LinearLayout(this).apply { gravity=Gravity.CENTER_VERTICAL; orientation=LinearLayout.HORIZONTAL }
            actionRow.addView(TextView(this).apply { text="• $action"; setTextColor(white); setPadding(0,4,0,4); layoutParams=LinearLayout.LayoutParams(0,-2,1f); setOnClickListener { addStart(action) } })
            actionRow.addView(Button(this).apply { text="−"; setOnClickListener { removeStart(action) } })
            content.addView(actionRow)
        }
        content.addView(Button(this).apply { text="＋ Add Start…"; setOnClickListener { addStart() } })

        AlertDialog.Builder(this).setTitle("Fleet Start").setView(scroller).setNegativeButton("Cancel"){_,_->loadFleetConfig(previous); prefs.edit().putString("signalFleetStartName",previous).apply()}.setPositiveButton("Save"){_,_->
            val updated=nameField.text.toString().trim().ifEmpty{name}
            val rule=rules[ruleSpinner.selectedItemPosition]
            val selectedClass=classes.getOrElse(classSpinner.selectedItemPosition){"420"}
            val editor=prefs.edit()
                .putString("signalFleetStartName",updated)
                .putString("signalStartRule",rule)
                .putString("signalPrepFlag",SignalSequence.preparationFlagForStartRule(rule))
                .putString("signalSelectedClassName",selectedClass)
                .putString("signalCustomClassFlag","class-$selectedClass")
                .putBoolean("signalOrangeEnabled",orangeEnabled.isChecked)
                .putInt("signalOrangeDisplayedMinutes",orangeMinutes.text.toString().toIntOrNull()?.coerceIn(0,30)?:5)
                .putInt("signalOrangeRemovedAfterMinutes",orangeRemove.text.toString().toIntOrNull()?.coerceIn(0,30)?:4)
                .putBoolean("signalRaceDelayEnabled",delayEnabled.isChecked)
                .putInt("signalRaceDelayMinutes",delay.text.toString().toIntOrNull()?.coerceIn(0,60)?:0)
                .putBoolean("signalTimeLimitEnabled",limitEnabled.isChecked)
                .putInt("signalRaceLimitMinutes",raceLimit.text.toString().toIntOrNull()?.coerceIn(1,300)?:50)
                .putInt("signalFinishWindowMinutes",finishWindow.text.toString().toIntOrNull()?.coerceIn(1,120)?:20)
                .putBoolean("signalRule42Override",rule42.isChecked)
            editor.apply()
            if (updated != name) {
                val names=prefs.getStringSet("signalFleetPresetNames",setOf(name))?.toMutableSet()?:mutableSetOf()
                names.remove(name); names.add(updated); prefs.edit().putStringSet("signalFleetPresetNames",names).apply()
            }
            saveFleetConfig(updated)
            build()
        }.show()
    }

    private val fleetConfigKeys = listOf("signalStartRule","signalPrepFlag","signalSelectedClassName","signalCustomClassFlag","signalOrangeEnabled","signalOrangeDisplayedMinutes","signalOrangeRemovedAfterMinutes","signalRaceDelayEnabled","signalRaceDelayMinutes","signalTimeLimitEnabled","signalRaceLimitMinutes","signalFinishWindowMinutes","signalRule42Override","signalStartEntries")
    private fun saveFleetConfig(name:String) {
        val json=org.json.JSONObject()
        fleetConfigKeys.forEach { key -> when (val value=prefs.all[key]) {
            is String -> json.put(key,value)
            is Boolean -> json.put(key,value)
            is Int -> json.put(key,value)
            is Set<*> -> json.put(key,org.json.JSONArray(value.toList()))
        } }
        prefs.edit().putString("signalFleetConfig:$name",json.toString()).apply()
    }
    private fun loadFleetConfig(name:String) {
        val raw=prefs.getString("signalFleetConfig:$name",null) ?: return
        val json=runCatching { org.json.JSONObject(raw) }.getOrNull() ?: return
        val editor=prefs.edit().putString("signalFleetStartName",name)
        fleetConfigKeys.forEach { key -> if(json.has(key)) when (key) {
            "signalStartEntries" -> { val array=json.optJSONArray(key); if(array!=null) editor.putStringSet(key,(0 until array.length()).map { array.optString(it) }.toSet()) }
            "signalStartRule","signalPrepFlag","signalSelectedClassName","signalCustomClassFlag" -> editor.putString(key,json.optString(key))
            "signalOrangeEnabled","signalRaceDelayEnabled","signalTimeLimitEnabled","signalRule42Override" -> editor.putBoolean(key,json.optBoolean(key))
            else -> editor.putInt(key,json.optInt(key))
        } }
        editor.apply()
    }
    private fun addStart(existing:String?=null) {
        val flags=listOf("Class","Orange","AP","X","First Substitute")
        val parsed=existing?.split("·")?.map(String::trim).orEmpty()
        val flag=parsed.getOrNull(0) ?: "Class"
        val time=Regex("""T[−-](\d+):(\d+)""").find(existing.orEmpty())
        val minute=time?.groupValues?.getOrNull(1)?.toIntOrNull() ?: 5
        val second=time?.groupValues?.getOrNull(2)?.toIntOrNull() ?: 0
        val direction=if(parsed.getOrNull(2)=="降下") "降下" else "掲揚"
        val horn=parsed.getOrNull(3) ?: "短音"
        val content=LinearLayout(this).apply { orientation=LinearLayout.VERTICAL; setPadding(22,8,22,4) }
        val flagPicker=Spinner(this).apply { adapter=ArrayAdapter(this@SignalSettingsActivity,android.R.layout.simple_spinner_dropdown_item,flags); setSelection(flags.indexOf(flag).coerceAtLeast(0)); content.addView(this) }
        val minuteField=EditText(this).apply { hint="分前"; inputType=2; setText(minute.toString()); setTextColor(white); content.addView(this) }
        val secondField=EditText(this).apply { hint="秒"; inputType=2; setText(second.toString()); setTextColor(white); content.addView(this) }
        val actionPicker=Spinner(this).apply { adapter=ArrayAdapter(this@SignalSettingsActivity,android.R.layout.simple_spinner_dropdown_item,listOf("掲揚","降下")); setSelection(if(direction=="降下")1 else 0); content.addView(this) }
        val hornPicker=Spinner(this).apply { adapter=ArrayAdapter(this@SignalSettingsActivity,android.R.layout.simple_spinner_dropdown_item,listOf("短音","長音","音なし")); setSelection(listOf("短音","長音","音なし").indexOf(horn).coerceAtLeast(0)); content.addView(this) }
        AlertDialog.Builder(this).setTitle(if(existing==null)"Add Start…" else "信号を編集").setView(content).setNegativeButton("キャンセル",null).setPositiveButton("保存"){_,_->
            val selected=flags[flagPicker.selectedItemPosition]
            val m=(minuteField.text.toString().toIntOrNull()?:5).coerceIn(0,60)
            val s=(secondField.text.toString().toIntOrNull()?:0).coerceIn(0,59)
            val row="$selected · T−${m}:${s.toString().padStart(2,'0')} · ${if(actionPicker.selectedItemPosition==1)"降下" else "掲揚"} · ${listOf("短音","長音","音なし")[hornPicker.selectedItemPosition]}"
            val items=prefs.getStringSet("signalStartEntries",emptySet())?.toMutableSet()?:mutableSetOf()
            existing?.let(items::remove); items.add(row)
            prefs.edit().putStringSet("signalStartEntries",items).apply(); build()
        }.show()
    }
    private fun removeStart(action:String) {
        val items=prefs.getStringSet("signalStartEntries",emptySet())?.toMutableSet()?:mutableSetOf()
        items.remove(action); prefs.edit().putStringSet("signalStartEntries",items).apply(); saveFleetConfig(prefs.getString("signalFleetStartName","OP Au Bp")?:"OP Au Bp"); build()
    }
    private fun classGallery() {
        val groups = linkedMapOf("クラスロゴ" to SignalClassLogoAssets.availableClassNames(this))
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(12, 4, 12, 12)
        }
        var dialog: AlertDialog? = null
        val density = resources.displayMetrics.density
        groups.forEach { (category, classes) ->
            content.addView(TextView(this).apply {
                text = category
                textSize = 17f
                typeface = android.graphics.Typeface.DEFAULT_BOLD
                setTextColor(0xFFB0B0B5.toInt())
                setPadding(4, 18, 4, 8)
            })
            val grid = GridView(this).apply {
                numColumns = 3
                horizontalSpacing = (8 * density).toInt()
                verticalSpacing = (8 * density).toInt()
                stretchMode = GridView.STRETCH_COLUMN_WIDTH
                adapter = object : BaseAdapter() {
                    override fun getCount() = classes.size
                    override fun getItem(position: Int) = classes[position]
                    override fun getItemId(position: Int) = position.toLong()
                    override fun getView(position: Int, convertView: View?, parent: android.view.ViewGroup?): View {
                        val name = classes[position]
                        return LinearLayout(this@SignalSettingsActivity).apply {
                            orientation = LinearLayout.VERTICAL
                            gravity = Gravity.CENTER
                            setPadding(4, 5, 4, 5)
                            val logoBitmap = SignalClassLogoAssets.bitmap(this@SignalSettingsActivity, name)
                            val markBox = FrameLayout(this@SignalSettingsActivity).apply {
                                setBackgroundColor(Color.WHITE)
                                if (logoBitmap != null) {
                                    addView(ImageView(this@SignalSettingsActivity).apply {
                                        setImageBitmap(logoBitmap)
                                        scaleType = ImageView.ScaleType.FIT_CENTER
                                        setPadding((5 * density).toInt(), (5 * density).toInt(), (5 * density).toInt(), (5 * density).toInt())
                                    }, FrameLayout.LayoutParams(-1, -1))
                                } else {
                                    addView(TextView(this@SignalSettingsActivity).apply {
                                        text = classMark(name)
                                        textSize = 23f
                                        typeface = android.graphics.Typeface.create("sans-serif-black", android.graphics.Typeface.BOLD_ITALIC)
                                        gravity = Gravity.CENTER
                                        isSingleLine = true
                                        setTextColor(Color.BLACK)
                                        if (android.os.Build.VERSION.SDK_INT >= 26) {
                                            setAutoSizeTextTypeUniformWithConfiguration(10, 23, 1, android.util.TypedValue.COMPLEX_UNIT_SP)
                                        }
                                    }, FrameLayout.LayoutParams(-1, -1))
                                }
                            }
                            addView(markBox, LinearLayout.LayoutParams(-1, (64 * density).toInt()))
                            addView(TextView(this@SignalSettingsActivity).apply {
                                text = name
                                textSize = 12f
                                gravity = Gravity.CENTER
                                setTextColor(white)
                                setPadding(0, 4, 0, 0)
                                maxLines = 2
                            })
                        }
                    }
                }
                setOnItemClickListener { _, _, index, _ ->
                    val selected = classes[index]
                    prefs.edit()
                        .putString("signalSelectedClassName", selected)
                        .putString("signalCustomClassFlag", "class-$selected")
                        .apply()
                    dialog?.dismiss()
                    build()
                }
            }
            val rows = (classes.size + 2) / 3
            content.addView(grid, LinearLayout.LayoutParams(-1, rows * (82 * density).toInt()))
        }
        val scroll = ScrollView(this).apply { addView(content) }
        dialog = AlertDialog.Builder(this)
            .setTitle("クラス旗を選択")
            .setView(scroll)
            .setNegativeButton("閉じる", null)
            .create()
        dialog?.show()
    }
    private fun classMark(name:String):String = when(name) {
        "A-Cat" -> "A̲"; "Optimist" -> "Ⓞ"; "Starling" -> "★"; "ILCA" -> "ILCA"
        "49er FX" -> "49er FX"; "J/22" -> "J\n22"; "J/24" -> "J\n24"; "J/70" -> "J\n70"; "J/80" -> "J\n80"
        "J/105" -> "J\n105"; "420" -> "420"; "470" -> "470"; else -> name
    }
    private fun internationalFlags() {
        val flags=listOf("Alpha","Bravo","Charlie","Delta","Echo","Foxtrot","Golf","Hotel","India","Juliett","Kilo","Lima","Mike","November","Oscar","Papa","Quebec","Romeo","Sierra","Tango","Uniform","Victor","Whiskey","X-Ray","Yankee","Zulu","Pennant 0","Pennant 1","Pennant 2","Pennant 3","Pennant 4","Pennant 5","Pennant 6","Pennant 7","Pennant 8","Pennant 9","Answering Pennant","First Substitute","Second Substitute","Third Substitute")
        val grid=GridView(this).apply { numColumns=3; horizontalSpacing=8; verticalSpacing=10; setPadding(12,12,12,12); adapter=object:BaseAdapter(){
            override fun getCount()=flags.size
            override fun getItem(position:Int)=flags[position]
            override fun getItemId(position:Int)=position.toLong()
            override fun getView(position:Int, convertView:View?, parent:android.view.ViewGroup?):View {
                val name=flags[position]
                return LinearLayout(this@SignalSettingsActivity).apply {
                    orientation=LinearLayout.VERTICAL; gravity=Gravity.CENTER
                    addView(SignalFlagArtworkView(this@SignalSettingsActivity,name),LinearLayout.LayoutParams(-1,72))
                    addView(TextView(this@SignalSettingsActivity).apply { text=name; textSize=12f; gravity=Gravity.CENTER; setTextColor(white); setPadding(0,4,0,0) })
                }
            }
        }; setOnItemClickListener { _,_,i,_ -> prefs.edit().putString("signalSelectedInternationalFlag",flags[i]).apply(); (tag as? AlertDialog)?.dismiss(); build() } }
        val dialog=AlertDialog.Builder(this).setTitle("International Signal Flags").setView(ScrollView(this).apply { addView(grid) }).setNegativeButton("閉じる",null).create()
        grid.tag=dialog; dialog.show()
    }
    private fun flagEditor() {
        val classNames=listOf("29er","3.7","420","470","49er","49er FX","A-Cat","Albacore","B14","Cadet","Dart 18","Dragon","Europe","Finn","Formula 18","Hobie","ILCA","IOD","J/22","J/24","J/70","J/80","Laser","Melges 24","Moth","Nacra 15","Nacra 17","Optimist","RS Aero","Snipe","Solo","Starling","Sunfish","Tasar","Topper","Tornado","Viper","WASZP","Wayfarer","Weta","X-79","X-99","Yngling","Zoom 8")
        val flagNames=listOf("Alpha","Bravo","Charlie","Delta","Echo","Foxtrot","Golf","Hotel","India","Juliett","Kilo","Lima","Mike","November","Oscar","Papa","Quebec","Romeo","Sierra","Tango","Uniform","Victor","Whiskey","X-Ray","Yankee","Zulu")
        val input=EditText(this).apply { hint="旗の名前"; setText(prefs.getString("signalCustomFlagName","Class Flag")); setTextColor(white) }
        val types=listOf("クラス旗","文字旗","国際信号旗")
        val type=Spinner(this).apply { adapter=ArrayAdapter(this@SignalSettingsActivity,android.R.layout.simple_spinner_dropdown_item,types) }
        val classes=Spinner(this).apply { adapter=ArrayAdapter(this@SignalSettingsActivity,android.R.layout.simple_spinner_dropdown_item,classNames) }
        val flags=Spinner(this).apply { adapter=ArrayAdapter(this@SignalSettingsActivity,android.R.layout.simple_spinner_dropdown_item,flagNames) }
        classes.setSelection(classNames.indexOf(prefs.getString("signalSelectedClassName","29er")).coerceAtLeast(0))
        flags.setSelection(flagNames.indexOf(prefs.getString("signalSelectedInternationalFlag","Alpha")).coerceAtLeast(0))
        val layouts=listOf("全面色","上下分割","左右分割","斜め分割","逆斜め")
        val layout=Spinner(this).apply { adapter=ArrayAdapter(this@SignalSettingsActivity,android.R.layout.simple_spinner_dropdown_item,layouts) }
        layout.setSelection(prefs.getInt("signalCustomFlagLayoutIndex",0).coerceIn(0,layouts.lastIndex))
        var logoColor = prefs.getInt("signalClassLogoTextColor", Color.BLACK)
        var logoBackground = prefs.getInt("signalClassLogoBackgroundColor", Color.WHITE)
        val logoColorButton = Button(this).apply { text = "ロゴ色を選択"; setTextColor(logoColor) }
        val backgroundColorButton = Button(this).apply { text = "背景色を選択"; setTextColor(logoBackground) }
        val preview=FrameLayout(this).apply { setBackgroundColor(logoBackground) }
        val box=LinearLayout(this).apply {
            orientation=LinearLayout.VERTICAL; setPadding(18,0,18,0)
            addView(input); addView(type); addView(classes); addView(flags); addView(layout);
            addView(logoColorButton); addView(backgroundColorButton); addView(preview,LinearLayout.LayoutParams(-1,96))
        }
        fun updatePreview() {
            val isInternational=type.selectedItemPosition==2
            classes.visibility=if(type.selectedItemPosition==0)View.VISIBLE else View.GONE
            flags.visibility=if(isInternational)View.VISIBLE else View.GONE
            layout.visibility=if(type.selectedItemPosition==1)View.VISIBLE else View.GONE
            preview.removeAllViews()
            preview.setBackgroundColor(logoBackground)
            logoColorButton.text = "ロゴ色: ${String.format("#%06X", 0xFFFFFF and logoColor)}"
            backgroundColorButton.text = "背景色: ${String.format("#%06X", 0xFFFFFF and logoBackground)}"
            logoColorButton.setTextColor(logoColor)
            backgroundColorButton.setTextColor(if (Color.luminance(logoBackground) > 0.45f) Color.BLACK else Color.WHITE)
            val label = when(type.selectedItemPosition){0->classes.selectedItem.toString();1->input.text.toString().ifBlank{"旗"};else->flagNames[flags.selectedItemPosition]}
            val logo = if(type.selectedItemPosition==0) SignalClassLogoAssets.bitmap(this, label) else null
            if (logo != null) {
                preview.addView(ImageView(this).apply {
                    setImageBitmap(logo); scaleType=ImageView.ScaleType.FIT_CENTER
                    setColorFilter(logoColor, android.graphics.PorterDuff.Mode.SRC_IN)
                    setPadding(8,8,8,8)
                }, FrameLayout.LayoutParams(-1,-1))
            } else {
                preview.addView(TextView(this).apply {
                    text=if(type.selectedItemPosition==0) classMark(label) else label
                    gravity=Gravity.CENTER; textSize=22f; setTextColor(logoColor)
                }, FrameLayout.LayoutParams(-1,-1))
            }
        }
        val paletteNames = arrayOf("黒","白","赤","橙","黄","緑","青","紫")
        val paletteColors = intArrayOf(Color.BLACK, Color.WHITE, 0xFFE32636.toInt(), 0xFFF58A00.toInt(), 0xFFF5D328.toInt(), 0xFF00B83F.toInt(), 0xFF1769FF.toInt(), 0xFF7A35A8.toInt())
        logoColorButton.setOnClickListener { AlertDialog.Builder(this).setTitle("ロゴ色").setItems(paletteNames) { _, i -> logoColor=paletteColors[i]; updatePreview() }.show() }
        backgroundColorButton.setOnClickListener { AlertDialog.Builder(this).setTitle("背景色").setItems(paletteNames) { _, i -> logoBackground=paletteColors[i]; updatePreview() }.show() }
        type.onItemSelectedListener=object:AdapterView.OnItemSelectedListener{
            override fun onItemSelected(parent:AdapterView<*>?,view:View?,position:Int,id:Long)=updatePreview()
            override fun onNothingSelected(parent:AdapterView<*>?) {}
        }
        classes.onItemSelectedListener=type.onItemSelectedListener
        flags.onItemSelectedListener=type.onItemSelectedListener
        input.addTextChangedListener(object:android.text.TextWatcher{
            override fun beforeTextChanged(s:CharSequence?,start:Int,count:Int,after:Int){}
            override fun onTextChanged(s:CharSequence?,start:Int,before:Int,count:Int){if(type.selectedItemPosition==1) updatePreview()}
            override fun afterTextChanged(s:android.text.Editable?){}
        })
        AlertDialog.Builder(this).setTitle("クラス旗・信号旗の設定").setView(box).setNegativeButton("キャンセル",null).setPositiveButton("保存"){_,_->
            val editor=prefs.edit().putString("signalCustomFlagName",input.text.toString()).putInt("signalCustomFlagStyle",type.selectedItemPosition).putInt("signalCustomFlagLayoutIndex",layout.selectedItemPosition)
                .putInt("signalClassLogoTextColor", logoColor).putInt("signalClassLogoBackgroundColor", logoBackground)
            when(type.selectedItemPosition){
                0->{val selected=classNames[classes.selectedItemPosition];editor.putString("signalSelectedClassName",selected).putString("signalCustomClassFlag","class-$selected")}
                1->{val label=input.text.toString().trim().ifEmpty{"旗"};editor.putString("signalSelectedClassName","text:$label").putString("signalCustomFlagText",label)}
                2->{val selected=flagNames[flags.selectedItemPosition];editor.putString("signalSelectedInternationalFlag",selected).putString("signalSelectedClassName","intl:$selected")}
            }
            editor.apply()
            build()
        }.show()
    }
    private fun notifications() {
        val items=listOf("ASAP","Every minute*","1 minute","30 seconds","20 seconds","Countdown","On Time","Race: Every minute","Race: Every 5 minutes","Time Limit","Zone alerts")
        val modes=arrayOf("Time","Full","Sound","None")
        val box=LinearLayout(this).apply { orientation=LinearLayout.VERTICAL; setPadding(16,0,16,0) }
        val radio=CheckBox(this).apply { text="Radio Friendly"; setTextColor(white); isChecked=prefs.getBoolean("signalRadioFriendly",true) }; box.addView(radio)
        val controls=mutableMapOf<String,Spinner>()
        items.forEach { label ->
            val r=LinearLayout(this).apply { orientation=LinearLayout.HORIZONTAL; gravity=Gravity.CENTER_VERTICAL }
            r.addView(TextView(this@SignalSettingsActivity).apply { text=label; setTextColor(white); layoutParams=LinearLayout.LayoutParams(0,-2,1f) })
            val s=Spinner(this).apply { adapter=ArrayAdapter(this@SignalSettingsActivity,android.R.layout.simple_spinner_dropdown_item,modes); setSelection(modes.indexOf(prefs.getString("notify_"+label,"None")).coerceAtLeast(0)) }
            r.addView(s,LinearLayout.LayoutParams(120,-2)); box.addView(r); controls[label]=s
        }
        AlertDialog.Builder(this).setTitle("Notifications").setView(ScrollView(this).apply{addView(box)}).setNegativeButton("キャンセル",null).setPositiveButton("Save"){_,_->
            val e=prefs.edit().putBoolean("signalRadioFriendly",radio.isChecked); controls.forEach{(k,v)->e.putString("notify_"+k,v.selectedItem.toString())};e.apply()
        }.show()
    }
    private fun horn() {
        val box=LinearLayout(this).apply { orientation=LinearLayout.VERTICAL; setPadding(16,0,16,0) }
        val enabled=CheckBox(this).apply { text="Virtual"; setTextColor(white); isChecked=prefs.getBoolean("signalHornEnabled",true) }; box.addView(enabled)
        fun slider(label:String,key:String,def:Int,max:Int) {
            box.addView(TextView(this).apply { text=label; setTextColor(white) })
            val seek=SeekBar(this).apply { this.max=max; progress=prefs.getInt(key,def).coerceIn(0,max) }
            seek.setOnSeekBarChangeListener(object:SeekBar.OnSeekBarChangeListener{
                override fun onProgressChanged(s:SeekBar?,v:Int,fromUser:Boolean){prefs.edit().putInt(key,v).apply()}
                override fun onStartTrackingTouch(s:SeekBar?){}; override fun onStopTrackingTouch(s:SeekBar?){}
            }); box.addView(seek)
        }
        slider("Volume","signalHornVolume",80,100);slider("Short Sound (ms)","signalShortHornMs",220,1000);slider("Long Sound (ms)","signalHornMs",700,5000);slider("Gap (ms)","signalGapMs",180,2000)
        AlertDialog.Builder(this).setTitle("Remote Horn").setView(box).setPositiveButton("完了"){_,_->prefs.edit().putBoolean("signalHornEnabled",enabled.isChecked).apply()}.show()
    }
    private fun showLog() = simpleSwitch("ログを保存","signalLogEnabled",true)
}
