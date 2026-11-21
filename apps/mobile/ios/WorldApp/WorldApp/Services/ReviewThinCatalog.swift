import Foundation

/// App Review thin catalog gate — mirrors API `isAppReviewViewer`.
///
/// When active, Home / Sparks / Hubs must stay empty: no ContentCache paint,
/// no GraphQL discover, no Sparks discovery catalog, no hub/spark top-ups.
/// `seed_catalog_public` stays true globally for everyone else.
///
/// **Safety:** only the known Review account is ever locked. A sticky
/// `reviewThin` flag must never empty a normal user's feed after an empty
/// page, account switch, or parse glitch.
@MainActor
enum ReviewThinCatalog {
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

    /// Active only for the Review tester account — never sticky for normal users.
    static var isActive: Bool { isReviewAccount }

    /// Server returned `reviewThin` — wipe caches only when this session is Review.
    static func noteServerReviewThin() {
        guard isReviewAccount else { return }
        wipeLocalCatalogCaches()
        #if DEBUG
        print("[ReviewThin] wipe caches from server reviewThin")
        #endif
    }

    /// Call on auth settle / feed bootstrap so Review never paints sticky cache first.
    /// Clears any prior wipe side-effects when a normal account is signed in.
    static func refreshFromSession() {
        if isReviewAccount {
            wipeLocalCatalogCaches()
            #if DEBUG
            print("[ReviewThin] active for review account session")
            #endif
        }
    }

    /// Clear after logout (kept for call-site symmetry).
    static func clear() {
        // isActive is derived from the session; nothing sticky to clear.
    }

    private static func wipeLocalCatalogCaches() {
        ContentCache.shared.invalidateAllFeeds()
        PostsService.shared.clearDiscoveryCatalogForReviewThin()
    }
}
