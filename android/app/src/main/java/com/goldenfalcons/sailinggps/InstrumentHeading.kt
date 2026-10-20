package com.goldenfalcons.sailinggps

object InstrumentHeading {
    data class Reading(val value:Double,val compass:Boolean)
    private fun valid(value:Double?)=value?.takeIf{it.isFinite() && it>=0 && it<360}
    fun bearing(trueBearing:Double?,magnetic:Boolean,declination:Double?):Double? {
        val value=valid(trueBearing) ?: return null
        if(!magnetic) return value
        val correction=declination?.takeIf{it.isFinite()} ?: return null
        return NavigationUtils.normalize360(value-correction)
    }
    fun resolve(course:Double?,speed:Double?,magneticHeading:Double?,declination:Double?,magnetic:Boolean):Reading? {
        val gps=valid(course)
        if(speed!=null && speed.isFinite() && speed>=0.25 && gps!=null) return bearing(gps,magnetic,declination)?.let{Reading(it,false)}
        val compass=valid(magneticHeading) ?: return null
        val heading=if(magnetic) compass else declination?.takeIf{it.isFinite()}?.let{NavigationUtils.normalize360(compass+it)}
        return heading?.let{Reading(it,true)}
    }
}
