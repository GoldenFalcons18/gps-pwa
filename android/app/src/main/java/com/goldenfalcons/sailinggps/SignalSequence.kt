package com.goldenfalcons.sailinggps

data class SignalFlagMark(val id: String, val color: Int, val whiteSquare: Boolean = false) {
    val secondaryColor: Int get() = when (id) {
        "斜め" -> 0xFFD71920.toInt()
        "赤白チェック", "N" -> 0xFFFFFFFF.toInt()
        else -> 0xFFFFFFFF.toInt()
    }
    val style: String get() = when {
        id.startsWith("intl:") -> "internationalFlag"
        id.startsWith("text:") -> "textFlag"
        id == "斜め" -> "diagonal"
        id == "赤白チェック" -> "checker"
        id == "級" || id.startsWith("class-") -> "classLogo"
        id == "青" -> "blueSquare"
        id in setOf("P", "I", "U", "N", "H", "O", "X", "第一代表", "AP", "Z", "L") -> "internationalFlag"
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
        "青" -> "blueSquare"
        "P", "I", "U", "N", "H", "O", "X", "第一代表", "AP", "Z", "L" -> "internationalFlag"
        "赤白チェック" -> "checker"
        "斜め" -> "diagonal"
        else -> if (id.startsWith("class-")) "classLogo" else "solid"
    },
    val secondaryColor: Int = when (id) {
        "斜め", "O" -> 0xFFD71920.toInt()
        "赤白チェック" -> 0xFFFFFFFF.toInt()
        else -> 0xFFFFFFFF.toInt()
    }
)

object SignalMastLayout {
    fun poleIndex(flagId: String, otherFlagOrdinal: Int): Int = when {
        flagId == "橙" || flagId == "orange" -> 1
        flagId == "X" -> 0
        flagId == "第一代表" || flagId == "first-sub" -> 0
        flagId.startsWith("class-") || flagId == "級" -> 3
        else -> 4
    }

    fun canOperateRaceSignals(hasStarted: Boolean, firstActionPending: Boolean, restartPending: Boolean): Boolean =
        hasStarted && !firstActionPending && !restartPending

    fun flagsWhilePostponementRaised(existing: List<SignalFlagState>): List<SignalFlagState> =
        existing.filter { it.id == "橙" || it.id == "orange" } +
            SignalFlagState("AP", 0xFFD71920.toInt(), true, false)
}

object SignalSequence {
    fun preparationFlagForStartRule(rule: String): String = when (rule) {
        "P", "I", "U", "Z" -> rule
        "Black" -> "black"
        else -> "P"
    }

    const val MANUAL_ORANGE_RAISE_RECORD_ID = -100

    fun recordingManualOrangeRaise(events: List<SignalEvent>, raisedAtMillis: Long, sequenceStartAtMillis: Long): List<SignalEvent> {
        val offsetSeconds = kotlin.math.floor((raisedAtMillis - sequenceStartAtMillis) / 1000.0).toInt()
        val record = SignalEvent(MANUAL_ORANGE_RAISE_RECORD_ID, offsetSeconds, "橙旗を掲揚（手動・実時刻）", 0xFFF58A00.toInt(), true, "橙", emptyList())
        return (events + record).sortedWith(compareBy<SignalEvent> { it.secondsAfterStart }.thenBy { it.id })
    }

    fun eventsStartingAtFirstClassWarning(events: List<SignalEvent>): List<SignalEvent>? {
        val warningIndex = events.indexOfFirst { event ->
            event.raised && event.flagMarks.any { it.style == "classLogo" }
        }
        if (warningIndex < 0) return null
        val warningOffset = events[warningIndex].secondsAfterStart
        return events.drop(warningIndex).mapIndexed { index, event ->
            event.copy(id = index, secondsAfterStart = event.secondsAfterStart - warningOffset)
        }
    }

    fun encodeEvents(events:List<SignalEvent>):String = org.json.JSONArray().apply {
        events.forEach { event -> put(org.json.JSONObject().apply {
            put("id",event.id);put("seconds",event.secondsAfterStart);put("title",event.title);put("color",event.color.toLong());put("raised",event.raised);put("flag",event.flag)
            put("pulses",org.json.JSONArray(event.hornPulses))
            put("additional",org.json.JSONArray().apply { event.additionalFlags.forEach { mark -> put(org.json.JSONObject().put("id",mark.id).put("color",mark.color.toLong()).put("white",mark.whiteSquare)) } })
        }) }
    }.toString()

