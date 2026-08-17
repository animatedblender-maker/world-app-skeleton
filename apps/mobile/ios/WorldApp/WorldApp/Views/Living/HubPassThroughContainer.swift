import SwiftUI
import UIKit

/// Full-screen host that **only** receives touches inside `interactiveRectGlobal` (window coords).
/// Touches outside return `nil` from `hitTest` so views underneath (ScrollView / mini chrome) work.
///
/// **Performance:** Re-host **only** when `contentID` (post) changes.
/// Geometry morph (mini ↔ stage ↔ FS) is driven by an `ObservableObject` *inside* the hosted
/// tree — never by reassigning `rootView` every drag frame (that paused the film).
struct HubPassThroughContainer<Content: View>: UIViewControllerRepresentable {
    /// Interactive region in **global / window** coordinates.
    var interactiveRectGlobal: CGRect
    var interactiveRect: CGRect = .zero
    /// New post → full rebuild. Morph must NOT change this.
    var contentID: String = ""
    /// Deprecated — ignored. Kept so call sites compile during transition.
    var layoutSignature: String = ""
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> HubPassThroughViewController<Content> {
        let vc = HubPassThroughViewController(rootView: content())
        vc.interactiveRectGlobal = resolvedGlobalRect()
        vc.hostedContentID = contentID
        vc.layoutSignature = contentID
        context.coordinator.lastContentID = contentID
        return vc
    }

    func updateUIViewController(_ controller: HubPassThroughViewController<Content>, context: Context) {
        let nextRect = resolvedGlobalRect()
        if controller.interactiveRectGlobal != nextRect {
            controller.interactiveRectGlobal = nextRect
        }

        // Only swap the SwiftUI tree when the *video identity* changes.
        // Morph / dock / chrome live on HubMorphState and update without rehost.
        guard context.coordinator.lastContentID != contentID else { return }
        context.coordinator.lastContentID = contentID
        controller.hostedContentID = contentID
        controller.layoutSignature = contentID
        controller.rootView = content()
    }

    private func resolvedGlobalRect() -> CGRect {
        if interactiveRectGlobal.width > 1, interactiveRectGlobal.height > 1 {
            return interactiveRectGlobal
        }
        return interactiveRect
    }

    final class Coordinator {
        var lastContentID: String = ""
    }
}

final class HubPassThroughViewController<Content: View>: UIViewController {
    var interactiveRectGlobal: CGRect = .zero {
        didSet {
            guard oldValue != interactiveRectGlobal else { return }
            (view as? HubPassThroughUIView)?.interactiveRectGlobal = interactiveRectGlobal
        }
    }
    var hostedContentID: String = ""
    var layoutSignature: String = ""

    private let host: UIHostingController<Content>

    var rootView: Content {
        get { host.rootView }
        set { host.rootView = newValue }
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
        pass.isUserInteractionEnabled = true
        pass.interactiveRectGlobal = interactiveRectGlobal
        view = pass
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        host.view.backgroundColor = .clear
        host.view.isOpaque = false
        host.view.isUserInteractionEnabled = true
        host.view.clipsToBounds = false
        view.clipsToBounds = false
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

final class HubPassThroughUIView: UIView {
    var interactiveRectGlobal: CGRect = .zero

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard interactiveRectGlobal.width > 1, interactiveRectGlobal.height > 1 else { return nil }
        let globalPoint = convert(point, to: nil)
        guard interactiveRectGlobal.insetBy(dx: -1, dy: -1).contains(globalPoint) else {
            return nil
        }
        return super.hitTest(point, with: event)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard interactiveRectGlobal.width > 1, interactiveRectGlobal.height > 1 else { return false }
        let globalPoint = convert(point, to: nil)
        return interactiveRectGlobal.insetBy(dx: -1, dy: -1).contains(globalPoint)
    }
}
