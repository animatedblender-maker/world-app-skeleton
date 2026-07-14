import Foundation

struct EmptyMutation: Decodable {
    init(from decoder: Decoder) throws {}
}

struct GraphQLPost: Decodable {
    let id: String
    let title: String?
    let body: String
    let mediaType: String?
    let mediaURL: String?
    let thumbURL: String?
    let sharedPostID: String?
    let sharedPost: GraphQLSharedPost?
    let visibility: String
    let likeCount: Int
    let commentCount: Int
    let likedByMe: Bool
    let savedByMe: Bool?
    let createdAt: String
    let updatedAt: String
    let authorID: String
    let countryName: String?
    let countryCode: String?
    let cityName: String?
    let author: GraphQLAuthor?

    enum CodingKeys: String, CodingKey {
        case id, title, body, visibility, author
        case mediaType = "media_type"
        case mediaURL = "media_url"
        case thumbURL = "thumb_url"
        case sharedPostID = "shared_post_id"
        case sharedPost = "shared_post"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case likedByMe = "liked_by_me"
        case savedByMe = "saved_by_me"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case authorID = "author_id"
        case countryName = "country_name"
        case countryCode = "country_code"
        case cityName = "city_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType)
        mediaURL = try container.decodeIfPresent(String.self, forKey: .mediaURL)
        thumbURL = try container.decodeIfPresent(String.self, forKey: .thumbURL)
        sharedPostID = try container.decodeIfPresent(String.self, forKey: .sharedPostID)
        sharedPost = try container.decodeIfPresent(GraphQLSharedPost.self, forKey: .sharedPost)
        visibility = try container.decodeIfPresent(String.self, forKey: .visibility) ?? "public"
        likeCount = try container.decodeLossyInt(forKey: .likeCount)
        commentCount = try container.decodeLossyInt(forKey: .commentCount)
        likedByMe = try container.decodeLossyBool(forKey: .likedByMe)
        savedByMe = try container.decodeIfPresent(Bool.self, forKey: .savedByMe)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? createdAt
        authorID = try container.decodeIfPresent(String.self, forKey: .authorID) ?? ""
        countryName = try container.decodeIfPresent(String.self, forKey: .countryName)
        countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode)
        cityName = try container.decodeIfPresent(String.self, forKey: .cityName)
        author = try container.decodeIfPresent(GraphQLAuthor.self, forKey: .author)
    }

    var toModel: CountryPost {
        CountryPost(
            id: id, title: title, body: body,
            mediaType: mediaType, mediaURL: mediaURL, thumbURL: thumbURL,
            sharedPostID: sharedPostID,
            sharedPost: sharedPost?.toPreview,
            visibility: PostVisibility(rawValue: visibility) ?? .public,
            likeCount: likeCount, commentCount: commentCount, viewCount: 0,
            likedByMe: likedByMe, savedByMe: savedByMe ?? false,
            createdAt: createdAt, updatedAt: updatedAt,
            authorID: authorID, countryName: countryName, countryCode: countryCode,
            cityName: cityName, author: author?.toModel
        )
    }
}

struct GraphQLSharedPost: Decodable {
    let id: String
    let title: String?
    let body: String
    let mediaType: String?
    let mediaURL: String?
    let thumbURL: String?
    let authorID: String
    let author: GraphQLAuthor?

    enum CodingKeys: String, CodingKey {
        case id, title, body, author
        case mediaType = "media_type"
        case mediaURL = "media_url"
        case thumbURL = "thumb_url"
        case authorID = "author_id"
    }

    var toPreview: SharedPostPreview {
        SharedPostPreview(
            id: id,
            title: title,
            body: body,
            mediaType: mediaType,
            mediaURL: mediaURL,
            thumbURL: thumbURL,
            authorID: authorID,
            author: author?.toModel
        )
    }
}

struct GraphQLAuthor: Decodable {
    let userID: String
    let displayName: String?
    let username: String?
    let avatarURL: String?
    let countryName: String?
    let countryCode: String?
    let lastReadAt: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case username
        case avatarURL = "avatar_url"
        case countryName = "country_name"
        case countryCode = "country_code"
        case lastReadAt = "last_read_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decodeIfPresent(String.self, forKey: .userID) ?? ""
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        avatarURL = try container.decodeIfPresent(String.self, forKey: .avatarURL)
        countryName = try container.decodeIfPresent(String.self, forKey: .countryName)
        countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode)
        lastReadAt = try container.decodeIfPresent(String.self, forKey: .lastReadAt)
    }

    var toModel: PostAuthor {
        PostAuthor(
            userID: userID, displayName: displayName, username: username,
            avatarURL: avatarURL, countryName: countryName, countryCode: countryCode,
            lastReadAt: lastReadAt
        )
    }

    var toModelIfValid: PostAuthor? {
        let normalized = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return PostAuthor(
            userID: normalized, displayName: displayName, username: username,
            avatarURL: avatarURL, countryName: countryName, countryCode: countryCode,
            lastReadAt: lastReadAt
        )
    }
}

struct GraphQLComment: Decodable {
    let id: String
    let postID: String
    let parentID: String?
    let authorID: String
    let body: String
    let likeCount: Int
    let likedByMe: Bool
    let createdAt: String
    let updatedAt: String
    let author: GraphQLAuthor?

    enum CodingKeys: String, CodingKey {
        case id, body, author
        case postID = "post_id"
        case parentID = "parent_id"
        case authorID = "author_id"
        case likeCount = "like_count"
        case likedByMe = "liked_by_me"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        postID = try container.decode(String.self, forKey: .postID)
        let rawParentID = try container.decodeIfPresent(String.self, forKey: .parentID)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        parentID = (rawParentID?.isEmpty == false) ? rawParentID : nil
        authorID = try container.decode(String.self, forKey: .authorID)
        body = try container.decode(String.self, forKey: .body)
        likeCount = try container.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
        likedByMe = try container.decodeIfPresent(Bool.self, forKey: .likedByMe) ?? false
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        author = try container.decodeIfPresent(GraphQLAuthor.self, forKey: .author)
    }

    var toModel: PostComment {
        PostComment(
            id: id, postID: postID, parentID: parentID, authorID: authorID,
            body: body, likeCount: likeCount, likedByMe: likedByMe,
            createdAt: createdAt, updatedAt: updatedAt, author: author?.toModel
        )
    }
}

struct GraphQLProfile: Decodable {
    let userID: String
    let email: String?
    let displayName: String?
    let username: String?
    let avatarURL: String?
    let countryName: String?
    let countryCode: String?
    let cityName: String?
    let bio: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case email
        case displayName = "display_name"
        case username
        case avatarURL = "avatar_url"
        case countryName = "country_name"
        case countryCode = "country_code"
        case cityName = "city_name"
        case bio
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var toModel: Profile {
        Profile(
            userID: userID, email: email, displayName: displayName, username: username,
            avatarURL: avatarURL, countryName: countryName, countryCode: countryCode,
            cityName: cityName, bio: bio, followersCount: nil, followingCount: nil,
            createdAt: createdAt ?? "", updatedAt: updatedAt ?? ""
        )
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyInt(forKey key: Key) throws -> Int {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(String.self, forKey: key), let parsed = Int(value) { return parsed }
        return 0
    }

    func decodeLossyBool(forKey key: Key) throws -> Bool {
        if let value = try? decode(Bool.self, forKey: key) { return value }
        if let value = try? decode(String.self, forKey: key) {
            return value == "true" || value == "1"
        }
        return false
    }
}