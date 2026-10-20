package com.goldenfalcons.sailinggps

import org.junit.Assert.*
import org.junit.Test

class ZoneMonitorTest {
    private val circle=ZoneMonitor.Zone("reef","障害物",100.0,listOf(MapCoordinate(0.0,0.0)))
    @Test fun baselineCrossingsAndDuplicateFixes() {
        val monitor=ZoneMonitor()
        fun fix(lon:Double,time:Double)=monitor.update(listOf(circle),MapCoordinate(0.0,lon),5.0,time,time,confirmations=2)
        assertTrue(fix(0.002,1.0).isEmpty());assertTrue(fix(0.002,2.0).isEmpty())
        assertTrue(fix(0.0,3.0).isEmpty());assertTrue(fix(0.0,3.0).isEmpty())
        val entered=fix(0.0,4.0);assertEquals(1,entered.size);assertTrue(entered.single().entered)
        assertTrue(fix(0.0,5.0).isEmpty());assertTrue(fix(0.002,6.0).isEmpty())
        assertFalse(fix(0.002,7.0).single().entered)
    }
    @Test fun uncertaintyAndBadAccuracyBreakConfirmation() {
        val monitor=ZoneMonitor()
        fun fix(lon:Double,time:Double,accuracy:Double=5.0,now:Double=time)=monitor.update(listOf(circle),MapCoordinate(0.0,lon),accuracy,time,now,confirmations=2)
        fix(0.002,1.0);fix(0.002,2.0);fix(0.0,3.0)
        assertTrue(fix(0.0,4.0,100.0).isEmpty());assertTrue(fix(0.0,5.0).isEmpty())
        assertTrue(fix(0.0009,6.0).isEmpty());assertTrue(fix(0.0,7.0).isEmpty())
        assertTrue(fix(0.0,8.0,5.0,30.0).isEmpty());assertTrue(fix(0.0,31.0).isEmpty())
        assertEquals(1,fix(0.0,32.0).size)
    }
    @Test fun geometryChangesAndRemovalResetBaseline() {
        val monitor=ZoneMonitor()
        for(time in 1..2) monitor.update(listOf(circle),MapCoordinate(0.0,0.002),5.0,time.toDouble(),time.toDouble(),confirmations=2)
        val changed=circle.copy(circleRadius=500.0)
        for(time in 3..4) assertTrue(monitor.update(listOf(changed),MapCoordinate(0.0,0.0),5.0,time.toDouble(),time.toDouble(),confirmations=2).isEmpty())
        monitor.update(emptyList(),MapCoordinate(0.0,0.0),5.0,5.0,5.0)
        assertTrue(monitor.update(listOf(circle),MapCoordinate(0.0,0.002),5.0,6.0,6.0,confirmations=1).isEmpty())
    }
    @Test fun polygonAcrossDateLine() {
        val polygon=ZoneMonitor.Zone("area","港",points=listOf(MapCoordinate(-0.01,179.99),MapCoordinate(-0.01,-179.99),MapCoordinate(0.01,-179.99),MapCoordinate(0.01,179.99)))
        assertTrue(polygon.clearance(MapCoordinate(0.0,0.0))!! < 0)
        assertTrue(polygon.clearance(MapCoordinate(0.0,180.0))!!>1000)
        assertTrue(polygon.clearance(MapCoordinate(0.02,180.0))!! < -1000)
        assertEquals(0.0,polygon.clearance(MapCoordinate(0.01,180.0))!!,0.001)
    }
    @Test fun courseUsesFreshMovingGpsOnly() {
        assertEquals(359.9,InstrumentSettings.course(359.9,2.0,1.0)!!,0.0001)
        assertEquals(0.0,InstrumentSettings.course(0.0,2.0,1.0)!!,0.0001)
        for(course in listOf(null,-1.0,360.0,Double.NaN,Double.POSITIVE_INFINITY)) assertNull(InstrumentSettings.course(course,2.0,1.0))
        assertNull(InstrumentSettings.course(82.0,0.1,1.0));assertNull(InstrumentSettings.course(82.0,null,1.0))
        assertNull(InstrumentSettings.course(82.0,2.0,16.0));assertNull(InstrumentSettings.course(82.0,2.0,-1.0))
    }
    @Test fun coordinateRoundingAndUnreliableEta() {
        assertEquals("35.500000°S",InstrumentSettings.coordinate(-35.5,true,"dd"))
        assertEquals("36°00′00.0″N",InstrumentSettings.coordinate(35.9999999,true,"dms"))
        assertEquals("--:--:--",InstrumentSettings.arrival(1000.0,0.0,0,true,false))
    }
}
