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
        rect(c,.5f-thickness/2,0f,thickness,1f,color); rect(c,0f,.5f-thickness/2,1f,thickness,color)
    }
    private fun pennant(c: Canvas, colors: List<Int>) {
        stripes(c,colors,true)
        // Pennants taper to the fly end.
        poly(c,white,.70f,0f,1f,.5f,.70f,1f)
    }
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val save=canvas.save()
        val flagW=width.toFloat(); val flagH=height.toFloat()
        canvas.clipRect(0f,0f,flagW,flagH)
        when(flagName.lowercase()) {
            "alpha" -> { rect(canvas,0f,0f,1f,1f,white); rect(canvas,0f,0f,.5f,1f,blue); poly(canvas,blue,.5f,0f,1f,.5f,.5f,1f); poly(canvas,white,.84f,0f,1f,.5f,.84f,1f) }
            "bravo" -> rect(canvas,0f,0f,1f,1f,red)
            "charlie" -> stripes(canvas,listOf(blue,white,red,white,blue),false)
            "delta" -> stripes(canvas,listOf(yellow,blue,yellow),false)
            "echo" -> stripes(canvas,listOf(blue,red),false)
            "foxtrot" -> { rect(canvas,0f,0f,1f,1f,white); poly(canvas,red,.5f,.12f,.88f,.5f,.5f,.88f,.12f,.5f) }
            "golf" -> stripes(canvas,listOf(yellow,blue,yellow,blue,yellow),true)
            "hotel" -> stripes(canvas,listOf(white,red),true)
            "india" -> { rect(canvas,0f,0f,1f,1f,yellow); p.color=black; canvas.drawCircle(width*.5f,height*.5f,minOf(width,height)*.25f,p) }
            "juliett" -> stripes(canvas,listOf(blue,white,blue),false)
            "kilo" -> stripes(canvas,listOf(yellow,blue),true)
            "lima" -> { rect(canvas,0f,0f,.5f,.5f,yellow);rect(canvas,.5f,0f,.5f,.5f,black);rect(canvas,0f,.5f,.5f,.5f,black);rect(canvas,.5f,.5f,.5f,.5f,yellow) }
            "mike" -> {rect(canvas,0f,0f,1f,1f,blue);cross(canvas,white,.18f)}
            "november" -> {rect(canvas,0f,0f,1f,1f,white);for(x in 0..3)for(y in 0..3)if((x+y)%2==0)rect(canvas,x/4f,y/4f,.25f,.25f,blue)}
            "oscar" -> {rect(canvas,0f,0f,1f,1f,yellow);poly(canvas,red,0f,1f,1f,0f,1f,1f)}
            "papa" -> {rect(canvas,0f,0f,1f,1f,blue);rect(canvas,.34f,.3f,.32f,.4f,white)}
            "quebec" -> rect(canvas,0f,0f,1f,1f,yellow)
            "romeo" -> stripes(canvas,listOf(red,yellow,red),false)
            "sierra" -> {rect(canvas,0f,0f,1f,1f,blue);rect(canvas,.28f,.22f,.44f,.56f,white)}
            "tango" -> stripes(canvas,listOf(red,white,blue),true)
            "uniform" -> {rect(canvas,0f,0f,1f,1f,white);rect(canvas,0f,0f,.5f,.5f,red);rect(canvas,.5f,.5f,.5f,.5f,red)}
            "victor" -> {rect(canvas,0f,0f,1f,1f,white);cross(canvas,red,.24f)}
            "whiskey" -> {rect(canvas,0f,0f,1f,1f,blue);rect(canvas,.18f,.12f,.64f,.76f,white);rect(canvas,.34f,.3f,.32f,.4f,red)}
            "x-ray" -> {rect(canvas,0f,0f,1f,1f,white);cross(canvas,blue,.18f)}
            "yankee" -> stripes(canvas,listOf(red,yellow,red,yellow,red,yellow),true)
            "zulu" -> {rect(canvas,0f,0f,.5f,.5f,black);rect(canvas,.5f,0f,.5f,.5f,yellow);rect(canvas,0f,.5f,.5f,.5f,blue);rect(canvas,.5f,.5f,.5f,.5f,red)}
            "answering pennant" -> pennant(canvas,listOf(red,white,red,white,red))
            "first substitute" -> pennant(canvas,listOf(blue,yellow,blue))
            "second substitute" -> pennant(canvas,listOf(blue,white,blue))
            "third substitute" -> pennant(canvas,listOf(black,white,black))
            "fourth substitute" -> pennant(canvas,listOf(red,yellow,red))
            else -> {
                val n=Regex("\\d+").find(flagName)?.value?.toIntOrNull() ?: 0
                val palette=listOf(listOf(yellow,red,yellow),listOf(white,red),listOf(blue,white),listOf(red,white,blue),listOf(red,white),listOf(yellow,red),listOf(black,white),listOf(yellow,red),listOf(white,red),listOf(yellow,red))[n.coerceIn(0,9)]
                pennant(canvas,palette)
            }
        }
        p.color=0xff777777.toInt();p.style=Paint.Style.STROKE;p.strokeWidth=(width*.018f).coerceAtLeast(1f)
        canvas.drawRect(RectF(0f,0f,flagW,flagH),p)
        canvas.restoreToCount(save)
    }
}
