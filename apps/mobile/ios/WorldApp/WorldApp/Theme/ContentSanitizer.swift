import Foundation

enum ContentSanitizer {
    static func looksLikeId(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }

        if trimmed.range(
            of: #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return true
        }

        if trimmed.count == 32, trimmed.allSatisfy(\.isHexDigit) {
            return true
        }

        if trimmed.range(of: #"^\d{8,}$"#, options: .regularExpression) != nil {
            return true
        }

        if trimmed.hasPrefix("user_"), trimmed.count > 12 {
            return true
        }

        if trimmed.contains("__call__") {
            return true
        }

        if trimmed.hasPrefix("post_") || trimmed.hasPrefix("conv_") || trimmed.hasPrefix("msg_") {
            return true
        }

        let segments = trimmed.split(separator: "/")
        if segments.count > 1, segments.contains(where: { looksLikeId(String($0)) }) {
            return true
        }

        return false
    }

    static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = rebrandCompetitorNames(stripInternalMarkers(value))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !looksLikeId(trimmed) else { return nil }
        // Final gate: pure control / stamp leftovers never reach UI.
        if isControlFieldLine(trimmed) { return nil }
        if trimmed.range(of: #"\bsid\s*="#, options: .regularExpression) != nil,
           trimmed.count < 200,
           trimmed.contains("|") || trimmed.contains("aid=") {
            return nil
        }
        return trimmed
    }

    /// User-facing copy never says "TikTok" — hashtags, captions, comments, bios, etc.
    /// `#tiktok` / `TikTok` / `TIKTOK` → `matterya` / `#matterya`.
    static func rebrandCompetitorNames(_ value: String) -> String {
        guard value.range(of: "tiktok", options: .caseInsensitive) != nil else { return value }
        guard let regex = try? NSRegularExpression(pattern: "tiktok", options: .caseInsensitive) else {
            return value
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.stringByReplacingMatches(
            in: value,
            options: [],
            range: range,
            withTemplate: "matterya"
        )
    }

    /// Removes client-only body markers (story / hub channel / spark) so cards never show raw tokens.
    /// Keeps real caption text that sits on the **same line** after a marker, e.g.
    /// `__spark__|My favourite English teacher` → `My favourite English teacher`.
    static func stripInternalMarkers(_ value: String) -> String {
        let markerPrefixes = [
            "__story__|",
            "__hub_channel__|",
            "__hub_channel__",
            "__hub_origin__|",
            "__hub_origin__",
            "__spark_share__|",
            "__spark__|",
            "__reel__|",
        ]
        // Seeder fluff that used to be written on spark *shares* — never show as caption.
        let fakeShareCaptions: Set<String> = [
            "this one 🔥",
            "need this on loop",
            "sending this to everyone",
            "no notes",
            "how is this real",
            "ok wait",
            "the audio though",
            "I'm obsessed",
            "more of this please",
            "mood",
            "saw this and had to share",
            "too good",
            "watch till the end",
            "😂😂😂",
            "//",
        ]

        let kept = value
            .components(separatedBy: .newlines)
            .compactMap { raw -> String? in
                var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty { return nil }

                for prefix in markerPrefixes {
                    guard line.hasPrefix(prefix) else { continue }
                    line = String(line.dropFirst(prefix.count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    // Share / hub-origin header is pure control: `sid=…|aid=…|an=…`
                    // (was leaking into feed/profile description as "sid blabla…").
                    if isControlFieldLine(line) || line.isEmpty {
                        return nil
                    }
                    break
                }

                if line.isEmpty { return nil }
                // Drop leftover pure control tokens / key=value stamp lines.
                if line.hasPrefix("__"), line.contains("|") { return nil }
                if isControlFieldLine(line) { return nil }
                // Mid-line stamp (e.g. "Watch this __hub_origin__|sid=…").
                if line.range(of: #"__hub_origin__\|"#, options: .regularExpression) != nil
                    || line.range(of: #"__spark_share__\|"#, options: .regularExpression) != nil {
                    return nil
                }
                if fakeShareCaptions.contains(line) { return nil }
                return line
            }

        return kept.joined(separator: "\n")
    }

    /// True for internal stamp payloads like `sid=uuid|aid=…|an=Name` (not user captions).
    static func isControlFieldLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        // Classic hub/spark share stamp (with optional spaces).
        if trimmed.range(of: #"^sid\s*="#, options: .regularExpression) != nil { return true }
        if trimmed.range(of: #"^(aid|an|au)\s*="#, options: .regularExpression) != nil { return true }
        // Line is mostly `key=value|key=value` control pairs (even if a stray word sneaks in).
        let parts = trimmed.split(separator: "|").map(String.init)
        guard !parts.isEmpty else { return false }
        let controlKeys: Set<String> = ["sid", "aid", "an", "au", "cid", "oid", "uid"]
        var controlCount = 0
        var otherCount = 0
        for part in parts {
            let s = part.trimmingCharacters(in: .whitespaces)
            guard let eq = s.firstIndex(of: "=") else {
                otherCount += 1
                continue
            }
            let key = String(s[..<eq]).trimmingCharacters(in: .whitespaces).lowercased()
            if controlKeys.contains(key) { controlCount += 1 }
            else { otherCount += 1 }
        }
        // Pure control stamp, or control-dominant garbage (e.g. sid=…|aid=…|junk).
        if controlCount >= 1, otherCount == 0 { return true }
        if controlCount >= 2, otherCount <= 1 { return true }
        return false
    }

    static func stripStoryMarker(_ value: String) -> String {
        stripInternalMarkers(value)
    }

    static func displayName(
        displayName: String?,
        username: String?,
        fallback: String = "Member"
    ) -> String {
        if let name = clean(displayName), !DemoPersonNames.isPlaceholderDisplayName(name) {
            return name
        }
        if let handle = clean(username), !DemoPersonNames.isPlaceholderDisplayName(handle) {
            return handle
        }
        return fallback
    }

    /// Prefer a real-looking name for demo `user_*` authors even when cached as "User 000123".
    static func displayName(
        forAuthor author: PostAuthor?,
        authorID: String,
        fallback: String = "Member"
    ) -> String {
        if let name = clean(author?.displayName), !DemoPersonNames.isPlaceholderDisplayName(name) {
            return name
        }
        if let handle = clean(author?.username), !DemoPersonNames.isPlaceholderDisplayName(handle) {
            return handle
        }
        if authorID.hasPrefix("user_") {
            return DemoPersonNames.fullName(
                forAuthorID: authorID,
                countryCode: author?.countryCode
            )
        }
        return fallback
    }
}