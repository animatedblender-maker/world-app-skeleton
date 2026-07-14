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
    @State private var busy = false

    private var isFollowing: Bool { appState.isFollowing(userID) }

    var body: some View {
        Button {
            Task {
                busy = true
                await appState.toggleFollow(userID)
                busy = false
            }
        } label: {
            Text(isFollowing ? "Following" : "Follow")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    isFollowing ? Theme.surfaceMuted : Theme.accentBright,
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(isFollowing ? Theme.border : Color.clear, lineWidth: 0.5)
                )
                .foregroundStyle(isFollowing ? Theme.inkSecondary : .white)
        }
        .disabled(busy)
    }
}