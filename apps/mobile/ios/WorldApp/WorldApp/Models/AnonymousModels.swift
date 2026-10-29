import Foundation

// MARK: - Identity

struct AnonymousProfile: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let username: String
    var avatarSeed: String?
    var createdAt: String?
    var state: String?

    var displayHandle: String { "@\(username)" }

    enum CodingKeys: String, CodingKey {
        case id, username, state
        case avatarSeed, avatar_seed
        case createdAt, created_at
    }

    init(id: String, username: String, avatarSeed: String? = nil, createdAt: String? = nil, state: String? = nil) {
        self.id = id
        self.username = username
        self.avatarSeed = avatarSeed
        self.createdAt = createdAt
        self.state = state
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        state = try c.decodeIfPresent(String.self, forKey: .state)
        avatarSeed = try c.decodeIfPresent(String.self, forKey: .avatarSeed)
            ?? c.decodeIfPresent(String.self, forKey: .avatar_seed)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
            ?? c.decodeIfPresent(String.self, forKey: .created_at)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(username, forKey: .username)
        try c.encodeIfPresent(state, forKey: .state)
        try c.encodeIfPresent(avatarSeed, forKey: .avatarSeed)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
    }
}

struct AnonymousSession: Codable, Hashable, Sendable {
    var eligibleAdult: Bool
    var ageAttested: Bool
    var birthdateMissing: Bool
    var suspended: Bool
    var profile: AnonymousProfile?
    var suggestedUsername: String?
    var privacyNoticeVersion: String?
    /// Server gate code when ineligible (`under_18`, `birthdate_required`, …).
    var gateCode: String?

    static let empty = AnonymousSession(
        eligibleAdult: false,
        ageAttested: false,
        birthdateMissing: false,
        suspended: false,
        profile: nil,
        suggestedUsername: nil,
        privacyNoticeVersion: nil,
        gateCode: nil
    )

    enum CodingKeys: String, CodingKey {
        case eligibleAdult, eligible
        case ageAttested, age_attested
        case birthdateMissing, birthdate_missing
        case suspended
        case profile
        case suggestedUsername, suggested_username
        case privacyNoticeVersion, privacy_notice_version
        case code, reason
        case paidEnabled, paid_enabled
    }

    init(
        eligibleAdult: Bool,
        ageAttested: Bool,
        birthdateMissing: Bool,
        suspended: Bool,
        profile: AnonymousProfile?,
        suggestedUsername: String?,
        privacyNoticeVersion: String?,
        gateCode: String? = nil
    ) {
        self.eligibleAdult = eligibleAdult
        self.ageAttested = ageAttested
        self.birthdateMissing = birthdateMissing
        self.suspended = suspended
        self.profile = profile
        self.suggestedUsername = suggestedUsername
        self.privacyNoticeVersion = privacyNoticeVersion
        self.gateCode = gateCode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // API returns `eligible`; older drafts used `eligible_adult`.
        if let v = try c.decodeIfPresent(Bool.self, forKey: .eligibleAdult) {
            eligibleAdult = v
        } else {
            eligibleAdult = try c.decodeIfPresent(Bool.self, forKey: .eligible) ?? false
        }
        if let v = try c.decodeIfPresent(Bool.self, forKey: .ageAttested) {
            ageAttested = v
        } else {
            ageAttested = try c.decodeIfPresent(Bool.self, forKey: .age_attested) ?? false
        }
        let code = try c.decodeIfPresent(String.self, forKey: .code)
        gateCode = code
        if let v = try c.decodeIfPresent(Bool.self, forKey: .birthdateMissing) {
            birthdateMissing = v
        } else if let v = try c.decodeIfPresent(Bool.self, forKey: .birthdate_missing) {
            birthdateMissing = v
        } else {
            birthdateMissing =
                code == "birthdate_required"
                || code == "birthdate_missing"
                || code == "under_18"
        }
        profile = try c.decodeIfPresent(AnonymousProfile.self, forKey: .profile)
        let profileState = profile?.state?.lowercased()
        if let v = try c.decodeIfPresent(Bool.self, forKey: .suspended) {
            suspended = v
        } else {
            suspended = profileState == "suspended" || code == "suspended"
        }
        if let v = try c.decodeIfPresent(String.self, forKey: .suggestedUsername) {
            suggestedUsername = v
        } else {
            suggestedUsername = try c.decodeIfPresent(String.self, forKey: .suggested_username)
        }
        if let v = try c.decodeIfPresent(String.self, forKey: .privacyNoticeVersion) {
            privacyNoticeVersion = v
        } else {
            privacyNoticeVersion = try c.decodeIfPresent(String.self, forKey: .privacy_notice_version)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(eligibleAdult, forKey: .eligibleAdult)
        try c.encode(ageAttested, forKey: .ageAttested)
        try c.encode(birthdateMissing, forKey: .birthdateMissing)
        try c.encode(suspended, forKey: .suspended)
        try c.encodeIfPresent(profile, forKey: .profile)
        try c.encodeIfPresent(suggestedUsername, forKey: .suggestedUsername)
        try c.encodeIfPresent(privacyNoticeVersion, forKey: .privacyNoticeVersion)
        try c.encodeIfPresent(gateCode, forKey: .code)
    }
}

// MARK: - Spaces

enum AnonymousSpaceFilter: String, CaseIterable, Identifiable, Sendable {
    case forYou = "for_you"
    case popular
    case newest
    case joined
    case free
    case paid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forYou: "For You"
        case .popular: "Popular"
        case .newest: "Newest"
        case .joined: "Joined"
        case .free: "Free"
        case .paid: "Paid"
        }
    }
}

