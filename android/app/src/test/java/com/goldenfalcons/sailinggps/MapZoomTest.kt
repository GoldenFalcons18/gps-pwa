package com.goldenfalcons.sailinggps
import org.junit.Assert.assertEquals
import org.junit.Test
class MapZoomTest {
    @Test fun scaleChangesZoomAndPreservesBoatAnchor() {
        assertEquals(2.0, DisplayNavigation.zoom(35.0, 50.0, 100.0) - DisplayNavigation.zoom(35.0, 50.0, 400.0), 0.000001)
        val close = DisplayNavigation.followCenter(0.0, 0.0, 0.0, 400.0, 50.0, 100.0)
        val far = DisplayNavigation.followCenter(0.0, 0.0, 0.0, 400.0, 50.0, 400.0)
        assertEquals(close.first * 4, far.first, 0.000001)
        assertEquals(0.0, close.second, 0.000001)
    }
}
