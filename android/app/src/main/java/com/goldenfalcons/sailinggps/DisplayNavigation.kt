package com.goldenfalcons.sailinggps

import kotlin.math.*

object DisplayNavigation {
    fun distance(meters: Double, metric: Boolean): String = if (!metric) "%.2f nm".format(meters / 1852.0)
        else if (meters < 1000) "%.0f m".format(meters) else "%.2f km".format(meters / 1000)

    fun destination(lat: Double, lon: Double, bearing: Double, meters: Double): Pair<Double, Double> {
        val a = Math.toRadians(lat); val b = Math.toRadians(lon)
        val h = Math.toRadians(bearing); val d = meters / 6371000.0
        val x = asin((sin(a)*cos(d)+cos(a)*sin(d)*cos(h)).coerceIn(-1.0,1.0))
        val y = b + atan2(sin(h)*sin(d)*cos(a), cos(d)-sin(a)*sin(x))
        return Math.toDegrees(x) to ((Math.toDegrees(y)+540)%360-180)
    }

    fun zoom(latitude: Double, pixelsPerCm: Double): Double =
        log2(156543.033928 * cos(Math.toRadians(latitude)).coerceAtLeast(0.000001) / (200.0 / pixelsPerCm))
}
