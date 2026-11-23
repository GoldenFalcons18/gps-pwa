package com.goldenfalcons.sailinggps

import kotlin.math.roundToInt

enum class SailingSpeedBand { BELOW_TARGET, APPROXIMATELY_TARGET, ABOVE_TARGET, UNAVAILABLE }

object SailingSpeedIndicator {
    fun resolve(current: Double?, target: Double, enabled: Boolean): SailingSpeedBand {
        if (!enabled) return SailingSpeedBand.ABOVE_TARGET
        if (current == null || !current.isFinite() || current < 0.0 || !target.isFinite() || target < 0.0)
            return SailingSpeedBand.UNAVAILABLE
        val shownCurrent = (current * 10.0).roundToInt()
        val shownTarget = (target * 10.0).roundToInt()
        if (shownCurrent == shownTarget) return SailingSpeedBand.APPROXIMATELY_TARGET
        return if (shownCurrent < shownTarget) SailingSpeedBand.BELOW_TARGET else SailingSpeedBand.ABOVE_TARGET
    }
}
