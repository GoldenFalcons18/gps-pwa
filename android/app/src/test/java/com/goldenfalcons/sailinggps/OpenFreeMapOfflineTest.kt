package com.goldenfalcons.sailinggps

import org.junit.Assert.assertEquals
import org.junit.Test

class OpenFreeMapOfflineTest {
    @Test
    fun oneWorldTileAtZoomZero() {
        assertEquals(
            1L,
            OpenFreeMapConfig.estimateTileCount(-180.0, -85.05112878, 180.0, 85.05112878, 0, 0)
        )
    }

    @Test
    fun worldTilePyramidCountsEveryZoomLevel() {
        assertEquals(
            5L,
            OpenFreeMapConfig.estimateTileCount(-180.0, -85.05112878, 180.0, 85.05112878, 0, 1)
        )
    }

    @Test
    fun tileCountStopsOnceProviderLimitIsExceeded() {
        val count = OpenFreeMapConfig.estimateTileCount(-180.0, -85.05112878, 180.0, 85.05112878, 0, 8)
        assertEquals(true, count > OpenFreeMapConfig.MAX_TILES_PER_DOWNLOAD)
    }

    @Test
    fun dateLineCrossingBoundsAreCountedOnBothSides() {
        val count = OpenFreeMapConfig.estimateTileCount(170.0, -10.0, -170.0, 10.0, 2, 2)
        assertEquals(4L, count)
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsUnsupportedLatitude() {
        OpenFreeMapConfig.estimateTileCount(-1.0, -90.0, 1.0, 1.0, 0, 0)
    }
}
