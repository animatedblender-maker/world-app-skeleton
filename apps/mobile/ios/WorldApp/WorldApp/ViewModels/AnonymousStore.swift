import Foundation
import Observation
import SwiftUI

enum AnonymousPhase: Equatable {
    case loading
    case gatedUnder18
    case needAttest
    case needUsername
    case ready
    case suspended
    case offline
}

@MainActor
@Observable
final class AnonymousStore {
    static let shared = AnonymousStore()

    private let cacheKey = "matterya.anonymous.session.v1"

    var phase: AnonymousPhase = .loading
    var session: AnonymousSession = .empty
    var suggestedUsername: String = ""
    var isClaimingUsername = false
    var isAttesting = false
    var isRefreshing = false

    var spacesByFilter: [AnonymousSpaceFilter: [AnonymousSpace]] = [:]
    var spacesCursor: [AnonymousSpaceFilter: String?] = [:]
    var spacesLoading: [AnonymousSpaceFilter: Bool] = [:]
    var activeSpaceFilter: AnonymousSpaceFilter = .forYou

    var feed: [AnonymousPost] = []
    var feedCursor: String?
    var feedSort: AnonymousFeedSort = .hot
    var feedLoading = false

    var currentSpace: AnonymousSpace?
    var spacePosts: [AnonymousPost] = []
    var spacePostsCursor: String?
    var spacePostsLoading = false

    var composerTitle: String = ""
    var composerBody: String = ""

    var lastError: String?
    var blockedProfileIds: Set<String> = []

    private init() {
        loadCachedSession()
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        if phase == .loading {
            applySession(session, animated: false)
        }
        await refreshSession()
    }

    func refreshSession() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let remote = try await AnonymousService.session()
            applySession(remote, animated: true)
            cacheSession(remote)
            if phase == .ready {
                async let spaces: () = loadSpaces(filter: activeSpaceFilter, force: false)
                async let feedTask: () = loadFeed(force: false)
                _ = await (spaces, feedTask)
            }
        } catch let err as AnonymousError {
            handleGateError(err)
        } catch {
            if session.profile != nil {
                withAnimation(MatteryaMotion.snappy) { phase = .ready }
            } else if phase == .loading {
                withAnimation(MatteryaMotion.snappy) { phase = .offline }
            }
            lastError = AnonymousError.network(error.localizedDescription).errorDescription
        }
    }

    func attest() async {
        guard !isAttesting else { return }
        isAttesting = true
        defer { isAttesting = false }
        do {
            let remote = try await AnonymousService.attest()
            applySession(remote, animated: true)
            cacheSession(remote)
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
            var next = session
            next.profile = profile
            next.suggestedUsername = profile.username
            applySession(next, animated: true)
            cacheSession(next)
            await loadSpaces(filter: .forYou, force: true)
            await loadFeed(force: true)
        } catch let err as AnonymousError {
            lastError = err.errorDescription
            if case .usernameTaken = err {
                await regenerateUsername()
            }
        } catch {
            lastError = error.localizedDescription
        }
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
            } else {
                lastError = err.errorDescription
                if spacesByFilter[filter] == nil {
                    spacesByFilter[filter] = []
                }
            }
        } catch {
            lastError = error.localizedDescription
            if spacesByFilter[filter] == nil {
                spacesByFilter[filter] = []
            }
        }
    }

    func refreshSpaces() async {
        await loadSpaces(filter: activeSpaceFilter, force: true)
    }

    func openSpace(slug: String) async {
        spacePostsLoading = true
        defer { spacePostsLoading = false }
        do {
            let space = try await AnonymousService.space(slug: slug)
            withAnimation(MatteryaMotion.snappy) {
                currentSpace = space
            }
            let page = try await AnonymousService.listPosts(spaceId: space.id)
            spacePosts = page.items
            spacePostsCursor = page.nextCursor
        } catch let err as AnonymousError {
            lastError = err.errorDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    func joinCurrentSpace() async {
        guard let space = currentSpace else { return }
        if space.isPaid {
            lastError = AnonymousError.paidDisabled.errorDescription
            return
        }
        do {
            _ = try await AnonymousService.join(spaceId: space.id)
            currentSpace?.isJoined = true
            currentSpace?.memberCount = (currentSpace?.memberCount ?? 0) + 1
            await loadSpaces(filter: .joined, force: true)
        } catch let err as AnonymousError {
            lastError = err.errorDescription
        } catch {
            lastError = error.localizedDescription
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
            let space = try await AnonymousService.createSpace(input)
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

    // MARK: - Feed / posts

    func loadFeed(force: Bool = false) async {
        if !force, !feed.isEmpty { return }
        feedLoading = true
        defer { feedLoading = false }
        do {
            let page = try await AnonymousService.feed(sort: feedSort)
            withAnimation(MatteryaMotion.insert) {
                feed = page.items
                feedCursor = page.nextCursor
            }
        } catch let err as AnonymousError {
            lastError = err.errorDescription
            if feed.isEmpty { feed = [] }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshFeed() async {
        await loadFeed(force: true)
    }

    func publishPost(spaceId: String) async -> AnonymousPost? {
        let title = composerTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = composerBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            lastError = "Write something before posting."
            return nil
        }
        do {
            let post = try await AnonymousService.createPost(
                spaceId: spaceId,
                input: AnonymousCreatePostInput(
                    title: title.isEmpty ? nil : title,
                    body: body
                )
            )
            composerTitle = ""
            composerBody = ""
            spacePosts.insert(post, at: 0)
            feed.insert(post, at: 0)
            return post
        } catch let err as AnonymousError {
            lastError = err.errorDescription
            return nil
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func vote(post: AnonymousPost, value: Int) async {
        do {
            try await AnonymousService.vote(targetType: "post", targetId: post.id, value: value)
            if let idx = feed.firstIndex(where: { $0.id == post.id }) {
                feed[idx].myVote = value
                feed[idx].score = (feed[idx].score ?? 0) + value - (post.myVote ?? 0)
            }
            if let idx = spacePosts.firstIndex(where: { $0.id == post.id }) {
                spacePosts[idx].myVote = value
                spacePosts[idx].score = (spacePosts[idx].score ?? 0) + value - (post.myVote ?? 0)
            }
        } catch let err as AnonymousError {
            lastError = err.errorDescription
        } catch {
            lastError = error.localizedDescription
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

    func block(profileId: String) async {
        do {
            try await AnonymousService.block(profileId: profileId)
            blockedProfileIds.insert(profileId)
            feed.removeAll { $0.authorProfileId == profileId }
            spacePosts.removeAll { $0.authorProfileId == profileId }
        } catch let err as AnonymousError {
            lastError = err.errorDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    func consumeError() -> String? {
        let msg = lastError
        lastError = nil
        return msg
    }

    // MARK: - Internals

    private func applySession(_ remote: AnonymousSession, animated: Bool) {
        session = remote
        if let suggested = remote.suggestedUsername, !suggested.isEmpty {
            suggestedUsername = suggested
        } else if suggestedUsername.isEmpty {
            suggestedUsername = Self.localSafeUsername()
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
        } else {
            next = .ready
        }

        if animated {
            withAnimation(MatteryaMotion.snappy) { phase = next }
        } else {
            phase = next
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
        case .network:
            if session.profile != nil {
                withAnimation(MatteryaMotion.snappy) { phase = .ready }
            } else if phase == .loading {
                withAnimation(MatteryaMotion.snappy) { phase = .offline }
            }
            lastError = err.errorDescription
        default:
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
