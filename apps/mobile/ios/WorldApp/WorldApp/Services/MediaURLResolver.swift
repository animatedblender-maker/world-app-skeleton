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
                // Prefer typed video rows — don't over-filter with isVideoURL (signed R2 paths vary).
                if let resolved = resolve(url), !isImageURL(resolved) { return resolved }
            }
            // Payload without type tags but clearly a spark/reel/video post.
            if post.hasVideo || post.isReel || post.isSpark {
                for url in payload.urls {
                    if let resolved = resolve(url), !isImageURL(resolved) { return resolved }
                }
            }
        }

        // Plain mediaURL (most R2 / Supabase sparks land here).
        if post.hasVideo || post.isReel || post.isSpark {
            if let media = resolve(post.mediaURL), !isImageURL(media) { return media }
            // Some rows only stamp the playable file on primaryMediaURL / thumb.
            if let primary = resolve(post.primaryMediaURL), !isImageURL(primary) {
                if isVideoURL(primary) || post.hasVideo || post.isReel { return primary }
            }
            if let thumb = resolve(post.thumbURL), isVideoURL(thumb) { return thumb }
        }

        // Last resort: any mediaURL that looks like video even if media_type was wrong.
        if let media = resolve(post.mediaURL), isVideoURL(media) { return media }
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
        // Server Frame 0 (first displayed video frame) — prefer over any CDN fallback.
        if let frame0 = frame0PosterURL(for: post) { return frame0 }
        if let thumb = resolve(post.thumbURL), !isVideoURL(thumb) { return thumb }
        // Matterya R2 LongForm/Sparks: never use YouTube hqdefault (wrong pixels vs Frame 0).
        // Nil → client holds black / extracts t=0 until backfill fills thumb_url.
        if hasMatteryaR2VideoKey(post) {
            return imageURL(for: post)
        }
        // Non-R2 legacy only.
        if let yt = r2LongformYouTubePosterURL(for: post) { return yt }
        return imageURL(for: post)
    }

    /// True when media lives on Matterya R2 (catalog or share) — Frame 0 owns the poster.
    static func hasMatteryaR2VideoKey(_ post: CountryPost) -> Bool {
        let blobs = [post.mediaURL, post.thumbURL, post.linkURL].compactMap { $0?.lowercased() }
        for b in blobs {
            if b.contains("r2_key") || b.contains("matterya-sparks") || b.contains("longform/")
                || b.contains("shortform/") || b.contains("r2.cloudflarestorage.com") {
                return true
            }
        }
        return false
    }

    /// Prefer server `frame0_*.webp` / media JSON `posters` (true t=0 pixels, same aspect as film).
    static func frame0PosterURL(for post: CountryPost) -> URL? {
        // Prefer embedded ladder (1080 → 512 → 256) when present — same aspect, sharper on Sparks.
        if let embedded = embeddedFrame0PosterURL(from: post.mediaURL) {
            return embedded
        }
        if let thumb = resolve(post.thumbURL), !isVideoURL(thumb), looksLikeFrame0Poster(thumb) {
            return thumb
        }
        return nil
    }

    static func looksLikeFrame0Poster(_ url: URL) -> Bool {
        let s = url.absoluteString.lowercased()
        return s.contains("frame0_512.webp")
            || s.contains("frame0_256.webp")
            || s.contains("frame0_1080.webp")
            || s.contains("frame0_")
    }

    /// media_url JSON may include `posters: { "256"|"512"|"1080": url }` after MediaReady.
    /// Prefer larger Frame 0 so aspect/pixels match the film (1080 → 512 → 256).
    static func embeddedFrame0PosterURL(from mediaURL: String?) -> URL? {
        guard let raw = mediaURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.hasPrefix("{"),
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let posters = obj["posters"] as? [String: Any] {
            for key in ["1080", "512", "256"] {
                if let s = posters[key] as? String, let u = resolve(s), !isVideoURL(u) {
                    return u
                }
            }
        }
        return nil
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

    /// Resolve a play configuration.
    /// - R2 **signed** URLs: play immediately if still valid; only hit API when near/past expiry.
    /// - (Previously every play awaited GraphQL → stuck loading + feed lag + ghost audio.)
    /// - Archive / Supabase: existing CDN/auth paths.
    static func playbackConfiguration(for url: URL, postID: String? = nil) async -> MediaPlaybackConfiguration {
        // Never run video CDN resolution on image posters (thumbs / services/img).
        if isImageURL(url) {
            return MediaPlaybackConfiguration(url: url, headers: nil)
        }

        // R2: always live-resolve when we have a post id and the URL is unsigned public
        // (pub-*.r2.dev often 403) or a dying presign. Never hand AVPlayer a dead public link.
        if looksLikeR2HostedURL(url), let postID, !postID.isEmpty {
            let needsLive =
                !isPresignedObjectURL(url)
                || isPresignExpiredOrNearExpiry(url, slackSeconds: 3600)
            if needsLive {
                if let live = await R2PlaybackResolver.shared.playURL(postID: postID, fallback: nil) {
                    // Prefer live only when it is actually signed / different host — avoid
                    // caching the same 403 public URL forever.
                    if live != url || isPresignedObjectURL(live) {
                        return MediaPlaybackConfiguration(url: live, headers: nil)
                    }
                }
            } else if isPresignedObjectURL(url) {
                return MediaPlaybackConfiguration(url: url, headers: nil)
            }
        }

        // Internet Archive `/download/` URLs 302 to CDN hosts. AVPlayer often never leaves
        // the poster if handed the redirect URL — same path used by hub long-form player.
        if ArchiveVideoPlayback.isArchiveURL(url) {
            // Resolve CDN first; do NOT attach custom headers to AVPlayer — Archive CDN hangs with them.
            let resolved = await ArchiveVideoPlayback.resolvedPlaybackURL(for: url)
            return MediaPlaybackConfiguration(url: resolved, headers: nil)
        }

        guard SupabaseStorageAccess.isPostsBucketURL(url) else {
            // Still-valid HTTPS — play direct.
            return MediaPlaybackConfiguration(url: url, headers: nil)
        }

        if let headers = await SupabaseStorageAccess.requestHeaders(),
           let authenticated = SupabaseStorageAccess.authenticatedURL(from: url) {
            return MediaPlaybackConfiguration(url: authenticated, headers: headers)
        }

        let publicURL = SupabaseStorageAccess.publicURL(from: url) ?? url
        return MediaPlaybackConfiguration(url: publicURL, headers: nil)
    }

    /// True for any R2-hosted path (signed or public custom domain).
    static func looksLikeR2HostedURL(_ url: URL) -> Bool {
        let lower = url.absoluteString.lowercased()
        return lower.contains("r2.cloudflarestorage.com")
            || lower.contains("matterya-sparks")
            || lower.contains("r2.dev")
            || lower.contains("\"r2_key\"")
    }

    static func playbackFallbackConfiguration(for url: URL) -> MediaPlaybackConfiguration? {
        guard SupabaseStorageAccess.isPostsBucketURL(url),
              let publicURL = SupabaseStorageAccess.publicURL(from: url),
              publicURL != url
        else { return nil }
        return MediaPlaybackConfiguration(url: publicURL, headers: nil)
    }

    /// Legacy name — true when URL is a signed object URL (may still be valid).
    static func looksLikeExpiredOrSignedR2URL(_ url: URL) -> Bool {
        isPresignedObjectURL(url)
    }

    /// AWS/R2 style query-string signature present.
    static func isPresignedObjectURL(_ url: URL) -> Bool {
        let lower = url.absoluteString.lowercased()
        if lower.contains("x-amz-signature") || lower.contains("x-amz-algorithm") {
            return true
        }
        // Some clients use X-Amz-Credential without Algorithm in rare cases.
        if lower.contains("x-amz-credential"), lower.contains("x-amz-expires") {
            return true
        }
        return false
    }

    /// Parse X-Amz-Date + X-Amz-Expires; true if already dead or within `slackSeconds` of death.
    static func isPresignExpiredOrNearExpiry(_ url: URL, slackSeconds: TimeInterval = 3600) -> Bool {
        guard isPresignedObjectURL(url) else { return false }
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return true // can't parse → treat as risky, re-resolve
        }
        var expires: String?
        var dateStr: String?
        for item in comps.queryItems ?? [] {
            let name = item.name.lowercased()
            if name == "x-amz-expires" { expires = item.value }
            if name == "x-amz-date" { dateStr = item.value }
        }
        guard let expRaw = expires, let expSecs = TimeInterval(expRaw), expSecs > 0 else {
            // Signed but no expiry field — re-resolve to be safe only if host is R2.
            return looksLikeR2HostedURL(url)
        }
        // X-Amz-Date is usually yyyyMMdd'T'HHmmss'Z'
        let start: Date
        if let dateStr,
           let parsed = parseAmzDate(dateStr) {
            start = parsed
        } else {
            // Missing date → assume issued "now" is wrong; force refresh.
            return true
        }
        let deadline = start.addingTimeInterval(expSecs)
        return Date().addingTimeInterval(slackSeconds) >= deadline
    }

    private static func parseAmzDate(_ raw: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        if let d = f.date(from: raw) { return d }
        // ISO fallback
        return ISO8601DateFormatter().date(from: raw)
    }
}

extension CountryPost {
    var playableVideoURL: URL? { MediaURLResolver.videoURL(for: self) }
    var posterImageURL: URL? { MediaURLResolver.posterURL(for: self) }
    var resolvedImageURL: URL? { MediaURLResolver.imageURL(for: self) }
    var feedImageURL: URL? { MediaURLResolver.posterURL(for: self) ?? MediaURLResolver.imageURL(for: self) }
}