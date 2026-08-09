import SwiftUI

struct SearchView: View {
    @Environment(AppState.self) private var appState

    @State private var query = ""
    @State private var profiles: [Profile] = []
    @State private var content: [CountryPost] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searchGeneration = 0

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField

            if isSearching {
                ProgressView().tint(Theme.accentBright).padding()
                Spacer()
            } else if normalizedQuery.isEmpty {
                emptyPrompt
            } else {
                resultsList
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.surface, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Search")
                    .font(.headline.weight(.semibold))
            }
        }
        .task {
            appState.searchPrefersCountries = false
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.inkMuted)
            TextField("Search people and content…", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Theme.ink)
                .onSubmit { Task { await runSearch() } }
            if !query.isEmpty {
                Button {
                    query = ""
                    profiles = []
                    content = []
                    searchError = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
        .shadow(color: Theme.ink.opacity(0.04), radius: 12, y: 4)
        .padding(Theme.pagePadding)
        .onChange(of: query) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                profiles = []
                content = []
                searchError = nil
                return
            }
            Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                if query == newValue { await runSearch() }
            }
        }
    }

    private var emptyPrompt: some View {
        ContentUnavailableView(
            "Search Matterya",
            systemImage: "magnifyingglass",
            description: Text("Find people and posts, Sparks, and videos.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsList: some View {
        Group {
            if let searchError, profiles.isEmpty && content.isEmpty {
                ContentUnavailableView("Search failed", systemImage: "magnifyingglass", description: Text(searchError))
            } else if profiles.isEmpty && content.isEmpty {
                ContentUnavailableView(
                    "No results",
                    systemImage: "text.magnifyingglass",
                    description: Text("Try another person or keyword.")
                )
            } else {
                List {
                    if !profiles.isEmpty {
                        Section("People") {
                            ForEach(profiles) { profile in
                                HStack {
                                    profileRow(profile)
                                    Spacer()
                                    if !profile.isDemoUser, profile.userID != appState.currentProfile?.userID {
                                        FollowButton(userID: profile.userID)
                                    }
                                }
                            }
                        }
                    }

                    if !content.isEmpty {
                        Section("Content") {
                            ForEach(content) { post in
                                contentRow(post)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Theme.canvas)
            }
        }
    }

    private func contentRow(_ post: CountryPost) -> some View {
        Button {
            appState.openPost(post)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                contentThumbnail(post)

                VStack(alignment: .leading, spacing: 6) {
                    Text(post.authorDisplayName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.ink)

                    if let headline = post.displayHeadline {
                        Text(headline)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                    }

                    let excerpt = post.displayExcerpt
                    if !excerpt.isEmpty, !post.hasVideo {
                        Text(excerpt)
                            .font(.caption)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 8) {
                        if let country = post.countryName ?? post.countryCode?.uppercased() {
                            Text(country)
                                .font(.caption2)
                                .foregroundStyle(Theme.inkMuted)
                        }
                        Text(RelativeTime.format(post.createdAt))
                            .font(.caption2)
                            .foregroundStyle(Theme.inkMuted)
                        if post.hasVideo {
                            Text(post.isReel ? MatteryaCopy.spark : "Video")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.inkMuted)
                        } else if post.hasImage {
                            Text("Photo")
                                .font(.caption2)
                                .foregroundStyle(Theme.inkMuted)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func contentThumbnail(_ post: CountryPost) -> some View {
        // Videos: eye-friendly 16:9 preview. Text/photo: compact square.
        if post.hasVideo {
            let w: CGFloat = post.isReel ? 72 : 128
            let h: CGFloat = post.isReel ? 128 : 72
            YouTubeVideoThumbnail(
                post: post,
                maxPixelSize: 360,
                showsPlayIcon: false,
                frameStyle: .card,
                extractFrameIfNeeded: false,
                showsHubBadge: false
            )
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if let url = post.feedImageURL ?? post.resolvedImageURL {
            CachedAsyncImage(url: url, maxPixelSize: 160, contentMode: .fill)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.canvasMuted)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "text.alignleft")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                }
        }
    }

    private func profileRow(_ profile: Profile) -> some View {
        HStack(spacing: 12) {
            Button {
                appState.openPublicProfile(username: profile.username, userID: profile.userID)
            } label: {
                HStack(spacing: 12) {
                    AvatarView(url: profile.avatarURL, seed: profile.userID, size: 40)
                    VStack(alignment: .leading) {
                        Text(profile.displayName ?? profile.username ?? "User")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        if let username = profile.username {
                            Text("@\(username)")
                                .font(.caption)
                                .foregroundStyle(Theme.inkMuted)
                        } else if let country = profile.countryName {
                            Text(country)
                                .font(.caption)
                                .foregroundStyle(Theme.inkMuted)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                appState.openPlayChannel(
                    authorID: profile.userID,
                    username: profile.username
                )
            } label: {
                Image(systemName: "globe.americas")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentBright)
                    .frame(width: 32, height: 32)
                    .background(Theme.accentSoft, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(MatteryaCopy.matteryaHubs) channel")
        }
    }

    private func runSearch() async {
        let trimmed = normalizedQuery
        guard !trimmed.isEmpty else { return }

        let generation = searchGeneration + 1
        searchGeneration = generation
        isSearching = true
        searchError = nil
        defer {
            if searchGeneration == generation {
                isSearching = false
            }
        }

        // Return values from concurrent tasks (do not mutate captured vars — Swift 6).
        async let peopleOutcome: Result<[Profile], Error> = {
            do {
                return .success(
                    try await ProfileService.shared.searchProfiles(
                        trimmed,
                        limit: MatteryaSearchEngine.peopleLimit
                    )
                )
            } catch {
                return .failure(error)
            }
        }()

        async let contentOutcome: Result<[CountryPost], Error> = {
            do {
                return .success(
                    try await PostsService.shared.searchPosts(
                        trimmed,
                        limit: MatteryaSearchEngine.contentLimit
                    )
                )
            } catch {
                return .failure(error)
            }
        }()

        let peopleResult = await peopleOutcome
        let contentResult = await contentOutcome
        guard searchGeneration == generation else { return }

        var errors: [String] = []
        switch peopleResult {
        case .success(let loaded):
            profiles = loaded
        case .failure(let error):
            profiles = []
            errors.append(error.localizedDescription)
        }
        switch contentResult {
        case .success(let loaded):
            content = loaded
        case .failure(let error):
            content = []
            errors.append(error.localizedDescription)
        }

        if profiles.isEmpty && content.isEmpty, !errors.isEmpty {
            searchError = errors.first
        }
    }
}
