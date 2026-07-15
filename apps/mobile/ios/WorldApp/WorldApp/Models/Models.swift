import Foundation

enum PostVisibility: String, Codable, Sendable {
    case `public`, followers, `private`, country
}

struct PostAuthor: Codable, Identifiable, Hashable, Sendable {
    var id: String { userID }
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
}

struct PostMediaPayload: Sendable {
    let urls: [String]
    let types: [String]
    let isReel: Bool
    let isStory: Bool
    let expiresAt: Date?

    static func parse(from mediaURL: String?) -> PostMediaPayload? {
        guard let raw = mediaURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        if raw.hasPrefix("{") || raw.hasPrefix("[") {
            guard let data = raw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data)
            else { return nil }

            if let array = json as? [String] {
                let urls = array.filter { !$0.isEmpty }
                guard !urls.isEmpty else { return nil }
                return PostMediaPayload(
                    urls: urls,
                    types: urls.map { inferMediaType(from: $0) },
                    isReel: false,
                    isStory: false,
                    expiresAt: nil
                )
            }

            guard let object = json as? [String: Any] else { return nil }

            let urls: [String]
            if let list = object["urls"] as? [String] {
                urls = list.filter { !$0.isEmpty }
            } else if let single = object["url"] as? String, !single.isEmpty {
                urls = [single]
            } else {
                urls = []
            }

            let types: [String]
            if let list = object["types"] as? [String], !list.isEmpty {
                if list.count == urls.count {
                    types = list
                } else {
                    types = urls.enumerated().map { index, url in
                        if index < list.count, !list[index].isEmpty {
                            return list[index]
                        }
                        return inferMediaType(from: url)
                    }
                }
            } else {
                types = urls.map { inferMediaType(from: $0) }
            }

            let reel = boolValue(object["reel"])
            let story = boolValue(object["story"])
            let expiresAt = parseDate(object["expires_at"] as? String)
            return PostMediaPayload(urls: urls, types: types, isReel: reel, isStory: story, expiresAt: expiresAt)
        }

