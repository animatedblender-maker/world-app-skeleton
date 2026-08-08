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
        // Internet Archive: always prefer services/img — nested `.thumbs/` paths are
        // slower and flakier on mobile (often 1–2s+). services/img is the snappy poster.
        if let ia = archiveServicesImgURL(for: post) { return ia }
        if let thumb = resolve(post.thumbURL), !isVideoURL(thumb) { return thumb }
        // R2 LongForm packs are YouTube ids under LongForm/<Country>/<id>/video.mp4
        // — use YouTube's CDN poster so Hubs isn't a wall of empty film icons.
        if let yt = r2LongformYouTubePosterURL(for: post) { return yt }
        return imageURL(for: post)
    }

    /// Best poster for Hubs lists / prefetch (same URL as posterURL; kept explicit for call sites).
    static func hubsListPosterURL(for post: CountryPost) -> URL? {
        posterURL(for: post)
    }

    /// `…/LongForm/<Country>/<youtubeId>/video.mp4` (in media JSON or path) → `i.ytimg.com` poster.
    static func r2LongformYouTubePosterURL(for post: CountryPost) -> URL? {
        let blobs: [String] = [
            post.thumbURL,
            post.mediaURL,
            post.linkURL,
        ].compactMap { $0 }
        for raw in blobs {
            if let id = youtubeIDFromR2LongformPath(raw) {
                // hqdefault is reliable; maxresdefault 404s for many older uploads.
                return URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")
            }
        }
        return nil
    }

    /// Extract YouTube video id from R2 LongForm object keys / media JSON.
    static func youtubeIDFromR2LongformPath(_ raw: String) -> String? {
        let patterns = [
            #"[Ll]ong[Ff]orm/[^/\"'\\]+/([A-Za-z0-9_-]{6,20})(?:/|\.mp4|\"|'|\?|$)"#,
            #"[Ll]ong[Ff]orm%2F[^/%]+%2F([A-Za-z0-9_-]{6,20})"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(raw.startIndex..., in: raw)
            if let match = regex.firstMatch(in: raw, options: [], range: range),
               match.numberOfRanges >= 2,
               let idRange = Range(match.range(at: 1), in: raw) {
                let id = String(raw[idRange])
                // TikTok spark folders are long pure digit ids — not YouTube posters.
                if id.count >= 15, id.allSatisfy(\.isNumber) { continue }
                if id.count >= 6, id.count <= 20 { return id }
            }
        }
        return nil
    }

    /// `archive.org/download/<id>/…` or `archive.org/details/<id>` → services/img thumbnail.
    static func archiveServicesImgURL(for post: CountryPost) -> URL? {
        let candidates = [post.thumbURL, post.mediaURL, post.linkURL].compactMap { $0 }
        for raw in candidates {
            if let id = archiveItemIdentifier(from: raw),
               let url = URL(string: "https://archive.org/services/img/\(id)") {
                return url
            }
        }
        return nil
    }

    static func archiveItemIdentifier(from raw: String) -> String? {
        let lower = raw.lowercased()
        guard lower.contains("archive.org") else { return nil }
        // /download/<id>/  or  /details/<id>  or  /services/img/<id>
        let patterns = [
            #"/download/([^/?#]+)"#,
            #"/details/([^/?#]+)"#,
            #"/services/img/([^/?#]+)"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: raw) {
                let id = String(raw[range]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !id.isEmpty, id != "download", id != "details" { return id }
            }
        }
        return nil
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

    static func isImageURL(_ url: URL) -> Bool {
        let lower = url.absoluteString.lowercased()
        if lower.range(
            of: #"\.(jpe?g|png|gif|webp|avif|bmp|heic)(\?|#|$)"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        // Archive item posters (no extension).
        if lower.contains("archive.org/services/img/") { return true }
        if lower.contains("/__ia_thumb.jpg") || lower.contains(".thumbs/") { return true }
        return false
    }

    static func isVideoURL(_ url: URL) -> Bool {
        // Image extensions always win — IA thumb paths must never be treated as video.
        if isImageURL(url) { return false }
        let lower = url.absoluteString.lowercased()
        if lower.range(
            of: #"\.(mp4|webm|mov|m4v|avi|mkv)(\?|#|$)"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        // Path segment /video/ or query video= — not the substring "video" in identifiers.
        if lower.contains("/video/") || lower.contains("/video.") || lower.contains("video%") {
            return true
        }
        return false
    }

    static func playbackURL(from url: URL) async -> URL {
        await playbackConfiguration(for: url).url
    }

    static func playbackConfiguration(for url: URL) async -> MediaPlaybackConfiguration {
        // Never run video CDN resolution on image posters (thumbs / services/img).
        if isImageURL(url) {
            return MediaPlaybackConfiguration(url: url, headers: nil)
        }
        // Internet Archive `/download/` URLs 302 to CDN hosts. AVPlayer often never leaves
        // the poster if handed the redirect URL — same path used by hub long-form player.
        if ArchiveVideoPlayback.isArchiveURL(url) {
            // Resolve CDN first; do NOT attach custom headers to AVPlayer — Archive CDN hangs with them.
            let resolved = await ArchiveVideoPlayback.resolvedPlaybackURL(for: url)
            return MediaPlaybackConfiguration(url: resolved, headers: nil)
        }

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