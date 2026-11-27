import AVFoundation
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
    static let serveCacheMaxAge: TimeInterval = 180
    /// Skip control becomes available after this many seconds (clamped with server value).
    static let skipAfterSecondsClamp = 3...5
    /// GraphQL serve timeout for cold pre-roll (seconds). Skip to film fast — never hang on spinner.
    static let serveTimeoutSeconds: Double = 2.5

    /// Premium gate — must hop to MainActor with `SubscriptionService`.
    @MainActor
    static var adsEnabled: Bool {
        !SubscriptionService.shared.isPremium
    }

    /// Must match `ads.serve.ts` pacing: `budget_cents / 10` max impressions.
    static let costPerImpressionCents = 10
    /// Share of impressions expected to register as a video view (estimate only).
    static let estimatedViewRate: Double = 0.85
}

struct AdsWalletModel: Sendable, Equatable {
    let balanceCents: Int
    let currency: String
    let hasPaymentMethod: Bool
    let billingConfigured: Bool
    let costPerImpressionCents: Int

    var balanceEUR: Double { Double(balanceCents) / 100.0 }

    var formattedBalance: String {
        String(format: "€%.2f", balanceEUR)
    }
}

/// Facebook-style reach estimates from advertiser-set budgets.
enum AdsBudgetEstimate {
    struct Snapshot: Equatable {
        let totalImpressions: Int
        let totalViews: Int
        let dailyImpressions: Int
        let dailyViews: Int
        let costPerImpressionEUR: Double
        let effectiveCPM: Double
    }

    static func snapshot(totalBudgetEUR: Double, dailyBudgetEUR: Double) -> Snapshot {
        let totalCents = max(0, Int((totalBudgetEUR * 100).rounded()))
        let dailyCents = max(0, Int((dailyBudgetEUR * 100).rounded()))
        let perImp = AdDeliveryPolicy.costPerImpressionCents
        let totalImp = perImp > 0 ? totalCents / perImp : 0
        let dailyImp = perImp > 0 ? dailyCents / perImp : 0
        let rate = AdDeliveryPolicy.estimatedViewRate
        let costEUR = Double(perImp) / 100.0
        return Snapshot(
            totalImpressions: totalImp,
            totalViews: Int((Double(totalImp) * rate).rounded()),
            dailyImpressions: dailyImp,
            dailyViews: Int((Double(dailyImp) * rate).rounded()),
            costPerImpressionEUR: costEUR,
            effectiveCPM: costEUR * 1000
        )
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
    /// Warmed assets so AdPreroll mounts without a cold CDN round-trip.
    private static var warmAssets: [String: AVURLAsset] = [:]

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
        warmMedia(slot.creative.mediaURL)
    }

    /// AVPlayerItem from a warmed asset when possible — instant Hubs pre-roll start.
    static func playerItem(for mediaURL: String) -> AVPlayerItem? {
        guard let url = AdURL.media(mediaURL) else { return nil }
        let key = url.absoluteString
        if let asset = warmAssets[key] {
            return AVPlayerItem(asset: asset)
        }
        let asset = AVURLAsset(url: url)
        warmAssets[key] = asset
        warmAssetKeys(asset)
        return AVPlayerItem(asset: asset)
    }

    static func warmMedia(_ raw: String) {
        guard let url = AdURL.media(raw) else { return }
        let key = url.absoluteString
        if warmAssets[key] != nil { return }
        let asset = AVURLAsset(url: url)
        warmAssets[key] = asset
        warmAssetKeys(asset)
    }

    private static func warmAssetKeys(_ asset: AVURLAsset) {
        asset.loadValuesAsynchronously(forKeys: ["playable", "duration"]) {
            // Keep asset retained in warmAssets; values load into AVFoundation cache.
        }
    }

    static func clear() {
        byPlacement.removeAll()
        warmAssets.removeAll()
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
