import SwiftUI

struct AnonymousSpacesDirectoryView: View {
    var onCreate: () -> Void
    @State private var store = AnonymousStore.shared
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                filterBar
                content
            }
            .navigationDestination(for: String.self) { slug in
                AnonymousSpaceDetailView(slug: slug)
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AnonymousSpaceFilter.allCases) { filter in
                    Button {
                        withAnimation(MatteryaMotion.snappy) {
                            store.activeSpaceFilter = filter
                        }
                        Task { await store.loadSpaces(filter: filter) }
                    } label: {
                        Text(filter.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(store.activeSpaceFilter == filter ? Theme.surface : Theme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(store.activeSpaceFilter == filter ? Theme.ink : Theme.matteDeep)
                            )
                            .overlay(
                                Capsule().stroke(Theme.border, lineWidth: store.activeSpaceFilter == filter ? 0 : 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onCreate) {
                    Text("Create Space")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .overlay(Capsule().stroke(Theme.ink, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var content: some View {
        let filter = store.activeSpaceFilter
        let spaces = store.spacesByFilter[filter] ?? []
        let loading = store.spacesLoading[filter] == true

        if loading && spaces.isEmpty {
            AnonymousLoadingSkeleton()
        } else if spaces.isEmpty {
            AnonymousEmptyState(
                title: emptyTitle(for: filter),
                message: emptyMessage(for: filter),
                systemImage: "square.stack.3d.up",
                actionTitle: filter == .joined ? nil : "Create Space",
                action: filter == .joined ? nil : onCreate
            )
            .refreshable { await store.refreshSpaces() }
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(spaces) { space in
                        Button {
                            path.append(space.slug)
                        } label: {
                            AnonymousSpaceCard(space: space)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.pagePadding)
            }
            .refreshable { await store.refreshSpaces() }
        }
    }

    private func emptyTitle(for filter: AnonymousSpaceFilter) -> String {
        switch filter {
        case .joined: return MatteryaCopy.anonymousNoJoinedSpaces
        case .paid: return MatteryaCopy.anonymousPaidComingSoonTitle
        default: return MatteryaCopy.anonymousNoSpaces
        }
    }

    private func emptyMessage(for filter: AnonymousSpaceFilter) -> String {
        switch filter {
        case .joined: return MatteryaCopy.anonymousNoJoinedSpacesBody
        case .paid: return MatteryaCopy.anonymousPaidComingSoonBody
        default: return MatteryaCopy.anonymousNoSpacesBody
        }
    }
}

struct AnonymousSpaceCard: View {
    let space: AnonymousSpace

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.matteDeep)
                        .frame(width: 44, height: 44)
                    Text(String(space.title.prefix(1)).uppercased())
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(space.title)
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        if space.isPaid {
                            Text("Paid")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Theme.matte, in: Capsule())
                                .overlay(Capsule().stroke(Theme.border, lineWidth: 0.5))
                        }
                    }
                    Text("a/\(space.slug)")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: 0)
            }

            if let description = space.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(3)
            }

            HStack(spacing: 12) {
                if let count = space.memberCount {
                    Text("\(count.formatted()) members")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                if let owner = space.ownerUsername {
                    Text("·")
                        .foregroundStyle(Theme.inkMuted)
                    Text("@\(owner)")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer()
                if space.isJoined == true {
                    Text("Joined")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                }
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
}
