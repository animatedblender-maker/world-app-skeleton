import Foundation

@MainActor
final class FollowService {
    static let shared = FollowService()

    private let gql = GraphQLService.shared
    /// Offline-only fallback for synthetic non-UUID authors (cannot FK into user_follows).
    private let localFollowingKey = "matterya.local_following_ids.v1"
    /// Last known counts for instant profile paint.
    private var countsCache: [String: FollowCounts] = [:]

    private init() {}

    /// Sync cache hit for profile header (never blocks).
    func cachedCounts(userID: String) -> FollowCounts? {
        let id = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }
        return countsCache[id]
    }

    /// True only for synthetic demo/seed ids that **cannot** be stored in Supabase `user_follows`
    /// (FK to auth.users). Real channel owners are UUIDs → always Supabase.
    static func usesLocalFollow(userID: String) -> Bool {
        let id = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty { return true }
        // Real accounts / channel owners are UUIDs — always server.
        if UUID(uuidString: id) != nil { return false }
        let lower = id.lowercased()
        if lower.hasPrefix("user_")
            || lower.hasPrefix("hub_")
            || lower.hasPrefix("hub_spark_")
            || lower.hasPrefix("demo_")
            || lower.hasPrefix("ia_")
            || lower.hasPrefix("archive_")
            || lower.hasPrefix("spark_")
        {
            return true
        }
        // Unknown non-UUID → local only (server would reject FK).
        return true
    }

    private var localFollowingIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: localFollowingKey) ?? []) }
        set {
            UserDefaults.standard.set(Array(newValue).sorted(), forKey: localFollowingKey)
        }
    }

    func counts(userID: String) async -> FollowCounts {
        let id = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        // Synthetic authors: local follower bit only.
        if Self.usesLocalFollow(userID: id) {
            let followers = localFollowingIDs.contains(id) ? 1 : 0
            let result = FollowCounts(followers: followers, following: 0)
            countsCache[id] = result
            return result
        }
        struct Response: Decodable {
            struct Counts: Decodable {
                let followers: Int
                let following: Int
            }
            let followCounts: Counts?
        }
        let query = """
        query FollowCounts($userId: ID!) {
          followCounts(user_id: $userId) { followers following }
        }
        """
        do {
            let result: Response = try await gql.authenticatedRequest(
                query: query,
                variables: ["userId": id]
            )
            let counts = FollowCounts(
                followers: result.followCounts?.followers ?? 0,
                following: result.followCounts?.following ?? 0
            )
            countsCache[id] = counts
            return counts
        } catch {
            return countsCache[id] ?? FollowCounts(followers: 0, following: 0)
        }
    }

    func isFollowing(targetID: String) async -> Bool {
        let id = targetID.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.usesLocalFollow(userID: id) {
            return localFollowingIDs.contains(id)
        }
        struct Response: Decodable { let isFollowing: Bool }
        let query = "query($target: ID!) { isFollowing(user_id: $target) }"
        do {
            let result: Response = try await gql.authenticatedRequest(
                query: query,
                variables: ["target": id]
            )
            return result.isFollowing
        } catch {
            return false
        }
    }

    /// Server following set is source of truth for real users; synthetic ids stay local.
    func followingIDs() async -> Set<String> {
        let local = localFollowingIDs
        struct Response: Decodable { let followingIds: [String] }
        let query = "query { followingIds }"
        do {
            let result: Response = try await gql.authenticatedRequest(query: query)
            // Prefer Supabase for UUIDs; keep synthetic locals for demo seeds only.
            return Set(result.followingIds).union(local)
        } catch {
            return local
        }
    }

    /// Always writes to Supabase for real UUID targets. Synthetic ids stay on-device only.
    func follow(targetID: String) async throws {
        let id = targetID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }

        if Self.usesLocalFollow(userID: id) {
            var set = localFollowingIDs
            set.insert(id)
            localFollowingIDs = set
            return
        }

        let mutation = "mutation($target: ID!) { followUser(target_id: $target) }"
        let _: EmptyMutation = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["target": id]
        )
        EngagementTracker.shared.enqueuePersonFollow(targetID: id, following: true)
    }

    func unfollow(targetID: String) async throws {
        let id = targetID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }

        if Self.usesLocalFollow(userID: id) {
            var set = localFollowingIDs
            set.remove(id)
            localFollowingIDs = set
            return
        }

        let mutation = "mutation($target: ID!) { unfollowUser(target_id: $target) }"
        let _: EmptyMutation = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["target": id]
        )
        EngagementTracker.shared.enqueuePersonFollow(targetID: id, following: false)
    }
}
