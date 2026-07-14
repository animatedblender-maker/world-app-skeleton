import SwiftUI

struct FloatingPostsOverlay: View {
    let posts: [CountryPost]

    @State private var offsets: [String: CGPoint] = [:]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                    let position = offsets[post.id] ?? randomPosition(index: index, size: geo.size)
                    Text(shortText(post))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.accentBright)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Theme.surface.opacity(0.92))
                                .shadow(color: Theme.ink.opacity(0.08), radius: 8, y: 4)
                        )
                        .overlay(Capsule().stroke(Theme.border, lineWidth: 0.5))
                        .position(position)
                        .onAppear {
                            if offsets[post.id] == nil {
                                offsets[post.id] = position
                            }
                        }
                        .animation(
                            .easeInOut(duration: Double.random(in: 4...8))
                                .repeatForever(autoreverses: true),
                            value: offsets[post.id]
                        )
                }
            }
            .onAppear {
                for (index, post) in posts.enumerated() {
                    offsets[post.id] = randomPosition(index: index, size: geo.size)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func shortText(_ post: CountryPost) -> String {
        let text = post.displayCaption ?? post.displayHeadline ?? post.authorDisplayName
        return String(text.prefix(28))
    }

    private func randomPosition(index: Int, size: CGSize) -> CGPoint {
        let seed = Double(index + 1)
        let x = size.width * (0.15 + 0.7 * (sin(seed) * 0.5 + 0.5))
        let y = size.height * (0.2 + 0.55 * (cos(seed * 1.7) * 0.5 + 0.5))
        return CGPoint(x: x, y: y)
    }
}