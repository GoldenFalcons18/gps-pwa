package com.goldenfalcons.sailinggps

data class SignalEvent(
    val id: Int,
    val secondsAfterStart: Int,
    val title: String,
    val color: Int,
    val raised: Boolean,
    val flag: String,
    val hornPulses: List<Int>
)
data class SignalFlagProfile(val id: String, val name: String, val events: List<SignalEvent>, val baseDurationMinutes: Int = 5)
data class SignalFlagState(val id: String, val color: Int, val raised: Boolean, val whiteSquare: Boolean)

object SignalSequence {
    private fun e(id: Int, seconds: Int, title: String, flag: String, color: Int, raised: Boolean, vararg pulses: Int) =
        SignalEvent(id, seconds, title, color, raised, flag, pulses.toList())

    // The video sequence is an elapsed-time program: 0, 5, 6, 9, 10, and 20 minutes.
    val profiles = listOf(
        SignalFlagProfile("video-20", "動画の信号（20分）", listOf(
            e(0, 0, "橙旗を掲揚", "橙", android.graphics.Color.rgb(245, 138, 0), true, 0),
            e(1, 300, "緑旗を掲揚", "緑", android.graphics.Color.rgb(0, 210, 40), true, 0),
            e(2, 360, "青旗を掲揚", "青", android.graphics.Color.rgb(23, 105, 255), true, 0),
            e(3, 540, "青旗を降下", "青", android.graphics.Color.rgb(23, 105, 255), false, 1),
            e(4, 600, "緑旗を降下", "緑", android.graphics.Color.rgb(0, 210, 40), false, 0),
            e(5, 1200, "橙旗を降下", "橙", android.graphics.Color.rgb(245, 138, 0), false)
        ), baseDurationMinutes = 20),
        SignalFlagProfile("class-p", "カスタム（クラス旗＋P旗）", listOf(
            e(0, 0, "クラス旗を掲揚", "級", android.graphics.Color.rgb(245, 138, 0), true, 0),
            e(1, 60, "P旗を掲揚", "P", android.graphics.Color.rgb(23, 105, 255), true, 0),
            e(2, 240, "P旗を降下", "P", android.graphics.Color.rgb(23, 105, 255), false, 1),
            e(3, 300, "クラス旗を降下", "級", android.graphics.Color.rgb(245, 138, 0), false, 0)
        )),
        SignalFlagProfile("class-i", "カスタム（クラス旗＋I旗）", listOf(
            e(0, 0, "クラス旗を掲揚", "級", android.graphics.Color.rgb(245, 138, 0), true, 0),
            e(1, 60, "I旗を掲揚", "I", android.graphics.Color.rgb(245, 211, 40), true, 0),
            e(2, 240, "I旗を降下", "I", android.graphics.Color.rgb(245, 211, 40), false, 1),
            e(3, 300, "クラス旗を降下", "級", android.graphics.Color.rgb(245, 138, 0), false, 0)
        )),
        SignalFlagProfile("class-u", "カスタム（クラス旗＋U旗）", listOf(
            e(0, 0, "クラス旗を掲揚", "級", android.graphics.Color.rgb(245, 138, 0), true, 0),
            e(1, 60, "U旗を掲揚", "U", android.graphics.Color.rgb(215, 44, 50), true, 0),
            e(2, 240, "U旗を降下", "U", android.graphics.Color.rgb(215, 44, 50), false, 1),
            e(3, 300, "クラス旗を降下", "級", android.graphics.Color.rgb(245, 138, 0), false, 0)
        )),
        SignalFlagProfile("class-black", "カスタム（クラス旗＋黒旗）", listOf(
            e(0, 0, "クラス旗を掲揚", "級", android.graphics.Color.rgb(245, 138, 0), true, 0),
            e(1, 60, "黒旗を掲揚", "黒", android.graphics.Color.rgb(32, 32, 32), true, 0),
            e(2, 240, "黒旗を降下", "黒", android.graphics.Color.rgb(32, 32, 32), false, 1),
            e(3, 300, "クラス旗を降下", "級", android.graphics.Color.rgb(245, 138, 0), false, 0)
        )),
        SignalFlagProfile("class-p-i", "カスタム（クラス旗＋P旗＋I旗）", listOf(
            e(0, 0, "クラス旗を掲揚", "級", android.graphics.Color.rgb(245, 138, 0), true, 0),
            e(1, 60, "P旗を掲揚", "P", android.graphics.Color.rgb(23, 105, 255), true, 0),
            e(2, 120, "I旗を掲揚", "I", android.graphics.Color.rgb(245, 211, 40), true, 0),
            e(3, 180, "I旗を降下", "I", android.graphics.Color.rgb(245, 211, 40), false, 0),
            e(4, 240, "P旗を降下", "P", android.graphics.Color.rgb(23, 105, 255), false, 1),
            e(5, 300, "クラス旗を降下", "級", android.graphics.Color.rgb(245, 138, 0), false, 0)
        )),
        SignalFlagProfile("appendix-v", "Appendix V参考（音声のみ）", listOf(
            e(0, 0, "スタート・短音", "♪", android.graphics.Color.DKGRAY, true, 0),
            e(1, 4, "4秒・短音", "♪", android.graphics.Color.DKGRAY, true, 0),
            e(2, 5, "5秒・短音", "♪", android.graphics.Color.DKGRAY, true, 0),
            e(3, 10, "10秒・短音", "♪", android.graphics.Color.DKGRAY, true, 0),
            e(4, 20, "20秒・短音×2", "♪", android.graphics.Color.DKGRAY, true, 0, 0),
            e(5, 30, "30秒・短音×3", "♪", android.graphics.Color.DKGRAY, true, 0, 0, 0),
            e(6, 60, "1分・長音", "♪", android.graphics.Color.DKGRAY, true, 1),
            e(7, 90, "1分30秒・長音＋短音×3", "♪", android.graphics.Color.DKGRAY, true, 1, 0, 0, 0),
            e(8, 120, "2分・長音×2", "♪", android.graphics.Color.DKGRAY, true, 1, 1),
            e(9, 180, "3分・長音×3", "♪", android.graphics.Color.DKGRAY, true, 1, 1, 1)
        ), baseDurationMinutes = 3)
    )

