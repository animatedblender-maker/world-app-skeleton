package com.matterya.matterya.theme

/** iOS `MatteryaReportCategories` — shared report reasons (Mature content, never NSFW). */
object MatteryaReportCategories {
    data class Item(val slug: String, val label: String)

    val all: List<Item> = listOf(
        Item("spam", "Spam"),
        Item("harassment", "Harassment"),
        Item("hate", "Hate"),
        Item("mature", "Mature content"),
        Item("csam", "CSAM"),
        Item("violence", "Violence"),
        Item("terrorism", "Terrorism"),
        Item("self_harm", "Self-harm"),
        Item("servitude", "Servitude / domestic helpers"),
        Item("solicitation", "Adult solicitation"),
        Item("misinfo", "Misinformation"),
        Item("scam", "Scam"),
        Item("doxxing", "Doxxing / privacy"),
        Item("other", "Other"),
    )

    val labels: List<String> get() = all.map { it.label }

    fun slugForLabel(label: String): String {
        val t = label.trim().lowercase()
        all.firstOrNull { it.label.equals(t, ignoreCase = true) || it.slug == t }?.let { return it.slug }
        return when {
            t.contains("nsfw") || t.contains("sexual") || t.contains("adult") -> "mature"
            t.contains("spam") -> "spam"
            t.contains("harass") -> "harassment"
            t.contains("misinfo") -> "misinfo"
            t.contains("terror") || t.contains("extremist") -> "terrorism"
            t.contains("csam") || t.contains("grooming") || t.contains("child sexual") -> "csam"
            t.contains("solicit") || t.contains("escort") -> "solicitation"
            t.contains("servitude") || t.contains("domestic helper") || t.contains("forced labor") ||
                t.contains("traffick") -> "servitude"
            else -> "other"
        }
    }
}
