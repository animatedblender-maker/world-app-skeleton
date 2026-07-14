import Foundation

struct GlobePresenceDot: Identifiable, Sendable, Equatable {
    let id: String
    let lat: Double
    let lng: Double
    let count: Int
}

@MainActor
@Observable
final class GlobePresenceService {
    static let shared = GlobePresenceService()

    private(set) var dots: [GlobePresenceDot] = []
    private(set) var totalOnline = 0
    private(set) var lastUpdated: Date?

    private let gql = GraphQLService.shared
    private let rest = SupabaseRESTClient.shared
    private var pollTask: Task<Void, Never>?
    private var countryEntries: [CountryMapEntry] = []
    private var currentPrecision = 4
    private var refreshTask: Task<Void, Never>?

    private init() {}

    func startPolling(precision: Int = 4) {
        currentPrecision = precision
        if countryEntries.isEmpty {
            countryEntries = CountryMapData.load()
        }
        stopPolling()
        pollTask = Task {
            await refresh(precision: currentPrecision)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                await refresh(precision: currentPrecision)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func updatePrecision(_ precision: Int) {
        guard precision != currentPrecision else { return }
        currentPrecision = precision
        refreshTask?.cancel()
        refreshTask = Task { await refresh(precision: precision) }
    }

    func refresh(precision: Int? = nil) async {
        let activePrecision = precision ?? currentPrecision
        currentPrecision = activePrecision

        if countryEntries.isEmpty {
            countryEntries = CountryMapData.load()
        }

        var merged: [GlobePresenceDot] = []
        var onlineCount = 0

        if let remote = await fetchSupabaseDots(precision: activePrecision) {
            merged = remote.dots
            onlineCount = remote.totalOnline
        } else if let remote = await fetchGraphQLDots(precision: activePrecision) {
            merged = remote.dots
            onlineCount = remote.totalOnline
        }

        if let me = await currentUserDot() {
            if !merged.contains(where: { $0.id == me.id }) {
                merged.insert(me, at: 0)
            }
            onlineCount = max(onlineCount, 1)
        }

        dots = merged
        totalOnline = onlineCount
        lastUpdated = Date()
    }

    private func currentUserDot() async -> GlobePresenceDot? {
        guard let userID = AuthService.shared.currentUser?.id else { return nil }
        let profile = ContentCache.shared.cachedProfile()
        let countryCode = ContentCache.shared.profileCountryCode() ?? profile?.countryCode
        guard let coordinate = await GlobeCityCoordinateCache.shared.resolveCurrentUser(
            userID: userID,
            countryCode: countryCode,
            cityName: profile?.cityName,
            countryName: profile?.countryName,
            entries: countryEntries
        ) else { return nil }

        return GlobePresenceDot(
            id: "me-\(userID)",
            lat: coordinate.lat,
            lng: coordinate.lng,
            count: 1
        )
    }

    private func fetchSupabaseDots(precision: Int) async -> (dots: [GlobePresenceDot], totalOnline: Int)? {
        let users = await fetchPresenceUsers()
        guard !users.isEmpty else { return nil }

        var coordinates: [String: (lat: Double, lng: Double)] = [:]
        for user in users {
            let coordinate = await GlobeCityCoordinateCache.shared.resolve(
                user: user,
                entries: countryEntries
            )
            coordinates[user.userID] = coordinate
        }

        let dots = GlobePresenceGeo.clusterDots(
            users: users,
            coordinates: coordinates,
            precision: precision
        )
        guard !dots.isEmpty else { return nil }
        return (dots, users.count)
    }

    private func fetchPresenceUsers() async -> [OnlinePresenceUser] {
        struct PresenceRow: Decodable {
            let userID: String
            let countryCode: String?
            let cityName: String?
            let countryName: String?

            enum CodingKeys: String, CodingKey {
                case userID = "user_id"
                case countryCode = "country_code"
                case cityName = "city_name"
                case countryName = "country_name"
            }
        }

        let cutoff = GlobePresenceGeo.ttlCutoffISO()
        let filters: [String: String] = [
            "is_online": "eq.true",
            "last_seen_at": "gte.\(cutoff)",
            "country_code": "not.is.null",
            "select": "user_id,country_code,city_name,country_name",
            "order": "last_seen_at.desc",
            "limit": "8000",
        ]

        let rows: [PresenceRow]
        if let anonRows: [PresenceRow] = try? await fetchPresenceRowsPublic(filters: filters) {
            rows = anonRows
        } else if let authedRows: [PresenceRow] = try? await rest.select(
            table: "user_presence",
            filters: filters
        ) {
            rows = authedRows
        } else {
            rows = []
        }

        return rows.compactMap { row -> OnlinePresenceUser? in
            guard let code = row.countryCode?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !code.isEmpty
            else { return nil }
            return OnlinePresenceUser(
                userID: row.userID,
                countryCode: code.uppercased(),
                cityName: row.cityName,
                countryName: row.countryName
            )
        }
    }

    private func fetchPresenceRowsPublic<T: Decodable>(filters: [String: String]) async throws -> T {
        var components = URLComponents(
            url: URL(string: "\(AppConfig.supabaseURL)/rest/v1/user_presence")!,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = filters
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw URLError(.badServerResponse)
        }

        if data.isEmpty {
            return try JSONDecoder().decode(T.self, from: Data("[]".utf8))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func fetchGraphQLDots(precision: Int) async -> (dots: [GlobePresenceDot], totalOnline: Int)? {
        let query = """
        query GlobePresenceDots($precision: Int, $maxPoints: Int) {
          globePresenceDots(precision: $precision, maxPoints: $maxPoints) {
            totalOnline
            dots { lat lng count }
          }
        }
        """

        guard let result: GlobePresenceDotsResponse = try? await gql.request(
            query: query,
            variables: [
                "precision": precision,
                "maxPoints": 4096,
            ]
        ), !result.globePresenceDots.dots.isEmpty else { return nil }

        let payload = result.globePresenceDots
        let dots = payload.dots.enumerated().map { index, dot in
            GlobePresenceDot(
                id: "\(dot.lat)-\(dot.lng)-\(index)",
                lat: dot.lat,
                lng: dot.lng,
                count: dot.count
            )
        }
        return (dots, payload.totalOnline)
    }
}

private struct GlobePresenceDotsResponse: Decodable {
    let globePresenceDots: GlobePresenceDotsPayload
}

private struct GlobePresenceDotsPayload: Decodable {
    let totalOnline: Int
    let dots: [GlobePresenceDotsNode]
}

private struct GlobePresenceDotsNode: Decodable {
    let lat: Double
    let lng: Double
    let count: Int
}