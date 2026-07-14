import SwiftUI

struct StoriesViewerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var context: StoryViewerContext
    @State private var progress: CGFloat = 0
    @State private var timerTask: Task<Void, Never>?

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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let story = currentStory {
                storyContent(story)
            } else {
                ProgressView().tint(.white)
            }

            VStack(spacing: 0) {
                progressBars
                header
                Spacer()
                if let story = currentStory, !story.displayBody.isEmpty {
                    Text(story.displayBody)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.35))
                }
            }
            .safeAreaPadding(.top, 6)
            .safeAreaPadding(.bottom, 8)

            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { goPrevious() }
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { goNext() }
            }
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
    }

    @ViewBuilder
    private func storyContent(_ story: CountryPost) -> some View {
        if story.hasVideo, let url = story.playableVideoURL {
            VideoPlayerView(
                url: url,
                posterURL: story.posterImageURL,
                adsEnabled: false,
                isActive: true,
                loops: false
            )
            .ignoresSafeArea()
        } else if let url = story.resolvedImageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                default:
                    ProgressView().tint(.white)
                }
            }
        } else {
            Text(story.displayBody)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .padding()
        }
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
        HStack(spacing: 10) {
            if let group = currentGroup {
                AvatarView(url: group.author?.avatarURL, seed: group.authorID, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    if let story = currentStory {
                        Text(momentUploadedLabel(for: story.createdAt))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(8)
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