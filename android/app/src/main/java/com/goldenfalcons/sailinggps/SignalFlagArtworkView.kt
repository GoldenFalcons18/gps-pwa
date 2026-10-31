package com.goldenfalcons.sailinggps

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.view.View

/** Draws the actual International Code of Signals flag patterns in a compact gallery tile. */
class SignalFlagArtworkView(context: Context, var flagName: String) : View(context) {
    private val p = Paint(Paint.ANTI_ALIAS_FLAG)
    private val red = 0xffed1c24.toInt()
    private val blue = 0xff0827d8.toInt()
    private val yellow = 0xffffdf00.toInt()
    private val black = 0xff111111.toInt()
    private val white = 0xffffffff.toInt()
    private var signalMark: SignalFlagMark? = null

    fun show(mark: SignalFlagMark, raised: Boolean) {
        flagName = when {
            mark.id.startsWith("intl:") -> mark.id.removePrefix("intl:")
            mark.id == "AP" -> "Answering Pennant"
            mark.id == "第一代表" -> "First Substitute"
            mark.id == "Z" -> "Zulu"
            mark.id == "L" -> "Lima"
            else -> mark.id
        }
        signalMark = if (mark.style == "internationalFlag") null else mark
        invalidate()
    }

    private fun drawSignalMark(canvas: Canvas, mark: SignalFlagMark) {
        val base = mark.color
        when (mark.style) {
            "textFlag" -> {
                rect(canvas,0f,0f,1f,1f,base)
                p.color=if(android.graphics.Color.luminance(base)>0.45f) black else white
                p.style=Paint.Style.FILL; p.textAlign=Paint.Align.CENTER
                p.typeface=android.graphics.Typeface.create("sans-serif",android.graphics.Typeface.BOLD)
                val label=mark.id.removePrefix("text:").removePrefix("intl:")
                p.textSize=minOf(height*0.62f,width*1.45f/label.length.coerceAtLeast(1))
                canvas.drawText(label,width*0.5f,height*0.5f-(p.ascent()+p.descent())/2f,p)
                p.textAlign=Paint.Align.LEFT
            }
            "classLogo" -> {
                rect(canvas,0f,0f,1f,1f,white)
                p.color=black; p.style=Paint.Style.FILL; p.textAlign=Paint.Align.CENTER
                p.typeface=android.graphics.Typeface.create("sans-serif-black",android.graphics.Typeface.BOLD_ITALIC)
                val label=mark.id.removePrefix("class-").ifEmpty { "4" }
                p.textSize=minOf(height*0.62f,width*1.35f/label.length.coerceAtLeast(2))
                canvas.drawText(label,width*0.5f,height*0.5f-(p.ascent()+p.descent())/2f,p)
                p.textAlign=Paint.Align.LEFT
            }
            "blueSquare" -> { rect(canvas,0f,0f,1f,1f,base); rect(canvas,0.34f,0.3f,0.32f,0.4f,white) }
            "circle" -> { rect(canvas,0f,0f,1f,1f,base); p.color=black; canvas.drawCircle(width*0.5f,height*0.5f,minOf(width,height)*0.24f,p) }
            "diagonal" -> { rect(canvas,0f,0f,1f,1f,base); poly(canvas,mark.secondaryColor,0f,0f,1f,0f,0f,1f) }
            "checker" -> { rect(canvas,0f,0f,1f,1f,base); rect(canvas,0.5f,0f,0.5f,0.5f,mark.secondaryColor); rect(canvas,0f,0.5f,0.5f,0.5f,mark.secondaryColor) }
            "apFlag" -> { rect(canvas,0f,0f,1f,1f,base); rect(canvas,0.5f,0f,0.5f,1f,white) }
            "hFlag" -> { rect(canvas,0f,0f,1f,1f,white); rect(canvas,0.5f,0f,0.5f,1f,red) }
            "lFlag" -> { rect(canvas,0f,0f,0.5f,0.5f,yellow); rect(canvas,0.5f,0f,0.5f,0.5f,black); rect(canvas,0f,0.5f,0.5f,0.5f,black); rect(canvas,0.5f,0.5f,0.5f,0.5f,yellow) }
            "zFlag" -> { poly(canvas,black,0f,0f,1f,0f,0.5f,0.5f); poly(canvas,yellow,1f,0f,1f,1f,0.5f,0.5f); poly(canvas,red,1f,1f,0f,1f,0.5f,0.5f); poly(canvas,blue,0f,1f,0f,0f,0.5f,0.5f) }
            "firstSub" -> { rect(canvas,0f,0f,1f,1f,blue); poly(canvas,red,0f,0f,1f,1f,1f,0f) }
            "xFlag" -> { rect(canvas,0f,0f,1f,1f,white); diagonalCross(canvas,blue,0.22f) }
            else -> {
                rect(canvas,0f,0f,1f,1f,base)
                if(mark.whiteSquare) rect(canvas,0.34f,0.3f,0.32f,0.4f,white)
            }
        }
        p.color=0xff777777.toInt();p.style=Paint.Style.STROKE;p.strokeWidth=(width*0.018f).coerceAtLeast(1f)
        canvas.drawRect(RectF(0f,0f,width.toFloat(),height.toFloat()),p);p.style=Paint.Style.FILL
    }

