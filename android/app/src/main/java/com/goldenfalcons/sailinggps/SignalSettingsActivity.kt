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
        row("Time Sync", "ntp.nict.jp / ゼロ合わせ") { AlertDialog.Builder(this).setMessage("シグナル画面のNTP同期とゼロ合わせを使用します。").setPositiveButton("OK", null).show() }
        row("Horn", if (prefs.getBoolean("signalHornEnabled", true)) "Virtual" else "Disabled") { horn() }
        switch("Remote Flags (alpha)", "signalRemoteFlagsEnabled", false)
        switch("BuoyZone", "signalBuoyZoneLinked", false)
        switch("External Display", "signalExternalDisplayEnabled", true)
        row("Log", "記録設定") { simpleSwitch("Log", "signalLogEnabled", true) }

        section("Fleet Start Sequences")
        val names = prefs.getStringSet("signalFleetPresetNames", setOf("OP Au Bp")) ?: setOf("OP Au Bp")
        names.sorted().forEach { row(it, "編集") { fleet(it) } }
        row("＋ Fleet Start", "Add") { addFleet() }

        section("Start 1")
        row("Start Sequence", selectedProfile()) { choose("Start Sequence", SignalSequence.profiles.map { it.name }, "signalProfileName") }
        row("Start Rule", prefs.getString("signalStartRule", "P") ?: "P") { choose("Start Rule", listOf("P","I","U","Z","Black","Default"), "signalStartRule") }
        row("Classes", prefs.getString("signalSelectedClassName", "クラス旗") ?: "クラス旗") { classGallery() }
        row("準備信号", prefs.getString("signalPrepFlag", "P") ?: "P") { choosePrep() }
        switch("Custom Race Delay", "signalRaceDelayEnabled", false)
        row("Time between races", prefs.getInt("signalRaceDelayMinutes", 0).toString()+"分") { number("レース間隔", "signalRaceDelayMinutes", 0, 0, 60) }

        section("Time Limits")
        switch("Enable", "signalTimeLimitEnabled", false)
        row("Race Limit", prefs.getInt("signalRaceLimitMinutes",50).toString()+"分") { number("Race Limit", "signalRaceLimitMinutes",50,1,300) }
        row("Finish Window", prefs.getInt("signalFinishWindowMinutes",20).toString()+"分") { number("Finish Window","signalFinishWindowMinutes",20,1,120) }
        section("Rule 42 Override"); switch("Enable","signalRule42Override",false)

        section("Orange Flag")
        switch("Enable","signalOrangeEnabled",true)
        row("最初のレース信号より前",prefs.getInt("signalOrangeDisplayedMinutes",5).toString()+"分") { number("最初のレース信号より前（分）","signalOrangeDisplayedMinutes",5,0,30) }
        row("最後の信号の後",prefs.getInt("signalOrangeRemovedAfterMinutes",4).toString()+"分") { number("最後の信号の後（分）","signalOrangeRemovedAfterMinutes",4,0,30) }
        list.addView(TextView(this).apply { text="待機中は降下状態です。有効時は開始時に橙旗を掲揚し、設定時間後に最初のレース信号を行います。無効時は最初のレース信号が0秒です。橙旗は最後の信号から設定時間後に降下します。掲揚・降下は手動でも操作できます。"; setTextColor(0xFFAAAAAA.toInt()); setPadding(6,4,6,12) })
        section("Starts")
        val starts=prefs.getStringSet("signalStartEntries",setOf("Class · T−5:00 · 掲揚 · 短音")) ?: emptySet()
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
            if(key=="signalProfileName") {
                val index=SignalSequence.profiles.indexOfFirst { it.name==items[i] }.coerceAtLeast(0)
                val profile=SignalSequence.profiles[index]
                val displayed=if(profile.id=="video-13") 4 else 5
                val removed=if(profile.id=="video-20") 10 else 4
                prefs.edit().putInt("signalFlagProfileIndex",index).putString("signalFlagProfile",profile.id)
                    .putInt("signalOrangeDisplayedMinutes",displayed)
                    .putInt("signalOrangeRemovedAfterMinutes",removed).apply()
            }
            if(key=="signalStartRule" && items[i] in listOf("P","I","U","Z","Black")) {
                prefs.edit().putString("signalPrepFlag",if(items[i]=="Black") "black" else items[i]).apply()
            }
            build()
        }.show()
    }
    private fun choosePrep() {
        AlertDialog.Builder(this).setTitle("準備信号").setItems(arrayOf("P","I","U","Z","Black")) { _,i ->
            val value=listOf("P","I","U","Z","black")[i]; prefs.edit().putString("signalPrepFlag",value).apply(); build()
        }.show()
    }
    private fun selectedProfile() = SignalSequence.profiles.getOrElse(prefs.getInt("signalFlagProfileIndex",0)){SignalSequence.profiles[0]}.name
    private fun simpleSwitch(title:String,key:String,default:Boolean) {
        val cb=CheckBox(this).apply { text=title; setTextColor(white); isChecked=prefs.getBoolean(key,default) }
        AlertDialog.Builder(this).setTitle(title).setView(cb).setNegativeButton("キャンセル",null).setPositiveButton("保存"){_,_->prefs.edit().putBoolean(key,cb.isChecked).apply()}.show()
    }
    private fun addFleet() {
        val input=EditText(this).apply { hint="Fleet Start name"; setTextColor(white) }
        AlertDialog.Builder(this).setTitle("新規フリート手順").setView(input).setNegativeButton("キャンセル",null).setPositiveButton("作成"){_,_->
            val name=input.text.toString().trim().ifEmpty{"Fleet Start"}
            val names=prefs.getStringSet("signalFleetPresetNames",setOf("OP Au Bp"))?.toMutableSet()?:mutableSetOf()
            names.add(name); prefs.edit().putStringSet("signalFleetPresetNames",names).putString("signalFleetStartName",name).apply(); build()
        }.show()
    }
    private fun fleet(name:String) {
        prefs.edit().putString("signalFleetStartName",name).apply()
        val input=EditText(this).apply { setText(name); setTextColor(white) }
        AlertDialog.Builder(this).setTitle("Fleet Start").setView(input).setNegativeButton("キャンセル",null).setPositiveButton("Save"){_,_->
            val updated=input.text.toString().trim().ifEmpty{name}; val names=prefs.getStringSet("signalFleetPresetNames",setOf(name))?.toMutableSet()?:mutableSetOf()
            names.remove(name); names.add(updated); prefs.edit().putStringSet("signalFleetPresetNames",names).putString("signalFleetStartName",updated).apply(); build()
        }.show()
    }
    private fun addStart() {
        val flags=listOf("Class","Orange","P","I","U","Z","Black","AP","X","First Substitute")
        AlertDialog.Builder(this).setTitle("Add Start…").setItems(flags.toTypedArray()){_,i->
            val items=prefs.getStringSet("signalStartEntries",emptySet())?.toMutableSet()?:mutableSetOf()
            items.add(flags[i]+" · T−5:00 · 掲揚 · 短音"); prefs.edit().putStringSet("signalStartEntries",items).apply(); build()
        }.show()
    }
    private fun classGallery() {
        val classes=listOf("29er","3.7","420","470","49er","49er FX","A-Cat","Albacore","B14","Cadet","Dart 18","Dragon","Europe","Finn","Formula 18","Hobie","ILCA","IOD","J/22","J/24","J/70","J/80","Laser","Melges 24","Moth","Nacra 15","Nacra 17","Optimist","RS Aero","Snipe","Solo","Starling","Sunfish","Tasar","Topper","Tornado","Viper","WASZP","Wayfarer","Weta","X-79","X-99","Yngling","Zoom 8")
        val grid=GridView(this).apply { numColumns=3; horizontalSpacing=8; verticalSpacing=8; setPadding(12,12,12,12); adapter=object:BaseAdapter(){
            override fun getCount()=classes.size
            override fun getItem(position:Int)=classes[position]
            override fun getItemId(position:Int)=position.toLong()
            override fun getView(position:Int, convertView:View?, parent:android.view.ViewGroup?):View {
                val name=classes[position]
                return LinearLayout(this@SignalSettingsActivity).apply {
                    orientation=LinearLayout.VERTICAL; gravity=Gravity.CENTER; setPadding(4,6,4,6)
                    addView(TextView(this@SignalSettingsActivity).apply {
                        text=classMark(name); textSize=23f; typeface=android.graphics.Typeface.create("sans-serif-black",android.graphics.Typeface.BOLD_ITALIC)
                        gravity=Gravity.CENTER; isSingleLine=true; setTextColor(Color.BLACK); setBackgroundColor(Color.WHITE)
                        if(android.os.Build.VERSION.SDK_INT>=26) setAutoSizeTextTypeUniformWithConfiguration(10,23,1,android.util.TypedValue.COMPLEX_UNIT_SP)
                    },LinearLayout.LayoutParams(-1,64))
                    addView(TextView(this@SignalSettingsActivity).apply { text=name; textSize=12f; gravity=Gravity.CENTER; setTextColor(white); setPadding(0,4,0,0) })
                }
            }
        }; setOnItemClickListener { _,_,i,_ -> prefs.edit().putString("signalSelectedClassName",classes[i]).putString("signalCustomClassFlag","class-${classes[i]}").apply(); (tag as? AlertDialog)?.dismiss(); build() } }
        val dialog=AlertDialog.Builder(this).setTitle("Class Logos").setView(grid).setNegativeButton("閉じる",null).create()
        grid.tag=dialog; dialog.show()
    }
    private fun classMark(name:String):String = when(name) {
        "A-Cat" -> "A̲"; "Optimist" -> "Ⓞ"; "Starling" -> "★"; "ILCA" -> "ILCA"
        "49er FX" -> "49er FX"; "J/22" -> "J\n22"; "J/24" -> "J\n24"; "J/70" -> "J\n70"; "J/80" -> "J\n80"
        "J/105" -> "J\n105"; "420" -> "420"; "470" -> "470"; else -> name
    }
    private fun internationalFlags() {
        val flags=listOf("Alpha","Bravo","Charlie","Delta","Echo","Foxtrot","Golf","Hotel","India","Juliett","Kilo","Lima","Mike","November","Oscar","Papa","Quebec","Romeo","Sierra","Tango","Uniform","Victor","Whiskey","X-Ray","Yankee","Zulu","Pennant 0","Pennant 1","Pennant 2","Pennant 3","Pennant 4","Pennant 5","Pennant 6","Pennant 7","Pennant 8","Pennant 9","Answering Pennant","First Substitute","Second Substitute","Third Substitute","Fourth Substitute","NATO 0","NATO 1","NATO 2","NATO 3","NATO 4","NATO 5","NATO 6","NATO 7","NATO 8","NATO 9")
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
        val preview=TextView(this).apply { gravity=Gravity.CENTER; textSize=22f; setTextColor(Color.BLACK); setBackgroundColor(Color.WHITE); text="クラス旗の見本" }
        val box=LinearLayout(this).apply {
            orientation=LinearLayout.VERTICAL; setPadding(18,0,18,0)
            addView(input); addView(type); addView(classes); addView(flags); addView(layout); addView(preview,LinearLayout.LayoutParams(-1,96))
        }
        fun updatePreview() {
            val isInternational=type.selectedItemPosition==2
            classes.visibility=if(type.selectedItemPosition==0)View.VISIBLE else View.GONE
            flags.visibility=if(isInternational)View.VISIBLE else View.GONE
            layout.visibility=if(type.selectedItemPosition==1)View.VISIBLE else View.GONE
            preview.text=when(type.selectedItemPosition){0->classMark(classes.selectedItem.toString());1->input.text.toString().ifBlank{"旗"};else->flagNames[flags.selectedItemPosition]}
        }
        type.onItemSelectedListener=object:AdapterView.OnItemSelectedListener{
            override fun onItemSelected(parent:AdapterView<*>?,view:View?,position:Int,id:Long)=updatePreview()
            override fun onNothingSelected(parent:AdapterView<*>?) {}
        }
        classes.onItemSelectedListener=type.onItemSelectedListener
        flags.onItemSelectedListener=type.onItemSelectedListener
        input.addTextChangedListener(object:android.text.TextWatcher{
            override fun beforeTextChanged(s:CharSequence?,start:Int,count:Int,after:Int){}
            override fun onTextChanged(s:CharSequence?,start:Int,before:Int,count:Int){if(type.selectedItemPosition==1) preview.text=s?.toString().orEmpty().ifBlank{"旗"}}
            override fun afterTextChanged(s:android.text.Editable?){}
        })
        AlertDialog.Builder(this).setTitle("クラス旗・信号旗の設定").setView(box).setNegativeButton("キャンセル",null).setPositiveButton("保存"){_,_->
            val editor=prefs.edit().putString("signalCustomFlagName",input.text.toString()).putInt("signalCustomFlagStyle",type.selectedItemPosition).putInt("signalCustomFlagLayoutIndex",layout.selectedItemPosition)
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
