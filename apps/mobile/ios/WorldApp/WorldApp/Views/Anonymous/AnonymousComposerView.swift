import SwiftUI

struct AnonymousComposerView: View {
    let spaceId: String
    let spaceTitle: String

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var store = AnonymousStore.shared
    @State private var isPublishing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Posting in \(spaceTitle)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkMuted)

                    TextField("Title (optional)", text: Binding(
                        get: { store.composerTitle },
                        set: { store.composerTitle = $0 }
                    ))
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.controlRadius)
                            .stroke(Theme.border, lineWidth: 0.5)
                    )

                    ZStack(alignment: .topLeading) {
                        if store.composerBody.isEmpty {
                            Text("Write your post…")
                                .foregroundStyle(Theme.inkMuted)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                        }
                        TextEditor(text: Binding(
                            get: { store.composerBody },
                            set: { store.composerBody = $0 }
                        ))
                        .frame(minHeight: 180)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                    }
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.controlRadius)
                            .stroke(Theme.border, lineWidth: 0.5)
                    )

                    Text(MatteryaCopy.anonymousComposerPrivacyNudge)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                .padding(Theme.pagePadding)
            }
            .screenBackground()
            .navigationTitle("New post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.ink)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isPublishing ? "Posting…" : "Post") {
                        Task { await publish() }
                    }
                    .foregroundStyle(Theme.ink)
                    .disabled(isPublishing || store.composerBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func publish() async {
        isPublishing = true
        defer { isPublishing = false }
        if let _ = await store.publishPost(spaceId: spaceId) {
            appState.showToast("Posted", style: .success)
            dismiss()
        } else if let err = store.consumeError() {
            appState.showToast(err, style: .error)
        }
    }
}
