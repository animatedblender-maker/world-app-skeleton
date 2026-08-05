import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onComplete?()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ToastBanner: View {
    let message: String
    var style: ToastStyle = .info

    enum ToastStyle {
        case info, success, error

        var background: Color {
            switch self {
            case .info: Theme.ink
            case .success: Theme.accent
            case .error: Theme.danger
            }
        }
    }

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(style.background, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
            .padding(.horizontal, 20)
    }
}

struct SharedPostEmbedView: View {
    @Environment(AppState.self) private var appState

    let embed: SharedPostPreview

    var body: some View {
        Group {
            if PlayPlatformBridge.isLongFormVideo(embed.asCountryPost) {
                PlayFeedLinkCard(
                    post: embed.asCountryPost,
                    onOpen: { appState.openPost(embed.asCountryPost) },
                    edgeToEdge: false
                )
                .padding(.horizontal, Theme.pagePadding)
                .padding(.vertical, 8)
            } else {
                standardEmbed
            }
        }
    }

    private var standardEmbed: some View {
        let post = embed.asCountryPost
        let isVideo = embed.hasVideo
        // Same height rules as feed cards: photos use 4:5 capped at maxFeedMediaHeight; videos 16:9 tall.
        let photoAspect = FacebookMediaLayout.aspectRatio(for: post, context: .feed)
            ?? FacebookMediaLayout.photoPortraitAspect

        return Button {
            appState.navigate(to: .post(embed.id))
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    AvatarView(url: embed.author?.avatarURL, seed: embed.authorID, size: 24)
                    Text(embed.author?.displayName ?? embed.author?.username ?? "Member")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.inkMuted)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)

                if embed.hasMedia {
                    Group {
                        if isVideo {
                            VideoThumbnailView(
                                post: post,
                                maxPixelSize: 720,
                                contentMode: .fill,
                                showsPlayIcon: false,
                                playIconSize: 36,
                                placeholder: AnyView(mediaPlaceholder)
                            )
                        } else if let url = embed.feedImageURL {
                            CachedAsyncImage(
                                url: url,
                                maxPixelSize: 720,
                                contentMode: .fill,
                                placeholder: AnyView(mediaPlaceholder)
                            )
                        } else {
                            mediaPlaceholder
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .modifier(SharedEmbedMediaSizeModifier(
                        isVideo: isVideo,
                        photoAspect: photoAspect
                    ))
                    .clipped()
                }

                if !embed.displayExcerpt.isEmpty {
                    Text(embed.displayExcerpt)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(3)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
            }
            .background(Theme.canvasMuted)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 8)
    }

    private var mediaPlaceholder: some View {
        Rectangle()
            .fill(Theme.canvas)
            .overlay {
                Image(systemName: embed.hasVideo ? "video" : "photo")
                    .foregroundStyle(Theme.inkMuted)
            }
    }
}

/// Matches `FeedMediaSizeModifier` so shared photos/videos use the same height caps as feed media.
private struct SharedEmbedMediaSizeModifier: ViewModifier {
    let isVideo: Bool
    let photoAspect: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if isVideo {
            content
                .frame(maxWidth: .infinity)
                .frame(height: FacebookMediaLayout.dominantFeedVideoHeight())
        } else {
            content
                .aspectRatio(photoAspect, contentMode: .fit)
                .frame(maxHeight: FacebookMediaLayout.maxFeedMediaHeight)
        }
    }
}

