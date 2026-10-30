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
        let trimmed = rebrandCompetitorNames(stripInternalMarkers(stripSquareBracketTags(value)))
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

    /// User-facing copy: never show competitor / source-platform names.
    /// `subreddit` → `space`, `reddit` → `masquerade`, TikTok → `matterya`,
    /// `u/name` → `@name`.
    /// Longer tokens first so `subreddit` is not partially rewritten.
    /// Compiled once — image cards hit `clean` many times per SwiftUI body pass.
    private static let rebrandPairs: [(NSRegularExpression, String)] = {
        // Patterns (not literal escape) so word boundaries / slash forms work.
        let pairs: [(String, String)] = [
            ("تيك توك", "matterya"),
            ("تيك\u{200C}توك", "matterya"),
            ("تيك-توك", "matterya"),
            ("تيكتوك", "matterya"),
            ("tik\\s*tok", "matterya"),
            ("subreddits", "spaces"),
            ("subreddit", "space"),
            // Whole word only — never rewrite "credited" etc.
            ("\\breddit\\b", "masquerade"),
            ("\\btiktok\\b", "matterya"),
            // Reddit path shorthand r/funny → space/funny
            ("\\br/", "space/"),
            // Reddit user shorthand u/name → @name (Masquerade handles).
            ("\\bu/", "@"),
        ]
        return pairs.compactMap { pattern, replacement in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                return nil
            }
            return (regex, replacement)
        }
    }()

    static func rebrandCompetitorNames(_ value: String) -> String {
        var out = value
        for (regex, replacement) in rebrandPairs {
            let full = NSRange(out.startIndex..<out.endIndex, in: out)
            guard regex.firstMatch(in: out, options: [], range: full) != nil else { continue }
            out = regex.stringByReplacingMatches(
                in: out,
                options: [],
                range: full,
                withTemplate: replacement
            )
        }
        // Reddit shorthand " sub " (spaces required) → Masquerade " space ".
        out = rebrandStandaloneSub(out)
        return out
    }

    /// Always safe for UI — rebrands even when `clean` would drop the string.
    /// Prefer this over `clean(x) ?? x` so raw "subreddit"/"reddit" never leak.
    static func displayText(_ value: String?) -> String {
        guard let value else { return "" }
        if let cleaned = clean(value) { return cleaned }
        let rebranded = rebrandCompetitorNames(stripInternalMarkers(stripSquareBracketTags(value)))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rebranded
    }

    /// Drop `[pic]`, `[SFW]`, `[CONFESS #N]`, and any other `[...]` tags from Masquerade copy.
    static func stripSquareBracketTags(_ value: String) -> String {
        guard value.contains("[") else { return value }
        var out = value
        if let regex = try? NSRegularExpression(pattern: #"\[[^\]]*\]"#) {
            let full = NSRange(out.startIndex..<out.endIndex, in: out)
            out = regex.stringByReplacingMatches(in: out, options: [], range: full, withTemplate: "")
        }
        // Collapse leftover double spaces from removed tags; keep newlines.
        while out.contains("  ") {
            out = out.replacingOccurrences(of: "  ", with: " ")
        }
        return out
            .replacingOccurrences(of: " .", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Only the bare word with a space on both sides — never touch submit/subtle/subreddit.
    private static func rebrandStandaloneSub(_ value: String) -> String {
        var out = value
        let pairs = [(" SUB ", " SPACE "), (" Sub ", " Space "), (" sub ", " space ")]
        for (from, to) in pairs {
            guard out.contains(from) else { continue }
            out = out.replacingOccurrences(of: from, with: to)
        }
        return out
    }

    /// True when caption/title/body hits the simple 18+ keyword gate (whole words).
    /// Same list as API `ADULT_KEYWORDS` until a real moderation stack ships.
    static func looksNsfw(_ value: String?) -> Bool {
        guard let value, !value.isEmpty else { return false }
        return value.range(
            of: #"\b(?:nsfw|sex|sexy|sexual|porn|porno|pornography|xxx|onlyfans|hentai|erotic|nude|nudes|naked|blowjob|handjob|cumshot|orgasm|masturbate|masturbation|masturbating|gooning|milf|incest)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
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
        if let name = clean(author?.displayName),
           !DemoPersonNames.isPlaceholderDisplayName(name),
           !isCountryLabel(name, countryName: author?.countryName, countryCode: author?.countryCode) {
            return name
        }
        if let handle = clean(author?.username),
           !DemoPersonNames.isPlaceholderDisplayName(handle),
           !isCountryLabel(handle, countryName: author?.countryName, countryCode: author?.countryCode) {
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

    /// True when display text is just the profile's country (legacy seed bug).
    private static func isCountryLabel(_ value: String, countryName: String?, countryCode: String?) -> Bool {
        let low = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let cn = countryName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !cn.isEmpty, low == cn {
            return true
        }
        if let cc = countryCode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !cc.isEmpty, low == cc {
            return true
        }
        return false
    }
}