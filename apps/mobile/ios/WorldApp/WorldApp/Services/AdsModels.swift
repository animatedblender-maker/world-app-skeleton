import Foundation

// MARK: - Delivery policy (single place for teammates)

/// Tunables for Sparks standalone ads + Hubs pre-roll.
/// Keep product density / skip timing here — not scattered in feed views.
enum AdDeliveryPolicy {
    /// First Sparks ad after this many organic swipes (inclusive range).
    static let firstOrganicGap = 12...28
    /// Later Sparks ads (light density).
    static let laterOrganicGap = 85...140
    /// Retry gap when serve returns nil before first insert.
    static let emptyServeFirstGap = 18...36
    /// Retry gap when serve returns nil after an ad was already shown.
    static let emptyServeLaterGap = 100...160
    /// How far ahead to look to avoid stacking ads.
    static let upcomingAdAvoidWindow = 18
    /// Client cache TTL for last successful serve (Hubs instant start).
    static let serveCacheMaxAge: TimeInterval = 120
    /// Skip control becomes available after this many seconds (clamped with server value).
    static let skipAfterSecondsClamp = 3...5
    /// GraphQL serve timeout for cold pre-roll (seconds).
    static let serveTimeoutSeconds: Double = 8

    /// Premium gate — must hop to MainActor with `SubscriptionService`.
    @MainActor
    static var adsEnabled: Bool {
        !SubscriptionService.shared.isPremium
    }
}

// MARK: - Domain models

struct AdCreative: Identifiable, Hashable, Sendable {
    let id: String
    let campaignID: String
    let title: String?
    let body: String?
    let mediaKind: String
    let mediaURL: String
    let clickURL: String?
    let ctaLabel: String?
    let durationSeconds: Int
}

struct AdCampaign: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let status: String
    let placement: String
    let targetCountryCodes: [String]
    let budgetCents: Int
    let dailyBudgetCents: Int
    let startAt: String?
    let endAt: String?
    let impressionCount: Int
    let clickCount: Int
    let creatives: [AdCreative]
}

struct AdSlot: Sendable {
    let impressionToken: String
    let skipAfterSeconds: Int
    let campaign: AdCampaign
    let creative: AdCreative
}

// MARK: - CountryPost sponsored factory

extension CountryPost {
    /// Standalone Sparks / feed sponsored card (not an overlay on organic content).
    var isSponsoredAd: Bool {
        externalRefType == "ad" || id.hasPrefix("adslot:")
    }

    static func sponsoredAd(from slot: AdSlot) -> CountryPost {
        let now = ISO8601DateFormatter().string(from: Date())
        let title = slot.creative.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (slot.creative.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return CountryPost(
            id: "adslot:\(slot.impressionToken)",
            title: (title?.isEmpty == false) ? title : slot.campaign.name,
            body: body,
            mediaType: "video",
            mediaURL: slot.creative.mediaURL,
            thumbURL: nil,
            mediaCaption: nil,
            sharedPostID: nil,
            sharedPost: nil,
            visibility: .public,
            likeCount: 0,
            commentCount: 0,
            viewCount: 0,
            likedByMe: false,
            savedByMe: false,
            createdAt: now,
            updatedAt: now,
            authorID: "sponsored",
            countryName: nil,
            countryCode: slot.campaign.targetCountryCodes.first,
            cityName: nil,
            author: PostAuthor(
                userID: "sponsored",
                displayName: "Sponsored",
                username: "sponsored",
                avatarURL: nil,
                countryName: nil,
                countryCode: nil,
                lastReadAt: nil,
                isVerified: false
            ),
            linkURL: slot.creative.clickURL,
            linkTitle: slot.creative.ctaLabel ?? "Learn more",
            externalRefType: "ad",
            externalRefID: slot.impressionToken,
            isAdult: false
        )
    }
}

// MARK: - Session registries

/// Session registry for standalone Sparks ad cards (CTA / impression token).
@MainActor
enum SparkAdRegistry {
    private static var slots: [String: AdSlot] = [:]

    static func remember(_ slot: AdSlot, forPostID id: String) {
        slots[id] = slot
    }

    static func slot(forPostID id: String) -> AdSlot? {
        slots[id]
    }

    static func clear(_ id: String) {
        slots.removeValue(forKey: id)
    }
}

/// In-memory last-serve cache so Hubs pre-roll can start without a GraphQL wait.
@MainActor
enum AdServeCache {
    private static var byPlacement: [String: (slot: AdSlot, at: Date)] = [:]

    static func peek(placement: String) -> AdSlot? {
        guard let entry = byPlacement[placement],
              Date().timeIntervalSince(entry.at) < AdDeliveryPolicy.serveCacheMaxAge
        else { return nil }
        return entry.slot
    }

    static func store(_ slot: AdSlot, placement: String) {
        let now = Date()
        byPlacement[placement] = (slot, now)
        // Video campaigns also feed Sparks reel requests.
        if placement == "video" {
            byPlacement["reel"] = (slot, now)
        }
    }

    static func clear() {
        byPlacement.removeAll()
    }
}

// MARK: - Safe URL open

enum AdURL {
    /// `matterya.com` (no scheme) → `https://matterya.com`.
    /// Rejects non-http(s), credentials-in-URL, and empty hosts.
    static func normalized(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2048 else { return nil }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("javascript:")
            || lower.hasPrefix("data:")
            || lower.hasPrefix("file:")
            || lower.hasPrefix("vbscript:")
            || lower.hasPrefix("blob:")
            || lower.hasPrefix("about:")
            || lower.hasPrefix("intent:")
            || lower.hasPrefix("app:")
        {
            return nil
        }
        let candidate: URL?
        if let url = URL(string: trimmed), url.scheme != nil {
            candidate = url
        } else if trimmed.hasPrefix("//") {
            candidate = URL(string: "https:\(trimmed)")
        } else {
            candidate = URL(string: "https://\(trimmed)")
        }
        guard let url = candidate,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil
        else { return nil }
        return url
    }

    static func media(_ raw: String) -> URL? {
        normalized(raw)
    }
}
