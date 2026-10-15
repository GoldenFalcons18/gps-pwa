package com.goldenfalcons.sailinggps

import org.json.JSONObject
import java.net.URI

data class AppUpdate(val versionCode: Int, val versionName: String, val downloadUrl: String, val notes: String)

/** Accept only the configured repository's stable Android release and exact APK asset. */
object ReleaseUpdateParser {
    fun assetUrl(url: String, repository: String): Boolean = runCatching {
        val uri = URI(url)
        uri.scheme == "https" && uri.host == "github.com" && uri.userInfo == null &&
            uri.port == -1 && uri.rawPath.startsWith("/$repository/releases/download/") &&
            !uri.rawPath.contains("%", ignoreCase = true) && !uri.rawPath.contains("..") &&
            uri.query == null && uri.fragment == null
    }.getOrDefault(false)

    fun metadataUrl(release: JSONObject, repository: String): String? {
        if (release.optBoolean("draft") || release.optBoolean("prerelease")) return null
        val assets = release.optJSONArray("assets") ?: return null
        for (index in 0 until assets.length()) {
            val asset = assets.getJSONObject(index)
            val url = asset.optString("browser_download_url")
            if (asset.optString("name") == "android-update.json" && assetUrl(url, repository)) return url
        }
        return null
    }

    fun parse(release: JSONObject, metadata: JSONObject, repository: String, installedCode: Int, sdk: Int): AppUpdate? {
        if (metadataUrl(release, repository) == null) return null
        if (metadata.optInt("schemaVersion") != 1 ||
            metadata.optString("packageName") != "com.goldenfalcons.sailinggps") return null
        val code = metadata.optInt("versionCode", -1)
        val version = metadata.optString("versionName")
        val apkName = metadata.optString("apkFile")
        val sha = metadata.optString("sha256")
        if (code <= installedCode || metadata.optInt("minSdk", Int.MAX_VALUE) > sdk) return null
        if (!Regex("[0-9]+\\.[0-9]+\\.[0-9]+").matches(version) ||
            release.optString("tag_name") != "android-v$version" ||
            !Regex("[A-Za-z0-9._-]+\\.apk").matches(apkName) ||
            !Regex("[a-fA-F0-9]{64}").matches(sha)) return null
        val assets = release.getJSONArray("assets")
        for (index in 0 until assets.length()) {
            val asset = assets.getJSONObject(index)
            val url = asset.optString("browser_download_url")
            if (asset.optString("name") == apkName && asset.optLong("size") > 0 && assetUrl(url, repository)) {
                return AppUpdate(code, version, url, release.optString("body").take(2000))
            }
        }
        return null
    }
}
