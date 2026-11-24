package com.goldenfalcons.sailinggps

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.time.Instant
import java.util.Locale

data class MarkLogRow(
    val time: String,
    val markALatitude: Double,
    val markALongitude: Double,
    val markBLatitude: Double,
    val markBLongitude: Double
)

data class WindLogRow(
    val time: String,
    val latitude: Double,
    val longitude: Double,
    val windFromDegrees: Double,
    val windSpeedKnots: Double
)

class WindMarkLogStore(context: Context) {
    private val directory = File(context.filesDir, "wind-mark-logs").apply { mkdirs() }

    fun marks(): List<MarkLogRow> = read("mark-log.json") { o ->
        MarkLogRow(o.getString("time"), o.getDouble("markALatitude"), o.getDouble("markALongitude"),
            o.getDouble("markBLatitude"), o.getDouble("markBLongitude"))
    }

    fun winds(): List<WindLogRow> = read("wind-log.json") { o ->
        WindLogRow(o.getString("time"), o.getDouble("latitude"), o.getDouble("longitude"),
            o.getDouble("windFromDegrees"), o.getDouble("windSpeedKnots"))
    }

    fun add(row: MarkLogRow) = append("mark-log.json", JSONObject().put("time", row.time)
        .put("markALatitude", row.markALatitude).put("markALongitude", row.markALongitude)
        .put("markBLatitude", row.markBLatitude).put("markBLongitude", row.markBLongitude))

    fun add(row: WindLogRow) = append("wind-log.json", JSONObject().put("time", row.time)
        .put("latitude", row.latitude).put("longitude", row.longitude)
        .put("windFromDegrees", row.windFromDegrees).put("windSpeedKnots", row.windSpeedKnots))

    fun markCsv(): String = buildString {
        appendLine("time,mark_a_latitude,mark_a_longitude,mark_b_latitude,mark_b_longitude")
        marks().forEach { appendLine("${it.time},${decimal(it.markALatitude)},${decimal(it.markALongitude)},${decimal(it.markBLatitude)},${decimal(it.markBLongitude)}") }
    }

    fun windCsv(): String = buildString {
        appendLine("time,latitude,longitude,wind_from_deg,wind_speed_kn")
        winds().forEach { appendLine("${it.time},${decimal(it.latitude)},${decimal(it.longitude)},${decimal(it.windFromDegrees)},${decimal(it.windSpeedKnots)}") }
    }

    private fun decimal(value: Double) = String.format(Locale.US, "%.6f", value)
    private fun <T> read(name: String, decode: (JSONObject) -> T): List<T> {
        val array = runCatching { JSONArray(File(directory, name).readText()) }.getOrNull() ?: return emptyList()
        return (0 until array.length()).mapNotNull { i -> runCatching { decode(array.getJSONObject(i)) }.getOrNull() }
    }
    private fun append(name: String, value: JSONObject) {
        val file = File(directory, name)
        val array = runCatching { JSONArray(file.readText()) }.getOrElse { JSONArray() }
        array.put(value)
        file.writeText(array.toString())
    }
    companion object {
        fun timestamp(): String = Instant.now().toString()
    }
}
