package com.goldenfalcons.sailinggps

import kotlin.math.*

object NavigationUtils {
    const val MPS_TO_KT = 1.9438444924406
    const val M_TO_NM = 1.0 / 1852.0
    private const val EARTH_RADIUS_M = 6371000.0

    fun normalize360(deg: Double): Double {
        val r = deg % 360.0
        return if (r < 0) r + 360.0 else r
    }

    fun normalize180(deg: Double): Double {
        var r = normalize360(deg)
        if (r > 180.0) r -= 360.0
        return r
    }

    fun distanceMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val p1 = Math.toRadians(lat1)
        val p2 = Math.toRadians(lat2)
        val a = sin(dLat / 2).pow(2) + cos(p1) * cos(p2) * sin(dLon / 2).pow(2)
        return 2 * EARTH_RADIUS_M * atan2(sqrt(a), sqrt(1 - a))
    }

    fun bearingDegrees(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val p1 = Math.toRadians(lat1)
        val p2 = Math.toRadians(lat2)
        val dl = Math.toRadians(lon2 - lon1)
        val y = sin(dl) * cos(p2)
        val x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        return normalize360(Math.toDegrees(atan2(y, x)))
    }

    /** Straight-line distance at current SOG; hide unreliable estimates below ~0.5 kt. */
    fun ete(distanceMeters: Double?, speedMps: Double?): String {
        val distance = distanceMeters ?: return "--:--:--"
        if (!distance.isFinite() || distance < 0) return "--:--:--"
        if (distance == 0.0) return "00:00:00"
        val speed = speedMps ?: return "--:--:--"
        if (!speed.isFinite() || speed < 0.25) return "--:--:--"
        val seconds = ceil(distance / speed)
        if (!seconds.isFinite() || seconds > Int.MAX_VALUE) return "--:--:--"
        val total = seconds.toLong()
        return "%02d:%02d:%02d".format(java.util.Locale.ROOT, total / 3600, total / 60 % 60, total % 60)
    }

    fun relativeClock(relativeDeg: Double): String {
        val idx = floor((relativeDeg + 15.0) / 30.0).toInt()
        val n = ((idx % 12) + 12) % 12
        return "${if (n == 0) 12 else n}時方向"
    }

    fun relativeText(relativeDeg: Double): String {
        val value = abs(relativeDeg)
        return when {
            value < 0.5 -> "前方 0°"
            relativeDeg > 0 -> "右 ${value.roundToInt()}°"
            else -> "左 ${value.roundToInt()}°"
        }
    }

    fun dmToDecimal(degrees: Int, minutes: Double, direction: String, isLat: Boolean): Double? {
        val max = if (isLat) 90 else 180
        if (degrees !in 0..max || minutes < 0.0 || minutes >= 60.0) return null
        if (degrees == max && minutes != 0.0) return null
        var value = degrees + minutes / 60.0
        if (direction == "S" || direction == "W") value = -value
        return value
    }

    fun formatDm(value: Double, isLat: Boolean): String {
        val absValue = abs(value)
        var degrees = floor(absValue).toInt()
        var minutes = (absValue - degrees) * 60.0
        if (minutes >= 59.99995) {
            degrees += 1
            minutes = 0.0
        }
        val dir = if (isLat) {
            if (value >= 0) "N" else "S"
        } else {
            if (value >= 0) "E" else "W"
        }
        return "%d°%.4f′%s".format(degrees, minutes, dir)
    }
}
