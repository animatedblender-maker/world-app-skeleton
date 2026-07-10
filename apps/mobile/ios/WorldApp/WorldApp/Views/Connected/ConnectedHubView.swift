import SwiftUI

struct ConnectedHubView: View {
    @Environment(AppState.self) private var appState

    @State private var accounts: [ConnectedAccount] = []
    @State private var nowPlaying: [YourNowPlaying] = []
    @State private var friends: [FriendActivity] = []
    @State private var momentRooms: [MomentRoom] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedMoment: MomentRoom?
    @State private var statusPlatform: StreamingPlatform?
    @State private var platformAction: ConnectedAccount?

    private let teasers = ConnectedHubContent.ecosystemTeasers

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header

                Group {
                    if isLoading && accounts.isEmpty {
                        ProgressView("Loading Living…")
                            .tint(Theme.accent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let errorMessage, accounts.isEmpty {
                        ContentUnavailableView(
                            "Living unavailable",
                            systemImage: "dot.radiowaves.left.and.right",
                            description: Text(errorMessage)
                        )
                    } else {
                        hubScroll
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .screenBackground()
        }
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await syncAppleMusicIfNeeded()
            await loadHub(showSpinner: false)
        }
        .task {
            await loadHub(showSpinner: true)
            await startAppleMusicAutoSync()
        }
        .task {
            await pollFriendsLive()
        }
        .onDisappear {
            AppleMusicNowPlayingService.shared.stopAutoSync()
        }
        .sheet(item: $selectedMoment) { room in
            MomentRoomSheet(room: room) {
                await loadHub(showSpinner: false)
            }
        }
        .sheet(item: $statusPlatform) { platform in
            UpdateNowPlayingSheet(
                platform: platform,
                existing: nowPlaying.first(where: { $0.platform == platform })
            ) {
                await loadHub(showSpinner: false)
            }
        }
        .confirmationDialog(
            platformAction?.platform.title ?? "Platform",
            isPresented: Binding(
                get: { platformAction != nil },
                set: { if !$0 { platformAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let account = platformAction {
                if account.isLinked {
                    Button(account.sharingEnabled ? "Pause sharing" : "Resume sharing") {
                        Task { await toggleSharing(account) }
                    }
                    if account.platform == .appleMusic {
                        Button("Sync from Apple Music") {
                            Task { await syncAppleMusicIfNeeded(force: true) }
                            platformAction = nil
                        }
                    } else {
                        Button("Update what you're watching") {
                            statusPlatform = account.platform
                            platformAction = nil
                        }
                    }
                    Button("Unlink", role: .destructive) {
                        Task { await unlink(account) }
                    }
                }
                Button("Cancel", role: .cancel) {
                    platformAction = nil
                }
            }
        }
    }

    private var hubScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                linkedPlatformsSection
                yourStatusSection
                friendsLiveSection
                momentRoomsSection
                comingSoonSection
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                MenuToolbarButton()
                    .frame(width: 44, height: 44)

                Spacer()

                Button {
                    appState.navigate(to: .search)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Living")
                        .font(.system(size: 28, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.ink)

                    if !nowPlaying.filter(\.isSharing).isEmpty {
                        Circle()
                            .fill(Theme.success)
                            .frame(width: 8, height: 8)
                    }
                }

                Text("Connect platforms, share status, join moment rooms")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 8)
        }
    }

    private var linkedPlatformsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connected").sectionLabel()
                .padding(.horizontal, Theme.pagePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(accounts) { account in
                        Button {
                            handlePlatformTap(account)
                        } label: {
                            PlatformChip(account: account)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
            }
        }
    }

    private var yourStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            yourStatusHeader
            yourStatusContent
        }
    }

    private var yourStatusHeader: some View {
        HStack {
            Text("Your status").sectionLabel()
            Spacer()
            yourStatusActionButton
        }
        .padding(.horizontal, Theme.pagePadding)
    }

    @ViewBuilder
    private var yourStatusActionButton: some View {
        if accounts.contains(where: { $0.platform == .appleMusic && $0.isLinked }) {
            Button("Sync Music") {
                Task { await syncAppleMusicIfNeeded(force: true) }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.trailing, Theme.pagePadding)
        } else if accounts.contains(where: { $0.isLinked && $0.platform != .appleMusic }) {
            Button("Share") {
                statusPlatform = accounts.first(where: { $0.isLinked && $0.platform != .appleMusic })?.platform ?? .netflix
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.trailing, Theme.pagePadding)
        }
    }

