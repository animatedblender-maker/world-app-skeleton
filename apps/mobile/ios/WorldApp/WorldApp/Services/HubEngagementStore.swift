import Foundation

/// Local likes + comments for Internet Archive hub/spark videos (IDs like `ia_…`).
/// GraphQL has no rows for seed content, so engagement is stored on-device and still feels live.
@MainActor
final class HubEngagementStore {
    static let shared = HubEngagementStore()

    private struct LikeState: Codable {
        var likedByMe: Bool
        var likeCount: Int
    }

    private struct StoredComment: Codable {
        var id: String
        var postID: String
        var parentID: String?
        var authorID: String
        var body: String
        var likeCount: Int
        var likedByMe: Bool
        var createdAt: String
        var updatedAt: String
        var displayName: String?
        var username: String?
        var avatarURL: String?
        var countryName: String?
        var countryCode: String?

        init(from comment: PostComment) {
            id = comment.id
            postID = comment.postID
            parentID = comment.parentID
            authorID = comment.authorID
            body = comment.body
            likeCount = comment.likeCount
            likedByMe = comment.likedByMe
            createdAt = comment.createdAt
            updatedAt = comment.updatedAt
            displayName = comment.author?.displayName
            username = comment.author?.username
            avatarURL = comment.author?.avatarURL
            countryName = comment.author?.countryName
            countryCode = comment.author?.countryCode
        }

        func toModel() -> PostComment {
            PostComment(
                id: id,
                postID: postID,
                parentID: parentID,
                authorID: authorID,
                body: body,
                likeCount: likeCount,
                likedByMe: likedByMe,
                createdAt: createdAt,
                updatedAt: updatedAt,
                author: PostAuthor(
                    userID: authorID,
                    displayName: displayName ?? "You",
                    username: username,
                    avatarURL: avatarURL,
                    countryName: countryName,
                    countryCode: countryCode,
                    lastReadAt: nil
                )
            )
        }
    }

    private struct DiskPayload: Codable {
        var likes: [String: LikeState]
        var comments: [String: [StoredComment]]
    }

    private var likes: [String: LikeState] = [:]
    private var comments: [String: [PostComment]] = [:]
    private let defaultsKey = "hub.engagement.v1"

    private init() {
        load()
    }

    static func isHubContentID(_ id: String) -> Bool {
        usesLocalEngagement(postID: id)
    }

    /// Seed / offline content must never hit GraphQL (server has no row → "Unexpected error").
    static func usesLocalEngagement(postID: String) -> Bool {
        let id = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty { return true }
        let lower = id.lowercased()
        if lower.hasPrefix("ia_")
            || lower.hasPrefix("hub_")
            || lower.hasPrefix("archive_")
            || lower.hasPrefix("post_")
            || lower.hasPrefix("post_synth_")
            || lower.hasPrefix("demo_")
            || lower.hasPrefix("hub_cmt_")
            || lower.hasPrefix("spark_")
            || lower.contains("internet_archive")
            || lower.contains("archive.org") {
            return true
        }
        // Real Matterya posts use UUIDs.
        if UUID(uuidString: id) != nil { return false }
        // Any other non-UUID id is treated as local seed content.
        return true
    }

    static func usesLocalEngagement(commentID: String) -> Bool {
        let lower = commentID.lowercased()
        if lower.hasPrefix("hub_cmt_") || lower.hasPrefix("demo_") || lower.hasPrefix("local_cmt_") {
            return true
        }
        // UUID comments may be real server rows — only force local when clearly seed-prefixed.
        return UUID(uuidString: commentID) == nil
    }

    // MARK: - Likes

    func applyLikeState(to post: CountryPost) -> CountryPost {
        guard Self.isHubContentID(post.id) else { return post }
        guard let state = likes[post.id] else { return post }
        return post.withEngagement(
            likedByMe: state.likedByMe,
            likeCount: state.likeCount,
            commentCount: post.commentCount
        )
    }

    func like(_ postID: String, baseLikeCount: Int) {
        let current = likes[postID]
        let wasLiked = current?.likedByMe ?? false
        let count = current?.likeCount ?? baseLikeCount
        likes[postID] = LikeState(
            likedByMe: true,
            likeCount: wasLiked ? count : count + 1
        )
        persist()
    }