    private fun rect(c: Canvas, x: Float, y: Float, w: Float, h: Float, color: Int) {
        p.color = color; p.style = Paint.Style.FILL
        c.drawRect(x * width, y * height, (x+w) * width, (y+h) * height, p)
    }
    private fun poly(c: Canvas, color: Int, vararg pts: Float) {
        p.color=color; p.style=Paint.Style.FILL
        val path=Path(); path.moveTo(pts[0]*width,pts[1]*height)
        var i=2; while(i<pts.size){path.lineTo(pts[i]*width,pts[i+1]*height);i+=2}
        path.close(); c.drawPath(path,p)
    }
    private fun stripes(c: Canvas, colors: List<Int>, vertical: Boolean) {
        colors.forEachIndexed { i,color ->
            val n=colors.size.toFloat()
            if(vertical) rect(c,i/n,0f,1f/n,1f,color) else rect(c,0f,i/n,1f,1f/n,color)
        }
    }
    private fun cross(c: Canvas, color: Int, thickness: Float) {
        rect(c,0.5f-thickness/2,0f,thickness,1f,color); rect(c,0f,0.5f-thickness/2,1f,thickness,color)
    }
    private fun diagonalCross(c: Canvas, color: Int, thickness: Float) {
        p.color=color; p.style=Paint.Style.STROKE; p.strokeWidth=minOf(width,height)*thickness
        c.drawLine(0f,0f,width.toFloat(),height.toFloat(),p)
        c.drawLine(width.toFloat(),0f,0f,height.toFloat(),p)
        p.style=Paint.Style.FILL
    }
    private fun diagonalStripes(c: Canvas, colors: List<Int>) {
        val save=c.save()
        c.rotate(-45f,width/2f,height/2f)
        val span=kotlin.math.hypot(width.toDouble(),height.toDouble()).toFloat()*1.6f
        val band=span/colors.size
        colors.forEachIndexed { i,color ->
            p.color=color; p.style=Paint.Style.FILL
            val left=width/2f-span/2f+i*band
            c.drawRect(left,height/2f-span/2f,left+band,height/2f+span/2f,p)
        }
        c.restoreToCount(save)
    }
    private fun pennant(c: Canvas, colors: List<Int>, vertical: Boolean = true, mark: String = "") {
        val clip=Path().apply { moveTo(0f,0f); lineTo(width.toFloat(),height*0.5f); lineTo(0f,height.toFloat()); close() }
        val save=c.save()
        c.clipPath(clip)
        stripes(c,colors,vertical)
        when(mark) {
            "redCircle" -> { p.color=red; c.drawCircle(width*0.43f,height*0.5f,minOf(width,height)*0.17f,p) }
            "whiteCircle" -> { p.color=white; c.drawCircle(width*0.43f,height*0.5f,minOf(width,height)*0.17f,p) }
            "whiteCross" -> cross(c,white,0.18f)
            "redCross" -> cross(c,red,0.18f)
            "yellowTriangle" -> poly(c,yellow,0.12f,0.20f,0.67f,0.50f,0.12f,0.80f)
            "whiteTriangle" -> poly(c,white,0.12f,0.20f,0.67f,0.50f,0.12f,0.80f)
            "blackBand" -> rect(c,0f,0.35f,0.70f,0.30f,black)
        }
        c.restoreToCount(save)
    }
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val save=canvas.save()
        val flagW=width.toFloat(); val flagH=height.toFloat()
        canvas.clipRect(0f,0f,flagW,flagH)
        signalMark?.let {
            drawSignalMark(canvas,it)
            canvas.restoreToCount(save)
            return
        }
        when(flagName.lowercase()) {
            "alpha" -> { rect(canvas,0f,0f,1f,1f,white); rect(canvas,0.5f,0f,0.5f,1f,blue); poly(canvas,white,0.72f,0.34f,1f,0.5f,0.72f,0.66f) }
            "bravo" -> { rect(canvas,0f,0f,1f,1f,red); poly(canvas,white,0.68f,0.34f,1f,0.5f,0.68f,0.66f) }
            "charlie" -> stripes(canvas,listOf(blue,white,red,white,blue),false)
            "delta" -> stripes(canvas,listOf(yellow,blue,yellow),false)
            "echo" -> stripes(canvas,listOf(blue,red),false)
            "foxtrot" -> { rect(canvas,0f,0f,1f,1f,white); poly(canvas,red,0.5f,0.12f,0.88f,0.5f,0.5f,0.88f,0.12f,0.5f) }
            "golf" -> stripes(canvas,listOf(yellow,blue,yellow,blue,yellow),true)
            "hotel" -> stripes(canvas,listOf(white,red),true)
            "india" -> { rect(canvas,0f,0f,1f,1f,yellow); p.color=black; canvas.drawCircle(width*0.5f,height*0.5f,minOf(width,height)*0.25f,p) }
            "juliett" -> stripes(canvas,listOf(blue,white,blue),false)
            "kilo" -> stripes(canvas,listOf(yellow,blue),true)
            "lima" -> { rect(canvas,0f,0f,0.5f,0.5f,yellow);rect(canvas,0.5f,0f,0.5f,0.5f,black);rect(canvas,0f,0.5f,0.5f,0.5f,black);rect(canvas,0.5f,0.5f,0.5f,0.5f,yellow) }
            "mike" -> {rect(canvas,0f,0f,1f,1f,blue);diagonalCross(canvas,white,0.22f)}
            "november" -> {rect(canvas,0f,0f,1f,1f,white);for(x in 0..3)for(y in 0..3)if((x+y)%2==0)rect(canvas,x/4f,y/4f,0.25f,0.25f,blue)}
            "oscar" -> {rect(canvas,0f,0f,1f,1f,yellow);poly(canvas,red,0f,1f,1f,0f,1f,1f)}
            "papa" -> {rect(canvas,0f,0f,1f,1f,blue);rect(canvas,0.34f,0.3f,0.32f,0.4f,white)}
            "quebec" -> rect(canvas,0f,0f,1f,1f,yellow)
            "romeo" -> {rect(canvas,0f,0f,1f,1f,red);cross(canvas,yellow,0.16f)}
            "sierra" -> {rect(canvas,0f,0f,1f,1f,white);rect(canvas,0.36f,0.34f,0.28f,0.32f,blue)}
            "tango" -> stripes(canvas,listOf(red,white,blue),true)
            "uniform" -> {rect(canvas,0f,0f,1f,1f,white);rect(canvas,0f,0f,0.5f,0.5f,red);rect(canvas,0.5f,0.5f,0.5f,0.5f,red)}
            "victor" -> {rect(canvas,0f,0f,1f,1f,white);diagonalCross(canvas,red,0.28f)}
            "whiskey" -> {rect(canvas,0f,0f,1f,1f,blue);rect(canvas,0.18f,0.12f,0.64f,0.76f,white);rect(canvas,0.34f,0.3f,0.32f,0.4f,red)}
            "x-ray" -> {rect(canvas,0f,0f,1f,1f,white);cross(canvas,blue,0.18f)}
            "yankee" -> diagonalStripes(canvas,listOf(red,yellow,red,yellow,red,yellow))
            "zulu" -> {poly(canvas,black,0f,0f,1f,0f,0.5f,0.5f);poly(canvas,yellow,1f,0f,1f,1f,0.5f,0.5f);poly(canvas,red,1f,1f,0f,1f,0.5f,0.5f);poly(canvas,blue,0f,1f,0f,0f,0.5f,0.5f)}
            "nato 0" -> {rect(canvas,0f,0f,1f,1f,white);cross(canvas,blue,0.10f);for(x in listOf(0.14f,0.86f))for(y in listOf(0.14f,0.86f)){p.color=blue;canvas.drawCircle(x*width,y*height,minOf(width,height)*0.045f,p)}}
            "nato 1" -> stripes(canvas,listOf(red,yellow),false)
            "nato 2" -> stripes(canvas,listOf(yellow,red),false)
            "nato 3" -> stripes(canvas,listOf(blue,red),false)
            "nato 4" -> {rect(canvas,0f,0f,1f,1f,red);diagonalCross(canvas,white,0.2f)}
            "nato 5" -> {rect(canvas,0f,0f,1f,1f,yellow);diagonalCross(canvas,blue,0.2f)}
            "nato 6" -> diagonalStripes(canvas,listOf(blue,white,blue,white,blue))
            "nato 7" -> stripes(canvas,listOf(red,white,red),true)
            "nato 8" -> {rect(canvas,0f,0f,1f,1f,yellow);rect(canvas,0.4f,0f,0.2f,1f,blue)}
            "nato 9" -> rect(canvas,0f,0f,1f,1f,blue)
            "answering pennant" -> pennant(canvas,listOf(red,white,red,white,red))
            "first substitute" -> pennant(canvas,listOf(blue),mark="yellowTriangle")
            "second substitute" -> pennant(canvas,listOf(blue),mark="whiteTriangle")
            "third substitute" -> pennant(canvas,listOf(white),mark="blackBand")
            "fourth substitute" -> pennant(canvas,listOf(red,yellow,red),vertical=false)
            else -> {
                val n=Regex("\\d+").find(flagName)?.value?.toIntOrNull() ?: 0
                when(n) {
                    0 -> pennant(canvas,listOf(yellow,red,yellow))
                    1 -> pennant(canvas,listOf(white),mark="redCircle")
                    2 -> pennant(canvas,listOf(blue),mark="whiteCircle")
                    3 -> pennant(canvas,listOf(red,white,blue),vertical=false)
                    4 -> pennant(canvas,listOf(red),mark="whiteCross")
                    5 -> pennant(canvas,listOf(yellow,blue),vertical=false)
                    6 -> pennant(canvas,listOf(black,white),vertical=false)
                    7 -> pennant(canvas,listOf(yellow,red),vertical=false)
                    8 -> pennant(canvas,listOf(white),mark="redCross")
                    else -> pennant(canvas,listOf(white,red,black,yellow))
                }
            }
        }
        p.color=0xff777777.toInt();p.style=Paint.Style.STROKE;p.strokeWidth=(width*0.018f).coerceAtLeast(1f)
        canvas.drawRect(RectF(0f,0f,flagW,flagH),p)
        canvas.restoreToCount(save)
    }
}
