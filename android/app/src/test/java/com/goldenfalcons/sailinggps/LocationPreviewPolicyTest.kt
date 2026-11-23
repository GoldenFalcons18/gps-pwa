package com.goldenfalcons.sailinggps

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LocationPreviewPolicyTest {
    @Test fun freshFixIsAccepted() {
        assertTrue(LocationPreviewPolicy.isUsableAge(0L))
        assertTrue(LocationPreviewPolicy.isUsableAge(LocationPreviewPolicy.FRESH_FIX_MAX_AGE_MS))
        assertFalse(LocationPreviewPolicy.isUsableAge(LocationPreviewPolicy.FRESH_FIX_MAX_AGE_MS + 1L))
    }

    @Test fun cachedPositionOnlyKeepsMapMarkerForFiveMinutes() {
        assertFalse(LocationPreviewPolicy.isUsableAge(60_000L))
        assertTrue(LocationPreviewPolicy.isUsableAge(60_000L, allowCachedDisplay = true))
        assertTrue(LocationPreviewPolicy.isUsableAge(LocationPreviewPolicy.CACHED_DISPLAY_MAX_AGE_MS, allowCachedDisplay = true))
        assertFalse(LocationPreviewPolicy.isUsableAge(LocationPreviewPolicy.CACHED_DISPLAY_MAX_AGE_MS + 1L, allowCachedDisplay = true))
        assertFalse(LocationPreviewPolicy.isUsableAge(-1L, allowCachedDisplay = true))
    }
}
