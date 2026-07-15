import Foundation

enum GraphQLError: LocalizedError {
    case network(String)
    case nonJSON(String)
    case http(Int, String)
    case gql(String)

    var errorDescription: String? {
        switch self {
        case .network(let message): message
        case .nonJSON(let message): message
        case .http(let code, let message): "HTTP \(code): \(message)"
        case .gql(let message): message
        }
    }
}

final class GraphQLService: Sendable {
    static let shared = GraphQLService()

    private let endpoint = URL(string: AppConfig.graphqlEndpoint)!
    private let decoder = JSONDecoder()

    private init() {}

    func authenticatedRequest<T: Decodable>(
        query: String,
        variables: [String: Any] = [:]
    ) async throws -> T {
        let token = try await fetchValidToken()
        return try await request(query: query, variables: variables, token: token)
    }

    private func fetchValidToken() async throws -> String {
        try await Task { @MainActor in
            try await AuthService.shared.ensureValidToken()
        }.value
    }

    func request<T: Decodable>(
        query: String,
        variables: [String: Any] = [:],
        token: String? = nil
    ) async throws -> T {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "query": query,
            "variables": variables
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GraphQLError.network("GraphQL network error: \(error.localizedDescription)")
        }

        let text = String(data: data, encoding: .utf8) ?? ""
        guard let http = response as? HTTPURLResponse else {
            throw GraphQLError.network("Missing HTTP response.")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GraphQLError.nonJSON("Non-JSON response (HTTP \(http.statusCode)): \(text.prefix(600))")
        }

        if http.statusCode < 200 || http.statusCode >= 300 {
            let snippet = String(describing: json).prefix(800)
            throw GraphQLError.http(http.statusCode, String(snippet))
        }

        if let errors = json["errors"] as? [[String: Any]], let first = errors.first {
            let message = first["message"] as? String ?? "GraphQL error."
            let code = (first["extensions"] as? [String: Any])?["code"] as? String
            throw GraphQLError.gql(code.map { "\(message) (code=\($0))" } ?? message)
        }

        guard let dataNode = json["data"] else {
            throw GraphQLError.gql("Missing data field.")
        }

        let dataJSON = try JSONSerialization.data(withJSONObject: dataNode)
        do {
            return try decoder.decode(T.self, from: dataJSON)
        } catch let error as DecodingError {
            throw GraphQLError.gql("Response decoding failed: \(Self.describeDecodingError(error))")
        }
    }

    private static func describeDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            "Missing field '\(key.stringValue)' at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .valueNotFound(_, let context):
            "Missing value at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .typeMismatch(let type, let context):
            "Type mismatch for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .dataCorrupted(let context):
            context.debugDescription
        @unknown default:
            error.localizedDescription
        }
    }
}