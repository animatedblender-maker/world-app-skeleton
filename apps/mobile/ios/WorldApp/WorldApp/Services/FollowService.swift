import Foundation

@MainActor
final class FollowService {
    static let shared = FollowService()

    private let gql = GraphQLService.shared
    private let localFollowingKey = "matterya.local_following_ids.v1"

    private init() {}

    /// Demo / hub / seed creators are not real server users — follow them on-device.
    static func usesLocalFollow(userID: String) -> Bool {
        let id = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty { return true }
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
        // Real accounts use UUIDs.
        if UUID(uuidString: id) != nil { return false }
        return true
    }

    private var localFollowingIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: localFollowingKey) ?? []) }
        set {
            UserDefaults.standard.set(Array(newValue).sorted(), forKey: localFollowingKey)
        }
    }

    func counts(userID: String) async -> FollowCounts {
        if Self.usesLocalFollow(userID: userID) {
            // Fake/hub creators: show at least the local follower (you) when followed.
            let followers = localFollowingIDs.contains(userID) ? 1 : 0
            return FollowCounts(followers: followers, following: 0)
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
            let result: Response = try await gql.authenticatedRequest(query: query, variables: ["userId": userID])
            return FollowCounts(
                followers: result.followCounts?.followers ?? 0,
                following: result.followCounts?.following ?? 0
            )
        } catch {
            return FollowCounts(followers: 0, following: 0)
        }
    }

    func isFollowing(targetID: String) async -> Bool {
        if Self.usesLocalFollow(userID: targetID) {
            return localFollowingIDs.contains(targetID)
        }
        struct Response: Decodable { let isFollowing: Bool }
        let query = "query($target: ID!) { isFollowing(user_id: $target) }"
        do {
            let result: Response = try await gql.authenticatedRequest(query: query, variables: ["target": targetID])
            return result.isFollowing
        } catch {
            return false
        }
    }

    func followingIDs() async -> Set<String> {
        let local = localFollowingIDs
        struct Response: Decodable { let followingIds: [String] }
        let query = "query { followingIds }"
        do {
            let result: Response = try await gql.authenticatedRequest(query: query)
            return Set(result.followingIds).union(local)
        } catch {
            return local
        }
    }

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
        let _: EmptyMutation = try await gql.authenticatedRequest(query: mutation, variables: ["target": id])
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
        let _: EmptyMutation = try await gql.authenticatedRequest(query: mutation, variables: ["target": id])
        EngagementTracker.shared.enqueuePersonFollow(targetID: id, following: false)
    }
}
