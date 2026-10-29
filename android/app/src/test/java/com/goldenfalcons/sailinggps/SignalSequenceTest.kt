package com.goldenfalcons.sailinggps

import org.junit.Assert.assertEquals
import org.junit.Test

class SignalSequenceTest {
    @Test
    fun videoProfileUsesElapsedSignalTimesInOrder() {
        assertEquals(listOf(0, 300, 360, 540, 600, 1200), SignalSequence.events(20, 0).map { it.secondsAfterStart })
        assertEquals(listOf(true, true, true, false, false, false), SignalSequence.events(20, 0).map { it.raised })
        assertEquals(listOf(listOf(0), listOf(0), listOf(0), listOf(1), listOf(0), emptyList()),
            SignalSequence.events(20, 0).map { it.hornPulses })
    }

    @Test
    fun activeRowAdvancesAtElapsedEventBoundary() {
        val offsets = listOf(0, 300, 360, 540, 600, 1200)
        assertEquals(-1, SignalTiming.activeEventIndex(-0.1, offsets))
        assertEquals(0, SignalTiming.activeEventIndex(0.0, offsets))
        assertEquals(0, SignalTiming.activeEventIndex(299.999, offsets))
        assertEquals(1, SignalTiming.activeEventIndex(300.0, offsets))
        assertEquals(2, SignalTiming.activeEventIndex(360.0, offsets))
        assertEquals(3, SignalTiming.activeEventIndex(540.0, offsets))
        assertEquals(4, SignalTiming.activeEventIndex(600.0, offsets))
        assertEquals(5, SignalTiming.activeEventIndex(1200.0, offsets))
    }

    @Test
    fun crossedEventsAreReportedOnceAndInOrder() {
        val offsets = listOf(0, 300, 360, 540, 600, 1200)
        assertEquals(listOf(0), SignalTiming.eventIndicesCrossed(-1.0, 0.0, offsets))
        assertEquals(listOf(1, 2), SignalTiming.eventIndicesCrossed(299.0, 361.0, offsets))
        assertEquals(emptyList<Int>(), SignalTiming.eventIndicesCrossed(361.0, 359.0, offsets))
    }

    @Test
    fun sequenceScalingPreservesElapsedOrder() {
        assertEquals(listOf(0, 150, 180, 270, 300, 600), SignalSequence.events(10, 0).map { it.secondsAfterStart })
    }

    @Test
    fun mastShowsCurrentRaisedFlags() {
        assertEquals(listOf("橙"), SignalSequence.flagsAt(0.0, 20, 0).filter { it.raised }.map { it.id })
        assertEquals(listOf("橙", "緑", "青"), SignalSequence.flagsAt(360.0, 20, 0).filter { it.raised }.map { it.id })
        assertEquals(listOf("橙"), SignalSequence.flagsAt(600.0, 20, 0).filter { it.raised }.map { it.id })
        assertEquals(emptyList<String>(), SignalSequence.flagsAt(1200.0, 20, 0).filter { it.raised }.map { it.id })
    }
}
