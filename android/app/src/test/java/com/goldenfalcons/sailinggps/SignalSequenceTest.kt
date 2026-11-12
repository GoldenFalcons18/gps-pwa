package com.goldenfalcons.sailinggps

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SignalSequenceTest {
    @Test
    fun orangeFlagAlwaysUsesOrangePoleAndOtherFlagsUseDifferentPoles() {
        assertEquals(1, SignalMastLayout.poleIndex("橙", 0))
        assertEquals(1, SignalMastLayout.poleIndex("orange", 4))
        assertEquals(0, SignalMastLayout.poleIndex("X", 2))
        assertEquals(0, SignalMastLayout.poleIndex("第一代表", 3))
        assertEquals(0, SignalMastLayout.poleIndex("first-sub", 0))
        assertEquals(3, SignalMastLayout.poleIndex("class-420", 4))
        assertEquals(4, SignalMastLayout.poleIndex("P", 0))
        assertEquals(4, SignalMastLayout.poleIndex("AP", 3))
    }

    @Test
    fun orangeAnchorRequiresOrangeFlagToStillBeRaised() {
        val timeline = SignalSequence.events(20, 0)
        val orangeLower = timeline.first { it.flagMarks.any { mark -> mark.id == "橙" } && !it.raised }!!
        assertEquals(1_000L, SignalSequence.raisedFlagTimeMs(timeline, "橙", (orangeLower.secondsAfterStart - 1) * 1000L, 1_000L))
        assertEquals(null, SignalSequence.raisedFlagTimeMs(timeline, "橙", orangeLower.secondsAfterStart * 1000L, 1_000L))
    }

    @Test
    fun postponementDisplayKeepsAnAlreadyRaisedOrangeFlag() {
        val flags = SignalMastLayout.flagsWhilePostponementRaised(listOf(
            SignalFlagState("橙", 0xFFF58A00.toInt(), true, false),
            SignalFlagState("class-420", 0xFFFFFFFF.toInt(), true, false)
        ))
        assertEquals(listOf("橙", "AP"), flags.map { it.id })
    }

    fun raceSignalControlsStayDisabledUntilFirstActionBegins() {
        assertEquals(false, SignalMastLayout.canOperateRaceSignals(false, false, false))
        assertEquals(false, SignalMastLayout.canOperateRaceSignals(true, true, false))
        assertEquals(false, SignalMastLayout.canOperateRaceSignals(true, false, true))
        assertEquals(true, SignalMastLayout.canOperateRaceSignals(true, false, false))
    }
    @Test
    fun startRuleSelectsItsMatchingPreparationSignal() {
        assertEquals("P", SignalSequence.preparationFlagForStartRule("P"))
        assertEquals("I", SignalSequence.preparationFlagForStartRule("I"))
        assertEquals("U", SignalSequence.preparationFlagForStartRule("U"))
        assertEquals("Z", SignalSequence.preparationFlagForStartRule("Z"))
        assertEquals("black", SignalSequence.preparationFlagForStartRule("Black"))
        assertEquals("P", SignalSequence.preparationFlagForStartRule("Default"))
    }

    @Test
    fun manualOrangeRaiseAnchorsClassWarningAndKeepsRaceTimeline() {
        val base = SignalSequence.events(durationMinutes = 14, profileIndex = 0)
        val configured = SignalSequence.configuredStandardEvents(
            base, setOf("Class · T−5:00 · 掲揚 · 短音"), 600, 4, false, 0
        )!!
        val anchored = SignalSequence.eventsStartingAtFirstClassWarning(configured)!!
        assertEquals(listOf(0, 60, 240, 300, 540), anchored.map { it.secondsAfterStart })
        assertEquals("クラス旗を掲揚（予告信号）", anchored.first().title)
        assertEquals("橙", anchored.last().flag)
        assertEquals(300_000L, SignalTiming.startAfterOrangeRaise(300_000L, 0L, 5, 15))
        assertEquals(360_000L, SignalTiming.startAfterOrangeRaise(301_000L, 0L, 5, 15))
        assertEquals(60_000L, SignalTiming.startAfterOrangeRaise(50_000L, 0L, 1, 15))
        assertEquals(120_000L, SignalTiming.startAfterOrangeRaise(65_000L, 50_000L, 1, 15))
    }

    @Test
    fun raceStartOffsetTracksOrangePhaseAndDisabledOrange() {
        assertEquals(600, SignalSequence.startReferenceOffset("standard-start", true, 5))
        assertEquals(540, SignalSequence.startReferenceOffset("standard-start", true, 4))
        assertEquals(300, SignalSequence.startReferenceOffset("standard-start", false, 5))
        assertEquals(0, SignalSequence.startReferenceOffset("video-20", true, 5))
    }

    @Test
    fun videoAAndVideoBMatchTheReferenceSignalTimes() {
        val videoA = SignalSequence.events(20, 1, orangeRemovedAfterMinutes = 10, orangeDisplayedMinutes = 5)
        assertEquals(listOf(0, 300, 360, 540, 600, 1200), videoA.map { it.secondsAfterStart })
        assertEquals(listOf("橙", "緑", "青", "青", "緑", "橙"), videoA.map { it.flag })
        assertEquals(listOf(true, true, true, false, false, false), videoA.map { it.raised })
        assertEquals(listOf(listOf(0), listOf(0), listOf(0), listOf(1), listOf(0), emptyList()),
            videoA.map { it.hornPulses })

        val videoB = SignalSequence.events(13, 2, orangeRemovedAfterMinutes = 4, orangeDisplayedMinutes = 4)
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
    fun orangeDisableSettingAppliesToEveryProfileAndRecallKeepsOrangeDown() {
        for (profile in SignalSequence.profiles.indices) {
            assertEquals(false, SignalSequence.events(20, profile, orangeEnabled = false).any { it.flag == "橙" })
        }
        val orangeOff = SignalSequence.events(
            durationMinutes = 14,
            profileIndex = 0,
            orangeEnabled = false,
            orangeDisplayedMinutes = 5,
            orangeRemovedAfterMinutes = 4
        )
        assertEquals(listOf(0, 60, 240, 300), orangeOff.map { it.secondsAfterStart })
        assertEquals(listOf("級", "P", "P", "級"), orangeOff.map { it.flag })

        val longerOrange = SignalSequence.events(
            durationMinutes = 14,
            profileIndex = 0,
            orangeEnabled = true,
            orangeDisplayedMinutes = 7,
            orangeRemovedAfterMinutes = 3
        )
        assertEquals(listOf(0, 420, 480, 660, 720, 900), longerOrange.map { it.secondsAfterStart })

        val restart = SignalSequence.restartEvents(orangeRemovedAfterMinutes = 4)
        assertEquals(setOf("橙", "級"), SignalSequence.flagsAtEvents(restart, 0.0).filter { it.raised }.map { it.id }.toSet())
        assertEquals(listOf(0, 0, 60, 240, 300, 540), restart.map { it.secondsAfterStart })
        assertEquals(listOf("橙"), SignalSequence.flagsAtEvents(restart, 539.0).filter { it.raised }.map { it.id })
        assertEquals(emptyList<String>(), SignalSequence.flagsAtEvents(restart, 540.0).filter { it.raised }.map { it.id })
        assertEquals(listOf("第一代表"), SignalSequence.generalRecallRaise.flagMarks.map { it.id })
        assertEquals(listOf("AP"), SignalSequence.postponementRaise.flagMarks.map { it.id })
    }

    @Test
    fun apRestartKeepsRaisedOrangeUntilItsActualLowerEvent() {
        val restart = SignalSequence.restartEvents(orangeRemovedAfterMinutes = 4)
        val orangeState = restart.first { it.flagMarks.any { mark -> mark.id == "橙" } && it.raised }
        val orangeLower = restart.first { it.flagMarks.any { mark -> mark.id == "橙" } && !it.raised }
        val classWarning = restart.first { it.title.contains("再予告信号") }

        assertTrue(!SignalSequence.shouldReleaseManualOrangeOverride(orangeState))
        assertTrue(SignalSequence.shouldReleaseManualOrangeOverride(orangeLower))
        assertEquals(0, classWarning.secondsAfterStart)
        assertEquals(540, orangeLower.secondsAfterStart)
        assertEquals(60, restart.first { it.title.contains("準備信号") }.secondsAfterStart)
    }

    @Test
    fun apRestartWaitsForOrangeFlagIntervalAndNeverStartsBeforeOneMinute() {
        assertEquals(1_200_000L, SignalTiming.postponementRestartWarningAt(1_000_000L, 900_000L, 5, true))
        assertEquals(1_080_000L, SignalTiming.postponementRestartWarningAt(1_000_000L, 700_000L, 5, true))
        assertEquals(1_320_000L, SignalTiming.postponementRestartWarningAt(1_000_000L, null, 5, true))
        assertEquals(1_080_000L, SignalTiming.postponementRestartWarningAt(1_000_000L, null, 5, false))
        assertEquals(1_260_000L, SignalTiming.postponementApLowerAt(1_000_000L, null, 5, true))
        assertEquals(1_020_000L, SignalTiming.postponementApLowerAt(1_000_000L, 700_000L, 5, true))
        assertEquals(0L, Math.floorMod(SignalTiming.postponementApLowerAt(1_000_000L, 900_000L, 5, true), 60_000L))
    }

    @Test
    fun manualOrangeRaiseIsRecordedWithItsActualSequenceOffset() {
        val events = SignalSequence.eventsStartingAtFirstClassWarning(SignalSequence.events(14, 0))!!
        val timeline = SignalSequence.recordingManualOrangeRaise(events, 754_000L, 960_000L)
        val record = timeline.first { it.id == SignalSequence.MANUAL_ORANGE_RAISE_RECORD_ID }
        assertEquals(-206, record.secondsAfterStart)
        assertEquals(754_000L, 960_000L + record.secondsAfterStart * 1000L)
        assertEquals("橙", record.flag)
        assertEquals(true, record.raised)
    }

    @Test
    fun selectedClassFlagCanBeLogoTextOrInternationalFlag() {
        assertEquals("class-Laser", SignalSequence.events(14, 0, className = "Laser")[1].flag)
        assertEquals("text:Class 1", SignalSequence.events(14, 0, className = "text:Class 1")[1].flag)
        assertEquals("intl:Alpha", SignalSequence.events(14, 0, className = "intl:Alpha")[1].flag)
        assertEquals("internationalFlag", SignalFlagMark("intl:Alpha", 0xFFFFFFFF.toInt()).style)
        assertEquals("textFlag", SignalFlagMark("text:Class 1", 0xFFFFFFFF.toInt()).style)
    }

    @Test
    fun signalSequenceAlignsZeroToRealClockMinuteAfterMinimumLead() {
        assertEquals(60_000L, SignalTiming.scheduledStartAt(10_000L, 15))
        assertEquals(60_000L, SignalTiming.scheduledStartAt(10_000L, 0))
        assertEquals(60_000L, SignalTiming.scheduledStartAt(60_000L, 0))
        assertEquals(120_000L, SignalTiming.scheduledStartAt(50_000L, 15))
    }
    @Test
    fun refreshWaitsForTheNextCorrectedWholeSecond() {
        assertEquals(400L, SignalTiming.millisUntilNextSecond(12_345_600L))
        assertEquals(1L, SignalTiming.millisUntilNextSecond(12_345_999L))
        assertEquals(1000L, SignalTiming.millisUntilNextSecond(12_346_000L))
    }

    @Test
    fun countdownUsesCeilingSoItMatchesClockSeconds() {
        assertEquals(51, SignalTiming.countdownSeconds(50.1))
        assertEquals(51, SignalTiming.countdownSeconds(51.0))
        assertEquals(0, SignalTiming.countdownSeconds(0.0))
    }

    @Test
    fun selectedStartRuleControlsTheRaisedAndLoweredPreparationFlag() {
        val expected = mapOf("P" to "P", "I" to "I", "U" to "U", "Z" to "Z", "black" to "black")
        for ((rule, flag) in expected) {
            val events = SignalSequence.events(14, 0, prepFlag = rule)
            assertEquals(flag, events[2].flag)
            assertEquals(flag, events[3].flag)
            assertEquals(events[2].color, events[3].color)
        }
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
        assertEquals(listOf(0, 0, 60, 240, 300, 540), SignalSequence.restartEvents().map { it.secondsAfterStart })
        assertEquals(listOf(emptyList<Int>(), listOf(0), listOf(0), listOf(1), listOf(0), emptyList()), SignalSequence.restartEvents().map { it.hornPulses })
        assertEquals(listOf(0), SignalSequence.individualRecallRaise.hornPulses)
        assertEquals(listOf(0, 0), SignalSequence.generalRecallRaise.hornPulses)
        assertEquals(listOf(0), SignalSequence.generalRecallLower.hornPulses)
        assertEquals(listOf(0, 0), SignalSequence.postponementRaise.hornPulses)
        assertEquals(listOf(0), SignalSequence.postponementLower.hornPulses)
        assertEquals(listOf(0, 0, 0), SignalSequence.abandonRaise.hornPulses)
        assertEquals(listOf(0), SignalSequence.abandonLower.hornPulses)
    }


    @Test
    fun savedFleetStartRowsDriveRuntimeFlagsAndHorns() {
        val base = SignalSequence.events(
            durationMinutes = 14,
            profileIndex = 0,
            prepFlag = "P",
            orangeEnabled = true,
            orangeRemovedAfterMinutes = 4,
            className = "クラス旗",
            orangeDisplayedMinutes = 5
        )
        val configured = SignalSequence.configuredStandardEvents(
            base = base,
            entries = setOf("Class · T−5:00 · 掲揚 · 短音"),
            referenceOffset = SignalSequence.startReferenceOffset("standard-start", true, 5),
            orangeRemovedAfterMinutes = 4,
            raceDelayEnabled = false,
            raceDelayMinutes = 0
        )!!
        assertEquals(listOf(0, 300, 360, 540, 600, 840), configured.map { it.secondsAfterStart })
        assertEquals(listOf("P", "橙", "級"), SignalSequence.flagsAtEvents(configured, 360.0).filter { it.raised }.map { it.id }.sorted())
        assertEquals(listOf(1), configured.first { it.secondsAfterStart == 540 }.hornPulses)
        assertEquals(emptyList<Int>(), configured.first { it.secondsAfterStart == 840 }.hornPulses)
    }

    @Test
    fun savedStartTimeAndRaceDelayChangeTheGeneratedTimeline() {
        val base = SignalSequence.events()
        val configured = SignalSequence.configuredStandardEvents(
            base = base,
            entries = setOf("Class · T−4:00 · 掲揚 · 長音"),
            referenceOffset = SignalSequence.startReferenceOffset("standard-start", true, 5),
            orangeRemovedAfterMinutes = 4,
            raceDelayEnabled = false,
            raceDelayMinutes = 0
        )!!
        assertEquals(listOf(0, 360, 420, 600, 660, 900), configured.map { it.secondsAfterStart })
        assertEquals(listOf(1), configured.first { it.secondsAfterStart == 360 }.hornPulses)
    }

    @Test
    fun sequentialFleetStartsKeepTheirSelectedClassFlagsAndOrder() {
        val configured = SignalSequence.configuredStandardEvents(
            base = SignalSequence.events(),
            entries = listOf(
                "Class:420 · T−5:00 · 掲揚 · 短音",
                "Class:470 · T−5:00 · 掲揚 · 短音"
            ),
            referenceOffset = SignalSequence.startReferenceOffset("standard-start", true, 5),
            orangeRemovedAfterMinutes = 4,
            raceDelayEnabled = true,
            raceDelayMinutes = 1
        )!!

        assertEquals("class-420", configured.first { it.raised && it.title.contains("420") }.flag)
        assertEquals(300, configured.first { it.raised && it.title.contains("420") }.secondsAfterStart)
        assertEquals("class-470", configured.first { it.raised && it.title.contains("470") }.flag)
        assertEquals(360, configured.first { it.raised && it.title.contains("470") }.secondsAfterStart)
        assertEquals("class-420", configured.first { !it.raised && it.title.contains("420") }.flag)
    }

    @Test
    fun fleetIntervalAppliesWithoutSwitchAndKeepsAutomaticClassLowerings() {
        val configured = SignalSequence.configuredStandardEvents(
            base = SignalSequence.events(),
            entries = setOf(
                "Class · T−5:00 · 掲揚 · 短音",
                "Class · T−4:00 · 掲揚 · 短音",
                "Class · T−1:00 · 降下 · 長音"
            ),
            referenceOffset = SignalSequence.startReferenceOffset("standard-start", true, 5),
            orangeRemovedAfterMinutes = 4,
            raceDelayEnabled = false,
            raceDelayMinutes = 2
        )!!

        assertTrue(configured.any { it.secondsAfterStart == 300 && it.raised && it.title.contains("予告信号") })
        assertTrue(configured.any { it.secondsAfterStart == 420 && it.raised && it.title.contains("予告信号") })
        assertTrue(configured.any { it.secondsAfterStart == 540 && !it.raised && it.hornPulses == listOf(1) })
        assertTrue(configured.any { it.secondsAfterStart == 600 && !it.raised && it.title.contains("スタート") })
        assertTrue(configured.any { it.secondsAfterStart == 720 && !it.raised && it.title.contains("スタート") })
        assertTrue(configured.any { it.secondsAfterStart == 960 && !it.raised && it.flag == "橙" })
    }


    @Test
    fun savedPrepAndIndividualSignalRowsControlTheirOwnTimesAndHorns() {
        val base = SignalSequence.events(
            durationMinutes = 14,
            profileIndex = 0,
            prepFlag = "P",
            orangeEnabled = true,
            orangeRemovedAfterMinutes = 4,
            className = "クラス旗",
            orangeDisplayedMinutes = 5
        )
        val configured = SignalSequence.configuredStandardEvents(
            base = base,
            entries = setOf(
                "Class · T−5:00 · 掲揚 · 短音",
                "I · T−4:00 · 掲揚 · 短音",
                "I · T−1:00 · 降下 · 長音",
                "X · T−0:30 · 掲揚 · 短音"
            ),
            referenceOffset = SignalSequence.startReferenceOffset("standard-start", true, 5),
            orangeRemovedAfterMinutes = 4,
            raceDelayEnabled = false,
            raceDelayMinutes = 0
        )!!
        assertEquals(listOf(0, 300, 360, 540, 570, 600, 840), configured.map { it.secondsAfterStart })
        assertEquals(listOf(1), configured.first { it.secondsAfterStart == 540 }.hornPulses)
        assertEquals("X", configured.first { it.secondsAfterStart == 570 }.flag)
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
    fun referenceVideoTimingDoesNotScaleWithDuration() {
        assertEquals(listOf(0, 300, 360, 540, 600, 840), SignalSequence.events(10, 1).map { it.secondsAfterStart })
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
        assertEquals(240_000L, SignalTiming.restartWarningAt(125_000L))
    }


    @Test
    fun raceStartCountdownTargetsTheClassLoweringAtRealZero() {
        val standard = SignalSequence.events(
            durationMinutes = 14,
            profileIndex = 0,
            prepFlag = "P",
            orangeEnabled = true,
            orangeRemovedAfterMinutes = 4,
            className = "クラス旗",
            orangeDisplayedMinutes = 5
        )
        val index = SignalSequence.raceStartEventIndex(standard)
        assertEquals(4, index)
        val raceStartSeconds = standard[index!!].secondsAfterStart
        assertEquals(600, raceStartSeconds)
        assertEquals(523, raceStartSeconds - 77)

        val videoA = SignalSequence.profiles.first { it.id == "video-20" }.events
        val videoB = SignalSequence.profiles.first { it.id == "video-13" }.events
        assertEquals(600, videoA[SignalSequence.raceStartEventIndex(videoA)!!].secondsAfterStart)
        assertEquals(540, videoB[SignalSequence.raceStartEventIndex(videoB)!!].secondsAfterStart)
    }

    @Test
    fun frozenSignalPlanRoundTripsWithoutFollowingLaterOrangeSettings() {
        val frozen = SignalSequence.events(14, 0, orangeEnabled = true, orangeRemovedAfterMinutes = 4, orangeDisplayedMinutes = 5)
        val saved = SignalSequence.encodeEvents(frozen)
        val laterConfiguration = SignalSequence.events(14, 0, orangeEnabled = true, orangeRemovedAfterMinutes = 9, orangeDisplayedMinutes = 8)
        val restored = SignalSequence.decodeEvents(saved)

        assertEquals(frozen, restored)
        assertNotEquals(laterConfiguration.map { it.secondsAfterStart }, restored!!.map { it.secondsAfterStart })
        assertEquals(600, restored[SignalSequence.raceStartEventIndex(restored)!!].secondsAfterStart)
    }
}