enum AnonymousSpaceVisibility: String, Codable, Sendable {
    case adultPublic = "adult_public"
    case restricted
    case privateSpace = "private"
}

enum AnonymousSpaceAdmission: String, Codable, Sendable {
    case free
    case approval
    case paid
    case paidPlusApproval = "paid_plus_approval"

    var isPaid: Bool {
        self == .paid || self == .paidPlusApproval
    }
}

struct AnonymousSpace: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let slug: String
    var title: String
    var description: String?
    var category: String?
    var tags: [String]?
    var visibility: AnonymousSpaceVisibility?
    var admission: AnonymousSpaceAdmission?
    var memberCount: Int?
    var postCount: Int?
    var ownerUsername: String?
    var rules: [String]?
    var isJoined: Bool?
    var isOwner: Bool?
    var isModerator: Bool?
    var priceCurrency: String?
    var priceAmountMinor: Int?
    var billingPeriod: String?
    var status: String?

    var isPaid: Bool { admission?.isPaid == true }

    /// Lowercased slug for tolerant directory / openSpace matching.
    var normalizedSlug: String {
        slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var priceLabel: String? {
        guard isPaid, let minor = priceAmountMinor, let currency = priceCurrency else { return nil }
        let amount = Double(minor) / 100.0
        let period = billingPeriod.map { " / \($0)" } ?? ""
        return String(format: "%@ %.2f%@", currency, amount, period)
    }

    enum CodingKeys: String, CodingKey {
        case id, slug, title, description, category, tags, visibility, admission, status
        case memberCount, member_count
        case postCount, post_count
        case ownerUsername, owner_username
        case rules
        case isJoined, is_joined, joined
        case isOwner, is_owner
        case isModerator, is_moderator
        case priceCurrency, price_currency
        case priceAmountMinor, price_amount_minor
        case billingPeriod, billing_period
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        slug = try c.decode(String.self, forKey: .slug)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        tags = try c.decodeIfPresent([String].self, forKey: .tags)
        visibility = try c.decodeIfPresent(AnonymousSpaceVisibility.self, forKey: .visibility)
        admission = try c.decodeIfPresent(AnonymousSpaceAdmission.self, forKey: .admission)
        memberCount = try c.decodeIfPresent(Int.self, forKey: .memberCount)
            ?? c.decodeIfPresent(Int.self, forKey: .member_count)
        postCount = try c.decodeIfPresent(Int.self, forKey: .postCount)
            ?? c.decodeIfPresent(Int.self, forKey: .post_count)
        ownerUsername = try c.decodeIfPresent(String.self, forKey: .ownerUsername)
            ?? c.decodeIfPresent(String.self, forKey: .owner_username)
        // API may return rules as [{position,text}] — accept string array only; ignore objects.
        if let strings = try? c.decodeIfPresent([String].self, forKey: .rules) {
            rules = strings
        } else {
            rules = nil
        }
        isJoined = try c.decodeIfPresent(Bool.self, forKey: .isJoined)
            ?? c.decodeIfPresent(Bool.self, forKey: .is_joined)
            ?? c.decodeIfPresent(Bool.self, forKey: .joined)
        isOwner = try c.decodeIfPresent(Bool.self, forKey: .isOwner)
            ?? c.decodeIfPresent(Bool.self, forKey: .is_owner)
        isModerator = try c.decodeIfPresent(Bool.self, forKey: .isModerator)
            ?? c.decodeIfPresent(Bool.self, forKey: .is_moderator)
        priceCurrency = try c.decodeIfPresent(String.self, forKey: .priceCurrency)
            ?? c.decodeIfPresent(String.self, forKey: .price_currency)
        priceAmountMinor = try c.decodeIfPresent(Int.self, forKey: .priceAmountMinor)
            ?? c.decodeIfPresent(Int.self, forKey: .price_amount_minor)
        billingPeriod = try c.decodeIfPresent(String.self, forKey: .billingPeriod)
            ?? c.decodeIfPresent(String.self, forKey: .billing_period)
        status = try c.decodeIfPresent(String.self, forKey: .status)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(slug, forKey: .slug)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(tags, forKey: .tags)
        try c.encodeIfPresent(visibility, forKey: .visibility)
        try c.encodeIfPresent(admission, forKey: .admission)
        try c.encodeIfPresent(memberCount, forKey: .memberCount)
        try c.encodeIfPresent(postCount, forKey: .postCount)
        try c.encodeIfPresent(ownerUsername, forKey: .ownerUsername)
        try c.encodeIfPresent(rules, forKey: .rules)
        try c.encodeIfPresent(isJoined, forKey: .isJoined)
        try c.encodeIfPresent(isOwner, forKey: .isOwner)
        try c.encodeIfPresent(isModerator, forKey: .isModerator)
        try c.encodeIfPresent(priceCurrency, forKey: .priceCurrency)
        try c.encodeIfPresent(priceAmountMinor, forKey: .priceAmountMinor)
        try c.encodeIfPresent(billingPeriod, forKey: .billingPeriod)
        try c.encodeIfPresent(status, forKey: .status)
    }
}

