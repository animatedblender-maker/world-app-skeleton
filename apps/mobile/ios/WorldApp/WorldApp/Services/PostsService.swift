import Foundation

@MainActor
final class PostsService {
    static let shared = PostsService()

    private let gql = GraphQLService.shared
    private let demo = DemoDatasetService.shared
    private let follow = FollowService.shared

    private init() {}

    private let postFields = """
    id title body media_type media_url thumb_url shared_post_id
    visibility like_count comment_count liked_by_me
    created_at updated_at author_id country_name country_code city_name
    author { user_id display_name username avatar_url country_name country_code }
    """

    func listByCountry(_ countryCode: String, limit: Int = 25) async throws -> [CountryPost] {
        let code = countryCode.uppercased()
        if AppConfig.useDemoDataset {
            async let realTask = fetchRealPostsByCountry(code, limit: max(limit, 40))
            async let demoTask = demo.listByCountry(code, limit: max(limit, 40))
            let real = (try? await realTask) ?? []
            let demoPosts = await demoTask
            return mergePosts(real: real, demo: demoPosts, limit: limit)
        }
        return try await fetchRealPostsByCountry(code, limit: limit)
    }

    func listForAuthor(_ authorID: String, limit: Int = 25) async throws -> [CountryPost] {
        if AppConfig.useDemoDataset, authorID.hasPrefix("user_") {
            return await demo.listForAuthor(authorID, limit: limit)
        }
        struct Response: Decodable { let postsByAuthor: [GraphQLPost] }
        let query = """
        query PostsByAuthor($authorId: ID!, $limit: Int) {
          postsByAuthor(user_id: $authorId, limit: $limit) { \(postFields) }
        }
        """
        let result: Response = try await gql.authenticatedRequest(query: query, variables: ["authorId": authorID, "limit": limit])
        return result.postsByAuthor.map(\.toModel)
    }

    func loadFollowingFeed(limitPerAuthor: Int = 4, maxAuthors: Int = 12) async -> [CountryPost] {
        let followingIDs = Array(await follow.followingIDs().prefix(maxAuthors))
        guard !followingIDs.isEmpty else { return [] }

        var merged: [CountryPost] = []
        await withTaskGroup(of: [CountryPost].self) { group in
            for authorID in followingIDs {
                group.addTask {
                    (try? await self.listForAuthor(authorID, limit: limitPerAuthor)) ?? []
                }
            }
            for await batch in group { merged.append(contentsOf: batch) }
        }
        return merged.sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
    }

    func loadHomeFeed(followingLimitPerAuthor: Int = 4, globalLimit: Int = 40, maxPosts: Int = 50) async -> [CountryPost] {
        async let followingTask = loadFollowingFeed(limitPerAuthor: followingLimitPerAuthor)
        async let globalTask = fetchRecentPosts(limit: globalLimit)

        let following = await followingTask
        let global = await globalTask
        return mergeFeedSources([following, global], limit: maxPosts)
    }

    func loadReelsFeed(
        followingLimitPerAuthor: Int = 10,
        globalLimit: Int = 40,
        viewerCountry: String? = nil,
        followingIDs: Set<String> = []
    ) async -> [CountryPost] {
        let pool = await loadReelsPool(
            followingLimitPerAuthor: followingLimitPerAuthor,
            globalLimit: globalLimit
        )
        let reels = pool.filter { $0.isReel && !$0.isStory && $0.playableVideoURL != nil }
        let source = reels.isEmpty
            ? pool.filter { $0.hasVideo && !$0.isStory && $0.playableVideoURL != nil }
            : reels
        return ReelsRankingEngine.rank(source, viewerCountry: viewerCountry, followingIDs: followingIDs)
    }

    func loadReelsPool(followingLimitPerAuthor: Int = 10, globalLimit: Int = 40) async -> [CountryPost] {
        let followingIDs = await follow.followingIDs()

        var videos: [CountryPost] = []
        var seen = Set<String>()

        func appendVideos(_ batch: [CountryPost]) {
            for post in batch where post.hasVideo && !post.isStory && !seen.contains(post.id) {
                videos.append(post)
                seen.insert(post.id)
            }
        }

        appendVideos(await fetchRecentPosts(limit: globalLimit))

        if !followingIDs.isEmpty {
            await withTaskGroup(of: [CountryPost].self) { group in
                for authorID in followingIDs {
                    group.addTask {
                        (try? await self.listForAuthor(authorID, limit: followingLimitPerAuthor)) ?? []
                    }
                }
                for await batch in group {
                    appendVideos(batch)
                }
            }
        }

        if AppConfig.useDemoDataset {
            appendVideos(await sampleGlobalPosts(limit: globalLimit))
        }
        return videos
    }