        return PostMediaPayload(
            urls: [raw],
            types: [inferMediaType(from: raw)],
            isReel: false,
            isStory: false,
            expiresAt: nil
        )
    }

    static func encode(
        urls: [String],
        types: [String],
        reel: Bool = false,
        story: Bool = false,
        expiresAt: Date? = nil
    ) -> String? {
        guard !urls.isEmpty else { return nil }
        var object: [String: Any] = [
            "urls": urls,
            "types": types,
        ]
        if reel { object["reel"] = true }
        if story { object["story"] = true }
        if let expiresAt {
            object["expires_at"] = ISO8601DateFormatter().string(from: expiresAt)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        return json
    }

    var primaryURL: String? { urls.first }

    var primaryType: String? { types.first }

    private static func boolValue(_ value: Any?) -> Bool {
        switch value {
        case let flag as Bool:
            return flag
        case let number as Int:
            return number != 0
        case let number as Double:
            return number != 0
        case let text as String:
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == "true" || normalized == "1" || normalized == "yes"
        default:
            return false
        }
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func inferMediaType(from url: String) -> String {
        let lower = url.lowercased()
        if lower.range(
            of: #"\.(mp4|webm|mov|m4v|avi|mkv)(\?|#|$)"#,
            options: .regularExpression
        ) != nil || lower.contains("/video") || lower.contains("video%") {
            return "video"
        }
        return "image"
    }
}

enum LivingChannelMarker {
    private static let prefix = "__living_channel__|"

    static func parse(from bio: String?) -> String? {
        guard let bio else { return nil }
        for line in bio.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix(prefix) else { continue }
            for part in trimmed.dropFirst(prefix.count).split(separator: "|") {
                if part.hasPrefix("name=") {
                    let name = String(part.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                    return name.isEmpty ? nil : name
                }
            }
        }
        return nil
    }

    static func displayBio(from rawBio: String?) -> String {
        guard let rawBio else { return "" }
        return rawBio
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(prefix) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func buildBio(displayBio: String, channelName: String?) -> String {
        var lines: [String] = []
        let cleaned = displayBio.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty { lines.append(cleaned) }
        if let channelName {
            let trimmed = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                lines.append("\(prefix)name=\(trimmed)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

struct LivingChannel: Identifiable, Hashable {
    let id: String
    let authorID: String
    let title: String
    let author: PostAuthor?
    let videos: [CountryPost]

    var videoCount: Int { videos.count }
    var latestVideo: CountryPost? { videos.first }
}

enum PostStoryMarker {
    static func buildBody(caption: String, expiresAt: Date) -> String {
        let marker = markerLine(expiresAt: expiresAt)
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return marker }
        return "\(trimmed)\n\(marker)"
    }

    static func expiresAt(from body: String) -> Date? {
        for line in body.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("__story__|expires=") else { continue }
            let iso = String(trimmed.dropFirst("__story__|expires=".count))
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: iso) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: iso)
        }
        return nil
    }

    private static func markerLine(expiresAt: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return "__story__|expires=\(formatter.string(from: expiresAt))"
    }
}

struct SharedPostPreview: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let title: String?
    let body: String
    let mediaType: String?
    let mediaURL: String?
    let thumbURL: String?
    let authorID: String
    let author: PostAuthor?

    var asCountryPost: CountryPost {
        CountryPost(
            id: id,
            title: title,
            body: body,
            mediaType: mediaType,
            mediaURL: mediaURL,
            thumbURL: thumbURL,
            createdAt: "",
            updatedAt: "",
            authorID: authorID,
            author: author
        )
    }

    var displayExcerpt: String { asCountryPost.displayExcerpt }
    var hasMedia: Bool { asCountryPost.hasMedia }
    var hasVideo: Bool { asCountryPost.hasVideo }
    var feedImageURL: URL? { asCountryPost.feedImageURL }
}

struct CountryPost: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let title: String?
    let body: String
    let mediaType: String?
    let mediaURL: String?
    let thumbURL: String?
    let mediaCaption: String?
    let sharedPostID: String?
    let sharedPost: SharedPostPreview?
    let visibility: PostVisibility
    let likeCount: Int
    let commentCount: Int
    let viewCount: Int
    let likedByMe: Bool
    let savedByMe: Bool
    let createdAt: String
    let updatedAt: String
    let authorID: String
    let countryName: String?
    let countryCode: String?
    let cityName: String?
    let author: PostAuthor?
    let linkURL: String?
    let linkTitle: String?
    let externalRefType: String?
    let externalRefID: String?

    init(
        id: String,
        title: String? = nil,
        body: String,
        mediaType: String? = nil,
        mediaURL: String? = nil,
        thumbURL: String? = nil,
        mediaCaption: String? = nil,
        sharedPostID: String? = nil,
        sharedPost: SharedPostPreview? = nil,
        visibility: PostVisibility = .public,
        likeCount: Int = 0,
        commentCount: Int = 0,
        viewCount: Int = 0,
        likedByMe: Bool = false,
        savedByMe: Bool = false,
        createdAt: String,
        updatedAt: String,
        authorID: String,
        countryName: String? = nil,
        countryCode: String? = nil,
        cityName: String? = nil,
        author: PostAuthor? = nil,
        linkURL: String? = nil,
        linkTitle: String? = nil,
        externalRefType: String? = nil,
        externalRefID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.mediaType = mediaType
        self.mediaURL = mediaURL
        self.thumbURL = thumbURL
        self.mediaCaption = mediaCaption
        self.sharedPostID = sharedPostID
        self.sharedPost = sharedPost
        self.visibility = visibility
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.viewCount = viewCount
        self.likedByMe = likedByMe
        self.savedByMe = savedByMe
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.authorID = authorID
        self.countryName = countryName
        self.countryCode = countryCode
        self.cityName = cityName
        self.author = author
        self.linkURL = linkURL
        self.linkTitle = linkTitle
        self.externalRefType = externalRefType
        self.externalRefID = externalRefID
    }

    var createdDate: Date? { RelativeTime.parseDate(createdAt) }
    var updatedDate: Date? { RelativeTime.parseDate(updatedAt) }

    var isEdited: Bool {
        guard let created = createdDate, let updated = updatedDate else { return false }
        return updated.timeIntervalSince(created) > 1
    }

    var privacyLabel: String {
        switch visibility {
        case .public: "Public"
        case .followers: "Followers"
        case .private: "Only me"
        case .country: "Country"
        }
    }

    func withSavedByMe(_ saved: Bool) -> CountryPost {
        CountryPost(
            id: id,
            title: title,
            body: body,
            mediaType: mediaType,
            mediaURL: mediaURL,
            thumbURL: thumbURL,
            mediaCaption: mediaCaption,
            sharedPostID: sharedPostID,
            sharedPost: sharedPost,
            visibility: visibility,
            likeCount: likeCount,
            commentCount: commentCount,
            viewCount: viewCount,
            likedByMe: likedByMe,
            savedByMe: saved,
            createdAt: createdAt,
            updatedAt: updatedAt,
            authorID: authorID,
            countryName: countryName,
            countryCode: countryCode,
            cityName: cityName,
            author: author,
            linkURL: linkURL,
            linkTitle: linkTitle,
            externalRefType: externalRefType,
            externalRefID: externalRefID
        )
    }

    var primaryMediaURL: String? {
        resolvedMediaURLs.first ?? mediaURL ?? thumbURL
    }

    var hasVideo: Bool {
        let type = (mediaType ?? "").lowercased()
        if type == "video" || type == "reel" { return true }
        if let payload = mediaPayload {
            return payload.types.contains { $0.lowercased() == "video" }
        }
        guard let url = primaryMediaURL?.lowercased() else { return false }
        return url.range(
            of: #"\.(mp4|webm|mov|m4v|avi|mkv)(\?|#|$)"#,
            options: .regularExpression
        ) != nil || url.contains("/video") || url.contains("video%")
    }

    var hasImage: Bool {
        if hasVideo || isStory || isReel { return false }
        let type = (mediaType ?? "").lowercased()
        if type == "image" { return primaryMediaURL != nil }
        if let payload = mediaPayload {
            return payload.types.contains { $0.lowercased() == "image" }
        }
        return hasMedia && !hasVideo
    }

    var hasMedia: Bool {
        if isStory || isReel { return primaryMediaURL != nil }
        let type = (mediaType ?? "").lowercased()
        return type != "none" && type != "" && primaryMediaURL != nil
    }

    var isDemoPost: Bool { authorID.hasPrefix("user_") }

    var mediaPayload: PostMediaPayload? { PostMediaPayload.parse(from: mediaURL) }

    var resolvedMediaURLs: [String] {
        if let payload = mediaPayload, !payload.urls.isEmpty { return payload.urls }
        if let mediaURL, !mediaURL.isEmpty { return [mediaURL] }
        return []
    }

    var isReel: Bool {
        let type = (mediaType ?? "").lowercased()
        if type == "reel" || type == "spark" { return true }
        if mediaPayload?.isReel == true { return true }
        if let mediaURL {
            let normalized = mediaURL.lowercased()
            if normalized.contains("\"reel\":true") || normalized.contains("\"reel\": true") {
                return true
            }
        }
        if body.contains("__spark__|") || body.contains("__reel__|") { return true }
        return false
    }

    var isStory: Bool {
        if body.contains("__story__|") { return true }
        if (mediaType ?? "").lowercased() == "story" { return true }
        return mediaPayload?.isStory == true
    }

    /// Sparks belong in the vertical sparks scroll only — not the home feed or profile grids.
    var isSpark: Bool { isReel }

    var storyExpiresAt: Date? {
        if let expiresAt = mediaPayload?.expiresAt { return expiresAt }
        if let parsed = PostStoryMarker.expiresAt(from: body) { return parsed }
        guard isStory, let created = createdDate else { return nil }
        return created.addingTimeInterval(86_400)
    }

    var isStoryActive: Bool {
        guard isStory else { return false }
        guard let expiresAt = storyExpiresAt else { return true }
        return expiresAt > Date()
    }

    var displayTitle: String? { ContentSanitizer.clean(title) }

    var displayBody: String { ContentSanitizer.clean(body) ?? "" }

    var displayCaption: String? {
        ContentSanitizer.clean(mediaCaption)
    }

    var displayHeadline: String? {
        if let title = displayTitle { return title }
        let text = displayBody
        if text.isEmpty { return nil }
        return String(text.prefix(72))
    }

    var displayExcerpt: String {
        let text = displayBody
        guard let title = displayTitle, !title.isEmpty else { return text }
        if text == title { return "" }
        return text
    }

    var authorDisplayName: String {
        ContentSanitizer.displayName(
            displayName: author?.displayName,
            username: author?.username
        )
    }
}

