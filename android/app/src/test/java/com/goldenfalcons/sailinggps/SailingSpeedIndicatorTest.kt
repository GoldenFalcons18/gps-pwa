package com.goldenfalcons.sailinggps

import org.junit.Assert.assertEquals
import org.junit.Test

class SailingSpeedIndicatorTest {
    @Test fun belowTargetIsYellowBand() {
        assertEquals(SailingSpeedBand.BELOW_TARGET, SailingSpeedIndicator.resolve(4.94, 5.0, true))
    }

    @Test fun displayedEqualValueIsWhiteBand() {
        assertEquals(SailingSpeedBand.APPROXIMATELY_TARGET, SailingSpeedIndicator.resolve(4.96, 5.0, true))
    }

    @Test fun aboveTargetIsGreenBand() {
        assertEquals(SailingSpeedBand.ABOVE_TARGET, SailingSpeedIndicator.resolve(5.06, 5.0, true))
    }

    @Test fun disabledUsesExistingGreenBand() {
        assertEquals(SailingSpeedBand.ABOVE_TARGET, SailingSpeedIndicator.resolve(1.0, 5.0, false))
    }

    @Test fun missingSpeedIsUnavailable() {
        assertEquals(SailingSpeedBand.UNAVAILABLE, SailingSpeedIndicator.resolve(null, 5.0, true))
    }
}
