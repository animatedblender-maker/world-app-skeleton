import PhotosUI
import SwiftUI

/// Channel settings for the creator and admins — manage branding + admins list.
struct ChannelSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let channelID: String

    @State private var channel: HubChannel?
    @State private var members: [ChannelMember] = []
    @State private var name = ""
    @State private var about = ""
    @State private var coverURL: String?
    @State private var coverPickerItem: PhotosPickerItem?
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var showAddAdmin = false
    @State private var memberToRemove: ChannelMember?

    private var isOwner: Bool { channel?.isOwner == true }
    private var isStaff: Bool { channel?.isStaff == true }

    var body: some View {
        NavigationStack {
            List {
                if let channel {
                    Section {
                        LabeledContent("Role") {
                            Text(channel.myRole?.displayTitle ?? "—")
                                .foregroundStyle(Theme.inkMuted)
                        }
                        LabeledContent("Videos") {
                            Text("\(channel.videoCount)")
                                .foregroundStyle(Theme.inkMuted)
                        }
                    } header: {
                        Text("Channel")
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Cover photo")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)

                            ZStack(alignment: .bottomTrailing) {
                                Group {
                                    if let coverURL, let url = URL(string: coverURL), !coverURL.isEmpty {
                                        CachedAsyncImage(
                                            url: url,
                                            maxPixelSize: 900,
                                            contentMode: .fill,
                                            placeholder: AnyView(
                                                Rectangle().fill(Theme.canvasMuted)
                                            )
                                        )
                                    } else {
                                        LinearGradient(
                                            colors: [Theme.accentSoft, Theme.canvasMuted],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                PhotosPicker(selection: $coverPickerItem, matching: .images) {
                                    Label(
                                        coverURL == nil ? "Add cover" : "Change",
                                        systemImage: "camera.fill"
                                    )
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.paper)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(Theme.ink.opacity(0.6), in: Capsule())
                                }
                                .padding(10)
                                .disabled(busy)
                                .onChange(of: coverPickerItem) { _, item in
                                    Task { await uploadCover(item) }
                                }
                            }

                            if coverURL != nil {
                                Button(role: .destructive) {
                                    Task { await clearCover() }
                                } label: {
                                    Text("Remove cover photo")
                                        .font(.caption.weight(.semibold))
                                }
                                .disabled(busy)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Channel name:")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            TextField("Channel name", text: $name)
                                .textInputAutocapitalization(.words)
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))

                        VStack(alignment: .leading, spacing: 6) {
                            Text("About:")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            TextField("About", text: $about, axis: .vertical)
                                .lineLimit(3...8)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))

                        Button {
                            Task { await saveBranding() }
                        } label: {
                            if busy {
                                ProgressView()
                            } else {
                                Text("Save changes")
                                    .fontWeight(.semibold)
                            }
                        }
                        .disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } header: {
                        Text("Branding")
                    } footer: {
                        Text("Creators and admins can edit the cover photo, channel name, and about.")
                    }

                    Section {
                        ForEach(members) { member in
                            HStack(spacing: 12) {
                                AvatarView(
                                    url: member.profile?.avatarURL,
                                    seed: member.userID,
                                    size: 36
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.profile?.displayName
                                         ?? member.profile?.username
                                         ?? "Member")
                                        .font(.subheadline.weight(.semibold))
                                    Text(member.role.displayTitle)
                                        .font(.caption)
                                        .foregroundStyle(Theme.inkMuted)
                                }
                                Spacer()
                                if member.role == .admin, isStaff {
                                    Button(role: .destructive) {
                                        memberToRemove = member
                                    } label: {
                                        Image(systemName: "person.badge.minus")
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Theme.danger)
                                }
                            }
                        }

                        if isStaff {
                            Button {
                                showAddAdmin = true
                            } label: {
                                Label("Add admin", systemImage: "person.badge.plus")
                                    .fontWeight(.semibold)
                            }
                        }
                    } header: {
                        Text("Admins")
                    } footer: {
                        Text("The creator picks admins. Admins can edit the channel, publish as the channel, hide posts, and moderate comments.")
                    }

                    if let statusMessage {
                        Section {
                            Text(statusMessage)
                                .font(.caption)
                                .foregroundStyle(Theme.accentBright)
                        }
                    }
                    if let errorMessage {
                        Section {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(Theme.danger)
                        }
                    }
                } else if busy {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("Loading channel…")
                            Spacer()
                        }
                    }
                } else {
                    Section {
                        Text("Channel not found.")
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            .navigationTitle("Channel settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .sheet(isPresented: $showAddAdmin) {
                ChannelAdminPickerView(
                    channelID: channelID,
                    existingMemberIDs: Set(members.map(\.userID))
                ) {
                    Task { await load() }
                    statusMessage = "Admin added."
                }
                .withAppState(appState)
                .presentationDetents([.medium, .large])
            }
            .confirmationDialog(
                "Remove admin?",
                isPresented: Binding(
                    get: { memberToRemove != nil },
                    set: { if !$0 { memberToRemove = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let member = memberToRemove {
                    Button("Remove \(member.profile?.displayName ?? "admin")", role: .destructive) {
                        Task { await removeAdmin(member) }
                    }
                }
                Button("Cancel", role: .cancel) { memberToRemove = nil }
            }
        }
    }

    @MainActor
    private func load() async {
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            async let ch = ChannelsService.shared.channel(id: channelID)
            async let mem = ChannelsService.shared.members(channelID: channelID)
            let loaded = try await ch
            channel = loaded
            members = try await mem
            if let loaded {
                name = loaded.name
                about = loaded.about ?? ""
                coverURL = loaded.coverURL
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func uploadCover(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else {
            errorMessage = "Could not read photo."
            return
        }
        busy = true
        errorMessage = nil
        statusMessage = nil
        defer {
            busy = false
            coverPickerItem = nil
        }
        do {
            let jpeg = (try? PhotosPickerMediaLoader.normalizeToJPEG(data, quality: 0.78, maxEdge: 1920)) ?? data
            let upload = try await MediaService.shared.uploadPostMedia(
                data: jpeg,
                fileExtension: "jpg",
                mimeType: "image/jpeg"
            )
            let updated = try await ChannelsService.shared.updateChannel(
                id: channelID,
                coverURL: upload.publicURL
            )
            channel = updated
            coverURL = updated.coverURL
            statusMessage = "Cover photo updated."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func clearCover() async {
        busy = true
        errorMessage = nil
        statusMessage = nil
        defer { busy = false }
        do {
            // Empty string clears cover_url on the server.
            let updated = try await ChannelsService.shared.updateChannel(
                id: channelID,
                coverURL: ""
            )
            channel = updated
            coverURL = updated.coverURL
            statusMessage = "Cover photo removed."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func saveBranding() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        busy = true
        errorMessage = nil
        statusMessage = nil
        defer { busy = false }
        do {
            let updated = try await ChannelsService.shared.updateChannel(
                id: channelID,
                name: trimmed,
                about: about.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            channel = updated
            coverURL = updated.coverURL
            statusMessage = "Channel updated."
            // Refresh profile so LivingChannelMarker dual-write is visible.
            if let profile = try? await ProfileService.shared.meProfile() {
                appState.currentProfile = profile
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func removeAdmin(_ member: ChannelMember) async {
        busy = true
        errorMessage = nil
        defer {
            busy = false
            memberToRemove = nil
        }
        do {
            _ = try await ChannelsService.shared.removeAdmin(
                channelID: channelID,
                userID: member.userID
            )
            members = try await ChannelsService.shared.members(channelID: channelID)
            statusMessage = "Admin removed."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
