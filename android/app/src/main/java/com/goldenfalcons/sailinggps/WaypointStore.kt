package com.goldenfalcons.sailinggps

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

data class Waypoint(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val lat: Double,
    val lon: Double,
    val mark: String = "●",
    val color: String = "#FFAA00",
    val note: String? = null,
    val archiveMark: String? = null,
    val group: String = ""
)

class WaypointStore(context: Context) {
    private val prefs = context.getSharedPreferences("waypoints", Context.MODE_PRIVATE)

    fun loadAll(): MutableList<Waypoint> {
        val raw = prefs.getString("items", "[]") ?: "[]"
        val arr = JSONArray(raw)
        val result = mutableListOf<Waypoint>()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            result += Waypoint(
                id = o.getString("id"),
                name = o.getString("name"),
                lat = o.getDouble("lat"),
                lon = o.getDouble("lon"),
                mark = o.optString("mark", "●"),
                color = o.optString("color", "#FFAA00"),
                note = if (o.isNull("note")) null else o.getString("note"),
                archiveMark = if (o.isNull("archiveMark")) null else o.getString("archiveMark"),
                group = o.optString("group", "")
            )
        }
        return result
    }

    private fun serialized(items: List<Waypoint>): JSONArray {
        val arr = JSONArray()
        items.forEach { w ->
            arr.put(JSONObject().apply {
                put("id", w.id)
                put("name", w.name)
                put("lat", w.lat)
                put("lon", w.lon)
                put("mark", w.mark)
                put("color", w.color)
                put("note", w.note ?: JSONObject.NULL)
                put("archiveMark", w.archiveMark ?: JSONObject.NULL)
                put("group", w.group)
            })
        }
        return arr
    }
    fun loadLibrary(): MapLibrary = MapLibrary.from(prefs.getString("library", "{}") ?: "{}")
    fun saveLibrary(items: List<Waypoint>, library: MapLibrary) {
        check(prefs.edit().putString("items", serialized(items).toString()).putString("library", library.json().toString()).commit()) { "保存に失敗しました" }
    }
    fun saveAll(items: List<Waypoint>, synchronous: Boolean = false) {
        val edit = prefs.edit().putString("items", serialized(items).toString())
        if (synchronous) check(edit.commit()) { "保存に失敗しました" } else edit.apply()
    }

    fun getActiveId(): String? = prefs.getString("activeId", null)

    fun setActiveId(id: String?) {
        prefs.edit().apply {
            putString("activeId", id ?: "__none__")
        }.apply()
    }
}
