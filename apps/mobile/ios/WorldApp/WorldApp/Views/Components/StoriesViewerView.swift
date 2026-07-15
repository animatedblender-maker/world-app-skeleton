import SwiftUI

struct StoriesViewerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var context: StoryViewerContext
    @State private var progress: CGFloat = 0
    @State private var timerTask: Task<Void, Never>?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false

    init(context: StoryViewerContext) {
        _context = State(initialValue: context)
    }

    private var currentGroup: StoryGroup? {
        guard context.groups.indices.contains(context.groupIndex) else { return nil }
        return context.groups[context.groupIndex]
    }

    private var currentStory: CountryPost? {
        guard let group = currentGroup, group.stories.indices.contains(context.storyIndex) else { return nil }
        return group.stories[context.storyIndex]
    }

    private var isOwnMoment: Bool {
        guard let story = currentStory,
              let userID = appState.currentProfile?.userID
        else { return false }
        return story.authorID == userID
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let story = currentStory {
                storyContent(story)
            } else {
                ProgressView().tint(.white)
            }

            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { goPrevious() }
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { goNext() }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topChrome
                Spacer(minLength: 0)
                if let story = currentStory, !story.displayBody.isEmpty {
                    Text(story.displayBody)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(4)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.55)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .safeAreaPadding(.top, 6)
            .safeAreaPadding(.bottom, 8)
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            if let story = currentStory {
                appState.markStoryViewed(story.id)
            }
            startTimer()
        }
        .onDisappear {
            timerTask?.cancel()
        }
        .onChange(of: context.storyIndex) { _, _ in
            restartTimer()
        }
        .onChange(of: context.groupIndex) { _, _ in
            restartTimer()
        }
        .confirmationDialog(
            "Delete this moment?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete moment", role: .destructive) {
                Task { await deleteCurrentMoment() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will disappear from Globe moments right away.")
        }
        .overlay {
            if isDeleting {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    ProgressView("Removing moment…")
                        .tint(.white)
                        .foregroundStyle(.white)
                }
            }
        }
    }

    @ViewBuilder
    private func storyContent(_ story: CountryPost) -> some View {
        GeometryReader { geometry in
            Group {
                if story.hasVideo, let url = story.playableVideoURL {
                    VideoPlayerView(
                        url: url,
                        posterURL: story.posterImageURL,
                        adsEnabled: false,
                        isActive: true,
                        loops: false
                    )
                } else if let url = story.resolvedImageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            ProgressView().tint(.white)
                        }
                    }
                } else {
                    Text(story.displayBody)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }

    private var topChrome: some View {
        VStack(spacing: 8) {
            progressBars
            header
        }
        .padding(.bottom, 10)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.68), Color.black.opacity(0.34), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var progressBars: some View {
        HStack(spacing: 4) {
            if let group = currentGroup {
                ForEach(Array(group.stories.enumerated()), id: \.element.id) { index, _ in
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.25))
                            Capsule()
                                .fill(Color.white)
                                .frame(width: barWidth(for: index, totalWidth: proxy.size.width))
                        }
                    }
                    .frame(height: 3)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private func barWidth(for index: Int, totalWidth: CGFloat) -> CGFloat {
        if index < context.storyIndex { return totalWidth }
        if index > context.storyIndex { return 0 }
        return totalWidth * progress
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            if let group = currentGroup {
                AvatarView(url: group.author?.avatarURL, seed: group.authorID, size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                    if let story = currentStory {
                        Text(momentUploadedLabel(for: story.createdAt))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isOwnMoment {
                Button {
                    timerTask?.cancel()
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.28), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete moment")
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.28), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private func startTimer() {
        timerTask?.cancel()
        progress = 0
        guard currentStory != nil else { return }

        let duration: UInt64 = currentStory?.hasVideo == true ? 12_000_000_000 : 5_000_000_000
        timerTask = Task {
            let steps = 50
            let stepNanos = duration / UInt64(steps)
            for step in 1...steps {
                try? await Task.sleep(nanoseconds: stepNanos)
                if Task.isCancelled { return }
                await MainActor.run {
                    progress = CGFloat(step) / CGFloat(steps)
                }
            }
            if !Task.isCancelled {
                await MainActor.run { goNext() }
            }
        }
    }

    private func restartTimer() {
        if let story = currentStory {
            appState.markStoryViewed(story.id)
        }
        startTimer()
    }

    private func goNext() {
        guard let group = currentGroup else {
            dismiss()
            return
        }

        if context.storyIndex < group.stories.count - 1 {
            context.storyIndex += 1
            return
        }

        if context.groupIndex < context.groups.count - 1 {
            context.groupIndex += 1
            context.storyIndex = 0
            return
        }

        dismiss()
    }

    private func goPrevious() {
        if context.storyIndex > 0 {
            context.storyIndex -= 1
            return
        }

        if context.groupIndex > 0 {
            context.groupIndex -= 1
            context.storyIndex = max(0, context.groups[context.groupIndex].stories.count - 1)
            return
        }

        progress = 0
        startTimer()
    }

    private func deleteCurrentMoment() async {
        guard let story = currentStory else { return }
        isDeleting = true
        timerTask?.cancel()
        defer { isDeleting = false }

        do {
            let deleted = try await PostsService.shared.deletePost(story.id)
            guard deleted else {
                appState.showToast("Could not delete moment.", style: .error)
                startTimer()
                return
            }

            var groups = context.groups
            guard groups.indices.contains(context.groupIndex) else {
                await appState.refreshStories()
                dismiss()
                return
            }

            let current = groups[context.groupIndex]
            let remainingStories = current.stories.filter { $0.id != story.id }
            var nextGroupIndex = context.groupIndex
            var nextStoryIndex = context.storyIndex

            if remainingStories.isEmpty {
                groups.remove(at: context.groupIndex)
                if groups.isEmpty {
                    await appState.refreshStories()
                    appState.showToast("Moment deleted.", style: .success)
                    dismiss()
                    return
                }
                if nextGroupIndex >= groups.count {
                    nextGroupIndex = max(0, groups.count - 1)
                }
                nextStoryIndex = 0
            } else {
                groups[context.groupIndex] = StoryGroup(
                    authorID: current.authorID,
                    author: current.author,
                    stories: remainingStories,
                    hasUnviewed: current.hasUnviewed
                )
                if nextStoryIndex >= remainingStories.count {
                    nextStoryIndex = max(0, remainingStories.count - 1)
                }
            }

            context = StoryViewerContext(
                groups: groups,
                groupIndex: nextGroupIndex,
                storyIndex: nextStoryIndex
            )
            await appState.refreshStories()
            appState.showToast("Moment deleted.", style: .success)
            startTimer()
        } catch {
            appState.showToast(error.localizedDescription, style: .error)
            startTimer()
        }
    }

    private func momentUploadedLabel(for createdAt: String) -> String {
        let relative = RelativeTime.format(createdAt)
        let clock = RelativeTime.formatClock(createdAt)
        switch (relative.isEmpty, clock.isEmpty) {
        case (false, false): return "\(relative) · \(clock)"
        case (false, true): return relative
        case (true, false): return clock
        case (true, true): return "Moment"
        }
    }
}