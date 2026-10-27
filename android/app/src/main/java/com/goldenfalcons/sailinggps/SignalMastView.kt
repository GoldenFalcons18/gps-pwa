package com.goldenfalcons.sailinggps

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.util.AttributeSet
import android.view.View

class SignalMastView @JvmOverloads constructor(context:Context,attrs:AttributeSet?=null):View(context,attrs) {
    private val paint=Paint(Paint.ANTI_ALIAS_FLAG)
    private var flagColor=0xffff8800.toInt()
    private var raised=true
    private var wave=0f
    fun show(event:SignalEvent,animate:Boolean) {
        val changed=flagColor!=event.color || raised!=event.raised
        flagColor=event.color;raised=event.raised
        if(changed && animate) ValueAnimator.ofFloat(0f,1f).apply {
            duration=420
            addUpdateListener { wave=it.animatedValue as Float;invalidate() }
            start()
        } else invalidate()
    }
    override fun onDraw(canvas:Canvas) {
        super.onDraw(canvas)
        val w=width.toFloat();val h=height.toFloat()
        canvas.drawColor(0xff55b8e8.toInt())
        paint.color=0xff777777.toInt();paint.strokeWidth=(w*0.035f).coerceAtLeast(2f);paint.style=Paint.Style.STROKE
        val mastX=w*0.18f
        canvas.drawLine(mastX,h*0.05f,mastX,h*0.95f,paint)
        paint.style=Paint.Style.FILL;paint.color=0xff777777.toInt();canvas.drawRect(w*0.05f,h*0.94f,w*0.92f,h*0.97f,paint)
        val top=if(raised) h*(0.06f+wave*0.02f) else h*0.61f
        val flag=Path().apply {moveTo(mastX,top);lineTo(w*0.86f,top);lineTo(w*0.80f,top+h*0.30f);lineTo(mastX,top+h*0.30f);close()}
        paint.color=flagColor;canvas.drawPath(flag,paint)
        paint.color=0xffffffff.toInt();paint.textAlign=Paint.Align.CENTER;paint.textSize=h*0.12f
        canvas.drawText("旗",(mastX+w*0.83f)/2f,top+h*0.2f,paint)
    }
}
