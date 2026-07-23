import Foundation
import Observation

// MARK: - Models

enum LetterDeliveryStatus: String, Codable, Sendable {
    case composing
    case sealing
    case inFlight
    case delivered
    case awaitingReply
    case replied
    case expired
    case penFriend
}

enum PenFriendRequestKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case chat
    case follow
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: "Open chat"
        case .follow: "Follow"
        case .profile: "See profile"
        }
    }

    var subtitle: String {
        switch self {
        case .chat: "Message in normal chats — only if mutual"
        case .follow: "Follow each other — only if mutual"
        case .profile: "Reveal real identity — only if mutual"
        }
    }

    var systemImage: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right"
        case .follow: "person.badge.plus"
        case .profile: "person.crop.circle"
        }
    }
}

struct LetterMessage: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let authorIsMe: Bool
    let body: String
    let createdAt: Date
    /// Country known to the other person (sender's country for them; destination for me).
    let fromCountryCode: String
    let fromCountryName: String
}

struct PenFriendRequestState: Codable, Hashable, Sendable {
    var iRequested: Bool
    var theyRequested: Bool

    var isMutual: Bool { iRequested && theyRequested }

    static let empty = PenFriendRequestState(iRequested: false, theyRequested: false)
}

struct LetterThread: Identifiable, Codable, Hashable, Sendable {
    let id: String
    /// Opaque stranger id — never shown as identity until mutual profile.
    let strangerID: String
    var destinationCountryCode: String
    var destinationCountryName: String
    var messages: [LetterMessage]
    var status: LetterDeliveryStatus
    var createdAt: Date
    var replyDeadline: Date?
    var lastActivityAt: Date
    var chatRequest: PenFriendRequestState
    var followRequest: PenFriendRequestState
    var profileRequest: PenFriendRequestState
    /// True when this thread started as a letter *I* sent to a stranger (counts toward daily quota).
    var startedByMe: Bool

    var isPenFriend: Bool {
        messages.count >= 2 && messages.contains(where: \.authorIsMe) && messages.contains(where: { !$0.authorIsMe })
    }

    var latestMessage: LetterMessage? { messages.last }

    var awaitingMyReply: Bool {
        guard let last = messages.last else { return false }
        return !last.authorIsMe && status != .expired
    }

    var awaitingTheirReply: Bool {
        guard let last = messages.last else { return false }
        return last.authorIsMe && (status == .awaitingReply || status == .delivered || status == .inFlight)
    }

    var replySecondsRemaining: TimeInterval? {
        guard let deadline = replyDeadline else { return nil }
        return deadline.timeIntervalSinceNow
    }

    func requestState(for kind: PenFriendRequestKind) -> PenFriendRequestState {
        switch kind {
        case .chat: chatRequest
        case .follow: followRequest
        case .profile: profileRequest
        }
    }
}

struct DailyLetterQuota: Codable, Hashable, Sendable {
    /// Local calendar day key, e.g. "2026-07-24"
    var dayKey: String
    var sentCount: Int

    static let dailyLimit = 5

    var remaining: Int { max(0, Self.dailyLimit - sentCount) }
    var isExhausted: Bool { remaining == 0 }
}

struct LetterFlightEvent: Identifiable, Equatable, Hashable {
    let id: String
    let threadID: String
    let body: String
    let slotUsed: Int
    let dailyLimit: Int
    let destinationCountryCode: String
    let destinationCountryName: String
}

// MARK: - Service

@MainActor
@Observable
final class LettersService {
    static let shared = LettersService()

    private let storeKey = "matterya.letters.store.v1"
    private let quotaKey = "matterya.letters.quota.v1"
    private let seedKey = "matterya.letters.seeded.v1"

    private(set) var threads: [LetterThread] = []
    private(set) var quota: DailyLetterQuota
    var activeFlight: LetterFlightEvent?

    private init() {
        quota = Self.loadQuota()
        threads = Self.loadThreads()
        rolloverQuotaIfNeeded()
        expireStaleThreads()
        seedDemoIfNeeded()
    }

    // MARK: Quota (local midnight)

