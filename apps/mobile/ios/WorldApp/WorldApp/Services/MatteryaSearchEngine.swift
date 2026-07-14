import Foundation

enum MatteryaSearchEngine {
    static let countryLimit = 12
    static let peopleLimit = 20
    static let contentLimit = 40

    static func normalizeName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: #"[^a-z0-9 ]"#, with: "", options: .regularExpression)
    }

    static func searchCountries(_ countries: [Country], query: String, limit: Int = countryLimit) -> [Country] {
        let normalized = normalizeName(query)
        guard !normalized.isEmpty else { return [] }

        let ranked = countries.compactMap { country -> (Country, Double)? in
            let score = countryScore(country, normalized: normalized, rawQuery: query)
            guard score > 0 else { return nil }
            return (country, score)
        }
        .sorted { lhs, rhs in
            if lhs.1 == rhs.1 { return lhs.0.name < rhs.0.name }
            return lhs.1 > rhs.1
        }

        return ranked.prefix(limit).map(\.0)
    }

    static func rankProfiles(_ profiles: [Profile], query: String, limit: Int = peopleLimit) -> [Profile] {
        let normalized = normalizeName(query)
        guard !normalized.isEmpty else { return Array(profiles.prefix(limit)) }

        let ranked = profiles.compactMap { profile -> (Profile, Double)? in
            let score = profileScore(profile, normalized: normalized, rawQuery: query)
            guard score > 0 else { return nil }
            return (profile, score)
        }
        .sorted { lhs, rhs in
            if lhs.1 == rhs.1 {
                return (lhs.0.displayName ?? lhs.0.username ?? "") < (rhs.0.displayName ?? rhs.0.username ?? "")
            }
            return lhs.1 > rhs.1
        }

        return ranked.prefix(limit).map(\.0)
    }

    static func rankContent(_ posts: [CountryPost], query: String, limit: Int = contentLimit) -> [CountryPost] {
        let normalized = normalizeName(query)
        guard !normalized.isEmpty else { return Array(posts.prefix(limit)) }

        let terms = normalized.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !terms.isEmpty else { return Array(posts.prefix(limit)) }

        let ranked = posts.compactMap { post -> (CountryPost, Double)? in
            guard !post.isStory else { return nil }
            let score = contentScore(post, normalized: normalized, terms: terms, rawQuery: query)
            guard score > 0 else { return nil }
            return (post, score)
        }
        .sorted { lhs, rhs in
            if lhs.1 == rhs.1 { return lhs.0.createdAt > rhs.0.createdAt }
            return lhs.1 > rhs.1
        }

        return ranked.prefix(limit).map(\.0)
    }

    private static func countryScore(_ country: Country, normalized: String, rawQuery: String) -> Double {
        let name = normalizeName(country.name)
        let iso = country.iso.lowercased()
        let raw = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if name == normalized || iso == raw || iso == normalized { return 120 }
        if name.hasPrefix(normalized) || iso.hasPrefix(raw) { return 95 }
        if normalized.count >= 3, name.contains(normalized) { return 72 }
        if raw.count == 2, iso == raw { return 110 }
        if iso.contains(raw), raw.count >= 2 { return 58 }
        return 0
    }

    private static func profileScore(_ profile: Profile, normalized: String, rawQuery: String) -> Double {
        let username = normalizeName(profile.username ?? "")
        let displayName = normalizeName(profile.displayName ?? "")
        let country = normalizeName(profile.countryName ?? "")
        let raw = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var score = 0.0
        if username == normalized || displayName == normalized { score = max(score, 120) }
        if username.hasPrefix(normalized) || displayName.hasPrefix(normalized) { score = max(score, 92) }
        if username.contains(normalized) || displayName.contains(normalized) { score = max(score, 68) }
        if !country.isEmpty, country.contains(normalized) { score = max(score, 42) }
        if raw.hasPrefix("@"), username.contains(normalizeName(String(raw.dropFirst()))) {
            score = max(score, 100)
        }

        let followers = Double(profile.followersCount ?? 0)
        if followers > 0 {
            score += min(8, log10(followers + 1))
        }
        return score
    }

    private static func contentScore(
        _ post: CountryPost,
        normalized: String,
        terms: [String],
        rawQuery: String
    ) -> Double {
        let title = normalizeName(post.displayTitle ?? "")
        let body = normalizeName(post.displayBody)
        let caption = normalizeName(post.displayCaption ?? "")
        let author = normalizeName(post.authorDisplayName)
        let username = normalizeName(post.author?.username ?? "")
        let country = normalizeName(post.countryName ?? "")
        let city = normalizeName(post.cityName ?? "")
        let linkTitle = normalizeName(post.linkTitle ?? "")

        let haystacks: [(String, Double)] = [
            (title, 5.0),
            (body, 2.0),
            (author, 3.0),
            (username, 3.0),
            (country, 2.0),
            (city, 1.5),
            (caption, 1.5),
            (linkTitle, 1.2),
        ]

        var score = 0.0
        for (haystack, weight) in haystacks where !haystack.isEmpty {
            if haystack == normalized { score += weight * 14 }
            else if haystack.hasPrefix(normalized) { score += weight * 10 }
            else if haystack.contains(normalized) { score += weight * 6 }

            let matchedTerms = terms.filter { haystack.contains($0) }.count
            if matchedTerms > 0 {
                score += weight * Double(matchedTerms) * 2.4
            }
        }

        if score <= 0 { return 0 }

        if post.hasVideo || post.hasImage { score += 1.2 }
        if post.isReel { score += 0.6 }

        let engagement = log(Double(post.likeCount + 1))
            + log(Double(post.commentCount + 1)) * 1.2
            + log(Double(max(post.viewCount, 0) + 1)) * 0.5
        score += min(6, engagement)

        if let created = post.createdDate {
            let ageHours = max(0, Date().timeIntervalSince(created) / 3600)
            let recencyBoost = exp(-ageHours / (24 * 7)) * 4
            score += recencyBoost
        }

        if rawQuery.hasPrefix("#"), body.contains(normalizeName(String(rawQuery.dropFirst()))) {
            score += 3
        }

        return score
    }
}