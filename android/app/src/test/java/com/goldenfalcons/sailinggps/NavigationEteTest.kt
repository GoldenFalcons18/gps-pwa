package com.goldenfalcons.sailinggps

import org.junit.Assert.assertEquals
import org.junit.Test

class NavigationEteTest {
    @Test fun travelTimeAndRounding() {
        assertEquals("00:08:20", NavigationUtils.ete(1000.0, 2.0))
        assertEquals("01:01:01", NavigationUtils.ete(3661.0, 1.0))
        assertEquals("00:00:01", NavigationUtils.ete(0.1, 1.0))
        assertEquals("00:00:00", NavigationUtils.ete(0.0, null))
    }
    @Test fun missingOrUnreliableData() {
        for (speed in listOf(null, 0.0, -1.0, 0.24, Double.NaN, Double.POSITIVE_INFINITY)) {
            assertEquals("--:--:--", NavigationUtils.ete(1000.0, speed))
        }
        for (distance in listOf(null, -1.0, Double.NaN, Double.POSITIVE_INFINITY, Double.MAX_VALUE)) {
            assertEquals("--:--:--", NavigationUtils.ete(distance, 1.0))
        }
        assertEquals("00:00:04", NavigationUtils.ete(1.0, 0.25))
    }
}
