package com.goldenfalcons.sailinggps

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.util.AttributeSet
import android.view.View
import kotlin.math.*

class InstrumentView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    enum class Mode { RELATIVE, ABSOLUTE }

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var targetAngle = 0f
    private var currentAngle = 0f
    private var relativeAngle = 0f
    private var compassHeading = 0f
    private var centerText = "--"
    private var sideText = "--"
    var mode: Mode = Mode.RELATIVE
        set(value) {
            field = value
            invalidate()
        }

    fun update(relativeDeg: Double?, absoluteBearing: Double?) {
        if (relativeDeg == null || absoluteBearing == null) {
            centerText = "--"
            sideText = "--"
            invalidate()
            return
        }
        compassHeading = NavigationUtils.normalize360(absoluteBearing - relativeDeg).toFloat()
        relativeAngle = relativeDeg.toFloat()
        targetAngle = when (mode) {
            Mode.RELATIVE -> NavigationUtils.normalize360(relativeDeg).toFloat()
            Mode.ABSOLUTE -> NavigationUtils.normalize360(absoluteBearing).toFloat()
        }
        centerText = "${absoluteBearing.roundToInt()}°"
        sideText = NavigationUtils.relativeText(relativeDeg)
        postInvalidateOnAnimation()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        val cx = w / 2f
        val cy = h / 2f
        val radius = min(w, h) * 0.43f

        // Smooth triangle animation every frame
        val diff = normalize180f(targetAngle - currentAngle)
        currentAngle += diff * 0.22f
        if (abs(diff) > 0.1f) postInvalidateOnAnimation()

        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 4f
        paint.color = Color.GRAY
        canvas.drawCircle(cx, cy, radius, paint)

        canvas.save()
        if (mode == Mode.RELATIVE) canvas.rotate(-compassHeading, cx, cy)
        // outer ticks
        for (deg in 0 until 360 step 10) {
            val a = Math.toRadians((deg - 90).toDouble())
            val outer = radius
            val inner = radius - if (deg % 30 == 0) 16f else 9f
            paint.strokeWidth = if (deg % 30 == 0) 3f else 1.5f
            paint.color = Color.LTGRAY
            canvas.drawLine(
                cx + cos(a).toFloat() * inner,
                cy + sin(a).toFloat() * inner,
                cx + cos(a).toFloat() * outer,
                cy + sin(a).toFloat() * outer,
                paint
            )
        }

        paint.style = Paint.Style.FILL
        paint.textAlign = Paint.Align.CENTER
        paint.typeface = android.graphics.Typeface.DEFAULT_BOLD
        paint.color = Color.LTGRAY
        paint.textSize = 22f

        canvas.drawText("北", cx, cy - radius + 36f, paint)
        canvas.drawText("東", cx + radius - 25f, cy + 7f, paint)
        canvas.drawText("南", cx, cy + radius - 18f, paint)
        canvas.drawText("西", cx - radius + 25f, cy + 7f, paint)
        canvas.restore()

        // triangle at circumference, vertex points outward
        val rad = Math.toRadians((currentAngle - 90).toDouble())
        val ux = cos(rad).toFloat()
        val uy = sin(rad).toFloat()
        val tx = -uy
        val ty = ux

        val tipR = radius + 2f
        val baseR = radius - 40f
        val halfBase = 20f

        val tipX = cx + ux * tipR
        val tipY = cy + uy * tipR
        val baseCx = cx + ux * baseR
        val baseCy = cy + uy * baseR

        val path = Path().apply {
            moveTo(tipX, tipY)
            lineTo(baseCx + tx * halfBase, baseCy + ty * halfBase)
            lineTo(baseCx - tx * halfBase, baseCy - ty * halfBase)
            close()
        }

        paint.color = Color.GREEN
        canvas.drawPath(path, paint)

        paint.textSize = 18f
        paint.color = Color.LTGRAY
        canvas.drawText("目標方位（真北）", cx, cy - 18f, paint)

        paint.textSize = 48f
        paint.color = Color.GREEN
        canvas.drawText(centerText, cx, cy + 34f, paint)

        paint.textSize = 17f
        canvas.drawText(sideText, cx, cy + 62f, paint)
    }

    private fun normalize180f(v: Float): Float {
        var r = v % 360f
        if (r > 180f) r -= 360f
        if (r < -180f) r += 360f
        return r
    }
}
