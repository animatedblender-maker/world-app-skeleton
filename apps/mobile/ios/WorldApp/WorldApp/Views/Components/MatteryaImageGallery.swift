import SwiftUI

/// Matterya-styled multi-photo carousel for home feed image posts.
/// Matches card ink/border language — page dots, no loud chrome.
struct MatteryaImageGallery: View {
    let urls: [URL]
    var maxPixelSize: CGFloat = 540
    var onZoomingChanged: ((Bool) -> Void)? = nil
    var onTap: (() -> Void)? = nil

    @State private var page = 0
    var onTapPage: ((Int) -> Void)? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $page) {
                ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                    FeedPinchZoomPhoto(
                        url: url,
                        maxPixelSize: maxPixelSize,
                        contentMode: .fit,
                        placeholder: AnyView(galleryPlaceholder),
                        onZoomingChanged: { zooming in
                            onZoomingChanged?(zooming)
                        },
                        onTap: {
                            if let onTapPage {
                                onTapPage(index)
                            } else {
                                onTap?()
                            }
                        }
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if urls.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<urls.count, id: \.self) { index in
                        Circle()
                            .fill(index == page ? Theme.ink : Theme.ink.opacity(0.28))
                            .frame(width: index == page ? 7 : 5, height: index == page ? 7 : 5)
                            .animation(.easeOut(duration: 0.18), value: page)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Theme.border.opacity(0.6), lineWidth: 0.5))
                .padding(.bottom, 10)

                Text("\(page + 1)/\(urls.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.surface)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.ink.opacity(0.55), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
    }

    private var galleryPlaceholder: some View {
        Rectangle()
            .fill(Theme.canvasMuted)
            .overlay {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Theme.inkMuted)
            }
    }
}
