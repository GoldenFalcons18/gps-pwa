package com.goldenfalcons.sailinggps

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View

class SignalMastView @JvmOverloads constructor(context: Context, attrs: AttributeSet? = null) : View(context, attrs) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var previous = emptyList<SignalFlagState>()
    private var flags = emptyList<SignalFlagState>()
    private var progress = 1f

    fun show(states: List<SignalFlagState>, animate: Boolean) {
        if (states == flags) return
        previous = flags
        flags = states
        if (animate) {
            ValueAnimator.ofFloat(0f, 1f).apply {
                duration = 420
                addUpdateListener { progress = it.animatedValue as Float; invalidate() }
                start()
            }
        } else {
            progress = 1f
            invalidate()
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        canvas.drawColor(0xff69cff2.toInt())

        val poleXs = listOf(0.03f, 0.23f, 0.43f, 0.65f, 0.84f).map { w * it }
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = (w * 0.012f).coerceAtLeast(2f)
        poleXs.forEachIndexed { index, x ->
            paint.color = if (index == 1) 0xffff8800.toInt() else 0xff555555.toInt()
            canvas.drawLine(x, h * 0.26f, x, h * 0.95f, paint)
        }
        paint.style = Paint.Style.FILL
        paint.color = 0xff555555.toInt()
        canvas.drawRect(w * 0.02f, h * 0.95f, w * 0.98f, h * 0.97f, paint)

        flags.forEachIndexed { index, state ->
            if (!state.raised && previous.getOrNull(index)?.raised != true) return@forEachIndexed
            val poleIndex = when (index) { 0 -> 1; 1 -> 3; 2 -> 2; 3 -> 4; else -> 0 }
            val mastX = poleXs[poleIndex]
            val flagWidth = w * 0.18f
            val flagHeight = h * 0.24f
            val topY = h * 0.28f
            val downY = h * 0.72f
            val oldRaised = previous.getOrNull(index)?.raised ?: false
            val y = if (oldRaised == state.raised) {
                if (state.raised) topY else downY
            } else if (state.raised) {
                downY + (topY - downY) * progress
            } else {
                topY + (downY - topY) * progress
            }
            paint.color = state.color
            canvas.drawRect(RectF(mastX, y, (mastX + flagWidth).coerceAtMost(w), (y + flagHeight).coerceAtMost(h)), paint)
            canvas.drawRect(RectF(mastX, y, (mastX + flagWidth).coerceAtMost(w), (y + flagHeight).coerceAtMost(h)), paint)
            when (state.id) {
                "X" -> {
                    paint.color = 0xffffffff.toInt()
                    canvas.drawRect(mastX, y, mastX + flagWidth, y + flagHeight, paint)
                    paint.color = 0xff1769ff.toInt()
                    paint.style = Paint.Style.STROKE
                    paint.strokeWidth = flagHeight * 0.20f
                    canvas.drawLine(mastX, y, mastX + flagWidth, y + flagHeight, paint)
                    canvas.drawLine(mastX + flagWidth, y, mastX, y + flagHeight, paint)
                    paint.style = Paint.Style.FILL
                }
                "AP" -> {
                    paint.color = 0xffffffff.toInt()
                    canvas.drawRect(mastX, y, mastX + flagWidth, y + flagHeight, paint)
                    paint.color = 0xffd71920.toInt()
                    canvas.drawRect(mastX, y, mastX + flagWidth * 0.5f, y + flagHeight, paint)
                }
                "第一代表" -> {
                    paint.color = 0xff1769ff.toInt()
                    canvas.drawRect(mastX, y, mastX + flagWidth, y + flagHeight, paint)
                    paint.color = 0xffd71920.toInt()
                    val triangle = android.graphics.Path().apply {
                        moveTo(mastX, y)
                        lineTo(mastX + flagWidth, y + flagHeight)
                        lineTo(mastX + flagWidth, y)
                        close()
                    }
                    canvas.drawPath(triangle, paint)
                }
            }
            if (state.whiteSquare) {
                paint.color = 0xffffffff.toInt()
                val inset = flagWidth * 0.34f
                val square = flagWidth * 0.32f
                canvas.drawRect(mastX + inset, y + flagHeight * 0.34f, mastX + inset + square, y + flagHeight * 0.66f, paint)
            }
        }
    }
}