    func loadLivingVideos(
        followingLimitPerAuthor: Int = 10,
        globalLimit: Int = 40
    ) async -> [CountryPost] {
        let pool = await loadReelsPool(
            followingLimitPerAuthor: followingLimitPerAuthor,
            globalLimit: globalLimit
        )
        return pool.filter { $0.hasVideo && !$0.isReel && !$0.isStory && $0.playableVideoURL != nil }
    }

    func searchPosts(_ query: String, limit: Int = 20) async throws -> [CountryPost] {
        struct Response: Decodable { let searchPosts: [GraphQLPost] }
        let gqlQuery = """
        query SearchPosts($query: String!, $limit: Int) {
          searchPosts(query: $query, limit: $limit) { \(postFields) }
        }
        """
        let real: [CountryPost]
        do {
            let result: Response = try await gql.authenticatedRequest(query: gqlQuery, variables: ["query": query, "limit": limit])
            real = result.searchPosts.map(\.toModel)
        } catch { real = [] }

        if AppConfig.useDemoDataset {
            let demoPosts = await demo.searchPosts(query, limit: limit)
            return mergePosts(real: real, demo: demoPosts, limit: limit)
        }
        return real
    }

    func getPostByID(_ postID: String) async throws -> CountryPost? {
        if AppConfig.useDemoDataset, let demoPost = await demo.getPostByID(postID) { return demoPost }
        struct Response: Decodable { let postById: GraphQLPost? }
        let query = "query($postId: ID!) { postById(post_id: $postId) { \(postFields) } }"
        let result: Response = try await gql.authenticatedRequest(query: query, variables: ["postId": postID])
        return result.postById?.toModel
    }

    func listComments(_ postID: String, limit: Int = 50) async throws -> [PostComment] {
        if AppConfig.useDemoDataset, await demo.isDemoPostID(postID) {
            return await demo.listComments(postID, limit: limit)
        }
        struct Response: Decodable { let commentsByPost: [GraphQLComment] }
        let query = """
        query($postId: ID!, $limit: Int) {
          commentsByPost(post_id: $postId, limit: $limit) {
            id post_id parent_id author_id body like_count liked_by_me created_at updated_at
            author { user_id display_name username avatar_url country_name country_code }
          }
        }
        """
        let result: Response = try await gql.authenticatedRequest(query: query, variables: ["postId": postID, "limit": limit])
        return result.commentsByPost.map(\.toModel)
    }

    func addComment(_ postID: String, body: String, parentID: String? = nil) async throws -> PostComment {
        if AppConfig.useDemoDataset, await demo.isDemoPostID(postID) {
            return await demo.addComment(postID, body: body, parentID: parentID)
        }
        struct Response: Decodable { let addComment: GraphQLComment }
        let mutation = """
        mutation($postId: ID!, $body: String!, $parentId: ID) {
          addComment(post_id: $postId, body: $body, parent_id: $parentId) {
            id post_id parent_id author_id body like_count liked_by_me created_at updated_at
            author { user_id display_name username avatar_url country_name country_code }
          }
        }
        """
        var vars: [String: Any] = ["postId": postID, "body": body]
        if let parentID { vars["parentId"] = parentID }
        let result: Response = try await gql.authenticatedRequest(query: mutation, variables: vars)
        return result.addComment.toModel
    }

    func createReel(
        authorID: String,
        body: String,
        countryName: String,
        countryCode: String,
        cityName: String? = nil,
        videoFileURL: URL,
        mimeType: String = "video/mp4",
        fileExtension: String = "mp4",
        onUploadProgress: (@Sendable (UploadProgress) -> Void)? = nil,
        onPublishing: (@Sendable () -> Void)? = nil
    ) async throws -> CountryPost {
        let upload = try await MediaService.shared.uploadPostMedia(
            fileURL: videoFileURL,
            fileExtension: fileExtension,
            mimeType: mimeType,
            onProgress: onUploadProgress
        )
        onPublishing?()
        let mediaURL = PostMediaPayload.encode(
            urls: [upload.publicURL],
            types: ["video"],
            reel: true
        )
        return try await createPost(
            authorID: authorID,
            body: body,
            countryName: countryName,
            countryCode: countryCode,
            cityName: cityName,
            mediaType: "video",
            mediaURL: mediaURL
        )
    }

