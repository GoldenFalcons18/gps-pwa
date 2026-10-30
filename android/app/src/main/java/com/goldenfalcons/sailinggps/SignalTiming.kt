package com.goldenfalcons.sailinggps

/** Pure elapsed-time boundary math shared by signal presentation and tests. */
object SignalTiming {
    fun scheduledStartAt(nowMillis: Long, minimumDelaySeconds: Int): Long =
        nowMillis + minimumDelaySeconds.coerceAtLeast(0) * 1000L

    fun activeEventIndex(elapsedSeconds: Double, eventOffsets: List<Int>): Int {
        if (eventOffsets.isEmpty() || !elapsedSeconds.isFinite()) return -1
        return eventOffsets.indexOfLast { elapsedSeconds >= it }
    }

    fun eventIndicesCrossed(previousElapsed: Double, elapsed: Double, eventOffsets: List<Int>): List<Int> {
        if (eventOffsets.isEmpty() || !previousElapsed.isFinite() || !elapsed.isFinite() || elapsed < previousElapsed) return emptyList()
        val from = activeEventIndex(previousElapsed, eventOffsets)
        val to = activeEventIndex(elapsed, eventOffsets)
        return if (to <= from) emptyList() else ((from + 1)..to).toList()
    }
}
