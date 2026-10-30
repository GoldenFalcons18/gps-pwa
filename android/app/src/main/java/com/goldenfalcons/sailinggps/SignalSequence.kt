package com.goldenfalcons.sailinggps

data class SignalFlagMark(val id: String, val color: Int, val whiteSquare: Boolean = false) {
    val secondaryColor: Int get() = when (id) {
        "斜め" -> 0xFFD71920.toInt()
        "赤白チェック" -> 0xFFFFFFFF.toInt()
        else -> 0xFFFFFFFF.toInt()
    }
    val style: String get() = when (id) {
        "斜め" -> "diagonal"
        "赤白チェック" -> "checker"
        "級", "class-4" -> "classLogo"
        "青", "P" -> "blueSquare"
        "I" -> "circle"
        "第一代表" -> "firstSub"
        "AP" -> "apFlag"
        "X" -> "xFlag"
        else -> "solid"
    }
}
data class SignalEvent(
    val id: Int,
    val secondsAfterStart: Int,
    val title: String,
    val color: Int,
    val raised: Boolean,
    val flag: String,
    val hornPulses: List<Int>,
    val additionalFlags: List<SignalFlagMark> = emptyList()
) {
    val flagMarks: List<SignalFlagMark>
        get() = listOf(SignalFlagMark(flag, color, flag == "青" || flag == "P")) + additionalFlags
}
data class SignalFlagProfile(val id: String, val name: String, val events: List<SignalEvent>, val baseDurationMinutes: Int = 5)
data class SignalFlagState(
    val id: String,
    val color: Int,
    val raised: Boolean,
    val whiteSquare: Boolean,
    val style: String = when (id) {
        "級" -> "classLogo"
        "青", "P" -> "blueSquare"
        "I" -> "circle"
        "U", "N", "赤白チェック" -> "checker"
        "斜め", "O" -> "diagonal"
        "第一代表" -> "firstSub"
        "AP" -> "apFlag"
        "H" -> "hFlag"
        "L" -> "lFlag"
        "Z" -> "zFlag"
        "X" -> "xFlag"
        else -> if (id.startsWith("class-")) "classLogo" else "solid"
    },
    val secondaryColor: Int = when (id) {
        "斜め", "O" -> 0xFFD71920.toInt()
        "赤白チェック" -> 0xFFFFFFFF.toInt()
        else -> 0xFFFFFFFF.toInt()
    }
)

object SignalSequence {
    private fun e(id: Int, seconds: Int, title: String, flag: String, color: Int, raised: Boolean, vararg pulses: Int) =
        SignalEvent(id, seconds, title, color, raised, flag, pulses.toList())

    private fun eWithFlags(id: Int, seconds: Int, title: String, flag: String, color: Int, raised: Boolean, additional: List<SignalFlagMark>, vararg pulses: Int) =
        SignalEvent(id, seconds, title, color, raised, flag, pulses.toList(), additional)