    func createLivingVideo(
        authorID: String,
        body: String,
        countryName: String,
        countryCode: String,
        cityName: String? = nil,
        title: String? = nil,
        videoFileURL: URL,
        mimeType: String = "video/mp4",
        fileExtension: String = "mp4",
        onUploadProgress: (@Sendable (UploadProgress) -> Void)? = nil,
        onPublishing: (@Sendable () -> Void)? = nil
    ) async throws -> CountryPost {
        let upload = try await MediaService.shared.uploadPostMedia(
            fileURL: videoFileURL,
            fileExtension: fileExtension,
            mimeType: mimeType,
            onProgress: onUploadProgress
        )
        onPublishing?()
        let mediaURL = PostMediaPayload.encode(
            urls: [upload.publicURL],
            types: ["video"],
            reel: false
        )
        return try await createPost(
            authorID: authorID,
            body: body,
            countryName: countryName,
            countryCode: countryCode,
            cityName: cityName,
            title: title,
            mediaType: "video",
            mediaURL: mediaURL
        )
    }

    func createStory(
        authorID: String,
        body: String,
        countryName: String,
        countryCode: String,
        cityName: String? = nil,
        mediaData: Data? = nil,
        mediaFileURL: URL? = nil,
        mimeType: String,
        fileExtension: String,
        onUploadProgress: (@Sendable (UploadProgress) -> Void)? = nil,
        onPublishing: (@Sendable () -> Void)? = nil
    ) async throws -> CountryPost {
        let upload: (path: String, publicURL: String)
        if let mediaFileURL {
            upload = try await MediaService.shared.uploadPostMedia(
                fileURL: mediaFileURL,
                fileExtension: fileExtension,
                mimeType: mimeType,
                onProgress: onUploadProgress
            )
        } else if let mediaData {
            upload = try await MediaService.shared.uploadPostMedia(
                data: mediaData,
                fileExtension: fileExtension,
                mimeType: mimeType
            )
        } else {
            throw MediaError.uploadFailed("Missing story media.")
        }
        onPublishing?()
        let mediaType = mimeType.hasPrefix("video/") ? "video" : "image"
        let expiresAt = Date().addingTimeInterval(86_400)
        let storyBody = PostStoryMarker.buildBody(caption: body, expiresAt: expiresAt)
        return try await createPost(
            authorID: authorID,
            body: storyBody,
            countryName: countryName,
            countryCode: countryCode,
            cityName: cityName,
            mediaType: mediaType,
            mediaURL: upload.publicURL
        )
    }

