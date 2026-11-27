package com.goldenfalcons.sailinggps

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View
import android.view.animation.LinearInterpolator
import java.util.Locale
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/** Compass-style numeric heading tape with a smoothly scrolling scale. */
class NumericCompassTapeView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {
    private val scale = resources.displayMetrics.scaledDensity
    private val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFF777777.toInt()
        style = Paint.Style.STROKE
        strokeWidth = 1.2f * scale
    }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = android.graphics.Color.WHITE
        textAlign = Paint.Align.CENTER
    }
    private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFFAAAAAA.toInt()
        textAlign = Paint.Align.LEFT
    }
    private val rulerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFFBBBBBB.toInt()
        strokeWidth = 1f * scale
    }
    private val accentPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFFFFAA00.toInt()
        strokeWidth = 1.7f * scale
        strokeCap = Paint.Cap.ROUND
    }
    private var value: Double? = null
    private var animatedHeading: Float? = null
    private var headingAnimator: ValueAnimator? = null
    private var compassLabel = "方位"

    fun setReading(heading: Double?, label: String) {
        val next = heading?.takeIf { it.isFinite() && it >= 0 }?.rem(360.0)?.toFloat()
        value = next?.toDouble()
        compassLabel = label
        contentDescription = "$label ${next?.let { String.format(Locale.ROOT, "%.0f°", it) } ?: "--"}"

        headingAnimator?.cancel()
        val current = animatedHeading
        if (next == null) {
            animatedHeading = null
        } else if (current == null) {
            animatedHeading = next
        } else {
            val currentNormalized = (current % 360f + 360f) % 360f
            val delta = ((next - currentNormalized + 540f) % 360f) - 180f
            headingAnimator = ValueAnimator.ofFloat(current, current + delta).apply {
                duration = 240L
                interpolator = LinearInterpolator()
                addUpdateListener {
                    animatedHeading = it.animatedValue as Float
                    invalidate()
                }
                start()
            }
        }
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0f || h <= 0f) return

        val inset = max(0.7f, scale)
        canvas.drawRoundRect(RectF(inset, inset, w - inset, h - inset), 12f * scale, 12f * scale, border)

        val separator = w * 0.37f
        canvas.drawLine(separator, 8f * scale, separator, h - 8f * scale, accentPaint)

        labelPaint.textSize = min(11f * scale, h * 0.17f)
        canvas.drawText(compassLabel, 9f * scale, min(18f * scale, h * 0.23f), labelPaint)

        textPaint.typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL)
        textPaint.textSize = min(36f * scale, h * 0.53f)
        val animatedValue = animatedHeading?.let { ((it % 360f) + 360f) % 360f }
        val largeValue = if (value == null) "---" else String.format(Locale.ROOT, "%.0f°", animatedValue ?: value!!.toFloat())
        canvas.drawText(largeValue, separator / 2f, h * 0.73f, textPaint)

        val left = separator + 8f * scale
        val right = w - 8f * scale
        val center = (left + right) / 2f
        val rulerWidth = right - left
        if (rulerWidth <= 0f) return

        val degreesVisible = 48f
        val pixelsPerDegree = rulerWidth / degreesVisible
        val heading = animatedHeading ?: 0f
        val baseDegree = floor(heading).toInt()
        val fractionalDegree = heading - baseDegree
        val baseline = h * 0.76f
        canvas.drawLine(left, baseline, right, baseline, rulerPaint)

        for (step in -24..24) {
            val degree = baseDegree + step
            val normalized = (degree % 360 + 360) % 360
            val x = center + (step - fractionalDegree) * pixelsPerDegree
            if (x < left - 2f * scale || x > right + 2f * scale) continue

            val major = normalized % 30 == 0
            val medium = normalized % 10 == 0
            val tickHeight = when {
                major -> h * 0.30f
                medium -> h * 0.20f
                else -> h * 0.10f
            }
            rulerPaint.strokeWidth = if (major) 1.5f * scale else 1f * scale
            rulerPaint.alpha = if (major) 245 else if (medium) 190 else 125
            canvas.drawLine(x, baseline - tickHeight, x, baseline, rulerPaint)

            if (medium) {
                textPaint.typeface = android.graphics.Typeface.create("monospace", android.graphics.Typeface.NORMAL)
                textPaint.textSize = min((if (major) 9f else 7.5f) * scale, h * 0.14f)
                textPaint.alpha = if (major) 245 else 210
                canvas.drawText(String.format(Locale.ROOT, "%03d°", normalized), x, h - 6f * scale, textPaint)
            }
        }

        // The fixed orange index points to the current heading while the degree tape slides beneath it.
        val pointerTop = 4f * scale
        val pointerTip = min(h * 0.25f, 16f * scale)
        val pointer = Path().apply {
            moveTo(center, pointerTop)
            lineTo(center - 5f * scale, pointerTip)
            lineTo(center + 5f * scale, pointerTip)
            close()
        }
        canvas.drawPath(pointer, accentPaint)
        canvas.drawLine(center, pointerTip, center, baseline, accentPaint)
        rulerPaint.alpha = 255
    }
}
