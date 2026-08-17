import SwiftUI
import UIKit

/// Full-screen host that **only** receives touches inside `interactiveRectGlobal` (window coords).
/// Touches outside return `nil` from `hitTest` so views underneath (comments ScrollView, feed,
/// mini play/mute/close) receive them.
///
/// MUST be the outermost view of the continuous player. A full-size SwiftUI `GeometryReader`
/// *above* this host claims every touch (returns `self` when children return nil) and kills
/// comment scroll + mini chrome.
struct HubPassThroughContainer<Content: View>: UIViewControllerRepresentable {
    /// Interactive region in **global / window** coordinates (same space as PreferenceKey frames).
    var interactiveRectGlobal: CGRect
    /// Legacy local-rect API — prefer `interactiveRectGlobal`.
    var interactiveRect: CGRect = .zero
    /// Bumped only when hosted identity must fully rebuild (new post).
    var contentID: String = ""
    @ViewBuilder var content: () -> Content

    func makeUIViewController(context: Context) -> HubPassThroughViewController<Content> {
        let vc = HubPassThroughViewController(rootView: content())
        vc.interactiveRectGlobal = resolvedGlobalRect()
        vc.hostedContentID = contentID
        return vc
    }

    func updateUIViewController(_ controller: HubPassThroughViewController<Content>, context: Context) {
        let next = resolvedGlobalRect()
        if controller.interactiveRectGlobal != next {
            controller.interactiveRectGlobal = next
        }
        // Always push latest tree so morph offset/size stay live — never force layout.
        controller.rootView = content()
    }

    private func resolvedGlobalRect() -> CGRect {
        if interactiveRectGlobal.width > 1, interactiveRectGlobal.height > 1 {
            return interactiveRectGlobal
        }
        return interactiveRect
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
        // Never clip film when mini dock sits at the bottom of the window.
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
    /// Film / stage / mini hole in **global** coordinates.
    var interactiveRectGlobal: CGRect = .zero

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard interactiveRectGlobal.width > 1, interactiveRectGlobal.height > 1 else { return nil }
        // Convert touch into global space and gate before any child sees it.
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
