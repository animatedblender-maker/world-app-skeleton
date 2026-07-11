import SwiftUI

struct UploadProgressView: View {
    let phase: MediaUploadPhase
    let progress: UploadProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                if let progress, phase == .uploading {
                    Text(progress.percentText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .monospacedDigit()
                }
            }

            if phase == .uploading, let progress {
                ProgressView(value: progress.fractionCompleted)
                    .tint(Theme.facebookBlue)
                Text(progress.bytesText)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))
                    .monospacedDigit()
            } else if phase == .publishing {
                ProgressView()
                    .tint(.white)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var title: String {
        switch phase {
        case .idle:
            return "Preparing…"
        case .uploading:
            return "Uploading video"
        case .publishing:
            return "Publishing post"
        }
    }
}