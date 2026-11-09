import SwiftUI

struct StudioRangeChips: View {
    @Binding var range: StudioService.Range

    var body: some View {
        HStack(spacing: 6) {
            ForEach(StudioService.Range.allCases) { item in
                Button {
                    range = item
                } label: {
                    Text(item.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(range == item ? Theme.paper : Theme.inkSecondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(range == item ? Theme.ink : Theme.surface)
                        )
                        .overlay {
                            if range != item {
                                Capsule(style: .continuous)
                                    .stroke(Theme.border, lineWidth: 0.5)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct StudioKPICard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.inkMuted)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .studioPanel()
    }
}

struct StudioVideoRowView: View {
    let video: StudioService.VideoRow
    var showsDate: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            thumb
            VStack(alignment: .leading, spacing: 4) {
                Text(rowTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Text(metaLine)
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
        }
    }

    private var rowTitle: String {
        if let title = video.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return "Untitled video"
    }

    private var metaLine: String {
        var parts = [
            "\(StudioService.formatCount(video.views)) views",
            StudioService.formatWatch(video.watchMs),
            "CTR \(StudioService.formatCtr(video.ctr))",
        ]
        if showsDate {
            parts.append(StudioService.formatDate(video.createdAt))
        }
        if let slug = video.hubSlug, !slug.isEmpty {
            parts.insert(slug, at: 0)
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var thumb: some View {
        let placeholder = RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.matteDeep)
            .frame(width: 56, height: 74)
        if let urlString = video.thumbUrl, let url = URL(string: urlString) {
            CachedAsyncImage(
                url: url,
                maxPixelSize: 200,
                contentMode: .fill,
                placeholder: AnyView(placeholder)
            )
            .frame(width: 56, height: 74)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            placeholder
        }
    }
}

extension View {
    func studioPanel() -> some View {
        background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.border.opacity(0.85), lineWidth: 0.5)
        )
    }
}
