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
        AlertDialog.Builder(activity).setTitle(title).setItems(items.map{it.first}.toTypedArray()){_,index->items[index].second()}.setNegativeButton("閉じる",null).show()
    }
    private fun bool(key:String,default:Boolean=true)=prefs.getBoolean(key,default)
    private fun toggle(label:String,key:String,default:Boolean=true):Pair<String,()->Unit> {
        return "$label：${if(bool(key,default)) "ON" else "OFF"}" to {
            val value=!bool(key,default);prefs.edit().putBoolean(key,value).apply()
            if(key=="zoneEnabled" && value && Build.VERSION.SDK_INT>=33) ActivityCompat.requestPermissions(activity,arrayOf(Manifest.permission.POST_NOTIFICATIONS),11)
            refresh();if(key.startsWith("zone")) zones() else display()
        }
    }
    private fun choice(title:String,key:String,labels:List<String>,values:List<String>,default:String) {
        AlertDialog.Builder(activity).setTitle(title).setSingleChoiceItems(labels.toTypedArray(),values.indexOf(prefs.getString(key,default))){dialog,index->
            prefs.edit().putString(key,values[index]).apply();refresh();dialog.dismiss()
        }.setNegativeButton("キャンセル",null).show()
    }
    private fun number(title:String,key:String,values:List<Int>,default:Int,unit:String) {
        AlertDialog.Builder(activity).setTitle(title).setSingleChoiceItems(values.map{"$it$unit"}.toTypedArray(),values.indexOf(prefs.getInt(key,default))){dialog,index->
            prefs.edit().putInt(key,values[index]).apply();refresh();dialog.dismiss()
        }.setNegativeButton("キャンセル",null).show()
    }
    fun show():Unit=menu("設定",listOf("速度・単位・座標・時刻" to ::display,"ナビゲーション" to ::navigation,"地図" to ::map,"ゾーンアラート" to ::zones,
        "デフォルトの保存先：$currentFolder" to {choice("デフォルトの保存先","mainWaypointFolder",folders,folders,currentFolder)},
        "GPS・アプリ情報" to {AlertDialog.Builder(activity).setTitle("GPS・アプリ情報").setMessage(gpsStatus+"\n\nSailing GPS ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})").setPositiveButton("閉じる",null).show()}))
    private fun display():Unit=menu("速度・単位・座標・時刻",listOf(
        "単位：${if(bool("metricUnits",false)) "km/h・m/km" else "knot・nm"}" to {
            AlertDialog.Builder(activity).setTitle("単位").setSingleChoiceItems(arrayOf("knot・nm","km/h・m/km"),if(bool("metricUnits",false)) 1 else 0){dialog,index->prefs.edit().putBoolean("metricUnits",index==1).apply();refresh();dialog.dismiss()}.show()
        },
        toggle("小数点を大きく表示","largeDecimal"),
        "ゼロ速度の表示補正" to {choice("速度表示だけを補正（記録値は保持）","zeroSpeedThreshold",listOf("補正なし","0.5 knot未満をゼロ","1.0 knot未満をゼロ"),listOf("0","0.5","1.0"),"0")},
        "座標の表示形式" to {choice("座標の表示形式","coordinateFormat",listOf("度分（35°19.0000′N）","度（35.316667°N）","度分秒（35°19′00.0″N）"),listOf("dm","dd","dms"),"dm")},
        toggle("12時間表示","twelveHourClock",false),toggle("画面を自動ロックしない","keepScreenAwake",false)))
    private fun navigation():Unit=menu("ナビゲーション",listOf(
        "方位ソース：${if(bool("preferGpsHeading",false)) "GPS進行方位を優先" else "磁気コンパスを優先"}" to {
            prefs.edit().putBoolean("preferGpsHeading",!bool("preferGpsHeading",false)).apply();refresh();navigation()
        },
        "予想時間の計算：${if(bool("arrivalUsesAverage",false)) "記録中の平均速度" else "現在の速度"}" to {
            prefs.edit().putBoolean("arrivalUsesAverage",!bool("arrivalUsesAverage",false)).apply();refresh();navigation()
        },
        "時間の表示：${if(bool("showETA",false)) "到着時刻（ETA）" else "所要時間（ETE）"}" to {
            prefs.edit().putBoolean("showETA",!bool("showETA",false)).apply();refresh();navigation()
        },
        "計算方法について" to {AlertDialog.Builder(activity).setMessage("目標までの直線距離で計算します。平均速度は有効なGPS位置間の移動距離÷時間です。未取得・低速時は予想を表示しません。").setPositiveButton("閉じる",null).show()}))
    private fun map():Unit=menu("地図",listOf(
        "進路ライン・距離目盛り：${if(bool("showCourse")) "ON" else "OFF"}" to {prefs.edit().putBoolean("showCourse",!bool("showCourse")).apply();refresh();map()},
        "縮尺・地点表示について" to {AlertDialog.Builder(activity).setMessage("地図の＋／−で航行中も縮尺を変更できます。地点名とマークは目標地点も同じ大きさです。").setPositiveButton("閉じる",null).show()}))
    private fun zones():Unit=menu("ゾーンアラート",listOf(
        toggle("有効","zoneEnabled",false),"監視するエリアを選択" to ::selectZones,
        toggle("エリアに入ったら通知","zoneEnter"),toggle("エリアから出たら通知","zoneExit"),toggle("通知音","zoneSound"),toggle("振動","zoneHaptic"),
        "使用するGPS精度：±${prefs.getInt("zoneAccuracy",50)}m" to {number("使用するGPS精度","zoneAccuracy",listOf(20,50,100),50,"m以内")},
        "境界からの余裕：${prefs.getInt("zoneMargin",10)}m" to {number("境界からの余裕","zoneMargin",listOf(5,10,20),10,"m")},
        "連続確認回数：${prefs.getInt("zoneConfirmations",3)}回" to {number("連続確認回数","zoneConfirmations",listOf(2,3,5),3,"回")},
        "端末の通知：${if(NotificationManagerCompat.from(activity).areNotificationsEnabled()) "許可済み" else "許可が必要"}" to {
            activity.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE,activity.packageName))
        },
        "動作条件について" to {AlertDialog.Builder(activity).setMessage("画面表示中、またはGPS記録中に検知します。アプリ終了・記録停止中のバックグラウンドでは監視しません。\n最初の位置は基準として登録し、通知しません。\n境界からGPS誤差と余裕の大きい方以上に離れ、指定回数連続した位置で確定します。小さい円では十分な精度が必要です。\n音と振動は端末の通知設定にも従います。").setPositiveButton("閉じる",null).show()}))
    private fun selectZones() {
        val areas=library.features.filter{it.kind in listOf("circle","area")}
        if(areas.isEmpty()) {AlertDialog.Builder(activity).setMessage("地図ライブラリで円または多角形エリアを作成してください。線は対象外です。").setPositiveButton("閉じる",null).show();return}
        val ids=(prefs.getString("zoneSelected","") ?: "").split(",").filter{it.isNotBlank()}.toMutableSet()
        AlertDialog.Builder(activity).setTitle("監視するエリア").setMultiChoiceItems(areas.map{it.name+if(it.group.isBlank()) "" else "（${it.group}）"}.toTypedArray(),areas.map{it.id in ids}.toBooleanArray()){_,index,enabled->
            if(enabled) ids.add(areas[index].id) else ids.remove(areas[index].id)
        }.setPositiveButton("保存"){_,_->prefs.edit().putString("zoneSelected",ids.sorted().joinToString(",")).apply();refresh()}.setNegativeButton("キャンセル",null).show()
    }
}
