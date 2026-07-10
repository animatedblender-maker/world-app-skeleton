import Foundation

@MainActor
final class FollowService {
    static let shared = FollowService()

    private let gql = GraphQLService.shared

    private init() {}

    func counts(userID: String) async -> FollowCounts {
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
        struct Response: Decodable { let followingIds: [String] }
        let query = "query { followingIds }"
        do {
            let result: Response = try await gql.authenticatedRequest(query: query)
            return Set(result.followingIds)
        } catch {
            return []
        }
    }

    func follow(targetID: String) async throws {
        guard !targetID.hasPrefix("user_") else { return }
        let mutation = "mutation($target: ID!) { followUser(target_id: $target) }"
        let _: EmptyMutation = try await gql.authenticatedRequest(query: mutation, variables: ["target": targetID])
    }

    func unfollow(targetID: String) async throws {
        guard !targetID.hasPrefix("user_") else { return }
        let mutation = "mutation($target: ID!) { unfollowUser(target_id: $target) }"
        let _: EmptyMutation = try await gql.authenticatedRequest(query: mutation, variables: ["target": targetID])
    }
}