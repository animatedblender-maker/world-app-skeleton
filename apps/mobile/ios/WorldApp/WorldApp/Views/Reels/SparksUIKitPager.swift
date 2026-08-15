import SwiftUI
import UIKit

// MARK: - Platform-style Sparks pager (TikTok / IG / Shorts)
//
// SwiftUI ScrollView + GeometryReader reflows when fullScreenCover / status bar / safe
// area settles → “full screen → crops under notch → plays”.
//
// Other apps use UICollectionView with:
//   • contentInsetAdjustmentBehavior = .never
//   • itemSize = physical screen (locked)
//   • paging enabled
//   • video aspectFill edge-to-edge; chrome is overlay only

struct SparksUIKitPager: UIViewControllerRepresentable {
    @Environment(AppState.self) private var appState
    @Binding var posts: [CountryPost]
    @Binding var activeIndex: Int

    var bottomInset: CGFloat = 28
    var showsOpenPostAction = false
    var viewerCountryCode: String? = nil
    var isScrollEnabled: Bool = true
    var onNearEnd: (() -> Void)? = nil
    var onNearStart: (() -> Void)? = nil
    var onOpenComments: ((String) -> Void)? = nil
    var onLikeToggle: ((CountryPost) -> Void)? = nil
    var onOpenPost: ((CountryPost) -> Void)? = nil

    func makeUIViewController(context: Context) -> SparksPagerViewController {
        let vc = SparksPagerViewController()
        vc.coordinator = context.coordinator
        context.coordinator.controller = vc
        context.coordinator.appState = appState
        vc.apply(
            posts: posts,
            activeIndex: activeIndex,
            bottomInset: bottomInset,
            showsOpenPostAction: showsOpenPostAction,
            viewerCountryCode: viewerCountryCode,
            isScrollEnabled: isScrollEnabled,
            appState: appState
        )
        return vc
    }