    fun events(durationMinutes: Int = 20, profileIndex: Int = 0): List<SignalEvent> {
        val profile = profiles.getOrElse(profileIndex) { profiles[0] }
        val scale = durationMinutes.coerceAtLeast(1).toDouble() / profile.baseDurationMinutes.coerceAtLeast(1)
        return profile.events.map { it.copy(secondsAfterStart = (it.secondsAfterStart * scale).toInt()) }
    }

    /** The most recent elapsed-time signal, or -1 before the first action. */
    fun nextIndex(elapsedSeconds: Double, durationMinutes: Int = 20, profileIndex: Int = 0): Int =
        SignalTiming.activeEventIndex(elapsedSeconds, events(durationMinutes, profileIndex).map { it.secondsAfterStart })

    fun untilNext(elapsedSeconds: Double, index: Int, durationMinutes: Int = 20, profileIndex: Int = 0): Int {
        val list = events(durationMinutes, profileIndex)
        if (index !in list.indices) return 0
        return kotlin.math.ceil(list[index].secondsAfterStart - elapsedSeconds).toInt()
    }

    /** Flag state at a point in the elapsed sequence, with one mast per distinct flag. */
    fun flagsAt(elapsedSeconds: Double, durationMinutes: Int = 20, profileIndex: Int = 0): List<SignalFlagState> {
        val list = events(durationMinutes, profileIndex)
        return list.groupBy { it.flag }.map { (flag, actions) ->
            val latest = actions.lastOrNull { it.secondsAfterStart <= elapsedSeconds }
            val exemplar = actions.first()
            SignalFlagState(flag, latest?.color ?: exemplar.color, latest?.raised ?: false, flag == "青" || flag == "P")
        }
    }
}
