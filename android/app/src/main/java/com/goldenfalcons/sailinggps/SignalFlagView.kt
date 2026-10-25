package com.goldenfalcons.sailinggps

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.util.AttributeSet
import android.view.View
import kotlin.math.sin

/** Animated race flags: warning, preparatory, one-minute warning, and start. */
class SignalFlagView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null
) : View(context, attrs) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var stage = "idle"
    private var frame = 0
    fun setSignalState(value: String) {
        if (stage != value) {
            stage = value
            invalidate()
        }
    }
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat(); val h = height.toFloat()
        if (w <= 0 || h <= 0) return
        val poleX = w * 0.5f
        paint.style = Paint.Style.STROKE; paint.strokeWidth = 5f; paint.color = 0xffcccccc.toInt()
        canvas.drawLine(poleX, h * .08f, poleX, h * .92f, paint)
        val elapsed = frame++ * .09
        val flags = when (stage) {
            "start" -> listOf(0xff00d65a.toInt(), 0xffffffff.toInt())
            "one-minute" -> listOf(0xffffaa00.toInt())
            "preparatory" -> listOf(0xffffaa00.toInt(), 0xff244bff.toInt())
            "warning" -> listOf(0xffffaa00.toInt())
            else -> emptyList()
        }
        flags.forEachIndexed { index, color ->
            val top = h * (.14f + index * .30f)
            val fw = w * .38f; val fh = h * .24f
            paint.style = Paint.Style.FILL; paint.color = color
            val path = Path().apply { moveTo(poleX, top) }
            val steps = 14
            for (i in 0..steps) {
                val x = poleX + fw * i / steps
                val wave = (sin(elapsed + i * .42) * h * .018).toFloat()
                path.lineTo(x, top + wave)
            }
            for (i in steps downTo 0) {
                val x = poleX + fw * i / steps
                val wave = (sin(elapsed + i * .42 + 1.1) * h * .018).toFloat()
                path.lineTo(x, top + fh + wave)
            }
            path.close(); canvas.drawPath(path, paint)
            paint.color = 0xff111111.toInt(); paint.textSize = fh * .42f
            paint.textAlign = Paint.Align.CENTER
            canvas.drawText(if (stage == "start") "START" else if (index == 0) "P" else "I", poleX + fw * .5f, top + fh * .62f, paint)
        }
        if (isShown && stage != "idle" && stage != "start") postInvalidateDelayed(55)
    }
}