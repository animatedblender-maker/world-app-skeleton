import SwiftUI

struct UploadProgressView: View {
    let phase: MediaUploadPhase
    let progress: UploadProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if let progress, phase == .uploading || phase == .compressing {
                    Text(progress.percentText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.inkSecondary)
                        .monospacedDigit()
                }
            }

            if phase == .uploading || phase == .compressing, let progress {
                ProgressView(value: progress.fractionCompleted)
                    .tint(Theme.accentBright)
                if phase == .uploading {
                    Text(progress.bytesText)
                        .font(.caption2)
                        .foregroundStyle(Theme.inkMuted)
                        .monospacedDigit()
                }
            } else if phase == .publishing {
                ProgressView()
                    .tint(Theme.accentBright)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }

    private var title: String {
        switch phase {
        case .idle:
            return "Preparing…"
        case .compressing:
            return "Compressing video"
        case .uploading:
            if let progress, progress.totalBytes > 0, progress.bytesSent >= progress.totalBytes {
                return "Finishing upload"
            }
            return "Uploading video"
        case .publishing:
            return "Publishing post"
        }
    }
}