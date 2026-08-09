import SwiftUI
import UIKit

/// Full-screen host that **only** receives touches inside `interactiveRect`.
/// Touches outside return `nil` from `hitTest` so views underneath (ScrollView) scroll normally.
struct HubPassThroughContainer<Content: View>: UIViewControllerRepresentable {
    /// Hit-testable region in the container’s bounds (same as GeometryReader local space).
    var interactiveRect: CGRect
    @ViewBuilder var content: () -> Content

    func makeUIViewController(context: Context) -> HubPassThroughViewController<Content> {
        HubPassThroughViewController(rootView: content())
    }

    func updateUIViewController(_ controller: HubPassThroughViewController<Content>, context: Context) {
        controller.interactiveRect = interactiveRect
        controller.rootView = content()
    }
}

final class HubPassThroughViewController<Content: View>: UIViewController {
    var interactiveRect: CGRect = .zero {
        didSet {
            (view as? HubPassThroughUIView)?.interactiveRect = interactiveRect
        }
    }

    private let host: UIHostingController<Content>

    var rootView: Content {
        get { host.rootView }
        set {
            host.rootView = newValue
            host.view.setNeedsLayout()
        }
    }

    init(rootView: Content) {
        host = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func loadView() {
        let pass = HubPassThroughUIView()
        pass.backgroundColor = .clear
        pass.isOpaque = false
        pass.interactiveRect = interactiveRect
        view = pass
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        host.view.backgroundColor = .clear
        host.view.isOpaque = false
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }
}

/// Returns `nil` for hit tests outside `interactiveRect` → touches pass through to SwiftUI below.
final class HubPassThroughUIView: UIView {
    var interactiveRect: CGRect = .zero

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Empty / invalid rect → never steal touches (e.g. mid-layout).
        guard interactiveRect.width > 1, interactiveRect.height > 1 else { return nil }
        guard interactiveRect.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard interactiveRect.width > 1, interactiveRect.height > 1 else { return false }
        return interactiveRect.contains(point)
    }
}
