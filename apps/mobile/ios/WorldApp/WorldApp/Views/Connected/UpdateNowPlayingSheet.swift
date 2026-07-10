import SwiftUI

struct UpdateNowPlayingSheet: View {
    let platform: StreamingPlatform
    let existing: YourNowPlaying?
    let onSave: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var subtitle = ""
    @State private var momentLabel = ""
    @State private var progressMinutes = 0
    @State private var progressSeconds = 0
    @State private var durationMinutes = 45
    @State private var isSharing = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("What you're on") {
                    TextField("Title", text: $title)
                    TextField("Episode, album, or artist", text: $subtitle)
                    TextField("Scene or track (optional)", text: $momentLabel)
                }

                Section("Progress") {
                    Stepper("Minutes: \(progressMinutes)", value: $progressMinutes, in: 0...300)
                    Stepper("Seconds: \(progressSeconds)", value: $progressSeconds, in: 0...59)
                    Stepper("Total length (min): \(durationMinutes)", value: $durationMinutes, in: 1...240)
                }

                Section {
                    Toggle("Share live with friends", isOn: $isSharing)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Theme.danger)
                            .font(.caption)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle(platform.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .onAppear {
                if let existing {
                    title = existing.title
                    subtitle = existing.subtitle
                    momentLabel = existing.momentLabel ?? ""
                    isSharing = existing.isSharing
                    let parts = existing.progressLabel.split(separator: ":")
                    if parts.count == 2 {
                        progressMinutes = Int(parts[0]) ?? 0
                        progressSeconds = Int(parts[1]) ?? 0
                    }
                    durationMinutes = max(1, Int((existing.progress > 0 ? 1 / existing.progress : 1) * Double(progressMinutes * 60 + progressSeconds) / 60))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            _ = try await StreamingHubService.shared.updateNowPlaying(
                platform: platform,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                momentLabel: momentLabel.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                progressMinutes: progressMinutes,
                progressSeconds: progressSeconds,
                durationMinutes: durationMinutes,
                isSharing: isSharing
            )
            await onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}