extension Array where Element == CountryPost {
    func excludingSparks() -> [CountryPost] {
        filter { !$0.isSpark }
    }

    func excludingMoments() -> [CountryPost] {
        filter { !$0.isStory }
    }
}

struct StoryGroup: Identifiable, Hashable, Sendable {
    let authorID: String
    let author: PostAuthor?
    let stories: [CountryPost]
    let hasUnviewed: Bool

    var id: String { authorID }

    var displayName: String {
        ContentSanitizer.displayName(
            displayName: author?.displayName,
            username: author?.username
        )
    }
}

struct StoryViewerContext: Identifiable {
    let id = UUID()
    let groups: [StoryGroup]
    var groupIndex: Int
    var storyIndex: Int
}

struct ReelsViewerContext: Identifiable {
    let id = UUID()
    let startingPost: CountryPost
    let seedPosts: [CountryPost]

    var startingPostID: String { startingPost.id }
}

enum CreateContentSheet: String, Identifiable {
    case post, video, reel, story
    var id: String { rawValue }
}

struct PostComment: Identifiable, Hashable, Sendable {
    let id: String
    let postID: String
    let parentID: String?
    let authorID: String
    let body: String
    let likeCount: Int
    let likedByMe: Bool
    let createdAt: String
    let updatedAt: String
    let author: PostAuthor?

