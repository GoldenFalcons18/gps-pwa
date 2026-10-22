package com.goldenfalcons.sailinggps

import kotlin.math.*

data class StartLineCoordinate(val latitude: Double, val longitude: Double) {
    val isValid: Boolean get() = latitude.isFinite() && longitude.isFinite() && latitude in -90.0..90.0 && longitude in -180.0..180.0
}

object StartLineMath {
    private const val EARTH_RADIUS_METERS = 6_371_008.8

    fun distanceMeters(boat: StartLineCoordinate, outerMark: StartLineCoordinate?, signalBoat: StartLineCoordinate?): Double? {
        if (!boat.isValid || outerMark?.isValid != true || signalBoat?.isValid != true) return null
        val originLatitude = Math.toRadians(boat.latitude)
        val cosine = cos(originLatitude)
        fun project(point: StartLineCoordinate): Pair<Double, Double> {
            val longitudeDelta = Math.toRadians(point.longitude - boat.longitude)
            val latitudeDelta = Math.toRadians(point.latitude - boat.latitude)
            return EARTH_RADIUS_METERS * longitudeDelta * cosine to EARTH_RADIUS_METERS * latitudeDelta
        }
        val a = project(outerMark)
        val b = project(signalBoat)
        val dx = b.first - a.first
        val dy = b.second - a.second
        val lengthSquared = dx * dx + dy * dy
        if (lengthSquared <= 0.0) return hypot(a.first, a.second)
        val fraction = (-(a.first * dx + a.second * dy) / lengthSquared).coerceIn(0.0, 1.0)
        return hypot(a.first + fraction * dx, a.second + fraction * dy)
    }

    fun countdown(seconds: Double): String {
        val value = ceil(seconds.coerceAtLeast(0.0)).toInt()
        return "%02d:%02d".format(value / 60, value % 60)
    }
}
