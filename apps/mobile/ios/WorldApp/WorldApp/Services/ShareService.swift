import Foundation
import UIKit

enum ShareContent: Sendable {
    case post(CountryPost)
    case profile(Profile)
    case news(ExternalNewsItem)
    case appInvite
    case custom(title: String, text: String, url: URL?)
}

@MainActor
final class ShareService {
    static let shared = ShareService()

    private init() {}

    var appInviteURL: URL {
        URL(string: "https://matterya.com/download")!
    }

    func postURL(_ postID: String) -> URL {
        URL(string: "https://matterya.com/post/\(postID)")!
    }

    func profileURL(username: String) -> URL {
        URL(string: "https://matterya.com/profile/\(username)")!
    }

    func newsURL(_ newsID: String) -> URL {
        URL(string: "https://matterya.com/news/\(newsID)")!
    }

    func shareText(for content: ShareContent) -> String {
        switch content {
        case .post(let post):
            let author = post.authorDisplayName
            if let headline = post.displayHeadline {
                return "\(headline) — \(author) on Matterya"
            }
            return "\(author) on Matterya"
        case .profile(let profile):
            let name = profile.displayName ?? profile.username ?? "Matterya member"
            return "Follow \(name) on Matterya"
        case .news(let item):
            return item.title
        case .appInvite:
            return "Join me on Matterya — connect with your country and the world."
        case .custom(let title, _, _):
            return title
        }
    }

    func shareURL(for content: ShareContent) -> URL? {
        switch content {
        case .post(let post):
            return PlayPlatformBridge.shareURL(for: post)
        case .profile(let profile):
            guard let username = profile.username, !username.isEmpty else { return appInviteURL }
            return profileURL(username: username)
        case .news(let item):
            if let url = URL(string: item.url) { return url }
            return newsURL(item.id)
        case .appInvite:
            return appInviteURL
        case .custom(_, _, let url):
            return url
        }
    }

    func activityItems(for content: ShareContent) -> [Any] {
        let text = shareText(for: content)
        var items: [Any] = [text]
        if let url = shareURL(for: content) {
            items.append(url)
        }
        if case .post(let post) = content, let imageURL = post.feedImageURL ?? post.posterImageURL {
            items.append(imageURL)
        }
        return items
    }

    func copyLink(for content: ShareContent) {
        guard let url = shareURL(for: content) else { return }
        UIPasteboard.general.string = url.absoluteString
    }

    func messageBody(for content: ShareContent) -> String {
        let text = shareText(for: content)
        guard let url = shareURL(for: content) else { return text }
        return "\(text)\n\(url.absoluteString)"
    }

    func parseDeepLink(_ url: URL) -> AppDestination? {
        let host = (url.host ?? "").lowercased()
        let scheme = url.scheme?.lowercased() ?? ""
        let isAppScheme = scheme == "matterya" || scheme == "worldapp"
        let isWeb = host == "matterya.com" || host == "www.matterya.com"

        guard isAppScheme || isWeb else { return nil }

        var path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if isAppScheme, let hostPath = url.host, !hostPath.isEmpty, hostPath != "matterya.com" {
            path = "\(hostPath)/\(path)".trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        let parts = path.split(separator: "/").map(String.init)
        guard let first = parts.first?.lowercased() else { return nil }

        switch first {
        case "post", "p":
            if let id = parts.dropFirst().first { return .post(id) }
        case "profile", "u":
            if let username = parts.dropFirst().first { return .publicProfile(username: username) }
        case "news":
            if let id = parts.dropFirst().first { return .news(id) }
        case "play":
            guard parts.count >= 2 else { return nil }
            let section = parts[1].lowercased()
            switch section {
            case "watch":
                if let id = parts.dropFirst(2).first { return .playWatch(id) }
            case "channel":
                let remainder = Array(parts.dropFirst(2))
                if remainder.count >= 2, remainder[0].lowercased() == "id", !remainder[1].isEmpty {
                    return .playChannelID(remainder[1])
                }
                if let username = remainder.first, !username.isEmpty {
                    return .playChannel(username: username)
                }
            default:
                break
            }
        case "settings":
            return .settings
        case "premium", "plus":
            return .settings
        default:
            break
        }
        return nil
    }

    func sendPostInMessage(post: CountryPost, conversationID: String) async throws {
        // Structured payload so chat renders a post card / playable hub video (not a bare link).
        let body = Message.buildShareBody(post: post)
        _ = try await MessagesService.shared.sendMessage(conversationID: conversationID, body: body)
    }

    func sendPostToUser(post: CountryPost, userID: String) async throws -> Conversation {
        let conversation = try await MessagesService.shared.startConversation(targetID: userID)
        try await sendPostInMessage(post: post, conversationID: conversation.id)
        return conversation
    }
}