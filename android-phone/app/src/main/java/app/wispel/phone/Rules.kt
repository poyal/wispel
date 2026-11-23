package app.wispel.phone

object Rules {
    const val DAY = 86_400_000L
    val labels =
        linkedMapOf(
            "call" to "전화 알림",
            "missedCall" to "부재중 전화",
            "sms" to "새 문자",
            "kakao" to "카카오톡",
            "slack" to "Slack",
            "mail" to "메일플러그",
        )

    fun classify(base: String, lines: List<String>): String =
        if (
            base == "call" && lines.any { it.trimEnd().substringAfterLast('\n').trim() == "부재중 전화" }
        )
            "missedCall"
        else base

    fun quiet(occurred: Long, now: Long) = now - occurred >= 60_000L

    fun valid(occurred: Long, now: Long) = occurred > now - DAY && occurred <= now + 300_000L
}