struct SharePostSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let post: CountryPost

    @State private var showSystemShare = false
    @State private var showMessagePicker = false
    @State private var showRepeatShareConfirm = false
    @State private var busy = false
    @State private var feedback: String?

    private var homeCountryName: String {
        appState.currentProfile?.countryName ?? "your country"
    }

    private var sourceCountryName: String? {
        post.countryName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfWhitespace
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        if let headline = post.displayHeadline {
                            Text(headline)
                                .postHeadlineStyle(lineLimit: 2)
                        }
                        if let sourceCountryName {
                            Text("From \(sourceCountryName)")
                                .font(.caption)
                                .foregroundStyle(Theme.inkMuted)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Outside Matterya") {
                    shareRow("Share anywhere", subtitle: "Messages, Mail, social apps", icon: "square.and.arrow.up", tint: Theme.accentBright) {
                        showSystemShare = true
                    }
                    shareRow("Copy link", subtitle: "Share the public post link", icon: "link", tint: Theme.accent) {
                        ShareService.shared.copyLink(for: .post(post))
                        appState.showToast("Link copied")
                        dismiss()
                    }
                }

                Section("Inside Matterya") {
                    shareRow(
                        MatteryaCopy.shareToYourFeed,
                        subtitle: shareToFeedSubtitle,
                        icon: "globe.americas",
                        tint: Theme.accent
                    ) {
                        if appState.needsRepeatShareWarning(for: post) {
                            showRepeatShareConfirm = true
                        } else {
                            Task { await shareToCountryFeed() }
                        }
                    }
                    shareRow("Send in message", subtitle: "Private chat with a friend", icon: "paperplane", tint: Theme.facebookBlue) {
                        showMessagePicker = true
                    }
                    shareRow("Repost with quote", subtitle: "Write your take on your home feed", icon: "quote.bubble", tint: Theme.ink) {
                        Task { await repostWithQuote() }
                    }
                }

                if let feedback {
                    Section {
                        Text(feedback)
                            .font(.caption)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showSystemShare) {
                ShareSheet(items: ShareService.shared.activityItems(for: .post(post))) {
                    dismiss()
                }
            }
            .confirmationDialog(
                "Share again?",
                isPresented: $showRepeatShareConfirm,
                titleVisibility: .visible
            ) {
                Button("Share Again") {
                    Task { await shareToCountryFeed() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(repeatShareWarningMessage)
            }
            .sheet(isPresented: $showMessagePicker) {
                ShareMessagePickerSheet(post: post) { conversationID in
                    appState.openConversation(id: conversationID)
                    appState.showToast("Sent in message")
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var shareToFeedSubtitle: String {
        if let sourceCountryName, sourceCountryName != homeCountryName {
            return "Adds this \(sourceCountryName) post to \(homeCountryName)"
        }
        return "Posts always land in \(homeCountryName)"
    }

    private var repeatShareWarningMessage: String {
        if let profile = appState.currentProfile,
           let countryCode = appState.homeCountryISO?.uppercased(),
           let postCountry = post.countryCode?.uppercased(),
           postCountry == countryCode,
           post.authorID == profile.userID,
           post.sharedPostID == nil {
            return "This post is already on your feed. Share it again anyway?"
        }
        return "You've shared this post before. Do you still want to add it to your feed again?"
    }

    private func shareRow(
        _ title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer()
            }
        }
        .disabled(busy)
    }

    private func shareToCountryFeed() async {
        busy = true
        defer { busy = false }
        let message = await appState.sharePostToCountryFeed(post)
        appState.showToast(message, style: message.localizedCaseInsensitiveContains("shared") ? .success : .info)
        dismiss()
    }

    private func repostWithQuote() async {
        busy = true
        defer { busy = false }
        guard let home = await appState.resolveHomeCountry() else {
            appState.showToast("Set your home country first", style: .error)
            return
        }
        appState.composerCountry = home
        appState.activeCreateSheet = .post
        appState.quotedSharePostID = post.sharedPostID ?? post.id
        dismiss()
    }
}

struct ShareMessagePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let post: CountryPost
    let onSent: (String) -> Void

    @State private var conversations: [Conversation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var currentUserID: String {
        AuthService.shared.currentUser?.id ?? ""
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading conversations…")
                } else if let errorMessage {
                    ContentUnavailableView("Couldn't load messages", systemImage: "exclamationmark.bubble", description: Text(errorMessage))
                } else if conversations.isEmpty {
                    ContentUnavailableView("No conversations yet", systemImage: "bubble.left.and.bubble.right", description: Text("Start a chat from someone's profile, then share here."))
                } else {
                    List(conversations) { conversation in
                        Button {
                            Task { await send(to: conversation) }
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(
                                    url: conversation.displayAvatarURL(currentUserID: currentUserID),
                                    seed: conversation.id,
                                    size: 40
                                )
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(conversation.displayTitle(currentUserID: currentUserID))
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(Theme.ink)
                                    if let preview = conversation.lastMessage?.body, !preview.isEmpty {
                                        Text(preview)
                                            .font(.caption)
                                            .foregroundStyle(Theme.inkMuted)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Send to…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            conversations = try await MessagesService.shared.listConversations(limit: 60)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func send(to conversation: Conversation) async {
        do {
            try await ShareService.shared.sendPostInMessage(post: post, conversationID: conversation.id)
            onSent(conversation.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension Conversation {
    func displayTitle(currentUserID: String) -> String {
        let other = otherMember(currentUserID: currentUserID)
        return ContentSanitizer.displayName(
            displayName: other?.displayName,
            username: other?.username
        )
    }

    func displayAvatarURL(currentUserID: String) -> String? {
        otherMember(currentUserID: currentUserID)?.avatarURL
    }
}

extension UIApplication {
    var firstKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}

extension View {
    func sharePostSheet(appState: AppState) -> some View {
        sheet(item: Binding(
            get: { appState.sharePostSheet },
            set: { appState.sharePostSheet = $0 }
        )) { post in
            SharePostSheet(post: post)
                .withAppState(appState)
        }
    }
}

extension UIViewController {
    func presentShareSheet(items: [Any]) {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        present(controller, animated: true)
    }

    func topMostViewController() -> UIViewController {
        if let presented = presentedViewController {
            return presented.topMostViewController()
        }
        if let navigation = self as? UINavigationController, let visible = navigation.visibleViewController {
            return visible.topMostViewController()
        }
        if let tab = self as? UITabBarController, let selected = tab.selectedViewController {
            return selected.topMostViewController()
        }
        return self
    }
}

private extension String {
    var nilIfWhitespace: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}