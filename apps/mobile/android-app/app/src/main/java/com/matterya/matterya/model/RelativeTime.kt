package com.matterya.matterya.model

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.abs

/** Mirrors iOS `RelativeTime` in Models.swift. */
object RelativeTime {

    fun format(iso: String): String {
        val date = parseDate(iso) ?: return ""
        val now = Instant.now()
        val minutes = ChronoUnit.MINUTES.between(date, now)
        val hours = ChronoUnit.HOURS.between(date, now)
        val days = ChronoUnit.DAYS.between(date, now)
        return when {
            abs(minutes) < 1 -> "now"
            abs(minutes) < 60 -> "${abs(minutes)}m"
            abs(hours) < 24 -> "${abs(hours)}h"
            abs(days) < 7 -> "${abs(days)}d"
            abs(days) < 30 -> "${abs(days) / 7}w"
            else -> DateTimeFormatter.ofPattern("MMM d", Locale.getDefault())
                .withZone(ZoneId.systemDefault())
                .format(date)
        }
    }

    fun formatClock(iso: String): String {
        val date = parseDate(iso) ?: return ""
        return DateTimeFormatter.ofLocalizedTime(java.time.format.FormatStyle.SHORT)
            .withZone(ZoneId.systemDefault())
            .withLocale(Locale.getDefault())
            .format(date)
    }

    fun formatDateTime(iso: String): String {
        val date = parseDate(iso) ?: return ""
        return DateTimeFormatter.ofLocalizedDateTime(
            java.time.format.FormatStyle.MEDIUM,
            java.time.format.FormatStyle.SHORT,
        )
            .withZone(ZoneId.systemDefault())
            .withLocale(Locale.getDefault())
            .format(date)
    }

    fun parseDate(iso: String): Instant? {
        val trimmed = iso.trim()
        if (trimmed.isEmpty() || ContentSanitizer.looksLikeId(trimmed)) return null

        parseIso(trimmed)?.let { return it }

        val normalized = if (trimmed.contains("T")) trimmed else trimmed.replace(" ", "T")
        parseIso(normalized)?.let { return it }

        trimmed.toDoubleOrNull()?.let { numeric ->
            val seconds = if (numeric > 1_000_000_000_000.0) numeric / 1000.0 else numeric
            return Instant.ofEpochMilli((seconds * 1000.0).toLong())
        }

        return null
    }

    private fun parseIso(value: String): Instant? {
        // Instant.parse handles offset forms; try common variants.
        runCatching { Instant.parse(value) }.getOrNull()?.let { return it }
        // With trailing Z after fractional / without Z
        val candidates = buildList {
            add(value)
            if (!value.endsWith("Z") && !value.contains("+") && value.count { it == '-' } <= 2) {
                add(value + "Z")
            }
        }
        for (c in candidates) {
            runCatching { Instant.parse(c) }.getOrNull()?.let { return it }
        }
        // Fallback formatters for fractional seconds
        val patterns = listOf(
            DateTimeFormatter.ISO_OFFSET_DATE_TIME,
            DateTimeFormatter.ISO_INSTANT,
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSSSSSX"),
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSSX"),
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ssX"),
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"),
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss'Z'"),
        )
        for (fmt in patterns) {
            runCatching {
                val ta = fmt.parse(value)
                Instant.from(ta)
            }.getOrNull()?.let { return it }
        }
        return null
    }
}