    /// Local calendar day string used for quota reset at midnight in the user's timezone.
    static func localDayKey(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 1970
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    func rolloverQuotaIfNeeded(now: Date = Date()) {
        let today = Self.localDayKey(for: now)
        if quota.dayKey != today {
            quota = DailyLetterQuota(dayKey: today, sentCount: 0)
            persistQuota()
        }
    }

    var remainingToday: Int {
        rolloverQuotaIfNeeded()
        return quota.remaining
    }

    var sentToday: Int {
        rolloverQuotaIfNeeded()
        return quota.sentCount
    }

    var secondsUntilLocalMidnight: TimeInterval {
        let calendar = Calendar.current
        let startOfTomorrow = calendar.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(86_400)
        return max(0, startOfTomorrow.timeIntervalSinceNow)
    }

    // MARK: Queries

    var inboxThreads: [LetterThread] {
        threads
            .filter { $0.awaitingMyReply || (!$0.startedByMe && $0.messages.count == 1) }
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    var inFlightThreads: [LetterThread] {
        threads
            .filter { $0.startedByMe && ($0.awaitingTheirReply || $0.status == .inFlight || $0.status == .delivered) }
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    var penFriendThreads: [LetterThread] {
        threads
            .filter(\.isPenFriend)
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    var unreadIncomingCount: Int {
        inboxThreads.count
    }

    func thread(id: String) -> LetterThread? {
        threads.first { $0.id == id }
    }

    // MARK: Send new letter to stranger

    enum SendError: LocalizedError {
        case emptyBody
        case quotaExhausted
        case tooLong

        var errorDescription: String? {
            switch self {
            case .emptyBody: "Write something before sealing the letter."
            case .quotaExhausted: "You've sent all 5 letters today. New ones unlock at local midnight."
            case .tooLong: "Letters are short notes — keep it under 500 characters."
            }
        }
    }

    @discardableResult
    func sendNewLetter(body: String, myCountryCode: String?, myCountryName: String?) throws -> LetterFlightEvent {
        rolloverQuotaIfNeeded()
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SendError.emptyBody }
        guard trimmed.count <= 500 else { throw SendError.tooLong }
        guard !quota.isExhausted else { throw SendError.quotaExhausted }

        let dest = Self.randomDestination(excluding: myCountryCode)
        let now = Date()
        let message = LetterMessage(
            id: UUID().uuidString,
            authorIsMe: true,
            body: trimmed,
            createdAt: now,
            fromCountryCode: (myCountryCode ?? "XX").uppercased(),
            fromCountryName: myCountryName ?? "Somewhere"
        )
        let thread = LetterThread(
            id: UUID().uuidString,
            strangerID: "stranger-\(UUID().uuidString.prefix(8))",
            destinationCountryCode: dest.code,
            destinationCountryName: dest.name,
            messages: [message],
            status: .inFlight,
            createdAt: now,
            replyDeadline: now.addingTimeInterval(24 * 60 * 60),
            lastActivityAt: now,
            chatRequest: .empty,
            followRequest: .empty,
            profileRequest: .empty,
            startedByMe: true
        )

        threads.insert(thread, at: 0)
        quota.sentCount += 1
        persistAll()

        let slot = quota.sentCount
        let event = LetterFlightEvent(
            id: UUID().uuidString,
            threadID: thread.id,
            body: trimmed,
            slotUsed: slot,
            dailyLimit: DailyLetterQuota.dailyLimit,
            destinationCountryCode: dest.code,
            destinationCountryName: dest.name
        )
        activeFlight = event
        return event
    }

    func completeFlight(threadID: String) {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else {
            activeFlight = nil
            return
        }
        // Idempotent — flight animation may call this more than once.
        let alreadyDelivered = threads[index].status == .awaitingReply
            || threads[index].status == .penFriend
            || threads[index].status == .replied
        if !alreadyDelivered {
            threads[index].status = .awaitingReply
            threads[index].lastActivityAt = Date()
            if threads[index].replyDeadline == nil {
                threads[index].replyDeadline = Date().addingTimeInterval(24 * 60 * 60)
            }
            persistThreads()
            // Demo: occasionally simulate a pen-friend reply after a short delay.
            scheduleDemoReply(for: threadID)
        }
        if activeFlight?.threadID == threadID {
            activeFlight = nil
        }
    }

    // MARK: Reply (pen-friend chain)

    @discardableResult
    func reply(to threadID: String, body: String, myCountryCode: String?, myCountryName: String?) throws -> LetterThread {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SendError.emptyBody }
        guard trimmed.count <= 500 else { throw SendError.tooLong }
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else {
            throw SendError.emptyBody
        }

        expireIfNeeded(at: index)
        guard threads[index].status != .expired else {
            throw SendError.emptyBody
        }

        let now = Date()
        let message = LetterMessage(
            id: UUID().uuidString,
            authorIsMe: true,
            body: trimmed,
            createdAt: now,
            fromCountryCode: (myCountryCode ?? "XX").uppercased(),
            fromCountryName: myCountryName ?? "Somewhere"
        )
        threads[index].messages.append(message)
        threads[index].status = .penFriend
        threads[index].replyDeadline = now.addingTimeInterval(24 * 60 * 60)
        threads[index].lastActivityAt = now
        persistThreads()

        // Demo: stranger may write back later.
        scheduleDemoReply(for: threadID, delaySeconds: Double.random(in: 12...40))
        return threads[index]
    }

    // MARK: Pen-friend requests (mutual only)

    func request(_ kind: PenFriendRequestKind, threadID: String) {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
        guard threads[index].isPenFriend else { return }

        switch kind {
        case .chat:
            threads[index].chatRequest.iRequested = true
            // Demo mutual chance for polish
            if Bool.random() { threads[index].chatRequest.theyRequested = true }
        case .follow:
            threads[index].followRequest.iRequested = true
            if Bool.random() { threads[index].followRequest.theyRequested = true }
        case .profile:
            threads[index].profileRequest.iRequested = true
            if Bool.random() { threads[index].profileRequest.theyRequested = true }
        }
        threads[index].lastActivityAt = Date()
        persistThreads()
    }

    // MARK: Maintenance

    func expireStaleThreads(now: Date = Date()) {
        var changed = false
        for i in threads.indices {
            if expireIfNeeded(at: i, now: now) { changed = true }
        }
        if changed { persistThreads() }
    }

    @discardableResult
    private func expireIfNeeded(at index: Int, now: Date = Date()) -> Bool {
        guard let deadline = threads[index].replyDeadline else { return false }
        guard threads[index].status == .awaitingReply || threads[index].status == .delivered else { return false }
        // Only expire if the last message was from me (they never answered).
        guard threads[index].messages.last?.authorIsMe == true else { return false }
        guard now >= deadline else { return false }
        threads[index].status = .expired
        return true
    }

    func dismissActiveFlight() {
        activeFlight = nil
    }

    // MARK: Demo seed + simulated replies

    private func seedDemoIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: seedKey) else { return }
        UserDefaults.standard.set(true, forKey: seedKey)

        let samples: [(String, String, String)] = [
            ("JP", "Japan", "Hello from a rainy afternoon train. What does the sky look like where you are?"),
            ("BR", "Brazil", "I left a note under a mango tree once. Writing to a stranger feels the same — soft and a little brave."),
            ("IS", "Iceland", "The wind here writes louder than I do. Tell me one quiet thing about your day."),
        ]

        let now = Date()
        for (i, sample) in samples.enumerated() {
            let msg = LetterMessage(
                id: UUID().uuidString,
                authorIsMe: false,
                body: sample.2,
                createdAt: now.addingTimeInterval(Double(-3600 * (i + 1))),
                fromCountryCode: sample.0,
                fromCountryName: sample.1
            )
            let thread = LetterThread(
                id: UUID().uuidString,
                strangerID: "stranger-seed-\(i)",
                destinationCountryCode: sample.0,
                destinationCountryName: sample.1,
                messages: [msg],
                status: .awaitingReply,
                createdAt: msg.createdAt,
                replyDeadline: now.addingTimeInterval(20 * 60 * 60),
                lastActivityAt: msg.createdAt,
                chatRequest: .empty,
                followRequest: .empty,
                profileRequest: .empty,
                startedByMe: false
            )
            threads.append(thread)
        }
        persistThreads()
    }

