import Foundation

@MainActor
final class PresenceService {
    static let shared = PresenceService()

    private let gql = GraphQLService.shared
    private var heartbeatTask: Task<Void, Never>?

    private init() {}

    func startHeartbeat(viewingISO: String?) {
        stopHeartbeat()
        heartbeatTask = Task {
            while !Task.isCancelled {
                await sendHeartbeat(iso: viewingISO)
                try? await Task.sleep(nanoseconds: 25_000_000_000)
            }
        }
    }

    func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    func sendHeartbeat(iso: String?) async {
        let mutation = """
        mutation Heartbeat($iso: String) {
          heartbeat(iso: $iso) { ok ttlSeconds lastSeen }
        }
        """
        var vars: [String: Any] = [:]
        if let iso { vars["iso"] = iso.uppercased() }
        _ = try? await gql.authenticatedRequest(query: mutation, variables: vars) as EmptyMutation
    }

    func setOffline() async {
        let mutation = "mutation { setOffline }"
        _ = try? await gql.authenticatedRequest(query: mutation) as BoolMutation
    }
}

private struct BoolMutation: Decodable {
    let setOffline: Bool
}