import SwiftUI

struct AnonymousInboxView: View {
    @State private var store = AnonymousStore.shared

    var body: some View {
        Group {
            if store.inboxLoading && store.inbox.isEmpty {
                AnonymousLoadingSkeleton()
            } else if store.inbox.isEmpty {
                VStack(spacing: 18) {
                    AnonymousEmptyState(
                        title: MatteryaCopy.anonymousInboxTitle,
                        message: MatteryaCopy.anonymousInboxBody,
                        systemImage: "tray"
                    )
                    Text(MatteryaCopy.anonymousInboxPrivacyNote)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 40)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.inbox) { item in
                            inboxRow(item)
                        }
                    }
                    .padding(Theme.pagePadding)
                    .padding(.bottom, 28)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await store.refreshInbox() }
        .task { await store.loadInbox() }
    }

    private func inboxRow(_ item: AnonymousNotification) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(item.isUnread ? Theme.ink : Theme.matteDeep)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(item.displayBody)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(3)
                if let space = item.spaceTitle, !space.isEmpty {
                    Text(space)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            Spacer(minLength: 0)
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