    func withParentID(_ parentID: String?) -> PostComment {
        PostComment(
            id: id,
            postID: postID,
            parentID: parentID,
            authorID: authorID,
            body: body,
            likeCount: likeCount,
            likedByMe: likedByMe,
            createdAt: createdAt,
            updatedAt: updatedAt,
            author: author
        )
    }
}

struct Country: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let iso: String
    let continent: String?
    let centerLat: Double?
    let centerLng: Double?
}

struct DetectedLocation: Sendable {
    let countryCode: String
    let countryName: String
    let cityName: String?
    let source: String
}

struct Profile: Identifiable, Hashable, Sendable, Codable {
    var id: String { userID }
    let userID: String
    let email: String?
    let displayName: String?
    let username: String?
    let avatarURL: String?
    let countryName: String?
    let countryCode: String?
    let cityName: String?
    let bio: String?
    let followersCount: Int?
    let followingCount: Int?
    let createdAt: String
    let updatedAt: String

    var isComplete: Bool {
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let country = countryName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !name.isEmpty && !country.isEmpty && country != "Unknown"
    }

    var isDemoUser: Bool { userID.hasPrefix("user_") }
}

struct Message: Identifiable, Hashable, Sendable {
    let id: String
    let conversationID: String
    let senderID: String
    let body: String
    let mediaType: String?
    let mediaPath: String?
    let mediaURL: String?
    let mediaName: String?
    let createdAt: String
    let updatedAt: String
    let sender: PostAuthor?

