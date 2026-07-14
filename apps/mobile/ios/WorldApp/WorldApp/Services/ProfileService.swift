import Foundation

@MainActor
final class ProfileService {
    static let shared = ProfileService()

    private let gql = GraphQLService.shared
    private var countriesCache: [Country]?

    private init() {}

    func countries() async throws -> [Country] {
        if let countriesCache { return countriesCache }

        do {
            let mapped = try await fetchCountries(authenticated: false)
            countriesCache = mapped
            return mapped
        } catch {
            let mapped = try await fetchCountries(authenticated: true)
            countriesCache = mapped
            return mapped
        }
    }

    private func fetchCountries(authenticated: Bool) async throws -> [Country] {
        struct Response: Decodable {
            struct CountriesResult: Decodable {
                let countries: [GraphQLCountry]
            }
            let countries: CountriesResult
        }

        let query = """
        query Countries {
          countries {
            countries { id name iso continent center { lat lng } }
          }
        }
        """

        let result: Response
        if authenticated {
            result = try await gql.authenticatedRequest(query: query)
        } else {
            result = try await gql.request(query: query)
        }
        return result.countries.countries.map(\.toModel).sorted { $0.name < $1.name }
    }

    func detectLocation(lat: Double, lng: Double) async throws -> DetectedLocation {
        struct Response: Decodable {
            let detectLocation: GraphQLDetectedLocation
        }

        let mutation = """
        mutation DetectLocation($lat: Float!, $lng: Float!) {
          detectLocation(lat: $lat, lng: $lng) {
            countryCode
            countryName
            cityName
            source
          }
        }
        """

        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["lat": lat, "lng": lng],

        )
        return result.detectLocation.toModel
    }

    func meProfile() async throws -> Profile? {
        struct Response: Decodable {
            let meProfile: GraphQLProfile?
        }

        let query = """
        query MeProfile {
          meProfile {
            user_id email display_name username avatar_url
            country_name country_code city_name bio created_at updated_at
          }
        }
        """

        let result: Response = try await gql.authenticatedRequest(query: query)
        return result.meProfile?.toModel
    }

    func updateProfile(
        displayName: String? = nil,
        username: String? = nil,
        countryName: String? = nil,
        countryCode: String? = nil,
        cityName: String? = nil,
        bio: String? = nil,
        avatarURL: String? = nil
    ) async throws -> Profile {
        struct Response: Decodable {
            let updateProfile: GraphQLProfile
        }

        var input: [String: Any] = [:]
        if let displayName { input["display_name"] = displayName }
        if let username { input["username"] = username }
        if let countryName { input["country_name"] = countryName }
        if let countryCode { input["country_code"] = countryCode }
        if let cityName { input["city_name"] = cityName }
        if let bio { input["bio"] = bio }
        if let avatarURL { input["avatar_url"] = avatarURL }

        let mutation = """
        mutation UpdateProfile($input: UpdateProfileInput!) {
          updateProfile(input: $input) {
            user_id email display_name username avatar_url
            country_name country_code city_name bio created_at updated_at
          }
        }
        """

        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["input": input],

        )
        return result.updateProfile.toModel
    }

    func profileByUsername(_ username: String) async throws -> Profile? {
        struct Response: Decodable {
            let profileByUsername: GraphQLProfile?
        }

        let query = """
        query ProfileByUsername($username: String!) {
          profileByUsername(username: $username) {
            user_id email display_name username avatar_url
            country_name country_code city_name bio created_at updated_at
          }
        }
        """

        if let result: Response = try? await gql.request(
            query: query,
            variables: ["username": username]
        ) {
            return result.profileByUsername?.toModel
        }

        let result: Response = try await gql.authenticatedRequest(
            query: query,
            variables: ["username": username]
        )
        return result.profileByUsername?.toModel
    }

    func searchProfiles(_ query: String, limit: Int = 20) async throws -> [Profile] {
        struct Response: Decodable { let searchProfiles: [GraphQLProfile] }
        let gqlQuery = """
        query SearchProfiles($query: String!, $limit: Int) {
          searchProfiles(query: $query, limit: $limit) {
            user_id email display_name username avatar_url
            country_name country_code city_name bio created_at updated_at
          }
        }
        """
        let result: Response = try await gql.authenticatedRequest(query: gqlQuery, variables: ["query": query, "limit": limit])
        let profiles = result.searchProfiles.map(\.toModel)
        return MatteryaSearchEngine.rankProfiles(profiles, query: query, limit: limit)
    }

    func browseProfiles(limit: Int = 30, offset: Int = 0) async throws -> [Profile] {
        struct Response: Decodable { let browseProfiles: [GraphQLProfile] }
        let query = """
        query BrowseProfiles($limit: Int, $offset: Int) {
          browseProfiles(limit: $limit, offset: $offset) {
            user_id email display_name username avatar_url
            country_name country_code city_name bio created_at updated_at
          }
        }
        """
        let result: Response = try await gql.authenticatedRequest(query: query, variables: ["limit": limit, "offset": offset])
        return result.browseProfiles.map(\.toModel)
    }

    func profileByID(_ userID: String) async throws -> Profile? {
        struct Response: Decodable { let profileById: GraphQLProfile? }
        let query = """
        query ProfileById($user_id: ID!) {
          profileById(user_id: $user_id) {
            user_id email display_name username avatar_url
            country_name country_code city_name bio created_at updated_at
          }
        }
        """
        if let result: Response = try? await gql.request(
            query: query,
            variables: ["user_id": userID]
        ) {
            return result.profileById?.toModel
        }

        let result: Response = try await gql.authenticatedRequest(query: query, variables: ["user_id": userID])
        return result.profileById?.toModel
    }

    func globalStats() async throws -> GlobalStats {
        struct Response: Decodable {
            let globalStats: GraphQLGlobalStats
        }

        let query = """
        query GlobalStats {
          globalStats { totalUsers onlineNow ttlSeconds computedAt }
        }
        """

        let result: Response = try await gql.authenticatedRequest(query: query)
        return GlobalStats(
            totalUsers: result.globalStats.totalUsers,
            onlineUsers: result.globalStats.onlineNow
        )
    }

    func countryStats(_ code: String) async throws -> CountryStats {
        struct Response: Decodable {
            let countryStats: GraphQLCountryStats
        }

        let query = """
        query CountryStats($iso: String!) {
          countryStats(iso: $iso) {
            iso name totalUsers onlineNow
          }
        }
        """

        let result: Response = try await gql.authenticatedRequest(
            query: query,
            variables: ["iso": code.uppercased()],

        )
        return CountryStats(
            countryCode: result.countryStats.iso,
            totalUsers: result.countryStats.totalUsers,
            onlineUsers: result.countryStats.onlineNow
        )
    }
}