struct AnonymousMembership: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let spaceId: String
    var state: String
    var role: String?
    var joinedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, state, role
        case spaceId, space_id
        case joinedAt, joined_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Live join payload is `{ space_id, state }` — synthesize id when omitted.
        let resolvedSpaceId = try c.decodeIfPresent(String.self, forKey: .spaceId)
            ?? c.decodeIfPresent(String.self, forKey: .space_id)
            ?? ""
        spaceId = resolvedSpaceId
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? "active"
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? resolvedSpaceId
        role = try c.decodeIfPresent(String.self, forKey: .role)
        joinedAt = try c.decodeIfPresent(String.self, forKey: .joinedAt)
            ?? c.decodeIfPresent(String.self, forKey: .joined_at)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(spaceId, forKey: .spaceId)
        try c.encode(state, forKey: .state)
        try c.encodeIfPresent(role, forKey: .role)
        try c.encodeIfPresent(joinedAt, forKey: .joinedAt)
    }
}

// MARK: - Inbox

struct AnonymousNotification: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var kind: String?
    var title: String?
    var body: String?
    var spaceId: String?
    var spaceTitle: String?
    var postId: String?
    var actorUsername: String?
    var createdAt: String?
    var readAt: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, title, body
        case spaceId, space_id
        case spaceTitle, space_title
        case postId, post_id
        case actorUsername, actor_username
        case createdAt, created_at
        case readAt, read_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        spaceId = try c.decodeIfPresent(String.self, forKey: .spaceId)
            ?? c.decodeIfPresent(String.self, forKey: .space_id)
        spaceTitle = try c.decodeIfPresent(String.self, forKey: .spaceTitle)
            ?? c.decodeIfPresent(String.self, forKey: .space_title)
        postId = try c.decodeIfPresent(String.self, forKey: .postId)
            ?? c.decodeIfPresent(String.self, forKey: .post_id)
        actorUsername = try c.decodeIfPresent(String.self, forKey: .actorUsername)
            ?? c.decodeIfPresent(String.self, forKey: .actor_username)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
            ?? c.decodeIfPresent(String.self, forKey: .created_at)
        readAt = try c.decodeIfPresent(String.self, forKey: .readAt)
            ?? c.decodeIfPresent(String.self, forKey: .read_at)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(kind, forKey: .kind)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(body, forKey: .body)
        try c.encodeIfPresent(spaceId, forKey: .spaceId)
        try c.encodeIfPresent(spaceTitle, forKey: .spaceTitle)
        try c.encodeIfPresent(postId, forKey: .postId)
        try c.encodeIfPresent(actorUsername, forKey: .actorUsername)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(readAt, forKey: .readAt)
    }

    var isUnread: Bool { readAt == nil }

    var displayTitle: String {
        if let title, !title.isEmpty { return ContentSanitizer.displayText(title) }
        switch kind {
        case "reply": return "New reply"
        case "mention": return "Mention"
        case "space": return "Space update"
        default: return "Masquerade alert"
        }
    }

    var displayBody: String {
        if let body, !body.isEmpty { return ContentSanitizer.displayText(body) }
        if let actor = actorUsername, let space = spaceTitle {
            return "@\(actor) in \(space)"
        }
        if let actor = actorUsername { return "@\(actor)" }
        return "Activity in Masquerade"
    }
}

