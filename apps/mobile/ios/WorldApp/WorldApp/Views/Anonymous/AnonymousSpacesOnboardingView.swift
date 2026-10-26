import SwiftUI

/// First-time Masquerade step: pick Spaces to join, or Skip.
struct AnonymousSpacesOnboardingView: View {
    @State private var store = AnonymousStore.shared
    @State private var joiningIds: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            footer
        }
        .background(Theme.canvas)
        .task {
            if store.spacesOnboardingCandidates.isEmpty {
                await store.loadSpaces(filter: .forYou, force: true)
                await store.loadSpaces(filter: .popular, force: true)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(MatteryaCopy.anonymousSpacesOnboardingTitle)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text(MatteryaCopy.anonymousSpacesOnboardingBody)
                .font(.body)
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 28)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var content: some View {
        let spaces = store.spacesOnboardingCandidates
        let loading = (store.spacesLoading[.forYou] == true || store.spacesLoading[.popular] == true)
            && spaces.isEmpty

        if loading {
            AnonymousLoadingSkeleton()
        } else if spaces.isEmpty {
            AnonymousEmptyState(
                title: MatteryaCopy.anonymousNoSpaces,
                message: MatteryaCopy.anonymousNoSpacesBody,
                systemImage: "square.stack.3d.up"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(spaces) { space in
                        onboardingCard(space)
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 12)
            }
        }
    }

    private func onboardingCard(_ space: AnonymousSpace) -> some View {
        let joined = space.isJoined == true
        let busy = joiningIds.contains(space.id)

        return VStack(alignment: .leading, spacing: 10) {
            AnonymousSpaceCard(space: space)

            Button {
                guard !joined, !busy else { return }
                Task { await join(space) }
            } label: {
                Text(joined ? "Joined" : (busy ? "Joining…" : "Join"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(joined ? Theme.inkMuted : Theme.surface)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                            .fill(joined ? Theme.matteDeep : Theme.ink)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                            .stroke(Theme.border, lineWidth: joined ? 0.5 : 0)
                    )
            }
            .buttonStyle(.plain)
            .disabled(joined || busy)
            .accessibilityLabel(joined ? "Joined \(space.title)" : "Join \(space.title)")
        }
    }

    private var footer: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                store.completeSpacesOnboarding()
            } label: {
                Text("Skip")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skip joining Spaces")
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .background(Theme.canvas.opacity(0.96))
        .overlay(alignment: .top) {
            Theme.divider.frame(height: 0.5)
        }
    }

    private func join(_ space: AnonymousSpace) async {
        joiningIds.insert(space.id)
        defer { joiningIds.remove(space.id) }
        _ = await store.joinSpace(space)
    }
}
