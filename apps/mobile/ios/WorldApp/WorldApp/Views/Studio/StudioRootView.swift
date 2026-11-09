import SwiftUI

/// Matterya Studio lite — Dashboard + Content for Hubs channel owners.
struct StudioRootView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case dashboard
        case content
        var id: String { rawValue }
        var title: String {
            switch self {
            case .dashboard: "Dashboard"
            case .content: "Content"
            }
        }
    }

    @State private var loading = true
    @State private var hasChannel = false
    @State private var channel: StudioService.Channel?
    @State private var errorMessage: String?
    @State private var tab: Tab = .dashboard

    var body: some View {
        Group {
            if loading {
                ProgressView("Loading Studio…")
                    .tint(Theme.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasChannel {
                emptyChannel
            } else {
                VStack(spacing: 0) {
                    channelChrome
                    tabPicker
                    Divider().overlay(Theme.border.opacity(0.6))
                    Group {
                        switch tab {
                        case .dashboard:
                            StudioDashboardView()
                        case .content:
                            StudioContentView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .screenBackground()
        .navigationTitle("Studio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .tint(Theme.ink)
        .task { await bootstrap() }
    }

    private var channelChrome: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Matterya Studio")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
                    .textCase(.uppercase)
                if let channel {
                    Text(channel.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        if let handle = channel.handle, !handle.isEmpty {
                            Text("@\(handle)")
                                .font(.caption)
                                .foregroundStyle(Theme.inkMuted)
                        }
                        Text("\(channel.videoCount) videos")
                            .font(.caption)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 12)
    }

    private var tabPicker: some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tab == item ? Theme.paper : Theme.inkSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(tab == item ? Theme.ink : Theme.matte)
                        )
                        .overlay {
                            if tab != item {
                                Capsule(style: .continuous)
                                    .stroke(Theme.border, lineWidth: 0.5)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.bottom, 12)
    }

    private var emptyChannel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Open Matterya Studio")
                .font(.system(size: 26, weight: .regular, design: .serif))
                .foregroundStyle(Theme.ink)
            Text(
                "Studio is for Hubs channel owners — analytics, content, and reach for your videos. Create a channel, publish a Hubs video, then return here."
            )
            .font(.body)
            .foregroundStyle(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
            }

            Button {
                Task { await bootstrap() }
            } label: {
                Text("Try again")
                    .matteryaSecondaryFill()
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(Theme.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @MainActor
    private func bootstrap() async {
        loading = true
        errorMessage = nil
        do {
            let result = try await StudioService.channel()
            hasChannel = result.hasChannel
            channel = result.channel
            if !result.hasChannel {
                errorMessage = nil
            }
        } catch StudioService.StudioError.channelRequired {
            hasChannel = false
            channel = nil
        } catch {
            hasChannel = false
            channel = nil
            errorMessage = error.localizedDescription
        }
        loading = false
    }
}