    private func scheduleDemoReply(for threadID: String, delaySeconds: Double = 8) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
            guard threads[index].messages.last?.authorIsMe == true else { return }
            guard threads[index].status != .expired else { return }
            // ~70% chance they write back in demo mode
            guard Double.random(in: 0...1) < 0.72 else { return }

            let replyBody = Self.demoReplyBodies.randomElement() ?? "I read your letter twice. Thank you for sending it across the world."
            let now = Date()
            let message = LetterMessage(
                id: UUID().uuidString,
                authorIsMe: false,
                body: replyBody,
                createdAt: now,
                fromCountryCode: threads[index].destinationCountryCode,
                fromCountryName: threads[index].destinationCountryName
            )
            threads[index].messages.append(message)
            threads[index].status = .penFriend
            threads[index].replyDeadline = now.addingTimeInterval(24 * 60 * 60)
            threads[index].lastActivityAt = now
            persistThreads()
            NotificationCenter.default.post(name: .lettersDidChange, object: nil)
        }
    }

    private static let demoReplyBodies = [
        "Your words landed softly. I don't know your name, only this country of mine — and that felt like enough.",
        "I folded your letter next to my window. The world feels a little smaller tonight.",
        "Thank you for writing to a stranger. Here's one true thing: I smiled reading this.",
        "I almost never answer cold messages. Letters are different. Tell me more when you can.",
        "Somewhere between your sky and mine, this found me. I'm glad it did.",
    ]

    // MARK: Persistence

    private func persistAll() {
        persistQuota()
        persistThreads()
        NotificationCenter.default.post(name: .lettersDidChange, object: nil)
    }

    private func persistQuota() {
        if let data = try? JSONEncoder().encode(quota) {
            UserDefaults.standard.set(data, forKey: quotaKey)
        }
    }

    private func persistThreads() {
        if let data = try? JSONEncoder().encode(threads) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    private static func loadQuota() -> DailyLetterQuota {
        let today = localDayKey()
        guard let data = UserDefaults.standard.data(forKey: "matterya.letters.quota.v1"),
              let decoded = try? JSONDecoder().decode(DailyLetterQuota.self, from: data)
        else {
            return DailyLetterQuota(dayKey: today, sentCount: 0)
        }
        if decoded.dayKey != today {
            return DailyLetterQuota(dayKey: today, sentCount: 0)
        }
        return decoded
    }

    private static func loadThreads() -> [LetterThread] {
        guard let data = UserDefaults.standard.data(forKey: "matterya.letters.store.v1"),
              let decoded = try? JSONDecoder().decode([LetterThread].self, from: data)
        else { return [] }
        return decoded
    }

    // MARK: Destinations

    struct Destination: Sendable {
        let code: String
        let name: String
    }

    static let destinations: [Destination] = [
        .init(code: "JP", name: "Japan"),
        .init(code: "BR", name: "Brazil"),
        .init(code: "IS", name: "Iceland"),
        .init(code: "MA", name: "Morocco"),
        .init(code: "NZ", name: "New Zealand"),
        .init(code: "NO", name: "Norway"),
        .init(code: "KE", name: "Kenya"),
        .init(code: "CL", name: "Chile"),
        .init(code: "KR", name: "South Korea"),
        .init(code: "PT", name: "Portugal"),
        .init(code: "IN", name: "India"),
        .init(code: "CA", name: "Canada"),
        .init(code: "EG", name: "Egypt"),
        .init(code: "PE", name: "Peru"),
        .init(code: "FI", name: "Finland"),
        .init(code: "TH", name: "Thailand"),
        .init(code: "GR", name: "Greece"),
        .init(code: "AR", name: "Argentina"),
        .init(code: "VN", name: "Vietnam"),
        .init(code: "IE", name: "Ireland"),
        .init(code: "ZA", name: "South Africa"),
        .init(code: "TR", name: "Turkey"),
        .init(code: "PH", name: "Philippines"),
        .init(code: "SE", name: "Sweden"),
        .init(code: "MX", name: "Mexico"),
        .init(code: "AU", name: "Australia"),
        .init(code: "IT", name: "Italy"),
        .init(code: "FR", name: "France"),
        .init(code: "ES", name: "Spain"),
        .init(code: "PL", name: "Poland"),
    ]

    static func randomDestination(excluding code: String?) -> Destination {
        let exclude = code?.uppercased()
        let pool = destinations.filter { $0.code != exclude }
        return pool.randomElement() ?? destinations[0]
    }
}

extension Notification.Name {
    static let lettersDidChange = Notification.Name("matterya.letters.didChange")
}
