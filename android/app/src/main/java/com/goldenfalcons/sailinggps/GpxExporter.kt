package com.goldenfalcons.sailinggps

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

object GpxExporter {
    private fun esc(s: String): String = s
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\"", "&quot;")
        .replace("'", "&apos;")

    fun export(context: Context, waypoints: List<Waypoint>): File {
        val source = GpsLoggingService.trackFile(context)
        val exportDir = File(context.filesDir, "exports").apply { mkdirs() }
        val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val out = File(exportDir, "sailing-track-$stamp.gpx")

        val iso = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }

        out.bufferedWriter().use { w ->
            w.appendLine("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
            w.appendLine("<gpx version=\"1.1\" creator=\"Sailing GPS Logger Android\"")
            w.appendLine(" xmlns=\"http://www.topografix.com/GPX/1/1\"")
            w.appendLine(" xmlns:gpxtpx=\"http://www.garmin.com/xmlschemas/TrackPointExtension/v1\">")

            waypoints.forEach { wp ->
                w.appendLine("  <wpt lat=\"${wp.lat}\" lon=\"${wp.lon}\"><name>${esc(wp.name)}</name></wpt>")
            }

            w.appendLine("  <trk><name>Sailing Track $stamp</name><trkseg>")
            if (source.exists()) {
                source.forEachLine { line ->
                    val p = line.split(',')
                    if (p.size >= 8) {
                        val ts = p[0].toLongOrNull() ?: return@forEachLine
                        val lat = p[1].toDoubleOrNull() ?: return@forEachLine
                        val lon = p[2].toDoubleOrNull() ?: return@forEachLine
                        val altitude = p[4].toDoubleOrNull()
                        val speed = p[6].toDoubleOrNull()

                        w.appendLine("    <trkpt lat=\"$lat\" lon=\"$lon\">")
                        altitude?.let { w.appendLine("      <ele>$it</ele>") }
                        speed?.let { w.appendLine("      <speed>$it</speed>") }
                        w.appendLine("      <time>${iso.format(Date(ts))}</time>")
                        speed?.let {
                            w.appendLine("      <extensions><gpxtpx:TrackPointExtension><gpxtpx:speed>$it</gpxtpx:speed></gpxtpx:TrackPointExtension></extensions>")
                        }
                        w.appendLine("    </trkpt>")
                    }
                }
            }
            w.appendLine("  </trkseg></trk>")
            w.appendLine("</gpx>")
        }
        return out
    }
}