    var hasImage: Bool {
        let type = (mediaType ?? "").lowercased()
        return type == "image" && (mediaPath != nil || mediaURL != nil)
    }

    var isReaction: Bool {
        Self.parseReaction(body) != nil
    }

    var reactionInfo: ReactionInfo? {
        Self.parseReaction(body)
    }

    var isCallLog: Bool {
        Self.parseCallLog(body) != nil
    }

    var isRenderableInChat: Bool {
        if isReaction { return false }
        if isCallLog { return true }
        if hasImage { return true }
        if displayText != nil { return true }
        return false
    }

    var previewText: String {
        if isReaction { return "Liked a message" }
        if let callLog = Self.parseCallLog(body) {
            return Self.formatCallLog(callLog)
        }
        if let text = displayText, !text.isEmpty { return text }
        if hasImage { return "Photo" }
        if (mediaType ?? "").lowercased() == "video" { return "Video" }
        return "Media message"
    }

    var displayText: String? {
        if isReaction { return nil }
        if let callLog = Self.parseCallLog(body) {
            return Self.formatCallLog(callLog)
        }
        if let reply = Self.parseReply(body) {
            var replyBody = Self.stripTrailingMeta(reply.body.trimmingCharacters(in: .whitespacesAndNewlines))
            replyBody = Self.stripIdOnlyLines(replyBody)
            return ContentSanitizer.clean(replyBody)
        }

        var text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        text = Self.stripTrailingMeta(text)
        text = Self.stripIdOnlyLines(text)
        guard let cleaned = ContentSanitizer.clean(text) else { return nil }
        if cleaned == id || cleaned == conversationID || cleaned == senderID { return nil }
        if cleaned == mediaPath || cleaned == mediaName { return nil }
        return cleaned
    }

    var timestampLabel: String {
        RelativeTime.formatClock(createdAt)
    }

    var isEdited: Bool {
        guard let created = RelativeTime.parseDate(createdAt),
              let updated = RelativeTime.parseDate(updatedAt)
        else { return false }
        return updated.timeIntervalSince(created) > 1
    }

    static func callLogBody(status: String, kind: String, durationSeconds: Int) -> String {
        let duration = max(0, durationSeconds)
        return "__call__|status=\(status)|kind=\(kind)|duration=\(duration)"
    }

    static func parseCallLog(_ body: String) -> CallLogInfo? {
        let cleaned = body.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let unquoted: String
        if (cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"")) || (cleaned.hasPrefix("'") && cleaned.hasSuffix("'")) {
            unquoted = String(cleaned.dropFirst().dropLast())
        } else {
            unquoted = cleaned
        }
        guard let match = unquoted.range(of: #"__call__\|status=([^|]+)\|kind=(audio|video)\|duration=([0-9]+)"#, options: .regularExpression) else {
            return nil
        }
        let segment = String(unquoted[match])
        let pattern = #"__call__\|status=([^|]+)\|kind=(audio|video)\|duration=([0-9]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let result = regex.firstMatch(in: segment, range: NSRange(segment.startIndex..., in: segment)),
              result.numberOfRanges == 4,
              let statusRange = Range(result.range(at: 1), in: segment),
              let kindRange = Range(result.range(at: 2), in: segment),
              let durationRange = Range(result.range(at: 3), in: segment)
        else { return nil }

        let status = String(segment[statusRange]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let kind = String(segment[kindRange]).lowercased() == "video" ? "video" : "audio"
        let duration = Int(segment[durationRange]) ?? 0
        guard !status.isEmpty else { return nil }
        return CallLogInfo(status: status, kind: kind, duration: max(0, duration))
    }

