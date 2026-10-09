package com.goldenfalcons.sailinggps

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ReleaseUpdateParserTest {
    private val repo = "GoldenFalcons18/gps-pwa"
    private fun release() = JSONObject("""{
        "tag_name":"android-v1.2.0", "prerelease":false, "draft":false, "body":"Changes",
        "assets":[
            {"name":"android-update.json","browser_download_url":"https://github.com/$repo/releases/download/android-v1.2.0/android-update.json"},
            {"name":"SailingGpsLogger-1.2.0.apk","size":1000,"browser_download_url":"https://github.com/$repo/releases/download/android-v1.2.0/SailingGpsLogger-1.2.0.apk"}
        ]} """)
    private fun metadata() = JSONObject().apply {
        put("schemaVersion", 1); put("packageName", "com.goldenfalcons.sailinggps")
        put("versionCode", 5); put("versionName", "1.2.0"); put("minSdk", 26)
        put("apkFile", "SailingGpsLogger-1.2.0.apk"); put("sha256", "a".repeat(64))
    }
    @Test fun newerCompatibleReleaseIsOffered() {
        assertEquals("1.2.0", ReleaseUpdateParser.parse(release(), metadata(), repo, 4, 34)?.versionName)
    }
    @Test fun sameAndOlderVersionsDoNotPrompt() {
        assertNull(ReleaseUpdateParser.parse(release(), metadata(), repo, 5, 34))
        assertNull(ReleaseUpdateParser.parse(release(), metadata(), repo, 6, 34))
    }
    @Test fun unsupportedAndroidDoesNotPrompt() {
        assertNull(ReleaseUpdateParser.parse(release(), metadata().put("minSdk", 35), repo, 4, 34))
    }
    @Test fun prereleaseAndDraftDoNotPrompt() {
        assertNull(ReleaseUpdateParser.parse(release().put("prerelease", true), metadata(), repo, 4, 34))
        assertNull(ReleaseUpdateParser.parse(release().put("draft", true), metadata(), repo, 4, 34))
    }
    @Test fun missingApkDoesNotPrompt() {
        val release = release(); release.getJSONArray("assets").remove(1)
        assertNull(ReleaseUpdateParser.parse(release, metadata(), repo, 4, 34))
    }
    @Test fun mismatchedPackageAndTagDoNotPrompt() {
        assertNull(ReleaseUpdateParser.parse(release(), metadata().put("packageName", "other.app"), repo, 4, 34))
        assertNull(ReleaseUpdateParser.parse(release().put("tag_name", "ios-v1.2.0"), metadata(), repo, 4, 34))
    }
    @Test fun foreignAndInsecureAssetUrlsAreRejected() {
        listOf("http://github.com/$repo/releases/download/a/app.apk",
            "https://github.com/attacker/repo/releases/download/a/app.apk",
            "https://github.com.evil.example/$repo/releases/download/a/app.apk",
            "https://github.com/$repo/releases/download/../app.apk").forEach {
            assertFalse(ReleaseUpdateParser.assetUrl(it, repo))
        }
    }
    @Test fun incompleteMetadataDoesNotPrompt() {
        assertNull(ReleaseUpdateParser.parse(release(), metadata().put("sha256", ""), repo, 4, 34))
    }
}