// MARK: - Content

struct AnonymousPost: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let spaceId: String
    var spaceSlug: String?
    var spaceTitle: String?
    var authorUsername: String
    var authorProfileId: String
    var title: String?
    var body: String
    var createdAt: String
    var editedAt: String?
    var score: Int?
    var commentCount: Int?
    var myVote: Int?
    var isPinned: Bool?
    var isLocked: Bool?
    var mediaType: String?
    var mediaURL: String?
    var thumbURL: String?

    /// UI title — `subreddit`/`reddit` already remapped to space/Masquerade.
    var displayTitle: String? {
        let t = ContentSanitizer.displayText(title)
        return t.isEmpty ? nil : t
    }

    /// UI body — never leak source-platform wording into Masquerade.
    var displayBody: String { ContentSanitizer.displayText(body) }

    var hasImage: Bool {
        guard let mediaType else { return false }
        return mediaType == "image" || mediaType == "gif"
    }

    var hasVideo: Bool { mediaType == "video" }

    var mediaURLValue: URL? {
        guard let mediaURL, let url = URL(string: mediaURL) else { return nil }
        return url
    }

    var thumbURLValue: URL? {
        guard let thumbURL, let url = URL(string: thumbURL) else { return nil }
        return url
    }

    enum CodingKeys: String, CodingKey {
        case id, title, body, author, score
        case spaceId, space_id
        case spaceSlug, space_slug
        case spaceTitle, space_title
        case authorUsername, author_username
        case authorProfileId, author_profile_id
        case createdAt, created_at
        case editedAt, edited_at
        case commentCount, comment_count
        case myVote, my_vote
        case isPinned, is_pinned
        case isLocked, is_locked
        case mediaType, media_type
        // mediaUrl/thumbUrl: convertFromSnakeCase maps media_url → mediaUrl (not mediaURL).
        case mediaURL, media_url, mediaUrl
        case thumbURL, thumb_url, thumbUrl
    }

    private struct AuthorBlob: Codable {
        let id: String?
        let username: String?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        spaceId = try c.decodeIfPresent(String.self, forKey: .spaceId)
            ?? c.decode(String.self, forKey: .space_id)
        spaceSlug = try c.decodeIfPresent(String.self, forKey: .spaceSlug)
            ?? c.decodeIfPresent(String.self, forKey: .space_slug)
        spaceTitle = try c.decodeIfPresent(String.self, forKey: .spaceTitle)
            ?? c.decodeIfPresent(String.self, forKey: .space_title)
        let author = try c.decodeIfPresent(AuthorBlob.self, forKey: .author)
        authorUsername = try c.decodeIfPresent(String.self, forKey: .authorUsername)
            ?? c.decodeIfPresent(String.self, forKey: .author_username)
            ?? author?.username
            ?? "anonymous"
        authorProfileId = try c.decodeIfPresent(String.self, forKey: .authorProfileId)
            ?? c.decodeIfPresent(String.self, forKey: .author_profile_id)
            ?? author?.id
            ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
            ?? c.decodeIfPresent(String.self, forKey: .created_at)
            ?? ""
        editedAt = try c.decodeIfPresent(String.self, forKey: .editedAt)
            ?? c.decodeIfPresent(String.self, forKey: .edited_at)
        score = try c.decodeIfPresent(Int.self, forKey: .score)
        commentCount = try c.decodeIfPresent(Int.self, forKey: .commentCount)
            ?? c.decodeIfPresent(Int.self, forKey: .comment_count)
        myVote = try c.decodeIfPresent(Int.self, forKey: .myVote)
            ?? c.decodeIfPresent(Int.self, forKey: .my_vote)
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned)
            ?? c.decodeIfPresent(Bool.self, forKey: .is_pinned)
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked)
            ?? c.decodeIfPresent(Bool.self, forKey: .is_locked)
        mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType)
            ?? c.decodeIfPresent(String.self, forKey: .media_type)
        mediaURL = try c.decodeIfPresent(String.self, forKey: .mediaURL)
            ?? c.decodeIfPresent(String.self, forKey: .media_url)
            ?? c.decodeIfPresent(String.self, forKey: .mediaUrl)
        thumbURL = try c.decodeIfPresent(String.self, forKey: .thumbURL)
            ?? c.decodeIfPresent(String.self, forKey: .thumb_url)
            ?? c.decodeIfPresent(String.self, forKey: .thumbUrl)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(spaceId, forKey: .spaceId)
        try c.encodeIfPresent(spaceSlug, forKey: .spaceSlug)
        try c.encodeIfPresent(spaceTitle, forKey: .spaceTitle)
        try c.encode(authorUsername, forKey: .authorUsername)
        try c.encode(authorProfileId, forKey: .authorProfileId)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encode(body, forKey: .body)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(editedAt, forKey: .editedAt)
        try c.encodeIfPresent(score, forKey: .score)
        try c.encodeIfPresent(commentCount, forKey: .commentCount)
        try c.encodeIfPresent(myVote, forKey: .myVote)
        try c.encodeIfPresent(isPinned, forKey: .isPinned)
        try c.encodeIfPresent(isLocked, forKey: .isLocked)
        try c.encodeIfPresent(mediaType, forKey: .mediaType)
        try c.encodeIfPresent(mediaURL, forKey: .mediaURL)
        try c.encodeIfPresent(thumbURL, forKey: .thumbURL)
    }
}

