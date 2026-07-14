import Foundation

struct BlockedAccount: Identifiable, Hashable, Sendable, Codable {
    let userID: String
    let username: String?
    let displayName: String?
    let blockedAt: Date

    var id: String { userID }

    var label: String {
        displayName ?? username.map { "@\($0)" } ?? userID
    }
}

@MainActor
final class BlockService {
    static let shared = BlockService()

    private let storageKey = "blocked_accounts_v1"
    private(set) var blocked: [BlockedAccount] = []

    private init() {
        load()
    }

    func isBlocked(_ userID: String) -> Bool {
        blocked.contains { $0.userID == userID }
    }

    func block(userID: String, username: String? = nil, displayName: String? = nil) {
        guard !userID.isEmpty, !isBlocked(userID) else { return }
        blocked.insert(
            BlockedAccount(
                userID: userID,
                username: username,
                displayName: displayName,
                blockedAt: Date()
            ),
            at: 0
        )
        persist()
    }

    func unblock(_ userID: String) {
        blocked.removeAll { $0.userID == userID }
        persist()
    }

    func filterPosts(_ posts: [CountryPost]) -> [CountryPost] {
        let ids = Set(blocked.map(\.userID))
        guard !ids.isEmpty else { return posts }
        return posts.filter { !ids.contains($0.authorID) }
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([BlockedAccount].self, from: data)
        else { return }
        blocked = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(blocked) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}