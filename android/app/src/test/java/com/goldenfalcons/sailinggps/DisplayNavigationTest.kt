package com.goldenfalcons.sailinggps
import org.junit.Assert.*
import org.junit.Test

class DisplayNavigationTest {
    @Test fun projectedMarksAreGeodesicAndCrossDateline() {
        for (distance in 100..500 step 100) {
            val p = DisplayNavigation.destination(35.318, 139.467, 87.0, distance.toDouble())
            assertEquals(distance.toDouble(), NavigationUtils.distanceMeters(35.318,139.467,p.first,p.second), 0.001)
            assertEquals(87.0, NavigationUtils.bearingDegrees(35.318,139.467,p.first,p.second), 0.001)
        }
        val p = DisplayNavigation.destination(0.0,179.999,90.0,500.0)
        assertTrue(p.second < -179.0)
        assertEquals(500.0, NavigationUtils.distanceMeters(0.0,179.999,p.first,p.second),0.001)
    }
    @Test fun scaleKeeps200MetersInOneCentimeter() {
        for (latitude in listOf(0.0,35.318,70.0)) {
            val zoom = DisplayNavigation.zoom(latitude, 400.0/2.54)
            val metersPerPixel = 156543.033928 * kotlin.math.cos(Math.toRadians(latitude)) / Math.pow(2.0,zoom)
            assertEquals(200.0, metersPerPixel * 400.0/2.54, 0.001)
        }
    }
    @Test fun distanceUnits() {
        assertTrue(DisplayNavigation.distance(999.0,true).endsWith(" m"))
        assertTrue(DisplayNavigation.distance(1000.0,true).endsWith(" km"))
        assertTrue(DisplayNavigation.distance(1852.0,false).endsWith(" nm"))
    }
}