/// Pushed Masquerade destinations — IDs only (full post structs in the path
/// made NavigationStack pop the destination immediately after push).
enum AnonymousRoute: Hashable, Sendable {
    case space(slug: String)
    case post(id: String)
    case profile(username: String)
    /// Official Matterya (and later user↔user) DMs — stays inside Masquerade so Back → Inbox.
    case conversation(id: String)
}

struct AnonymousSearchResults: Decodable, Sendable {
    var people: [AnonymousProfile]
    var spaces: [AnonymousSpace]
    var posts: [AnonymousPost]

    enum CodingKeys: String, CodingKey {
        case people, spaces, posts
        case profiles
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        people = (try? c.decode([AnonymousProfile].self, forKey: .people))
            ?? (try? c.decode([AnonymousProfile].self, forKey: .profiles))
            ?? []
        spaces = (try? c.decode([AnonymousSpace].self, forKey: .spaces)) ?? []
        posts = (try? c.decode([AnonymousPost].self, forKey: .posts)) ?? []
    }

    init(people: [AnonymousProfile] = [], spaces: [AnonymousSpace] = [], posts: [AnonymousPost] = []) {
        self.people = people
        self.spaces = spaces
        self.posts = posts
    }
}

struct AnonymousPublicProfilePayload: Decodable, Sendable {
    var profile: AnonymousProfile
    var postCount: Int?
    var spaceCount: Int?

