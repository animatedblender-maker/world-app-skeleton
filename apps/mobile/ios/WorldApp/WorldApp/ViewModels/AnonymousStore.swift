import Foundation
import Observation
import SwiftUI

enum AnonymousPhase: Equatable {
    case loading
    case gatedUnder18
    case needAttest
    case needUsername
    /// Full Masquerade welcome letter after claiming a name.
    case welcomeLetter
    /// First-time Space picker after the welcome letter (skippable).
    case pickSpaces
    case ready
    case suspended
    case offline
}

@MainActor
@Observable
final class AnonymousStore {
    static let shared = AnonymousStore()

    private let cacheKey = "matterya.anonymous.session.v1"
    /// v6 — For you reshuffles on each Masquerade open (v5 stuck a 20‑min disk cache).
    private let feedCacheKey = "matterya.anonymous.feed.v6"
    private let feedCacheSavedAtKey = "matterya.anonymous.feed.v6.savedAt"
    /// Instant paint from disk, then reshuffle when older than this.
    private let feedCacheMaxAge: TimeInterval = 60
    private let wildeSeenKey = "matterya.anonymous.wildeSeen.v1"
    private let welcomeLetterSeenKey = "matterya.anonymous.welcomeLetterSeen.v1"
    private let spacesOnboardingSeenKey = "matterya.anonymous.spacesOnboardingSeen.v1"
    private let pinnedUsernameKey = "matterya.anonymous.pinnedUsername.v1"

    var phase: AnonymousPhase = .loading
    var session: AnonymousSession = .empty
    var suggestedUsername: String = ""
    var isClaimingUsername = false
    var isAttesting = false
    var isRefreshing = false
    /// Wilde epigraph — only for first Masquerade entry (onboarding), then gone.
    var showWildeEpigraph: Bool = false

    var spacesByFilter: [AnonymousSpaceFilter: [AnonymousSpace]] = [:]
    var spacesCursor: [AnonymousSpaceFilter: String?] = [:]
    var spacesLoading: [AnonymousSpaceFilter: Bool] = [:]
    var activeSpaceFilter: AnonymousSpaceFilter = .forYou

    var feed: [AnonymousPost] = []
    var feedCursor: String?
    /// Default For you — social score + MMR + masquerade_for_you delivery ledger.
    var feedSort: AnonymousFeedSort = .forYou
    var feedLoading = false
    var feedLoadingMore = false
    var feedHasMore = true
    /// Posts already painted this Masquerade session — refresh/load-more prefer unseen.
    private var sessionSeenFeedIds: Set<String> = []
    /// Pull-to-refresh may replace the list; background/force must not mid-scroll.
    private var allowFeedReplace = false
    /// Last open's For you head — demoted on the next refresh so viral cards don't stick.
    private let lastFeedHeadKey = "matterya.anonymous.feed.lastHead.v1"
    /// Coalesce bootstrap + Feed tab `.task` so Masquerade doesn't double-hit `/feed`.
    private var feedLoadTask: Task<Void, Never>?

    var inbox: [AnonymousNotification] = []
    var inboxCursor: String?
    var inboxLoading = false
    /// Server unread for Masquerade alerts (bell + tab badge).
    var notificationUnreadCount = 0
    /// Masquerade Inbox DM threads with unread inbound messages.
    var masqueradeMessageUnreadCount = 0

    var totalMasqueradeUnread: Int {
        notificationUnreadCount + masqueradeMessageUnreadCount
    }

    var currentSpace: AnonymousSpace?
    var spacePosts: [AnonymousPost] = []
    var spacePostsCursor: String?
    var spacePostsLoading = false
    var spacePostsLoadingMore = false
    var spacePostsHasMore = true

    var composerTitle: String = ""
    var composerBody: String = ""
    /// Bumps after a successful Space post so pickers/sheets can dismiss.
    var publishEpoch: Int = 0

    /// Single Masquerade NavigationStack path (Feed/Spaces/Search push into this).
    var navigationPath: [AnonymousRoute] = []
    /// Posts keyed for `.post(id:)` routes — keep full payloads out of NavigationPath.
    var postById: [String: AnonymousPost] = [:]

    var lastError: String?
    /// When false, Root shows the offline/empty screen without a red toast.
    var shouldToastLastError = true
    var blockedProfileIds: Set<String> = []
    /// Soft re-entry — avoid full session await on every Masquerade tab hop.
    private var lastBootstrapAt: Date = .distantPast
    /// Session soft-skip window (feed reshuffle is separate — see `feedReshuffleInterval`).
    private let softBootstrapInterval: TimeInterval = 90
    /// Last time For you was replaced with a newly ranked first page.
    private var lastFeedReplaceAt: Date = .distantPast
    /// Minimum gap between automatic open-reshuffles (pull-to-refresh always reshuffles).
    private let feedReshuffleInterval: TimeInterval = 12

    /// Stable Masquerade handle for Me — never swap for a regenerated suggestion.
    var displayUsername: String {
        if let pinned = UserDefaults.standard.string(forKey: pinnedUsernameKey), !pinned.isEmpty {
            return pinned
        }
        return session.profile?.username ?? suggestedUsername
    }

    private init() {
        loadCachedSession()
        loadCachedFeed()
        showWildeEpigraph = !UserDefaults.standard.bool(forKey: wildeSeenKey)
    }

    // MARK: - Navigation

    /// Push Space detail onto the Masquerade stack (does not fetch — detail view loads).
    func pushSpace(slug: String) {
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if navigationPath.last == .space(slug: trimmed) { return }
        // Replace the array — in-place `append` hid the tab bar via observation but
        // left NavigationStack without a visible destination (blank Masquerade push).
        navigationPath = navigationPath + [.space(slug: trimmed)]
    }

    /// Push Post thread onto the Masquerade stack.
    func pushPost(_ post: AnonymousPost) {
        let id = post.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        postById[id] = post
        // Prefetch comments before the detail view appears.
        AnonymousCommentsWarmCache.shared.warm(id)
        // Avoid duplicate top-of-stack pushes from double taps.
        if navigationPath.last == .post(id: id) { return }
        navigationPath = navigationPath + [.post(id: id)]
    }

    /// Push by id when we only have a notification / deep-link reference.
    func pushPostId(_ id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        AnonymousCommentsWarmCache.shared.warm(trimmed)
        if navigationPath.last == .post(id: trimmed) { return }
        navigationPath = navigationPath + [.post(id: trimmed)]
    }