    static func formatCallLog(_ log: CallLogInfo) -> String {
        let kindLabel = log.kind == "video" ? "Video call" : "Voice call"
        switch log.status {
        case "ended":
            if log.duration > 0 {
                return "\(kindLabel) · \(formatDuration(log.duration))"
            }
            return "\(kindLabel) ended"
        case "missed", "busy":
            return "Missed \(kindLabel.lowercased())"
        case "declined":
            return "\(kindLabel) declined"
        case "ringing", "trying":
            return "\(kindLabel) ringing"
        default:
            return "\(kindLabel)"
        }
    }

    private static let reactionPrefix = "__react__|"
    private static let replyPrefix = "__reply__|"

    struct ReplyInfo: Hashable, Sendable {
        let targetID: String
        let quotedText: String
        let body: String
    }

    private struct ParsedReply {
        let targetID: String
        let text: String
        let body: String
    }

    var replyInfo: ReplyInfo? {
        guard let parsed = Self.parseReply(body) else { return nil }
        return ReplyInfo(targetID: parsed.targetID, quotedText: parsed.text, body: parsed.body)
    }

    static func buildReplyBody(target: Message, body: String) -> String {
        let quoted = target.displayText ?? target.previewText
        let encoded = encodeBase64(String(quoted.prefix(160)))
        return "\(replyPrefix)id=\(target.id)|text=\(encoded)||\(body)"
    }

    struct ReactionInfo: Hashable, Sendable {
        let targetID: String
        let emoji: String
        let isActive: Bool
    }

    static func buildReactionBody(targetID: String, emoji: String = "❤", active: Bool) -> String {
        let normalized = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = normalized.isEmpty ? "❤" : normalized
        return "\(reactionPrefix)target=\(targetID)|emoji=\(resolved)|state=\(active ? 1 : 0)"
    }

    static func parseReaction(_ body: String) -> ReactionInfo? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(reactionPrefix) else { return nil }
        guard let targetRange = trimmed.range(of: #"target=([^|]+)"#, options: .regularExpression) else { return nil }
        let targetID = String(trimmed[targetRange]).replacingOccurrences(of: "target=", with: "")
        guard !targetID.isEmpty else { return nil }

        let emoji: String
        if let emojiRange = trimmed.range(of: #"emoji=([^|]+)"#, options: .regularExpression) {
            emoji = String(trimmed[emojiRange]).replacingOccurrences(of: "emoji=", with: "")
        } else {
            emoji = "❤"
        }

        let state: Int
        if let stateRange = trimmed.range(of: #"state=([01])"#, options: .regularExpression) {
            let raw = String(trimmed[stateRange]).replacingOccurrences(of: "state=", with: "")
            state = Int(raw) ?? 1
        } else {
            state = 1
        }

        return ReactionInfo(targetID: targetID, emoji: emoji, isActive: state == 1)
    }

