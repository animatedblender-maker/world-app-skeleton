import Foundation

enum JSONCoding {
    static func decode<T: Decodable>(_ type: T.Type, from dict: [String: Any]) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(type, from: data)
    }

    static func decodeArray<T: Decodable>(_ type: T.Type, from array: [[String: Any]]) throws -> [T] {
        let data = try JSONSerialization.data(withJSONObject: array)
        return try JSONDecoder().decode([T].self, from: data)
    }
}

extension CountryPost {
    static func fromGraphQL(_ row: [String: Any]) -> CountryPost {
        CountryPost(
            id: row["id"] as? String ?? UUID().uuidString,
            title: row["title"] as? String,
            body: row["body"] as? String ?? "",
            mediaType: row["media_type"] as? String,
            mediaURL: row["media_url"] as? String,
            thumbURL: row["thumb_url"] as? String,
            mediaCaption: row["media_caption"] as? String,
            sharedPostID: row["shared_post_id"] as? String,
            visibility: PostVisibility(rawValue: row["visibility"] as? String ?? "public") ?? .public,
            likeCount: row["like_count"] as? Int ?? 0,
            commentCount: row["comment_count"] as? Int ?? 0,
            viewCount: row["view_count"] as? Int ?? 0,
            likedByMe: row["liked_by_me"] as? Bool ?? false,
            savedByMe: row["saved_by_me"] as? Bool ?? false,
            createdAt: row["created_at"] as? String ?? "",
            updatedAt: row["updated_at"] as? String ?? "",
            authorID: row["author_id"] as? String ?? "",
            countryName: row["country_name"] as? String,
            countryCode: row["country_code"] as? String,
            cityName: row["city_name"] as? String,
            author: PostAuthor.fromGraphQL(row["author"] as? [String: Any])
        )
    }
}

extension PostAuthor {
    static func fromGraphQL(_ row: [String: Any]?) -> PostAuthor? {
        guard let row, let userID = row["user_id"] as? String else { return nil }
        return PostAuthor(
            userID: userID,
            displayName: row["display_name"] as? String,
            username: row["username"] as? String,
            avatarURL: row["avatar_url"] as? String,
            countryName: row["country_name"] as? String,
            countryCode: row["country_code"] as? String,
            lastReadAt: row["last_read_at"] as? String
        )
    }
}

extension Profile {
    static func fromGraphQL(_ row: [String: Any]?) -> Profile? {
        guard let row, let userID = row["user_id"] as? String else { return nil }
        return Profile(
            userID: userID,
            email: row["email"] as? String,
            displayName: row["display_name"] as? String,
            username: row["username"] as? String,
            avatarURL: row["avatar_url"] as? String,
            countryName: row["country_name"] as? String,
            countryCode: row["country_code"] as? String,
            cityName: row["city_name"] as? String,
            bio: row["bio"] as? String,
            followersCount: row["followers_count"] as? Int,
            followingCount: row["following_count"] as? Int,
            createdAt: row["created_at"] as? String ?? "",
            updatedAt: row["updated_at"] as? String ?? ""
        )
    }
}

extension Country {
    static func fromGraphQL(_ row: [String: Any]) -> Country {
        let center = row["center"] as? [String: Any]
        return Country(
            id: row["id"] as? String ?? row["iso"] as? String ?? UUID().uuidString,
            name: row["name"] as? String ?? "",
            iso: row["iso"] as? String ?? "",
            continent: row["continent"] as? String,
            centerLat: center?["lat"] as? Double,
            centerLng: center?["lng"] as? Double
        )
    }
}

extension Message {
    static func fromGraphQL(_ row: [String: Any]) -> Message {
        Message(
            id: row["id"] as? String ?? UUID().uuidString,
            conversationID: row["conversation_id"] as? String ?? "",
            senderID: row["sender_id"] as? String ?? "",
            body: row["body"] as? String ?? "",
            mediaType: row["media_type"] as? String,
            mediaPath: row["media_path"] as? String,
            mediaURL: row["media_url"] as? String,
            mediaName: row["media_name"] as? String,
            createdAt: row["created_at"] as? String ?? "",
            updatedAt: row["updated_at"] as? String ?? "",
            sender: PostAuthor.fromGraphQL(row["sender"] as? [String: Any])
        )
    }
}

extension Conversation {
    static func fromGraphQL(_ row: [String: Any]) -> Conversation {
        let members = (row["members"] as? [[String: Any]] ?? [])
            .compactMap { PostAuthor.fromGraphQL($0) }
        let lastMessageRow = row["last_message"] as? [String: Any]
        return Conversation(
            id: row["id"] as? String ?? UUID().uuidString,
            isDirect: row["is_direct"] as? Bool ?? true,
            createdAt: row["created_at"] as? String ?? "",
            updatedAt: row["updated_at"] as? String ?? "",
            lastMessageAt: row["last_message_at"] as? String,
            members: members,
            lastMessage: lastMessageRow.map { Message.fromGraphQL($0) }
        )
    }
}