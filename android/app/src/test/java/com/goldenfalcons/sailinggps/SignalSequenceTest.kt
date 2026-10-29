package com.goldenfalcons.sailinggps

import org.junit.Assert.assertEquals
import org.junit.Test

class SignalSequenceTest {
    @Test
    fun nextEventAdvancesOnExactSignalBoundary() {
        assertEquals(0, SignalSequence.nextIndex(301.0, 5, 0))
        assertEquals(1, SignalSequence.nextIndex(300.0, 5, 0))
        assertEquals(1, SignalSequence.nextIndex(241.0, 5, 0))
        assertEquals(2, SignalSequence.nextIndex(240.0, 5, 0))
        assertEquals(3, SignalSequence.nextIndex(60.0, 5, 0))
        assertEquals(3, SignalSequence.nextIndex(0.0, 5, 0))
    }

    @Test
    fun selectedDurationScalesEventBoundaries() {
        assertEquals(0, SignalSequence.nextIndex(61.0, 1, 0))
        assertEquals(1, SignalSequence.nextIndex(60.0, 1, 0))
        assertEquals(2, SignalSequence.nextIndex(48.0, 1, 0))
        assertEquals(3, SignalSequence.nextIndex(12.0, 1, 0))
    }
}