    fun decodeEvents(raw:String?):List<SignalEvent>? = runCatching {
        val array=org.json.JSONArray(raw ?: return null)
        (0 until array.length()).map { index ->
            val item=array.getJSONObject(index);val pulseArray=item.getJSONArray("pulses");val additional=item.getJSONArray("additional")
            SignalEvent(item.getInt("id"),item.getInt("seconds"),item.getString("title"),item.getLong("color").toInt(),item.getBoolean("raised"),item.getString("flag"),
                (0 until pulseArray.length()).map { pulseArray.getInt(it) },
                (0 until additional.length()).map { extra -> additional.getJSONObject(extra).let { SignalFlagMark(it.getString("id"),it.getLong("color").toInt(),it.optBoolean("white",false)) } })
        }
    }.getOrNull()

    fun startReferenceOffset(profileId: String, orangeEnabled: Boolean, orangeDisplayedMinutes: Int): Int =
        if (profileId == "standard-start") ((if (orangeEnabled) orangeDisplayedMinutes.coerceIn(0, 30) else 0) + 5) * 60 else 0

    /** The race-start zero is the final non-orange flag lowering in the start sequence. */
    fun raceStartEventIndex(events: List<SignalEvent>): Int? {
        return events.indexOfLast {
            !it.raised &&
                it.flag !in setOf("橙", "orange") &&
                (it.title.contains("スタート") || it.title.contains("降下"))
        }.takeIf { it >= 0 }
    }

    private fun resolvedClassFlagId(value: String): String = when {
        value == "クラス旗" -> "級"
        value.startsWith("intl:") -> value
        value.startsWith("text:") -> value
        value.startsWith("class-") -> value
        else -> "class-$value"
    }

    private fun classFlagLabel(value: String): String = when {
        value.startsWith("intl:") -> value.removePrefix("intl:")
        value.startsWith("text:") -> value.removePrefix("text:")
        value.startsWith("class-") -> value.removePrefix("class-")
        else -> value
    }

    private fun e(id: Int, seconds: Int, title: String, flag: String, color: Int, raised: Boolean, vararg pulses: Int) =
        SignalEvent(id, seconds, title, color, raised, flag, pulses.toList())

    private fun eWithFlags(id: Int, seconds: Int, title: String, flag: String, color: Int, raised: Boolean, additional: List<SignalFlagMark>, vararg pulses: Int) =
        SignalEvent(id, seconds, title, color, raised, flag, pulses.toList(), additional)

