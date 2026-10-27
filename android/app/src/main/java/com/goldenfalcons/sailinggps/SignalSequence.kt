package com.goldenfalcons.sailinggps

data class SignalEvent(val id:Int,val secondsBeforeStart:Int,val title:String,val color:Int,val raised:Boolean,val flag:String)

object SignalSequence {
    private val template=listOf(
        SignalEvent(0,300,"オレンジ旗を掲揚",android.graphics.Color.rgb(245,138,0),true,"橙"),
        SignalEvent(1,240,"グリーン旗を掲揚",android.graphics.Color.rgb(24,212,75),true,"緑"),
        SignalEvent(2,180,"ブルー旗を掲揚",android.graphics.Color.rgb(23,105,255),true,"青"),
        SignalEvent(3,120,"ブルー旗を降下",android.graphics.Color.rgb(23,105,255),false,"青"),
        SignalEvent(4,60,"グリーン旗を降下",android.graphics.Color.rgb(24,212,75),false,"緑"),
        SignalEvent(5,0,"グリーン start at",android.graphics.Color.rgb(245,138,0),false,"橙")
    )
    fun events(durationMinutes:Int):List<SignalEvent> = template.map { it.copy(secondsBeforeStart=(it.secondsBeforeStart*durationMinutes.coerceAtLeast(1)/5.0).toInt()) }
    fun nextIndex(secondsUntilStart:Double,durationMinutes:Int):Int {
        val events=events(durationMinutes)
        return events.indexOfFirst { secondsUntilStart >= it.secondsBeforeStart }.let { if(it<0) events.lastIndex else it }
    }
    fun untilNext(secondsUntilStart:Double,index:Int,durationMinutes:Int):Int = kotlin.math.ceil(secondsUntilStart-events(durationMinutes)[index].secondsBeforeStart).toInt()
}
