package com.goldenfalcons.sailinggps

import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import kotlin.math.*

data class MapCoordinate(val lat: Double, val lon: Double)
data class MapFeature(val id: String = UUID.randomUUID().toString(), val name: String, val kind: String,
    val waypointIds: List<String> = emptyList(), val coordinates: List<MapCoordinate> = emptyList(),
    val radius: Double = 200.0, val color: String = "#00AAFF", val group: String = "", val visible: Boolean = true) {
    fun points(waypoints: List<Waypoint>): List<MapCoordinate> = if (waypointIds.isEmpty()) coordinates else waypointIds.mapNotNull { id -> waypoints.firstOrNull { it.id == id }?.let { MapCoordinate(it.lat,it.lon) } }
    fun boundary(waypoints: List<Waypoint>): List<MapCoordinate> {
        val p = points(waypoints)
        if (kind != "circle") return p
        val c = p.firstOrNull() ?: return emptyList()
        return (0..72).map { DisplayNavigation.destination(c.lat,c.lon,it*5.0,radius).let { v -> MapCoordinate(v.first,v.second) } }
    }
    fun validate() {
        require(name.isNotBlank() && name.length <= 1000 && kind in listOf("circle","area","line")) { "図形が無効です" }
        val n = if (waypointIds.isEmpty()) coordinates.size else waypointIds.size
        require(n >= if (kind == "area") 3 else if (kind == "line") 2 else 1) { "地点が不足しています" }
        require(n <= 10000 && radius.isFinite() && radius > 0 && radius <= 1000000) { "半径が無効です（1～1000000m）" }
        require(Regex("#[0-9A-Fa-f]{6}").matches(color)) { "色は#RRGGBBで入力してください" }
        coordinates.forEach { require(it.lat.isFinite() && it.lon.isFinite() && it.lat in -90.0..90.0 && it.lon in -180.0..180.0) }
    }
    fun json() = JSONObject().put("id",id).put("name",name).put("kind",kind).put("waypointIds",JSONArray(waypointIds)).put("coordinates",JSONArray(coordinates.map { listOf(it.lat,it.lon) })).put("radius",radius).put("color",color).put("group",group).put("visible",visible)
    companion object {
        fun from(o: JSONObject) = MapFeature(o.getString("id"),o.getString("name"),o.getString("kind"),
            o.optJSONArray("waypointIds")?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList(),
            o.optJSONArray("coordinates")?.let { a -> (0 until a.length()).map { a.getJSONArray(it).let { p -> MapCoordinate(p.getDouble(0),p.getDouble(1)) } } } ?: emptyList(),
            o.optDouble("radius",200.0),o.optString("color","#00AAFF"),o.optString("group",""),o.optBoolean("visible",true)).also { it.validate() }
    }
}
data class MapLibrary(val groups: List<String> = emptyList(), val hiddenGroups: Set<String> = emptySet(), val features: List<MapFeature> = emptyList()) {
    fun json() = JSONObject().put("groups",JSONArray(groups)).put("hiddenGroups",JSONArray(hiddenGroups.toList())).put("features",JSONArray(features.map { it.json() }))
    companion object {
        fun from(raw: String): MapLibrary { val o=JSONObject(raw);fun strings(key: String): List<String> = o.optJSONArray(key)?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList()
            val a=o.optJSONArray("features");return MapLibrary(strings("groups"),strings("hiddenGroups").toSet(),a?.let { (0 until it.length()).map { i -> MapFeature.from(it.getJSONObject(i)) } } ?: emptyList()) }
    }
}


object DefaultWaypointFolder {
    fun resolve(requested:String?,folders:List<String>,waypointFolders:List<String>):String {
        val populated=waypointFolders.filter{it.isNotBlank()}.distinct().sorted()
        val available=(folders+populated).filter{it.isNotBlank()}.distinct().sorted()
        return requested?.takeIf{it in available} ?: populated.firstOrNull() ?: available.firstOrNull() ?: "メインフォルダ"
    }
}
