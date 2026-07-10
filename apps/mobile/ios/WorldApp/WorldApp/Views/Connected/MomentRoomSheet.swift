import SwiftUI

struct MomentRoomSheet: View {
    let room: MomentRoom
    let onUpdated: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var comments: [MomentComment] = []
    @State private var commentText = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard
                    commentsSection
                }
                .padding(Theme.pagePadding)
                .padding(.bottom, 80)
            }
            .screenBackground()
            .navigationTitle("Moment Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .safeAreaInset(edge: .bottom) {
                composerBar
            }
            .task { await loadComments() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.accentSoft)
                        .frame(width: 48, height: 48)

                    Image(systemName: room.platform.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(room.showTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.ink)

                    Text("\(room.episodeLabel) · \(room.timestamp)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.inkSecondary)
                }
            }

            HStack(spacing: 16) {
                Label("\(room.activeFriends) friends here", systemImage: "person.2.fill")
                Label(room.heat > 0.8 ? "Trending" : "Active", systemImage: "flame.fill")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.inkMuted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hubSheetCard()
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("At this moment")
                .sectionLabel()

            if isLoading {
                ProgressView()
                    .tint(Theme.accent)
            } else if comments.isEmpty {
                Text("Be the first to react at \(room.timestamp).")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
            } else {
                ForEach(comments) { comment in
                    CommentBubble(comment: comment)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
            }
        }
    }

    private var composerBar: some View {
        HStack(spacing: 10) {
            TextField("React at \(room.timestamp)…", text: $commentText)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Theme.canvasMuted, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius)
                        .stroke(Theme.border, lineWidth: 0.5)
                )

            Button {
                Task { await sendComment() }
            } label: {
                Image(systemName: isSending ? "hourglass" : "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.accentSoft, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isSending || commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 12)
        .background(Theme.surface.opacity(0.96))
    }

    private func loadComments() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loaded = try await StreamingHubService.shared.momentRoomComments(roomKey: room.roomKey)
            comments = loaded.isEmpty ? room.previewComments : loaded
        } catch {
            comments = room.previewComments
            errorMessage = error.localizedDescription
        }
    }

    private func sendComment() async {
        let body = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }

        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            let comment = try await StreamingHubService.shared.addMomentRoomComment(
                roomKey: room.roomKey,
                body: body
            )
            comments.append(comment)
            commentText = ""
            await onUpdated()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CommentBubble: View {
    let comment: MomentComment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(comment.author)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                    Text("\(comment.reactions)")
                        .font(.caption.monospacedDigit())
                }
                .foregroundStyle(Theme.inkMuted)
            }

            Text(comment.body)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .hubSheetCard()
    }
}

private extension View {
    func hubSheetCard() -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
    }
}