    // Standard race sequence, measured from the orange flag raise at T-10 minutes.
    val profiles = listOf(
        SignalFlagProfile("standard-start", "帆走スタート（オレンジ旗から14分）", listOf(
            e(0, 0, "オレンジ旗を掲揚（予告信号の5分前）", "橙", 0xFFF58A00.toInt(), true, 0),
            e(1, 300, "クラス旗を掲揚（スタート5分前）", "級", 0xFF7A35A8.toInt(), true, 0),
            e(2, 360, "準備信号を掲揚（スタート4分前）", "P", 0xFF1769FF.toInt(), true, 0),
            e(3, 540, "準備信号を降下（スタート1分前）", "P", 0xFF1769FF.toInt(), false, 1),
            e(4, 600, "クラス旗を降下（スタート）", "級", 0xFF7A35A8.toInt(), false, 0),
            e(5, 840, "オレンジ旗を降下（スタート約4分後）", "橙", 0xFFF58A00.toInt(), false)
        ), baseDurationMinutes = 14),
        SignalFlagProfile("video-20", "動画の信号（20分）", listOf(
            e(0, 0, "橙旗を掲揚", "橙", 0xFFF58A00.toInt(), true, 0),
            e(1, 300, "緑旗を掲揚", "緑", 0xFF00D228.toInt(), true, 0),
            e(2, 360, "青旗を掲揚", "青", 0xFF1769FF.toInt(), true, 0),
            e(3, 540, "青旗を降下", "青", 0xFF1769FF.toInt(), false, 1),
            e(4, 600, "緑旗を降下", "緑", 0xFF00D228.toInt(), false, 0),
            e(5, 1200, "橙旗を降下", "橙", 0xFFF58A00.toInt(), false)
        ), baseDurationMinutes = 20),
        SignalFlagProfile("video-13", "動画の信号（13分）", listOf(
            e(0, 0, "橙旗を掲揚", "橙", 0xFFF58A00.toInt(), true, 0),
            eWithFlags(1, 240, "クラス旗・斜め旗を掲揚", "級", 0xFFFFFFFF.toInt(), true,
                listOf(SignalFlagMark("斜め", 0xFFE6D300.toInt())), 0),
            e(2, 300, "赤白チェック旗を掲揚", "赤白チェック", 0xFFE32636.toInt(), true, 0),
            e(3, 480, "赤白チェック旗を降下", "赤白チェック", 0xFFE32636.toInt(), false, 1),
            eWithFlags(4, 540, "クラス旗・斜め旗を降下", "級", 0xFFFFFFFF.toInt(), false,
                listOf(SignalFlagMark("斜め", 0xFFE6D300.toInt())), 0),
            e(5, 780, "橙旗を降下", "橙", 0xFFF58A00.toInt(), false)
        ), baseDurationMinutes = 13),
        SignalFlagProfile("class-p", "カスタム（クラス旗＋P旗）", listOf(
            e(0, 0, "クラス旗を掲揚", "級", 0xFFF58A00.toInt(), true, 0),
            e(1, 60, "P旗を掲揚", "P", 0xFF1769FF.toInt(), true, 0),
            e(2, 240, "P旗を降下", "P", 0xFF1769FF.toInt(), false, 1),
            e(3, 300, "クラス旗を降下", "級", 0xFFF58A00.toInt(), false, 0)
        )),
        SignalFlagProfile("class-i", "カスタム（クラス旗＋I旗）", listOf(
            e(0, 0, "クラス旗を掲揚", "級", 0xFFF58A00.toInt(), true, 0),
            e(1, 60, "I旗を掲揚", "I", 0xFFF5D328.toInt(), true, 0),
            e(2, 240, "I旗を降下", "I", 0xFFF5D328.toInt(), false, 1),
            e(3, 300, "クラス旗を降下", "級", 0xFFF58A00.toInt(), false, 0)
        )),
        SignalFlagProfile("class-u", "カスタム（クラス旗＋U旗）", listOf(
            e(0, 0, "クラス旗を掲揚", "級", 0xFFF58A00.toInt(), true, 0),
            e(1, 60, "U旗を掲揚", "U", 0xFFD72C32.toInt(), true, 0),
            e(2, 240, "U旗を降下", "U", 0xFFD72C32.toInt(), false, 1),
            e(3, 300, "クラス旗を降下", "級", 0xFFF58A00.toInt(), false, 0)
        )),
        SignalFlagProfile("class-black", "カスタム（クラス旗＋黒旗）", listOf(
            e(0, 0, "クラス旗を掲揚", "級", 0xFFF58A00.toInt(), true, 0),
            e(1, 60, "黒旗を掲揚", "黒", 0xFF202020.toInt(), true, 0),
            e(2, 240, "黒旗を降下", "黒", 0xFF202020.toInt(), false, 1),
            e(3, 300, "クラス旗を降下", "級", 0xFFF58A00.toInt(), false, 0)
        )),
        SignalFlagProfile("class-p-i", "カスタム（クラス旗＋P旗＋I旗）", listOf(
            e(0, 0, "クラス旗を掲揚", "級", 0xFFF58A00.toInt(), true, 0),
            e(1, 60, "P旗を掲揚", "P", 0xFF1769FF.toInt(), true, 0),
            e(2, 120, "I旗を掲揚", "I", 0xFFF5D328.toInt(), true, 0),
            e(3, 180, "I旗を降下", "I", 0xFFF5D328.toInt(), false, 0),
            e(4, 240, "P旗を降下", "P", 0xFF1769FF.toInt(), false, 1),
            e(5, 300, "クラス旗を降下", "級", 0xFFF58A00.toInt(), false, 0)
        )),
        SignalFlagProfile("appendix-v", "Appendix V参考（音声のみ）", listOf(
            e(0, 0, "スタート・短音", "♪", 0xFF444444.toInt(), true, 0),
            e(1, 4, "4秒・短音", "♪", 0xFF444444.toInt(), true, 0),
            e(2, 5, "5秒・短音", "♪", 0xFF444444.toInt(), true, 0),
            e(3, 10, "10秒・短音", "♪", 0xFF444444.toInt(), true, 0),
            e(4, 20, "20秒・短音×2", "♪", 0xFF444444.toInt(), true, 0, 0),
            e(5, 30, "30秒・短音×3", "♪", 0xFF444444.toInt(), true, 0, 0, 0),
            e(6, 60, "1分・長音", "♪", 0xFF444444.toInt(), true, 1),
            e(7, 90, "1分30秒・長音＋短音×3", "♪", 0xFF444444.toInt(), true, 1, 0, 0, 0),
            e(8, 120, "2分・長音×2", "♪", 0xFF444444.toInt(), true, 1, 1),
            e(9, 180, "3分・長音×3", "♪", 0xFF444444.toInt(), true, 1, 1, 1)
        ), baseDurationMinutes = 3)
    )

