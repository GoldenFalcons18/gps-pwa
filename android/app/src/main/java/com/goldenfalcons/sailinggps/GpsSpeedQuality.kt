package com.goldenfalcons.sailinggps

/**
 * Rejects speed estimates when location uncertainty could make stationary GPS jitter look like motion.
 * Android reports speed accuracy as a 68% confidence radius on API 26+.
 */
object GpsSpeedQuality {
    fun acceptedSpeedMps(speedMps: Double?, horizontalAccuracyM: Double?, speedAccuracyMps: Double?): Double? {
        val speed = speedMps?.takeIf { it.isFinite() && it >= 0.0 } ?: return null
        val horizontal = horizontalAccuracyM?.takeIf { it.isFinite() && it >= 0.0 } ?: return null
        if (horizontal > 15.0) return null
        if (speedAccuracyMps != null) {
            if (!speedAccuracyMps.isFinite() || speedAccuracyMps < 0.0 || speedAccuracyMps > 1.0) return null
        } else if (horizontal > 5.0) {
            return null
        }
        return speed
    }
}
