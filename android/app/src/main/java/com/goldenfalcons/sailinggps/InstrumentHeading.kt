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
    fun resolve(course:Double?,speed:Double?,magneticHeading:Double?,declination:Double?,magnetic:Boolean,compassWhileMoving:Boolean=false):Reading? {
        val gps=valid(course)
        val compass=valid(magneticHeading)
        val compassValue=compass?.let{compassHeading->if(magnetic) compassHeading else declination?.takeIf{it.isFinite()}?.let{value->NavigationUtils.normalize360(compassHeading+value)}}
        if(compassWhileMoving && compassValue!=null) return Reading(compassValue,true)
        if(speed!=null && speed.isFinite() && speed>=0.25 && gps!=null) return bearing(gps,magnetic,declination)?.let{Reading(it,false)}
        return compassValue?.let{Reading(it,true)}
    }
}
