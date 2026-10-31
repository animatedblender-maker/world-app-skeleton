package com.matterya.matterya.data.search

import com.matterya.matterya.model.Country
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.Profile
import com.matterya.matterya.model.RelativeTime
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min

/** iOS `MatteryaSearchEngine.swift` — ranking weights preserved. */
object MatteryaSearchEngine {
    const val COUNTRY_LIMIT = 12
    const val PEOPLE_LIMIT = 20
    const val CONTENT_LIMIT = 40

    fun normalizeName(value: String): String =
        value.trim().lowercase()
            .replace(Regex("""\s+"""), " ")
            .replace("'", "")
            .replace("’", "")
            .replace(Regex("""[^a-z0-9 ]"""), "")

    fun searchCountries(countries: List<Country>, query: String, limit: Int = COUNTRY_LIMIT): List<Country> {
        val normalized = normalizeName(query)
        if (normalized.isEmpty()) return emptyList()
        return countries.mapNotNull { c ->
            val score = countryScore(c, normalized, query)
            if (score > 0) c to score else null
        }.sortedWith(compareByDescending<Pair<Country, Double>> { it.second }.thenBy { it.first.name })
            .take(limit)
            .map { it.first }
    }

    fun rankProfiles(profiles: List<Profile>, query: String, limit: Int = PEOPLE_LIMIT): List<Profile> {
        val normalized = normalizeName(query)
        if (normalized.isEmpty()) return profiles.take(limit)
        return profiles.mapNotNull { p ->
            val score = profileScore(p, normalized, query)
            if (score > 0) p to score else null
        }.sortedWith(
            compareByDescending<Pair<Profile, Double>> { it.second }
                .thenBy { it.first.displayName ?: it.first.username ?: "" },
        ).take(limit).map { it.first }
    }

    fun rankContent(posts: List<CountryPost>, query: String, limit: Int = CONTENT_LIMIT): List<CountryPost> {
        val normalized = normalizeName(query)
        if (normalized.isEmpty()) return posts.take(limit)
        val terms = normalized.split(" ").filter { it.isNotEmpty() }
        if (terms.isEmpty()) return posts.take(limit)
        return posts.mapNotNull { post ->
            if (post.isStory) return@mapNotNull null
            val score = contentScore(post, normalized, terms, query)
            if (score > 0) post to score else null
        }.sortedWith(
            compareByDescending<Pair<CountryPost, Double>> { it.second }
                .thenByDescending { it.first.createdAt },
        ).take(limit).map { it.first }
    }

    private fun countryScore(country: Country, normalized: String, rawQuery: String): Double {
        val name = normalizeName(country.name)
        val iso = country.iso.lowercase()
        val raw = rawQuery.trim().lowercase()
        if (name == normalized || iso == raw || iso == normalized) return 120.0
        if (name.startsWith(normalized) || iso.startsWith(raw)) return 95.0
        if (normalized.length >= 3 && name.contains(normalized)) return 72.0
        if (raw.length == 2 && iso == raw) return 110.0
        if (iso.contains(raw) && raw.length >= 2) return 58.0
        return 0.0
    }

    private fun profileScore(profile: Profile, normalized: String, rawQuery: String): Double {
        val username = normalizeName(profile.username ?: "")
        val displayName = normalizeName(profile.displayName ?: "")
        val country = normalizeName(profile.countryName ?: "")
        val raw = rawQuery.trim().lowercase()
        var score = 0.0
        if (username == normalized || displayName == normalized) score = max(score, 120.0)
        if (username.startsWith(normalized) || displayName.startsWith(normalized)) score = max(score, 92.0)
        if (username.contains(normalized) || displayName.contains(normalized)) score = max(score, 68.0)
        if (country.isNotEmpty() && country.contains(normalized)) score = max(score, 42.0)
        if (raw.startsWith("@") && username.contains(normalizeName(raw.drop(1)))) score = max(score, 100.0)
        val followers = (profile.followersCount ?: 0).toDouble()
        if (followers > 0) score += min(8.0, log10(followers + 1))
        return score
    }

    private fun contentScore(
        post: CountryPost,
        normalized: String,
        terms: List<String>,
        rawQuery: String,
    ): Double {
        val title = normalizeName(post.displayTitle ?: "")
        val body = normalizeName(post.displayBody)
        val caption = normalizeName(post.displayCaption ?: "")
        val author = normalizeName(post.authorDisplayName)
        val username = normalizeName(post.author?.username ?: "")
        val country = normalizeName(post.countryName ?: "")
        val city = normalizeName(post.cityName ?: "")
        val linkTitle = normalizeName(post.linkTitle ?: "")
        val haystacks = listOf(
            title to 5.0, body to 2.0, author to 3.0, username to 3.0,
            country to 2.0, city to 1.5, caption to 1.5, linkTitle to 1.2,
        )
        var score = 0.0
        for ((haystack, weight) in haystacks) {
            if (haystack.isEmpty()) continue
            when {
                haystack == normalized -> score += weight * 14
                haystack.startsWith(normalized) -> score += weight * 10
                haystack.contains(normalized) -> score += weight * 6
            }
            val matched = terms.count { haystack.contains(it) }
            if (matched > 0) score += weight * matched * 2.4
        }
        if (score <= 0) return 0.0
        if (post.hasVideo || post.hasImage) score += 1.2
        if (post.isReel) score += 0.6
        val engagement = ln((post.likeCount + 1).toDouble()) +
            ln((post.commentCount + 1).toDouble()) * 1.2 +
            ln((max(post.viewCount, 0) + 1).toDouble()) * 0.5
        score += min(6.0, engagement)
        val created = RelativeTime.parseDate(post.createdAt)
        if (created != null) {
            val ageHours = max(0.0, (System.currentTimeMillis() - created.toEpochMilli()) / 3_600_000.0)
            score += exp(-ageHours / (24 * 7)) * 4
        }
        if (rawQuery.startsWith("#") && body.contains(normalizeName(rawQuery.drop(1)))) {
            score += 3
        }
        return score
    }
}
