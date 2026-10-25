package com.goldenfalcons.sailinggps

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class StartLineMathTest {
    @Test fun distanceToSegmentAndBeyondEndpoints() {
        val west = StartLineCoordinate(0.0, 0.0)
        val east = StartLineCoordinate(0.0, 0.01)
        val midpoint = StartLineCoordinate(0.001, 0.005)
        assertEquals(111.2, StartLineMath.distanceMeters(midpoint, west, east)!!, 1.0)
        val beyond = StartLineCoordinate(0.0, -0.001)
        assertEquals(111.2, StartLineMath.distanceMeters(beyond, west, east)!!, 1.0)
    }

    @Test fun missingInvalidAndCountdown() {
        val boat = StartLineCoordinate(35.0, 139.0)
        assertNull(StartLineMath.distanceMeters(boat, null, boat))
        assertNull(StartLineMath.distanceMeters(boat, boat, StartLineCoordinate(91.0, 0.0)))
        assertEquals("05:00", StartLineMath.countdown(300.0))
        assertEquals("00:01", StartLineMath.countdown(0.1))
        org.junit.Assert.assertTrue(StartLineMath.isMinuteCountdown(10.0))
        org.junit.Assert.assertTrue(StartLineMath.isMinuteCountdown(61.0))
        org.junit.Assert.assertFalse(StartLineMath.isMinuteCountdown(11.0))
        org.junit.Assert.assertTrue(StartLineMath.isThirtySecondWarning(30.0))
        org.junit.Assert.assertFalse(StartLineMath.isThirtySecondWarning(90.0))
        org.junit.Assert.assertTrue(StartLineMath.isMinuteMarker(60.0))
        org.junit.Assert.assertTrue(StartLineMath.isMinuteMarker(180.0))
        org.junit.Assert.assertEquals(60L, StartLineMath.nearestMinute(89.0))
        org.junit.Assert.assertEquals(120L, StartLineMath.nearestMinute(91.0))
    }
}
