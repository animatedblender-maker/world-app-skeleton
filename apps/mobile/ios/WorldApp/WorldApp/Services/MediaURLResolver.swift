import Foundation

struct MediaPlaybackConfiguration: Sendable {
    let url: URL
    let headers: [String: String]?
}

enum SupabaseStorageAccess {
    static func isPostsBucketURL(_ url: URL) -> Bool {
        let value = url.absoluteString
        return value.contains("/storage/v1/object/") && value.contains("/posts/")
    }

    static func authenticatedURL(from url: URL) -> URL? {
        var value = url.absoluteString
        if value.contains("/object/public/posts/") {
            value = value.replacingOccurrences(of: "/object/public/posts/", with: "/object/authenticated/posts/")
        } else if value.contains("/object/sign/posts/") {
            return url
        } else if value.contains("/object/authenticated/posts/") {
            return url
        }
        return URL(string: value)
    }

    static func publicURL(from url: URL) -> URL? {
        var value = url.absoluteString
        if value.contains("/object/authenticated/posts/") {
            value = value.replacingOccurrences(of: "/object/authenticated/posts/", with: "/object/public/posts/")
        }
        return URL(string: value)
    }

    static func requestHeaders() async -> [String: String]? {
        guard await AuthService.shared.isAuthenticated else { return nil }
        guard let token = try? await AuthService.shared.ensureValidToken() else { return nil }
        return [
            "Authorization": "Bearer \(token)",
            "apikey": AppConfig.supabaseAnonKey,
        ]
    }
}

enum MediaURLResolver {
    static func videoURL(for post: CountryPost) -> URL? {
        if let payload = post.mediaPayload {
            let pairs = zip(payload.urls, payload.types)
            for (url, type) in pairs where type.lowercased() == "video" {
                if let resolved = resolve(url) { return resolved }
            }
            if post.hasVideo, let first = payload.urls.first {
                return resolve(first)
            }
        }

        if post.hasVideo {
            return resolve(post.mediaURL) ?? resolve(post.thumbURL)
        }
        return nil
    }

    static func imageURL(for post: CountryPost) -> URL? {
        if let payload = post.mediaPayload {
            let pairs = zip(payload.urls, payload.types)
            for (url, type) in pairs where type.lowercased() == "image" {
                if let resolved = resolve(url), !isVideoURL(resolved) { return resolved }
            }
            for url in payload.urls {
                if let resolved = resolve(url), !isVideoURL(resolved) { return resolved }
            }
        }

        if let media = resolve(post.mediaURL), !isVideoURL(media) { return media }
        if let thumb = resolve(post.thumbURL), !isVideoURL(thumb) { return thumb }
        return nil
    }

    static func posterURL(for post: CountryPost) -> URL? {
        if let thumb = resolve(post.thumbURL), !isVideoURL(thumb) { return thumb }
        return imageURL(for: post)
    }

    static func resolve(_ raw: String?) -> URL? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("{") || value.hasPrefix("[") { return nil }

        if value.hasPrefix("//") {
            value = "https:\(value)"
        } else if !value.contains("://"), value.hasPrefix("/") {
            value = "\(AppConfig.apiBaseURL)\(value)"
        } else if !value.contains("://"), !value.hasPrefix("/") {
            if value.contains("/") && !value.contains(" ") {
                value = "\(AppConfig.supabaseURL)/storage/v1/object/public/posts/\(value.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
            } else {
                value = "https://\(value)"
            }
        }

        if let url = URL(string: value), url.scheme != nil {
            return url
        }

        if let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
           let url = URL(string: encoded),
           url.scheme != nil {
            return url
        }
        return nil
    }

    static func isVideoURL(_ url: URL) -> Bool {
        let lower = url.absoluteString.lowercased()
        return lower.range(
            of: #"\.(mp4|webm|mov|m4v|avi|mkv)(\?|#|$)"#,
            options: .regularExpression
        ) != nil || lower.contains("/video") || lower.contains("video%")
    }

    static func playbackURL(from url: URL) async -> URL {
        await playbackConfiguration(for: url).url
    }

    static func playbackConfiguration(for url: URL) async -> MediaPlaybackConfiguration {
        guard SupabaseStorageAccess.isPostsBucketURL(url) else {
            return MediaPlaybackConfiguration(url: url, headers: nil)
        }

        if let headers = await SupabaseStorageAccess.requestHeaders(),
           let authenticated = SupabaseStorageAccess.authenticatedURL(from: url) {
            return MediaPlaybackConfiguration(url: authenticated, headers: headers)
        }

        let publicURL = SupabaseStorageAccess.publicURL(from: url) ?? url
        return MediaPlaybackConfiguration(url: publicURL, headers: nil)
    }

    static func playbackFallbackConfiguration(for url: URL) -> MediaPlaybackConfiguration? {
        guard SupabaseStorageAccess.isPostsBucketURL(url),
              let publicURL = SupabaseStorageAccess.publicURL(from: url),
              publicURL != url
        else { return nil }
        return MediaPlaybackConfiguration(url: publicURL, headers: nil)
    }
}

extension CountryPost {
    var playableVideoURL: URL? { MediaURLResolver.videoURL(for: self) }
    var posterImageURL: URL? { MediaURLResolver.posterURL(for: self) }
    var resolvedImageURL: URL? { MediaURLResolver.imageURL(for: self) }
    var feedImageURL: URL? { MediaURLResolver.posterURL(for: self) ?? MediaURLResolver.imageURL(for: self) }
}