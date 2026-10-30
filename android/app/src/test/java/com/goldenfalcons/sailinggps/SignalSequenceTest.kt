package com.goldenfalcons.sailinggps

import org.junit.Assert.assertEquals
import org.junit.Test

class SignalSequenceTest {
    @Test
    fun videoAAndVideoBMatchTheReferenceSignalTimes() {
        val videoA = SignalSequence.events(20, 1)
        assertEquals(listOf(0, 300, 360, 540, 600, 1200), videoA.map { it.secondsAfterStart })
        assertEquals(listOf("橙", "緑", "青", "青", "緑", "橙"), videoA.map { it.flag })
        assertEquals(listOf(true, true, true, false, false, false), videoA.map { it.raised })
        assertEquals(listOf(listOf(0), listOf(0), listOf(0), listOf(1), listOf(0), emptyList()),
            videoA.map { it.hornPulses })

        val videoB = SignalSequence.events(13, 2)
        assertEquals(listOf(0, 240, 300, 480, 540, 780), videoB.map { it.secondsAfterStart })
        assertEquals(listOf(true, true, true, false, false, false), videoB.map { it.raised })
        assertEquals(listOf(listOf(0), listOf(0), listOf(0), listOf(1), listOf(0), emptyList()),
            videoB.map { it.hornPulses })
        assertEquals(listOf("級", "斜め"), videoB[1].flagMarks.map { it.id })
        assertEquals(listOf("級", "斜め"), videoB[4].flagMarks.map { it.id })
        assertEquals(setOf("橙", "級", "斜め", "赤白チェック"),
            SignalSequence.flagsAtEvents(videoB, 300.0).filter { it.raised }.map { it.id }.toSet())
        assertEquals(4, SignalSequence.initialEventIndex(1))
        assertEquals(4, SignalSequence.initialEventIndex(2))
    }

    @Test
    fun signalSequenceAlignsZeroToRealClockMinuteAfterMinimumLead() {
        assertEquals(60_000L, SignalTiming.scheduledStartAt(10_000L, 15))
        assertEquals(60_000L, SignalTiming.scheduledStartAt(10_000L, 0))
        assertEquals(60_000L, SignalTiming.scheduledStartAt(60_000L, 0))
        assertEquals(120_000L, SignalTiming.scheduledStartAt(50_000L, 15))
    }
    @Test
    fun countdownUsesCeilingSoItMatchesClockSeconds() {
        assertEquals(51, SignalTiming.countdownSeconds(50.1))
        assertEquals(51, SignalTiming.countdownSeconds(51.0))
        assertEquals(0, SignalTiming.countdownSeconds(0.0))
    }

    @Test
    fun standardStartUsesRaceSignalTimesAndOrangeShortHorn() {
        assertEquals(listOf(0, 300, 360, 540, 600, 840), SignalSequence.events(14, 0).map { it.secondsAfterStart })
        assertEquals(listOf(true, true, true, false, false, false), SignalSequence.events(20, 0).map { it.raised })
        assertEquals(listOf(listOf(0), listOf(0), listOf(0), listOf(1), listOf(0), emptyList()),
            SignalSequence.events(20, 0).map { it.hornPulses })
    }

    @Test
    fun standardTimelineAndRecallRestartUseExpectedOffsets() {
        assertEquals(listOf(0, 300, 360, 540, 600, 840), SignalSequence.profiles[0].events.map { it.secondsAfterStart })
        assertEquals("I", SignalSequence.events(14, 0, "I")[2].flag)
        assertEquals(0xFFF5D328.toInt(), SignalSequence.events(14, 0, "I")[2].color)
        assertEquals(listOf(0, 60, 240, 300, 540), SignalSequence.restartEvents().map { it.secondsAfterStart })
        assertEquals(listOf(listOf(0), listOf(0), listOf(1), listOf(0), emptyList()), SignalSequence.restartEvents().map { it.hornPulses })
        assertEquals(listOf(0), SignalSequence.individualRecallRaise.hornPulses)
        assertEquals(listOf(0, 0), SignalSequence.generalRecallRaise.hornPulses)
        assertEquals(listOf(0), SignalSequence.generalRecallLower.hornPulses)
        assertEquals(listOf(0, 0), SignalSequence.postponementRaise.hornPulses)
        assertEquals(listOf(0), SignalSequence.postponementLower.hornPulses)
        assertEquals(listOf(0, 0, 0), SignalSequence.abandonRaise.hornPulses)
        assertEquals(listOf(0), SignalSequence.abandonLower.hornPulses)
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
        assertEquals(listOf(0, 150, 180, 270, 300, 600), SignalSequence.events(10, 1).map { it.secondsAfterStart })
    }

    @Test
    fun mastShowsCurrentRaisedFlags() {
        assertEquals(listOf("橙"), SignalSequence.flagsAt(0.0, 20, 0).filter { it.raised }.map { it.id })
        assertEquals(listOf("橙", "級", "P"), SignalSequence.flagsAt(360.0, 14, 0).filter { it.raised }.map { it.id })
        assertEquals(listOf("橙"), SignalSequence.flagsAt(600.0, 14, 0).filter { it.raised }.map { it.id })
        assertEquals(emptyList<String>(), SignalSequence.flagsAt(1200.0, 14, 0).filter { it.raised }.map { it.id })
    }

    @Test
    fun restartWarningFollowsFlagLoweringByExactlyOneMinute() {
        assertEquals(185_000L, SignalTiming.restartWarningAt(125_000L))
    }

}
