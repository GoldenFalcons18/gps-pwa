package com.goldenfalcons.sailinggps

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DaylightAppearanceTest {
    @Test fun daytimeAndNighttimeAreDistinguishedAtJapanLocation() {
        assertTrue(NavigationUtils.isDaylight(35.3, 139.5, 1782010800000L))
        assertFalse(NavigationUtils.isDaylight(35.3, 139.5, 1782054000000L))
    }
}
