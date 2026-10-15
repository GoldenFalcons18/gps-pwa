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
    val color: String = "#FFAA00"
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
                color = o.optString("color", "#FFAA00")
            )
        }
        return result
    }

    fun saveAll(items: List<Waypoint>) {
        val arr = JSONArray()
        items.forEach { w ->
            arr.put(JSONObject().apply {
                put("id", w.id)
                put("name", w.name)
                put("lat", w.lat)
                put("lon", w.lon)
                put("mark", w.mark)
                put("color", w.color)
            })
        }
        prefs.edit().putString("items", arr.toString()).apply()
    }

    fun getActiveId(): String? = prefs.getString("activeId", null)

    fun setActiveId(id: String?) {
        prefs.edit().apply {
            putString("activeId", id ?: "__none__")
        }.apply()
    }
}
