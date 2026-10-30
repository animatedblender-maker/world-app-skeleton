import SwiftUI

struct CreateMenuOverlay: View {
    @Environment(AppState.self) private var appState

    private var isShowing: Bool {
        appState.showCreateMenu || appState.showMasqueradeCreateMenu
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if appState.showCreateMenu {
                Theme.ink.opacity(0.16)
                    .ignoresSafeArea()
                    .onTapGesture { close() }

                CreateMenuPanel()
                    .padding(.bottom, Theme.tabBarHeight)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if appState.showMasqueradeCreateMenu {
                Theme.ink.opacity(0.16)
                    .ignoresSafeArea()
                    .onTapGesture { closeMasquerade() }

                MasqueradeCreatePanel()
                    .padding(.bottom, Theme.tabBarHeight)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.22), value: isShowing)
        .allowsHitTesting(isShowing)
        .zIndex(500)
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.22)) {
            appState.showCreateMenu = false
        }
    }

    private func closeMasquerade() {
        withAnimation(.easeOut(duration: 0.22)) {
            appState.showMasqueradeCreateMenu = false
        }
    }
}

/// Reddit-style create for Masquerade Spaces / posts.
private struct MasqueradeCreatePanel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Theme.border)
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 12)

            HStack {
                Text(MatteryaCopy.anonymousCreateMenuTitle)
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.22)) {
                        appState.showMasqueradeCreateMenu = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            Theme.divider.frame(height: 0.5)

            VStack(spacing: 0) {
                masqueradeCreateRow(
                    title: MatteryaCopy.anonymousCreateSpace,
                    subtitle: "Start a community Space",
                    icon: "plus.rectangle.on.folder"
                ) {
                    withAnimation(.easeOut(duration: 0.22)) {
                        appState.showMasqueradeCreateMenu = false
                        appState.showMasqueradeCreateSpace = true
                    }
                }

                masqueradeCreateRow(
                    title: MatteryaCopy.anonymousCreatePost,
                    subtitle: "Pick a Space and write",
                    icon: "square.and.pencil"
                ) {
                    withAnimation(.easeOut(duration: 0.22)) {
                        appState.showMasqueradeCreateMenu = false
                        appState.selectedTab = .anonymous
                        appState.showMasqueradeCreatePost = true
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 18,
                topTrailingRadius: 18,
                style: .continuous
            )
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 18,
                topTrailingRadius: 18,
                style: .continuous
            )
            .stroke(Theme.border, lineWidth: 0.5)
        )
        .shadow(color: Theme.ink.opacity(0.08), radius: 18, y: -4)
    }

    private func masqueradeCreateRow(
        title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(width: 24)
                    .foregroundStyle(Theme.ink)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

/// Choose a Space, join if needed, then open the Masquerade post composer.
struct AnonymousPostSpacePickerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var store = AnonymousStore.shared
    @State private var joiningSpaceId: String?
    @State private var composerSpace: AnonymousSpace?

    private var candidateSpaces: [AnonymousSpace] {
        var seen = Set<String>()
        var out: [AnonymousSpace] = []
        let pools: [[AnonymousSpace]] = [
            store.spacesByFilter[.joined] ?? [],
            store.spacesByFilter[.forYou] ?? [],
            store.spacesByFilter[.newest] ?? [],
            store.spacesByFilter[.popular] ?? [],
            store.spacesByFilter[.free] ?? [],
        ]
        for pool in pools {
            for space in pool where !space.isPaid {
                if seen.insert(space.id).inserted {
                    out.append(space)
                }
            }
        }
        return out.sorted { lhs, rhs in
            let lj = lhs.isJoined == true
            let rj = rhs.isJoined == true
            if lj != rj { return lj && !rj }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidateSpaces.isEmpty && store.spacesLoading[.joined] == true {
                    ProgressView()
                        .tint(Theme.ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if candidateSpaces.isEmpty {
                    AnonymousEmptyState(
                        title: MatteryaCopy.anonymousNoSpaces,
                        message: "Create a Space first, or pull to refresh the directory.",
                        systemImage: "square.stack.3d.up",
                        actionTitle: MatteryaCopy.anonymousCreateSpace
                    ) {
                        dismiss()
                        appState.showMasqueradeCreateSpace = true
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(candidateSpaces) { space in
                                Button {
                                    Task { await select(space) }
                                } label: {
                                    spaceRow(space)
                                }
                                .buttonStyle(.plain)
                                .disabled(joiningSpaceId != nil)
                            }
                        }
                        .padding(Theme.pagePadding)
                    }
                }
            }
            .screenBackground()
            .navigationTitle(MatteryaCopy.anonymousCreatePost)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.ink)
                }
            }
            .task {
                async let joined: () = store.loadSpaces(filter: .joined, force: false)
                async let forYou: () = store.loadSpaces(filter: .forYou, force: false)
                async let newest: () = store.loadSpaces(filter: .newest, force: false)
                _ = await (joined, forYou, newest)
            }
            .sheet(item: $composerSpace) { space in
                AnonymousComposerView(spaceId: space.id, spaceTitle: space.title)
                    .environment(appState)
            }
            .onChange(of: store.publishEpoch) { _, _ in
                composerSpace = nil
                dismiss()
                appState.showMasqueradeCreatePost = false
            }
        }
    }

    private func spaceRow(_ space: AnonymousSpace) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(space.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                if let description = space.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                HStack(spacing: 8) {
                    if space.isJoined == true {
                        Text("Joined")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.matteDeep, in: Capsule())
                    }
                    if let count = space.memberCount {
                        Text("\(count.formatted()) members")
                            .font(.caption2)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            Spacer(minLength: 0)
            if joiningSpaceId == space.id {
                ProgressView()
                    .tint(Theme.ink)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }

    private func select(_ space: AnonymousSpace) async {
        joiningSpaceId = space.id
        defer { joiningSpaceId = nil }
        let ok = await store.ensureJoined(space)
        if ok {
            var joined = space
            joined.isJoined = true
            composerSpace = joined
        } else if let err = store.consumeError() {
            appState.showToast(err, style: .error)
        }
    }
}

/// Matterya + create sheet (Post / Hubs video / Spark).
private struct CreateMenuPanel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Theme.border)
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 12)

            HStack {
                Text("Create")
                    .font(.system(size: 24, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button { close() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            Theme.divider.frame(height: 0.5)

            VStack(spacing: 0) {
                createRow(
                    title: "Post",
                    subtitle: "Share an update",
                    icon: "square.and.pencil"
                ) {
                    Task { await appState.presentCreateSheet(.post) }
                }

                // Hubs long-form only — channel is created on demand if missing (not for every user).
                createRow(
                    title: "Hubs video",
                    subtitle: "Long-form on \(MatteryaCopy.matteryaHubs)",
                    icon: "film"
                ) {
                    Task { await appState.presentHubVideoCreate() }
                }

                createRow(
                    title: MatteryaCopy.spark,
                    subtitle: MatteryaCopy.sparksOnHubs,
                    icon: "sparkles"
                ) {
                    // Sparks also live on Hubs — require channel the same way.
                    Task { await appState.presentHubSparkCreate() }
                }
                // Moments removed — no create entry.
            }
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 18,
                topTrailingRadius: 18,
                style: .continuous
            )
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 18,
                topTrailingRadius: 18,
                style: .continuous
            )
            .stroke(Theme.border, lineWidth: 0.5)
        )
        .shadow(color: Theme.ink.opacity(0.08), radius: 18, y: -4)
    }

    private func createRow(
        title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(width: 24)
                    .foregroundStyle(Theme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.22)) {
            appState.showCreateMenu = false
        }
    }
}