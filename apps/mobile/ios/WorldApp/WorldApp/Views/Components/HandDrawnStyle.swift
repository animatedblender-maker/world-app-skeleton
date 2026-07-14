import SwiftUI

struct PaperBackground: View {
    var body: some View {
        Theme.paper
            .ignoresSafeArea()
    }
}

struct HandDrawnPlusIcon: View {
    var size: CGFloat = 28
    var color: Color = Theme.ink

    var body: some View {
        Canvas { context, canvasSize in
            let centerX = canvasSize.width / 2
            let centerY = canvasSize.height / 2
            let arm = size * 0.36

            var horizontal = Path()
            horizontal.move(to: CGPoint(x: centerX - arm, y: centerY + 0.4))
            horizontal.addLine(to: CGPoint(x: centerX + arm, y: centerY - 0.3))

            var vertical = Path()
            vertical.move(to: CGPoint(x: centerX - 0.3, y: centerY - arm))
            vertical.addLine(to: CGPoint(x: centerX + 0.5, y: centerY + arm))

            HandDrawnStroke.sketch(horizontal, in: context, color: color, width: 2.1)
            HandDrawnStroke.sketch(vertical, in: context, color: color, width: 2.1)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct HandDrawnGlobeStoryRing: View {
    var size: CGFloat = 62
    var highlighted: Bool = true

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let radius = min(canvasSize.width, canvasSize.height) / 2 - 1.5
            let ringColor = highlighted ? Theme.accent : Theme.inkMuted
            let meridianColor = highlighted ? Theme.oceanWash.opacity(0.95) : Theme.border

            let ring = wobblyCircle(center: center, radius: radius, segments: 28, wobble: 0.9)
            HandDrawnStroke.sketch(ring, in: context, color: ringColor, width: highlighted ? 2.3 : 1.6)

            if highlighted {
                let inner = wobblyCircle(center: center, radius: radius - 2.8, segments: 24, wobble: 0.45)
                HandDrawnStroke.sketch(inner, in: context, color: Theme.oceanWash.opacity(0.35), width: 0.9)
            }

            var leftMeridian = Path()
            leftMeridian.addArc(
                center: center,
                radius: radius - 4,
                startAngle: .degrees(-68),
                endAngle: .degrees(68),
                clockwise: false
            )
            HandDrawnStroke.sketch(leftMeridian, in: context, color: meridianColor, width: 1.0)

            var rightMeridian = Path()
            rightMeridian.addArc(
                center: center,
                radius: radius - 4,
                startAngle: .degrees(112),
                endAngle: .degrees(248),
                clockwise: false
            )
            HandDrawnStroke.sketch(rightMeridian, in: context, color: meridianColor, width: 1.0)

            var equator = Path()
            equator.move(to: CGPoint(x: center.x - radius + 3, y: center.y + 0.6))
            equator.addQuadCurve(
                to: CGPoint(x: center.x + radius - 3, y: center.y - 0.4),
                control: CGPoint(x: center.x, y: center.y + 2.4)
            )
            HandDrawnStroke.sketch(equator, in: context, color: meridianColor.opacity(0.85), width: 0.9)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func wobblyCircle(
        center: CGPoint,
        radius: CGFloat,
        segments: Int,
        wobble: CGFloat
    ) -> Path {
        var path = Path()
        for index in 0...segments {
            let progress = Double(index) / Double(segments)
            let angle = progress * 2 * .pi
            let offset = CGFloat(sin(angle * 4) * 0.55 + cos(angle * 6) * 0.35) * wobble
            let point = CGPoint(
                x: center.x + cos(angle) * (radius + offset),
                y: center.y + sin(angle) * (radius + offset)
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

enum HandDrawnStroke {
    static func sketch(_ path: Path, in context: GraphicsContext, color: Color, width: CGFloat = 1.1) {
        let offsets: [CGSize] = [
            .zero,
            CGSize(width: 0.35, height: 0.2),
            CGSize(width: -0.25, height: 0.15),
        ]
        for (index, offset) in offsets.enumerated() {
            let stroke = StrokeStyle(
                lineWidth: width - CGFloat(index) * 0.15,
                lineCap: .round,
                lineJoin: .round
            )
            var ctx = context
            ctx.translateBy(x: offset.width, y: offset.height)
            ctx.stroke(
                path,
                with: .color(color.opacity(index == 0 ? 0.88 : 0.18)),
                style: stroke
            )
        }
    }
}