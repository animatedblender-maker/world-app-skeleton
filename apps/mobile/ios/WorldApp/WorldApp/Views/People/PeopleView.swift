import SwiftUI

struct PeopleView: View {
    @Environment(AppState.self) private var appState

    @State private var people: [Profile] = []
    @State private var offset = 0
    @State private var hasMore = true
    @State private var isLoading = true
    @State private var loadingMore = false
    @State private var errorMessage: String?

    private let pageSize = 30

    var body: some View {
        List {
            if isLoading && people.isEmpty {
                ProgressView("Loading people…")
            } else if let errorMessage, people.isEmpty {
                ContentUnavailableView("People unavailable", systemImage: "person.2", description: Text(errorMessage))
            } else if people.isEmpty {
                ContentUnavailableView("No people yet", systemImage: "person.2", description: Text("Check back soon for new members."))
            } else {
                ForEach(people) { person in
                    HStack(spacing: 12) {
                        Button {
                            appState.openPublicProfile(username: person.username, userID: person.userID)
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(url: person.avatarURL, seed: person.userID, size: 44)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(person.displayName ?? person.username ?? "Member")
                                        .font(.subheadline.weight(.semibold))
                                    Text("@\(person.username ?? "user") · \(person.countryName ?? "")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if person.userID != appState.currentProfile?.userID, !person.isDemoUser {
                            FollowButton(userID: person.userID)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if hasMore {
                    Button(loadingMore ? "Loading…" : "Load more") {
                        Task { await loadMore() }
                    }
                    .disabled(loadingMore)
                }
            }
        }
        .navigationTitle("People")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await loadInitial() }
    }

    private func loadInitial() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            people = try await ProfileService.shared.browseProfiles(limit: pageSize, offset: 0)
            offset = people.count
            hasMore = people.count >= pageSize
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMore() async {
        loadingMore = true
        defer { loadingMore = false }
        do {
            let batch = try await ProfileService.shared.browseProfiles(limit: pageSize, offset: offset)
            people.append(contentsOf: batch)
            offset += batch.count
            hasMore = batch.count >= pageSize
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct FollowButton: View {
    @Environment(AppState.self) private var appState
    let userID: String
    /// Smaller chip for post-card name rows.
    var compact: Bool = false
    /// White/outline styling for Sparks and other dark video surfaces.
    var onDark: Bool = false
    @State private var busy = false

    private var isFollowing: Bool { appState.isFollowing(userID) }
    private var isSelf: Bool {
        let me = appState.currentProfile?.userID
        return !userID.isEmpty && userID == me
    }

    var body: some View {
        Button {
            guard !busy else { return }
            busy = true
            Task {
                defer { busy = false }
                // Keep Sparks video playing; follow is optimistic + non-blocking.
                await appState.toggleFollow(userID)
            }
        } label: {
            Text(isFollowing ? "Following" : "Follow")
                .font(compact ? .caption2.weight(.bold) : .caption.weight(.bold))
                .padding(.horizontal, compact ? 10 : 14)
                .padding(.vertical, compact ? 4 : 7)
                .background(backgroundFill, in: Capsule())
                .overlay(
                    Capsule().stroke(borderColor, lineWidth: onDark || isFollowing ? 0.5 : 0)
                )
                .foregroundStyle(labelColor)
        }
        .buttonStyle(.plain)
        .disabled(busy || isSelf || userID.isEmpty)
        .opacity(isSelf ? 0 : 1)
        .accessibilityLabel(isFollowing ? "Unfollow" : "Follow")
    }

    private var backgroundFill: Color {
        if onDark {
            return isFollowing ? Color.white.opacity(0.14) : Theme.accentBright
        }
        return isFollowing ? Theme.surfaceMuted : Theme.accentBright
    }

    private var borderColor: Color {
        if onDark {
            return isFollowing ? Color.white.opacity(0.45) : Color.clear
        }
        return isFollowing ? Theme.border : Color.clear
    }

    private var labelColor: Color {
        if onDark {
            return .white
        }
        return isFollowing ? Theme.inkSecondary : .white
    }
}