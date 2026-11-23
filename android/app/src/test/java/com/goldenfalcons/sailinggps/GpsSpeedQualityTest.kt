package com.goldenfalcons.sailinggps

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class GpsSpeedQualityTest {
    @Test fun rejectsMissingOrWeakLocationFix() {
        assertNull(GpsSpeedQuality.acceptedSpeedMps(2.0, null, 0.2))
        assertNull(GpsSpeedQuality.acceptedSpeedMps(2.0, 16.0, 0.2))
        assertNull(GpsSpeedQuality.acceptedSpeedMps(2.0, 8.0, null))
    }

    @Test fun rejectsUncertainSpeedAndKeepsReliableSpeed() {
        assertNull(GpsSpeedQuality.acceptedSpeedMps(4.0, 4.0, 1.01))
        assertEquals(2.5, GpsSpeedQuality.acceptedSpeedMps(2.5, 12.0, 0.6)!!, 0.0)
        assertEquals(1.0, GpsSpeedQuality.acceptedSpeedMps(1.0, 5.0, null)!!, 0.0)
    }

    @Test fun rejectsInvalidValues() {
        assertNull(GpsSpeedQuality.acceptedSpeedMps(Double.NaN, 2.0, 0.2))
        assertNull(GpsSpeedQuality.acceptedSpeedMps(-1.0, 2.0, 0.2))
    }
}
