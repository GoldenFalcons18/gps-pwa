package com.goldenfalcons.sailinggps

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View
import java.util.Locale

/** Seven segment SOG display, scaled to the available width. */
class SpeedDisplayView(context: Context, attrs: AttributeSet? = null) : View(context, attrs) {
    var speedKnots: Double? = null
        set(value) { field = value; invalidate(); contentDescription = value?.let { "対地速度 %.1f ノット".format(it) } ?: "対地速度 未取得" }
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val masks = intArrayOf(0x3f, 0x06, 0x5b, 0x4f, 0x66, 0x6d, 0x7d, 0x07, 0x7f, 0x6f)

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val value = speedKnots?.takeIf { it.isFinite() && it >= 0 }?.let { String.format(Locale.US, "%.1f", it) } ?: "--.-"
        val slots = value.fold(0f) { total, char -> total + if (char == '.') 22f else 100f }
        val scale = minOf(width / slots, height / 180f)
        canvas.save()
        canvas.translate((width - slots * scale) / 2f, (height - 180f * scale) / 2f)
        canvas.scale(scale, scale)
        value.forEach { char ->
            if (char == '.') {
                paint.color = Color.rgb(0, 255, 35)
                canvas.drawCircle(9f, 164f, 7f, paint)
                canvas.translate(22f, 0f)
            } else {
                val mask = if (char.isDigit()) masks[char.digitToInt()] else 0x40
                val rects = arrayOf(
                    floatArrayOf(17f, 4f, 77f, 16f), floatArrayOf(78f, 17f, 90f, 82f),
                    floatArrayOf(78f, 96f, 90f, 161f), floatArrayOf(17f, 162f, 77f, 174f),
                    floatArrayOf(4f, 96f, 16f, 161f), floatArrayOf(4f, 17f, 16f, 82f),
                    floatArrayOf(17f, 83f, 77f, 95f)
                )
                rects.forEachIndexed { index, r ->
                    paint.color = if (mask and (1 shl index) != 0) Color.rgb(0, 255, 35) else Color.rgb(17, 17, 17)
                    canvas.drawRoundRect(r[0], r[1], r[2], r[3], 3f, 3f, paint)
                }
                canvas.translate(100f, 0f)
            }
        }
        canvas.restore()
    }
}
