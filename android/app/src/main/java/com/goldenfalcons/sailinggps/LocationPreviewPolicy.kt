package com.goldenfalcons.sailinggps

/** Fresh GPS fixes update speed; a recent cached fix may keep the map marker visible while GPS reacquires. */
object LocationPreviewPolicy {
    const val FRESH_FIX_MAX_AGE_MS = 30_000L
    const val CACHED_DISPLAY_MAX_AGE_MS = 5 * 60_000L
    const val PERSISTED_DISPLAY_MAX_AGE_MS = 60 * 60_000L

    fun isUsableAge(ageMs: Long, allowCachedDisplay: Boolean = false): Boolean {
        if (ageMs < 0L) return false
        val maxAge = if (allowCachedDisplay) CACHED_DISPLAY_MAX_AGE_MS else FRESH_FIX_MAX_AGE_MS
        return ageMs <= maxAge
    }
}
