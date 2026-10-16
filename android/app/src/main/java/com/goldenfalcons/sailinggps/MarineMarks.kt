package com.goldenfalcons.sailinggps

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path

/** App-owned vector marks; independent of emoji font availability. */
object MarineMarks {
    val names = listOf("灯台", "港", "網", "危険", "ブイ", "岩礁", "錨")
    fun draw(canvas: Canvas, mark: String, centerX: Float, centerY: Float, size: Float, color: Int): Boolean {
        if (mark !in names) return false
        canvas.save(); canvas.translate(centerX - size / 2, centerY - size / 2); canvas.scale(size / 32, size / 32)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color; style = Paint.Style.STROKE; strokeWidth = 2.2f; strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND }
        fun line(x: Float, y: Float, a: Float, b: Float) { canvas.drawLine(x, y, a, b, paint) }
        fun polygon(points: List<Pair<Float, Float>>, filled: Boolean = false) {
            val path = Path(); path.moveTo(points[0].first, points[0].second)
            points.drop(1).forEach { path.lineTo(it.first, it.second) }; path.close()
            paint.style = if (filled) Paint.Style.FILL else Paint.Style.STROKE; canvas.drawPath(path, paint); paint.style = Paint.Style.STROKE
        }
        when (mark) {
            "灯台" -> {
                polygon(listOf(9f to 29f, 12f to 12f, 20f to 12f, 23f to 29f))
                polygon(listOf(11f to 7f, 21f to 7f, 21f to 13f, 11f to 13f), true)
                polygon(listOf(9f to 7f, 16f to 2f, 23f to 7f), true)
                line(4f,29f,28f,29f); line(11f,19f,21f,19f)
                line(2f,6f,7f,9f); line(2f,13f,7f,10f); line(25f,9f,30f,6f); line(25f,10f,30f,13f)
            }
            "網" -> {
                canvas.drawRect(3f,3f,29f,29f,paint)
                for (v in 4..28 step 6) { val n = v.toFloat(); line(3f,n,n,3f); line(n,29f,29f,n); line(3f,32-n,n,29f); line(n,3f,29f,32-n) }
            }
            "危険" -> {
                polygon(listOf(16f to 2f, 30f to 29f, 2f to 29f)); line(16f,11f,16f,20f)
                paint.style = Paint.Style.FILL; canvas.drawCircle(16f,25f,1.5f,paint)
            }
            "ブイ" -> {
                line(16f,3f,16f,24f); line(8f,24f,24f,24f); line(8f,24f,12f,18f); line(12f,18f,20f,18f); line(20f,18f,24f,24f)
                canvas.drawCircle(16f,9f,4f,paint); line(2f,28f,8f,30f); line(8f,30f,16f,27f); line(16f,27f,24f,30f); line(24f,30f,30f,28f)
            }
            "岩礁" -> polygon(listOf(2f to 28f, 10f to 10f, 17f to 21f, 23f to 15f, 30f to 28f))
            "港" -> {
                line(3f,3f,3f,28f);line(3f,28f,10f,28f);line(29f,3f,29f,28f);line(29f,28f,22f,28f)
                canvas.drawRect(12f,10f,20f,17f,paint)
                polygon(listOf(8f to 17f,24f to 17f,20f to 23f,12f to 23f))
                line(16f,5f,16f,10f)
            }
            "錨" -> {
                canvas.drawCircle(16f,6f,4f,paint); line(16f,10f,16f,28f); line(8f,13f,24f,13f)
                val path = Path(); path.moveTo(4f,19f); path.cubicTo(5f,33f,27f,33f,28f,19f); canvas.drawPath(path,paint)
                line(4f,19f,3f,24f); line(4f,19f,9f,20f); line(28f,19f,29f,24f); line(28f,19f,23f,20f)
            }
        }
        canvas.restore(); return true
    }
}
