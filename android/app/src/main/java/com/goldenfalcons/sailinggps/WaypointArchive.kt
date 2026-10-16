package com.goldenfalcons.sailinggps

import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

object WaypointArchive {
    const val MAX_BYTES = 8 * 1024 * 1024
    const val MAX_COUNT = 10000
    private val symbols = mapOf("marine.lighthouse" to "灯台", "marine.net" to "網", "exclamationmark.triangle.fill" to "危険", "marine.buoy" to "ブイ", "mountain.2.fill" to "岩礁", "marine.anchor" to "錨", "sailboat.fill" to "⛵", "ferry.fill" to "🚢", "flag.fill" to "⚑", "star.fill" to "★", "circle.fill" to "●", "mappin" to "📍", "triangle.fill" to "▲", "square.fill" to "■", "diamond.fill" to "◆", "house.fill" to "🏠", "sun.max.fill" to "☀", "moon.fill" to "🌙", "fish.fill" to "🐟", "binoculars.fill" to "🔭", "light.beacon.max.fill" to "灯火")
    fun displayMark(mark: String): String = if (mark.startsWith("text:")) mark.removePrefix("text:") else symbols[mark.removePrefix("symbol:")] ?: "⚑"
    fun archiveMark(w: Waypoint): String = w.archiveMark?.takeIf { displayMark(it) == w.mark } ?: symbols.entries.firstOrNull { it.value == w.mark }?.let { "symbol:${it.key}" } ?: "text:${w.mark}"
    private fun validate(w: Waypoint) {
        require(w.lat.isFinite() && w.lon.isFinite() && w.lat in -90.0..90.0 && w.lon in -180.0..180.0) { "座標が無効です" }
        require(w.name.isNotBlank() && w.name.toByteArray().size <= 1000 && archiveMark(w).toByteArray().size <= 256 && (w.note ?: "").toByteArray().size <= 100000) { "地点の内容が無効です" }
        require(Regex("#[0-9A-Fa-f]{6}").matches(w.color)) { "色が無効です" }
        require(UUID.fromString(w.id).toString().equals(w.id, true)) { "地点IDが無効です" }
    }
    fun encode(items: List<Waypoint>): ByteArray {
        require(items.size <= MAX_COUNT) { "地点数の上限を超えています" }
        val array = JSONArray()
        items.forEach { w -> validate(w); array.put(JSONObject().apply {
            put("id", w.id); put("name", w.name); put("latitude", w.lat); put("longitude", w.lon)
            put("group", w.group); put("mark", archiveMark(w)); put("color", w.color.uppercase(java.util.Locale.ROOT)); put("note", w.note ?: JSONObject.NULL)
        }) }
        return JSONObject().put("format", "sailing-gps-waypoints").put("version", 1).put("waypoints", array).toString(2).toByteArray(Charsets.UTF_8).also { require(it.size <= MAX_BYTES) { "8MBを超えています" } }
    }
    fun decode(data: ByteArray): List<Waypoint> {
        require(data.size <= MAX_BYTES) { "8MBを超えています" }
        val root = JSONObject(data.toString(Charsets.UTF_8))
        require(root.getString("format") == "sailing-gps-waypoints" && root.get("version") is Number && root.getDouble("version") == 1.0) { "対応していない形式です" }
        val array = root.getJSONArray("waypoints"); require(array.length() <= MAX_COUNT) { "地点数の上限を超えています" }
        return (0 until array.length()).map { i ->
            val o = array.getJSONObject(i)
            for (key in listOf("id", "name", "mark", "color")) require(o.get(key) is String) { "地点の内容が無効です" }
            require(o.get("latitude") is Number && o.get("longitude") is Number) { "座標が無効です" }
            require(o.isNull("note") || o.get("note") is String) { "注記が無効です" }
            val mark = o.getString("mark"); require(mark.startsWith("text:") || mark.startsWith("symbol:")) { "マークが無効です" }
            Waypoint(id = UUID.fromString(o.getString("id")).toString(), name = o.getString("name"), lat = o.getDouble("latitude"), lon = o.getDouble("longitude"), mark = displayMark(mark), color = o.getString("color").uppercase(java.util.Locale.ROOT), note = if (o.isNull("note")) null else o.getString("note"), archiveMark = mark, group = o.optString("group", "")).also(::validate)
        }
    }
    data class Result(val items: List<Waypoint>, val added: Int, val skipped: Int)
    fun merge(existing: List<Waypoint>, incoming: List<Waypoint>): Result {
        incoming.forEach(::validate)
        val result = existing.toMutableList(); var skipped = 0; var added = 0
        for (item in incoming) {
            if (result.any { it.group == item.group && it.name == item.name && it.lat == item.lat && it.lon == item.lon && archiveMark(it) == archiveMark(item) && it.color.equals(item.color, true) && (it.note ?: "") == (item.note ?: "") }) { skipped++; continue }
            result += if (result.any { it.id == item.id }) item.copy(id = UUID.randomUUID().toString()) else item
            added++
        }
        require(result.size <= MAX_COUNT) { "地点数の上限を超えています" }
        return Result(result, added, skipped)
    }
}
