import Foundation

@MainActor
final class NewsService {
    static let shared = NewsService()

    private let gql = GraphQLService.shared
    private init() {}

    func countryConflictUpdates(_ countryCode: String, limit: Int = 10) async throws -> [ExternalNewsItem] {
        struct Response: Decodable { let countryConflictUpdates: [GraphQLNewsItem] }
        let query = """
        query($country_code: String!, $limit: Int) {
          countryConflictUpdates(country_code: $country_code, limit: $limit) {
            id provider title url source_name published_at country_codes country_names
            disaster_types theme_names snippet image_url like_count liked_by_me
            comment_count shared_post_count
          }
        }
        """
        let result: Response = try await gql.authenticatedRequest(
            query: query,
            variables: ["country_code": countryCode.uppercased(), "limit": limit],

        )
        return result.countryConflictUpdates.map(\.toModel)
    }

    func item(_ newsItemID: String) async throws -> ExternalNewsItem? {
        struct Response: Decodable { let externalNewsItem: GraphQLNewsItem? }
        let query = """
        query($news_item_id: ID!) {
          externalNewsItem(news_item_id: $news_item_id) {
            id provider title url source_name published_at country_codes country_names
            disaster_types theme_names snippet image_url like_count liked_by_me
            comment_count shared_post_count
          }
        }
        """
        let result: Response = try await gql.authenticatedRequest(
            query: query,
            variables: ["news_item_id": newsItemID],

        )
        return result.externalNewsItem?.toModel
    }

    func comments(_ newsItemID: String, limit: Int = 25) async throws -> [ExternalNewsComment] {
        struct Response: Decodable { let externalNewsComments: [GraphQLNewsComment] }
        let query = """
        query($news_item_id: ID!, $limit: Int) {
          externalNewsComments(news_item_id: $news_item_id, limit: $limit) {
            id news_item_id parent_id author_id body created_at updated_at
            author { user_id display_name username avatar_url country_name country_code }
          }
        }
        """
        let result: Response = try await gql.authenticatedRequest(
            query: query,
            variables: ["news_item_id": newsItemID, "limit": limit],

        )
        return result.externalNewsComments.map(\.toModel)
    }

    func addComment(_ newsItemID: String, body: String, parentID: String? = nil) async throws -> ExternalNewsComment {
        struct Response: Decodable { let addExternalNewsComment: GraphQLNewsComment }
        let mutation = """
        mutation($news_item_id: ID!, $body: String!, $parent_id: ID) {
          addExternalNewsComment(news_item_id: $news_item_id, body: $body, parent_id: $parent_id) {
            id news_item_id parent_id author_id body created_at updated_at
            author { user_id display_name username avatar_url country_name country_code }
          }
        }
        """
        var vars: [String: Any] = ["news_item_id": newsItemID, "body": body]
        if let parentID { vars["parent_id"] = parentID }
        let result: Response = try await gql.authenticatedRequest(query: mutation, variables: vars)
        return result.addExternalNewsComment.toModel
    }

    func like(_ newsItemID: String) async throws -> ExternalNewsItem {
        struct Response: Decodable { let likeExternalNews: GraphQLNewsItem }
        let mutation = """
        mutation($news_item_id: ID!) {
          likeExternalNews(news_item_id: $news_item_id) {
            id provider title url source_name published_at country_codes country_names
            disaster_types theme_names snippet image_url like_count liked_by_me
            comment_count shared_post_count
          }
        }
        """
        let result: Response = try await gql.authenticatedRequest(query: mutation, variables: ["news_item_id": newsItemID])
        return result.likeExternalNews.toModel
    }

    func unlike(_ newsItemID: String) async throws -> ExternalNewsItem {
        struct Response: Decodable { let unlikeExternalNews: GraphQLNewsItem }
        let mutation = """
        mutation($news_item_id: ID!) {
          unlikeExternalNews(news_item_id: $news_item_id) {
            id provider title url source_name published_at country_codes country_names
            disaster_types theme_names snippet image_url like_count liked_by_me
            comment_count shared_post_count
          }
        }
        """
        let result: Response = try await gql.authenticatedRequest(query: mutation, variables: ["news_item_id": newsItemID])
        return result.unlikeExternalNews.toModel
    }

    func shareToCountry(_ newsItemID: String, body: String?) async throws -> CountryPost {
        struct Response: Decodable { let shareExternalNewsToCountry: GraphQLPost }
        let mutation = """
        mutation($news_item_id: ID!, $body: String) {
          shareExternalNewsToCountry(news_item_id: $news_item_id, body: $body, visibility: "country") {
            id title body media_type media_url thumb_url visibility like_count comment_count
            liked_by_me created_at updated_at author_id country_name country_code city_name
            author { user_id display_name username avatar_url country_name country_code }
          }
        }
        """
        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["news_item_id": newsItemID, "body": body as Any],

        )
        return result.shareExternalNewsToCountry.toModel
    }
}

struct GraphQLNewsItem: Decodable {
    let id: String
    let provider: String
    let title: String
    let url: String
    let sourceName: String?
    let publishedAt: String?
    let countryCodes: [String]
    let countryNames: [String]
    let disasterTypes: [String]
    let themeNames: [String]
    let snippet: String?
    let imageURL: String?
    let likeCount: Int
    let likedByMe: Bool
    let commentCount: Int
    let sharedPostCount: Int

    enum CodingKeys: String, CodingKey {
        case id, provider, title, url, snippet
        case sourceName = "source_name"
        case publishedAt = "published_at"
        case countryCodes = "country_codes"
        case countryNames = "country_names"
        case disasterTypes = "disaster_types"
        case themeNames = "theme_names"
        case imageURL = "image_url"
        case likeCount = "like_count"
        case likedByMe = "liked_by_me"
        case commentCount = "comment_count"
        case sharedPostCount = "shared_post_count"
    }

    var toModel: ExternalNewsItem {
        ExternalNewsItem(
            id: id, provider: provider, title: title, url: url,
            sourceName: sourceName, publishedAt: publishedAt,
            countryCodes: countryCodes, countryNames: countryNames,
            disasterTypes: disasterTypes, themeNames: themeNames,
            snippet: snippet, imageURL: imageURL,
            likeCount: likeCount, likedByMe: likedByMe,
            commentCount: commentCount, sharedPostCount: sharedPostCount
        )
    }
}

struct GraphQLNewsComment: Decodable {
    let id: String
    let newsItemID: String
    let parentID: String?
    let authorID: String
    let body: String
    let createdAt: String
    let updatedAt: String
    let author: GraphQLAuthor?

    enum CodingKeys: String, CodingKey {
        case id, body, author
        case newsItemID = "news_item_id"
        case parentID = "parent_id"
        case authorID = "author_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var toModel: ExternalNewsComment {
        ExternalNewsComment(
            id: id, newsItemID: newsItemID, parentID: parentID,
            authorID: authorID, body: body, createdAt: createdAt,
            updatedAt: updatedAt, author: author?.toModel
        )
    }
}