private struct GraphQLCountry: Decodable {
    let id: String
    let name: String
    let iso: String
    let continent: String?
    let center: GraphQLLatLng?

    enum CodingKeys: String, CodingKey {
        case id, name, iso, continent, center
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let stringID = try? container.decode(String.self, forKey: .id) {
            id = stringID
        } else {
            let intID = try container.decode(Int.self, forKey: .id)
            id = String(intID)
        }
        name = try container.decode(String.self, forKey: .name)
        iso = try container.decode(String.self, forKey: .iso)
        continent = try container.decodeIfPresent(String.self, forKey: .continent)
        center = try container.decodeIfPresent(GraphQLLatLng.self, forKey: .center)
    }

    var toModel: Country {
        Country(
            id: id,
            name: name,
            iso: iso.uppercased(),
            continent: continent,
            centerLat: center?.lat,
            centerLng: center?.lng
        )
    }
}

private struct GraphQLLatLng: Decodable {
    let lat: Double
    let lng: Double
}

private struct GraphQLGlobalStats: Decodable {
    let totalUsers: Int
    let onlineNow: Int
}

private struct GraphQLCountryStats: Decodable {
    let iso: String
    let name: String?
    let totalUsers: Int
    let onlineNow: Int
}

private struct GraphQLDetectedLocation: Decodable {
    let countryCode: String
    let countryName: String
    let cityName: String?
    let source: String

    var toModel: DetectedLocation {
        DetectedLocation(
            countryCode: countryCode,
            countryName: countryName,
            cityName: cityName,
            source: source
        )
    }
}