    enum CodingKeys: String, CodingKey {
        case profile
        case postCount, post_count
        case spaceCount, space_count
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profile = try c.decode(AnonymousProfile.self, forKey: .profile)
        postCount = try c.decodeIfPresent(Int.self, forKey: .postCount)
            ?? c.decodeIfPresent(Int.self, forKey: .post_count)
        spaceCount = try c.decodeIfPresent(Int.self, forKey: .spaceCount)
            ?? c.decodeIfPresent(Int.self, forKey: .space_count)
    }
}

struct AnonymousComment: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let postId: String
    var parentCommentId: String?
    var authorUsername: String
    var authorProfileId: String
    var body: String
    var createdAt: String
    var depth: Int?
    var score: Int?
    var myVote: Int?
    var replies: [AnonymousComment]?

    /// UI body — `subreddit` → space, `reddit` → masquerade (never raw).
    var displayBody: String { ContentSanitizer.displayText(body) }

    enum CodingKeys: String, CodingKey {
        case id, body, author, depth, score, replies
        case postId, post_id
        case parentCommentId, parent_comment_id, parent_id
        case authorUsername, author_username
        case authorProfileId, author_profile_id
        case createdAt, created_at
        case myVote, my_vote
    }

    private struct AuthorBlob: Codable {
        let id: String?
        let username: String?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        postId = try c.decodeIfPresent(String.self, forKey: .postId)
            ?? c.decodeIfPresent(String.self, forKey: .post_id)
            ?? ""
        parentCommentId = try c.decodeIfPresent(String.self, forKey: .parentCommentId)
            ?? c.decodeIfPresent(String.self, forKey: .parent_comment_id)
            ?? c.decodeIfPresent(String.self, forKey: .parent_id)
        let author = try c.decodeIfPresent(AuthorBlob.self, forKey: .author)
        authorUsername = try c.decodeIfPresent(String.self, forKey: .authorUsername)
            ?? c.decodeIfPresent(String.self, forKey: .author_username)
            ?? author?.username
            ?? "anonymous"
        authorProfileId = try c.decodeIfPresent(String.self, forKey: .authorProfileId)
            ?? c.decodeIfPresent(String.self, forKey: .author_profile_id)
            ?? author?.id
            ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
            ?? c.decodeIfPresent(String.self, forKey: .created_at)
            ?? ""
        depth = try c.decodeIfPresent(Int.self, forKey: .depth)
        score = try c.decodeIfPresent(Int.self, forKey: .score)
        myVote = try c.decodeIfPresent(Int.self, forKey: .myVote)
            ?? c.decodeIfPresent(Int.self, forKey: .my_vote)
        replies = try c.decodeIfPresent([AnonymousComment].self, forKey: .replies)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(postId, forKey: .postId)
        try c.encodeIfPresent(parentCommentId, forKey: .parentCommentId)
        try c.encode(authorUsername, forKey: .authorUsername)
        try c.encode(authorProfileId, forKey: .authorProfileId)
        try c.encode(body, forKey: .body)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(depth, forKey: .depth)
        try c.encodeIfPresent(score, forKey: .score)
        try c.encodeIfPresent(myVote, forKey: .myVote)
        try c.encodeIfPresent(replies, forKey: .replies)
    }
}

// MARK: - Pagination

struct AnonymousPage<T: Codable & Sendable>: Codable, Sendable {
    var items: [T]
    var nextCursor: String?
}

struct AnonymousNotificationsPage: Sendable {
    var items: [AnonymousNotification]
    var nextCursor: String?
    var unreadCount: Int
}

struct AnonymousFeedPage: Codable, Sendable {
    var items: [AnonymousPost]
    var nextCursor: String?
}

enum AnonymousFeedSort: String, CaseIterable, Identifiable, Sendable {
    /// Personalized MIND ranking (social hot + MMR + delivery ledger).
    case forYou = "for_you"
    case hot
    case new
    case top

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forYou: "For you"
        case .hot: "Hot"
        case .new: "New"
        case .top: "Top"
        }
    }
}