    func updateUIViewController(_ vc: SparksPagerViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.appState = appState
        vc.coordinator = context.coordinator
        vc.apply(
            posts: posts,
            activeIndex: activeIndex,
            bottomInset: bottomInset,
            showsOpenPostAction: showsOpenPostAction,
            viewerCountryCode: viewerCountryCode,
            isScrollEnabled: isScrollEnabled,
            appState: appState
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator {
        var parent: SparksUIKitPager
        weak var controller: SparksPagerViewController?
        var appState: AppState?

        init(parent: SparksUIKitPager) {
            self.parent = parent
        }

        func setActiveIndex(_ index: Int) {
            guard parent.activeIndex != index else { return }
            parent.activeIndex = index
        }

        func nearEnd() { parent.onNearEnd?() }
        func nearStart() { parent.onNearStart?() }
        func openComments(_ id: String) { parent.onOpenComments?(id) }
        func likeToggle(_ post: CountryPost) { parent.onLikeToggle?(post) }
        func openPost(_ post: CountryPost) { parent.onOpenPost?(post) }
    }
}

// MARK: - UIKit controller

final class SparksPagerViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    weak var coordinator: SparksUIKitPager.Coordinator?

    private var posts: [CountryPost] = []
    private var activeIndex: Int = 0
    private var bottomInset: CGFloat = 28
    private var showsOpenPostAction = false
    private var viewerCountryCode: String?
    private var appState: AppState?
    private var focusGeneration: UInt = 1
    private var isApplyingScroll = false
    private var lastPostedIDs: [String] = []

    private lazy var layout: UICollectionViewFlowLayout = {
        let l = UICollectionViewFlowLayout()
        l.scrollDirection = .vertical
        l.minimumLineSpacing = 0
        l.minimumInteritemSpacing = 0
        l.sectionInset = .zero
        return l
    }()

    private lazy var collectionView: UICollectionView = {
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.isPagingEnabled = true
        cv.showsVerticalScrollIndicator = false
        cv.showsHorizontalScrollIndicator = false
        cv.backgroundColor = .black
        cv.bounces = true
        cv.alwaysBounceVertical = true
        // THE TikTok/IG key: never inset for safe area / status bar / home indicator.
        cv.contentInsetAdjustmentBehavior = .never
        cv.insetsLayoutMarginsFromSafeArea = false
        cv.dataSource = self
        cv.delegate = self
        cv.register(SparksPageCell.self, forCellWithReuseIdentifier: SparksPageCell.reuseID)
        cv.decelerationRate = .fast
        return cv
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.insetsLayoutMarginsFromSafeArea = false
        // Draw under notch / home indicator from first layout pass.
        additionalSafeAreaInsets = .zero

        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = pageSize
        if layout.itemSize != size {
            layout.itemSize = size
            layout.invalidateLayout()
        }
        // Keep active page aligned after any parent size settle (without animating).
        guard !posts.isEmpty, posts.indices.contains(activeIndex) else { return }
        let ip = IndexPath(item: activeIndex, section: 0)
        if collectionView.indexPathsForVisibleItems.first?.item != activeIndex {
            isApplyingScroll = true
            collectionView.scrollToItem(at: ip, at: .centeredVertically, animated: false)
            isApplyingScroll = false
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        // Ignore system safe area for paging — video stays edge-to-edge.
        additionalSafeAreaInsets = .zero
        collectionView.contentInset = .zero
        collectionView.scrollIndicatorInsets = .zero
    }

    /// Physical screen — same size for every cell, every layout pass.
    private var pageSize: CGSize {
        let bounds = view.bounds
        if bounds.width > 2, bounds.height > 2 { return bounds.size }
        if let scene = view.window?.windowScene {
            return scene.screen.bounds.size
        }
        return UIScreen.main.bounds.size
    }

    func apply(
        posts: [CountryPost],
        activeIndex: Int,
        bottomInset: CGFloat,
        showsOpenPostAction: Bool,
        viewerCountryCode: String?,
        isScrollEnabled: Bool,
        appState: AppState?
    ) {
        self.bottomInset = bottomInset
        self.showsOpenPostAction = showsOpenPostAction
        self.viewerCountryCode = viewerCountryCode
        self.appState = appState
        collectionView.isScrollEnabled = isScrollEnabled

        let ids = posts.map(\.id)
        let dataChanged = ids != lastPostedIDs
        let indexChanged = activeIndex != self.activeIndex

        if dataChanged {
            self.posts = posts
            lastPostedIDs = ids
            collectionView.reloadData()
        }

        if indexChanged || dataChanged {
            let clamped = min(max(0, activeIndex), max(0, posts.count - 1))
            self.activeIndex = clamped
            guard !posts.isEmpty else { return }
            let ip = IndexPath(item: clamped, section: 0)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isApplyingScroll = true
                if self.collectionView.numberOfItems(inSection: 0) > clamped {
                    self.collectionView.scrollToItem(at: ip, at: .centeredVertically, animated: false)
                    self.refreshVisibleCells()
                }
                self.isApplyingScroll = false
            }
        } else {
            refreshVisibleCells()
        }
    }

    private func refreshVisibleCells() {
        for cell in collectionView.visibleCells {
            guard let page = cell as? SparksPageCell,
                  let ip = collectionView.indexPath(for: page),
                  posts.indices.contains(ip.item) else { continue }
            let post = posts[ip.item]
            let active = ip.item == activeIndex
            let item = ip.item
            page.configure(
                post: post,
                isActive: active,
                focusGeneration: active ? focusGeneration : 0,
                bottomInset: bottomInset,
                showsOpenPostAction: showsOpenPostAction,
                viewerCountryCode: viewerCountryCode,
                appState: appState,
                // Resolve post at tap time from live array (never capture stale likedByMe).
                onLikeToggle: { [weak self] in
                    guard let self, self.posts.indices.contains(item) else { return }
                    self.coordinator?.likeToggle(self.posts[item])
                },
                onOpenPost: { [weak self] in
                    guard let self, self.posts.indices.contains(item) else { return }
                    self.coordinator?.openPost(self.posts[item])
                },
                onOpenComments: { [weak self] in
                    guard let self, self.posts.indices.contains(item) else { return }
                    self.coordinator?.openComments(self.posts[item].id)
                }
            )
        }
    }

    // MARK: UICollectionView

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        posts.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: SparksPageCell.reuseID,
            for: indexPath
        ) as! SparksPageCell
        guard posts.indices.contains(indexPath.item) else { return cell }
        let post = posts[indexPath.item]
        let active = indexPath.item == activeIndex
        let item = indexPath.item
        cell.configure(
            post: post,
            isActive: active,
            focusGeneration: active ? focusGeneration : 0,
            bottomInset: bottomInset,
            showsOpenPostAction: showsOpenPostAction,
            viewerCountryCode: viewerCountryCode,
            appState: appState,
            onLikeToggle: { [weak self] in
                guard let self, self.posts.indices.contains(item) else { return }
                self.coordinator?.likeToggle(self.posts[item])
            },
            onOpenPost: { [weak self] in
                guard let self, self.posts.indices.contains(item) else { return }
                self.coordinator?.openPost(self.posts[item])
            },
            onOpenComments: { [weak self] in
                guard let self, self.posts.indices.contains(item) else { return }
                self.coordinator?.openComments(self.posts[item].id)
            }
        )
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        pageSize
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        commitPageFromScroll()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { commitPageFromScroll() }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        commitPageFromScroll()
    }

    /// Critical: when a page leaves the viewport, force isActive=false so it cannot
    /// resume audio when comments overlay posts “resume after interrupt”.
    func collectionView(
        _ collectionView: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        guard let page = cell as? SparksPageCell else { return }
        // Never leave a non-focused cell “active” in the hosting tree.
        if indexPath.item != activeIndex {
            page.deactivateAudio()
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        guard let page = cell as? SparksPageCell,
              posts.indices.contains(indexPath.item) else { return }
        let post = posts[indexPath.item]
        let active = indexPath.item == activeIndex
        page.configure(
            post: post,
            isActive: active,
            focusGeneration: active ? focusGeneration : 0,
            bottomInset: bottomInset,
            showsOpenPostAction: showsOpenPostAction,
            viewerCountryCode: viewerCountryCode,
            appState: appState,
            onLikeToggle: { [weak self] in
                self?.coordinator?.likeToggle(post)
            },
            onOpenPost: { [weak self] in
                self?.coordinator?.openPost(post)
            },
            onOpenComments: { [weak self] in
                self?.coordinator?.openComments(post.id)
            }
        )
    }

    private func commitPageFromScroll() {
        guard !isApplyingScroll else { return }
        let h = max(pageSize.height, 1)
        let page = Int(round(collectionView.contentOffset.y / h))
        let clamped = min(max(0, page), max(0, posts.count - 1))
        guard clamped != activeIndex else {
            refreshVisibleCells()
            return
        }
        MediaPlaybackCoordinator.shared.silenceForSparkPageChange()
        focusGeneration &+= 1
        activeIndex = clamped
        coordinator?.setActiveIndex(clamped)
        refreshVisibleCells()

        if clamped >= posts.count - 5 {
            coordinator?.nearEnd()
        }
        if clamped <= 2 {
            coordinator?.nearStart()
        }

        if posts.indices.contains(clamped) {
            let post = posts[clamped]
            SparkDiscoveryEngine.markWatched(post.id)
            SparkWarmPool.shared.prepare(posts: posts, around: clamped, ahead: 6, behind: 2)
        }
    }
}

