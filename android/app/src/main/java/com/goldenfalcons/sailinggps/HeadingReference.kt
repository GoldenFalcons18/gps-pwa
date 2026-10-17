package com.goldenfalcons.sailinggps

/** One reference for map, target arrow and numeric heading. GPS COG is true-north based. */
object HeadingReference {
    data class Reading(val heading: Double, val trueHeading: Double?, val magnetic: Boolean)
    fun resolve(preferGps: Boolean, magnetic: Double?, declination: Double?, course: Double?, speed: Double?): Reading? {
        val mag = magnetic?.takeIf { it.isFinite() && it >= 0 }
        val gps = course?.takeIf { it.isFinite() && it >= 0 && speed != null && speed.isFinite() && speed >= 0.25 }
        if (preferGps && gps != null) return Reading(NavigationUtils.normalize360(gps), NavigationUtils.normalize360(gps), false)
        if (mag != null) return Reading(NavigationUtils.normalize360(mag), declination?.takeIf { it.isFinite() }?.let { NavigationUtils.normalize360(mag + it) }, true)
        return gps?.let { Reading(NavigationUtils.normalize360(it), NavigationUtils.normalize360(it), false) }
    }
    fun relative(target: Double, heading: Double) = NavigationUtils.normalize180(target - heading)
}
