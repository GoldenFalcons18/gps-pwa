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
    private var encodedInternationalFlags: JSONObject? = null
    private val internationalBitmapCache = mutableMapOf<String, Bitmap>()

    fun availableClassNames(context: Context): List<String> {
        val keys = imageMap(context).keys()
        val names = mutableListOf("420")
        while (keys.hasNext()) names += keys.next()
        return names.distinct().sortedBy { it.lowercase() }
    }

    @Synchronized
    fun bitmap(context: Context, className: String): Bitmap? {
        val key = assetKey(className)
        bitmapCache[key]?.let { return it }
        if (key == "420") {
            val logo = runCatching {
                val bytes = Base64.decode("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", Base64.DEFAULT)
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            }.getOrNull()
            if (logo != null) {
                bitmapCache[key] = logo
                return logo
            }
        }
        val encoded = findEncodedImage(imageMap(context), key) ?: return null
        val bytes = runCatching { Base64.decode(encoded, Base64.DEFAULT) }.getOrNull() ?: return null
        val image = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
        bitmapCache[key] = image
        return image
    }

    @Synchronized
    fun internationalBitmap(context: Context, flagName: String): Bitmap? {
        val key = normalizeKey(flagName.removePrefix("intl:"))
        internationalBitmapCache[key]?.let { return it }
        val map = encodedInternationalFlags ?: run {
            val loaded = runCatching {
                context.assets.open("signal-international-flags.json").bufferedReader().use { JSONObject(it.readText()) }
            }.getOrElse {
                runCatching {
                    context.assets.open("Shared/signal-international-flags.json").bufferedReader().use { JSONObject(it.readText()) }
                }.getOrNull()
            } ?: return null
            encodedInternationalFlags = loaded
            loaded
        }
        val encoded = map.optString(flagName.removePrefix("intl:")).takeIf { it.isNotBlank() }
            ?: run {
                val keys = map.keys()
                var value: String? = null
                while (keys.hasNext()) {
                    val candidate = keys.next()
                    if (normalizeKey(candidate) == key) { value = map.optString(candidate); break }
                }
                value
            } ?: return null
        val bytes = runCatching { Base64.decode(encoded, Base64.DEFAULT) }.getOrNull() ?: return null
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
        internationalBitmapCache[key] = bitmap
        return bitmap
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

