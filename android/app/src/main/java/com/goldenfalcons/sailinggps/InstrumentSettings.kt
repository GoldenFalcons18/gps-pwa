package com.goldenfalcons.sailinggps

import kotlin.math.*
import java.util.Locale

object InstrumentSettings {
    fun coordinate(value:Double,isLat:Boolean,format:String):String {
        if(!value.isFinite()) return "—"
        if(format=="dm") return NavigationUtils.formatDm(value,isLat)
        val direction=if(isLat) {if(value<0) "S" else "N"} else {if(value<0) "W" else "E"}
        if(format=="dd") return String.format(Locale.US,"%.6f°%s",abs(value),direction)
        val total=round(abs(value)*36000)/10
        return String.format(Locale.US,"%d°%02d′%04.1f″%s",(total/3600).toInt(),(total/60).toInt()%60,total%60,direction)
    }
    fun arrival(distance:Double,speed:Double?,now:Long,eta:Boolean,twelveHour:Boolean):String {
        val duration=NavigationUtils.ete(distance,speed)
        if(!eta || duration=="--:--:--" || speed==null || speed<=0) return duration
        return java.text.SimpleDateFormat(if(twelveHour) "h:mm:ss a" else "HH:mm:ss",Locale.US).format(java.util.Date(now+ceil(distance/speed).toLong()*1000))
    }
}
