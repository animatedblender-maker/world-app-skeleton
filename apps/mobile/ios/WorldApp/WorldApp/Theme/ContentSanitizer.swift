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
        let trimmed = stripInternalMarkers(value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !looksLikeId(trimmed) else { return nil }
        return trimmed
    }

    /// Removes client-only body markers (story / hub channel / spark) so cards never show raw tokens.
    static func stripInternalMarkers(_ value: String) -> String {
        value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                if line.isEmpty { return false }
                if line.hasPrefix("__story__|") { return false }
                if line.hasPrefix("__hub_channel__") { return false }
                if line.hasPrefix("__spark__|") { return false }
                if line.hasPrefix("__reel__|") { return false }
                return true
            }
            .joined(separator: "\n")
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