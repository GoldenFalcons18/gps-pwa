package com.goldenfalcons.sailinggps
import org.junit.Assert.*
import org.junit.Test
class InstrumentHeadingTest {
    @Test fun courseAndTargetUseSameCorrection() {
        assertEquals(152.0,InstrumentHeading.bearing(144.0,true,-8.0)!!,0.0001)
        assertEquals(InstrumentHeading.Reading(238.0,false),InstrumentHeading.resolve(230.0,3.0,226.0,-8.0,true))
        assertEquals(InstrumentHeading.Reading(230.0,false),InstrumentHeading.resolve(230.0,3.0,226.0,-8.0,false))
    }
    @Test fun lowSpeedAndMissingCourseUseCompass() {
        for(speed in listOf(0.0,0.24,null)) {
            assertEquals(InstrumentHeading.Reading(226.0,true),InstrumentHeading.resolve(82.0,speed,226.0,-8.0,true))
            assertEquals(InstrumentHeading.Reading(218.0,true),InstrumentHeading.resolve(82.0,speed,226.0,-8.0,false))
        }
        assertEquals(InstrumentHeading.Reading(226.0,true),InstrumentHeading.resolve(-1.0,3.0,226.0,-8.0,true))
    }
    @Test fun missingCompassDoesNotInventCorrection() {
        assertNull(InstrumentHeading.bearing(144.0,true,null));assertEquals(144.0,InstrumentHeading.bearing(144.0,false,null)!!,0.0001)
        assertNull(InstrumentHeading.resolve(82.0,0.0,null,null,true))
        assertNull(InstrumentHeading.resolve(82.0,3.0,226.0,null,true))
        assertEquals(InstrumentHeading.Reading(82.0,false),InstrumentHeading.resolve(82.0,3.0,null,null,false))
    }
    @Test fun northWrapAndInvalidAngles() {
        assertEquals(354.0,InstrumentHeading.bearing(2.0,true,8.0)!!,0.0001)
        assertEquals(6.0,InstrumentHeading.bearing(358.0,true,-8.0)!!,0.0001)
        assertNull(InstrumentHeading.bearing(Double.NaN,false,0.0))
    }
}
