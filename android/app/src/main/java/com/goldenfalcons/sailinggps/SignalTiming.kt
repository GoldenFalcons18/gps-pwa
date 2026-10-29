package com.goldenfalcons.sailinggps

/** Pure timing math shared by signal presentation and unit tests. */
object SignalTiming {
    fun nextEventIndex(secondsUntilStart: Double, eventOffsets: List<Int>): Int {
        if (eventOffsets.isEmpty()) return -1
        val next = eventOffsets.indexOfFirst { secondsUntilStart > it }
        return if (next < 0) eventOffsets.lastIndex else next
    }
}
