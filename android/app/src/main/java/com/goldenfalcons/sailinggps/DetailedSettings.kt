package com.goldenfalcons.sailinggps

import android.Manifest
import android.app.Activity
import android.content.*
import android.os.Build
import android.provider.Settings
import androidx.appcompat.app.AlertDialog
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat

/** Each change persists immediately, and the instrument screen reads the same preferences. */
class DetailedSettings(private val activity:Activity,private val library:MapLibrary,private val folders:List<String>,
    private val currentFolder:String,private val gpsStatus:String,private val refresh:()->Unit) {
    private val prefs=activity.getSharedPreferences("display",Context.MODE_PRIVATE)
    private fun menu(title:String,items:List<Pair<String,()->Unit>>) {
        val sheet=com.google.android.material.bottomsheet.BottomSheetDialog(activity)
        val density=activity.resources.displayMetrics.density
        val column=android.widget.LinearLayout(activity).apply {
            orientation=android.widget.LinearLayout.VERTICAL
            setPadding((16*density).toInt(),(14*density).toInt(),(16*density).toInt(),(16*density).toInt())
            setBackgroundColor(android.graphics.Color.rgb(15,15,15))
        }
        column.addView(android.widget.TextView(activity).apply {
            text=title;textSize=22f;setTextColor(android.graphics.Color.WHITE)
            setTypeface(null,android.graphics.Typeface.BOLD)
            setPadding((8*density).toInt(),(6*density).toInt(),(8*density).toInt(),(12*density).toInt())
        })
        items.forEach { item ->
            val row=android.widget.TextView(activity).apply {
                text=item.first;textSize=17f;setTextColor(android.graphics.Color.WHITE)
                gravity=android.view.Gravity.CENTER_VERTICAL;minHeight=(54*density).toInt()
                setPadding((14*density).toInt(),(8*density).toInt(),(14*density).toInt(),(8*density).toInt())
                background=android.graphics.drawable.GradientDrawable().apply { setColor(android.graphics.Color.rgb(30,30,30));cornerRadius=10*density }
                isClickable=true;isFocusable=true
                setOnClickListener { sheet.dismiss();item.second() }
            }
            column.addView(row,android.widget.LinearLayout.LayoutParams(-1,-2).apply { bottomMargin=(6*density).toInt() })
        }
        column.addView(android.widget.Button(activity).apply { text="閉じる";isAllCaps=false;setOnClickListener { sheet.dismiss() } })
        sheet.setContentView(android.widget.ScrollView(activity).apply { addView(column) })
        sheet.show()
        sheet.behavior.state=com.google.android.material.bottomsheet.BottomSheetBehavior.STATE_EXPANDED
    }
    private fun message(title:String,text:String) {
        val sheet=com.google.android.material.bottomsheet.BottomSheetDialog(activity)
        val density=activity.resources.displayMetrics.density
        val column=android.widget.LinearLayout(activity).apply {
            orientation=android.widget.LinearLayout.VERTICAL
            setPadding((20*density).toInt(),(18*density).toInt(),(20*density).toInt(),(18*density).toInt())
            setBackgroundColor(android.graphics.Color.rgb(15,15,15))
        }
        column.addView(android.widget.TextView(activity).apply {
            this.text=title;textSize=22f;setTextColor(android.graphics.Color.WHITE)
            setTypeface(null,android.graphics.Typeface.BOLD);setPadding(0,0,0,(14*density).toInt())
        })
        column.addView(android.widget.TextView(activity).apply {
            this.text=text;textSize=16f;setTextColor(android.graphics.Color.LTGRAY)
            setPadding(0,0,0,(16*density).toInt())
        })
        column.addView(android.widget.Button(activity).apply { this.text="閉じる";isAllCaps=false;setOnClickListener { sheet.dismiss() } })
        sheet.setContentView(column)
        sheet.show()
        sheet.behavior.state=com.google.android.material.bottomsheet.BottomSheetBehavior.STATE_EXPANDED
    }
    private fun bool(key:String,default:Boolean=true)=prefs.getBoolean(key,default)
    private fun toggle(label:String,key:String,default:Boolean=true):Pair<String,()->Unit> =
        "$label：${if(bool(key,default)) "ON" else "OFF"}" to { switchDialog(label,key,default) }

    private fun switchDialog(label:String,key:String,default:Boolean) {
        val sheet=com.google.android.material.bottomsheet.BottomSheetDialog(activity)
        val column=android.widget.LinearLayout(activity).apply {
            orientation=android.widget.LinearLayout.VERTICAL
            setPadding(20,18,20,18)
            setBackgroundColor(android.graphics.Color.rgb(22,22,22))
        }
        column.addView(android.widget.TextView(activity).apply {
            text=label
            textSize=20f
            setTextColor(android.graphics.Color.WHITE)
            setTypeface(null,android.graphics.Typeface.BOLD)
            setPadding(0,0,0,12)
        })
        val row=android.widget.LinearLayout(activity).apply {
            orientation=android.widget.LinearLayout.HORIZONTAL
            gravity=android.view.Gravity.CENTER_VERTICAL
            setPadding(0,8,0,8)
        }
        row.addView(android.widget.TextView(activity).apply {
            text="無効                         有効"
            textSize=15f
            setTextColor(android.graphics.Color.LTGRAY)
            layoutParams=android.widget.LinearLayout.LayoutParams(0,-2,1f)
        })
        val control=com.google.android.material.switchmaterial.SwitchMaterial(activity).apply {
            isChecked=bool(key,default)
            contentDescription=label
            setOnCheckedChangeListener { _,value ->
                prefs.edit().putBoolean(key,value).apply()
                if(key=="zoneEnabled" && value && Build.VERSION.SDK_INT>=33)
                    ActivityCompat.requestPermissions(activity,arrayOf(Manifest.permission.POST_NOTIFICATIONS),11)
                refresh()
            }
        }
        row.addView(control)
        column.addView(row)
        column.addView(android.widget.Button(activity).apply {
            text="完了"
            setOnClickListener { sheet.dismiss() }
        })
        sheet.setContentView(column)
        sheet.show()
    }
    private fun choice(title:String,key:String,labels:List<String>,values:List<String>,default:String) {
        val selected=prefs.getString(key,default)
        menu(title,labels.mapIndexed { index,label ->
            (if(values.getOrNull(index)==selected) "✓  " else "    ")+label to {
                prefs.edit().putString(key,values[index]).apply();refresh()
            }
        })
    }
    private fun booleanChoice(title:String,key:String,labels:List<String>,default:Boolean=false) {
        val selected=bool(key,default)
        menu(title,labels.mapIndexed { index,label ->
            val value=index==1
            (if(value==selected) "✓  " else "    ")+label to {
                prefs.edit().putBoolean(key,value).apply();refresh()
            }
        })
    }
    private fun number(title:String,key:String,values:List<Int>,default:Int,unit:String) {
        val selected=prefs.getInt(key,default)
        menu(title,values.map { value ->
            (if(value==selected) "✓  " else "    ")+"$value$unit" to {
                prefs.edit().putInt(key,value).apply();refresh()
            }
        })
    }
    fun show():Unit=menu("設定",listOf(
        "単位：${if(bool("metricUnits",false)) "km/h・m/km" else "knot・nm"}" to {
            booleanChoice("単位","metricUnits",listOf("knot・nm","km/h・m/km"))
        },
        "地図の追従方位：${if(bool("preferGpsHeading",false)) "GPS進路" else "磁気コンパス"}" to {
            booleanChoice("地図の追従方位","preferGpsHeading",listOf("磁気コンパス","GPS進路"))
        },
        "計器の北基準：${if(bool("instrumentMagnetic",false)) "磁北" else "真北"}" to {
            booleanChoice("計器の北基準","instrumentMagnetic",listOf("真北","磁北"))
        },
        "コンパス中央の表示：${if(prefs.getString("compassCenterMode","absolute")=="relative") "相対方位" else "絶対方位"}" to {
            choice("コンパス中央の表示","compassCenterMode",listOf("絶対方位","相対方位（左右）"),listOf("absolute","relative"),"absolute")
        },
        "速度・座標・時刻の詳細設定" to ::display,
        "ナビゲーションの詳細設定" to ::navigation,
        "地図" to ::map,
        "ゾーンアラート" to ::zones,
        "デフォルトの保存先：$currentFolder" to {choice("デフォルトの保存先","mainWaypointFolder",folders,folders,currentFolder)},
        "GPS・アプリ情報" to { message("GPS・アプリ情報", gpsStatus + "\n\nSailing GPS ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})") }
    ))
    private fun display():Unit=menu("速度・単位・座標・時刻",listOf(
        "単位：${if(bool("metricUnits",false)) "km/h・m/km" else "knot・nm"}" to {
            booleanChoice("単位","metricUnits",listOf("knot・nm","km/h・m/km"))
        },
        toggle("小数点を大きく表示","largeDecimal"),
        "ゼロ速度の表示補正" to {choice("速度表示だけを補正（記録値は保持）","zeroSpeedThreshold",listOf("補正なし","0.5 knot未満をゼロ","1.0 knot未満をゼロ"),listOf("0","0.5","1.0"),"0")},
        "座標の表示形式" to {choice("座標の表示形式","coordinateFormat",listOf("度分（35°19.0000′N）","度（35.316667°N）","度分秒（35°19′00.0″N）"),listOf("dm","dd","dms"),"dm")},
        toggle("12時間表示","twelveHourClock",false),toggle("画面を自動ロックしない","keepScreenAwake",false)))
    private fun navigation():Unit=menu("ナビゲーション",listOf(
        "地図の追従方位：${if(bool("preferGpsHeading",false)) "GPS進路" else "磁気コンパス"}" to {
            booleanChoice("地図の追従方位","preferGpsHeading",listOf("磁気コンパス","GPS進路"))
        },
        "計器の北基準：${if(bool("instrumentMagnetic",false)) "磁北" else "真北"}" to {
            booleanChoice("計器の北基準","instrumentMagnetic",listOf("真北","磁北"))
        },
        "コンパス中央の表示：${if(prefs.getString("compassCenterMode","absolute")=="relative") "相対方位" else "絶対方位"}" to {
            choice("コンパス中央の表示","compassCenterMode",listOf("絶対方位","相対方位（左右）"),listOf("absolute","relative"),"absolute")
        },
        "平均速度：${if(bool("arrivalUsesAverage",false)) "使用する" else "使用しない"}" to {
            booleanChoice("予想時間の速度","arrivalUsesAverage",listOf("現在の速度","記録中の平均速度"))
        },
        "時間表示：${if(bool("showETA",false)) "到着時刻（ETA）" else "所要時間（ETE）"}" to {
            booleanChoice("時間表示","showETA",listOf("所要時間（ETE）","到着時刻（ETA）"))
        },
        "方位について" to {message("方位について","地図の追従方位と計器の北基準は別々に設定できます。計器は航行中にGPS進路を使い、磁北を選ぶと偏角を補正します。停止中やGPS進路が不安定なときは磁気コンパスに切り替えます。")},
        "予想時間について" to {message("予想時間について","目標までの直線距離を、選択した速度で割って計算します。未取得・低速時は予想を表示しません。")}))
    private fun map():Unit=menu("地図",listOf(
        "進路ライン・距離目盛り：${if(bool("showCourse")) "ON" else "OFF"}" to {prefs.edit().putBoolean("showCourse",!bool("showCourse")).apply();refresh();map()},
        "縮尺・地点表示について" to {message("地図について","地図の＋／−で航行中も縮尺を変更できます。地点名とマークは目標地点も同じ大きさです。")}))
    private fun zones():Unit=menu("ゾーンアラート",listOf(
        toggle("有効","zoneEnabled",false),"監視するエリアを選択" to ::selectZones,
        toggle("エリアに入ったら通知","zoneEnter"),toggle("エリアから出たら通知","zoneExit"),toggle("通知音","zoneSound"),toggle("振動","zoneHaptic"),
        "使用するGPS精度：±${prefs.getInt("zoneAccuracy",50)}m" to {number("使用するGPS精度","zoneAccuracy",listOf(20,50,100),50,"m以内")},
        "境界からの余裕：${prefs.getInt("zoneMargin",10)}m" to {number("境界からの余裕","zoneMargin",listOf(5,10,20),10,"m")},
        "連続確認回数：${prefs.getInt("zoneConfirmations",3)}回" to {number("連続確認回数","zoneConfirmations",listOf(2,3,5),3,"回")},
        "端末の通知：${if(NotificationManagerCompat.from(activity).areNotificationsEnabled()) "許可済み" else "許可が必要"}" to {
            activity.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE,activity.packageName))
        },
        "各設定の意味" to {message("誤通知を抑える設定","GPS精度：指定した誤差以内の測位だけを判定に使います。境界からの余裕：境界から「GPS誤差」と「設定距離」の大きい方より離れるまで判定を保留します。連続確認回数：同じ側の新しい測位が指定回数続いた時に通知します。値を大きくすると誤通知を抑えやすくなりますが、通知は遅くなります。")},
        "動作条件について" to {message("動作条件について","画面表示中、またはGPS記録中に検知します。アプリ終了・記録停止中のバックグラウンドでは監視しません。\n最初の位置は基準として登録し、通知しません。\n境界からGPS誤差と余裕の大きい方以上に離れ、指定回数連続した位置で確定します。小さい円では十分な精度が必要です。\n音と振動は端末の通知設定にも従います.")}))
    private fun selectZones() {
        val areas=library.features.filter{it.kind in listOf("circle","area")}
        if(areas.isEmpty()) {message("監視するエリア","地図ライブラリで円または多角形エリアを作成してください。線は対象外です。");return}
        val ids=(prefs.getString("zoneSelected","") ?: "").split(",").filter{it.isNotBlank()}.toMutableSet()
        val sheet=com.google.android.material.bottomsheet.BottomSheetDialog(activity)
        val density=activity.resources.displayMetrics.density
        val column=android.widget.LinearLayout(activity).apply {
            orientation=android.widget.LinearLayout.VERTICAL
            setPadding((18*density).toInt(),(16*density).toInt(),(18*density).toInt(),(16*density).toInt())
            setBackgroundColor(android.graphics.Color.rgb(15,15,15))
        }
        column.addView(android.widget.TextView(activity).apply {
            text="監視するエリア";textSize=22f;setTextColor(android.graphics.Color.WHITE)
            setTypeface(null,android.graphics.Typeface.BOLD);setPadding(0,0,0,(10*density).toInt())
        })
        areas.forEach { area ->
            column.addView(android.widget.CheckBox(activity).apply {
                text=area.name+if(area.group.isBlank()) "" else "（${area.group}）"
                textSize=17f;setTextColor(android.graphics.Color.WHITE);isChecked=area.id in ids
                minHeight=(52*density).toInt()
                setOnCheckedChangeListener { _,checked -> if(checked) ids.add(area.id) else ids.remove(area.id) }
            })
        }
        val buttons=android.widget.LinearLayout(activity).apply { orientation=android.widget.LinearLayout.HORIZONTAL }
        buttons.addView(android.widget.Button(activity).apply { text="キャンセル";isAllCaps=false;setOnClickListener { sheet.dismiss() } },
            android.widget.LinearLayout.LayoutParams(0,-2,1f))
        buttons.addView(android.widget.Button(activity).apply {
            text="保存";isAllCaps=false;setOnClickListener {
                prefs.edit().putString("zoneSelected",ids.sorted().joinToString(",")).apply()
                refresh();sheet.dismiss()
            }
        },android.widget.LinearLayout.LayoutParams(0,-2,1f))
        column.addView(buttons)
        sheet.setContentView(android.widget.ScrollView(activity).apply { addView(column) })
        sheet.show()
        sheet.behavior.state=com.google.android.material.bottomsheet.BottomSheetBehavior.STATE_EXPANDED
    }
}
