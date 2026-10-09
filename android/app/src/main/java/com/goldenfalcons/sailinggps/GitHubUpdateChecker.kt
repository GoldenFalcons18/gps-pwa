package com.goldenfalcons.sailinggps

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import org.json.JSONObject
import org.json.JSONArray
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class GitHubUpdateChecker(private val activity: AppCompatActivity, private val log: (String) -> Unit) {
    private val preferences = activity.getSharedPreferences("updates", 0)
    private val worker = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    private var dialog: AlertDialog? = null
    @Volatile private var closed = false

    fun check(manual: Boolean = false) {
        val now = System.currentTimeMillis()
        val previous = preferences.getLong("lastAttempt", 0L)
        if (!manual && now >= previous && now - previous < 24 * 60 * 60 * 1000L) return
        if (closed || !busy.compareAndSet(false, true)) return
        preferences.edit().putLong("lastAttempt", now).apply()
        log("Update check started / manual=$manual / installed=${BuildConfig.VERSION_CODE}")
        worker.execute {
            val result = runCatching {
                val repository = BuildConfig.UPDATE_REPOSITORY
                require(Regex("[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+").matches(repository))
                val response = get("https://api.github.com/repos/$repository/releases?per_page=100")
                if (response == null) null else {
                    val releases = JSONArray(response)
                    var newest: AppUpdate? = null
                    for (index in 0 until releases.length()) {
                        val release = releases.getJSONObject(index)
                        if (!release.optString("tag_name").startsWith("android-v")) continue
                        val metadataUrl = ReleaseUpdateParser.metadataUrl(release, repository) ?: continue
                        val metadata = JSONObject(get(metadataUrl) ?: error("更新情報が見つかりません"))
                        val update = ReleaseUpdateParser.parse(release, metadata, repository, BuildConfig.VERSION_CODE, Build.VERSION.SDK_INT)
                        if (update != null && update.versionCode > (newest?.versionCode ?: -1)) newest = update
                    }
                    newest
                }
            }
            activity.runOnUiThread {
                busy.set(false)
                if (closed || activity.isFinishing || activity.isDestroyed) return@runOnUiThread
                result.fold(onSuccess = { update ->
                    if (update == null) {
                        log("Update check finished / no installable newer release")
                        if (manual) message("更新確認", "現在のバージョンは ${BuildConfig.VERSION_NAME} です。対応する新しい公開版は見つかりませんでした。")
                    } else if (manual || preferences.getInt("skippedCode", -1) != update.versionCode) {
                        log("Update available / ${update.versionName}")
                        dialog?.dismiss()
                        dialog = AlertDialog.Builder(activity)
                            .setTitle("新しいバージョン ${update.versionName} があります")
                            .setMessage("現在：${BuildConfig.VERSION_NAME}\n記録中の場合は停止・GPX保存後に更新してください。\n\n${update.notes}")
                            .setPositiveButton("ダウンロード") { _, _ ->
                                try {
                                    activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(update.downloadUrl)))
                                } catch (_: ActivityNotFoundException) { message("更新", "リンクを開けるブラウザがありません。") }
                            }
                            .setNegativeButton("あとで", null)
                            .setNeutralButton("この版をスキップ") { _, _ -> preferences.edit().putInt("skippedCode", update.versionCode).apply() }
                            .show()
                    } else log("Update skipped / ${update.versionName}")
                }, onFailure = { error ->
                    log("Update check failed / ${error.javaClass.simpleName}: ${error.message}")
                    if (manual) message("更新を確認できませんでした", "通信状態を確認し、あとで再度お試しください。GPS記録は引き続き使用できます。")
                })
            }
        }
    }

    private fun get(url: String): String? {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 8000
        connection.readTimeout = 12000
        connection.setRequestProperty("User-Agent", "SailingGpsLogger/${BuildConfig.VERSION_NAME}")
        connection.setRequestProperty("Accept", "application/vnd.github+json")
        try {
            val code = connection.responseCode
            if (code == 404) return null
            if (code != 200) error("HTTP $code")
            connection.inputStream.use { stream ->
                val bytes = stream.readBytesBounded(1024 * 1024)
                return bytes.toString(Charsets.UTF_8)
            }
        } finally { connection.disconnect() }
    }

    private fun java.io.InputStream.readBytesBounded(limit: Int): ByteArray {
        val output = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val count = read(buffer)
            if (count < 0) break
            require(output.size() + count <= limit) { "Update response too large" }
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }

    private fun message(title: String, text: String) {
        dialog?.dismiss()
        dialog = AlertDialog.Builder(activity).setTitle(title).setMessage(text).setPositiveButton("OK", null).show()
    }

    fun close() {
        closed = true
        dialog?.dismiss()
        worker.shutdownNow()
    }
}