    val individualRecallRaise = e(-1, 0, "X旗を掲揚（個別リコール）", "X", 0xFFFFFFFF.toInt(), true, 0)
    val generalRecallRaise = e(-2, 0, "第一代表旗を掲揚（ゼネラルリコール）", "第一代表", 0xFF1769FF.toInt(), true, 0, 0)
    val generalRecallLower = e(-3, 0, "第一代表旗を降下", "第一代表", 0xFF1769FF.toInt(), false, 0)
    val postponementRaise = e(-4, 0, "回答旗（AP）を掲揚", "AP", 0xFFD71920.toInt(), true, 0, 0)
    val postponementLower = e(-5, 0, "回答旗（AP）を降下", "AP", 0xFFD71920.toInt(), false, 0)

    fun restartEvents(prepFlag: String = "P", orangeEnabled: Boolean = true, orangeRemovedAfterMinutes: Int = 4, className: String = "クラス旗"): List<SignalEvent> {
        val rows = listOf(
            e(0, 0, "${className}を掲揚（再予告信号）", if (className == "クラス旗") "級" else "class-$className", 0xFF7A35A8.toInt(), true, 0),
            e(1, 60, "準備信号を掲揚", prepFlag, if (prepFlag == "I") 0xFFF5D328.toInt() else 0xFF1769FF.toInt(), true, 0),
            e(2, 240, "準備信号を降下（スタート1分前）", prepFlag, if (prepFlag == "I") 0xFFF5D328.toInt() else 0xFF1769FF.toInt(), false, 1),
            e(3, 300, "${className}を降下（スタート）", if (className == "クラス旗") "級" else "class-$className", 0xFF7A35A8.toInt(), false, 0),
            e(4, 540, "オレンジ旗を降下（スタート後）", "橙", 0xFFF58A00.toInt(), false)
        )
        return rows.mapNotNull { row ->
            if (row.flag == "橙" && !orangeEnabled) null
            else if (row.flag == "橙" && !row.raised) row.copy(secondsAfterStart = 300 + orangeRemovedAfterMinutes.coerceIn(0, 30) * 60)
            else row
        }
    }