    private static func parseReply(_ body: String) -> ParsedReply? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(replyPrefix) else { return nil }
        let parts = trimmed.components(separatedBy: "||")
        let meta = parts.first ?? ""
        let rest = parts.dropFirst().joined(separator: "||")
        let targetID = metaValue(meta, key: "id")
        let encodedText = metaValue(meta, key: "text")
        return ParsedReply(targetID: targetID, text: decodeBase64(encodedText), body: rest)
    }

    private static func metaValue(_ meta: String, key: String) -> String {
        guard let range = meta.range(of: "\(key)=([^|]+)", options: .regularExpression) else { return "" }
        return String(meta[range]).replacingOccurrences(of: "\(key)=", with: "")
    }

    private static func encodeBase64(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
    }

    static func stripTrailingMeta(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let trailingUUID = try? NSRegularExpression(
            pattern: #"[ \t\n]+[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[ \t\n]*$"#,
            options: .caseInsensitive
        )

        while true {
            var changed = false

            if let range = result.range(of: "\n", options: .backwards) {
                let lastLine = String(result[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if ContentSanitizer.looksLikeId(lastLine) {
                    result = String(result[..<range.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    changed = true
                }
            }

            let parts = result.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            if parts.count >= 2,
               let last = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines),
               ContentSanitizer.looksLikeId(last) {
                result = parts.dropLast().joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                changed = true
            }

            if let trailingUUID,
               let match = trailingUUID.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
               let range = Range(match.range, in: result) {
                result = String(result[..<range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                changed = true
            }

            if !changed { break }
        }

        return result
    }

    static func stripIdOnlyLines(_ value: String) -> String {
        value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !ContentSanitizer.looksLikeId($0) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeBase64(_ value: String) -> String {
        guard let data = Data(base64Encoded: value) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func formatDuration(_ totalSeconds: Int) -> String {
        let seconds = max(0, totalSeconds)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}

struct CallLogInfo: Hashable, Sendable {
    let status: String
    let kind: String
    let duration: Int
}

struct Conversation: Identifiable, Hashable, Sendable {
    let id: String
    let isDirect: Bool
    let createdAt: String
    let updatedAt: String
    let lastMessageAt: String?
    let members: [PostAuthor]
    let lastMessage: Message?

    func otherMember(currentUserID: String) -> PostAuthor? {
        members.first { $0.userID != currentUserID }
    }
}

struct NotificationItem: Identifiable, Hashable, Sendable {
    let id: String
    let userID: String
    let actorID: String?
    let type: String
    let entityType: String?
    let entityID: String?
    let readAt: String?
    let createdAt: String
    let actor: PostAuthor?

    var isUnread: Bool {
        guard let readAt else { return true }
        return readAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isMessageType: Bool { type.lowercased() == "message" }

    var postID: String? {
        guard entityType?.lowercased() == "post" else { return nil }
        return entityID
    }

    var resolvedPostID: String? {
        let normalizedType = type.lowercased()
        guard let rawID = entityID?.trimmingCharacters(in: .whitespacesAndNewlines), !rawID.isEmpty else {
            return nil
        }
        switch normalizedType {
        case "like", "comment", "comment_like", "comment_reply", "reply", "post":
            return rawID
        default:
            return entityType?.lowercased() == "post" ? rawID : nil
        }
    }

    var conversationID: String? {
        let rawID = entityID?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawID, !rawID.isEmpty else { return nil }
        if entityType?.lowercased() == "conversation" { return rawID }
        if type.lowercased() == "message" { return rawID }
        return nil
    }

    var actorUserID: String? {
        if let actorID = actorID?.trimmingCharacters(in: .whitespacesAndNewlines), !actorID.isEmpty {
            return actorID
        }
        if let userID = actor?.userID.trimmingCharacters(in: .whitespacesAndNewlines), !userID.isEmpty {
            return userID
        }
        if entityType?.lowercased() == "user",
           let entityID = entityID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !entityID.isEmpty {
            return entityID
        }
        return nil
    }

    func markedAsRead(at timestamp: String = ISO8601DateFormatter().string(from: Date())) -> NotificationItem {
        NotificationItem(
            id: id,
            userID: userID,
            actorID: actorID,
            type: type,
            entityType: entityType,
            entityID: entityID,
            readAt: timestamp,
            createdAt: createdAt,
            actor: actor
        )
    }
}

struct ExternalNewsItem: Identifiable, Hashable, Sendable {
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
}

struct ExternalNewsComment: Identifiable, Hashable, Sendable {
    let id: String
    let newsItemID: String
    let parentID: String?
    let authorID: String
    let body: String
    let createdAt: String
    let updatedAt: String
    let author: PostAuthor?
}

struct AdCreative: Identifiable, Hashable, Sendable {
    let id: String
    let campaignID: String
    let title: String?
    let body: String?
    let mediaKind: String
    let mediaURL: String
    let clickURL: String?
    let ctaLabel: String?
    let durationSeconds: Int
}

struct AdCampaign: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let status: String
    let placement: String
    let targetCountryCodes: [String]
    let budgetCents: Int
    let dailyBudgetCents: Int
    let startAt: String?
    let endAt: String?
    let impressionCount: Int
    let clickCount: Int
    let creatives: [AdCreative]
}

struct AdSlot: Sendable {
    let impressionToken: String
    let skipAfterSeconds: Int
    let campaign: AdCampaign
    let creative: AdCreative
}

struct FollowCounts: Sendable {
    let followers: Int
    let following: Int
}

struct AuthUser: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let email: String?
}

struct GlobalStats: Sendable {
    let totalUsers: Int
    let onlineUsers: Int
}

struct CountryStats: Sendable {
    let countryCode: String
    let totalUsers: Int
    let onlineUsers: Int
}

enum GlobePanel: String, Identifiable {
    case notifications, presence
    var id: String { rawValue }
}

enum ProfileLibrarySection: String, CaseIterable, Identifiable {
    case posts, savedPosts, savedVideos, savedReels
    var id: String { rawValue }

    var title: String {
        switch self {
        case .posts: "Posts"
        case .savedPosts: "Saved posts"
        case .savedVideos: "Saved videos"
        case .savedReels: MatteryaCopy.savedSparks
        }
    }
}

enum CountryTab: String, CaseIterable, Identifiable {
    case posts, following, media, stats, news
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

enum AppTab: String, CaseIterable, Identifiable {
    case feed, globe, hubs, messages, profile
    var id: String { rawValue }

    var title: String {
        switch self {
        case .feed: "Feed"
        case .globe: "Globe"
        case .hubs: MatteryaCopy.matteryaHubs
        case .messages: "Messages"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .feed: "house"
        case .globe: "globe.americas"
        case .hubs: "square.grid.2x2"
        case .messages: "bubble.left.and.bubble.right"
        case .profile: "person.circle"
        }
    }
}

enum AppDestination: Hashable, Identifiable {
    case post(String)
    case news(String)
    case reels(Country)
    case countryFeed(Country)
    case search
    case publicProfile(username: String)
    case publicProfileByUserID(String)
    case playWatch(String)
    case playChannel(username: String)
    case playChannelID(String)
    case people
    case ads
    case editProfile
    case settings
    case premium
    case conversation(String)

    var id: String {
        switch self {
        case .post(let id): "post-\(id)"
        case .news(let id): "news-\(id)"
        case .reels(let c): "reels-\(c.iso)"
        case .countryFeed(let c): "country-feed-\(c.iso)"
        case .search: "search"
        case .publicProfile(let u): "profile-\(u)"
        case .publicProfileByUserID(let id): "profile-id-\(id)"
        case .playWatch(let id): "play-watch-\(id)"
        case .playChannel(let u): "play-channel-\(u)"
        case .playChannelID(let id): "play-channel-id-\(id)"
        case .people: "people"
        case .ads: "ads"
        case .editProfile: "edit-profile"
        case .settings: "settings"
        case .premium: "premium"
        case .conversation(let id): "conversation-\(id)"
        }
    }
}

enum RelativeTime {
    static func format(_ iso: String) -> String {
        guard let date = parseDate(iso) else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func formatClock(_ iso: String) -> String {
        guard let date = parseDate(iso) else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func formatDateTime(_ iso: String) -> String {
        guard let date = parseDate(iso) else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func parseDate(_ iso: String) -> Date? {
        let trimmed = iso.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !ContentSanitizer.looksLikeId(trimmed) else { return nil }

        let standard = ISO8601DateFormatter()
        if let date = standard.date(from: trimmed) { return date }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: trimmed) { return date }

        let normalized = trimmed.contains("T") ? trimmed : trimmed.replacingOccurrences(of: " ", with: "T")
        if let date = fractional.date(from: normalized) { return date }
        if let date = standard.date(from: normalized) { return date }

        if let numeric = Double(trimmed) {
            let seconds = numeric > 1_000_000_000_000 ? numeric / 1000 : numeric
            return Date(timeIntervalSince1970: seconds)
        }

        return nil
    }
}