    func loadActiveStoryGroups(
        countryCode: String?,
        followingIDs: Set<String>,
        viewedStoryIDs: Set<String>,
        currentUserID: String?
    ) async -> [StoryGroup] {
        var pool: [CountryPost] = []
        var seen = Set<String>()

        func append(_ batch: [CountryPost]) {
            for post in batch where post.isStory && post.isStoryActive && !seen.contains(post.id) {
                pool.append(post)
                seen.insert(post.id)
            }
        }

        if let countryCode {
            append((try? await listByCountry(countryCode, limit: 80)) ?? [])
        }

        if !followingIDs.isEmpty {
            await withTaskGroup(of: [CountryPost].self) { group in
                for authorID in followingIDs {
                    group.addTask { (try? await self.listForAuthor(authorID, limit: 20)) ?? [] }
                }
                for await batch in group { append(batch) }
            }
        }

        if let currentUserID {
            append((try? await listForAuthor(currentUserID, limit: 20)) ?? [])
        }

        let grouped = Dictionary(grouping: pool, by: \.authorID)
        return grouped.map { authorID, stories in
            let sorted = stories.sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
            let author = sorted.first?.author
            let hasUnviewed = sorted.contains { !viewedStoryIDs.contains($0.id) }
            return StoryGroup(authorID: authorID, author: author, stories: sorted, hasUnviewed: hasUnviewed)
        }
        .sorted { lhs, rhs in
            if lhs.authorID == currentUserID { return true }
            if rhs.authorID == currentUserID { return false }
            if lhs.hasUnviewed != rhs.hasUnviewed { return lhs.hasUnviewed }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    func sharePostToCountryFeed(
        post: CountryPost,
        countryName: String,
        countryCode: String,
        cityName: String? = nil
    ) async throws -> CountryPost {
        let originalID = post.sharedPostID ?? post.id
        struct Response: Decodable { let createPost: GraphQLPost }
        var input: [String: Any] = [
            "body": "",
            "country_name": countryName,
            "country_code": countryCode.uppercased(),
            "visibility": "country",
            "media_type": "none",
            "shared_post_id": originalID,
        ]
        if let cityName { input["city_name"] = cityName }

        let mutation = "mutation($input: CreatePostInput!) { createPost(input: $input) { \(postFields) } }"
        let result: Response = try await gql.authenticatedRequest(query: mutation, variables: ["input": input])
        return result.createPost.toModel
    }

    func createPost(
        authorID: String,
        body: String,
        countryName: String,
        countryCode: String,
        cityName: String? = nil,
        title: String? = nil,
        mediaType: String? = nil,
        mediaURL: String? = nil,
        thumbURL: String? = nil
    ) async throws -> CountryPost {
        struct Response: Decodable { let createPost: GraphQLPost }
        var input: [String: Any] = [
            "body": body,
            "country_name": countryName,
            "country_code": countryCode.uppercased(),
            "visibility": "country"
        ]
        if let title { input["title"] = title }
        if let cityName { input["city_name"] = cityName }
        if let mediaType { input["media_type"] = mediaType }
        if let mediaURL { input["media_url"] = mediaURL }
        if let thumbURL { input["thumb_url"] = thumbURL }

        let mutation = "mutation($input: CreatePostInput!) { createPost(input: $input) { \(postFields) } }"
        let result: Response = try await gql.authenticatedRequest(query: mutation, variables: ["input": input])
        return result.createPost.toModel
    }

    func likePost(_ postID: String) async throws {
        let mutation = "mutation($postId: ID!) { likePost(post_id: $postId) { id } }"
        let _: EmptyMutation = try await gql.authenticatedRequest(query: mutation, variables: ["postId": postID])
    }

    func unlikePost(_ postID: String) async throws {
        let mutation = "mutation($postId: ID!) { unlikePost(post_id: $postId) { id } }"
        let _: EmptyMutation = try await gql.authenticatedRequest(query: mutation, variables: ["postId": postID])
    }

    func savedPosts(limit: Int = 80) async throws -> [CountryPost] {
        struct Response: Decodable { let savedPosts: [GraphQLPost] }
        let query = """
        query SavedPosts($limit: Int) {
          savedPosts(limit: $limit) { \(postFields) }
        }
        """
        let result: Response = try await gql.authenticatedRequest(query: query, variables: ["limit": limit])
        return result.savedPosts.map(\.toModel)
    }

    func savePost(_ postID: String) async throws -> CountryPost {
        struct Response: Decodable { let savePost: GraphQLPost }
        let mutation = """
        mutation($postId: ID!) {
          savePost(post_id: $postId) { \(postFields) }
        }
        """
        let result: Response = try await gql.authenticatedRequest(query: mutation, variables: ["postId": postID])
        return result.savePost.toModel
    }

    func unsavePost(_ postID: String) async throws -> CountryPost {
        struct Response: Decodable { let unsavePost: GraphQLPost }
        let mutation = """
        mutation($postId: ID!) {
          unsavePost(post_id: $postId) { \(postFields) }
        }
        """
        let result: Response = try await gql.authenticatedRequest(query: mutation, variables: ["postId": postID])
        return result.unsavePost.toModel
    }

    func updatePost(
        _ postID: String,
        title: String? = nil,
        body: String? = nil
    ) async throws -> CountryPost {
        struct Response: Decodable { let updatePost: GraphQLPost }
        var input: [String: Any] = [:]
        if let title { input["title"] = title }
        if let body { input["body"] = body }
        let mutation = """
        mutation($postId: ID!, $input: UpdatePostInput!) {
          updatePost(post_id: $postId, input: $input) { \(postFields) }
        }
        """
        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["postId": postID, "input": input]
        )
        return result.updatePost.toModel
    }

    func deletePost(_ postID: String) async throws -> Bool {
        struct Response: Decodable { let deletePost: Bool }
        let mutation = "mutation($postId: ID!) { deletePost(post_id: $postId) }"
        let result: Response = try await gql.authenticatedRequest(query: mutation, variables: ["postId": postID])
        return result.deletePost
    }

    func reportPost(_ postID: String, reason: String) async throws -> Bool {
        struct Response: Decodable { let reportPost: Bool }
        let mutation = "mutation($postId: ID!, $reason: String!) { reportPost(post_id: $postId, reason: $reason) }"
        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["postId": postID, "reason": reason]
        )
        return result.reportPost
    }

