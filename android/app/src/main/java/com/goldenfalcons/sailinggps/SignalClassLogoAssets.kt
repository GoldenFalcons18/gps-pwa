package com.goldenfalcons.sailinggps

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import org.json.JSONObject

/** Loads offline class emblems bundled as Commons-derived PNGs. */
object SignalClassLogoAssets {
    private var encodedImages: JSONObject? = null
    private val bitmapCache = mutableMapOf<String, Bitmap>()

    @Synchronized
    fun bitmap(context: Context, className: String): Bitmap? {
        val key = assetKey(className)
        bitmapCache[key]?.let { return it }
        val encoded = findEncodedImage(imageMap(context), key) ?: return null
        val bytes = runCatching { Base64.decode(encoded, Base64.DEFAULT) }.getOrNull() ?: return null
        val image = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
        bitmapCache[key] = image
        return image
    }

    private fun imageMap(context: Context): JSONObject {
        encodedImages?.let { return it }
        val loaded = JSONObject()
        val assets = listOf(
            "signal-class-logos.json",
            "signal-class-logos-extra-1.json",
            "signal-class-logos-extra-2.json",
            "signal-class-logos-extra-3.json",
            "signal-class-logos-extra-4.json",
            "signal-class-logos-extra-5.json",
            "signal-class-logos-extra-6.json",
            "signal-class-logos-extra-7.json"
        )
        assets.forEach { asset ->
            val source = sequenceOf(asset, "Shared/$asset")
                .mapNotNull { path ->
                    runCatching {
                        context.assets.open(path).bufferedReader().use { JSONObject(it.readText()) }
                    }.getOrNull()
                }
                .firstOrNull()
            source?.let {
                val keys = it.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    loaded.put(key, it.optString(key))
                }
            }
        }
        encodedImages = loaded
        return loaded
    }

    private fun findEncodedImage(images: JSONObject, key: String): String? {
        images.optString(key).takeIf { it.isNotBlank() }?.let { return it }
        val normalized = normalizeKey(key)
        val keys = images.keys()
        while (keys.hasNext()) {
            val candidate = keys.next()
            if (normalizeKey(candidate) == normalized) {
                return images.optString(candidate).takeIf { it.isNotBlank() }
            }
        }
        return null
    }

    private fun normalizeKey(value: String): String =
        value.lowercase().filter { it.isLetterOrDigit() }

    private fun assetKey(className: String): String {
        val value = className.removePrefix("class-").trim()
        return when (value.lowercase()) {
            "a-cat" -> "A-Cat"
            "29er" -> "29er"
            "420" -> "420"
            "470" -> "470"
            "49er" -> "49er"
            "finn" -> "Finn"
            "optimist" -> "Optimist"
            "tornado" -> "Tornado"
            "star" -> "Star_red"
            "laser" -> "Sailing_laser"
            "snipe" -> "Sailing_snipe"
            else -> value
        }
    }
}