    func unlike(_ postID: String, baseLikeCount: Int) {
        let current = likes[postID]
        let wasLiked = current?.likedByMe ?? false
        let count = current?.likeCount ?? baseLikeCount
        likes[postID] = LikeState(
            likedByMe: false,
            likeCount: wasLiked ? max(0, count - 1) : count
        )
        persist()
    }

    // MARK: - Comments

    func listComments(_ postID: String, limit: Int) -> [PostComment] {
        Array((comments[postID] ?? []).prefix(max(limit, 0)))
    }

    func commentCount(_ postID: String, seed: Int = 0) -> Int {
        max(seed, comments[postID]?.count ?? 0)
    }

    func addComment(
        postID: String,
        body: String,
        parentID: String?,
        author: PostAuthor?
    ) -> PostComment {
        let now = ISO8601DateFormatter().string(from: Date())
        let userID = author?.userID ?? AuthService.shared.currentUser?.id ?? "local_user"
        let resolvedAuthor = author ?? PostAuthor(
            userID: userID,
            displayName: "You",
            username: "you",
            avatarURL: nil,
            countryName: nil,
            countryCode: nil,
            lastReadAt: nil
        )
        let comment = PostComment(
            id: "hub_cmt_\(UUID().uuidString)",
            postID: postID,
            parentID: parentID,
            authorID: resolvedAuthor.userID,
            body: body.trimmingCharacters(in: .whitespacesAndNewlines),
            likeCount: 0,
            likedByMe: false,
            createdAt: now,
            updatedAt: now,
            author: resolvedAuthor
        )
        comments[postID, default: []].append(comment)
        persist()
        return comment
    }

    func likeComment(_ commentID: String) -> PostComment? {
        updateComment(commentID) { c in
            PostComment(
                id: c.id,
                postID: c.postID,
                parentID: c.parentID,
                authorID: c.authorID,
                body: c.body,
                likeCount: c.likedByMe ? c.likeCount : c.likeCount + 1,
                likedByMe: true,
                createdAt: c.createdAt,
                updatedAt: c.updatedAt,
                author: c.author
            )
        }
    }

    func unlikeComment(_ commentID: String) -> PostComment? {
        updateComment(commentID) { c in
            PostComment(
                id: c.id,
                postID: c.postID,
                parentID: c.parentID,
                authorID: c.authorID,
                body: c.body,
                likeCount: c.likedByMe ? max(0, c.likeCount - 1) : c.likeCount,
                likedByMe: false,
                createdAt: c.createdAt,
                updatedAt: c.updatedAt,
                author: c.author
            )
        }
    }

    private func updateComment(_ commentID: String, transform: (PostComment) -> PostComment) -> PostComment? {
        for postID in comments.keys {
            guard var list = comments[postID],
                  let index = list.firstIndex(where: { $0.id == commentID }) else { continue }
            let updated = transform(list[index])
            list[index] = updated
            comments[postID] = list
            persist()
            return updated
        }
        return nil
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let payload = try? JSONDecoder().decode(DiskPayload.self, from: data)
        else { return }
        likes = payload.likes
        comments = payload.comments.mapValues { $0.map { $0.toModel() } }
    }

    private func persist() {
        let stored = comments.mapValues { $0.map(StoredComment.init(from:)) }
        let payload = DiskPayload(likes: likes, comments: stored)
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

extension CountryPost {
    func withEngagement(likedByMe: Bool, likeCount: Int, commentCount: Int) -> CountryPost {
        CountryPost(
            id: id,
            title: title,
            body: body,
            mediaType: mediaType,
            mediaURL: mediaURL,
            thumbURL: thumbURL,
            mediaCaption: mediaCaption,
            sharedPostID: sharedPostID,
            sharedPost: sharedPost,
            visibility: visibility,
            likeCount: likeCount,
            commentCount: commentCount,
            viewCount: viewCount,
            likedByMe: likedByMe,
            savedByMe: savedByMe,
            createdAt: createdAt,
            updatedAt: updatedAt,
            authorID: authorID,
            countryName: countryName,
            countryCode: countryCode,
            cityName: cityName,
            author: author,
            linkURL: linkURL,
            linkTitle: linkTitle,
            externalRefType: externalRefType,
            externalRefID: externalRefID
        )
    }
}
