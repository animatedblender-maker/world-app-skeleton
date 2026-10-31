package com.matterya.matterya.model

import com.matterya.matterya.theme.ContentSanitizer
import com.matterya.matterya.theme.MatteryaCopy

/** iOS `AnonymousModels.swift` — Masquerade identity, spaces, posts, inbox. */

data class AnonymousProfile(
    val id: String,
    val username: String,
    val avatarSeed: String? = null,
    val createdAt: String? = null,
    val state: String? = null,
) {
    val displayHandle: String get() = "@$username"
}

data class AnonymousSession(
    val eligibleAdult: Boolean = false,
    val ageAttested: Boolean = false,
    val birthdateMissing: Boolean = false,
    val suspended: Boolean = false,
    val profile: AnonymousProfile? = null,
    val suggestedUsername: String? = null,
    val privacyNoticeVersion: String? = null,
    val gateCode: String? = null,
) {
    companion object {
        val empty = AnonymousSession()
    }
}

enum class AnonymousSpaceFilter(val rawValue: String, val title: String) {
    ForYou("for_you", "For You"),
    Popular("popular", "Popular"),
    Newest("newest", "Newest"),
    Joined("joined", "Joined"),
    Free("free", "Free"),
    Paid("paid", "Paid"),
    ;

    val id: String get() = rawValue

    companion object {
        fun fromRaw(raw: String?): AnonymousSpaceFilter =
            entries.firstOrNull { it.rawValue == raw } ?: ForYou
    }
}

enum class AnonymousSpaceVisibility(val rawValue: String) {
    AdultPublic("adult_public"),
    Restricted("restricted"),
    PrivateSpace("private"),
    ;

    companion object {
        fun fromRaw(raw: String?): AnonymousSpaceVisibility? =
            entries.firstOrNull { it.rawValue == raw }
    }
}

enum class AnonymousSpaceAdmission(val rawValue: String) {
    Free("free"),
    Approval("approval"),
    Paid("paid"),
    PaidPlusApproval("paid_plus_approval"),
    ;

    val isPaid: Boolean get() = this == Paid || this == PaidPlusApproval

    companion object {
        fun fromRaw(raw: String?): AnonymousSpaceAdmission? =
            entries.firstOrNull { it.rawValue == raw }
    }
}

data class AnonymousSpace(
    val id: String,
    val slug: String,
    val title: String,
    val description: String? = null,
    val category: String? = null,
    val tags: List<String>? = null,
    val visibility: AnonymousSpaceVisibility? = null,
    val admission: AnonymousSpaceAdmission? = null,
    val memberCount: Int? = null,
    val postCount: Int? = null,
    val ownerUsername: String? = null,
    val rules: List<String>? = null,
    val isJoined: Boolean? = null,
    val isOwner: Boolean? = null,
    val isModerator: Boolean? = null,
    val priceCurrency: String? = null,
    val priceAmountMinor: Int? = null,
    val billingPeriod: String? = null,
    val status: String? = null,
) {
    val isPaid: Boolean get() = admission?.isPaid == true

    val normalizedSlug: String
        get() = slug.trim().lowercase()

    val priceLabel: String?
        get() {
            if (!isPaid) return null
            val minor = priceAmountMinor ?: return null
            val currency = priceCurrency ?: return null
            val amount = minor / 100.0
            val period = billingPeriod?.let { " / $it" } ?: ""
            return String.format("%s %.2f%s", currency, amount, period)
        }
}

data class AnonymousMembership(
    val id: String,
    val spaceId: String,
    val state: String,
    val role: String? = null,
    val joinedAt: String? = null,
)

data class AnonymousNotification(
    val id: String,
    val kind: String? = null,
    val title: String? = null,
    val body: String? = null,
    val spaceId: String? = null,
    val spaceTitle: String? = null,
    val postId: String? = null,
    val actorUsername: String? = null,
    val createdAt: String? = null,
    val readAt: String? = null,
) {
    val isUnread: Boolean get() = readAt == null

    val displayTitle: String
        get() {
            val t = title?.let { masqueradeDisplayText(it) }.orEmpty()
            if (t.isNotEmpty()) return t
            return when (kind) {
                "reply" -> "New reply"
                "mention" -> "Mention"
                "space" -> "Space update"
                "moderation_removal" -> "Post removed"
                "moderation_report_resolved" -> "Report update"
                "moderation_account" -> "Account notice"
                else -> "Masquerade alert"
            }
        }

    val displayBody: String
        get() {
            val b = body?.let { masqueradeDisplayText(it) }.orEmpty()
            if (b.isNotEmpty()) return b
            val actor = actorUsername
            val space = spaceTitle
            return when {
                actor != null && space != null -> "@$actor in $space"
                actor != null -> "@$actor"
                else -> "Activity in Masquerade"
            }
        }
}