    @ViewBuilder
    private var yourStatusContent: some View {
        if nowPlaying.isEmpty {
            emptyCard(
                icon: "play.circle",
                title: "Nothing shared yet",
                detail: "Link Apple Music to auto-share from the Music app, or link Netflix to share manually."
            )
        } else {
            VStack(spacing: 12) {
                ForEach(nowPlaying) { item in
                    NowPlayingStatusRow(item: item) {
                        statusPlatform = item.platform
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
        }
    }

    private var friendsLiveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Friends live").sectionLabel()
                Spacer()
                if !friends.isEmpty {
                    Text("\(friends.filter(\.isLive).count) online")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                        .padding(.trailing, Theme.pagePadding)
                }
            }
            .padding(.horizontal, Theme.pagePadding)

            if friends.isEmpty {
                emptyCard(
                    icon: "person.2",
                    title: "No friend activity",
                    detail: "When people you follow share what they're streaming, it shows up here."
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(friends) { friend in
                            FriendLiveSessionCard(friend: friend) {
                                await joinFriendSession(friend)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                }
            }
        }
    }

    private var momentRoomsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Moment rooms").sectionLabel()
                .padding(.horizontal, Theme.pagePadding)

            if momentRooms.isEmpty {
                emptyCard(
                    icon: "bubble.left.and.bubble.right",
                    title: "No active moments",
                    detail: "Moment rooms appear when you and friends are at the same point in a show or track."
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(momentRooms) { room in
                        Button {
                            selectedMoment = room
                        } label: {
                            MomentRoomCard(room: room)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
            }
        }
    }

    private var comingSoonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coming soon").sectionLabel()
                .padding(.horizontal, Theme.pagePadding)

            VStack(spacing: 10) {
                ForEach(Array(teasers.enumerated()), id: \.offset) { _, teaser in
                    TeaserRow(icon: teaser.0, text: teaser.1)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
        }
    }

    private func emptyCard(icon: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.inkMuted)
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
        .padding(.horizontal, Theme.pagePadding)
    }

    private func loadHub(showSpinner: Bool) async {
        if showSpinner { isLoading = true }
        errorMessage = nil
        defer { isLoading = false }

        do {
            let snapshot = try await StreamingHubService.shared.loadHub()
            accounts = ConnectedHubContent.mergedAccounts(snapshot.accounts)
            nowPlaying = snapshot.nowPlaying
            friends = snapshot.friends
            momentRooms = snapshot.momentRooms
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handlePlatformTap(_ account: ConnectedAccount) {
        guard account.platform.isAvailable else { return }
        if account.isLinked {
            platformAction = account
        } else {
            Task { await link(account) }
        }
    }

    private func link(_ account: ConnectedAccount) async {
        do {
            if account.platform == .appleMusic {
                try await AppleMusicNowPlayingService.shared.requestAuthorization()
            }
            _ = try await StreamingHubService.shared.linkPlatform(account.platform)
            await loadHub(showSpinner: false)
            if account.platform == .appleMusic {
                await syncAppleMusicIfNeeded(force: true)
                await startAppleMusicAutoSync()
            } else {
                statusPlatform = account.platform
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func unlink(_ account: ConnectedAccount) async {
        platformAction = nil
        do {
            if account.platform == .appleMusic {
                AppleMusicNowPlayingService.shared.stopAutoSync()
            }
            try await StreamingHubService.shared.unlinkPlatform(account.platform)
            await loadHub(showSpinner: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleSharing(_ account: ConnectedAccount) async {
        platformAction = nil
        do {
            _ = try await StreamingHubService.shared.setPlatformSharing(
                account.platform,
                enabled: !account.sharingEnabled
            )
            await loadHub(showSpinner: false)
            if account.platform == .appleMusic {
                await startAppleMusicAutoSync()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startAppleMusicAutoSync() async {
        guard let account = accounts.first(where: {
            $0.platform == .appleMusic && $0.isLinked && $0.sharingEnabled
        }) else {
            AppleMusicNowPlayingService.shared.stopAutoSync()
            return
        }

        _ = try? await AppleMusicNowPlayingService.shared.readCurrentPlayback()
        AppleMusicNowPlayingService.shared.startAutoSync(sharingEnabled: account.sharingEnabled) {
            await loadHub(showSpinner: false)
        }
    }

    private func pollFriendsLive() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { break }
            if let refreshed = try? await StreamingHubService.shared.fetchFriendsActivityOnly() {
                friends = refreshed
            }
        }
    }

    private func joinFriendSession(_ friend: FriendActivity) async {
        guard friend.platform == .appleMusic,
              let contentId = friend.contentId else {
            errorMessage = "This session can't be joined yet."
            return
        }

        do {
            try await AppleMusicNowPlayingService.shared.joinSession(
                contentId: contentId,
                progressMs: friend.liveState.liveProgressMs
            )
            await loadHub(showSpinner: false)
            await startAppleMusicAutoSync()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncAppleMusicIfNeeded(force: Bool = false) async {
        guard let account = accounts.first(where: { $0.platform == .appleMusic && $0.isLinked }) else {
            return
        }

        do {
            if force {
                _ = try await AppleMusicNowPlayingService.shared.syncNowPlayingToHub(
                    sharingEnabled: account.sharingEnabled,
                    force: true
                )
                await loadHub(showSpinner: false)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Components

private struct NowPlayingStatusRow: View {
    let item: YourNowPlaying
    let onEdit: () -> Void

    var body: some View {
        if item.platform == .appleMusic {
            LivePlaybackCard(resolveState: {
                AppleMusicNowPlayingService.shared.liveStateForDisplay(fallback: item)
            })
        } else {
            Button(action: onEdit) {
                LivePlaybackCard(resolveState: { item.liveState })
            }
            .buttonStyle(.plain)
        }
    }
}

private struct PlatformChip: View {
    let account: ConnectedAccount

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: account.platform.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(account.isLinked ? account.platform.accent : Theme.inkMuted)

            VStack(alignment: .leading, spacing: 1) {
                Text(account.platform.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(account.isLinked ? Theme.ink : Theme.inkMuted)

                if account.isLinked {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 9))
                        Text(account.sharingEnabled ? "Sharing live" : "Linked")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(account.sharingEnabled ? Theme.success : Theme.inkSecondary)
                } else if account.platform == .appleMusic {
                    Text("Reads Music app")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.accent)
                } else if account.platform.isAvailable {
                    Text("Tap to link")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.accent)
                } else {
                    Text("Soon")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(account.isLinked ? Theme.border : Theme.divider, lineWidth: 0.5)
        )
        .opacity(account.platform.isAvailable ? 1 : 0.6)
    }
}

private struct NowPlayingCard: View {
    let item: YourNowPlaying

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.accentSoft)
                        .frame(width: 44, height: 44)

                    Image(systemName: item.platform.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)

                    Text(item.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }

                Spacer()

                if item.isSharing {
                    Text("Live")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.success)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.success.opacity(0.12), in: Capsule())
                }
            }

            if let moment = item.momentLabel {
                Text(moment)
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(2)
            }

            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.divider)
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: geo.size.width * item.progress)
                    }
                }
                .frame(height: 4)

                HStack {
                    Text(item.progressLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.inkMuted)
                    Spacer()
                    Text("\(Int(item.progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
        }
        .padding(14)
        .hubCard()
    }
}

private struct FriendActivityCard: View {
    let friend: FriendActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(url: friend.avatarURL, seed: friend.avatarSeed, size: 36)

                    if friend.isLive {
                        Circle()
                            .fill(Theme.success)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Theme.surface, lineWidth: 2))
                            .offset(x: 2, y: 2)
                    }
                }

                Text(friend.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: friend.platform.icon)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.accent)
                    Text(friend.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                }

                Text(friend.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 148)
        .padding(12)
        .hubCard()
    }
}

private struct MomentRoomCard: View {
    let room: MomentRoom

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: room.platform.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.accent)

                        Text(room.showTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                    }

                    Text("\(room.episodeLabel) · \(room.timestamp)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.inkSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(room.activeFriends)")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text("here now")
                        .font(.caption2)
                        .foregroundStyle(Theme.inkMuted)
                }
            }

            HeatBar(value: room.heat)

            if !room.previewComments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(room.previewComments.prefix(2)) { comment in
                        HStack(alignment: .top, spacing: 6) {
                            Text(comment.author)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.inkSecondary)
                            Text(comment.body)
                                .font(.caption)
                                .foregroundStyle(Theme.ink)
                                .lineLimit(2)
                        }
                    }
                }
            }

            HStack {
                Text("Join moment room")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .padding(14)
        .hubCard()
    }
}

private struct HeatBar: View {
    let value: Double

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.accent)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.divider)
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: geo.size.width * value)
                }
            }
            .frame(height: 4)

            Text(value > 0.8 ? "Hot" : "Active")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary)
        }
    }
}

private struct TeaserRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.inkMuted)
                .frame(width: 32)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(14)
        .background(Theme.canvasMuted, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }
}

private extension View {
    func hubCard() -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
    }
}