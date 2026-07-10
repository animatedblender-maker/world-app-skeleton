import SwiftUI

struct ReelsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let country: Country

    @State private var posts: [CountryPost] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var activeIndex = 0
    @State private var scrollPosition: Int?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView("Loading reels…").tint(.white)
            } else if let errorMessage {
                ContentUnavailableView("Reels unavailable", systemImage: "video.slash", description: Text(errorMessage))
            } else if posts.isEmpty {
                ContentUnavailableView("No videos yet", systemImage: "video", description: Text("No reels for \(country.name) yet."))
            } else {
                GeometryReader { geometry in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 0) {
                            ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                                ReelCard(
                                    post: post,
                                    country: country,
                                    isActive: activeIndex == index
                                )
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .id(index)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $scrollPosition)
                    .onChange(of: scrollPosition) { _, newValue in
                        guard let newValue else { return }
                        activeIndex = newValue
                    }
                }
                .ignoresSafeArea()
            }

            VStack {
                HStack {
                    Button("Back") { dismiss() }
                        .foregroundStyle(.white)
                    Spacer()
                    Text(country.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 44)
                }
                .padding()
                Spacer()
            }
        }
        .task {
            await load()
            scrollPosition = 0
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            posts = try await PostsService.shared.videoPosts(for: country)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ReelCard: View {
    @Environment(AppState.self) private var appState
    let post: CountryPost
    let country: Country
    let isActive: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let url = post.playableVideoURL {
                VideoPlayerView(
                    url: url,
                    posterURL: post.posterImageURL,
                    placement: "reel",
                    countryCode: country.iso,
                    contentCountryCode: post.countryCode ?? country.iso,
                    postID: post.id,
                    isActive: isActive,
                    loops: true,
                    muted: false
                )
                .ignoresSafeArea()
            }

            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    if let username = post.author?.username {
                        appState.navigate(to: .publicProfile(username: username))
                    }
                } label: {
                    HStack {
                        AvatarView(url: post.author?.avatarURL, seed: post.authorID, size: 36)
                        Text(post.author?.displayName ?? "Member")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)

                Text(post.displayCaption ?? post.displayHeadline)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(4)

                HStack {
                    Label("\(post.likeCount)", systemImage: "heart")
                    Label("\(post.commentCount)", systemImage: "bubble.right")
                    Spacer()
                    Button("Open post") {
                        appState.navigate(to: .post(post.id))
                    }
                    .font(.caption.weight(.bold))
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
            }
            .padding(20)
            .padding(.bottom, 40)
        }
    }
}