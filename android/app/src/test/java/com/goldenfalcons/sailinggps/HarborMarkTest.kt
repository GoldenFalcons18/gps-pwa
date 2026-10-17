package com.goldenfalcons.sailinggps
import org.junit.Assert.assertEquals
import org.junit.Test

class HarborMarkTest {
    @Test fun harborSurvivesJsonAndKmzTransferBetweenPlatforms() {
        val point=Waypoint(name="港",lat=35.0,lon=139.0,mark="港",color="#12ABCD",group="港一覧")
        assertEquals("symbol:marine.harbor",WaypointArchive.archiveMark(point))
        val json=WaypointArchive.decode(WaypointArchive.encode(listOf(point))).single()
        val kmz=KmlArchive.decode(KmlArchive.encode(listOf(point),emptyList(),true)).waypoints.single()
        for(restored in listOf(json,kmz)) {
            assertEquals("港",restored.mark)
            assertEquals("symbol:marine.harbor",WaypointArchive.archiveMark(restored))
            assertEquals(point.color,restored.color)
            assertEquals(point.group,restored.group)
        }
    }
}
