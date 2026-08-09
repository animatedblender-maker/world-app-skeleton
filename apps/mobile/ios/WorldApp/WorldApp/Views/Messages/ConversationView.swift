import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct ConversationView: View {
    @Environment(AppState.self) private var appState

    let conversation: Conversation

    @State private var messages: [Message]
    @State private var draft = ""
    @State private var isLoading: Bool
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingMediaData: Data?
    @State private var pendingMediaImage: UIImage?
    @State private var scrollToBottomToken = 0
    @State private var replyingTo: Message?
    /// Peer's `last_read_at` — drives Read receipts on my messages.
    @State private var peerLastReadAt: String?

    init(conversation: Conversation) {
        self.conversation = conversation
        // Paint from warm cache immediately — no spinner flash on re-open.
        let cached = MessagesService.shared.cachedMessages(for: conversation.id) ?? []
        _messages = State(initialValue: cached)
        _isLoading = State(initialValue: cached.isEmpty)
        let peerCached = MessagesService.shared.cachedPeerRead(for: conversation.id)
            ?? conversation.otherMember(currentUserID: AuthService.shared.currentUser?.id ?? "")?.lastReadAt
        _peerLastReadAt = State(initialValue: peerCached)
    }
    /// Fixed chat miniplayer (under composer) — long-form / hub shares only.
    @State private var chatMiniShare: Message.ShareInfo?
    @State private var chatMiniPlaying = false
    @State private var chatMiniExpanded = false
    @FocusState private var composerFocused: Bool

    @Bindable private var callManager = CallSessionManager.shared

    private var visibleMessages: [Message] {
        messages
            .filter(\.isRenderableInChat)
            .filter { !HiddenMessagesStore.isHidden(conversationID: conversation.id, messageID: $0.id) }
    }

    /// Latest of my messages the recipient has read (show the "Read" label only here).
    private var lastReadOwnMessageID: String? {
        guard let me = currentUserID,
              let peerLastReadAt,
              let readDate = RelativeTime.parseDate(peerLastReadAt)
        else { return nil }

        return visibleMessages
            .filter { $0.senderID == me && !$0.isCallLog && !$0.id.hasPrefix("pending-") }
            .filter { message in
                guard let created = RelativeTime.parseDate(message.createdAt) else { return false }
                // Small skew so near-simultaneous send/open still counts as read.
                return readDate.timeIntervalSince(created) >= -2
            }
            .last?
            .id
    }

    private var reactionSummaries: [String: MessageReactionSummary] {
        MessageReactionIndex.build(from: messages, currentUserID: currentUserID)
    }

    private var currentUserID: String? {
        AuthService.shared.currentUser?.id
    }

    private var otherMember: PostAuthor? {
        guard let userID = currentUserID else { return nil }
        return conversation.otherMember(currentUserID: userID)
    }

    private var title: String {
        otherMember?.displayName ?? otherMember?.username ?? "Chat"
    }

    private var canSend: Bool {
        pendingMediaData != nil || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Always paint the thread chrome immediately — never a full-screen loader
            // that covers the hubs mini player or freezes open-chat.
            ZStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(visibleMessages) { message in
                                MessageBubble(
                                    message: message,
                                    isMine: message.senderID == currentUserID,
                                    peerLastReadAt: peerLastReadAt,
                                    isLastReadByPeer: message.id == lastReadOwnMessageID,
                                    reactionSummary: reactionSummaries[message.id],
                                    replyAuthorName: replyAuthorName(for: message),
                                    onReply: { replyingTo = message },
                                    onLike: { Task { await toggleMessageLike(message) } },
                                    onReact: { emoji in Task { await reactToMessage(message, emoji: emoji) } },
                                    onUnsend: { Task { await unsendMessage(message) } },
                                    onRemoveLocally: { removeMessageLocally(message) },
                                    onOpenShare: { share in openShareDestination(share) }
                                )
                                .id(message.id)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("chat-bottom")
                        }
                        .padding(Theme.pagePadding)
                    }
                    // iOS 17+: open at the end of the thread (WhatsApp / iMessage style).
                    .defaultScrollAnchor(.bottom)
                    .onAppear {
                        // Immediate + delayed so LazyVStack / async images still land at bottom.
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                    .onChange(of: scrollToBottomToken) { _, _ in
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                    .onChange(of: visibleMessages.last?.id) { _, _ in
                        // New message arrived (send or load) → stay pinned to latest.
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                    .onChange(of: isLoading) { _, loading in
                        if !loading {
                            scrollToBottom(proxy: proxy, animated: false)
                        }
                    }
                }

                if isLoading && visibleMessages.isEmpty {
                    ProgressView()
                        .tint(Theme.accentBright)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxHeight: .infinity)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal)
            }

            // Hubs continuous mini chrome — FIXED under the thread.
            // Video itself stays in GlobalHubPlaybackLayer (embedsVideo: false) so
            // expand/minimize never restarts the AVPlayer.
            if let hubPost = appState.hubPlaybackPost, !appState.hubPlaybackExpanded {
                YouTubeMiniPlayerBar(
                    post: hubPost,
                    onExpand: {
                        appState.expandHubPlayback()
                    },
                    onClose: {
                        appState.stopHubPlayback()
                    },
                    embedsVideo: false,
                    isPlaying: Binding(
                        get: { appState.hubPlaybackPlaying },
                        set: { appState.hubPlaybackPlaying = $0 }
                    ),
                    isMuted: Binding(
                        get: { appState.hubPlaybackMuted },
                        set: { appState.hubPlaybackMuted = $0 }
                    )
                )
                // Video hole reports HubContinuousVideoSlotKey from YouTubeMiniPlayerBar (embedsVideo: false).
                .padding(.bottom, 0)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Optional share-card mini (user-docked) — same fixed band under messages.
            if let share = chatMiniShare, appState.hubPlaybackPost == nil {
                ChatFixedMiniPlayer(
                    share: share,
                    isPlaying: $chatMiniPlaying,
                    isExpanded: $chatMiniExpanded,
                    onClose: {
                        chatMiniPlaying = false
                        chatMiniShare = nil
                        chatMiniExpanded = false
                    },
                    onOpenDestination: {
                        openShareDestination(share)
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            composerBar
        }
        .animation(.easeInOut(duration: 0.22), value: appState.hubPlaybackPost?.id)
        .animation(.easeInOut(duration: 0.22), value: chatMiniShare?.postID)
        .screenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await callManager.startCall(conversationID: conversation.id, kind: .audio, peer: otherMember) }
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(callManager.canStartCall ? Theme.ink : Theme.inkMuted)
                }
                .disabled(!callManager.canStartCall)

                Button {
                    Task { await callManager.startCall(conversationID: conversation.id, kind: .video, peer: otherMember) }
                } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(callManager.canStartCall ? Theme.ink : Theme.inkMuted)
                }
                .disabled(!callManager.canStartCall)
            }
        }
        .task(id: conversation.id) {
            // Keep hubs mini playing for the whole chat session.
            if appState.hubPlaybackPost != nil {
                appState.hubPlaybackPlaying = true
            }
            // Seed from conversation members while the network refresh loads.
            if peerLastReadAt == nil, let me = currentUserID {
                peerLastReadAt = conversation.otherMember(currentUserID: me)?.lastReadAt            }
            // If we already painted from cache, soft-refresh without a blocking spinner.
            await callManager.ensureSignalingReady()
            await loadMessages()
            // Keep read receipts fresh while this chat is open.
            await pollPeerReadReceipts()
        }
        .alert("Call unavailable", isPresented: Binding(
            get: { callManager.errorMessage != nil && !callManager.showUI },
            set: { if !$0 { callManager.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                callManager.errorMessage = nil
            }
        } message: {
            Text(callManager.errorMessage ?? "Calling is unavailable right now.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .conversationMessagesDidChange)) { notification in
            guard let conversationID = notification.userInfo?["conversationId"] as? String,
                  conversationID == conversation.id
            else { return }
            Task {
                await loadMessages()
                await refreshPeerReadReceipt()
                // Light clear only — avoid re-fetching the full notifications list every message.
                await PushNotificationService.shared.clearDeliveredNotifications(
                    forConversation: conversation.id
                )
            }
        }
        .onAppear {
            Task { await refreshPeerReadReceipt() }
        }
        .onDisappear {
            chatMiniPlaying = false
        }
    }

    // MARK: - Share routing (card tap)

    /// Card / arrow → Sparks, Hubs watch, or post. Never autoplay.
    private func openShareDestination(_ share: Message.ShareInfo) {
        chatMiniPlaying = false
        ChatShareRouting.open(share, appState: appState)
    }

    /// Poll peer `last_read_at` so "Read" appears soon after they open the chat.
    private func pollPeerReadReceipts() async {
        while !Task.isCancelled {
            // Gentle interval — aggressive polling made chat feel laggy.
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            await refreshPeerReadReceipt()
        }
    }

    private func refreshPeerReadReceipt() async {
        guard let me = currentUserID else { return }
        guard let refreshed = try? await MessagesService.shared.getConversationById(conversation.id) else {
            return
        }
        let peerRead = refreshed.otherMember(currentUserID: me)?.lastReadAt
        await MainActor.run {
            if peerRead != peerLastReadAt {
                withAnimation(.easeInOut(duration: 0.2)) {
                    peerLastReadAt = peerRead
                }
            }
        }
    }

    /// Always pin the thread to the newest message (open + after load + after send).
    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        let lastID = visibleMessages.last?.id
        func perform() {
            // Prefer last message id (more reliable with LazyVStack than a trailing spacer alone).
            if let lastID {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
            proxy.scrollTo("chat-bottom", anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.15)) { perform() }
        } else {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { perform() }
        }
        // Layout passes after images / network replace — re-pin without animation.
        DispatchQueue.main.async {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { perform() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { perform() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { perform() }
        }
    }

    private func requestScrollToBottom() {
        scrollToBottomToken += 1
    }

    private func replyAuthorName(for message: Message) -> String? {
        guard let targetID = message.replyInfo?.targetID else { return nil }
        if let target = messages.first(where: { $0.id == targetID }) {
            return target.sender?.displayName
                ?? target.sender?.username
                ?? "Message"
        }
        return "Message"
    }

    private var composerBar: some View {
        VStack(spacing: 10) {
            if let replyingTo {
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Theme.accent.opacity(0.45))
                        .frame(width: 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Replying to \(replyingTo.sender?.displayName ?? replyingTo.sender?.username ?? "Message")")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text(replyingTo.previewText)
                            .font(.caption)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Button("Cancel") { self.replyingTo = nil }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, Theme.pagePadding)
            }

            if let pendingMediaImage {
                HStack(spacing: 12) {
                    Image(uiImage: pendingMediaImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Button("Remove", role: .destructive) {
                        clearPendingMedia()
                    }
                    .font(.subheadline.weight(.semibold))

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.pagePadding)
            }

            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "photo")
                        .foregroundStyle(Theme.accentBright)
                        .frame(width: 36, height: 36)
                }
                .onChange(of: selectedPhoto) { _, item in
                    Task { await loadPendingMedia(item) }
                }

                TextField(replyingTo == nil ? "Message…" : "Write a reply…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        composerFocused = false
                        Keyboard.dismiss()
                    }
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.controlRadius)
                            .stroke(Theme.border, lineWidth: 0.5)
                    )

                Button {
                    Task { await sendMessage() }
                } label: {
                    Image(systemName: isSending ? "hourglass" : "paperplane.fill")
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(canSend && !isSending ? Theme.accentBright : Theme.inkMuted, in: Circle())
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .disabled(isSending || !canSend)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, Theme.pagePadding)
        }
        .padding(.top, Theme.pagePadding)
        .background(Theme.surface)
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(Theme.border), alignment: .top)
    }

    private func loadMessages() async {
        let hadLocalMessages = !messages.isEmpty
        // Only block the UI with a spinner on a cold open (no cache / no local rows).
        if !hadLocalMessages {
            await MainActor.run { isLoading = true }
        }
        do {
            async let loadedTask = MessagesService.shared.listMessages(conversationID: conversation.id)
            async let refreshedTask = MessagesService.shared.getConversationById(conversation.id)
            let loaded = try await loadedTask
            let refreshed = try? await refreshedTask
            let peerRead = refreshed?.otherMember(currentUserID: currentUserID ?? "")?.lastReadAt
            await MainActor.run {
                messages = loaded
                if let peerRead { peerLastReadAt = peerRead }
                errorMessage = nil
                isLoading = false
                MessagesService.shared.storeMessages(
                    loaded,
                    peerReadAt: peerRead,
                    for: conversation.id
                )
                // Always land on the latest message when opening / refreshing this chat.
                requestScrollToBottom()
            }
            // Second pass after LazyVStack lays out the full network list.
            try? await Task.sleep(nanoseconds: 80_000_000)
            await MainActor.run { requestScrollToBottom() }
            try? await Task.sleep(nanoseconds: 200_000_000)
            await MainActor.run { requestScrollToBottom() }
            _ = hadLocalMessages
            // listMessages updates last_read_at server-side — drop banners + tab badge for this chat.
            await PushNotificationService.shared.clearDeliveredNotifications(forConversation: conversation.id)
        } catch {
            await MainActor.run {
                // Keep cached messages visible on a soft refresh failure.
                if !hadLocalMessages {
                    errorMessage = error.localizedDescription
                }
                isLoading = false
            }
        }
    }

    private func loadPendingMedia(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else {
                throw MediaError.uploadFailed("Could not read image data.")
            }
            guard let image = UIImage(data: raw), let jpeg = image.jpegData(compressionQuality: 0.86) else {
                throw MediaError.uploadFailed("Could not prepare image for upload.")
            }
            pendingMediaData = jpeg
            pendingMediaImage = UIImage(data: jpeg)
            selectedPhoto = nil
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            clearPendingMedia()
        }
    }

    private func clearPendingMedia() {
        pendingMediaData = nil
        pendingMediaImage = nil
        selectedPhoto = nil
    }

    private func sendMessage() async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }

        let body: String
        if let replyingTo, !trimmed.isEmpty {
            body = Message.buildReplyBody(target: replyingTo, body: trimmed)
        } else {
            body = trimmed
        }

        isSending = true
        errorMessage = nil
        defer { isSending = false }

        let usesPlaceholder = pendingMediaData == nil
        let placeholderID = usesPlaceholder ? "pending-\(UUID().uuidString)" : nil
        if usesPlaceholder, let placeholderID {
            let now = ISO8601DateFormatter().string(from: Date())
            let placeholder = Message(
                id: placeholderID,
                conversationID: conversation.id,
                senderID: currentUserID ?? "",
                body: body,
                mediaType: nil,
                mediaPath: nil,
                mediaURL: nil,
                mediaName: nil,
                createdAt: now,
                updatedAt: now,
                sender: nil
            )
            messages.append(placeholder)
            persistMessageCache()
            requestScrollToBottom()
        }
        draft = ""
        let savedReply = replyingTo
        replyingTo = nil
        composerFocused = false
        Keyboard.dismiss()

        do {
            if let data = pendingMediaData {
                let upload = try await MediaService.shared.uploadMessageMedia(
                    data: data,
                    conversationID: conversation.id,
                    fileName: "image.jpg",
                    mimeType: "image/jpeg"
                )
                let message = try await MessagesService.shared.sendMessage(
                    conversationID: conversation.id,
                    body: body,
                    mediaType: "image",
                    mediaPath: upload.path,
                    mediaName: upload.name,
                    mediaMime: upload.mime,
                    mediaSize: upload.size
                )
                if let placeholderID {
                    replacePendingMessage(id: placeholderID, with: message)
                } else {
                    messages.append(message)
                    persistMessageCache()
                }
                clearPendingMedia()
            } else {
                let message = try await MessagesService.shared.sendMessage(conversationID: conversation.id, body: body)
                if let placeholderID {
                    replacePendingMessage(id: placeholderID, with: message)
                } else {
                    messages.append(message)
                    persistMessageCache()
                }
            }
            notifyConversationChanged()
            requestScrollToBottom()
            if let refreshed = try? await MessagesService.shared.getConversationById(conversation.id) {
                peerLastReadAt = refreshed.otherMember(currentUserID: currentUserID ?? "")?.lastReadAt
                persistMessageCache()
            }
        } catch {
            if let placeholderID {
                messages.removeAll { $0.id == placeholderID }
                persistMessageCache()
            }
            draft = body
            replyingTo = savedReply
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func replacePendingMessage(id: String, with message: Message) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index] = message
        } else {
            messages.append(message)
        }
        persistMessageCache()
    }

    private func persistMessageCache() {
        MessagesService.shared.storeMessages(
            messages,
            peerReadAt: peerLastReadAt,
            for: conversation.id
        )
    }

    private func notifyConversationChanged() {
        persistMessageCache()
        NotificationCenter.default.post(
            name: .conversationMessagesDidChange,
            object: nil,
            userInfo: ["conversationId": conversation.id]
        )
    }

    private func toggleMessageLike(_ message: Message) async {
        let liked = reactionSummaries[message.id]?.likedByMe ?? false
        await sendReaction(to: message, emoji: "❤", active: !liked)
    }

    private func reactToMessage(_ message: Message, emoji: String) async {
        let normalized = MessageReactionIndex.normalizeEmoji(emoji)
        let mine = reactionSummaries[message.id]?.myEmoji
        let active = mine != normalized
        await sendReaction(to: message, emoji: normalized, active: active)
    }

    private func sendReaction(to message: Message, emoji: String, active: Bool) async {
        guard !message.id.hasPrefix("pending-") else { return }
        let body = Message.buildReactionBody(targetID: message.id, emoji: emoji, active: active)
        do {
            let reaction = try await MessagesService.shared.sendMessage(
                conversationID: conversation.id,
                body: body
            )
            messages.append(reaction)
            notifyConversationChanged()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func unsendMessage(_ message: Message) async {
        guard message.senderID == currentUserID, !message.id.hasPrefix("pending-") else { return }
        do {
            let deleted = try await MessagesService.shared.deleteMessage(message.id)
            guard deleted else { return }
            messages.removeAll { $0.id == message.id }
            HiddenMessagesStore.unhide(conversationID: conversation.id, messageID: message.id)
            notifyConversationChanged()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func removeMessageLocally(_ message: Message) {
        HiddenMessagesStore.hide(conversationID: conversation.id, messageID: message.id)
    }
}

private struct MessageReactionSummary {
    var emojiCounts: [String: Int] = [:]
    var likedByMe = false
    var myEmoji: String?
}

private enum MessageReactionIndex {
    static let quickEmojis = ["❤️", "😂", "👍", "😮", "😢", "🔥"]

    static func normalizeEmoji(_ emoji: String) -> String {
        let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "❤️" { return "❤" }
        return trimmed.isEmpty ? "❤" : trimmed
    }

    static func build(from messages: [Message], currentUserID: String?) -> [String: MessageReactionSummary] {
        var perTarget: [String: [String: (emoji: String, state: Int)]] = [:]

        for message in messages {
            guard let reaction = message.reactionInfo else { continue }
            let targetID = reaction.targetID
            let senderID = message.senderID
            guard !targetID.isEmpty, !senderID.isEmpty else { continue }
            perTarget[targetID, default: [:]][senderID] = (
                normalizeEmoji(reaction.emoji),
                reaction.isActive ? 1 : 0
            )
        }

        var result: [String: MessageReactionSummary] = [:]
        for (targetID, userReactions) in perTarget {
            var summary = MessageReactionSummary()
            for (userID, entry) in userReactions where entry.state == 1 {
                summary.emojiCounts[entry.emoji, default: 0] += 1
                if userID == currentUserID {
                    summary.myEmoji = entry.emoji
                    summary.likedByMe = entry.emoji == "❤"
                }
            }
            if !summary.emojiCounts.isEmpty {
                result[targetID] = summary
            }
        }
        return result
    }
}

@MainActor
private enum HiddenMessagesStore {
    private static var storageKey: String {
        "conversation.hiddenMessages.\(AuthService.shared.currentUser?.id ?? "anonymous")"
    }

    static func isHidden(conversationID: String, messageID: String) -> Bool {
        hiddenIDs(for: conversationID).contains(messageID)
    }

    static func hide(conversationID: String, messageID: String) {
        var bucket = load()
        var ids = bucket[conversationID] ?? []
        ids.insert(messageID)
        bucket[conversationID] = ids
        save(bucket)
    }

    static func unhide(conversationID: String, messageID: String) {
        var bucket = load()
        var ids = bucket[conversationID] ?? []
        ids.remove(messageID)
        bucket[conversationID] = ids
        save(bucket)
    }

    private static func hiddenIDs(for conversationID: String) -> Set<String> {
        load()[conversationID] ?? []
    }

    private static func load() -> [String: Set<String>] {
        guard let raw = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: [String]] else {
            return [:]
        }
        return raw.mapValues(Set.init)
    }

    private static func save(_ bucket: [String: Set<String>]) {
        let raw = bucket.mapValues(Array.init)
        UserDefaults.standard.set(raw, forKey: storageKey)
    }
}

private struct MessageBubble: View {
    @Environment(AppState.self) private var appState

    let message: Message
    let isMine: Bool
    let peerLastReadAt: String?
    /// True only for the latest of my messages the recipient has read — shows "Read · time".
    var isLastReadByPeer: Bool = false
    let reactionSummary: MessageReactionSummary?
    let replyAuthorName: String?
    let onReply: () -> Void
    let onLike: () -> Void
    let onReact: (String) -> Void
    let onUnsend: () -> Void
    let onRemoveLocally: () -> Void
    var onOpenShare: ((Message.ShareInfo) -> Void)? = nil

    @State private var resolvedImageURL: URL?
    @State private var showsStatusDetail = false
    @State private var swipeOffset: CGFloat = 0
    @State private var showImageLightbox = false

    var body: some View {
        if message.isCallLog {
            callLogBubble
        } else {
            chatBubble
        }
    }

    private var callLogBubble: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                line
                HStack(spacing: 6) {
                    Image(systemName: callLogIcon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(message.displayText ?? message.previewText)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Theme.inkMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.canvasMuted, in: Capsule())
                line
            }

            if !message.timestampLabel.isEmpty {
                Text(message.timestampLabel)
                    .font(.caption2)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var line: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 0.5)
            .frame(maxWidth: .infinity)
    }

    private var callLogIcon: String {
        guard let log = Message.parseCallLog(message.body) else { return "phone.fill" }
        return log.kind == "video" ? "video.fill" : "phone.fill"
    }

    private var chatBubble: some View {
        ZStack(alignment: isMine ? .trailing : .leading) {
            if swipeOffset < -18 {
                HStack {
                    Spacer()
                    Label("Reply", systemImage: "arrowshape.turn.up.left.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.trailing, 12)
                }
            }

            HStack(alignment: .top, spacing: 0) {
                if isMine { Spacer(minLength: 48) }
                VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                    bubbleContent
                    reactionStrip
                    messageMeta
                        // Status detail toggle lives on the timestamp row only —
                        // never on the whole bubble (that stole share-card taps).
                        .onTapGesture {
                            showsStatusDetail.toggle()
                        }
                        .onTapGesture(count: 2) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onLike()
                        }
                }
                if !isMine { Spacer(minLength: 48) }
            }
            .offset(x: swipeOffset)
        }
        .simultaneousGesture(swipeToReplyGesture)
        .contextMenu {
            Menu("Add Emoji", systemImage: "face.smiling") {
                ForEach(MessageReactionIndex.quickEmojis, id: \.self) { emoji in
                    Button(emoji) { onReact(emoji) }
                }
            }
            if isMine {
                Button("Unsend for Everyone", systemImage: "arrow.uturn.backward.circle", role: .destructive) {
                    onUnsend()
                }
            }
            Button("Remove from This Device", systemImage: "iphone.and.arrow.forward", role: .destructive) {
                onRemoveLocally()
            }
        }
        .task(id: message.mediaPath) {
            await resolveImageURLIfNeeded()
        }
    }

    private var swipeToReplyGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onChanged { value in
                let horizontal = value.translation.width
                let vertical = abs(value.translation.height)
                guard abs(horizontal) > vertical else { return }
                if horizontal < 0 {
                    swipeOffset = max(horizontal, -72)
                }
            }
            .onEnded { value in
                if value.translation.width < -56 {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onReply()
                }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    swipeOffset = 0
                }
            }
    }

    @ViewBuilder
    private var reactionStrip: some View {
        if let reactionSummary, !reactionSummary.emojiCounts.isEmpty {
            HStack(spacing: 6) {
                ForEach(reactionSummary.emojiCounts.keys.sorted(), id: \.self) { emoji in
                    let count = reactionSummary.emojiCounts[emoji] ?? 0
                    Text(count > 1 ? "\(displayEmoji(emoji)) \(count)" : displayEmoji(emoji))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.canvasMuted, in: Capsule())
                }
            }
        }
    }

    private func displayEmoji(_ emoji: String) -> String {
        emoji == "❤" ? "❤️" : emoji
    }

    @ViewBuilder
    private var messageMeta: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
            HStack(spacing: 5) {
                if !message.timestampLabel.isEmpty {
                    Text(message.timestampLabel)
                }
                if message.isEdited {
                    Text("Edited")
                        .fontWeight(.semibold)
                }
            }
            .font(.caption2)
            .foregroundStyle(Theme.inkMuted)

            // Word only under the last message the recipient has read — no ticks.
            if isMine, isLastReadByPeer, isReadByPeer {
                Text("Read")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.inkMuted)
                    .accessibilityLabel("Read by recipient")
            }

            if showsStatusDetail, !isMine, !RelativeTime.formatDateTime(message.createdAt).isEmpty {
                Text(RelativeTime.formatDateTime(message.createdAt))
                    .font(.caption2)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
    }

    private var isPending: Bool {
        message.id.hasPrefix("pending-")
    }

    private var isReadByPeer: Bool {
        guard isMine,
              !isPending,
              let peerLastReadAt,
              let readDate = RelativeTime.parseDate(peerLastReadAt),
              let created = RelativeTime.parseDate(message.createdAt),
              readDate.timeIntervalSince(created) >= -2
        else { return false }
        return true
    }

    @ViewBuilder
    private var bubbleContent: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 8) {
            if let reply = message.replyInfo {
                replyPreview(reply)
            }

            // Shared hub / post / spark card — whole card opens destination (no play button).
            if let share = message.shareInfo {
                ChatShareCard(
                    share: share,
                    isMine: isMine,
                    onOpen: { onOpenShare?(share) }
                )
            }

            // Native video attachment — open via share routing when possible.
            if message.shareInfo == nil, message.hasVideoMedia {
                chatAttachedVideoThumb
            }

            if message.hasImage, message.shareInfo == nil {
                messageImage
            }

            if let text = message.displayText {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(isMine ? .white : Theme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(isMine ? Theme.accentBright : Theme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isMine ? Color.clear : Theme.border, lineWidth: 0.5)
                    )
            }
        }
        .padding(message.hasImage && message.shareInfo == nil && !message.hasVideoMedia ? 4 : 0)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    message.hasImage && message.shareInfo == nil && !message.hasVideoMedia
                        ? (isMine ? Theme.accentBright.opacity(0.15) : Theme.surface)
                        : Color.clear
                )
        )
        .fullScreenCover(isPresented: $showImageLightbox) {
            if let url = resolvedImageURL ?? message.mediaURL.flatMap(URL.init(string:)) {
                ChatImageLightbox(url: url)
            }
        }
    }

    /// Direct video attachment thumb — no play chrome; tap opens as a share destination.
    @ViewBuilder
    private var chatAttachedVideoThumb: some View {
        let cardW: CGFloat = YouTubeMiniPlayerBar.videoWidth
        let cardH: CGFloat = YouTubeMiniPlayerBar.videoHeight
        let rawURL = resolvedImageURL
            ?? MediaURLResolver.resolve(message.mediaURL)
            ?? message.mediaURL.flatMap(URL.init(string:))
        Button {
            guard let rawURL else { return }
            let share = Message.ShareInfo(
                kind: .post,
                postID: message.id,
                title: "Video",
                bodyText: nil,
                authorName: message.sender?.displayName,
                authorID: message.senderID,
                mediaURL: rawURL.absoluteString,
                posterURL: nil,
                mediaType: "video",
                note: ""
            )
            onOpenShare?(share)
        } label: {
            ZStack {
                Theme.canvasDeep
                Image(systemName: "film")
                    .font(.title3)
                    .foregroundStyle(Theme.inkMuted)
            }
            .frame(width: cardW, height: cardH)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .task(id: message.mediaPath) {
            guard message.mediaURL == nil, let path = message.mediaPath, !path.isEmpty else { return }
            if let signed = try? await MediaService.shared.signedMessageURL(path: path) {
                resolvedImageURL = URL(string: signed)
            }
        }
    }

    @ViewBuilder
    private var messageImage: some View {
        if let url = resolvedImageURL ?? message.mediaURL.flatMap(URL.init(string:)) {
            Button {
                showImageLightbox = true
            } label: {
                CachedAsyncImage(
                    url: url,
                    maxPixelSize: 720,
                    contentMode: .fill,
                    placeholder: AnyView(
                        ProgressView()
                            .frame(width: 180, height: 140)
                    )
                )
                .frame(maxWidth: 220, maxHeight: 280)
                .frame(minWidth: 160, minHeight: 120)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.4), in: Circle())
                        .padding(8)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View photo full screen")
        } else {
            imagePlaceholder
        }
    }

    private func replyPreview(_ reply: Message.ReplyInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Replying to \(replyAuthorName ?? "Message")")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
            Text(reply.quotedText.isEmpty ? "Message" : reply.quotedText)
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 220, alignment: .leading)
        .background(Theme.canvasMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Theme.accent)
                .frame(width: 3)
                .padding(.vertical, 6)
        }
    }

    private var imagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Theme.canvasMuted)
            .frame(width: 180, height: 140)
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(Theme.inkMuted)
            }
    }

    private func resolveImageURLIfNeeded() async {
        if let urlString = message.mediaURL, let url = URL(string: urlString) {
            resolvedImageURL = url
            return
        }
        guard let path = message.mediaPath, !path.isEmpty else { return }
        if let urlString = try? await MediaService.shared.signedMessageURL(path: path) {
            resolvedImageURL = URL(string: urlString)
        }
    }
}