data class AnonymousPost(
    val id: String,
    val spaceId: String,
    val spaceSlug: String? = null,
    val spaceTitle: String? = null,
    val authorUsername: String = "anonymous",
    val authorProfileId: String = "",
    val title: String? = null,
    val body: String = "",
    val createdAt: String = "",
    val editedAt: String? = null,
    val score: Int? = null,
    val commentCount: Int? = null,
    val myVote: Int? = null,
    val isPinned: Boolean? = null,
    val isLocked: Boolean? = null,
    val mediaType: String? = null,
    val mediaURL: String? = null,
    val thumbURL: String? = null,
    val flagged: Boolean? = null,
    val flaggedAt: String? = null,
    val flagReason: String? = null,
) {
    val isFlagged: Boolean
        get() = flagged == true || !(flaggedAt.isNullOrEmpty())

    val displayTitle: String?
        get() {
            val t = masqueradeDisplayText(title)
            return t.ifEmpty { null }
        }

    val displayBody: String get() = masqueradeDisplayText(body)

    val hasImage: Boolean
        get() = mediaType == "image" || mediaType == "gif"

    val hasVideo: Boolean get() = mediaType == "video"

    val usableMediaUrl: String?
        get() {
            val u = mediaURL?.trim().orEmpty()
            if (u.isEmpty() || u.startsWith("r2:", ignoreCase = true)) return null
            return u
        }

    val usableThumbUrl: String?
        get() {
            val u = thumbURL?.trim().orEmpty()
            if (u.isEmpty() || u.startsWith("r2:", ignoreCase = true)) return null
            return u
        }
}

sealed class AnonymousRoute {
    data class Space(val slug: String) : AnonymousRoute()
    data class Post(val id: String) : AnonymousRoute()
    data class Profile(val username: String) : AnonymousRoute()
    data class Conversation(val id: String) : AnonymousRoute()
}

data class AnonymousSearchResults(
    val people: List<AnonymousProfile> = emptyList(),
    val spaces: List<AnonymousSpace> = emptyList(),
    val posts: List<AnonymousPost> = emptyList(),
)

data class AnonymousPublicProfilePayload(
    val profile: AnonymousProfile,
    val postCount: Int? = null,
    val spaceCount: Int? = null,
)

data class AnonymousComment(
    val id: String,
    val postId: String,
    val parentCommentId: String? = null,
    val authorUsername: String = "anonymous",
    val authorProfileId: String = "",
    val body: String = "",
    val createdAt: String = "",
    val depth: Int? = null,
    val score: Int? = null,
    val myVote: Int? = null,
    val replies: List<AnonymousComment>? = null,
) {
    val displayBody: String get() = masqueradeDisplayText(body)
}

data class AnonymousPage<T>(
    val items: List<T>,
    val nextCursor: String? = null,
)

data class AnonymousNotificationsPage(
    val items: List<AnonymousNotification>,
    val nextCursor: String? = null,
    val unreadCount: Int = 0,
)

enum class AnonymousFeedSort(val rawValue: String, val title: String) {
    ForYou("for_you", "For you"),
    Hot("hot", "Hot"),
    New("new", "New"),
    Top("top", "Top"),
    ;

    val id: String get() = rawValue
}

enum class AnonymousErrorCode(val rawValue: String) {
    Under18("under_18"),
    Unattested("unattested"),
    NoProfile("no_profile"),
    PaidDisabled("paid_disabled"),
    UsernameTaken("username_taken"),
    UsernameInvalid("username_invalid"),
    Suspended("suspended"),
    Forbidden("forbidden"),
    NotFound("not_found"),
    RateLimited("rate_limited"),
    Unauthenticated("unauthenticated"),
    SessionFailed("session_failed"),
    SchemaMissing("schema_missing"),
    BirthdateRequired("birthdate_required"),
    BirthdateMissing("birthdate_missing"),
    NotMember("not_member"),
    Network("network"),
    Unknown("unknown"),
    ;