    fun events(
        durationMinutes: Int = 14,
        profileIndex: Int = 0,
        prepFlag: String = "P",
        orangeEnabled: Boolean = true,
        orangeRemovedAfterMinutes: Int = 4,
        className: String = "クラス旗"
    ): List<SignalEvent> {
        val profile = profiles.getOrElse(profileIndex) { profiles[0] }
        val source = if (profile.id == "standard-start") {
            profile.events.map { event ->
                when {
                    event.flag == "P" && prepFlag == "I" -> event.copy(flag = "I", color = 0xFFF5D328.toInt(), title = event.title.replace("P旗", "I旗"))
                    event.flag == "級" -> event.copy(flag = if (className == "クラス旗") "級" else "class-$className", title = event.title.replace("クラス旗", className))
                    else -> event
                }
            }
        } else {
            val fixedVideo = profile.id == "video-20" || profile.id == "video-13"
            val scale = durationMinutes.coerceAtLeast(1).toDouble() / profile.baseDurationMinutes.coerceAtLeast(1)
            profile.events.map { event ->
                val scaled = if (fixedVideo) event else event.copy(secondsAfterStart = (event.secondsAfterStart * scale).toInt())
                if (event.flag == "級") scaled.copy(flag = if (className == "クラス旗") "級" else "class-$className", title = scaled.title.replace("クラス旗", className)) else scaled
            }
        }
        return source.mapNotNull { event ->
            if (event.flag == "橙" && !orangeEnabled) null
            else if (event.flag == "橙" && profile.id == "standard-start" && !event.raised)
                event.copy(secondsAfterStart = 600 + orangeRemovedAfterMinutes.coerceIn(0, 30) * 60)
            else event
        }
    }

    /** Selects the same pre-start row that the reference app keeps highlighted. */
    fun initialEventIndex(profileIndex: Int): Int {
        val profile = profiles.getOrElse(profileIndex) { profiles[0] }
        val selectedSeconds = when (profile.id) {
            "video-20" -> 600
            "video-13" -> 540
            else -> 0
        }
        return profile.events.indexOfFirst { it.secondsAfterStart == selectedSeconds }.takeIf { it >= 0 } ?: 0
    }

    /** The most recent elapsed-time signal, or -1 before the first action. */
    fun nextIndex(elapsedSeconds: Double, durationMinutes: Int = 14, profileIndex: Int = 0, prepFlag: String = "P"): Int =
        SignalTiming.activeEventIndex(elapsedSeconds, events(durationMinutes, profileIndex, prepFlag).map { it.secondsAfterStart })

    fun untilNext(elapsedSeconds: Double, index: Int, durationMinutes: Int = 14, profileIndex: Int = 0, prepFlag: String = "P"): Int {
        val list = events(durationMinutes, profileIndex, prepFlag)
        if (index !in list.indices) return 0
        return kotlin.math.ceil(list[index].secondsAfterStart - elapsedSeconds).toInt()
    }

    /** Flag state at a point in the elapsed sequence, with one mast per distinct flag. */
    fun flagsAt(elapsedSeconds: Double, durationMinutes: Int = 14, profileIndex: Int = 0, prepFlag: String = "P"): List<SignalFlagState> =
        flagsAtEvents(events(durationMinutes, profileIndex, prepFlag), elapsedSeconds)

    fun flagsAtEvents(list: List<SignalEvent>, elapsedSeconds: Double): List<SignalFlagState> {
        val transitions = list.flatMap { event ->
            event.flagMarks.map { mark ->
                event.secondsAfterStart to SignalFlagState(
                    mark.id, mark.color, event.raised, mark.whiteSquare, mark.style, mark.secondaryColor
                )
            }
        }
        return transitions.groupBy { it.second.id }.map { (_, actions) ->
            val latest = actions.lastOrNull { it.first <= elapsedSeconds }
            val first = actions.first().second
            (latest?.second ?: first).copy(raised = latest?.second?.raised ?: false)
        }
    }
}
