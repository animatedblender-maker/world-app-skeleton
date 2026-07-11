import SwiftUI

struct UnreadBadge: View {
    let count: Int
    var size: CGFloat = 18

    var body: some View {
        if count > 0 {
            ZStack {
                Circle()
                    .fill(Theme.danger)
                    .frame(width: size, height: size)
                Circle()
                    .stroke(Theme.surface, lineWidth: 2)
                    .frame(width: size, height: size)
                Text(count > 9 ? "9+" : "\(count)")
                    .font(.system(size: size * 0.52, weight: .bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityLabel("\(count) unread")
        }
    }
}

struct UnreadDot: View {
    var size: CGFloat = 9

    var body: some View {
        Circle()
            .fill(Theme.danger)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(Theme.surface, lineWidth: 1.5)
            )
    }
}