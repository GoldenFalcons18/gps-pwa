package com.goldenfalcons.sailinggps

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View
import java.util.Locale
import kotlin.math.roundToInt

/** Compact numeric compass tape for the bottom navigation readout. */
class NumericCompassTapeView @JvmOverloads constructor(context: Context, attrs: AttributeSet? = null) : View(context, attrs) {
    private val scale = resources.displayMetrics.scaledDensity
    private val border = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF777777.toInt(); style = Paint.Style.STROKE; strokeWidth = 1.2f * scale }
    private val white = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.WHITE; textAlign = Paint.Align.CENTER }
    private val gray = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFFAAAAAA.toInt(); textAlign = Paint.Align.LEFT }
    private val orange = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFFFFAA00.toInt(); strokeWidth = 1.5f * scale }
    private var value: Double? = null
    private var compassLabel = "方位"
    fun setReading(heading: Double?, label: String) {
        value = heading?.takeIf { it.isFinite() && it >= 0 }
        compassLabel = label
        contentDescription = "$label ${value?.let { String.format(Locale.ROOT, "%.0f°", it) } ?: "--"}"
        invalidate()
    }
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat(); val h = height.toFloat()
        canvas.drawRoundRect(RectF(0.7f, 0.7f, w - 0.7f, h - 0.7f), 12f * scale, 12f * scale, border)
        val separator = w * 0.37f
        canvas.drawLine(separator, 8f * scale, separator, h - 8f * scale, orange)
        gray.textSize = 11f * scale
        canvas.drawText(compassLabel, 9f * scale, 18f * scale, gray)
        white.textSize = 36f * scale
        white.typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL)
        canvas.drawText(value?.let { String.format(Locale.ROOT, "%.0f°", it) } ?: "---", separator / 2, h * 0.72f, white)
        val left = separator + 8f * scale; val right = w - 8f * scale; val center = (left + right) / 2; val half = (right - left) / 2
        val bearing = value?.roundToInt() ?: 0
        for (step in -4..4) {
            val x = center + step * half / 4; val major = step % 3 == 0; val length = if (major) 18f * scale else 9f * scale
            white.color = android.graphics.Color.WHITE; white.alpha = if (major) 235 else 150
            val tickPaint = if (step == 0) orange else white
            canvas.drawLine(x, h / 2 - length / 2, x, h / 2 + length / 2, tickPaint)
            if (major) {
                val degree = (bearing + (step * 10) % 360 + 360) % 360
                white.color = android.graphics.Color.WHITE; white.alpha = 255; white.textSize = 10f * scale
                white.typeface = android.graphics.Typeface.create("monospace", android.graphics.Typeface.NORMAL)
                canvas.drawText("$degree°", x, h - 8f * scale, white)
            }
        }
        canvas.drawLine(center, 5f * scale, center, h - 5f * scale, orange)
    }
}