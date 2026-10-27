package com.goldenfalcons.sailinggps
data class SignalEvent(val id:Int,val secondsBeforeStart:Int,val title:String,val color:Int,val raised:Boolean,val flag:String)
data class SignalFlagProfile(val id:String,val name:String,val events:List<SignalEvent>)
object SignalSequence {
    private fun e(id:Int,s:Int,t:String,f:String,c:Int,u:Boolean)=SignalEvent(id,s,t,c,u,f)
    val profiles=listOf(
        SignalFlagProfile("class-p","クラス旗＋P旗",listOf(e(0,300,"クラス旗を掲揚","級",android.graphics.Color.rgb(245,138,0),true),e(1,240,"P旗を掲揚","P",android.graphics.Color.rgb(23,105,255),true),e(2,60,"P旗を降下","P",android.graphics.Color.rgb(23,105,255),false),e(3,0,"クラス旗を降下","級",android.graphics.Color.rgb(245,138,0),false))),
        SignalFlagProfile("class-i","クラス旗＋I旗",listOf(e(0,300,"クラス旗を掲揚","級",android.graphics.Color.rgb(245,138,0),true),e(1,240,"I旗を掲揚","I",android.graphics.Color.rgb(245,211,40),true),e(2,60,"I旗を降下","I",android.graphics.Color.rgb(245,211,40),false),e(3,0,"クラス旗を降下","級",android.graphics.Color.rgb(245,138,0),false))),
        SignalFlagProfile("class-u","クラス旗＋U旗",listOf(e(0,300,"クラス旗を掲揚","級",android.graphics.Color.rgb(245,138,0),true),e(1,240,"U旗を掲揚","U",android.graphics.Color.rgb(215,44,50),true),e(2,60,"U旗を降下","U",android.graphics.Color.rgb(215,44,50),false),e(3,0,"クラス旗を降下","級",android.graphics.Color.rgb(245,138,0),false))),
        SignalFlagProfile("class-black","クラス旗＋黒旗",listOf(e(0,300,"クラス旗を掲揚","級",android.graphics.Color.rgb(245,138,0),true),e(1,240,"黒旗を掲揚","黒",android.graphics.Color.rgb(32,32,32),true),e(2,60,"黒旗を降下","黒",android.graphics.Color.rgb(32,32,32),false),e(3,0,"クラス旗を降下","級",android.graphics.Color.rgb(245,138,0),false))),
        SignalFlagProfile("class-p-i","クラス旗＋P旗＋I旗",listOf(e(0,300,"クラス旗を掲揚","級",android.graphics.Color.rgb(245,138,0),true),e(1,240,"P旗を掲揚","P",android.graphics.Color.rgb(23,105,255),true),e(2,180,"I旗を掲揚","I",android.graphics.Color.rgb(245,211,40),true),e(3,120,"I旗を降下","I",android.graphics.Color.rgb(245,211,40),false),e(4,60,"P旗を降下","P",android.graphics.Color.rgb(23,105,255),false),e(5,0,"クラス旗を降下","級",android.graphics.Color.rgb(245,138,0),false))))
    fun events(minutes:Int,profileIndex:Int=0):List<SignalEvent>{val d=minutes.coerceAtLeast(1);return profiles.getOrElse(profileIndex){profiles[0]}.events.map{it.copy(secondsBeforeStart=(it.secondsBeforeStart*d/5.0).toInt())}}
    fun nextIndex(left:Double,minutes:Int,profileIndex:Int=0):Int{val es=events(minutes,profileIndex);return es.indexOfFirst{left>=it.secondsBeforeStart}.let{if(it<0)es.lastIndex else it}}
    fun untilNext(left:Double,index:Int,minutes:Int,profileIndex:Int=0)=kotlin.math.ceil(left-events(minutes,profileIndex)[index].secondsBeforeStart).toInt()
}