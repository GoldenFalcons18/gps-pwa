package com.goldenfalcons.sailinggps

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Bitmap
import android.graphics.Paint
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View

class SignalMastView @JvmOverloads constructor(context: Context, attrs: AttributeSet? = null) : View(context, attrs) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var previous = emptyList<SignalFlagState>()
    private var flags = emptyList<SignalFlagState>()
    private var progress = 1f
    private val artworkCache = mutableMapOf<String, Bitmap>()

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

    private fun drawInternationalArtwork(canvas: Canvas, state: SignalFlagState, bounds: RectF) {
        val name = when (state.id) {
            "AP" -> "Answering Pennant"
            "第一代表" -> "First Substitute"
            "Z" -> "Zulu"
            "L" -> "Lima"
            else -> state.id
        }
        val bitmap = artworkCache.getOrPut(name) {
            val width = 300
            val height = 200
            val image = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val artwork = SignalFlagArtworkView(context, name)
            artwork.measure(
                MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY),
                MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY)
            )
            artwork.layout(0, 0, width, height)
            artwork.draw(Canvas(image))
            image
        }
        canvas.drawBitmap(bitmap, null, bounds, paint)
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
            val flagRect = RectF(mastX, y, (mastX + flagWidth).coerceAtMost(w), (y + flagHeight).coerceAtMost(h))
            val classFlag = state.id.startsWith("class-") || state.id == "級"
            val white = 0xFFFFFFFF.toInt()
            val black = 0xFF111111.toInt()
            val red = 0xFFD71920.toInt()
            val blue = 0xFF1769FF.toInt()
            val yellow = 0xFFE6D300.toInt()
            fun fill(color: Int) { paint.color = color; canvas.drawRect(flagRect, paint) }
            fun triangle(color: Int, points: List<Pair<Float, Float>>) {
                paint.color = color
                val path = android.graphics.Path().apply {
                    moveTo(mastX + flagWidth * points[0].first, y + flagHeight * points[0].second)
                    points.drop(1).forEach { lineTo(mastX + flagWidth * it.first, y + flagHeight * it.second) }
                    close()
                }
                canvas.drawPath(path, paint)
            }
            fun pennant(colors: List<Int>) {
                val path = android.graphics.Path().apply {
                    moveTo(mastX, y)
                    lineTo(mastX + flagWidth, y + flagHeight * 0.5f)
                    lineTo(mastX, y + flagHeight)
                    close()
                }
                val save = canvas.save()
                canvas.clipPath(path)
                colors.forEachIndexed { band, color ->
                    paint.color = color
                    val left = mastX + flagWidth * band / colors.size
                    val right = mastX + flagWidth * (band + 1) / colors.size
                    canvas.drawRect(left, y, right, y + flagHeight, paint)
                }
                canvas.restoreToCount(save)
                paint.color = 0xff333333.toInt()
                paint.style = Paint.Style.STROKE
                paint.strokeWidth = (flagWidth * 0.018f).coerceAtLeast(1f)
                canvas.drawPath(path, paint)
                paint.style = Paint.Style.FILL
            }
            when (state.style) {
                "internationalFlag" -> drawInternationalArtwork(canvas, state, flagRect)
                "blueSquare" -> {
                    fill(state.color)
                    paint.color = white
                    canvas.drawRect(mastX + flagWidth * 0.34f, y + flagHeight * 0.30f, mastX + flagWidth * 0.66f, y + flagHeight * 0.70f, paint)
                }
                "circle" -> {
                    fill(state.color); paint.color = black
                    canvas.drawCircle(flagRect.centerX(), flagRect.centerY(), flagHeight * 0.24f, paint)
                }
                "diagonal" -> { fill(state.color); triangle(state.secondaryColor, listOf(0f to 0f, 1f to 0f, 0f to 1f)) }
                "checker" -> {
                    fill(state.color); paint.color = state.secondaryColor
                    canvas.drawRect(mastX + flagWidth * 0.5f, y, mastX + flagWidth, y + flagHeight * 0.5f, paint)
                    canvas.drawRect(mastX, y + flagHeight * 0.5f, mastX + flagWidth * 0.5f, y + flagHeight, paint)
                }
                "apFlag" -> pennant(listOf(red, white, red, white, red))
                "hFlag" -> {
                    fill(white); paint.color = red
                    canvas.drawRect(mastX + flagWidth * 0.5f, y, mastX + flagWidth, y + flagHeight, paint)
                }
                "lFlag" -> {
                    fill(yellow); paint.color = black
                    canvas.drawRect(mastX + flagWidth * 0.5f, y, mastX + flagWidth, y + flagHeight * 0.5f, paint)
                    canvas.drawRect(mastX, y + flagHeight * 0.5f, mastX + flagWidth * 0.5f, y + flagHeight, paint)
                }
                "zFlag" -> {
                    fill(black)
                    triangle(yellow, listOf(0f to 0f, 1f to 0f, 0.5f to 0.5f))
                    triangle(blue, listOf(1f to 0f, 1f to 1f, 0.5f to 0.5f))
                    triangle(red, listOf(1f to 1f, 0f to 1f, 0.5f to 0.5f))
                }
                "firstSub" -> pennant(listOf(blue, yellow, blue))
                "xFlag" -> {
                    fill(white); paint.color = blue
                    paint.strokeWidth = flagHeight * 0.18f
                    canvas.drawLine(mastX, y, mastX + flagWidth, y + flagHeight, paint)
                    canvas.drawLine(mastX + flagWidth, y, mastX, y + flagHeight, paint)
                }
                "classLogo" -> {
                    fill(white)
                    paint.color = black
                    paint.typeface = android.graphics.Typeface.create("sans-serif-black", android.graphics.Typeface.BOLD_ITALIC)
                    paint.textAlign = Paint.Align.CENTER
                    val mark = state.id.removePrefix("class-")
                    paint.textSize = (flagHeight * 0.52f).coerceAtMost(flagWidth * (1.35f / mark.length.coerceAtLeast(2)))
                    canvas.drawText(mark, flagRect.centerX(), flagRect.centerY() - (paint.ascent() + paint.descent()) / 2f, paint)
                    paint.textAlign = Paint.Align.LEFT
                }
                else -> fill(state.color)
            }
        }
    }
}