    companion object {
        fun fromRaw(raw: String?): AnonymousErrorCode =
            entries.firstOrNull { it.rawValue == raw } ?: Unknown
    }
}

sealed class AnonymousError(message: String? = null) : Exception(message) {
    data object Under18 : AnonymousError(MatteryaCopy.anonymousUnder18Body)
    data object Unattested : AnonymousError("Confirm you are 18+ to enter Masquerade.")
    data object NoProfile : AnonymousError("Claim a Masquerade username to continue.")
    data object PaidDisabled : AnonymousError("Paid Spaces are coming soon. Join free Spaces for now.")
    data object UsernameTaken : AnonymousError("That username was just taken. Try another suggestion.")
    data class UsernameInvalid(val detail: String?) : AnonymousError(detail ?: "That username isn’t allowed.")
    data object Suspended : AnonymousError("Your Masquerade access is suspended.")
    data class Forbidden(val detail: String?) : AnonymousError(detail ?: "You don’t have permission to do that.")
    data object NotFound : AnonymousError(MatteryaCopy.anonymousOfflineBody)
    data object RateLimited : AnonymousError("Too many requests. Try again in a moment.")
    data class Network(val detail: String?) : AnonymousError(detail ?: MatteryaCopy.anonymousOfflineBody)
    data class Server(val detail: String?) : AnonymousError(detail ?: MatteryaCopy.anonymousOfflineTitle)
    data object Decoding : AnonymousError("Couldn’t read the Masquerade response.")

    companion object {
        fun from(code: String?, message: String? = null): AnonymousError =
            when (AnonymousErrorCode.fromRaw(code)) {
                AnonymousErrorCode.Under18,
                AnonymousErrorCode.BirthdateRequired,
                AnonymousErrorCode.BirthdateMissing,
                -> Under18
                AnonymousErrorCode.Unattested -> Unattested
                AnonymousErrorCode.NoProfile -> NoProfile
                AnonymousErrorCode.PaidDisabled -> PaidDisabled
                AnonymousErrorCode.UsernameTaken -> UsernameTaken
                AnonymousErrorCode.UsernameInvalid -> UsernameInvalid(message)
                AnonymousErrorCode.Suspended -> Suspended
                AnonymousErrorCode.Forbidden,
                AnonymousErrorCode.NotMember,
                -> Forbidden(message)
                AnonymousErrorCode.NotFound -> NotFound
                AnonymousErrorCode.RateLimited -> RateLimited
                AnonymousErrorCode.Unauthenticated ->
                    Network("Sign in again to open Masquerade.")
                AnonymousErrorCode.SchemaMissing,
                AnonymousErrorCode.SessionFailed,
                -> Server(message ?: "Masquerade session isn’t ready yet. Pull to retry.")
                AnonymousErrorCode.Network -> Network(message)
                else -> Server(message ?: code)
            }
    }
}

data class AnonymousCreateSpaceInput(
    val slug: String,
    val title: String,
    val description: String,
    val category: String? = null,
    val tags: List<String> = emptyList(),
    val rules: List<String> = emptyList(),
    val visibility: String = AnonymousSpaceVisibility.AdultPublic.rawValue,
    val admission: String = AnonymousSpaceAdmission.Free.rawValue,
)

data class AnonymousCreatePostInput(
    val title: String? = null,
    val body: String,
    val mediaType: String? = null,
    val mediaURL: String? = null,
    val thumbURL: String? = null,
)

data class AnonymousCreateCommentInput(
    val body: String,
    val parentCommentId: String? = null,
)

data class AnonymousVoteResult(
    val value: Int? = null,
    val score: Int? = null,
)

enum class AnonymousPhase {
    Loading,
    GatedUnder18,
    NeedAttest,
    NeedUsername,
    WelcomeLetter,
    PickSpaces,
    Ready,
    Suspended,
    Offline,
}

/** Remap competitor/source wording for Masquerade surfaces. */
fun masqueradeDisplayText(value: String?): String {
    val base = ContentSanitizer.displayText(value)
    if (base.isEmpty()) return ""
    return base
        .replace(Regex("(?i)subreddits"), "spaces")
        .replace(Regex("(?i)subreddit"), "space")
        .replace(Regex("(?i)\\breddit\\b"), "masquerade")
}