    func likeComment(_ commentID: String) async throws -> PostComment {
        if AppConfig.useDemoDataset, let comment = await demo.likeComment(commentID) {
            return comment
        }
        struct Response: Decodable { let likeComment: GraphQLComment }
        let mutation = """
        mutation($commentId: ID!) {
          likeComment(comment_id: $commentId) {
            id post_id parent_id author_id body like_count liked_by_me created_at updated_at
            author { user_id display_name username avatar_url country_name country_code }
          }
        }
        """
        let result: Response = try await gql.authenticatedRequest(query: mutation, variables: ["commentId": commentID])
        return result.likeComment.toModel
    }

    func unlikeComment(_ commentID: String) async throws -> PostComment {
        if AppConfig.useDemoDataset, let comment = await demo.unlikeComment(commentID) {
            return comment
        }
        struct Response: Decodable { let unlikeComment: GraphQLComment }
        let mutation = """
        mutation($commentId: ID!) {
          unlikeComment(comment_id: $commentId) {
            id post_id parent_id author_id body like_count liked_by_me created_at updated_at
            author { user_id display_name username avatar_url country_name country_code }
          }
        }
        """
        let result: Response = try await gql.authenticatedRequest(query: mutation, variables: ["commentId": commentID])
        return result.unlikeComment.toModel
    }

    func videoPosts(for country: Country, limit: Int = 40) async throws -> [CountryPost] {
        let posts = try await listByCountry(country.iso, limit: limit)
        return posts.filter(\.hasVideo)
    }

    func sampleGlobalPosts(limit: Int = 12) async -> [CountryPost] {
        await demo.sampleGlobalPosts(limit: limit)
    }

    private var viewedPostIDs: Set<String> = []

    func recordView(_ post: CountryPost) async {
        guard !post.id.isEmpty, !viewedPostIDs.contains(post.id) else { return }
        viewedPostIDs.insert(post.id)
        ReelsRankingEngine.markWatched(post.id)
    }

    private func fetchRealPostsByCountry(_ code: String, limit: Int) async throws -> [CountryPost] {
        struct Response: Decodable { let postsByCountry: [GraphQLPost] }
        let query = "query($code: String!, $limit: Int) { postsByCountry(country_code: $code, limit: $limit) { \(postFields) } }"
        let result: Response = try await gql.authenticatedRequest(query: query, variables: ["code": code, "limit": limit])
        return result.postsByCountry.map(\.toModel)
    }

    func fetchRecentPosts(limit: Int = 40) async -> [CountryPost] {
        struct Response: Decodable { let recentPosts: [GraphQLPost] }
        let query = "query($limit: Int) { recentPosts(limit: $limit) { \(postFields) } }"
        var real: [CountryPost]
        do {
            let result: Response = try await gql.authenticatedRequest(
                query: query,
                variables: ["limit": limit]
            )
            real = result.recentPosts.map(\.toModel)
        } catch {
            real = []
        }

        if real.isEmpty {
            real = await fallbackGlobalPosts(limit: limit)
        }

        if AppConfig.useDemoDataset {
            return mergePosts(real: real, demo: await demo.sampleGlobalPosts(limit: limit), limit: limit)
        }
        return real
    }

    private func fallbackGlobalPosts(limit: Int) async -> [CountryPost] {
        let countries = (try? await ProfileService.shared.countries()) ?? []
        let codes = countries.prefix(14).map(\.iso)
        guard !codes.isEmpty else { return [] }

        var batches: [[CountryPost]] = []
        await withTaskGroup(of: [CountryPost].self) { group in
            for code in codes {
                group.addTask {
                    (try? await self.listByCountry(code, limit: max(6, limit / codes.count))) ?? []
                }
            }
            for await batch in group {
                batches.append(batch)
            }
        }
        return mergeFeedSources(batches, limit: limit)
    }

    func mergeFeedSources(_ batches: [[CountryPost]], limit: Int) -> [CountryPost] {
        var seen = Set<String>()
        var merged: [CountryPost] = []
        let sortedBatches = batches.map {
            $0.sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
        }
        var indices = Array(repeating: 0, count: sortedBatches.count)

        while merged.count < limit {
            var appended = false
            for batchIndex in sortedBatches.indices {
                let batch = sortedBatches[batchIndex]
                while indices[batchIndex] < batch.count {
                    let post = batch[indices[batchIndex]]
                    indices[batchIndex] += 1
                    guard !seen.contains(post.id) else { continue }
                    seen.insert(post.id)
                    merged.append(post)
                    appended = true
                    break
                }
                if merged.count >= limit { break }
            }
            if !appended { break }
        }

        return merged
    }

    func mergePosts(real: [CountryPost], demo: [CountryPost], limit: Int) -> [CountryPost] {
        mergeFeedSources([real, demo], limit: limit)
    }
}