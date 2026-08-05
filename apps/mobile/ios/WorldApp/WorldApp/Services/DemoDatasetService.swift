import Foundation

actor DemoDatasetService {
    static let shared = DemoDatasetService()

    private var posts: [CountryPost] = []
    private var postsByCountry: [String: [CountryPost]] = [:]
    private var postsByAuthor: [String: [CountryPost]] = [:]
    private var commentsByPost: [String: [PostComment]] = [:]
    /// author_id → country from their posts (for comment avatars/location).
    private var authorCountry: [String: (name: String?, code: String?)] = [:]
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
        return MatteryaSearchEngine.rankContent(posts, query: query, limit: limit)
    }

    func getPostByID(_ id: String) async -> CountryPost? {
        await ensureLoaded()
        return posts.first { $0.id == id }
    }

    func isDemoPostID(_ id: String) async -> Bool {
        await ensureLoaded()
        return posts.contains { $0.id == id }
    }

    /// Stable order (not reshuffled every call) so feed identity stays consistent
    /// and LazyVStack does not rebuild on every background refresh.
    func sampleGlobalPosts(limit: Int) async -> [CountryPost] {
        await ensureLoaded()
        return Array(posts.prefix(limit))
    }

    /// Seeded Reddit-derived comments for a demo post (real thread bodies + stable names).
    func listComments(_ postID: String, limit: Int) async -> [PostComment] {
        await ensureLoaded()
        return Array((commentsByPost[postID] ?? []).prefix(limit))
    }

    /// Actual number of seeded comments for a demo post (not a random hash).
    func seededCommentCount(for postID: String) async -> Int {
        await ensureLoaded()
        return commentsByPost[postID]?.count ?? 0
    }

    func addComment(_ postID: String, body: String, parentID: String?) async -> PostComment {
        await ensureLoaded()
        let authorID = "demo_local"
        let now = ISO8601DateFormatter().string(from: Date())
        let comment = PostComment(
            id: "cmt_local_\(UUID().uuidString)",
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
        // Keep post.commentCount in sync for in-memory feed rows.
        if let index = posts.firstIndex(where: { $0.id == postID }) {
            let p = posts[index]
            posts[index] = p.withEngagement(
                likedByMe: p.likedByMe,
                likeCount: p.likeCount,
                commentCount: (commentsByPost[postID] ?? []).count
            )
        }
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

        // Prefer the app-bundled seed (instant, offline). Remote is optional and capped.
        // File I/O + JSONL parse run off the actor so first callers don't serialize on CPU.
        let seedResult: (posts: String, comments: String)? = await Task.detached(priority: .userInitiated) {
            Self.loadBundledSeedTextsSync()
        }.value

        let postsText: String
        let commentsText: String
        if let seedResult {
            postsText = seedResult.posts
            commentsText = seedResult.comments
            #if DEBUG
            print("[DemoDataset] loading bundled demo_social_seed")
            #endif
        } else if AppConfig.demoDatasetAllowRemoteDownload,
                  let postsURL = URL(string: "\(AppConfig.demoDatasetBaseURL)/demo_social_dataset_30k/posts.jsonl"),
                  let commentsURL = URL(string: "\(AppConfig.demoDatasetBaseURL)/demo_social_dataset_30k/comments.jsonl") {
            do {
                async let postsDataTask = URLSession.shared.data(from: postsURL)
                async let commentsDataTask = URLSession.shared.data(from: commentsURL)
                let (postsData, _) = try await postsDataTask
                let (commentsData, _) = try await commentsDataTask
                postsText = String(data: postsData, encoding: .utf8) ?? ""
                commentsText = String(data: commentsData, encoding: .utf8) ?? ""
            } catch {
                #if DEBUG
                print("[DemoDataset] remote load failed: \(error.localizedDescription)")
                #endif
                posts = []
                commentsByPost = [:]
                return
            }
        } else {
            #if DEBUG
            print("[DemoDataset] no bundled seed and remote disabled — feed will have no demo posts")
            #endif
            posts = []
            commentsByPost = [:]
            return
        }

        // Parse on the actor — seed is small (~120 posts); file I/O already ran off-actor.
        let maxPosts = max(24, AppConfig.demoDatasetMaxPosts)
        let parsed = Self.parseSeed(postsText: postsText, commentsText: commentsText, maxPosts: maxPosts)
        posts = parsed.posts
        postsByCountry = parsed.postsByCountry
        postsByAuthor = parsed.postsByAuthor
        commentsByPost = parsed.commentsByPost
        authorCountry = parsed.authorCountry

        #if DEBUG
        let withComments = commentsByPost.values.filter { !$0.isEmpty }.count
        let totalComments = commentsByPost.values.reduce(0) { $0 + $1.count }
        let maxThread = commentsByPost.values.map(\.count).max() ?? 0
        print("[DemoDataset] rootPosts=\(posts.count) threads=\(withComments) comments=\(totalComments) maxThread=\(maxThread)")
        #endif
    }

    /// Prefer large monorepo corpus (dev), then app-bundled seed.
    nonisolated private static func loadBundledSeedTextsSync() -> (posts: String, comments: String)? {
        let candidates: [(posts: URL, comments: URL)] = {
            var list: [(URL, URL)] = []
            // Full Reddit-derived corpus on the Matterya SSD monorepo (thousands of posts).
            let monoRoots = [
                "/Volumes/MatteryaSSD/Development/Projects/World_App/world-app-skeleton/demo_social_dataset_30k",
                "/Users/animated/Development/world-app-skeleton/demo_social_dataset_30k",
            ]
            for root in monoRoots {
                let p = URL(fileURLWithPath: root).appendingPathComponent("posts.jsonl")
                let c = URL(fileURLWithPath: root).appendingPathComponent("comments.jsonl")
                if FileManager.default.fileExists(atPath: p.path),
                   FileManager.default.fileExists(atPath: c.path) {
                    list.append((p, c))
                }
            }
            if let bp = Bundle.main.url(forResource: "posts", withExtension: "jsonl", subdirectory: "demo_social_seed")
                ?? Bundle.main.url(forResource: "posts", withExtension: "jsonl"),
               let bc = Bundle.main.url(forResource: "comments", withExtension: "jsonl", subdirectory: "demo_social_seed")
                ?? Bundle.main.url(forResource: "comments", withExtension: "jsonl") {
                list.append((bp, bc))
            }
            return list
        }()

        // Prefer the largest posts file (full corpus over tiny bundle).
        let ranked = candidates.compactMap { pair -> (URL, URL, Int)? in
            guard let size = (try? FileManager.default.attributesOfItem(atPath: pair.posts.path)[.size] as? NSNumber)?.intValue,
                  size > 100
            else { return nil }
            return (pair.posts, pair.comments, size)
        }
        .sorted { $0.2 > $1.2 }

        for (postsURL, commentsURL, _) in ranked {
            guard let postsData = try? Data(contentsOf: postsURL),
                  let commentsData = try? Data(contentsOf: commentsURL),
                  let postsText = String(data: postsData, encoding: .utf8),
                  let commentsText = String(data: commentsData, encoding: .utf8),
                  !postsText.isEmpty
            else { continue }
            #if DEBUG
            print("[DemoDataset] seed from \(postsURL.path) bytes=\(postsData.count)")
            #endif
            return (postsText, commentsText)
        }
        return nil
    }

    private struct ParsedSeed {
        var posts: [CountryPost]
        var postsByCountry: [String: [CountryPost]]
        var postsByAuthor: [String: [CountryPost]]
        var commentsByPost: [String: [PostComment]]
        var authorCountry: [String: (name: String?, code: String?)]
    }

    /// Nonisolated so heavy JSONL parse can run on a detached task.
    nonisolated private static func parseSeed(postsText: String, commentsText: String, maxPosts: Int) -> ParsedSeed {
        // Load a wide window of raw rows so conversation expansion can follow turn chains
        // that live outside the final root-post cap.
        var postRows = parseJSONL(postsText)
        let expandWindow = min(postRows.count, max(maxPosts * 4, maxPosts))
        if postRows.count > expandWindow {
            postRows = Array(postRows.prefix(expandWindow))
        }

        var authorCountry: [String: (name: String?, code: String?)] = [:]
        for row in postRows {
            let authorID = normalizeAuthorIDStatic(row["author_id"] as? String ?? "user_unknown")
            let code = (row["country_code"] as? String)?.uppercased()
            let name = row["country_name"] as? String
            if authorCountry[authorID] == nil {
                authorCountry[authorID] = (name, code)
            }
        }

        let keepIDs = Set(postRows.compactMap { $0["id"] as? String })
        var rawCommentsByPost: [String: [PostComment]] = [:]
        let commentRows = parseJSONL(commentsText)
        for row in commentRows {
            guard let comment = mapDemoCommentStatic(row, authorCountry: authorCountry) else { continue }
            guard keepIDs.contains(comment.postID) else { continue }
            rawCommentsByPost[comment.postID, default: []].append(comment)
        }
        for key in rawCommentsByPost.keys {
            rawCommentsByPost[key]?.sort { $0.createdAt < $1.createdAt }
        }

        let allMappedPosts = postRows.map { row in
            let id = row["id"] as? String ?? UUID().uuidString
            return mapDemoPostStatic(row, commentCount: (rawCommentsByPost[id] ?? []).count)
        }

        // Body → original speaker (so the same Reddit turn always keeps one Matterya person).
        var utteranceAuthorByBody: [String: (id: String, author: PostAuthor?)] = [:]
        for post in allMappedPosts {
            let key = normalizeThreadBody(post.body)
            guard !key.isEmpty, utteranceAuthorByBody[key] == nil else { continue }
            utteranceAuthorByBody[key] = (post.authorID, post.author)
        }

        // Seed rule is "turn0 = post, turn1+ = comments", but turns were also exported as
        // standalone posts. Rebuild full trees under conversation roots and drop reply-posts
        // from the feed so Home is not a sea of duplicate mid-thread messages.
        let rebuilt = rebuildConversationThreads(
            allPosts: allMappedPosts,
            rawCommentsByPost: rawCommentsByPost,
            utteranceAuthorByBody: utteranceAuthorByBody,
            maxRootPosts: maxPosts
        )

        var postsByCountry: [String: [CountryPost]] = [:]
        var postsByAuthor: [String: [CountryPost]] = [:]
        for post in rebuilt.posts {
            let code = post.countryCode?.uppercased() ?? "XX"
            postsByCountry[code, default: []].append(post)
            postsByAuthor[post.authorID, default: []].append(post)
        }
        for key in postsByCountry.keys {
            postsByCountry[key]?.sort {
                ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast)
            }
        }

        return ParsedSeed(
            posts: rebuilt.posts,
            postsByCountry: postsByCountry,
            postsByAuthor: postsByAuthor,
            commentsByPost: rebuilt.commentsByPost,
            authorCountry: authorCountry
        )
    }

    /// Collapse “reply-as-post” rows into full comment trees under conversation roots.
    /// One Reddit fake user ⇒ one Matterya `author_id` + name (see `DemoPersonNames`).
    nonisolated private static func rebuildConversationThreads(
        allPosts: [CountryPost],
        rawCommentsByPost: [String: [PostComment]],
        utteranceAuthorByBody: [String: (id: String, author: PostAuthor?)],
        maxRootPosts: Int
    ) -> (posts: [CountryPost], commentsByPost: [String: [PostComment]]) {
        // body → earliest post id (stable for matching comment bodies back to turns)
        var bodyToPostID: [String: String] = [:]
        var postByID: [String: CountryPost] = [:]
        for post in allPosts.sorted(by: { $0.id < $1.id }) {
            postByID[post.id] = post
            let key = normalizeThreadBody(post.body)
            if !key.isEmpty, bodyToPostID[key] == nil {
                bodyToPostID[key] = post.id
            }
        }

        // Posts that appear as a comment body on another post are mid-thread turns, not roots.
        var replyPostIDs = Set<String>()
        for comments in rawCommentsByPost.values {
            for comment in comments {
                let key = normalizeThreadBody(comment.body)
                if let linkedID = bodyToPostID[key] {
                    replyPostIDs.insert(linkedID)
                }
            }
        }

        let rootCandidates = allPosts
            .filter { !replyPostIDs.contains($0.id) }
            .sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
        let roots = Array(rootCandidates.prefix(max(1, maxRootPosts)))

        var expandedByRoot: [String: [PostComment]] = [:]
        expandedByRoot.reserveCapacity(roots.count)

        for root in roots {
            var visiting = Set<String>()
            var seenCommentIDs = Set<String>()
            let tree = expandComments(
                postID: root.id,
                rootPostID: root.id,
                reparentTo: nil,
                rawCommentsByPost: rawCommentsByPost,
                bodyToPostID: bodyToPostID,
                postByID: postByID,
                visiting: &visiting,
                seenCommentIDs: &seenCommentIDs
            )
            // Bind speakers so the same person can comment more than once and stay recognizable.
            expandedByRoot[root.id] = stabilizeThreadAuthors(
                root: root,
                comments: tree,
                utteranceAuthorByBody: utteranceAuthorByBody
            )
        }

        let posts = roots.map { root in
            let count = expandedByRoot[root.id]?.count ?? 0
            return root.withEngagement(
                likedByMe: root.likedByMe,
                likeCount: root.likeCount,
                commentCount: count
            )
        }

        return (posts, expandedByRoot)
    }

    nonisolated private static func expandComments(
        postID: String,
        rootPostID: String,
        reparentTo: String?,
        rawCommentsByPost: [String: [PostComment]],
        bodyToPostID: [String: String],
        postByID: [String: CountryPost],
        visiting: inout Set<String>,
        seenCommentIDs: inout Set<String>
    ) -> [PostComment] {
        guard visiting.insert(postID).inserted else { return [] }
        defer { visiting.remove(postID) }

        var out: [PostComment] = []
        let raw = rawCommentsByPost[postID] ?? []
        for comment in raw {
            guard seenCommentIDs.insert(comment.id).inserted else { continue }

            // Nest this post's top-level comments under the parent comment that linked here.
            let parentID: String? = {
                if let reparentTo, comment.parentID == nil { return reparentTo }
                return comment.parentID
            }()
            var remapped = comment.withPostAndParent(postID: rootPostID, parentID: parentID)

            // Comment body matches a turn that was also exported as a post → same speaker.
            let key = normalizeThreadBody(comment.body)
            if let linkedPostID = bodyToPostID[key],
               let linkedPost = postByID[linkedPostID]
            {
                remapped = remapped.withAuthor(
                    authorID: linkedPost.authorID,
                    author: linkedPost.author
                )
            }

            out.append(remapped)

            // Pull that turn's replies under this comment so the full thread is one tree.
            if let linkedPostID = bodyToPostID[key],
               linkedPostID != postID,
               linkedPostID != rootPostID
            {
                let nested = expandComments(
                    postID: linkedPostID,
                    rootPostID: rootPostID,
                    reparentTo: comment.id,
                    rawCommentsByPost: rawCommentsByPost,
                    bodyToPostID: bodyToPostID,
                    postByID: postByID,
                    visiting: &visiting,
                    seenCommentIDs: &seenCommentIDs
                )
                out.append(contentsOf: nested)
            }
        }
        return out
    }

    nonisolated private static func normalizeThreadBody(_ body: String) -> String {
        body
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    nonisolated private static func parseJSONL(_ text: String) -> [[String: Any]] {
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

    nonisolated private static func normalizeAuthorIDStatic(_ raw: String) -> String {
        DemoPersonNames.normalizeAuthorID(raw)
    }

    /// Stable partner id for dialogue threads (one Matterya person for all non-OP replies).
    nonisolated private static func stablePartnerAuthorID(rootPostID: String) -> String {
        let seed = hashSeedStatic("partner|\(rootPostID)")
        let number = Int(seed % 90_000) + 1_000
        return String(format: "user_%06d", number)
    }

    /// One Reddit-style speaker → one Matterya user for the whole thread.
    /// Seed rows often used a fresh random author per comment; we re-bind speakers so
    /// the same person can leave multiple comments and stay recognizable.
    nonisolated private static func stabilizeThreadAuthors(
        root: CountryPost,
        comments: [PostComment],
        utteranceAuthorByBody: [String: (id: String, author: PostAuthor?)]
    ) -> [PostComment] {
        guard !comments.isEmpty else { return comments }

        let opID = DemoPersonNames.normalizeAuthorID(root.authorID)
        let opAuthor = root.author ?? DemoPersonNames.author(
            id: opID,
            countryName: root.countryName,
            countryCode: root.countryCode
        )
        let partnerID = stablePartnerAuthorID(rootPostID: root.id)
        let partnerAuthor = DemoPersonNames.author(
            id: partnerID,
            countryName: root.countryName,
            countryCode: root.countryCode
        )

        // Process parents before children when possible.
        let ordered = comments.sorted { $0.createdAt < $1.createdAt }
        var speakerOfComment: [String: String] = [:]
        var rewritten: [String: PostComment] = [:]

        for comment in ordered {
            let bodyKey = normalizeThreadBody(comment.body)
            let speakerID: String
            let speakerAuthor: PostAuthor?

            if let utterance = utteranceAuthorByBody[bodyKey] {
                // Same text as a known post turn → same person as that post's author.
                speakerID = DemoPersonNames.normalizeAuthorID(utterance.id)
                speakerAuthor = utterance.author
                    ?? DemoPersonNames.author(
                        id: speakerID,
                        countryName: root.countryName,
                        countryCode: root.countryCode
                    )
            } else if let parentID = comment.parentID, let parentSpeaker = speakerOfComment[parentID] {
                // Reply: the other party in a two-person dialogue (OP ↔ partner).
                if parentSpeaker == opID {
                    speakerID = partnerID
                    speakerAuthor = partnerAuthor
                } else {
                    speakerID = opID
                    speakerAuthor = opAuthor
                }
            } else {
                // Top-level replies to the post → one consistent partner person
                // (so two top-level comments look like the same user writing twice).
                speakerID = partnerID
                speakerAuthor = partnerAuthor
            }

            speakerOfComment[comment.id] = speakerID
            rewritten[comment.id] = comment.withAuthor(authorID: speakerID, author: speakerAuthor)
        }

        // Preserve original list order for UI stability.
        return comments.compactMap { rewritten[$0.id] }
    }

    nonisolated private static func normalizeBodyStatic(_ body: String, countryCode: String) -> String {
        let prefix = "[\(countryCode)] "
        if body.hasPrefix(prefix) {
            return String(body.dropFirst(prefix.count))
        }
        return body
    }

    nonisolated private static func hashSeedStatic(_ value: String) -> UInt64 {
        var hash: UInt64 = 2166136261
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 16777619
        }
        return hash
    }

    nonisolated private static func mapDemoPostStatic(_ row: [String: Any], commentCount: Int) -> CountryPost {
        let media = row["media"] as? [String: Any]
        let authorID = normalizeAuthorIDStatic(row["author_id"] as? String ?? "user_unknown")
        let countryCode = (row["country_code"] as? String ?? "XX").uppercased()
        let body = normalizeBodyStatic(row["body"] as? String ?? "", countryCode: countryCode)
        let createdAt = row["created_at"] as? String ?? ISO8601DateFormatter().string(from: Date())
        let seed = hashSeedStatic(row["id"] as? String ?? authorID)

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
            commentCount: commentCount,
            viewCount: Int(seed % 5000) + 50,
            likedByMe: false,
            savedByMe: false,
            createdAt: createdAt,
            updatedAt: createdAt,
            authorID: authorID,
            countryName: row["country_name"] as? String,
            countryCode: countryCode,
            cityName: nil,
            author: DemoPersonNames.author(
                id: authorID,
                countryName: row["country_name"] as? String,
                countryCode: countryCode
            )
        )
    }

    nonisolated private static func mapDemoCommentStatic(
        _ row: [String: Any],
        authorCountry: [String: (name: String?, code: String?)]
    ) -> PostComment? {
        guard let id = row["id"] as? String, !id.isEmpty,
              let postID = row["post_id"] as? String, !postID.isEmpty,
              let body = row["body"] as? String
        else { return nil }

        let authorID = normalizeAuthorIDStatic(row["author_id"] as? String ?? "user_unknown")
        let createdAt = row["created_at"] as? String ?? ISO8601DateFormatter().string(from: Date())
        let parentID = row["parent_id"] as? String
        let country = authorCountry[authorID]
        let code = country?.code
        let seed = hashSeedStatic(id)

        return PostComment(
            id: id,
            postID: postID,
            parentID: parentID,
            authorID: authorID,
            body: body,
            likeCount: Int(seed % 24),
            likedByMe: false,
            createdAt: createdAt,
            updatedAt: createdAt,
            author: DemoPersonNames.author(
                id: authorID,
                countryName: country?.name,
                countryCode: code
            )
        )
    }

}
