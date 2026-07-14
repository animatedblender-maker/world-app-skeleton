import PhotosUI
import SwiftUI
import UIKit

struct ConversationView: View {
    let conversation: Conversation

    @State private var messages: [Message] = []
    @State private var draft = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingMediaData: Data?
    @State private var pendingMediaImage: UIImage?
    @State private var scrollToBottomToken = 0
    @State private var replyingTo: Message?
    @State private var peerLastReadAt: String?

    @Bindable private var callManager = CallSessionManager.shared

    private var visibleMessages: [Message] {
        messages
            .filter(\.isRenderableInChat)
            .filter { !HiddenMessagesStore.isHidden(conversationID: conversation.id, messageID: $0.id) }
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
            if isLoading {
                ProgressView().tint(Theme.accentBright).frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(visibleMessages) { message in
                                MessageBubble(
                                    message: message,
                                    isMine: message.senderID == currentUserID,
                                    peerLastReadAt: peerLastReadAt,
                                    reactionSummary: reactionSummaries[message.id],
                                    replyAuthorName: replyAuthorName(for: message),
                                    onReply: { replyingTo = message },
                                    onLike: { Task { await toggleMessageLike(message) } },
                                    onReact: { emoji in Task { await reactToMessage(message, emoji: emoji) } },
                                    onUnsend: { Task { await unsendMessage(message) } },
                                    onRemoveLocally: { removeMessageLocally(message) }
                                )
                                .id(message.id)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("chat-bottom")
                        }
                        .padding(Theme.pagePadding)
                    }
                    .onAppear {
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: scrollToBottomToken) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal)
            }

            composerBar
        }
        .screenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
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
        .task {
            await callManager.ensureSignalingReady()
            await loadMessages()
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
            Task { await loadMessages() }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        func perform() {
            proxy.scrollTo("chat-bottom", anchor: .bottom)
        }
        perform()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            perform()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            perform()
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
        let showSpinner = messages.isEmpty
        if showSpinner {
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
                peerLastReadAt = peerRead
                errorMessage = nil
                if showSpinner { isLoading = false }
                requestScrollToBottom()
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
            await MainActor.run { requestScrollToBottom() }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                if showSpinner { isLoading = false }
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
            requestScrollToBottom()
        }
        draft = ""
        let savedReply = replyingTo
        replyingTo = nil

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
                }
                clearPendingMedia()
            } else {
                let message = try await MessagesService.shared.sendMessage(conversationID: conversation.id, body: body)
                if let placeholderID {
                    replacePendingMessage(id: placeholderID, with: message)
                } else {
                    messages.append(message)
                }
            }
            notifyConversationChanged()
            requestScrollToBottom()
            if let refreshed = try? await MessagesService.shared.getConversationById(conversation.id) {
                peerLastReadAt = refreshed.otherMember(currentUserID: currentUserID ?? "")?.lastReadAt
            }
        } catch {
            if let placeholderID {
                messages.removeAll { $0.id == placeholderID }
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
    }

    private func notifyConversationChanged() {
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
    let message: Message
    let isMine: Bool
    let peerLastReadAt: String?
    let reactionSummary: MessageReactionSummary?
    let replyAuthorName: String?
    let onReply: () -> Void
    let onLike: () -> Void
    let onReact: (String) -> Void
    let onUnsend: () -> Void
    let onRemoveLocally: () -> Void

    @State private var resolvedImageURL: URL?
    @State private var showsStatusDetail = false
    @State private var swipeOffset: CGFloat = 0

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
                }
                if !isMine { Spacer(minLength: 48) }
            }
            .offset(x: swipeOffset)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(swipeToReplyGesture)
        .gesture(messageTapGesture)
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

    private var messageTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded { _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onLike()
            }
            .exclusively(before: TapGesture(count: 1).onEnded {
                showsStatusDetail.toggle()
            })
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
            HStack(spacing: 6) {
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

            if showsStatusDetail {
                if isMine {
                    deliveryStatusLines
                } else if !RelativeTime.formatDateTime(message.createdAt).isEmpty {
                    Text(RelativeTime.formatDateTime(message.createdAt))
                        .font(.caption2)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
        }
    }

    @ViewBuilder
    private var deliveryStatusLines: some View {
        VStack(alignment: .trailing, spacing: 2) {
            statusLine(label: "Sent", timestamp: message.createdAt)
            if isDelivered {
                statusLine(label: "Delivered", timestamp: message.createdAt)
            }
            if let readAt = readTimestamp {
                statusLine(label: "Read", timestamp: readAt)
            }
        }
    }

    private func statusLine(label: String, timestamp: String) -> some View {
        Text("\(label) \(RelativeTime.formatDateTime(timestamp))")
            .font(.caption2)
            .foregroundStyle(Theme.inkMuted)
    }

    private var isPending: Bool {
        message.id.hasPrefix("pending-")
    }

    private var isDelivered: Bool {
        guard isMine else { return false }
        return !isPending && !message.id.isEmpty && !message.createdAt.isEmpty
    }

    private var readTimestamp: String? {
        guard isMine,
              let peerLastReadAt,
              let readDate = RelativeTime.parseDate(peerLastReadAt),
              let created = RelativeTime.parseDate(message.createdAt),
              readDate >= created
        else { return nil }
        return peerLastReadAt
    }

    @ViewBuilder
    private var bubbleContent: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 8) {
            if let reply = message.replyInfo {
                replyPreview(reply)
            }

            if message.hasImage {
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
        .padding(message.hasImage ? 4 : 0)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(message.hasImage ? (isMine ? Theme.accentBright.opacity(0.15) : Theme.surface) : Color.clear)
        )
    }

    @ViewBuilder
    private var messageImage: some View {
        if let url = resolvedImageURL ?? message.mediaURL.flatMap(URL.init(string:)) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 220, maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                case .failure:
                    imagePlaceholder
                default:
                    ProgressView()
                        .frame(width: 180, height: 140)
                }
            }
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