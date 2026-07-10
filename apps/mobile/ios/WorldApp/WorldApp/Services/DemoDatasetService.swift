import Foundation

actor DemoDatasetService {
    static let shared = DemoDatasetService()

    private var posts: [CountryPost] = []
    private var postsByCountry: [String: [CountryPost]] = [:]
    private var postsByAuthor: [String: [CountryPost]] = [:]
    private var loaded = false

    func listByCountry(_ code: String, limit: Int) async -> [CountryPost] {
        await ensureLoaded()
        let key = code.uppercased()
        let slice = postsByCountry[key] ?? []
        return Array(slice.prefix(limit))
    }

    func listForAuthor(_ authorID: String, limit: Int) async -> [CountryPost] {
        await ensureLoaded()
        let slice = postsByAuthor[authorID] ?? []
        return Array(slice.prefix(limit))
    }

    func searchPosts(_ query: String, limit: Int) async -> [CountryPost] {
        await ensureLoaded()
        let needle = query.lowercased()
        return posts
            .filter {
                $0.body.lowercased().contains(needle)
                    || ($0.title?.lowercased().contains(needle) ?? false)
                    || ($0.author?.displayName?.lowercased().contains(needle) ?? false)
            }
            .prefix(limit)
            .map { $0 }
    }

    func getPostByID(_ id: String) async -> CountryPost? {
        await ensureLoaded()
        return posts.first { $0.id == id }
    }

    func isDemoPostID(_ id: String) async -> Bool {
        await ensureLoaded()
        return posts.contains { $0.id == id }
    }

    func sampleGlobalPosts(limit: Int) async -> [CountryPost] {
        await ensureLoaded()
        return Array(posts.shuffled().prefix(limit))
    }

    private var commentsByPost: [String: [PostComment]] = [:]

    func listComments(_ postID: String, limit: Int) async -> [PostComment] {
        Array((commentsByPost[postID] ?? []).prefix(limit))
    }

    func addComment(_ postID: String, body: String, parentID: String?) async -> PostComment {
        let authorID = "demo_local"
        let now = ISO8601DateFormatter().string(from: Date())
        let comment = PostComment(
            id: UUID().uuidString,
            postID: postID,
            parentID: parentID,
            authorID: authorID,
            body: body,
            likeCount: 0,
            likedByMe: false,
            createdAt: now,
            updatedAt: now,
            author: PostAuthor(
                userID: authorID,
                displayName: "You",
                username: "you",
                avatarURL: nil,
                countryName: nil,
                countryCode: nil,
                lastReadAt: nil
            )
        )
        commentsByPost[postID, default: []].append(comment)
        return comment
    }

    func likeComment(_ commentID: String) async -> PostComment? {
        updateComment(commentID) { comment in
            PostComment(
                id: comment.id,
                postID: comment.postID,
                parentID: comment.parentID,
                authorID: comment.authorID,
                body: comment.body,
                likeCount: comment.likedByMe ? comment.likeCount : comment.likeCount + 1,
                likedByMe: true,
                createdAt: comment.createdAt,
                updatedAt: comment.updatedAt,
                author: comment.author
            )
        }
    }

    func unlikeComment(_ commentID: String) async -> PostComment? {
        updateComment(commentID) { comment in
            PostComment(
                id: comment.id,
                postID: comment.postID,
                parentID: comment.parentID,
                authorID: comment.authorID,
                body: comment.body,
                likeCount: comment.likedByMe ? max(0, comment.likeCount - 1) : comment.likeCount,
                likedByMe: false,
                createdAt: comment.createdAt,
                updatedAt: comment.updatedAt,
                author: comment.author
            )
        }
    }

    private func updateComment(_ commentID: String, transform: (PostComment) -> PostComment) -> PostComment? {
        for postID in commentsByPost.keys {
            guard var comments = commentsByPost[postID],
                  let index = comments.firstIndex(where: { $0.id == commentID }) else { continue }
            let updated = transform(comments[index])
            comments[index] = updated
            commentsByPost[postID] = comments
            return updated
        }
        return nil
    }

    private func ensureLoaded() async {
        guard !loaded else { return }
        loaded = true

        guard let url = URL(string: "\(AppConfig.demoDatasetBaseURL)/demo_social_dataset_30k/posts.jsonl") else {
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let text = String(data: data, encoding: .utf8) ?? ""
            let rows = parseJSONL(text)
            posts = rows.map(mapDemoPost).sorted { lhs, rhs in
                (lhs.createdDate ?? .distantPast) > (rhs.createdDate ?? .distantPast)
            }

            for post in posts {
                let code = post.countryCode?.uppercased() ?? "XX"
                postsByCountry[code, default: []].append(post)
                postsByAuthor[post.authorID, default: []].append(post)
            }

            for key in postsByCountry.keys {
                postsByCountry[key]?.sort {
                    ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast)
                }
            }
        } catch {
            posts = []
        }
    }

    private func parseJSONL(_ text: String) -> [[String: Any]] {
        text
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> [String: Any]? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      let data = trimmed.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return nil }
                return json
            }
    }

    private func mapDemoPost(_ row: [String: Any]) -> CountryPost {
        let media = row["media"] as? [String: Any]
        let authorID = normalizeAuthorID(row["author_id"] as? String ?? "user_unknown")
        let countryCode = (row["country_code"] as? String ?? "XX").uppercased()
        let body = normalizeBody(row["body"] as? String ?? "", countryCode: countryCode)
        let createdAt = row["created_at"] as? String ?? ISO8601DateFormatter().string(from: Date())
        let seed = hashSeed(row["id"] as? String ?? authorID)

        return CountryPost(
            id: row["id"] as? String ?? UUID().uuidString,
            title: row["title"] as? String,
            body: body,
            mediaType: media?["type"] as? String,
            mediaURL: media?["url"] as? String,
            thumbURL: media?["thumb_url"] as? String,
            mediaCaption: nil,
            sharedPostID: nil,
            visibility: .public,
            likeCount: Int(seed % 420) + 3,
            commentCount: Int(seed % 80),
            viewCount: Int(seed % 5000) + 50,
            likedByMe: false,
            savedByMe: false,
            createdAt: createdAt,
            updatedAt: createdAt,
            authorID: authorID,
            countryName: row["country_name"] as? String,
            countryCode: countryCode,
            cityName: nil,
            author: PostAuthor(
                userID: authorID,
                displayName: "User \(authorID.suffix(6))",
                username: "user\(authorID.suffix(6))",
                avatarURL: "https://api.dicebear.com/7.x/identicon/svg?seed=\(authorID)",
                countryName: row["country_name"] as? String,
                countryCode: countryCode,
                lastReadAt: nil
            )
        )
    }

    private func normalizeAuthorID(_ raw: String) -> String {
        guard raw.hasPrefix("user_"), let number = Int(raw.replacingOccurrences(of: "user_", with: "")) else {
            return raw
        }
        return String(format: "user_%06d", number)
    }

    private func normalizeBody(_ body: String, countryCode: String) -> String {
        let prefix = "[\(countryCode)] "
        if body.hasPrefix(prefix) {
            return String(body.dropFirst(prefix.count))
        }
        return body
    }

    private func hashSeed(_ value: String) -> UInt64 {
        var hash: UInt64 = 2166136261
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 16777619
        }
        return hash
    }
}