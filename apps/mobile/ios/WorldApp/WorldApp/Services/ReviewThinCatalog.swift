import Foundation

/// App Review thin catalog gate — mirrors API `isAppReviewViewer`.
///
/// When active, Home / Sparks / Hubs must stay empty: no ContentCache paint,
/// no GraphQL discover, no Sparks discovery catalog, no hub/spark top-ups.
/// `seed_catalog_public` stays true globally for everyone else.
@MainActor
enum ReviewThinCatalog {
    /// Sticky once any surface returns `reviewThin`, or the signed-in account matches.
    private(set) static var isLocked = false

    private static let reviewEmails: Set<String> = [
        "iostester@matterya.com",
    ]
    private static let reviewUserIds: Set<String> = [
        "7a5d21ee-9f6f-4246-9728-8bb7a6ddb830",
    ]

    /// True when the current session is the App Review tester (email or user id).
    static var isReviewAccount: Bool {
        let user = AuthService.shared.currentUser
        if let email = user?.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !email.isEmpty,
           reviewEmails.contains(email)
        {
            return true
        }
        if let id = user?.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !id.isEmpty,
           reviewUserIds.contains(id)
        {
            return true
        }
        return false
    }

    /// Active lock: known Review account and/or server `reviewThin` seen this session.
    static var isActive: Bool {
        isLocked || isReviewAccount
    }

    /// Call when `/v1/feed`, `/v1/sparks`, or hubs return `reviewThin: true`.
    static func noteServerReviewThin() {
        guard !isLocked else { return }
        isLocked = true
        wipeLocalCatalogCaches()
        #if DEBUG
        print("[ReviewThin] locked from server reviewThin")
        #endif
    }

    /// Call on auth settle / feed bootstrap so Review never paints sticky cache first.
    static func refreshFromSession() {
        if isReviewAccount {
            isLocked = true
            wipeLocalCatalogCaches()
            #if DEBUG
            print("[ReviewThin] locked from review account session")
            #endif
        }
    }

    /// Clear after logout so a normal account is not stuck empty.
    static func clear() {
        isLocked = false
    }

    private static func wipeLocalCatalogCaches() {
        ContentCache.shared.invalidateAllFeeds()
        PostsService.shared.clearDiscoveryCatalogForReviewThin()
    }
}