    /// Open a Masquerade anonymous profile by handle (`@name` or `name`).
    func pushProfile(username: String) {
        let trimmed = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !trimmed.isEmpty else { return }
        // Official Matterya is not an anonymous handle — leave to Messages / public profile.
        if trimmed.lowercased() == "matterya" { return }
        if case .profile(let current) = navigationPath.last,
           current.lowercased() == trimmed.lowercased() {
            return
        }
        navigationPath = navigationPath + [.profile(username: trimmed)]
    }

    /// Open a Masquerade inbox thread **inside** Masquerade (never jumps to the Messages tab).
    func pushConversation(id: String, seed: Conversation? = nil) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let seed {
            MessagesService.shared.storeConversation(seed)
        }
        if case .conversation(let current) = navigationPath.last, current == trimmed {
            return
        }
        // Drop any prior conversation push so Back always lands on Inbox.
        navigationPath = navigationPath.filter {
            if case .conversation = $0 { return false }
            return true
        } + [.conversation(id: trimmed)]
    }

    func post(forId id: String) -> AnonymousPost? {
        let key = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        if let cached = postById[key] { return cached }
        if let hit = feed.first(where: { $0.id == key }) {
            postById[key] = hit
            return hit
        }
        if let hit = spacePosts.first(where: { $0.id == key }) {
            postById[key] = hit
            return hit
        }
        return nil
    }

    /// Drop a photo post whose media failed to decode (HTML scrape poison as .jpg).
    /// Context without the image is useless — remove from every local list and pop the thread.
    func removeBrokenPhotoPost(id: String) {
        let key = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        feed.removeAll { $0.id == key }
        spacePosts.removeAll { $0.id == key }
        postById.removeValue(forKey: key)
        if case .post(let top) = navigationPath.last, top == key {
            navigationPath = Array(navigationPath.dropLast())
        } else {
            navigationPath = navigationPath.filter {
                if case .post(let pid) = $0 { return pid != key }
                return true
            }
        }
        cacheFeed(feed, cursor: feedCursor)
    }

    /// Keep feed / space / detail caches in sync after a fresh GET (e.g. re-signed media).
    /// Preserves existing media URLs when the incoming post has none — a getPost
    /// decode miss must not wipe images already painted on feed/space cards.
    func rememberPost(_ post: AnonymousPost) {
        let merged = mergePreservingMedia(incoming: post, existing: postById[post.id]
            ?? feed.first(where: { $0.id == post.id })
            ?? spacePosts.first(where: { $0.id == post.id }))
        postById[merged.id] = merged
        if let idx = feed.firstIndex(where: { $0.id == merged.id }) {
            feed[idx] = mergePreservingMedia(incoming: merged, existing: feed[idx])
        }
        if let idx = spacePosts.firstIndex(where: { $0.id == merged.id }) {
            spacePosts[idx] = mergePreservingMedia(incoming: merged, existing: spacePosts[idx])
        }
    }

    private func mergePreservingMedia(incoming: AnonymousPost, existing: AnonymousPost?) -> AnonymousPost {
        guard let existing else { return incoming }
        var out = incoming
        let incomingMediaEmpty = out.mediaURL == nil || out.mediaURL?.isEmpty == true
        let existingMediaUsable = existing.mediaURL != nil && !(existing.mediaURL?.isEmpty ?? true)
        if incomingMediaEmpty, existingMediaUsable {
            out.mediaURL = existing.mediaURL
        }
        let incomingThumbEmpty = out.thumbURL == nil || out.thumbURL?.isEmpty == true
        let existingThumbUsable = existing.thumbURL != nil && !(existing.thumbURL?.isEmpty ?? true)
        if incomingThumbEmpty, existingThumbUsable {
            out.thumbURL = existing.thumbURL
        }
        if out.mediaType == nil, let keep = existing.mediaType {
            out.mediaType = keep
        }
        return out
    }

    func popNavigation() {
        guard !navigationPath.isEmpty else { return }
        navigationPath = Array(navigationPath.dropLast())
    }

    func resetNavigation() {
        guard !navigationPath.isEmpty else { return }
        navigationPath = []
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        if phase == .loading {
            applySession(session, animated: false)
        }
        // Already ready with feed painted — skip session storm, still rotate For you.
        if phase == .ready, !feed.isEmpty,
           Date().timeIntervalSince(lastBootstrapAt) < softBootstrapInterval {
            await reshuffleFeedOnOpen()
            return
        }
        await refreshSession()
        lastBootstrapAt = Date()
        if phase == .ready {
            await reshuffleFeedOnOpen()
        }
    }

    func refreshSession() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Cached ready session: start feed immediately so Masquerade isn't blocked on /session.
        let feedTask: Task<Void, Never>? = {
            guard phase == .ready else { return nil }
            return Task { await self.reshuffleFeedOnOpen() }
        }()

        do {
            let remote = try await AnonymousService.session()
            applySession(remote, animated: true)
            cacheSession(remote)
            if phase == .ready {
                if let feedTask {
                    await feedTask.value
                } else {
                    await loadFeed(force: feed.isEmpty || isFeedCacheStale())
                }
                Task(priority: .utility) {
                    await loadSpaces(filter: activeSpaceFilter, force: false)
                }
            } else {
                feedTask?.cancel()
            }
        } catch let err as AnonymousError {
            if let feedTask, phase == .ready || session.profile != nil {
                await feedTask.value
            }
            handleGateError(err)
        } catch {
            // Prefer cached ready session over offline flash on cold timeout.
            if session.profile != nil {
                withAnimation(MatteryaMotion.snappy) { phase = .ready }
                noteSoftNetworkError(
                    AnonymousError.network(error.localizedDescription).errorDescription
                )
                if let feedTask {
                    await feedTask.value
                } else {
                    await loadFeed(force: false)
                }
                Task(priority: .utility) {
                    await loadSpaces(filter: activeSpaceFilter, force: false)
                }
            } else if phase == .loading {
                feedTask?.cancel()
                withAnimation(MatteryaMotion.snappy) { phase = .offline }
                shouldToastLastError = false
                lastError = AnonymousError.network(error.localizedDescription).errorDescription
            } else {
                feedTask?.cancel()
                noteSoftNetworkError(
                    AnonymousError.network(error.localizedDescription).errorDescription
                )
            }
        }
    }

    func attest() async {
        guard !isAttesting else { return }
        isAttesting = true
        defer { isAttesting = false }
        do {
            // Attest endpoint returns a partial payload — always re-fetch /session after.
            _ = try await AnonymousService.attest()
            await refreshSession()
        } catch let err as AnonymousError {
            lastError = err.errorDescription
            handleGateError(err)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func regenerateUsername() async {
        do {
            let name = try await AnonymousService.suggestUsername()
            withAnimation(MatteryaMotion.micro) {
                suggestedUsername = name
            }
        } catch {
            // Local safe fallback when suggest endpoint is thin.
            suggestedUsername = Self.localSafeUsername()
        }
    }

    func claimUsername() async {
        guard !isClaimingUsername else { return }
        let candidate = suggestedUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        isClaimingUsername = true
        defer { isClaimingUsername = false }
        do {
            let profile = try await AnonymousService.claimProfile(username: candidate)
            // Pin the handle we claimed — Me must not drift to a later suggestion/regen.
            UserDefaults.standard.set(profile.username, forKey: pinnedUsernameKey)
            var next = session
            next.profile = profile
            next.suggestedUsername = profile.username
            // Claim is only reachable after attest — keep gate ready for Spaces load.
            next.ageAttested = true
            applySession(next, animated: true)
            cacheSession(next)
            suggestedUsername = profile.username
            markWildeSeenIfReady()
            // Soft-load catalog; empty Spaces is fine — don't toast as "API unreachable".
            shouldToastLastError = false
            await refreshSession()
            // Re-assert pinned profile if a thin session payload omitted it.
            if session.profile == nil {
                var patched = session
                patched.profile = profile
                applySession(patched, animated: false)
                cacheSession(patched)
            }
            // New name → welcome letter → Space picker → Feed.
            if !hasCompletedWelcomeLetter {
                withAnimation(MatteryaMotion.snappy) { phase = .welcomeLetter }
            } else if !hasCompletedSpacesOnboarding {
                withAnimation(MatteryaMotion.snappy) { phase = .pickSpaces }
                await loadSpaces(filter: .forYou, force: true)
                await loadSpaces(filter: .popular, force: true)
            } else {
                await loadFeed(force: true)
                await loadSpaces(filter: .joined, force: true)
            }
            lastError = nil
        } catch let err as AnonymousError {
            shouldToastLastError = true
            lastError = err.errorDescription
            if case .usernameTaken = err {
                await regenerateUsername()
            }
        } catch {
            shouldToastLastError = true
            lastError = error.localizedDescription
        }
    }

    func markWildeSeenIfReady() {
        guard phase == .ready || phase == .welcomeLetter || phase == .pickSpaces || session.profile != nil else { return }
        UserDefaults.standard.set(true, forKey: wildeSeenKey)
        withAnimation(MatteryaMotion.snappy) { showWildeEpigraph = false }
    }

    var hasCompletedWelcomeLetter: Bool {
        UserDefaults.standard.bool(forKey: welcomeLetterSeenKey)
    }

    var hasCompletedSpacesOnboarding: Bool {
        UserDefaults.standard.bool(forKey: spacesOnboardingSeenKey)
    }

    func completeWelcomeLetter() {
        UserDefaults.standard.set(true, forKey: welcomeLetterSeenKey)
        if !hasCompletedSpacesOnboarding {
            withAnimation(MatteryaMotion.snappy) { phase = .pickSpaces }
            Task {
                await loadSpaces(filter: .forYou, force: true)
                await loadSpaces(filter: .popular, force: true)
            }
        } else {
            completeSpacesOnboarding()
        }
    }

    /// Spaces shown on the first-time join picker (For you, then popular fill).
    /// Includes already-joined so the Join button can flip to Joined in place.
    var spacesOnboardingCandidates: [AnonymousSpace] {
        var seen = Set<String>()
        var out: [AnonymousSpace] = []
        for space in (spacesByFilter[.forYou] ?? []) + (spacesByFilter[.popular] ?? []) + (spacesByFilter[.free] ?? []) {
            guard !space.isPaid else { continue }
            guard seen.insert(space.id).inserted else { continue }
            out.append(space)
            if out.count >= 24 { break }
        }
        return out
    }

    func completeSpacesOnboarding() {
        UserDefaults.standard.set(true, forKey: spacesOnboardingSeenKey)
        withAnimation(MatteryaMotion.snappy) { phase = .ready }
        Task {
            await loadFeed(force: true)
            await loadSpaces(filter: .joined, force: true)
            await loadSpaces(filter: .forYou, force: false)
        }
    }

    @discardableResult
    func joinSpace(_ space: AnonymousSpace) async -> Bool {
        await ensureJoined(space)
    }

    // MARK: - Spaces

    func loadSpaces(filter: AnonymousSpaceFilter, force: Bool = false) async {
        if !force, let cached = spacesByFilter[filter], !cached.isEmpty { return }
        spacesLoading[filter] = true
        defer { spacesLoading[filter] = false }
        do {
            let page = try await AnonymousService.listSpaces(filter: filter)
            withAnimation(MatteryaMotion.insert) {
                spacesByFilter[filter] = page.items
                spacesCursor[filter] = page.nextCursor
            }
        } catch let err as AnonymousError {
            if case .paidDisabled = err, filter == .paid {
                spacesByFilter[filter] = []
            } else if spacesByFilter[filter]?.isEmpty != false {
                spacesByFilter[filter] = spacesByFilter[filter] ?? []
                noteSoftNetworkError(err.errorDescription)
            }
        } catch {
            if spacesByFilter[filter]?.isEmpty != false {
                spacesByFilter[filter] = spacesByFilter[filter] ?? []
                noteSoftNetworkError(error.localizedDescription)
            }
        }
    }

    func refreshSpaces() async {
        await loadSpaces(filter: activeSpaceFilter, force: true)
    }

    func openSpace(slug: String) async {
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let needle = trimmed.lowercased()

        // Paint chrome immediately from any cached directory hit — don't wait on /space.
        let alreadyOpen = currentSpace?.slug == trimmed || currentSpace?.normalizedSlug == needle
        if !alreadyOpen {
            func matches(_ space: AnonymousSpace) -> Bool {
                space.slug == trimmed || space.normalizedSlug == needle
            }
            let known =
                (spacesByFilter[.forYou] ?? []).first(where: matches)
                ?? (spacesByFilter[.popular] ?? []).first(where: matches)
                ?? (spacesByFilter[.joined] ?? []).first(where: matches)
                ?? spacesByFilter.values.flatMap { $0 }.first(where: matches)
            if let known {
                withAnimation(MatteryaMotion.snappy) { currentSpace = known }
            }
            // Clear previous space's posts so we don't flash the wrong room.
            spacePosts = []
            spacePostsCursor = nil
            spacePostsHasMore = true
        }

        spacePostsLoading = true
        defer { spacePostsLoading = false }
        do {
            // If we already have the space id, fetch posts in parallel with a soft meta refresh.
            if let cached = currentSpace, cached.slug == trimmed || cached.normalizedSlug == needle,
               !cached.id.isEmpty {
                async let metaTask: AnonymousSpace? = {
                    try? await AnonymousService.space(slug: trimmed)
                }()
                async let pageTask = AnonymousService.listPosts(
                    spaceId: cached.id,
                    sort: .new,
                    limit: AnonymousService.spacePostsPageLimit
                )
                let page = try await pageTask
                if let fresh = await metaTask {
                    withAnimation(MatteryaMotion.snappy) { currentSpace = fresh }
                }
                for item in page.items { postById[item.id] = item }
                let spaceOwn = mergeOwnRecentPosts(into: page.items).filter {
                    $0.spaceId == (currentSpace?.id ?? cached.id)
                }
                spacePosts = spaceOwn
                spacePostsCursor = page.nextCursor
                spacePostsHasMore = page.nextCursor != nil
                return
            }

            let space = try await AnonymousService.space(slug: trimmed)
            withAnimation(MatteryaMotion.snappy) { currentSpace = space }
            // Chronological + cursor — Hot/score order breaks keyset pagination.
            let page = try await AnonymousService.listPosts(
                spaceId: space.id,
                sort: .new,
                limit: AnonymousService.spacePostsPageLimit
            )
            for item in page.items {
                postById[item.id] = item
            }
            let spaceOwn = mergeOwnRecentPosts(into: page.items).filter { $0.spaceId == space.id }
            spacePosts = spaceOwn
            spacePostsCursor = page.nextCursor
            spacePostsHasMore = page.nextCursor != nil
        } catch let err as AnonymousError {
            lastError = err.errorDescription
            shouldToastLastError = currentSpace?.slug != trimmed
        } catch {
            lastError = error.localizedDescription
            shouldToastLastError = currentSpace?.slug != trimmed
        }
    }

    /// Endless Space posts — append next chronological page.
    func loadMoreSpacePosts() async {
        guard let space = currentSpace else { return }
        guard !spacePostsLoading, !spacePostsLoadingMore else { return }
        guard spacePostsHasMore, let cursor = spacePostsCursor, !cursor.isEmpty else { return }
        spacePostsLoadingMore = true
        defer { spacePostsLoadingMore = false }
        do {
            let page = try await AnonymousService.listPosts(
                spaceId: space.id,
                cursor: cursor,
                sort: .new,
                limit: AnonymousService.spacePostsPageLimit
            )
            var seen = Set(spacePosts.map(\.id))
            var appended: [AnonymousPost] = []
            for item in page.items where seen.insert(item.id).inserted {
                postById[item.id] = item
                appended.append(item)
            }
            if !appended.isEmpty {
                spacePosts.append(contentsOf: appended)
            }
            spacePostsCursor = page.nextCursor
            spacePostsHasMore = page.nextCursor != nil && !page.items.isEmpty
        } catch {
            // Soft — keep what we have; user can scroll again.
            spacePostsHasMore = spacePostsCursor != nil
        }
    }

    @discardableResult
    func joinCurrentSpace() async -> Bool {
        guard let space = currentSpace else { return false }
        return await ensureJoined(space)
    }

    /// Join a Space when needed so POST / COMMENT succeed (API requires membership).
    @discardableResult
    func ensureJoined(_ space: AnonymousSpace) async -> Bool {
        if space.isJoined == true {
            if currentSpace?.id == space.id {
                currentSpace?.isJoined = true
            }
            return true
        }
        if space.isPaid {
            lastError = AnonymousError.paidDisabled.errorDescription
            return false
        }
        do {
            _ = try await AnonymousService.join(spaceId: space.id)
            if currentSpace?.id == space.id {
                currentSpace?.isJoined = true
                currentSpace?.memberCount = (currentSpace?.memberCount ?? 0) + 1
            }
            markJoinedLocally(spaceId: space.id, slug: space.slug)
            await loadSpaces(filter: .joined, force: true)
            return true
        } catch let err as AnonymousError {
            lastError = err.errorDescription
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func markJoinedLocally(spaceId: String, slug: String) {
        for key in spacesByFilter.keys {
            guard var list = spacesByFilter[key] else { continue }
            if let idx = list.firstIndex(where: { $0.id == spaceId || $0.slug == slug }) {
                list[idx].isJoined = true
                spacesByFilter[key] = list
            }
        }
    }

    func leaveCurrentSpace() async {
        guard let space = currentSpace else { return }
        do {
            try await AnonymousService.leave(spaceId: space.id)
            currentSpace?.isJoined = false
            if let count = currentSpace?.memberCount {
                currentSpace?.memberCount = max(0, count - 1)
            }
            await loadSpaces(filter: .joined, force: true)
        } catch let err as AnonymousError {
            lastError = err.errorDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    func createSpace(_ input: AnonymousCreateSpaceInput) async -> AnonymousSpace? {
        if input.admission != AnonymousSpaceAdmission.free.rawValue {
            lastError = AnonymousError.paidDisabled.errorDescription
            return nil
        }
        do {
            var space = try await AnonymousService.createSpace(input)
            // Owner is joined on create — keep local lists honest even if reload is slow.
            space.isJoined = true
            space.isOwner = true
            prependSpace(space, into: [.newest, .joined, .forYou, .popular, .free])
            activeSpaceFilter = .joined
            await loadSpaces(filter: .newest, force: true)
            await loadSpaces(filter: .joined, force: true)
            return space
        } catch let err as AnonymousError {
            lastError = err.errorDescription
            return nil
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private func prependSpace(_ space: AnonymousSpace, into filters: [AnonymousSpaceFilter]) {
        for filter in filters {
            var list = spacesByFilter[filter] ?? []
            list.removeAll { $0.id == space.id || $0.slug == space.slug }
            list.insert(space, at: 0)
            spacesByFilter[filter] = list
        }
    }

    // MARK: - Feed / posts

    func loadFeed(force: Bool = false) async {
        if !force, !feed.isEmpty, !isFeedCacheStale() { return }
        if let existing = feedLoadTask {
            await existing.value
            if !force, !feed.isEmpty, !isFeedCacheStale() { return }
        }
        let task = Task { @MainActor in
            await self.performLoadFeed(force: force || isFeedCacheStale())
        }
        feedLoadTask = task
        await task.value
        if feedLoadTask != nil {
            feedLoadTask = nil
        }
    }

    /// Remember cards the user already saw so the next ranked page can skip them.
    func markFeedPostSeen(_ id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sessionSeenFeedIds.insert(trimmed)
    }

    /// Background reshuffle only when the list is empty (cache miss).
    func softRefreshFeedIfStale() async {
        guard !feedLoading else { return }
        guard feed.isEmpty else { return }
        guard isFeedCacheStale() else { return }
        await loadFeed(force: true)
    }

    /// Open / re-enter Masquerade → fetch a new For you page and replace the list
    /// (unless the user is mid-fling). Instant disk paint stays until network returns.
    func reshuffleFeedOnOpen() async {
        guard !feedLoading else { return }
        if !feed.isEmpty, ScrollBudget.isFlinging {
            return
        }
        let due =
            feed.isEmpty
            || isFeedCacheStale()
            || Date().timeIntervalSince(lastFeedReplaceAt) >= feedReshuffleInterval
        guard due else { return }
        allowFeedReplace = true
        defer { allowFeedReplace = false }
        await loadFeed(force: true)
    }

    private func performLoadFeed(force: Bool) async {
        if !force, !feed.isEmpty, !isFeedCacheStale() { return }
        let showSpinner = feed.isEmpty
        if showSpinner { feedLoading = true }
        defer { if showSpinner { feedLoading = false } }
        do {
            let page = try await fetchFeedPageWithRetry()
            for item in page.items {
                postById[item.id] = item
            }
            // Prefer never-seen this session / last open's head. Falling back to the full
            // page re-stuck the same 98k-upvote viral card at index 0 every refresh.
            let lastHead = Set(UserDefaults.standard.stringArray(forKey: lastFeedHeadKey) ?? [])
            let suppress = sessionSeenFeedIds.union(lastHead)
            let fresh = page.items.filter { !suppress.contains($0.id) }
            let preferred: [AnonymousPost]
            if fresh.count >= min(6, max(1, page.items.count / 2)) {
                preferred = fresh
            } else if !fresh.isEmpty {
                // Keep fresh at the front; top up from session-unseen only.
                var seen = Set(fresh.map(\.id))
                var mixed = fresh
                for item in page.items where !sessionSeenFeedIds.contains(item.id) && seen.insert(item.id).inserted {
                    mixed.append(item)
                    if mixed.count >= page.items.count { break }
                }
                preferred = mixed.isEmpty ? page.items : mixed
            } else {
                // Everything already seen — still demote last head to the tail.
                let head = page.items.filter { lastHead.contains($0.id) }
                let rest = page.items.filter { !lastHead.contains($0.id) }
                preferred = rest + head
            }
            var merged = mergeOwnRecentPosts(into: preferred)
            // Never let a thin ranked page wipe a healthy feed (ledger exhaustion).
            if merged.count < 6, feed.count > merged.count {
                let incomingIds = Set(merged.map(\.id))
                let keep = feed.filter { !incomingIds.contains($0.id) && !sessionSeenFeedIds.contains($0.id) }
                let keepAny = keep.isEmpty
                    ? feed.filter { !incomingIds.contains($0.id) }
                    : keep
                merged = mergeOwnRecentPosts(into: Array((merged + keepAny).prefix(48)))
            }
            for item in merged {
                sessionSeenFeedIds.insert(item.id)
            }
            rememberFeedHead(merged)
            // Mid-fling only: soft-append unseen — never replace under the finger.
            // Open/re-entry and pull-to-refresh set `allowFeedReplace` so tops rotate.
            let midScroll = !feed.isEmpty && !allowFeedReplace && ScrollBudget.isFlinging
            if midScroll {
                var seen = Set(feed.map(\.id))
                let extras = merged.filter { seen.insert($0.id).inserted }
                if !extras.isEmpty {
                    feed.append(contentsOf: extras.prefix(24))
                }
                feedCursor = page.nextCursor
                feedHasMore = true
            } else {
                withAnimation(MatteryaMotion.snappy) {
                    feed = merged
                    feedCursor = page.nextCursor
                    feedHasMore = true
                }
                lastFeedReplaceAt = Date()
            }
            cacheFeed(feed, cursor: feedCursor)
            // Clear soft timeout copy once paint succeeds.
            if lastError != nil, shouldToastLastError == false {
                lastError = nil
            }
        } catch let err as AnonymousError {
            // Keep any painted / cached cards — timeout must not wipe to "Nothing in your feed".
            if feed.isEmpty {
                noteSoftNetworkError(err.errorDescription)
            }
        } catch {
            if feed.isEmpty {
                noteSoftNetworkError(error.localizedDescription)
            }
        }
    }

    /// Endless append — prefetch ahead of the tail; soft-recycle when cursor/ledger thin.
    func loadMoreFeed() async {
        guard !feedLoading, !feedLoadingMore else { return }
        if feed.count >= AnonymousService.feedSoftCap {
            feedHasMore = true
            // Trim oldest painted cards so RAM stays light while scroll stays endless.
            let keep = Array(feed.suffix(600))
            feed = keep
        }
        feedLoadingMore = true
        defer { feedLoadingMore = false }
        var hops = 0
        while hops < 4 {
            hops += 1
            let cursor = feedCursor
            do {
                let page = try await AnonymousService.feed(
                    sort: feedSort,
                    cursor: (cursor?.isEmpty == false) ? cursor : nil,
                    limit: AnonymousService.feedPageLimit
                )
                var seen = Set(feed.map(\.id))
                // Soft recycle may re-serve session-seen — still skip what's on screen now.
                var appended: [AnonymousPost] = []
                for item in page.items where seen.insert(item.id).inserted {
                    postById[item.id] = item
                    sessionSeenFeedIds.insert(item.id)
                    appended.append(item)
                }
                feedCursor = page.nextCursor
                if !appended.isEmpty {
                    feed.append(contentsOf: appended)
                    feedHasMore = true
                    cacheFeed(feed, cursor: feedCursor)
                    return
                }
                // All duplicates — advance cursor, or restart from a fresh ranked page.
                if let next = page.nextCursor, next != cursor {
                    feedCursor = next
                    feedHasMore = true
                    continue
                }
                // Cursor exhausted — clear suppress so soft-recycle can refill endlessly.
                if hops >= 2 {
                    sessionSeenFeedIds = Set(feed.suffix(24).map(\.id))
                    feedCursor = nil
                }
                feedHasMore = true
            } catch {
                feedHasMore = true
                return
            }
        }
        feedHasMore = true
        cacheFeed(feed, cursor: feedCursor)
    }

    private func isFeedCacheStale() -> Bool {
        let saved = UserDefaults.standard.double(forKey: feedCacheSavedAtKey)
        guard saved > 0 else { return !feed.isEmpty }
        return Date().timeIntervalSince1970 - saved > feedCacheMaxAge
    }

    /// One retry covers Render cold wakes / device -1001 without doubling every success path.
    private func fetchFeedPageWithRetry() async throws -> AnonymousPage<AnonymousPost> {
        do {
            return try await AnonymousService.feed(
                sort: feedSort,
                limit: AnonymousService.feedPageLimit
            )
        } catch let err as AnonymousError {
            guard case .network = err else { throw err }
            try await Task.sleep(nanoseconds: 400_000_000)
            return try await AnonymousService.feed(
                sort: feedSort,
                limit: AnonymousService.feedPageLimit
            )
        } catch {
            try await Task.sleep(nanoseconds: 400_000_000)
            return try await AnonymousService.feed(
                sort: feedSort,
                limit: AnonymousService.feedPageLimit
            )
        }
    }

    /// Soft network noise (timeouts) — show only when the surface is empty.
    private func noteSoftNetworkError(_ message: String?) {
        guard let message, !message.isEmpty else { return }
        shouldToastLastError = false
        lastError = message
    }

    func refreshFeed() async {
        for post in feed.prefix(60) {
            sessionSeenFeedIds.insert(post.id)
        }
        allowFeedReplace = true
        defer { allowFeedReplace = false }
        await loadFeed(force: true)
    }

    func loadInbox(force: Bool = false) async {
        if !force, !inbox.isEmpty {
            await refreshMasqueradeMessageUnread()
            syncMasqueradeBadge()
            return
        }
        inboxLoading = true
        defer { inboxLoading = false }
        do {
            let page = try await AnonymousService.notifications()
            withAnimation(MatteryaMotion.insert) {
                inbox = page.items
                inboxCursor = page.nextCursor
                notificationUnreadCount = max(page.unreadCount, page.items.filter(\.isUnread).count)
            }
            await refreshMasqueradeMessageUnread()
            syncMasqueradeBadge()
        } catch let err as AnonymousError {
            lastError = err.errorDescription
            if inbox.isEmpty { inbox = [] }
            await refreshMasqueradeMessageUnread()
            syncMasqueradeBadge()
        } catch {
            lastError = error.localizedDescription
            if inbox.isEmpty { inbox = [] }
            await refreshMasqueradeMessageUnread()
            syncMasqueradeBadge()
        }
    }

    func refreshInbox() async {
        await loadInbox(force: true)
    }

    func markNotificationRead(_ item: AnonymousNotification) async {
        guard item.isUnread else { return }
        if let idx = inbox.firstIndex(where: { $0.id == item.id }) {
            var updated = inbox[idx]
            updated.readAt = ISO8601DateFormatter().string(from: Date())
            inbox[idx] = updated
            notificationUnreadCount = max(0, inbox.filter(\.isUnread).count)
            syncMasqueradeBadge()
        }
        _ = try? await AnonymousService.markNotificationRead(id: item.id)
        await loadInbox(force: true)
    }

    func markAllNotificationsRead() async {
        inbox = inbox.map { item in
            var copy = item
            if copy.readAt == nil {
                copy.readAt = ISO8601DateFormatter().string(from: Date())
            }
            return copy
        }
        notificationUnreadCount = 0
        syncMasqueradeBadge()
        _ = try? await AnonymousService.markAllNotificationsRead()
    }

    func refreshMasqueradeMessageUnread() async {
        do {
            let page = try await MessagesService.shared.listConversations(
                limit: 40,
                forceNetwork: true,
                inbox: "masquerade"
            )
            let me = AuthService.shared.currentUser?.id
            let unread = page.reduce(0) { partial, conversation in
                guard let me else { return partial }
                return partial + (conversation.hasUnread(for: me) ? 1 : 0)
            }
            masqueradeMessageUnreadCount = unread
            syncMasqueradeBadge()
        } catch {
            // Keep last known count — badge must not clear on a flaky inbox probe.
        }
    }

    private func syncMasqueradeBadge() {
        // AppState owns the bottom-tab red dot; keep it in sync whenever Masquerade unread changes.
        NotificationCenter.default.post(
            name: .masqueradeUnreadDidChange,
            object: nil,
            userInfo: ["count": totalMasqueradeUnread]
        )
    }

    func publishPost(
        spaceId: String,
        mediaType: String? = nil,
        mediaURL: String? = nil,
        thumbURL: String? = nil
    ) async -> AnonymousPost? {
        let title = composerTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = composerBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasMedia = !(mediaURL ?? "").isEmpty
        guard !body.isEmpty || !title.isEmpty || hasMedia else {
            lastError = "Write something or attach a photo/video."
            return nil
        }

        // API requires membership — join first when we know the Space.
        if let space = currentSpace, space.id == spaceId {
            if await ensureJoined(space) == false { return nil }
        } else if let known = spacesByFilter.values.flatMap({ $0 }).first(where: { $0.id == spaceId }) {
            if await ensureJoined(known) == false { return nil }
        } else {
            do {
                _ = try await AnonymousService.join(spaceId: spaceId)
            } catch let err as AnonymousError {
                // Decoding can fail on a thin membership payload; the join may still have landed.
                if case .decoding = err {
                    /* continue to create */
                } else {
                    lastError = err.errorDescription
                    return nil
                }
            } catch {
                lastError = error.localizedDescription
                return nil
            }
        }

        let input = AnonymousCreatePostInput(
            title: title.isEmpty ? nil : title,
            body: body,
            mediaType: mediaType,
            mediaURL: mediaURL,
            thumbURL: thumbURL
        )

        do {
            return try await finishPublish(spaceId: spaceId, input: input)
        } catch let err as AnonymousError {
            // One retry: join then create (covers not_member / race).
            if case .forbidden = err {
                do {
                    _ = try await AnonymousService.join(spaceId: spaceId)
                } catch {
                    /* still attempt create */
                }
                do {
                    return try await finishPublish(spaceId: spaceId, input: input)
                } catch let retryErr as AnonymousError {
                    lastError = retryErr.errorDescription
                    return nil
                } catch {
                    lastError = error.localizedDescription
                    return nil
                }
            }
            lastError = err.errorDescription
            return nil
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private func finishPublish(spaceId: String, input: AnonymousCreatePostInput) async throws -> AnonymousPost {
        var post = try await AnonymousService.createPost(spaceId: spaceId, input: input)
        // If the server echo lost media, keep the URLs we just uploaded so the card paints.
        if (post.mediaURL == nil || post.mediaURL?.isEmpty == true),
           let keep = input.mediaURL, !keep.isEmpty {
            post.mediaURL = keep
            post.mediaType = post.mediaType ?? input.mediaType
        }
        if (post.thumbURL == nil || post.thumbURL?.isEmpty == true),
           let keep = input.thumbURL, !keep.isEmpty {
            post.thumbURL = keep
        }
        composerTitle = ""
        composerBody = ""
        spacePosts.insert(post, at: 0)
        feed.removeAll { $0.id == post.id }
        feed.insert(post, at: 0)
        postById[post.id] = post
        if currentSpace?.id == spaceId {
            currentSpace?.postCount = (currentSpace?.postCount ?? 0) + 1
        }
        // Persist so soft-refresh doesn't treat the feed as stale and wipe this post.
        cacheFeed(feed, cursor: feedCursor)
        rememberOwnRecentPost(post.id)
        publishEpoch += 1
        return post
    }

    private let ownRecentPostIdsKey = "matterya.anonymous.ownRecentPosts.v1"
    private let ownRecentPostsBlobKey = "matterya.anonymous.ownRecentPosts.blob.v1"

    private func rememberOwnRecentPost(_ id: String) {
        var ids = UserDefaults.standard.stringArray(forKey: ownRecentPostIdsKey) ?? []
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
        UserDefaults.standard.set(Array(ids.prefix(20)), forKey: ownRecentPostIdsKey)
        // Persist the full card (incl. media) so ranked refresh cannot drop image/URL.
        if let post = postById[id] ?? feed.first(where: { $0.id == id }) ?? spacePosts.first(where: { $0.id == id }) {
            cacheOwnRecentPostBlob(post)
        }
    }

    private func ownRecentPostIds() -> [String] {
        UserDefaults.standard.stringArray(forKey: ownRecentPostIdsKey) ?? []
    }

    private func cacheOwnRecentPostBlob(_ post: AnonymousPost) {
        var blobs = loadOwnRecentPostBlobs()
        blobs.removeAll { $0.id == post.id }
        blobs.insert(post, at: 0)
        blobs = Array(blobs.prefix(20))
        if let data = try? JSONEncoder().encode(blobs) {
            UserDefaults.standard.set(data, forKey: ownRecentPostsBlobKey)
        }
    }

    private func loadOwnRecentPostBlobs() -> [AnonymousPost] {
        guard let data = UserDefaults.standard.data(forKey: ownRecentPostsBlobKey),
              let posts = try? JSONDecoder().decode([AnonymousPost].self, from: data)
        else { return [] }
        return posts
    }

    /// Keep the viewer's freshly published posts near the top for a short window only.
    /// Longer sticky own-posts were freezing For you under the algorithm.
    private static let ownRecentPinMaxAge: TimeInterval = 2 * 60 * 60

    private func rememberFeedHead(_ posts: [AnonymousPost]) {
        let ids = Array(posts.prefix(12).map(\.id))
        guard !ids.isEmpty else { return }
        var merged = ids
        for old in UserDefaults.standard.stringArray(forKey: lastFeedHeadKey) ?? [] where !merged.contains(old) {
            merged.append(old)
            if merged.count >= 48 { break }
        }
        UserDefaults.standard.set(Array(merged.prefix(48)), forKey: lastFeedHeadKey)
    }

    private func mergeOwnRecentPosts(into items: [AnonymousPost]) -> [AnonymousPost] {
        let ownIds = Set(ownRecentPostIds())
        guard !ownIds.isEmpty else { return items }
        let blobs = Dictionary(uniqueKeysWithValues: loadOwnRecentPostBlobs().map { ($0.id, $0) })
        let now = Date()
        var kept: [AnonymousPost] = []
        var expiredIds: [String] = []
        for id in ownRecentPostIds() {
            let hit =
                postById[id]
                ?? feed.first(where: { $0.id == id })
                ?? spacePosts.first(where: { $0.id == id })
                ?? items.first(where: { $0.id == id })
                ?? blobs[id]
            guard var post = hit else {
                expiredIds.append(id)
                continue
            }
            if let created = RelativeTime.parseDate(post.createdAt),
               now.timeIntervalSince(created) > Self.ownRecentPinMaxAge {
                expiredIds.append(id)
                continue
            }
            // Prefer any non-empty media we still hold locally.
            if (post.mediaURL == nil || post.mediaURL?.isEmpty == true),
               let blob = blobs[id],
               let keep = blob.mediaURL, !keep.isEmpty {
                post.mediaURL = keep
                post.mediaType = post.mediaType ?? blob.mediaType
                post.thumbURL = post.thumbURL ?? blob.thumbURL
            }
            postById[post.id] = post
            kept.append(post)
            if kept.count >= 1 { break }
        }
        if !expiredIds.isEmpty {
            var ids = ownRecentPostIds().filter { !expiredIds.contains($0) }
            UserDefaults.standard.set(ids, forKey: ownRecentPostIdsKey)
            let alive = Set(ids)
            let pruned = loadOwnRecentPostBlobs().filter { alive.contains($0.id) }
            if let data = try? JSONEncoder().encode(pruned) {
                UserDefaults.standard.set(data, forKey: ownRecentPostsBlobKey)
            }
        }
        let pinnedIds = Set(kept.map(\.id))
        let rest = items.filter { !pinnedIds.contains($0.id) }
        return kept + rest
    }

    @discardableResult
    func vote(post: AnonymousPost, value: Int) async -> AnonymousPost? {
        do {
            let result = try await AnonymousService.vote(targetType: "post", targetId: post.id, value: value)
            var updated = post
            let prev = post.myVote ?? 0
            updated.myVote = result.value ?? value
            // Prefer server score. Fallback clamps a like↔dislike flip to ±1 (not ±2).
            if let serverScore = result.score {
                updated.score = serverScore
            } else {
                var delta = value - prev
                if delta > 1 { delta = 1 }
                if delta < -1 { delta = -1 }
                updated.score = (post.score ?? 0) + delta
            }
            rememberPost(updated)
            return updated
        } catch let err as AnonymousError {
            lastError = err.errorDescription
            return nil
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func voteComment(_ comment: AnonymousComment, value: Int) async -> AnonymousComment? {
        do {
            let result = try await AnonymousService.vote(targetType: "comment", targetId: comment.id, value: value)
            var updated = comment
            let prev = comment.myVote ?? 0
            updated.myVote = result.value ?? value
            if let serverScore = result.score {
                updated.score = serverScore
            } else {
                var delta = value - prev
                if delta > 1 { delta = 1 }
                if delta < -1 { delta = -1 }
                updated.score = (comment.score ?? 0) + delta
            }
            return updated
        } catch let err as AnonymousError {
            lastError = err.errorDescription
            return nil
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func report(targetType: String, targetId: String, reason: String) async {
        do {
            try await AnonymousService.report(targetType: targetType, targetId: targetId, reason: reason)
        } catch let err as AnonymousError {
            lastError = err.errorDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Returns true when the block landed (local lists updated + path can pop).
    @discardableResult
    func block(profileId: String) async -> Bool {
        let id = profileId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            lastError = "Missing profile to block."
            return false
        }
        do {
            try await AnonymousService.block(profileId: id)
            blockedProfileIds.insert(id)
            feed.removeAll { $0.authorProfileId == id }
            spacePosts.removeAll { $0.authorProfileId == id }
            // Drop any open thread for this author.
            if let top = navigationPath.last, case .post(let postId) = top,
               let post = post(forId: postId), post.authorProfileId == id {
                popNavigation()
            }
            return true
        } catch let err as AnonymousError {
            lastError = err.errorDescription
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func consumeError() -> String? {
        let msg = lastError
        lastError = nil
        shouldToastLastError = true
        return msg
    }

    // MARK: - Internals

    private func applySession(_ remote: AnonymousSession, animated: Bool) {
        var remote = remote
        // Never let a thin session wipe a claimed handle — Me identity must stay stable.
        if remote.profile == nil, let pinned = UserDefaults.standard.string(forKey: pinnedUsernameKey),
           !pinned.isEmpty, let existing = session.profile, existing.username == pinned {
            remote.profile = existing
        }
        if let profile = remote.profile {
            UserDefaults.standard.set(profile.username, forKey: pinnedUsernameKey)
        }
        session = remote
        // Suggestions only matter before claim — don't overwrite a claimed handle.
        if remote.profile == nil {
            if let suggested = remote.suggestedUsername, !suggested.isEmpty {
                suggestedUsername = suggested
            } else if suggestedUsername.isEmpty {
                suggestedUsername = Self.localSafeUsername()
            }
        } else {
            suggestedUsername = remote.profile?.username ?? suggestedUsername
        }

        let next: AnonymousPhase
        if remote.suspended {
            next = .suspended
        } else if remote.birthdateMissing || !remote.eligibleAdult {
            next = .gatedUnder18
        } else if !remote.ageAttested {
            next = .needAttest
        } else if remote.profile == nil {
            next = .needUsername
        } else if !UserDefaults.standard.bool(forKey: welcomeLetterSeenKey) {
            next = .welcomeLetter
        } else if !UserDefaults.standard.bool(forKey: spacesOnboardingSeenKey) {
            next = .pickSpaces
        } else {
            next = .ready
        }

        if animated {
            withAnimation(MatteryaMotion.snappy) { phase = next }
        } else {
            phase = next
        }

        // Wilde is onboarding-only: show through claim, then dismiss once ready.
        if next == .needAttest || next == .needUsername {
            if !UserDefaults.standard.bool(forKey: wildeSeenKey) {
                showWildeEpigraph = true
            }
        } else if next == .ready || next == .welcomeLetter || next == .pickSpaces {
            markWildeSeenIfReady()
        }

        if next == .pickSpaces {
            Task {
                await loadSpaces(filter: .forYou, force: false)
                await loadSpaces(filter: .popular, force: false)
            }
        }
    }

    private func handleGateError(_ err: AnonymousError) {
        switch err {
        case .under18:
            withAnimation(MatteryaMotion.snappy) { phase = .gatedUnder18 }
        case .unattested:
            withAnimation(MatteryaMotion.snappy) { phase = .needAttest }
        case .noProfile:
            withAnimation(MatteryaMotion.snappy) { phase = .needUsername }
        case .suspended:
            withAnimation(MatteryaMotion.snappy) { phase = .suspended }
        case .network, .notFound, .server, .decoding:
            // API not deployed / migration missing used to toast “That content isn’t available.”
            // Keep the offline screen only — no red toast for bootstrap failures.
            shouldToastLastError = false
            lastError = err.errorDescription
            if session.profile != nil {
                withAnimation(MatteryaMotion.snappy) { phase = .ready }
            } else {
                withAnimation(MatteryaMotion.snappy) { phase = .offline }
            }
        default:
            shouldToastLastError = true
            lastError = err.errorDescription
            if phase == .loading {
                withAnimation(MatteryaMotion.snappy) { phase = .offline }
            }
        }
    }

    private func loadCachedSession() {
        guard
            let data = UserDefaults.standard.data(forKey: cacheKey),
            let cached = try? JSONDecoder().decode(AnonymousSession.self, from: data)
        else { return }
        session = cached
        if let suggested = cached.suggestedUsername {
            suggestedUsername = suggested
        }
        applySession(cached, animated: false)
    }

    private func cacheSession(_ session: AnonymousSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    private struct CachedFeed: Codable {
        var items: [AnonymousPost]
        var cursor: String?
    }

    private func loadCachedFeed() {
        guard
            let data = UserDefaults.standard.data(forKey: feedCacheKey),
            let cached = try? JSONDecoder().decode(CachedFeed.self, from: data),
            !cached.items.isEmpty
        else { return }
        feed = cached.items
        feedCursor = cached.cursor
        feedHasMore = cached.cursor != nil
        for item in cached.items {
            postById[item.id] = item
        }
    }

    private func cacheFeed(_ items: [AnonymousPost], cursor: String?) {
        guard !items.isEmpty else { return }
        let payload = CachedFeed(items: items, cursor: cursor)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: feedCacheKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: feedCacheSavedAtKey)
    }

    private static let adjectives = [
        "quiet", "silver", "amber", "north", "misty", "calm", "hidden", "lunar",
        "soft", "ember", "cedar", "ivory", "coral", "velvet", "hollow", "brisk",
    ]
    private static let nouns = [
        "orbit", "harbor", "willow", "lantern", "meadow", "comet", "ridge", "folio",
        "current", "atlas", "ember", "pebble", "mirror", "signal", "grove", "cipher",
    ]

    static func localSafeUsername() -> String {
        let adj = adjectives.randomElement() ?? "quiet"
        let noun = nouns.randomElement() ?? "orbit"
        let suffix = Int.random(in: 1000...9999)
        return "\(adj)\(noun)_\(suffix)"
    }
}
