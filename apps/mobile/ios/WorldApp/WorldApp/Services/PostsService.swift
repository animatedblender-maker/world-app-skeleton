import Foundation
import UIKit

@MainActor
final class PostsService {
    static let shared = PostsService()

    private let gql = GraphQLService.shared
    private let demo = DemoDatasetService.shared
    private let follow = FollowService.shared

    private init() {}

    private let postFields = """
    id title body media_type media_url thumb_url shared_post_id
    shared_post {
      id title body media_type media_url thumb_url author_id
      author { user_id display_name username avatar_url country_name country_code }
    }
    visibility like_count comment_count liked_by_me
    created_at updated_at author_id country_name country_code city_name
    author { user_id display_name username avatar_url country_name country_code }
    """

    private let postFieldsWithBookmarks = """
    id title body media_type media_url thumb_url shared_post_id
    shared_post {
      id title body media_type media_url thumb_url author_id
      author { user_id display_name username avatar_url country_name country_code }
    }
    visibility like_count comment_count liked_by_me saved_by_me
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
        if ScreenshotMode.isActive, authorID == ScreenshotMode.demoProfile.userID {
            if let cached = ContentCache.shared.posts(for: .profilePosts) {
                return Array(cached.prefix(limit))
            }
            return Array(await demo.sampleGlobalPosts(limit: limit).prefix(limit))
        }
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

    /// Country feed posts: local country posts plus followed creators posting from abroad.
    func loadCountryFeedPosts(
        countryISO: String,
        localLimit: Int = 30,
        followingLimitPerAuthor: Int = 5,
        maxAuthors: Int = 24
    ) async throws -> [CountryPost] {
        let iso = countryISO.uppercased()
        async let localTask = listByCountry(iso, limit: localLimit)
        async let followingTask = loadFollowingFeed(
            limitPerAuthor: followingLimitPerAuthor,
            maxAuthors: maxAuthors
        )

        let local = try await localTask
        let following = await followingTask
        let localIDs = Set(local.map(\.id))
        let abroadFollowing = following.filter { post in
            guard !localIDs.contains(post.id) else { return false }
            let postISO = post.countryCode?.uppercased() ?? ""
            return !postISO.isEmpty && postISO != iso
        }

        return mergeFeedSources([local, abroadFollowing], limit: localLimit + abroadFollowing.count)
            .excludingMoments()
            .excludingSparks()
    }

    func loadHomeFeed(
        followingLimitPerAuthor: Int = 4,
        globalLimit: Int = 40,
        maxPosts: Int = 50,
        forceRefresh: Bool = false
    ) async -> [CountryPost] {
        if !forceRefresh,
           ContentCache.shared.isFresh(.homeFeed),
           let cached = ContentCache.shared.posts(for: .homeFeed) {
            return cached
        }

        await prepareFeedContext()

        async let ownTask = fetchOwnPosts(limit: max(globalLimit, 25))
        async let followingTask = loadFollowingFeed(limitPerAuthor: followingLimitPerAuthor)
        async let globalTask = fetchRecentPosts(limit: globalLimit)
        async let homeCountryTask = fetchHomeCountryPosts(limit: max(globalLimit, 25))

        let own = await ownTask
        let following = await followingTask
        let global = await globalTask
        let homeCountry = await homeCountryTask
        var batches: [[CountryPost]] = []
        if !own.isEmpty { batches.append(own) }
        if !homeCountry.isEmpty { batches.append(homeCountry) }
        if !following.isEmpty { batches.append(following) }
        if !global.isEmpty { batches.append(global) }

        var merged = mergeFeedSources(batches, limit: maxPosts).excludingMoments().excludingSparks()
        if merged.isEmpty {
            merged = await fallbackFeedPosts(limit: maxPosts).excludingSparks()
        }
        if !merged.isEmpty {
            ContentCache.shared.setPosts(merged, for: .homeFeed)
        } else {
            ContentCache.shared.invalidate(.homeFeed)
        }
        return merged
    }

    func loadReelsFeed(
        followingLimitPerAuthor: Int = 10,
        globalLimit: Int = 40,
        viewerCountry: String? = nil,
        followingIDs: Set<String> = []
    ) async -> [CountryPost] {
        let page = await loadReelsFeedPage(
            excludingIDs: [],
            cursor: nil,
            batchSize: globalLimit,
            fetchLimit: max(globalLimit, 40),
            followingLimitPerAuthor: followingLimitPerAuthor,
            viewerCountry: viewerCountry,
            followingIDs: followingIDs,
            tail: [],
            allowRecycle: false
        )
        return page.posts
    }

    /// Paginated endless spark feed — ranks diversity, following, home country, and engagement.
    func loadReelsFeedPage(
        excludingIDs: Set<String>,
        cursor: String? = nil,
        batchSize: Int = 12,
        fetchLimit: Int = 48,
        followingLimitPerAuthor: Int = 10,
        viewerCountry: String? = nil,
        followingIDs: Set<String> = [],
        tail: [CountryPost] = [],
        allowRecycle: Bool = false
    ) async -> ReelsFeedPage {
        await prepareFeedContext()

        var candidates: [CountryPost] = []
        let recent = await fetchRecentPosts(limit: fetchLimit, before: cursor)
        candidates.append(contentsOf: recent)

        if cursor == nil {
            let pool = await loadReelsPool(
                followingLimitPerAuthor: followingLimitPerAuthor,
                globalLimit: max(fetchLimit, 40)
            )
            candidates.append(contentsOf: pool)
        }

        var seenCandidateIDs = Set<String>()
        candidates = candidates.filter { post in
            guard seenCandidateIDs.insert(post.id).inserted else { return false }
            return ReelsRankingEngine.isSparkEligible(post)
        }

        let batch = ReelsRankingEngine.nextBatch(
            from: candidates,
            excluding: excludingIDs,
            limit: batchSize,
            viewerCountry: viewerCountry,
            followingIDs: followingIDs,
            tail: tail,
            allowRecycle: allowRecycle
        )

        let nextCursor = recent.last?.createdAt
        let hasMore = recent.count >= max(8, fetchLimit / 3)

        return ReelsFeedPage(posts: batch, nextCursor: nextCursor, hasMore: hasMore)
    }

    /// Fresher sparks to prepend when scrolling back up.
    func loadReelsNewerBatch(
        than createdAfter: String,
        excludingIDs: Set<String>,
        batchSize: Int = 8,
        viewerCountry: String? = nil,
        followingIDs: Set<String> = [],
        head: [CountryPost] = []
    ) async -> [CountryPost] {
        let recent = await fetchRecentPosts(limit: 60)
        let newer = recent.filter { $0.createdAt > createdAfter }
        let pool = await loadReelsPool(followingLimitPerAuthor: 8, globalLimit: 40)
        var candidates = newer + pool
        var seen = Set<String>()
        candidates = candidates.filter { seen.insert($0.id).inserted }

        return ReelsRankingEngine.nextBatch(
            from: candidates,
            excluding: excludingIDs,
            limit: batchSize,
            viewerCountry: viewerCountry,
            followingIDs: followingIDs,
            tail: head,
            allowRecycle: false
        )
    }

    func loadReelsPool(followingLimitPerAuthor: Int = 10, globalLimit: Int = 40) async -> [CountryPost] {
        await prepareFeedContext()

        let followingIDs = await follow.followingIDs()
        let currentUserID = currentAuthorID()

        var videos: [CountryPost] = []
        var seen = Set<String>()

        func appendVideos(_ batch: [CountryPost]) {
            for post in batch where post.hasVideo && !post.isStory && !seen.contains(post.id) {
                videos.append(post)
                seen.insert(post.id)
            }
        }

        appendVideos(await fetchOwnPosts(limit: globalLimit))
        appendVideos(await fetchHomeCountryPosts(limit: globalLimit))
        appendVideos(await fetchRecentPosts(limit: globalLimit))

        if !followingIDs.isEmpty {
            await withTaskGroup(of: [CountryPost].self) { group in
                for authorID in followingIDs where authorID != currentUserID {
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
        globalLimit: Int = 40,
        forceRefresh: Bool = false
    ) async -> [CountryPost] {
        if !forceRefresh,
           ContentCache.shared.isFresh(.livingVideos),
           let cached = ContentCache.shared.posts(for: .livingVideos) {
            return cached
        }

        await prepareFeedContext()

        let pool = await loadReelsPool(
            followingLimitPerAuthor: followingLimitPerAuthor,
            globalLimit: globalLimit
        )
        var videos = pool.filter { $0.hasVideo && !$0.isReel && !$0.isStory }
        if videos.isEmpty {
            let own = await fetchOwnPosts(limit: globalLimit)
            videos = own.filter { $0.hasVideo && !$0.isReel && !$0.isStory }
        }
        if !videos.isEmpty {
            ContentCache.shared.setPosts(videos, for: .livingVideos)
        } else {
            ContentCache.shared.invalidate(.livingVideos)
        }
        return videos
    }

    /// Unified Matterya Hubs catalog: long-form videos + reels.
    func loadPlayCatalog(
        followingLimitPerAuthor: Int = 10,
        globalLimit: Int = 40,
        forceRefresh: Bool = false,
        viewerCountry: String? = nil,
        followingIDs: Set<String> = []
    ) async -> [CountryPost] {
        async let longFormTask = loadLivingVideos(
            followingLimitPerAuthor: followingLimitPerAuthor,
            globalLimit: globalLimit,
            forceRefresh: forceRefresh
        )
        async let reelsTask = loadReelsFeed(
            followingLimitPerAuthor: followingLimitPerAuthor,
            globalLimit: globalLimit,
            viewerCountry: viewerCountry,
            followingIDs: followingIDs
        )
        let longForm = await longFormTask
        let reels = await reelsTask

        var merged: [CountryPost] = []
        var seen = Set<String>()
        for post in reels + longForm where !seen.contains(post.id) {
            seen.insert(post.id)
            merged.append(post)
        }
        return merged
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
            let merged = mergePosts(real: real, demo: demoPosts, limit: limit)
            return MatteryaSearchEngine.rankContent(merged, query: query, limit: limit)
                .excludingSparks()
        }
        return MatteryaSearchEngine.rankContent(real, query: query, limit: limit)
            .excludingSparks()
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
        query($post_id: ID!, $limit: Int) {
          commentsByPost(post_id: $post_id, limit: $limit) {
            id post_id parent_id author_id body like_count liked_by_me created_at updated_at
            author { user_id display_name username avatar_url country_name country_code }
          }
        }
        """
        let result: Response = try await gql.authenticatedRequest(
            query: query,
            variables: ["post_id": postID, "limit": limit]
        )
        return result.commentsByPost.map(\.toModel)
    }

    func addComment(_ postID: String, body: String, parentID: String? = nil) async throws -> PostComment {
        if AppConfig.useDemoDataset, await demo.isDemoPostID(postID) {
            return await demo.addComment(postID, body: body, parentID: parentID)
        }
        struct Response: Decodable { let addComment: GraphQLComment }
        let mutation = """
        mutation($post_id: ID!, $body: String!, $parent_id: ID) {
          addComment(post_id: $post_id, body: $body, parent_id: $parent_id) {
            id post_id parent_id author_id body like_count liked_by_me created_at updated_at
            author { user_id display_name username avatar_url country_name country_code }
          }
        }
        """
        var vars: [String: Any] = [
            "post_id": postID,
            "body": body,
        ]
        if let parentID, !parentID.isEmpty {
            vars["parent_id"] = parentID
        }
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
        thumbnailImage: UIImage? = nil,
        onUploadProgress: (@Sendable (UploadProgress) -> Void)? = nil,
        onPublishing: (@Sendable () -> Void)? = nil
    ) async throws -> CountryPost {
        let upload = try await MediaService.shared.uploadPostMedia(
            fileURL: videoFileURL,
            fileExtension: fileExtension,
            mimeType: mimeType,
            onProgress: onUploadProgress
        )
        let thumbURL = try await uploadVideoThumbnail(
            from: videoFileURL,
            prefetchedImage: thumbnailImage
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
            mediaURL: mediaURL,
            thumbURL: thumbURL
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
        thumbnailImage: UIImage? = nil,
        onUploadProgress: (@Sendable (UploadProgress) -> Void)? = nil,
        onPublishing: (@Sendable () -> Void)? = nil
    ) async throws -> CountryPost {
        let upload = try await MediaService.shared.uploadPostMedia(
            fileURL: videoFileURL,
            fileExtension: fileExtension,
            mimeType: mimeType,
            onProgress: onUploadProgress
        )
        let thumbURL = try await uploadVideoThumbnail(
            from: videoFileURL,
            prefetchedImage: thumbnailImage
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
            mediaURL: mediaURL,
            thumbURL: thumbURL
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
        let expiresAt = Date().addingTimeInterval(86_400)
        let storyBody = PostStoryMarker.buildBody(caption: body, expiresAt: expiresAt)
        return try await createPost(
            authorID: authorID,
            body: storyBody,
            countryName: countryName,
            countryCode: countryCode,
            cityName: cityName,
            visibility: .country,
            mediaType: "story",
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
        guard !post.isStory else {
            throw PostsServiceError.momentCannotBeSharedAsPost
        }
        if let shared = post.sharedPost, shared.asCountryPost.isStory {
            throw PostsServiceError.momentCannotBeSharedAsPost
        }
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
        visibility: PostVisibility = .public,
        mediaType: String? = nil,
        mediaURL: String? = nil,
        thumbURL: String? = nil,
        sharedPostID: String? = nil
    ) async throws -> CountryPost {
        struct Response: Decodable { let createPost: GraphQLPost }
        let normalizedMediaType = (mediaType ?? "").lowercased()
        let resolvedVisibility: PostVisibility
        if normalizedMediaType == "story" || body.contains("__story__|") {
            resolvedVisibility = .country
        } else if normalizedMediaType == "video" {
            resolvedVisibility = .public
        } else {
            resolvedVisibility = visibility
        }
        var input: [String: Any] = [
            "body": body,
            "country_name": countryName,
            "country_code": countryCode.uppercased(),
            "visibility": resolvedVisibility.rawValue
        ]
        if let title { input["title"] = title }
        if let cityName { input["city_name"] = cityName }
        if let mediaType { input["media_type"] = mediaType }
        if let mediaURL { input["media_url"] = mediaURL }
        if let thumbURL { input["thumb_url"] = thumbURL }
        if let sharedPostID { input["shared_post_id"] = sharedPostID }

        let mutation = "mutation($input: CreatePostInput!) { createPost(input: $input) { \(postFields) } }"
        let result: Response = try await gql.authenticatedRequest(query: mutation, variables: ["input": input])
        let created = result.createPost.toModel
        if !created.isStory {
            ContentCache.shared.invalidateAllFeeds()
        }
        return created
    }

    func likePost(_ postID: String) async throws {
        let mutation = "mutation($postId: ID!) { likePost(post_id: $postId) { id } }"
        let _: EmptyMutation = try await gql.authenticatedRequest(query: mutation, variables: ["postId": postID])
    }

    func unlikePost(_ postID: String) async throws {
        let mutation = "mutation($postId: ID!) { unlikePost(post_id: $postId) { id } }"
        let _: EmptyMutation = try await gql.authenticatedRequest(query: mutation, variables: ["postId": postID])
    }

    private static let localBookmarksOnlyKey = "posts.bookmarks.local_only"

    static var usesLocalBookmarksOnly: Bool {
        get { UserDefaults.standard.bool(forKey: localBookmarksOnlyKey) }
        set { UserDefaults.standard.set(newValue, forKey: localBookmarksOnlyKey) }
    }

    static func isUnsupportedBookmarkError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("savepost")
            || message.contains("unsavepost")
            || message.contains("savedposts")
            || message.contains("saved_by_me")
            || message.contains("post_bookmarks")
            || message.contains("internal server error")
            || message.contains("internal_server_error")
            || message.contains("cannot query field")
            || message.contains("graphql_validation_failed")
    }

    func savedPosts(limit: Int = 80) async throws -> [CountryPost] {
        struct Response: Decodable { let savedPosts: [GraphQLPost] }
        let query = """
        query SavedPosts($limit: Int) {
          savedPosts(limit: $limit) { \(postFieldsWithBookmarks) }
        }
        """
        let result: Response = try await gql.authenticatedRequest(query: query, variables: ["limit": limit])
        Self.usesLocalBookmarksOnly = false
        return result.savedPosts.map(\.toModel)
    }

    func savePost(_ postID: String) async throws -> CountryPost {
        struct Response: Decodable { let savePost: GraphQLPost }
        let mutation = """
        mutation($postId: ID!) {
          savePost(post_id: $postId) { \(postFieldsWithBookmarks) }
        }
        """
        let result: Response = try await gql.authenticatedRequest(query: mutation, variables: ["postId": postID])
        Self.usesLocalBookmarksOnly = false
        return result.savePost.toModel
    }

    func unsavePost(_ postID: String) async throws -> CountryPost {
        struct Response: Decodable { let unsavePost: GraphQLPost }
        let mutation = """
        mutation($postId: ID!) {
          unsavePost(post_id: $postId) { \(postFieldsWithBookmarks) }
        }
        """
        let result: Response = try await gql.authenticatedRequest(query: mutation, variables: ["postId": postID])
        Self.usesLocalBookmarksOnly = false
        return result.unsavePost.toModel
    }

    func loadBookmarkedPosts(localIDs: Set<String>, limit: Int = 100) async -> [CountryPost] {
        if Self.usesLocalBookmarksOnly {
            return await resolveLocalBookmarks(ids: localIDs, limit: limit)
        }
        do {
            return try await savedPosts(limit: limit)
        } catch {
            if Self.isUnsupportedBookmarkError(error) {
                Self.usesLocalBookmarksOnly = true
                return await resolveLocalBookmarks(ids: localIDs, limit: limit)
            }
            if let cached = ContentCache.shared.posts(for: .savedPosts), !cached.isEmpty {
                return cached
            }
            return await resolveLocalBookmarks(ids: localIDs, limit: limit)
        }
    }

    func toggleBookmark(for post: CountryPost, saved: Bool) async throws -> CountryPost {
        if Self.usesLocalBookmarksOnly {
            return post.withSavedByMe(saved)
        }
        do {
            if saved {
                return try await savePost(post.id)
            }
            return try await unsavePost(post.id)
        } catch {
            if Self.isUnsupportedBookmarkError(error) {
                Self.usesLocalBookmarksOnly = true
                return post.withSavedByMe(saved)
            }
            throw error
        }
    }

    private func resolveLocalBookmarks(ids: Set<String>, limit: Int) async -> [CountryPost] {
        guard !ids.isEmpty else { return [] }

        if let cached = ContentCache.shared.posts(for: .savedPosts) {
            let filtered = cached
                .filter { ids.contains($0.id) }
                .map { $0.withSavedByMe(true) }
            if !filtered.isEmpty {
                return filtered.sorted { $0.createdAt > $1.createdAt }
            }
        }

        var resolved: [CountryPost] = []
        for id in ids.prefix(limit) {
            if let post = try? await getPostByID(id) {
                resolved.append(post.withSavedByMe(true))
            }
        }
        return resolved.sorted { $0.createdAt > $1.createdAt }
    }

    func updatePost(
        _ postID: String,
        title: String? = nil,
        body: String? = nil,
        visibility: PostVisibility? = nil,
        mediaType: String? = nil,
        mediaURL: String? = nil,
        thumbURL: String? = nil,
        clearMedia: Bool = false
    ) async throws -> CountryPost {
        struct Response: Decodable { let updatePost: GraphQLPost }
        var input: [String: Any] = [:]
        if let title { input["title"] = title }
        if let body { input["body"] = body }
        if let visibility { input["visibility"] = visibility.rawValue }
        if clearMedia {
            input["clear_media"] = true
        } else if let mediaURL {
            input["media_url"] = mediaURL
            if let mediaType { input["media_type"] = mediaType }
            if let thumbURL { input["thumb_url"] = thumbURL }
        }
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

    func fetchRecentPosts(limit: Int = 40, before: String? = nil) async -> [CountryPost] {
        struct Response: Decodable { let recentPosts: [GraphQLPost] }
        let query = """
        query($limit: Int, $before: String) {
          recentPosts(limit: $limit, before: $before) { \(postFields) }
        }
        """
        var variables: [String: Any] = ["limit": limit]
        if let before, !before.isEmpty {
            variables["before"] = before
        }
        var real: [CountryPost] = []
        for attempt in 0..<2 {
            do {
                let result: Response = try await gql.authenticatedRequest(
                    query: query,
                    variables: variables
                )
                real = result.recentPosts.map(\.toModel)
                break
            } catch {
                if attempt == 0 {
                    _ = try? await Task { @MainActor in
                        try await AuthService.shared.ensureValidToken()
                    }.value
                    continue
                }
                real = []
            }
        }

        if real.isEmpty {
            real = await fallbackGlobalPosts(limit: limit)
        }

        if AppConfig.useDemoDataset {
            return mergePosts(real: real, demo: await demo.sampleGlobalPosts(limit: limit), limit: limit)
        }
        return real
    }

    private func fetchHomeCountryPosts(limit: Int) async -> [CountryPost] {
        guard let code = await resolvedHomeCountryCode() else { return [] }
        return (try? await listByCountry(code, limit: limit)) ?? []
    }

    private func prepareFeedContext() async {
        _ = try? await AuthService.shared.ensureValidToken()
        _ = await resolvedHomeCountryCode()
    }

    private func resolvedHomeCountryCode() async -> String? {
        if let code = ContentCache.shared.profileCountryCode(), !code.isEmpty {
            return code
        }
        if let code = ContentCache.shared.cachedProfile()?.countryCode?.uppercased(), !code.isEmpty {
            ContentCache.shared.setProfileCountryCode(code)
            return code
        }
        if let profile = try? await ProfileService.shared.meProfile(),
           let code = profile.countryCode?.uppercased(), !code.isEmpty {
            ContentCache.shared.setProfile(profile)
            return code
        }
        return nil
    }

    private func currentAuthorID() -> String? {
        if let userID = ContentCache.shared.cachedProfile()?.userID, !userID.isEmpty {
            return userID
        }
        return AuthService.shared.currentUser?.id
    }

    private func fetchOwnPosts(limit: Int) async -> [CountryPost] {
        guard let userID = currentAuthorID() else { return [] }
        for attempt in 0..<2 {
            do {
                let posts = try await listForAuthor(userID, limit: limit).excludingSparks()
                ContentCache.shared.setPosts(posts, for: .profilePosts)
                return posts
            } catch {
                if attempt == 0 {
                    _ = try? await AuthService.shared.ensureValidToken()
                    continue
                }
            }
        }
        return ContentCache.shared.posts(for: .profilePosts) ?? []
    }

    private func fallbackFeedPosts(limit: Int) async -> [CountryPost] {
        var batches: [[CountryPost]] = []

        let own = await fetchOwnPosts(limit: limit)
        if !own.isEmpty { batches.append(own) }

        let home = await fetchHomeCountryPosts(limit: limit)
        if !home.isEmpty { batches.append(home) }

        if batches.isEmpty, let cached = ContentCache.shared.posts(for: .profilePosts) {
            batches.append(cached)
        }

        if batches.isEmpty, let code = await resolvedHomeCountryCode() {
            let retry = (try? await listByCountry(code, limit: limit)) ?? []
            if !retry.isEmpty { batches.append(retry) }
        }

        guard !batches.isEmpty else { return [] }
        return mergeFeedSources(batches, limit: limit)
    }

    private func fallbackGlobalPosts(limit: Int) async -> [CountryPost] {
        await fallbackFeedPosts(limit: limit)
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
                    guard !seen.contains(post.id), !post.isStory else { continue }
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

    private func uploadVideoThumbnail(
        from videoFileURL: URL,
        prefetchedImage: UIImage?
    ) async throws -> String? {
        let image: UIImage?
        if let prefetchedImage {
            image = prefetchedImage
        } else {
            image = await VideoCompressionService.shared.generateThumbnail(from: videoFileURL)
        }
        guard let image,
              let data = image.jpegData(compressionQuality: 0.82)
        else { return nil }

        let upload = try await MediaService.shared.uploadPostMedia(
            data: data,
            fileExtension: "jpg",
            mimeType: "image/jpeg"
        )
        return upload.publicURL
    }
}

enum PostsServiceError: LocalizedError {
    case momentCannotBeSharedAsPost

    var errorDescription: String? {
        switch self {
        case .momentCannotBeSharedAsPost:
            "Moments live in Globe — they can't be shared as feed posts."
        }
    }
}