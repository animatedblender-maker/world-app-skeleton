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
        let mt = (post.mediaType ?? "").lowercased()
        // Explicit image/text posts are never Sparks/AV — even when the R2 key ends in video.mp4.
        if mt == "image" || mt == "photo" || mt == "gif" || mt == "none" || mt == "text" {
            return nil
        }
        if let payload = post.mediaPayload {
            let types = payload.types.map { $0.lowercased() }
            if types.contains("image") && !types.contains("video") {
                return nil
            }
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
        // Skip when payload already declared image-only.
        if let media = resolve(post.mediaURL), isVideoURL(media) { return media }
        return nil
    }

    static func imageURL(for post: CountryPost) -> URL? {
        let mt = (post.mediaType ?? "").lowercased()
        // Demoted meme packs keep a `.mp4` key with JPEG bytes + types:["image"].
        let declaredImage = mt == "image" || mt == "photo" || mt == "gif"
        if let payload = post.mediaPayload {
            let pairs = zip(payload.urls, payload.types)
            for (url, type) in pairs where type.lowercased() == "image" {
                if let resolved = resolve(url) {
                    if declaredImage || !isVideoURL(resolved) { return resolved }
                }
            }
            if declaredImage {
                for url in payload.urls {
                    if let resolved = resolve(url) { return resolved }
                }
            } else {
                for url in payload.urls {
                    if let resolved = resolve(url), !isVideoURL(resolved) { return resolved }
                }
            }
        }

        if let media = resolve(post.mediaURL) {
            if declaredImage || !isVideoURL(media) { return media }
        }
        if let thumb = resolve(post.thumbURL), !isVideoURL(thumb) { return thumb }
        return nil
    }

    static func posterURL(for post: CountryPost) -> URL? {
        // Internet Archive: always prefer services/img — nested `.thumbs/` paths are
        // slower and flakier on mobile (often 1–2s+). services/img is the snappy poster.
        if let ia = archiveServicesImgURL(for: post), isUsablePosterURL(ia) { return ia }
        // Server Frame 0 (first displayed video frame) — prefer over any CDN fallback.
        if let frame0 = frame0PosterURL(for: post) { return frame0 }
        if let thumb = resolve(post.thumbURL), !isVideoURL(thumb), isUsablePosterURL(thumb) {
            return thumb
        }
        // Matterya R2: Frame 0 first, then any usable image, then LongForm YouTube
        // hqdefault — never return nil for LongForm or Hubs tiles stay black forever.
        if hasMatteryaR2VideoKey(post) {
            if let img = imageURL(for: post), isUsablePosterURL(img) { return img }
            if let yt = r2LongformYouTubePosterURL(for: post) { return yt }
            return nil
        }
        // Non-R2 legacy.
        if let yt = r2LongformYouTubePosterURL(for: post) { return yt }
        if let img = imageURL(for: post), isUsablePosterURL(img) { return img }
        return nil
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
        // Live Frame0 cache (fresh signed from /v1/poster/batch) — lock-safe, any isolation.
        if let cached = Frame0PosterCache.url(for: post.id), isUsablePosterURL(cached) {
            return cached
        }
        // Prefer embedded ladder (1080 → 512 → 256) when still valid.
        if let embedded = embeddedFrame0PosterURL(from: post.mediaURL), isUsablePosterURL(embedded) {
            return embedded
        }
        if let thumb = resolve(post.thumbURL), !isVideoURL(thumb), looksLikeFrame0Poster(thumb),
           isUsablePosterURL(thumb) {
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
    /// - R2: always live-resolve when URL is pub-*.r2.dev (CF 1010) or expired/near-expiry presign.
    /// - Archive / Supabase: existing CDN/auth paths.
    static func playbackConfiguration(for url: URL, postID: String? = nil) async -> MediaPlaybackConfiguration {
        // Never run video CDN resolution on image posters (thumbs / services/img).
        if isImageURL(url) {
            return MediaPlaybackConfiguration(url: url, headers: nil)
        }

        // R2: pub-*.r2.dev is 403/CF1010; expired signed GETs also fail. Fresh-presign via API.
        if looksLikeR2HostedURL(url), let postID, !postID.isEmpty {
            let needsLive =
                isBlockedR2PublicURL(url)
                || !isPresignedObjectURL(url)
                || isPresignExpiredOrNearExpiry(url, slackSeconds: 3600)
            if needsLive {
                if let live = await R2PlaybackResolver.shared.playURL(postID: postID, fallback: nil),
                   isPresignedObjectURL(live),
                   !isBlockedR2PublicURL(live) {
                    return MediaPlaybackConfiguration(url: live, headers: nil)
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

    /// `pub-*.r2.dev` is CF 1010 / 403 for matterya-sparks — never hand to AVPlayer/ImageCache.
    static func isBlockedR2PublicURL(_ url: URL) -> Bool {
        (url.host ?? "").lowercased().contains("r2.dev")
    }

    /// Poster usable for list/player chrome (not expired, not banned public host).
    static func isUsablePosterURL(_ url: URL) -> Bool {
        if isBlockedR2PublicURL(url) { return false }
        if isPresignedObjectURL(url), isPresignExpiredOrNearExpiry(url, slackSeconds: 120) {
            return false
        }
        return true
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
    var resolvedImageURL: URL? {
        guard let url = MediaURLResolver.imageURL(for: self),
              MediaURLResolver.isUsablePosterURL(url)
        else { return nil }
        return url
    }
    /// Never fall through to expired / banned r2.dev thumbs after posterURL rejects them.
    var feedImageURL: URL? {
        let mt = (mediaType ?? "").lowercased()
        // Image posts: prefer the photo URL (even demoted `.mp4` JPEG keys) over Frame0 video posters.
        if mt == "image" || mt == "photo" || mt == "gif" {
            if let img = MediaURLResolver.imageURL(for: self),
               MediaURLResolver.isUsablePosterURL(img) {
                return img
            }
        }
        if let poster = MediaURLResolver.posterURL(for: self) { return poster }
        guard let img = MediaURLResolver.imageURL(for: self),
              MediaURLResolver.isUsablePosterURL(img)
        else { return nil }
        return img
    }
}