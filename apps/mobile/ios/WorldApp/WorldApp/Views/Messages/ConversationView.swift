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

    @Bindable private var callManager = CallSessionManager.shared

    private var visibleMessages: [Message] {
        messages.filter(\.isRenderableInChat)
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
                                    replyAuthorName: replyAuthorName(for: message),
                                    onReply: { replyingTo = message }
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
            let loaded = try await MessagesService.shared.listMessages(conversationID: conversation.id)
            await MainActor.run {
                messages = loaded
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
                messages.append(message)
                draft = ""
                replyingTo = nil
                clearPendingMedia()
                notifyConversationChanged()
                requestScrollToBottom()
            } else {
                let message = try await MessagesService.shared.sendMessage(conversationID: conversation.id, body: body)
                messages.append(message)
                draft = ""
                replyingTo = nil
                notifyConversationChanged()
                requestScrollToBottom()
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func notifyConversationChanged() {
        NotificationCenter.default.post(
            name: .conversationMessagesDidChange,
            object: nil,
            userInfo: ["conversationId": conversation.id]
        )
    }
}

private struct MessageBubble: View {
    let message: Message
    let isMine: Bool
    let replyAuthorName: String?
    let onReply: () -> Void

    @State private var resolvedImageURL: URL?

    private var isReply: Bool { message.replyInfo != nil }
    private var replyIndent: CGFloat { isReply ? 28 : 0 }

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
        HStack {
            if isMine { Spacer(minLength: 48) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                bubbleContent
                if !message.timestampLabel.isEmpty {
                    Text(message.timestampLabel)
                        .font(.caption2)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            .padding(isMine ? .trailing : .leading, replyIndent)
            if !isMine { Spacer(minLength: 48) }
        }
        .contextMenu {
            Button("Reply", systemImage: "arrowshape.turn.up.left") {
                onReply()
            }
        }
        .task(id: message.mediaPath) {
            await resolveImageURLIfNeeded()
        }
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