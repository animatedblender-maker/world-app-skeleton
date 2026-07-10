import SwiftUI

struct NewsDetailView: View {
    @Environment(AppState.self) private var appState

    let newsID: String

    @State private var item: ExternalNewsItem?
    @State private var comments: [ExternalNewsComment] = []
    @State private var commentDraft = ""
    @State private var shareDraft = ""
    @State private var commentsOpen = false
    @State private var isLoading = true
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                } else if let item {
                    newsContent(item)
                }
            }
            .padding()
        }
        .screenBackground()
        .navigationTitle("News")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .task { await load() }
    }

    @ViewBuilder
    private func newsContent(_ article: ExternalNewsItem) -> some View {
        HStack {
            Text(article.sourceName ?? "ReliefWeb")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.accentBright)
            Spacer()
            if let published = article.publishedAt {
                Text(RelativeTime.format(published))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }

        Text(article.title)
            .font(.title3.weight(.bold))

        if !article.themeNames.isEmpty || !article.disasterTypes.isEmpty {
            FlowTags(tags: article.themeNames.prefix(3) + article.disasterTypes.prefix(3))
        }

        if let imageURL = article.imageURL, let url = URL(string: imageURL) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }

        if let snippet = article.snippet {
            Text(snippet).font(.body)
        }

        if !article.countryNames.isEmpty {
            Text(article.countryNames.joined(separator: " • "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        HStack {
            Button(article.likedByMe ? "Unlike" : "Like") { Task { await toggleLike(article) } }
            Button(commentsOpen ? "Hide comments" : "Comments (\(article.commentCount))") {
                commentsOpen.toggle()
            }
            if let url = URL(string: article.url) {
                Link("Source", destination: url)
            }
        }
        .font(.caption.weight(.semibold))

        VStack(alignment: .leading, spacing: 8) {
            Text("Share to country feed")
                .font(.subheadline.weight(.bold))
            TextField("Add your caption…", text: $shareDraft, axis: .vertical)
                .lineLimit(2...4)
            Button(busy ? "Sharing…" : "Share") { Task { await share(article) } }
                .disabled(busy)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

        if commentsOpen {
            VStack(alignment: .leading, spacing: 10) {
                Text("Comments").font(.headline)
                ForEach(comments) { comment in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(comment.author?.displayName ?? "Member")
                            .font(.caption.weight(.bold))
                        Text(comment.body).font(.subheadline)
                    }
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                }
                HStack {
                    TextField("Add comment…", text: $commentDraft)
                    Button("Send") { Task { await addComment(article) } }
                        .disabled(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            item = try await NewsService.shared.item(newsID)
            comments = try await NewsService.shared.comments(newsID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleLike(_ article: ExternalNewsItem) async {
        do {
            item = article.likedByMe
                ? try await NewsService.shared.unlike(article.id)
                : try await NewsService.shared.like(article.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addComment(_ article: ExternalNewsItem) async {
        let body = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        do {
            let comment = try await NewsService.shared.addComment(article.id, body: body)
            comments.append(comment)
            commentDraft = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func share(_ article: ExternalNewsItem) async {
        busy = true
        defer { busy = false }
        do {
            _ = try await NewsService.shared.shareToCountry(article.id, body: shareDraft.nilIfEmpty)
            shareDraft = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FlowTags: View {
    let tags: ArraySlice<String>
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(Array(tags), id: \.self) { tag in
                    Text(tag)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.cyan.opacity(0.15), in: Capsule())
                }
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}