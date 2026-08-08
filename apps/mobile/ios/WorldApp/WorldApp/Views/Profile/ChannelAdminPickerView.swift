import SwiftUI

/// Search / pick a Matterya member to grant channel admin.
struct ChannelAdminPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let channelID: String
    let existingMemberIDs: Set<String>
    var onAdded: (() -> Void)?

    @State private var query = ""
    @State private var results: [Profile] = []
    @State private var browse: [Profile] = []
    @State private var busy = false
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    private var list: [Profile] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = q.isEmpty ? browse : results
        let me = appState.currentProfile?.userID
        return source.filter { profile in
            if profile.userID == me { return false }
            if existingMemberIDs.contains(profile.userID) { return false }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Theme.inkMuted)
                        TextField("Search by name or username", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: query) { _, _ in
                                scheduleSearch()
                            }
                        if loading {
                            ProgressView().scaleEffect(0.85)
                        }
                    }
                }

                Section {
                    if list.isEmpty, !loading {
                        Text(query.isEmpty
                             ? "No people to show yet."
                             : "No matches for “\(query)”.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkMuted)
                    } else {
                        ForEach(list, id: \.userID) { profile in
                            Button {
                                Task { await add(profile) }
                            } label: {
                                HStack(spacing: 12) {
                                    AvatarView(
                                        url: profile.avatarURL,
                                        seed: profile.userID,
                                        size: 40
                                    )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(profile.displayName ?? profile.username ?? "Member")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Theme.ink)
                                        if let username = profile.username, !username.isEmpty {
                                            Text("@\(username)")
                                                .font(.caption)
                                                .foregroundStyle(Theme.inkMuted)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(Theme.accentBright)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(busy)
                        }
                    }
                } header: {
                    Text(query.isEmpty ? "People on Matterya" : "Results")
                } footer: {
                    Text("Admins can edit the channel, publish as the channel, hide posts, and moderate comments.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Theme.danger)
                    }
                }
            }
            .navigationTitle("Add admin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                await loadBrowse()
            }
            .onDisappear {
                searchTask?.cancel()
            }
        }
    }

    @MainActor
    private func loadBrowse() async {
        loading = true
        defer { loading = false }
        do {
            browse = try await ProfileService.shared.browseProfiles(limit: 40, offset: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            results = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            await runSearch(q)
        }
    }

    @MainActor
    private func runSearch(_ q: String) async {
        loading = true
        defer { loading = false }
        do {
            results = try await ProfileService.shared.searchProfiles(q, limit: 30)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func add(_ profile: Profile) async {
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            _ = try await ChannelsService.shared.addAdmin(
                channelID: channelID,
                userID: profile.userID
            )
            onAdded?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
