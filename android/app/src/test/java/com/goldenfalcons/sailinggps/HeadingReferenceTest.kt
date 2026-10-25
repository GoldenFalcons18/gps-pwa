package com.goldenfalcons.sailinggps

import org.junit.Assert.*
import org.junit.Test

class HeadingReferenceTest {
    @Test fun deviceRotationDrivesMagneticModeEvenWhileMoving() {
        val first = HeadingReference.resolve(false, 26.0, -7.9, 200.0, 3.0)!!
        val second = HeadingReference.resolve(false, 119.0, -7.9, 200.0, 3.0)!!
        assertTrue(first.magnetic)
        assertEquals(18.1, first.trueHeading!!, 0.0001)
        assertEquals(111.1, second.trueHeading!!, 0.0001)
        // The map uses true north; the compass displays magnetic north. Both arrows agree.
        val targetTrue = 132.1
        val targetMag = 140.0
        assertEquals(HeadingReference.relative(targetTrue, first.trueHeading), HeadingReference.relative(targetMag, first.heading), 0.0001)
        assertEquals(HeadingReference.relative(targetTrue, second.trueHeading), HeadingReference.relative(targetMag, second.heading), 0.0001)
    }
    @Test fun gpsModeUsesCourseAndStationaryFallsBackToCompass() {
        assertFalse(HeadingReference.resolve(true, 26.0, -7.9, 200.0, 3.0)!!.magnetic)
        assertTrue(HeadingReference.resolve(true, 26.0, -7.9, 200.0, 0.0)!!.magnetic)
        assertFalse(HeadingReference.resolve(false, null, null, 200.0, 3.0)!!.magnetic)
        assertNull(HeadingReference.resolve(true, null, null, -1.0, 3.0))
        assertNull(HeadingReference.resolve(true, null, null, Double.NaN, 3.0))
    }
    @Test fun compassCanOverrideGpsCourseWhileMoving() {
        val result=HeadingReference.resolve(true,26.0,-7.9,200.0,3.0,compassWhileMoving=true)!!
        assertTrue(result.magnetic)
        assertEquals(18.1,result.trueHeading!!,0.0001)
        assertFalse(HeadingReference.resolve(true,null,null,200.0,3.0,compassWhileMoving=true)!!.magnetic)
    }
    @Test fun northCrossingUsesTheShortArc() {
        assertEquals(2.0, HeadingReference.relative(1.0, 359.0), 0.0001)
        assertEquals(-2.0, HeadingReference.relative(359.0, 1.0), 0.0001)
    }
}