    // Standard race sequence, measured from the orange flag raise at T-10 minutes.
    val profiles = listOf(
        SignalFlagProfile("standard-start", "帆走スタート（Rule 26・5分＋橙旗）", listOf(
            e(0, 0, "オレンジ旗を掲揚（予告信号の5分前）", "橙", 0xFFF58A00.toInt(), true, 0),
            e(1, 300, "クラス旗を掲揚（スタート5分前）", "級", 0xFF7A35A8.toInt(), true, 0),
            e(2, 360, "準備信号を掲揚（スタート4分前）", "P", 0xFF1769FF.toInt(), true, 0),
            e(3, 540, "P旗を降下（スタート1分前）", "P", 0xFF1769FF.toInt(), false, 1),
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

    val abandonRaise = e(-6, 0, "N旗を掲揚（レース中止）", "N", 0xFF1769FF.toInt(), true, 0, 0, 0)
    val abandonLower = e(-7, 0, "N旗を降下", "N", 0xFF1769FF.toInt(), false, 0)
    val individualRecallRaise = e(-1, 0, "X旗を掲揚（個別リコール）", "X", 0xFFFFFFFF.toInt(), true, 0)
    val generalRecallRaise = e(-2, 0, "第一代表旗を掲揚（ゼネラルリコール）", "第一代表", 0xFF1769FF.toInt(), true, 0, 0)
    val generalRecallLower = e(-3, 0, "第一代表旗を降下", "第一代表", 0xFF1769FF.toInt(), false, 0)
    val postponementRaise = e(-4, 0, "回答旗（AP）を掲揚", "AP", 0xFFD71920.toInt(), true, 0, 0)
    val postponementLower = e(-5, 0, "回答旗（AP）を降下", "AP", 0xFFD71920.toInt(), false, 0)

    fun shouldReleaseManualOrangeOverride(event: SignalEvent): Boolean =
        !event.raised && event.flagMarks.any { it.id == "橙" || it.id == "orange" }

    fun restartEvents(prepFlag: String = "P", orangeEnabled: Boolean = true, orangeRemovedAfterMinutes: Int = 4, className: String = "クラス旗"): List<SignalEvent> {
        val rows = mutableListOf(
            e(0, 0, "${classFlagLabel(className)}を掲揚（再予告信号）", resolvedClassFlagId(className), 0xFF7A35A8.toInt(), true, 0),
            e(1, 60, "準備信号を掲揚", prepFlag, if (prepFlag == "I") 0xFFF5D328.toInt() else 0xFF1769FF.toInt(), true, 0),
            e(2, 240, "準備信号を降下（スタート1分前）", prepFlag, if (prepFlag == "I") 0xFFF5D328.toInt() else 0xFF1769FF.toInt(), false, 1),
            e(3, 300, "${classFlagLabel(className)}を降下（スタート）", resolvedClassFlagId(className), 0xFF7A35A8.toInt(), false, 0),
        )
        if (orangeEnabled) {
            // Restart begins at the warning, while the orange flag has been
            // raised during AP handling and remains up. This state row has no
            // second horn/raise action.
            rows += e(-1, 0, "橙旗掲揚中", "橙", 0xFFF58A00.toInt(), true)
            rows += e(4, 300 + orangeRemovedAfterMinutes.coerceAtLeast(0) * 60, "橙旗を降下（スタート後の設定時間）", "橙", 0xFFF58A00.toInt(), false)
        }
        return rows.sortedWith(compareBy<SignalEvent> { it.secondsAfterStart }.thenBy { it.id })
            .mapIndexed { index, event -> event.copy(id = index) }
    }

    fun events(
        durationMinutes: Int = 14,
        profileIndex: Int = 0,
        prepFlag: String = "P",
        orangeEnabled: Boolean = true,
        orangeRemovedAfterMinutes: Int = 4,
        className: String = "クラス旗",
        orangeDisplayedMinutes: Int = 5
    ): List<SignalEvent> {
        val profile = profiles.getOrElse(profileIndex) { profiles[0] }
        val source = if (profile.id == "standard-start") {
            profile.events.map { event ->
                when {
                    event.flag == "P" -> {
                        val normalized = if (prepFlag.equals("black", ignoreCase = true)) "black" else prepFlag
                        val color = when (normalized) {
                            "I", "Z" -> 0xFFF5D328.toInt()
                            "U" -> 0xFFD72C32.toInt()
                            "black" -> 0xFF111111.toInt()
                            else -> 0xFF1769FF.toInt()
                        }
                        val label = when (normalized) {
                            "I" -> "I旗"; "U" -> "U旗"; "Z" -> "Z旗"; "black" -> "黒旗"; else -> "P旗"
                        }
                        event.copy(flag = normalized, color = color, title = event.title.replace("P旗", label))
                    }
                    event.flag == "級" -> event.copy(flag = resolvedClassFlagId(className), title = event.title.replace("クラス旗", classFlagLabel(className)))
                    else -> event
                }
            }
        } else {
            // Reference-video profiles keep their recorded spacing; the duration picker must not stretch them.
            profile.events.map { event ->
                if (event.flag == "級") event.copy(flag = resolvedClassFlagId(className), title = event.title.replace("クラス旗", classFlagLabel(className))) else event
            }
        }

        val hasOrange = source.any { it.flag == "橙" }
        val firstSignal = source.firstOrNull { it.flag != "橙" && it.raised }?.secondsAfterStart ?: 0
        val lastSignal = source.lastOrNull { it.flag != "橙" }?.secondsAfterStart ?: firstSignal

        // With the orange flag enabled, sequence zero is its raise and the first
        // race signal follows after the configured display interval. With it
        // disabled, the first race signal itself is the first action at zero.
        val displayShift = if (!hasOrange) 0
            else if (orangeEnabled) orangeDisplayedMinutes.coerceIn(0, 30) * 60 - firstSignal
            else -firstSignal
        val orangeDownAt = lastSignal + displayShift + orangeRemovedAfterMinutes.coerceIn(0, 30) * 60

        return source.mapNotNull { event ->
            when {
                event.flag == "橙" && !orangeEnabled -> null
                event.flag == "橙" && event.raised -> event
                event.flag == "橙" && !event.raised -> event.copy(secondsAfterStart = orangeDownAt)
                else -> event.copy(secondsAfterStart = (event.secondsAfterStart + displayShift).coerceAtLeast(0))
            }
        }.sortedWith(compareBy<SignalEvent> { it.secondsAfterStart }.thenBy { it.id })
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

    /**
     * Applies saved fleet-start rows to the live standard sequence.
     * Rows use the settings format: Class · T−5:00 · 掲揚 · 短音.
     * Other profiles remain tied to their recorded/reference timeline.
     */
    fun configuredStandardEvents(
        base: List<SignalEvent>,
        entries: Set<String>,
        referenceOffset: Int,
        orangeRemovedAfterMinutes: Int,
        raceDelayEnabled: Boolean,
        raceDelayMinutes: Int
    ): List<SignalEvent>? = configuredStandardEvents(
        base, entries.sorted(), referenceOffset, orangeRemovedAfterMinutes, raceDelayEnabled, raceDelayMinutes
    )

    fun configuredStandardEvents(
        base: List<SignalEvent>,
        entries: List<String>,
        referenceOffset: Int,
        orangeRemovedAfterMinutes: Int,
        raceDelayEnabled: Boolean,
        raceDelayMinutes: Int
    ): List<SignalEvent>? {
        data class StartAction(
            val label: String,
            val secondsBeforeRace: Int,
            val raised: Boolean,
            val horn: List<Int>,
            val order: Int
        )

        val actions = entries.mapIndexedNotNull { order, row ->
            val match = Regex("""T[−-](\d+):(\d+)""").find(row) ?: return@mapIndexedNotNull null
            val label = row.substringBefore("·").trim()
            val minute = match.groupValues[1].toIntOrNull() ?: return@mapIndexedNotNull null
            val second = match.groupValues[2].toIntOrNull()?.coerceIn(0, 59) ?: return@mapIndexedNotNull null
            val raised = row.contains("掲揚")
            val horn = when {
                row.contains("長音") -> listOf(1)
                row.contains("音なし") -> emptyList()
                else -> listOf(0)
            }
            StartAction(label, minute * 60 + second, raised, horn, order)
        }
        val classActions = actions.filter {
            it.label.equals("Class", ignoreCase = true) || it.label.startsWith("Class:", ignoreCase = true) || it.label.contains("クラス")
        }
        val classRaises = classActions.filter { it.raised }
            .sortedWith(compareByDescending<StartAction> { it.secondsBeforeRace }.thenBy { it.order })
        if (classRaises.isEmpty()) return null

        val classUp = base.firstOrNull { (it.flag == "級" || it.flag.startsWith("class-")) && it.raised } ?: return null
        val classDown = base.firstOrNull { it.flag == classUp.flag && !it.raised } ?: return null
        val prepUp = base.firstOrNull { it.flag != classUp.flag && it.flag != "橙" && it.raised } ?: return null
        val prepDown = base.firstOrNull { it.flag == prepUp.flag && !it.raised } ?: return null
        val orangeUp = base.firstOrNull { it.flag == "橙" && it.raised }
        val orangeDown = base.lastOrNull { it.flag == "橙" && !it.raised }

        fun flagFor(label: String): Pair<String, Int> = when (label.lowercase()) {
            "orange", "橙旗" -> "橙" to 0xFFF58A00.toInt()
            "p" -> "P" to 0xFF1769FF.toInt()
            "i", "z" -> label.uppercase() to 0xFFF5D328.toInt()
            "u" -> "U" to 0xFFD72C32.toInt()
            "black" -> "黒" to 0xFF202020.toInt()
            "ap" -> "AP" to 0xFFD71920.toInt()
            "x" -> "X" to 0xFFFFFFFF.toInt()
            "first substitute" -> "第一代表" to 0xFF1769FF.toInt()
            else -> classUp.flag to classUp.color
        }

        // A zero-minute interval means simultaneous starts. Positive saved
        // intervals always apply; the former enable switch silently ignored them.
        val delay = raceDelayMinutes.coerceAtLeast(0) * 60
        val timeline = mutableListOf<SignalEvent>()
        val orangeActions = actions.filter { it.label.equals("Orange", true) || it.label == "橙旗" }
        if (orangeActions.none { it.raised }) orangeUp?.let { timeline += it }

        var finalRaceStart = 0
        var previousRaceStart: Int? = null
        classRaises.forEach { action ->
            val nominalRaceStart = (referenceOffset - action.secondsBeforeRace).coerceAtLeast(0) + 300
            val raceStart = previousRaceStart?.let { maxOf(nominalRaceStart, it + delay) } ?: nominalRaceStart
            val warningAt = (raceStart - 300).coerceAtLeast(0)
            previousRaceStart = raceStart
            val configuredClassName = action.label.substringAfter("Class:", "").trim()
            val classFlagId = if (configuredClassName.isEmpty()) classUp.flag else "class-$configuredClassName"
            val className = classFlagId.removePrefix("class-")
            val classTitle = if (classFlagId == "級") "クラス旗" else "クラス旗 $className"
            val classFlagUp = classUp.copy(flag = classFlagId, color = 0xFFFFFFFF.toInt())
            val classFlagDown = classDown.copy(flag = classFlagId, color = 0xFFFFFFFF.toInt())
            timeline += classFlagUp.copy(
                secondsAfterStart = warningAt,
                title = "${classTitle}を掲揚（予告信号）",
                hornPulses = action.horn
            )

            // The selected start rule is also the preparation signal. Do not
            // let stale fleet rows override that paired setting.
            timeline += prepUp.copy(secondsAfterStart = warningAt + 60)
            timeline += prepDown.copy(secondsAfterStart = warningAt + 240)

            // Every raised class start has its own automatic start-time lowering.
            // A separately configured lowering must not suppress this event.
            timeline += classFlagDown.copy(
                secondsAfterStart = raceStart,
                title = "${classTitle}を降下（スタート）"
            )
            finalRaceStart = maxOf(finalRaceStart, raceStart)

            actions.filter {
                !it.label.equals("Class", true) && !it.label.startsWith("Class:", true) &&
                    it.label !in setOf("Orange", "クラス旗", "橙旗") &&
                    it.label.uppercase() !in setOf("P", "I", "U", "Z", "BLACK")
            }.forEach { custom ->
                val (flag, color) = flagFor(custom.label)
                val customTime = (raceStart - custom.secondsBeforeRace).coerceAtLeast(0)
                val actionName = if (custom.raised) "掲揚" else "降下"
                timeline += SignalEvent(
                    id = timeline.size,
                    secondsAfterStart = customTime,
                    title = "${flag}を${actionName}（設定信号）",
                    color = color,
                    raised = custom.raised,
                    flag = flag,
                    hornPulses = custom.horn
                )
            }
        }

        classActions.filter { !it.raised }.forEach { action ->
            val at = (referenceOffset - action.secondsBeforeRace).coerceAtLeast(0)
            val configuredClassName = action.label.substringAfter("Class:", "").trim()
            val classFlagId = if (configuredClassName.isEmpty()) classDown.flag else "class-$configuredClassName"
            val className = classFlagId.removePrefix("class-")
            val classTitle = if (classFlagId == "級") "クラス旗" else "クラス旗 $className"
            timeline += classDown.copy(
                secondsAfterStart = at,
                title = "${classTitle}を降下",
                flag = classFlagId,
                color = 0xFFFFFFFF.toInt(),
                hornPulses = action.horn
            )
        }
        orangeActions.forEach { action ->
            val (flag, color) = flagFor(action.label)
            val at = (referenceOffset - action.secondsBeforeRace).coerceAtLeast(0)
            val actionName = if (action.raised) "掲揚" else "降下"
            timeline += SignalEvent(
                id = timeline.size,
                secondsAfterStart = at,
                title = "${flag}を${actionName}（設定信号）",
                color = color,
                raised = action.raised,
                flag = flag,
                hornPulses = action.horn
            )
        }
        if (orangeDown != null) timeline += orangeDown.copy(
            secondsAfterStart = finalRaceStart + orangeRemovedAfterMinutes.coerceAtLeast(0) * 60
        )
        return timeline.sortedWith(compareBy<SignalEvent> { it.secondsAfterStart }.thenBy { it.id })
            .mapIndexed { index, event -> event.copy(id = index) }
    }

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

    fun raisedFlagTimeMs(events: List<SignalEvent>, flagId: String, elapsedMs: Long, baseTimeMs: Long): Long? {
        val latest = events.filter {
            it.secondsAfterStart * 1000L <= elapsedMs && it.flagMarks.any { mark -> mark.id == flagId }
        }.maxByOrNull { it.secondsAfterStart }
        if (latest?.raised != true) return null
        return baseTimeMs + latest.secondsAfterStart * 1000L
    }
}