// MARK: - Errors

enum AnonymousErrorCode: String, Codable, Sendable {
    case under18 = "under_18"
    case unattested
    case noProfile = "no_profile"
    case paidDisabled = "paid_disabled"
    case usernameTaken = "username_taken"
    case usernameInvalid = "username_invalid"
    case suspended
    case forbidden
    case notFound = "not_found"
    case rateLimited = "rate_limited"
    case unauthenticated
    case sessionFailed = "session_failed"
    case schemaMissing = "schema_missing"
    case birthdateRequired = "birthdate_required"
    case birthdateMissing = "birthdate_missing"
    case notMember = "not_member"
    case network
    case unknown
}

enum AnonymousError: Error, LocalizedError, Equatable {
    case under18
    case unattested
    case noProfile
    case paidDisabled
    case usernameTaken
    case usernameInvalid(String?)
    case suspended
    case forbidden(String?)
    case notFound
    case rateLimited
    case network(String?)
    case server(String?)
    case decoding

    var errorDescription: String? {
        switch self {
        case .under18:
            return "Masquerade is only available to adults 18 and older."
        case .unattested:
            return "Confirm you are 18+ to enter Masquerade."
        case .noProfile:
            return "Claim a Masquerade username to continue."
        case .paidDisabled:
            return "Paid Spaces are coming soon. Join free Spaces for now."
        case .usernameTaken:
            return "That username was just taken. Try another suggestion."
        case .usernameInvalid(let detail):
            return detail ?? "That username isn’t allowed."
        case .suspended:
            return "Your Masquerade access is suspended."
        case .forbidden(let detail):
            return detail ?? "You don’t have permission to do that."
        case .notFound:
            return MatteryaCopy.anonymousOfflineBody
        case .rateLimited:
            return "Too many requests. Try again in a moment."
        case .network(let detail):
            return detail ?? MatteryaCopy.anonymousOfflineBody
        case .server(let detail):
            return detail ?? MatteryaCopy.anonymousOfflineTitle
        case .decoding:
            return "Couldn’t read the Masquerade response."
        }
    }

    static func from(code: String?, message: String? = nil) -> AnonymousError {
        switch AnonymousErrorCode(rawValue: code ?? "") {
        case .under18, .birthdateRequired, .birthdateMissing: return .under18
        case .unattested: return .unattested
        case .noProfile: return .noProfile
        case .paidDisabled: return .paidDisabled
        case .usernameTaken: return .usernameTaken
        case .usernameInvalid: return .usernameInvalid(message)
        case .suspended: return .suspended
        case .forbidden, .notMember: return .forbidden(message)
        case .notFound: return .notFound
        case .rateLimited: return .rateLimited
        case .unauthenticated:
            return .network("Sign in again to open Masquerade.")
        case .schemaMissing, .sessionFailed:
            return .server(message ?? "Masquerade session isn’t ready yet. Pull to retry.")
        case .network: return .network(message)
        default: return .server(message ?? code)
        }
    }
}

// MARK: - Create payloads

struct AnonymousCreateSpaceInput: Codable, Sendable {
    var slug: String
    var title: String
    var description: String
    var category: String?
    var tags: [String]
    var rules: [String]
    var visibility: String
    var admission: String
}

struct AnonymousCreatePostInput: Codable, Sendable {
    var title: String?
    var body: String
    var mediaType: String?
    var mediaURL: String?
    var thumbURL: String?

    enum CodingKeys: String, CodingKey {
        case title, body
        case mediaType = "media_type"
        case mediaURL = "media_url"
        case thumbURL = "thumb_url"
    }
}

struct AnonymousCreateCommentInput: Codable, Sendable {
    var body: String
    var parentCommentId: String?
}

struct AnonymousVoteInput: Codable, Sendable {
    var targetType: String
    var targetId: String
    var value: Int
}

struct AnonymousReportInput: Codable, Sendable {
    var targetType: String
    var targetId: String
    var reason: String
}

struct AnonymousBlockInput: Codable, Sendable {
    var profileId: String
}
