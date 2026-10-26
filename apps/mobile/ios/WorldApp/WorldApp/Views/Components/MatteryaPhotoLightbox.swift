import SwiftUI
import UIKit

/// Instagram-style fullscreen photo viewer — pinch/pan zoom that stays until dismiss.
struct MatteryaPhotoLightbox: View {
    let urls: [URL]
    var startIndex: Int = 0
    var onClose: () -> Void

    @State private var page: Int
    @State private var dragOffset: CGFloat = 0

    init(urls: [URL], startIndex: Int = 0, onClose: @escaping () -> Void) {
        self.urls = urls
        self.startIndex = startIndex
        self.onClose = onClose
        _page = State(initialValue: min(max(0, startIndex), max(0, urls.count - 1)))
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .opacity(max(0.35, 1 - Double(abs(dragOffset) / 420)))

            TabView(selection: $page) {
                ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                    MatteryaZoomablePhotoPage(url: url)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .automatic : .never))
            .offset(y: dragOffset)
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onChanged { value in
                        // Vertical dismiss only when mostly downward.
                        if abs(value.translation.height) > abs(value.translation.width) {
                            dragOffset = max(0, value.translation.height)
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 140 || value.predictedEndTranslation.height > 220 {
                            onClose()
                        } else {
                            withAnimation(.interpolatingSpring(stiffness: 280, damping: 30)) {
                                dragOffset = 0
                            }
                        }
                    }
            )

            VStack {
                HStack {
                    if urls.count > 1 {
                        Text("\(page + 1)/\(urls.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                Spacer()
            }
        }
        .statusBarHidden(true)
    }
}

// MARK: - Zoomable page (UIScrollView)

private struct MatteryaZoomablePhotoPage: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> MatteryaZoomScrollView {
        let view = MatteryaZoomScrollView()
        view.load(url: url)
        return view
    }

    func updateUIView(_ uiView: MatteryaZoomScrollView, context: Context) {
        uiView.load(url: url)
    }
}

final class MatteryaZoomScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var loadedURL: URL?
    private var loadTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 5
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        bouncesZoom = true
        alwaysBounceVertical = false
        alwaysBounceHorizontal = false

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.clipsToBounds = true
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func load(url: URL) {
        guard loadedURL != url else { return }
        loadedURL = url
        loadTask?.cancel()
        imageView.image = nil
        zoomScale = 1
        loadTask = Task { [weak self] in
            let image = await ImageCache.shared.image(for: url, maxPixelSize: 1600)
            guard !Task.isCancelled, let self, self.loadedURL == url else { return }
            await MainActor.run {
                self.imageView.image = image
                self.setNeedsLayout()
                self.layoutIfNeeded()
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard zoomScale <= 1.01 else { return }
        let boundsSize = bounds.size
        imageView.frame = CGRect(origin: .zero, size: boundsSize)
        contentSize = boundsSize
        centerImage()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }

    private func centerImage() {
        let boundsSize = bounds.size
        var frame = imageView.frame
        if frame.size.width < boundsSize.width {
            frame.origin.x = (boundsSize.width - frame.size.width) / 2
        } else {
            frame.origin.x = 0
        }
        if frame.size.height < boundsSize.height {
            frame.origin.y = (boundsSize.height - frame.size.height) / 2
        } else {
            frame.origin.y = 0
        }
        imageView.frame = frame
    }

    @objc private func handleDoubleTap(_ gr: UITapGestureRecognizer) {
        if zoomScale > 1.05 {
            setZoomScale(1, animated: true)
        } else {
            let point = gr.location(in: imageView)
            let target: CGFloat = 2.5
            let size = CGSize(
                width: bounds.width / target,
                height: bounds.height / target
            )
            let origin = CGPoint(
                x: point.x - size.width / 2,
                y: point.y - size.height / 2
            )
            zoom(to: CGRect(origin: origin, size: size), animated: true)
        }
    }
}