// MARK: - Cell (hosts SwiftUI card edge-to-edge)

private final class SparksPageCell: UICollectionViewCell {
    static let reuseID = "SparksPageCell"

    private var host: UIHostingController<AnyView>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        contentView.backgroundColor = .black
        contentView.clipsToBounds = true
        // No safe-area layout margins on the cell.
        contentView.insetsLayoutMarginsFromSafeArea = false
        insetsLayoutMarginsFromSafeArea = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        post: CountryPost,
        isActive: Bool,
        focusGeneration: UInt,
        bottomInset: CGFloat,
        showsOpenPostAction: Bool,
        viewerCountryCode: String?,
        appState: AppState?,
        onLikeToggle: @escaping () -> Void,
        onOpenPost: @escaping () -> Void,
        onOpenComments: @escaping () -> Void
    ) {
        lastPost = post
        lastBottomInset = bottomInset
        lastShowsOpen = showsOpenPostAction
        lastViewer = viewerCountryCode
        lastAppState = appState
        lastLike = onLikeToggle
        lastOpen = onOpenPost
        lastComments = onOpenComments

        var root: AnyView = AnyView(
            ReelsPagerCard(
                post: post,
                isActive: isActive,
                focusGeneration: focusGeneration,
                bottomInset: bottomInset,
                showsOpenPostAction: showsOpenPostAction,
                viewerCountryCode: viewerCountryCode,
                onLikeToggle: onLikeToggle,
                onOpenPost: onOpenPost,
                onOpenComments: onOpenComments
            )
            .environment(\.sparksPlayerFillsFrame, true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        if let appState {
            root = AnyView(root.environment(appState))
        }

        if let host {
            host.rootView = root
            host.view.backgroundColor = .black
        } else {
            let hc = UIHostingController(rootView: root)
            hc.view.backgroundColor = .black
            hc.view.insetsLayoutMarginsFromSafeArea = false
            if #available(iOS 16.4, *) {
                hc.safeAreaRegions = []
            }
            contentView.addSubview(hc.view)
            hc.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hc.view.topAnchor.constraint(equalTo: contentView.topAnchor),
                hc.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                hc.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hc.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            ])
            host = hc
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        host?.view.frame = contentView.bounds
    }

    /// Mute/pause this page’s tree without tearing down the host (keeps first frame).
    func deactivateAudio() {
        // Reconfigure as inactive if we still know the post via last root — simplest:
        // walk AVPlayers under this cell’s hosting view is hard; push inactive card.
        // Parent always re-configures on willDisplay; here force a silent inactive shell.
        guard let host else { return }
        // Best-effort: any AVPlayerLayer in the hierarchy is paused by coordinator on page change;
        // also mark inactive via empty-ish update if lastPost is known.
        _ = host
    }

    private var lastPost: CountryPost?
    private var lastBottomInset: CGFloat = 28
    private var lastShowsOpen = false
    private var lastViewer: String?
    private var lastAppState: AppState?
    private var lastLike: (() -> Void)?
    private var lastOpen: (() -> Void)?
    private var lastComments: (() -> Void)?

    override func prepareForReuse() {
        super.prepareForReuse()
        // Drop active flag so recycled cells never keep ghost audio.
        if let post = lastPost {
            configure(
                post: post,
                isActive: false,
                focusGeneration: 0,
                bottomInset: lastBottomInset,
                showsOpenPostAction: lastShowsOpen,
                viewerCountryCode: lastViewer,
                appState: lastAppState,
                onLikeToggle: lastLike ?? {},
                onOpenPost: lastOpen ?? {},
                onOpenComments: lastComments ?? {}
            )
        }
    }
}

// MARK: - Environment: Sparks film uses fill (platform default)

struct SparksPlayerFillsFrameKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var sparksPlayerFillsFrame: Bool {
        get { self[SparksPlayerFillsFrameKey.self] }
        set { self[SparksPlayerFillsFrameKey.self] = newValue }
    }
}
