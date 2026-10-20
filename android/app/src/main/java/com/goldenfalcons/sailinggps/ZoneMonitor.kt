package com.goldenfalcons.sailinggps

import kotlin.math.*

/** No notification for the initial baseline. Boundary uncertainty never counts as a crossing. */
class ZoneMonitor {
    data class Zone(val id:String,val name:String,val circleRadius:Double?=null,val points:List<MapCoordinate>) {
        fun clearance(point:MapCoordinate):Double? {
            if (!point.lat.isFinite() || !point.lon.isFinite() || points.any{!it.lat.isFinite() || !it.lon.isFinite()}) return null
            circleRadius?.let { radius ->
                val center=points.firstOrNull() ?: return null
                if (!radius.isFinite() || radius<=0) return null
                return radius-NavigationUtils.distanceMeters(center.lat,center.lon,point.lat,point.lon)
            }
            if(points.size<3) return null
            val xy=points.map{p->
                val longitude=((p.lon-point.lon+540)%360)-180
                Pair(Math.toRadians(longitude)*6371000*cos(Math.toRadians(point.lat)),Math.toRadians(p.lat-point.lat)*6371000)
            }
            var inside=false;var nearest=Double.POSITIVE_INFINITY
            xy.indices.forEach { i ->
                val a=xy[i];val b=xy[(i+1)%xy.size];val dx=b.first-a.first;val dy=b.second-a.second
                if((a.second>0)!=(b.second>0) && a.first+(b.first-a.first)*(-a.second)/(b.second-a.second)>0) inside=!inside
                val length=dx*dx+dy*dy
                val t=if(length>0) (-(a.first*dx+a.second*dy)/length).coerceIn(0.0,1.0) else 0.0
                nearest=min(nearest,hypot(a.first+t*dx,a.second+t*dy))
            }
            return if(inside) nearest else -nearest
        }
    }
    data class Event(val id:String,val name:String,val entered:Boolean)
    private data class State(val zone:Zone,var stable:Boolean?=null,var candidate:Boolean?=null,var count:Int=0,var last:Double=Double.NEGATIVE_INFINITY)
    private val states=mutableMapOf<String,State>()
    fun reset(){states.clear()}
    fun update(zones:List<Zone>,point:MapCoordinate,accuracy:Double,timestamp:Double,now:Double,maximumAccuracy:Double=50.0,margin:Double=10.0,confirmations:Int=3):List<Event> {
        states.keys.retainAll(zones.map{it.id}.toSet())
        if(!accuracy.isFinite() || accuracy<0 || accuracy>maximumAccuracy || now-timestamp !in 0.0..15.0) {
            states.values.forEach{it.candidate=null;it.count=0};return emptyList()
        }
        val events=mutableListOf<Event>()
        zones.forEach { zone ->
            val state=states[zone.id]?.takeIf{it.zone==zone} ?: State(zone).also{states[zone.id]=it}
            if(timestamp<=state.last) return@forEach
            state.last=timestamp
            val clearance=zone.clearance(point)
            if(clearance==null || abs(clearance)<=max(margin,accuracy)) {state.candidate=null;state.count=0;return@forEach}
            val inside=clearance>0
            if(state.candidate==inside) state.count++ else {state.candidate=inside;state.count=1}
            if(state.count>=max(1,confirmations) && state.stable!=inside) {
                if(state.stable!=null) events+=Event(zone.id,zone.name,inside)
                state.stable=inside
            }
        }
        return events
    }
}
