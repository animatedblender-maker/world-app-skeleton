import SwiftUI

enum StreamingPlatform: String, CaseIterable, Identifiable {
    case netflix
    case appleMusic
    case appleTV
    case spotify
    case disney

    var id: String { rawValue }

    var apiSlug: String {
        switch self {
        case .netflix: "netflix"
        case .appleMusic: "apple_music"
        case .appleTV: "apple_tv"
        case .spotify: "spotify"
        case .disney: "disney"
        }
    }

    static func fromAPISlug(_ slug: String) -> StreamingPlatform? {
        switch slug.lowercased() {
        case "netflix": .netflix
        case "apple_music": .appleMusic
        case "apple_tv": .appleTV
        case "spotify": .spotify
        case "disney": .disney
        default: nil
        }
    }

    var title: String {
        switch self {
        case .netflix: "Netflix"
        case .appleMusic: "Apple Music"
        case .appleTV: "Apple TV+"
        case .spotify: "Spotify"
        case .disney: "Disney+"
        }
    }

    var icon: String {
        switch self {
        case .netflix: "play.tv.fill"
        case .appleMusic: "music.note.list"
        case .appleTV: "appletv.fill"
        case .spotify: "waveform"
        case .disney: "sparkles.tv.fill"
        }
    }

    var accent: Color {
        switch self {
        case .netflix: Color(red: 0.90, green: 0.04, blue: 0.08)
        case .appleMusic: Color(red: 0.98, green: 0.24, blue: 0.37)
        case .appleTV: Theme.ink
        case .spotify: Color(red: 0.12, green: 0.73, blue: 0.33)
        case .disney: Color(red: 0.07, green: 0.29, blue: 0.67)
        }
    }

    var isAvailable: Bool {
        switch self {
        case .netflix, .appleMusic, .appleTV: true
        case .spotify, .disney: false
        }
    }
}

struct ConnectedAccount: Identifiable {
    let id: String
    let platform: StreamingPlatform
    let isLinked: Bool
    let sharingEnabled: Bool
}

struct YourNowPlaying: Identifiable {
    let id: String
    let platform: StreamingPlatform
    let title: String
    let subtitle: String
    let progressLabel: String
    let progress: Double
    let isSharing: Bool
    let momentLabel: String?
    let contentId: String?
    let progressMs: Int
    let durationMs: Int
    let updatedAt: Date
}

struct FriendActivity: Identifiable {
    let id: String
    let name: String
    let avatarURL: String?
    let avatarSeed: String
    let platform: StreamingPlatform
    let title: String
    let subtitle: String
    let detail: String
    let isLive: Bool
    let contentId: String?
    let progressMs: Int
    let durationMs: Int
    let updatedAt: Date
}

struct MomentRoom: Identifiable {
    let id: String
    let roomKey: String
    let platform: StreamingPlatform
    let showTitle: String
    let episodeLabel: String
    let timestamp: String
    let activeFriends: Int
    let previewComments: [MomentComment]
    let heat: Double
}

struct MomentComment: Identifiable {
    let id: String
    let author: String
    let body: String
    let reactions: Int
}

enum ConnectedHubContent {
    static let ecosystemTeasers: [(String, String)] = [
        ("bag.fill", "Shopping with friends — vote on drops, split carts, share finds"),
        ("ticket.fill", "Live events — concerts & sports with a shared watch thread"),
        ("book.fill", "Reading circles — same chapter, same reactions"),
    ]

    static func mergedAccounts(_ remote: [ConnectedAccount]) -> [ConnectedAccount] {
        let remoteByPlatform = Dictionary(uniqueKeysWithValues: remote.map { ($0.platform, $0) })
        return StreamingPlatform.allCases.map { platform in
            if let account = remoteByPlatform[platform] {
                return account
            }
            return ConnectedAccount(
                id: platform.rawValue,
                platform: platform,
                isLinked: false,
                sharingEnabled: false
            )
        }
    }
}