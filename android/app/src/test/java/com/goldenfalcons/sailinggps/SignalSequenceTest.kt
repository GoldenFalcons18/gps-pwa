package com.goldenfalcons.sailinggps

import org.junit.Assert.assertEquals
import org.junit.Test

class SignalSequenceTest {
    @Test
    fun nextEventAdvancesOnExactSignalBoundary() {
        assertEquals(0, SignalTiming.nextEventIndex(301.0, listOf(300, 240, 60, 0)))
        assertEquals(1, SignalTiming.nextEventIndex(300.0, listOf(300, 240, 60, 0)))
        assertEquals(1, SignalTiming.nextEventIndex(241.0, listOf(300, 240, 60, 0)))
        assertEquals(2, SignalTiming.nextEventIndex(240.0, listOf(300, 240, 60, 0)))
        assertEquals(3, SignalTiming.nextEventIndex(60.0, listOf(300, 240, 60, 0)))
        assertEquals(3, SignalTiming.nextEventIndex(0.0, listOf(300, 240, 60, 0)))
    }

    @Test
    fun selectedDurationScalesEventBoundaries() {
        assertEquals(0, SignalTiming.nextEventIndex(61.0, listOf(60, 48, 12, 0)))
        assertEquals(1, SignalTiming.nextEventIndex(60.0, listOf(60, 48, 12, 0)))
        assertEquals(2, SignalTiming.nextEventIndex(48.0, listOf(60, 48, 12, 0)))
        assertEquals(3, SignalTiming.nextEventIndex(12.0, listOf(60, 48, 12, 0)))
    }
}
