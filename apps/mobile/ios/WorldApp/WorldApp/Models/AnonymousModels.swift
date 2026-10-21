import Foundation

// MARK: - Identity

struct AnonymousProfile: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let username: String
    var avatarSeed: String?
    var createdAt: String?
    var state: String?

    var displayHandle: String { "@\(username)" }
}

struct AnonymousSession: Codable, Hashable, Sendable {
    var eligibleAdult: Bool
    var ageAttested: Bool
    var birthdateMissing: Bool
    var suspended: Bool
    var profile: AnonymousProfile?
    var suggestedUsername: String?
    var privacyNoticeVersion: String?

    static let empty = AnonymousSession(
        eligibleAdult: false,
        ageAttested: false,
        birthdateMissing: false,
        suspended: false,
        profile: nil,
        suggestedUsername: nil,
        privacyNoticeVersion: nil
    )
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

    var priceLabel: String? {
        guard isPaid, let minor = priceAmountMinor, let currency = priceCurrency else { return nil }
        let amount = Double(minor) / 100.0
        let period = billingPeriod.map { " / \($0)" } ?? ""
        return String(format: "%@ %.2f%@", currency, amount, period)
    }
}

struct AnonymousMembership: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let spaceId: String
    var state: String
    var role: String?
    var joinedAt: String?
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
}

// MARK: - Pagination

struct AnonymousPage<T: Codable & Sendable>: Codable, Sendable {
    var items: [T]
    var nextCursor: String?
}

struct AnonymousFeedPage: Codable, Sendable {
    var items: [AnonymousPost]
    var nextCursor: String?
}

enum AnonymousFeedSort: String, CaseIterable, Identifiable, Sendable {
    case hot
    case new
    case top

    var id: String { rawValue }

    var title: String {
        switch self {
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
            return "Anonymous is only available to adults 18 and older."
        case .unattested:
            return "Confirm you are 18+ to enter Anonymous."
        case .noProfile:
            return "Claim an Anonymous username to continue."
        case .paidDisabled:
            return "Paid Spaces are coming soon. Join free Spaces for now."
        case .usernameTaken:
            return "That username was just taken. Try another suggestion."
        case .usernameInvalid(let detail):
            return detail ?? "That username isn’t allowed."
        case .suspended:
            return "Your Anonymous access is suspended."
        case .forbidden(let detail):
            return detail ?? "You don’t have permission to do that."
        case .notFound:
            return "That content isn’t available."
        case .rateLimited:
            return "Too many requests. Try again in a moment."
        case .network(let detail):
            return detail ?? "Couldn’t reach Anonymous right now."
        case .server(let detail):
            return detail ?? "Anonymous isn’t available right now."
        case .decoding:
            return "Couldn’t read the Anonymous response."
        }
    }

    static func from(code: String?, message: String? = nil) -> AnonymousError {
        switch AnonymousErrorCode(rawValue: code ?? "") {
        case .under18: return .under18
        case .unattested: return .unattested
        case .noProfile: return .noProfile
        case .paidDisabled: return .paidDisabled
        case .usernameTaken: return .usernameTaken
        case .usernameInvalid: return .usernameInvalid(message)
        case .suspended: return .suspended
        case .forbidden: return .forbidden(message)
        case .notFound: return .notFound
        case .rateLimited: return .rateLimited
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
