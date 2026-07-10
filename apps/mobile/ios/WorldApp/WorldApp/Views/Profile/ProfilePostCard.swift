import SwiftUI

struct ProfilePostCard: View {
    let post: CountryPost
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                header
                content
                footer
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
            .shadow(color: Theme.ink.opacity(0.04), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                if let country = post.countryName {
                    Text(country.uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(1.6)
                        .foregroundStyle(Theme.accent)
                }
                Text(post.title?.nilIfWhitespace ?? headline)
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }
            Spacer(minLength: 12)
            Text(RelativeTime.format(post.createdAt))
                .font(.caption2)
                .foregroundStyle(Theme.inkMuted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var content: some View {
        if let mediaURL = post.mediaURL ?? post.thumbURL, let url = URL(string: mediaURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(height: 220)
                        .clipped()
                        .overlay(alignment: .bottom) {
                            LinearGradient(
                                colors: [.clear, Theme.ink.opacity(0.18)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 80)
                        }
                default:
                    mediaPlaceholder
                }
            }
            .padding(.horizontal, 16)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }

        if !excerpt.isEmpty {
            Text(excerpt)
                .font(.body)
                .foregroundStyle(Theme.inkSecondary)
                .lineSpacing(4)
                .lineLimit(post.mediaURL == nil ? 8 : 4)
                .padding(.horizontal, 20)
                .padding(.top, post.hasMedia ? 14 : 0)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Label("\(post.likeCount)", systemImage: "heart")
            Label("\(post.commentCount)", systemImage: "text.bubble")
            if let city = post.cityName, !city.isEmpty {
                Text(city)
            }
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
        }
        .font(.caption)
        .foregroundStyle(Theme.inkMuted)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var headline: String {
        let trimmed = post.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Untitled entry" }
        return String(trimmed.prefix(72))
    }

    private var excerpt: String {
        let trimmed = post.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title = post.title?.nilIfWhitespace, !title.isEmpty else { return trimmed }
        if trimmed == title { return "" }
        return trimmed
    }

    private var mediaPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Theme.canvasMuted)
            .frame(height: 180)
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(Theme.inkMuted)
            }
    }
}

private extension String {
    var nilIfWhitespace: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}