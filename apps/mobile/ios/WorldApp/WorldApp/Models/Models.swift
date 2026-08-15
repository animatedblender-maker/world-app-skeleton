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
    /// R2 object key — used when signed GET URLs expire and need a fresh post fetch.
    let r2Key: String?

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
                    expiresAt: nil,
                    r2Key: nil
                )
            }

            guard let object = json as? [String: Any] else { return nil }

            let urls: [String]
            if let list = object["urls"] as? [String] {
                urls = list.filter { !$0.isEmpty }
            } else if let single = object["url"] as? String, !single.isEmpty {
                urls = [single]
            } else if let signed = object["signedUrl"] as? String, !signed.isEmpty {
                urls = [signed]
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
                ?? parseDate(object["signed_at"] as? String)
            let r2Raw = (object["r2_key"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let r2Key = (r2Raw?.isEmpty == false) ? r2Raw : nil
            return PostMediaPayload(
                urls: urls,
                types: types,
                isReel: reel,
                isStory: story,
                expiresAt: expiresAt,
                r2Key: r2Key
            )
        }

        return PostMediaPayload(
            urls: [raw],
            types: [inferMediaType(from: raw)],
            isReel: false,
            isStory: false,
            expiresAt: nil,
            r2Key: nil
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

    /// True when the profile bio embeds a Living channel name marker.
    static func hasChannel(profile: Profile?) -> Bool {
        parse(from: profile?.bio) != nil
    }
}

/// Marks long-form uploads that belong on a user's **own** Hubs channel
/// (intentional Hubs publish only — never used for feed shares).
enum HubChannelPostMarker {
    static let token = "__hub_channel__|"

    static func markBody(_ caption: String) -> String {
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(token) { return trimmed }
        if trimmed.isEmpty { return token }
        return "\(token)\n\(trimmed)"
    }

    static func strip(_ body: String) -> String {
        body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.hasPrefix(token) && $0 != token.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isMarked(_ body: String?) -> Bool {
        guard let body else { return false }
        return body.contains(token)
    }
}

/// Feed share of a **Spark** — shows as a Spark card on the home feed only.
/// Must **never** use `__spark__|` (that would enter the Sparks swipe pool as an original).
///
/// Header line: `__spark_share__|sid=…`
/// Optional caption lines follow.
enum SparkShareMarker {
    static let token = "__spark_share__|"

    static func isMarked(_ body: String?) -> Bool {
        guard let body else { return false }
        return body.contains(token)
    }

    /// Stamp original Spark id + **channel** so feed cards can show
    /// “you shared · from Channel” without pretending the channel posted.
    static func markBody(caption: String, origin: CountryPost) -> String {
        let sid = (origin.sharedPostID ?? origin.id)
            .replacingOccurrences(of: "|", with: "")
        let aid = origin.authorID.replacingOccurrences(of: "|", with: "")
        let an = (origin.author?.displayName ?? origin.authorDisplayName)
            .replacingOccurrences(of: "|", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var header = "\(token)sid=\(sid)"
        if !aid.isEmpty { header += "|aid=\(aid)" }
        if !an.isEmpty { header += "|an=\(an)" }
        let cap = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if cap.isEmpty { return header }
        return "\(header)\n\(cap)"
    }

    static func strip(_ body: String) -> String {
        body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.hasPrefix(token) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Original spark id when this post is a feed re-share of a Spark.
    static func originID(from body: String?) -> String? {
        parseFields(from: body)?["sid"]
    }

    /// Channel / creator name the Spark came from (for feed attribution).
    static func originChannelName(from body: String?) -> String? {
        guard let an = parseFields(from: body)?["an"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !an.isEmpty else { return nil }
        return an
    }

    private static func parseFields(from body: String?) -> [String: String]? {
        guard let body else { return nil }
        for line in body.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix(token) else { continue }
            let rest = String(trimmed.dropFirst(token.count))
            var out: [String: String] = [:]
            for part in rest.split(separator: "|") {
                let s = String(part)
                guard let eq = s.firstIndex(of: "=") else { continue }
                let key = String(s[..<eq])
                let val = String(s[s.index(after: eq)...])
                if !key.isEmpty { out[key] = val }
            }
            return out.isEmpty ? nil : out
        }
        return nil
    }
}

/// Feed share of a Hubs video — **does not** create a channel for the sharer.
/// Preserves original channel/author so Hubs watch shows the real creator.
///
/// Header line: `__hub_origin__|sid=…|aid=…|an=…|au=…`
/// Optional caption lines follow.
enum HubOriginShareMarker {
    static let token = "__hub_origin__|"

    static func isMarked(_ body: String?) -> Bool {
        guard let body else { return false }
        return body.contains(token)
    }

    static func markBody(caption: String, origin: CountryPost) -> String {
        let sid = (origin.sharedPostID ?? origin.id)
            .replacingOccurrences(of: "|", with: "")
        let aid = origin.authorID.replacingOccurrences(of: "|", with: "")
        let an = (origin.author?.displayName ?? origin.authorDisplayName)
            .replacingOccurrences(of: "|", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let au = (origin.author?.username ?? "")
            .replacingOccurrences(of: "|", with: "")
        var header = "\(token)sid=\(sid)|aid=\(aid)|an=\(an)"
        if !au.isEmpty {
            header += "|au=\(au)"
        }
        let cap = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if cap.isEmpty { return header }
        return "\(header)\n\(cap)"
    }

    static func strip(_ body: String) -> String {
        body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.hasPrefix(token) && !$0.hasPrefix("__hub_channel__") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Rebuild a presentation post for Hubs watch: same media as the share, original channel author.
    static func originPresentation(from share: CountryPost) -> CountryPost? {
        guard let fields = parseFields(from: share.body) else { return nil }
        let originAuthorID = fields["aid"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let originAuthorID, !originAuthorID.isEmpty else { return nil }
        let name = fields["an"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = fields["au"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceID = fields["sid"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        // Channel name only — never fall back to the sharer's name/avatar (that caused
        // "channel name + my profile picture" on Saved Videos).
        let channelName: String = {
            if let name, !name.isEmpty { return name }
            if HubVideoSeedService.isArchiveChannelAuthor(originAuthorID) {
                return HubVideoSeedService.archiveChannelDisplayName
            }
            if let embed = share.sharedPost?.asCountryPost,
               embed.authorID == originAuthorID {
                return embed.authorDisplayName
            }
            return HubVideoSeedService.archiveChannelDisplayName
        }()
        let channelAvatar: String? = {
            if let embed = share.sharedPost?.asCountryPost,
               embed.authorID == originAuthorID {
                return embed.author?.avatarURL
            }
            return nil
        }()
        let author = PostAuthor(
            userID: originAuthorID,
            displayName: channelName,
            username: (username?.isEmpty == false) ? username : nil,
            avatarURL: channelAvatar,
            countryName: nil,
            countryCode: nil,
            lastReadAt: nil
        )
        // Keep share media (self-contained stamp) but show original channel identity.
        return CountryPost(
            id: (sourceID?.isEmpty == false) ? sourceID! : share.id,
            title: share.title,
            body: strip(share.body),
            mediaType: share.mediaType,
            mediaURL: share.mediaURL,
            thumbURL: share.thumbURL,
            mediaCaption: share.mediaCaption,
            sharedPostID: share.sharedPostID,
            sharedPost: share.sharedPost,
            visibility: share.visibility,
            likeCount: share.likeCount,
            commentCount: share.commentCount,
            viewCount: share.viewCount,
            likedByMe: share.likedByMe,
            savedByMe: share.savedByMe,
            createdAt: share.createdAt,
            updatedAt: share.updatedAt,
            authorID: originAuthorID,
            countryName: share.countryName,
            countryCode: share.countryCode,
            cityName: share.cityName,
            author: author,
            externalRefType: share.externalRefType ?? "hub",
            externalRefID: share.externalRefID ?? sourceID
        )
    }

    static func parseFields(from body: String?) -> [String: String]? {
        guard let body else { return nil }
        guard let line = body.components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { $0.hasPrefix(token) })
        else { return nil }
        let payload = String(line.dropFirst(token.count))
        var out: [String: String] = [:]
        for part in payload.split(separator: "|") {
            let s = String(part)
            guard let eq = s.firstIndex(of: "=") else { continue }
            let key = String(s[..<eq])
            let val = String(s[s.index(after: eq)...])
            if !key.isEmpty { out[key] = val }
        }
        return out.isEmpty ? nil : out
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
    /// Origin thread size — share rows often have 0 local comments while origin has the full R2 set.
    var commentCount: Int = 0
    var likeCount: Int = 0
    /// Preserved so hub-seed shares still resolve as Hubs content in the feed.
    var externalRefType: String? = nil
    var externalRefID: String? = nil

    var asCountryPost: CountryPost {
        CountryPost(
            id: id,
            title: title,
            body: body,
            mediaType: mediaType,
            mediaURL: mediaURL,
            thumbURL: thumbURL,
            likeCount: likeCount,
            commentCount: commentCount,
            createdAt: "",
            updatedAt: "",
            authorID: authorID,
            author: author,
            externalRefType: externalRefType,
            externalRefID: externalRefID
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

    /// Feed/share cards: use the fuller of local + origin thread sizes.
    /// Spark/hub *shares* often store 0 comments on the share row while R2 comments live on the origin.
    var displayCommentCount: Int {
        max(commentCount, sharedPost?.commentCount ?? 0, sharedPost?.asCountryPost.commentCount ?? 0)
    }

    /// Stamp media_type when Keep from Sparks player so profile Saved Sparks keeps the row.
    func withMediaTypeForSave(_ type: String) -> CountryPost {
        CountryPost(
            id: id,
            title: title,
            body: body,
            mediaType: type,
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
            savedByMe: savedByMe,
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

    /// Seeded Reddit / hub catalog / synthetic rows — not a live Matterya member post.
    var isSeededOrSynthetic: Bool {
        if isDemoPost || isHubSeedVideo { return true }
        let pid = id.lowercased()
        let aid = authorID.lowercased()
        if pid.hasPrefix("post_") || pid.hasPrefix("demo_") || pid.hasPrefix("ia_") || pid.hasPrefix("hub_") {
            return true
        }
        if aid.hasPrefix("user_") || aid.hasPrefix("hub_") || aid.hasPrefix("hub_spark_") {
            return true
        }
        return false
    }

    /// Live people on Matterya (GraphQL / Supabase) — feed should surface these first.
    var isRealPersonFeedPost: Bool {
        !isSeededOrSynthetic && !isStory && !isSpark
    }

    var mediaPayload: PostMediaPayload? { PostMediaPayload.parse(from: mediaURL) }

    var resolvedMediaURLs: [String] {
        if let payload = mediaPayload, !payload.urls.isEmpty { return payload.urls }
        if let mediaURL, !mediaURL.isEmpty { return [mediaURL] }
        return []
    }

    /// True only for **original** Sparks (short vertical reels) — never long-form,
    /// hub watch videos, or **feed shares** of Sparks (`SparkShareMarker`).
    /// Markers must be explicit; do not infer from duration, aspect, or "has a video URL".
    var isReel: Bool {
        // Feed re-shares of Sparks are feed cards only — never first-class Sparks.
        if SparkShareMarker.isMarked(body) { return false }
        let type = (mediaType ?? "").lowercased()
        if type == "reel" || type == "spark" { return true }
        if mediaPayload?.isReel == true { return true }
        if let mediaURL {
            let normalized = mediaURL.lowercased()
            // JSON payload flag only — avoid matching unrelated substrings.
            if normalized.contains("\"reel\":true") || normalized.contains("\"reel\": true") {
                return true
            }
        }
        // Explicit body markers (line-prefix), not a mid-caption substring false positive.
        if Self.bodyHasSparkMarker(body) { return true }
        return false
    }

    /// Feed card should render Spark chrome (letterbox + badge) without being a swipe-pool Spark.
    var isSparkFeedShare: Bool {
        SparkShareMarker.isMarked(body)
            || (sharedPost.map { $0.asCountryPost.isReel } == true)
    }

    /// `__spark__|` / `__reel__|` only when used as a control line (start or after newline).
    private static func bodyHasSparkMarker(_ body: String) -> Bool {
        guard !body.isEmpty else { return false }
        // Never treat spark-share control lines as original Spark markers.
        if SparkShareMarker.isMarked(body) { return false }
        if body.hasPrefix("__spark__|") || body.hasPrefix("__reel__|") { return true }
        if body.contains("\n__spark__|") || body.contains("\n__reel__|") { return true }
        return false
    }

    var isStory: Bool {
        if body.contains("__story__|") { return true }
        if (mediaType ?? "").lowercased() == "story" { return true }
        return mediaPayload?.isStory == true
    }

    /// Sparks belong in the vertical sparks scroll only — not the home feed or profile grids.
    var isSpark: Bool { isReel }

    /// Cloudflare R2 focus packs (US/DE/EG/AL seed) — preferred Sparks source.
    var isR2HostedMedia: Bool {
        let media = (mediaURL ?? "").lowercased()
        if media.contains("r2.cloudflarestorage.com") { return true }
        if media.contains("matterya-sparks") { return true }
        if media.contains("\"r2_key\"") || media.contains("r2_key") { return true }
        if media.contains("r2_focus_seed") || media.contains("r2_spark") { return true }
        if media.contains("\"source\":\"r2") { return true }
        let thumb = (thumbURL ?? "").lowercased()
        if thumb.contains("r2.cloudflarestorage.com") || thumb.contains("matterya-sparks") { return true }
        return false
    }

    /// Internet Archive / local hub seed catalog — lowest priority in Sparks player.
    var isArchiveSparkSource: Bool {
        if isHubSeedVideo { return true }
        if HubVideoSeedService.isArchiveChannelAuthor(authorID) { return true }
        let id = id.lowercased()
        if id.hasPrefix("ia_") || id.hasPrefix("hub_spark_") { return true }
        if PlayPlatformBridge.isArchiveCatalogMedia(self) { return true }
        return false
    }

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
        // Sparks / spark shares: prefer body (R2 meta text after markers) over AI media_caption.
        if isReel || isSparkFeedShare {
            let fromBody = displayBody
            if !fromBody.isEmpty { return fromBody }
            // Feed spark share: prefer original caption when embed is present.
            if let origin = sharedPost?.asCountryPost {
                let originBody = origin.displayBody
                if !originBody.isEmpty { return originBody }
                if let t = origin.displayTitle { return t }
                if let c = ContentSanitizer.clean(origin.mediaCaption), !c.isEmpty { return c }
            }
            if let caption = ContentSanitizer.clean(mediaCaption) { return caption }
            return nil
        }
        if let caption = ContentSanitizer.clean(mediaCaption) { return caption }
        return nil
    }

    /// Caption line for Sparks player / feed Spark cards — R2 meta text, never seeder fluff.
    var sparkDisplayCaption: String? {
        // Prefer body/meta over title/headline so we never surface filler.
        if let c = displayCaption, !c.isEmpty { return c }
        if isSparkFeedShare, let origin = sharedPost?.asCountryPost {
            if let c = origin.displayCaption, !c.isEmpty { return c }
            if let t = origin.displayTitle { return t }
        }
        return displayHeadline
    }

    /// Feed share of a Hubs channel video (`__hub_origin__|…`).
    var isHubOriginFeedShare: Bool {
        HubOriginShareMarker.isMarked(body)
    }

    var displayHeadline: String? {
        if let title = displayTitle { return title }
        // Spark shares: body after stripping markers may be empty or a weak share line —
        // prefer embedded original when available.
        if isSparkFeedShare, let origin = sharedPost?.asCountryPost {
            if let t = origin.displayTitle { return t }
            let originBody = origin.displayBody
            if !originBody.isEmpty { return String(originBody.prefix(120)) }
        }
        let text = displayBody
        if text.isEmpty { return nil }
        return String(text.prefix(120))
    }

    var displayExcerpt: String {
        let text = displayBody
        guard let title = displayTitle, !title.isEmpty else { return text }
        if text == title { return "" }
        return text
    }

    /// True when a feed/profile card would show something meaningful (text, media, or share).
    /// Filters out blank rows left by marker-only bodies or deleted shared originals.
    var hasFeedVisibleContent: Bool {
        if isStory { return false }
        if hasMedia { return true }
        if playableVideoURL != nil { return true }
        if sharedPost != nil { return true }
        // Pending share hydrate — still show the card (loading embed).
        if let sharedPostID, !sharedPostID.isEmpty { return true }
        if let title = displayTitle, !title.isEmpty { return true }
        if !displayBody.isEmpty { return true }
        if let caption = displayCaption, !caption.isEmpty { return true }
        return false
    }

    /// Stable key so original Spark + its feed re-share collapse to one card.
    var homeFeedContentKey: String {
        if let origin = SparkShareMarker.originID(from: body)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !origin.isEmpty {
            return "spark:\(origin)"
        }
        if let shared = sharedPostID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !shared.isEmpty,
           isSparkFeedShare || isReel || hasVideo {
            return "spark:\(shared)"
        }
        // Original Sparks: key by own id so a later share of this id collapses onto it.
        if isReel || isSpark {
            return "spark:\(id.lowercased())"
        }
        // Same media file (strip signed query) — share + original often differ only by id.
        if let media = playableVideoURL?.absoluteString
            ?? primaryMediaURL
            ?? mediaPayload?.primaryURL {
            let bare = media.split(separator: "?").first.map(String.init) ?? media
            let lower = bare.lowercased()
            if lower.contains("r2") || lower.contains("mp4") || lower.contains("video") {
                return "media:\(lower)"
            }
        }
        if let r2 = mediaPayload?.r2Key?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !r2.isEmpty {
            return "r2:\(r2)"
        }
        return "id:\(id.lowercased())"
    }

    /// Subtle location line for post cards (country name or ISO).
    var authorLocationLabel: String? {
        let name = (author?.countryName ?? countryName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let code = (author?.countryCode ?? countryCode)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if let name, !name.isEmpty, name.uppercased() != "XX" {
            return name
        }
        if let code, !code.isEmpty, code != "XX" {
            return code
        }
        return nil
    }

    /// ISO regional-indicator flag for the post author location (nil if unknown).
    var authorLocationFlag: String? {
        let code = (author?.countryCode ?? countryCode)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard let code, code.count == 2, code != "XX" else { return nil }
        let base: UInt32 = 127397
        let scalars = code.unicodeScalars.compactMap { UnicodeScalar(base + $0.value) }
        guard scalars.count == 2 else { return nil }
        return String(String.UnicodeScalarView(scalars))
    }

    var authorDisplayName: String {
        ContentSanitizer.displayName(
            displayName: author?.displayName,
            username: author?.username
        )
    }
}

extension Array where Element == CountryPost {
    /// Drop Internet Archive seed / archive.org media when `AppConfig.archiveContentEnabled` is false.
    func excludingArchiveContent() -> [CountryPost] {
        guard !AppConfig.archiveContentEnabled else { return self }
        return filter { !$0.isArchiveSparkSource && !PlayPlatformBridge.isArchiveCatalogMedia($0) }
    }

    func excludingSparks() -> [CountryPost] {
        filter { !$0.isSpark }
    }

    func excludingMoments() -> [CountryPost] {
        filter { !$0.isStory }
    }

    /// Home feed surface: text, long-form, **and** Sparks (R2 originals + shares as SparkFeedCard).
    /// Moments / demo fakes / archive seeds stay out. Never drop the R2 library.
    func forHomeFeed() -> [CountryPost] {
        filter { post in
            if post.isStory { return false }
            if post.authorID.hasPrefix("user_") { return false }
            if post.id.hasPrefix("post_") || post.id.hasPrefix("demo_") { return false }
            if post.id.hasPrefix("ia_") || post.id.hasPrefix("hub_") { return false }
            if post.isHubSeedVideo { return false }
            if !AppConfig.archiveContentEnabled {
                if post.isArchiveSparkSource { return false }
                if PlayPlatformBridge.isArchiveCatalogMedia(post) { return false }
            }
            // Sparks with no playable path are useless on feed; keep text/photo posts.
            if post.isSpark || post.isReel || PlayPlatformBridge.isSparkFeedCard(post) {
                return post.playableVideoURL != nil
                    || post.hasVideo
                    || !(post.mediaURL ?? "").isEmpty
            }
            if post.hasFeedVisibleContent { return true }
            if post.hasVideo || post.mediaURL != nil { return true }
            let body = post.body.trimmingCharacters(in: .whitespacesAndNewlines)
            return !body.isEmpty
        }
    }

    /// Collapse original Spark + feed re-share of the **same** clip into one card.
    /// Pipeline seeds both rows; without this every Spark shows twice.
    func dedupeHomeFeedContent() -> [CountryPost] {
        // Prefer feed shares (social context) over bare channel originals.
        let ranked = sorted { a, b in
            let aShare = a.isSparkFeedShare || SparkShareMarker.isMarked(a.body)
            let bShare = b.isSparkFeedShare || SparkShareMarker.isMarked(b.body)
            if aShare != bShare { return aShare && !bShare }
            let aDate = a.createdDate ?? .distantPast
            let bDate = b.createdDate ?? .distantPast
            return aDate > bDate
        }
        var seenIDs = Set<String>()
        var seenKeys = Set<String>()
        var unique: [CountryPost] = []
        unique.reserveCapacity(ranked.count)
        for post in ranked {
            guard seenIDs.insert(post.id).inserted else { continue }
            let key = post.homeFeedContentKey
            guard seenKeys.insert(key).inserted else { continue }
            unique.append(post)
        }
        // Restore newest-first timeline for the surviving set.
        return unique.sorted {
            ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast)
        }
    }

    /// Profile / feed lists — no blank cards, moments, or sparks.
    func forProfileFeedGrid() -> [CountryPost] {
        excludingMoments()
            .excludingSparks()
            .filter(\.hasFeedVisibleContent)
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
    /// Long-form video published to the user's Living channel (Hubs).
    case hubVideo
    /// First-time channel name / about setup before hubVideo.
    case channelSetup
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

    func withPostAndParent(postID: String, parentID: String?) -> PostComment {
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

    /// Reassign the speaker while keeping comment content / engagement.
    func withAuthor(authorID: String, author: PostAuthor?) -> PostComment {
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
    /// active | deactivated | deleted
    let accountStatus: String?
    let deactivatedAt: String?
    let deletedAt: String?
    let createdAt: String
    let updatedAt: String

    var isComplete: Bool {
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let country = countryName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !name.isEmpty && !country.isEmpty && country != "Unknown"
    }

    var isDemoUser: Bool { userID.hasPrefix("user_") }

    var isDeactivated: Bool {
        (accountStatus ?? "active").lowercased() == "deactivated"
    }

    var isDeleted: Bool {
        (accountStatus ?? "active").lowercased() == "deleted"
    }
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

    var hasVideoMedia: Bool {
        let type = (mediaType ?? "").lowercased()
        return (type == "video" || type == "reel") && (mediaPath != nil || mediaURL != nil)
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

    /// Shared hub video / feed post / reel card encoded in the message body.
    var shareInfo: ShareInfo? {
        Self.parseShare(body)
    }

    var isShare: Bool {
        shareInfo != nil
    }

    var isRenderableInChat: Bool {
        if isReaction { return false }
        if isCallLog { return true }
        if isShare { return true }
        if hasImage || hasVideoMedia { return true }
        if displayText != nil { return true }
        return false
    }

    var previewText: String {
        if isReaction { return "Liked a message" }
        if let callLog = Self.parseCallLog(body) {
            return Self.formatCallLog(callLog)
        }
        if let share = shareInfo {
            if !share.note.isEmpty { return share.note }
            switch share.kind {
            case .reel: return "Shared a \(MatteryaCopy.spark)"
            case .hub: return share.isVideo ? "Shared a video" : "Shared from Hubs"
            case .post: return share.isVideo ? "Shared a video" : "Shared a post"
            }
        }
        if let text = displayText, !text.isEmpty { return text }
        if hasImage { return "Photo" }
        if hasVideoMedia || (mediaType ?? "").lowercased() == "video" { return "Video" }
        return "Media message"
    }

    var displayText: String? {
        if isReaction { return nil }
        if let callLog = Self.parseCallLog(body) {
            return Self.formatCallLog(callLog)
        }
        // Structured share: optional note only (card carries the content).
        if let share = shareInfo {
            let note = share.note.trimmingCharacters(in: .whitespacesAndNewlines)
            return note.isEmpty ? nil : ContentSanitizer.clean(note)
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
    private static let sharePrefix = "__share__|"

    /// Rich content shared into chat (hub video, feed post, reel).
    struct ShareInfo: Hashable, Sendable {
        enum Kind: String, Sendable {
            case post
            case hub
            case reel
        }

        let kind: Kind
        let postID: String
        let title: String?
        let bodyText: String?
        let authorName: String?
        let authorID: String?
        let mediaURL: String?
        let posterURL: String?
        let mediaType: String?
        /// Optional caption the sender typed with the share.
        let note: String

        var isVideo: Bool {
            let type = (mediaType ?? "").lowercased()
            if type == "video" || type == "reel" { return true }
            if kind == .hub || kind == .reel { return true }
            if playableVideoURL != nil { return true }
            if let mediaURL, !mediaURL.isEmpty {
                let lower = mediaURL.lowercased()
                if lower.contains(".mp4") || lower.contains(".m3u8") || lower.contains("archive.org")
                    || lower.contains("\"video\"") || lower.contains("\"reel\"") {
                    return true
                }
            }
            return false
        }

        var isHubContent: Bool {
            // Reels/Sparks are never Hubs long-form — keep them on the Sparks path.
            if kind == .reel { return false }
            let type = (mediaType ?? "").lowercased()
            if type == "reel" || type == "spark" { return false }
            return kind == .hub
                || postID.lowercased().hasPrefix("ia_")
                || postID.lowercased().hasPrefix("hub_")
                || (mediaURL?.lowercased().contains("archive.org") == true
                    && kind != .post)
        }

        /// Same resolution path as feed/hubs (JSON media payloads, relative paths, Archive).
        var playableVideoURL: URL? {
            if let resolved = MediaURLResolver.videoURL(for: mediaProbePost) { return resolved }
            return MediaURLResolver.resolve(mediaURL)
        }

        var posterImageURL: URL? {
            // Never treat an mp4 / m3u8 as a poster — CachedAsyncImage fails and chat shows blank.
            if let resolved = MediaURLResolver.posterURL(for: mediaProbePost),
               !MediaURLResolver.isVideoURL(resolved) {
                return resolved
            }
            if let raw = posterURL, !raw.isEmpty, !Message.looksLikeVideoURL(raw),
               let resolved = MediaURLResolver.resolve(raw),
               !MediaURLResolver.isVideoURL(resolved) {
                return resolved
            }
            return nil
        }

        /// Lightweight post used only for MediaURLResolver (does not call `isVideo`).
        private var mediaProbePost: CountryPost {
            let type = mediaType
                ?? (kind == .reel ? "reel" : (kind == .hub ? "video" : "video"))
            return CountryPost(
                id: postID,
                title: title,
                body: bodyText ?? "",
                mediaType: type,
                mediaURL: mediaURL,
                thumbURL: posterURL,
                createdAt: "",
                updatedAt: "",
                authorID: authorID ?? ""
            )
        }

        var asCountryPost: CountryPost {
            let author: PostAuthor? = {
                guard let authorID, !authorID.isEmpty else { return nil }
                return PostAuthor(
                    userID: authorID,
                    displayName: authorName,
                    username: nil,
                    avatarURL: nil,
                    countryName: nil,
                    countryCode: nil,
                    lastReadAt: nil
                )
            }()
            // Prefer a plain https URL so players never receive a JSON media blob.
            let plainMedia = playableVideoURL?.absoluteString ?? mediaURL
            let isSpark = kind == .reel
                || (mediaType ?? "").lowercased() == "reel"
                || (mediaType ?? "").lowercased() == "spark"
            // Stamp spark marker so open path treats this as a first-class Spark.
            let body: String = {
                let raw = (bodyText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if isSpark {
                    if raw.hasPrefix("__spark__|") || raw.hasPrefix("__reel__|") { return raw }
                    return "__spark__|\(raw.isEmpty ? "Spark" : raw)"
                }
                return raw
            }()
            return CountryPost(
                id: postID,
                title: title,
                body: body,
                mediaType: isSpark ? (mediaType ?? "reel") : (mediaType ?? (isVideo ? "video" : nil)),
                mediaURL: plainMedia,
                thumbURL: posterURL ?? posterImageURL?.absoluteString,
                createdAt: "",
                updatedAt: "",
                authorID: authorID ?? "",
                author: author
            )
        }

        var previewLabel: String {
            if kind == .reel { return title?.isEmpty == false ? title! : MatteryaCopy.spark }
            if isVideo { return title?.isEmpty == false ? title! : "Video" }
            return title?.isEmpty == false ? title! : "Post"
        }
    }

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

    /// Encodes a post/hub video / Spark so chat can render a rich card (not just a bare link).
    static func buildShareBody(post: CountryPost, note: String = "") -> String {
        let kind: ShareInfo.Kind
        // Sparks first — including spark feed shares — so chat never paints them as Hubs.
        if post.isReel
            || post.isSparkFeedShare
            || PlayPlatformBridge.isSparkFeedCard(post)
            || PlayPlatformBridge.isReelVideo(post) {
            kind = .reel
        } else if PlayPlatformBridge.isHubCatalogContent(post), post.hasVideo {
            kind = .hub
        } else {
            kind = .post
        }

        let mediaType = post.mediaType
            ?? (post.hasVideo ? (kind == .reel ? "reel" : "video") : nil)
        let title = post.displayHeadline ?? post.displayTitle
        let bodyText: String? = {
            let body = post.displayBody.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { return body }
            return post.displayCaption
        }()
        let author = post.authorDisplayName
        // Always encode a *playable* https URL — never a JSON media payload blob.
        let media = post.playableVideoURL?.absoluteString
            ?? MediaURLResolver.resolve(post.mediaURL)?.absoluteString
            ?? post.mediaURL
        // Prefer real image poster; never encode the mp4 as "poster" (chat showed blank thumbs).
        let poster: String? = {
            if let p = post.posterImageURL?.absoluteString, !p.isEmpty, !Self.looksLikeVideoURL(p) {
                return p
            }
            if let p = post.feedImageURL?.absoluteString, !p.isEmpty, !Self.looksLikeVideoURL(p) {
                return p
            }
            if let p = post.thumbURL, !p.isEmpty, !Self.looksLikeVideoURL(p) {
                return p
            }
            if let p = MediaURLResolver.posterURL(for: post)?.absoluteString, !Self.looksLikeVideoURL(p) {
                return p
            }
            return nil
        }()

        var parts: [String] = [
            "v=1",
            "kind=\(kind.rawValue)",
            "id=\(post.id)",
        ]
        if let title, !title.isEmpty { parts.append("title=\(encodeBase64(String(title.prefix(180))))") }
        if let bodyText, !bodyText.isEmpty { parts.append("body=\(encodeBase64(String(bodyText.prefix(280))))") }
        if !author.isEmpty { parts.append("author=\(encodeBase64(String(author.prefix(80))))") }
        if !post.authorID.isEmpty { parts.append("authorId=\(post.authorID)") }
        if let media, !media.isEmpty, !media.hasPrefix("{") {
            parts.append("media=\(encodeBase64(media))")
        } else if let media = post.playableVideoURL?.absoluteString {
            parts.append("media=\(encodeBase64(media))")
        }
        if let poster, !poster.isEmpty, !poster.hasPrefix("{") {
            parts.append("poster=\(encodeBase64(poster))")
        }
        if let mediaType, !mediaType.isEmpty { parts.append("type=\(mediaType)") }

        let meta = parts.joined(separator: "|")
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNote.isEmpty {
            return "\(sharePrefix)\(meta)||"
        }
        return "\(sharePrefix)\(meta)||\(trimmedNote)"
    }

    /// True when a string looks like a playable video URL (not a JPG/PNG poster).
    static func looksLikeVideoURL(_ raw: String) -> Bool {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        if lower.hasPrefix("{") { return false } // media JSON blob — not a direct video path
        if lower.range(of: #"\.(mp4|webm|mov|m4v|m3u8|avi|mkv)(\?|#|$)"#, options: .regularExpression) != nil {
            return true
        }
        if lower.contains("/video/") || lower.contains("/video.") { return true }
        if let url = URL(string: raw), MediaURLResolver.isVideoURL(url) { return true }
        return false
    }

    static func parseShare(_ body: String) -> ShareInfo? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(sharePrefix) {
            return parseStructuredShare(trimmed)
        }
        return parseLegacyShareLink(trimmed)
    }

    private static func parseStructuredShare(_ trimmed: String) -> ShareInfo? {
        let withoutPrefix = String(trimmed.dropFirst(sharePrefix.count))
        let parts = withoutPrefix.components(separatedBy: "||")
        let meta = parts.first ?? ""
        let note = parts.dropFirst().joined(separator: "||").trimmingCharacters(in: .whitespacesAndNewlines)

        let id = metaValue(meta, key: "id")
        guard !id.isEmpty else { return nil }

        let kindRaw = metaValue(meta, key: "kind").lowercased()
        let kind = ShareInfo.Kind(rawValue: kindRaw) ?? .post
        let title = nonEmpty(decodeBase64(metaValue(meta, key: "title")))
        let bodyText = nonEmpty(decodeBase64(metaValue(meta, key: "body")))
        let authorName = nonEmpty(decodeBase64(metaValue(meta, key: "author")))
        let authorID = nonEmpty(metaValue(meta, key: "authorId"))
        let media = nonEmpty(decodeBase64(metaValue(meta, key: "media")))
        let poster = nonEmpty(decodeBase64(metaValue(meta, key: "poster")))
        let mediaType = nonEmpty(metaValue(meta, key: "type"))
            ?? nonEmpty(metaValue(meta, key: "mediaType"))

        return ShareInfo(
            kind: kind,
            postID: id,
            title: title,
            bodyText: bodyText,
            authorName: authorName,
            authorID: authorID,
            mediaURL: media,
            posterURL: poster,
            mediaType: mediaType,
            note: note
        )
    }

    /// Older shares were plain "title\\nhttps://matterya.com/post|play/watch/…".
    private static func parseLegacyShareLink(_ trimmed: String) -> ShareInfo? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = detector?.firstMatch(in: trimmed, options: [], range: range),
              let urlRange = Range(match.range, in: trimmed)
        else { return nil }

        let urlString = String(trimmed[urlRange])
        guard let url = URL(string: urlString) else { return nil }
        let host = (url.host ?? "").lowercased()
        let isMatterya = host.contains("matterya.com") || url.scheme?.lowercased() == "matterya"
        guard isMatterya else { return nil }

        var path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if url.scheme?.lowercased() == "matterya", let hostPath = url.host, !hostPath.contains(".") {
            path = "\(hostPath)/\(path)".trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        let segments = path.split(separator: "/").map(String.init)
        guard let first = segments.first?.lowercased() else { return nil }

        let postID: String
        let kind: ShareInfo.Kind
        switch first {
        case "post", "p":
            guard let id = segments.dropFirst().first, !id.isEmpty else { return nil }
            postID = id
            kind = .post
        case "play":
            guard segments.count >= 3, segments[1].lowercased() == "watch" else { return nil }
            postID = segments[2]
            kind = .hub
        default:
            return nil
        }

        let before = String(trimmed[..<urlRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = before
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })

        return ShareInfo(
            kind: kind,
            postID: postID,
            title: title,
            bodyText: nil,
            authorName: nil,
            authorID: nil,
            mediaURL: nil,
            posterURL: nil,
            mediaType: kind == .hub ? "video" : nil,
            note: ""
        )
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

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

// MARK: - Channel admins (creator + selected admins)

enum ChannelMemberRole: String, Codable, Sendable, Hashable {
    case owner
    case admin

    var isStaff: Bool { self == .owner || self == .admin }
    var displayTitle: String {
        switch self {
        case .owner: return "Creator"
        case .admin: return "Admin"
        }
    }
}

struct HubChannel: Identifiable, Hashable, Sendable {
    let id: String
    let ownerUserID: String
    let name: String
    let handle: String?
    let about: String?
    let avatarURL: String?
    /// Wide banner / cover image on the channel page (separate from avatar).
    let coverURL: String?
    let createdAt: String
    let updatedAt: String
    let owner: PostAuthor?
    let myRole: ChannelMemberRole?
    let videoCount: Int

    var isStaff: Bool { myRole?.isStaff == true }
    var isOwner: Bool { myRole == .owner }
}

struct ChannelMember: Identifiable, Hashable, Sendable {
    var id: String { "\(channelID):\(userID)" }
    let channelID: String
    let userID: String
    let role: ChannelMemberRole
    let invitedBy: String?
    let createdAt: String
    let profile: PostAuthor?
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
    case letters
    case letterThread(String)

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
        case .letters: "letters"
        case .letterThread(let id): "letter-thread-\(id)"
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