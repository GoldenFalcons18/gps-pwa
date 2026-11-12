package com.goldenfalcons.sailinggps

/** Pure elapsed-time boundary math shared by signal presentation and tests. */
object SignalTiming {
    fun scheduledStartAt(nowMillis: Long, minimumDelaySeconds: Int): Long {
        val earliest = nowMillis + minimumDelaySeconds.coerceAtLeast(0) * 1000L
        val minute = 60_000L
        val remainder = Math.floorMod(earliest, minute)
        return if (remainder == 0L) earliest else earliest + minute - remainder
    }

    fun startAfterOrangeRaise(nowMillis: Long, orangeRaisedAtMillis: Long, intervalMinutes: Int, minimumLeadSeconds: Int): Long {
        // A manual orange raise is the timing anchor. The first class signal
        // must not occur before its configured interval; then start on the
        // next real-clock :00 boundary, keeping the event sequence on whole
        // minutes. Do not add the generic minimum lead a second time.
        val earliestByOrange = orangeRaisedAtMillis + intervalMinutes.coerceAtLeast(0) * 60_000L
        return scheduledStartAt(maxOf(nowMillis, earliestByOrange), 0)
    }

    fun restartWarningAt(loweredAtMs: Long): Long = loweredAtMs + 60_000L

    fun postponementRestartWarningAt(loweredAtMs: Long, orangeRaisedAtMs: Long?, orangeDisplayedMinutes: Int, orangeEnabled: Boolean): Long {
        if (!orangeEnabled) return restartWarningAt(loweredAtMs)
        val orangeDeadline = (orangeRaisedAtMs ?: loweredAtMs) + orangeDisplayedMinutes.coerceAtLeast(0) * 60_000L
        return maxOf(restartWarningAt(loweredAtMs), orangeDeadline)
    }

    /** Keep AP raised until exactly one minute before the next warning. */
    fun postponementApLowerAt(loweredAtMs: Long, orangeRaisedAtMs: Long?, orangeDisplayedMinutes: Int, orangeEnabled: Boolean): Long =
        postponementRestartWarningAt(loweredAtMs, orangeRaisedAtMs, orangeDisplayedMinutes, orangeEnabled) - 60_000L

    /** Delay the next refresh until the next whole corrected-clock second. */
    fun millisUntilNextSecond(nowMillis: Long): Long = 1000L - Math.floorMod(nowMillis, 1000L)

    fun countdownSeconds(remainingSeconds: Double): Int = kotlin.math.ceil(remainingSeconds).toInt().coerceAtLeast(0)

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

