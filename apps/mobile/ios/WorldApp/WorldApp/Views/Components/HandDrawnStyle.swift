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

/// Matterya like / dislike mark — crisp custom icon (not SF Symbol, not sketch).
/// Pad carries a cut Matterya **M**. `up: true` = like; `up: false` = dislike (flipped).
struct MatteryaThumbIcon: View {
    var up: Bool = true
    var filled: Bool = false
    var size: CGFloat = 18
    var color: Color = Theme.ink

    var body: some View {
        Canvas { context, canvasSize in
            let thumb = Self.thumbPath(in: canvasSize)
            let strokeW = max(1.35, size * 0.085)

            if filled {
                // Solid thumb with M punched out of the pad (brand cut).
                let cut = Self.mRibbonPath(in: canvasSize)
                context.drawLayer { layer in
                    layer.fill(thumb, with: .color(color))
                    layer.blendMode = .destinationOut
                    layer.fill(cut, with: .color(.black))
                }
            } else {
                // Clean outline + stroked M monogram in the pad.
                context.stroke(
                    thumb,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round)
                )
                context.stroke(
                    Self.mStrokePath(in: canvasSize),
                    with: .color(color),
                    style: StrokeStyle(
                        lineWidth: max(1.1, size * 0.07),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(up ? 0 : 180))
        .accessibilityHidden(true)
    }

    /// Geometric thumb: rounded pad + straight knuckle column (icon, not ink blob).
    private static func thumbPath(in size: CGSize) -> Path {
        let w = size.width
        let h = size.height
        var path = Path()

        // Pad — upright rounded tip above a crisp stalk.
        path.move(to: CGPoint(x: w * 0.42, y: h * 0.46))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.38, y: h * 0.18),
            control: CGPoint(x: w * 0.30, y: h * 0.36)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.58, y: h * 0.06),
            control: CGPoint(x: w * 0.42, y: h * 0.04)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.86, y: h * 0.28),
            control: CGPoint(x: w * 0.78, y: h * 0.08)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.70, y: h * 0.48),
            control: CGPoint(x: w * 0.92, y: h * 0.44)
        )

        // Knuckle column — rounded rectangle under the pad.
        path.addLine(to: CGPoint(x: w * 0.70, y: h * 0.78))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.58, y: h * 0.92),
            control: CGPoint(x: w * 0.70, y: h * 0.92)
        )
        path.addLine(to: CGPoint(x: w * 0.30, y: h * 0.92))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.22, y: h * 0.78),
            control: CGPoint(x: w * 0.22, y: h * 0.92)
        )
        path.addLine(to: CGPoint(x: w * 0.22, y: h * 0.50))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.42, y: h * 0.46),
            control: CGPoint(x: w * 0.22, y: h * 0.46)
        )
        path.closeSubpath()
        return path
    }

    private static func mBox(in size: CGSize) -> (left: CGFloat, right: CGFloat, top: CGFloat, bot: CGFloat, midX: CGFloat, midY: CGFloat) {
        let w = size.width
        let h = size.height
        let left = w * 0.48
        let right = w * 0.78
        let top = h * 0.15
        let bot = h * 0.39
        return (left, right, top, bot, (left + right) / 2, top + (bot - top) * 0.62)
    }

    /// Open polyline M for outline mode.
    private static func mStrokePath(in size: CGSize) -> Path {
        let b = mBox(in: size)
        var m = Path()
        m.move(to: CGPoint(x: b.left, y: b.bot))
        m.addLine(to: CGPoint(x: b.left, y: b.top))
        m.addLine(to: CGPoint(x: b.midX, y: b.midY))
        m.addLine(to: CGPoint(x: b.right, y: b.top))
        m.addLine(to: CGPoint(x: b.right, y: b.bot))
        return m
    }

    /// Thick closed M for destinationOut cut when filled.
    private static func mRibbonPath(in size: CGSize) -> Path {
        let b = mBox(in: size)
        let t = max(size.width * 0.048, 1.15)
        var path = Path()
        path.move(to: CGPoint(x: b.left - t, y: b.bot))
        path.addLine(to: CGPoint(x: b.left - t, y: b.top))
        path.addLine(to: CGPoint(x: b.left + t, y: b.top))
        path.addLine(to: CGPoint(x: b.midX, y: b.midY - t * 0.2))
        path.addLine(to: CGPoint(x: b.right - t, y: b.top))
        path.addLine(to: CGPoint(x: b.right + t, y: b.top))
        path.addLine(to: CGPoint(x: b.right + t, y: b.bot))
        path.addLine(to: CGPoint(x: b.right - t, y: b.bot))
        path.addLine(to: CGPoint(x: b.right - t, y: b.top + (b.bot - b.top) * 0.40))
        path.addLine(to: CGPoint(x: b.midX, y: b.midY + t * 1.05))
        path.addLine(to: CGPoint(x: b.left + t, y: b.top + (b.bot - b.top) * 0.40))
        path.addLine(to: CGPoint(x: b.left + t, y: b.bot))
        path.closeSubpath()
        return path
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

    /// Soft filled sketch — multiple slightly offset fills like ink from a brush.
    static func brushFill(_ path: Path, in context: GraphicsContext, color: Color) {
        let offsets: [CGSize] = [
            .zero,
            CGSize(width: 0.4, height: -0.25),
            CGSize(width: -0.35, height: 0.3),
            CGSize(width: 0.2, height: 0.35),
        ]
        for (index, offset) in offsets.enumerated() {
            var ctx = context
            ctx.translateBy(x: offset.width, y: offset.height)
            let opacity = index == 0 ? 0.92 : 0.14
            ctx.fill(path, with: .color(color.opacity(opacity)))
        }
    }
}

/// Hubs mark: hand-drawn TV / monitor with the Matterya app icon on the screen.
struct MatteryaHubsLogoView: View {
    var size: CGFloat = 28
    /// Off-white brush ink for the TV outline.
    var ink: Color = Color(red: 0.22, green: 0.20, blue: 0.18)
    var screenFill: Color = Color(red: 0.97, green: 0.96, blue: 0.93)

    var body: some View {
        ZStack {
            Canvas { context, canvasSize in
                let w = canvasSize.width
                let h = canvasSize.height
                // Screen area (upper ~72% of mark)
                let screenRect = CGRect(
                    x: w * 0.08,
                    y: h * 0.06,
                    width: w * 0.84,
                    height: h * 0.62
                )
                let screen = wobblyRoundedRect(screenRect, corner: w * 0.12, wobble: w * 0.02)

                // Soft screen wash
                let wash = context
                wash.fill(screen, with: .color(screenFill.opacity(0.95)))
                HandDrawnStroke.sketch(screen, in: context, color: ink, width: max(1.6, size * 0.07))

                // Stand neck
                let neckTop = CGPoint(x: w * 0.5, y: screenRect.maxY + h * 0.02)
                let neckBot = CGPoint(x: w * 0.5, y: h * 0.82)
                var neck = Path()
                neck.move(to: CGPoint(x: neckTop.x - w * 0.03, y: neckTop.y))
                neck.addLine(to: CGPoint(x: neckBot.x - w * 0.04, y: neckBot.y))
                neck.addLine(to: CGPoint(x: neckBot.x + w * 0.04, y: neckBot.y))
                neck.addLine(to: CGPoint(x: neckTop.x + w * 0.03, y: neckTop.y))
                neck.closeSubpath()
                HandDrawnStroke.brushFill(neck, in: context, color: ink.opacity(0.85))
                HandDrawnStroke.sketch(neck, in: context, color: ink, width: max(1.2, size * 0.045))

                // Base plate
                let baseY = h * 0.88
                var base = Path()
                base.move(to: CGPoint(x: w * 0.22, y: baseY))
                base.addQuadCurve(
                    to: CGPoint(x: w * 0.78, y: baseY + h * 0.02),
                    control: CGPoint(x: w * 0.5, y: baseY + h * 0.06)
                )
                base.addQuadCurve(
                    to: CGPoint(x: w * 0.22, y: baseY),
                    control: CGPoint(x: w * 0.5, y: baseY - h * 0.02)
                )
                HandDrawnStroke.sketch(base, in: context, color: ink, width: max(1.8, size * 0.065))

                // Tiny antenna nubs (optional TV vibe)
                var antL = Path()
                antL.move(to: CGPoint(x: w * 0.32, y: screenRect.minY + h * 0.02))
                antL.addLine(to: CGPoint(x: w * 0.26, y: h * 0.02))
                var antR = Path()
                antR.move(to: CGPoint(x: w * 0.68, y: screenRect.minY + h * 0.02))
                antR.addLine(to: CGPoint(x: w * 0.74, y: h * 0.015))
                HandDrawnStroke.sketch(antL, in: context, color: ink, width: max(1.2, size * 0.04))
                HandDrawnStroke.sketch(antR, in: context, color: ink, width: max(1.2, size * 0.04))
            }
            .frame(width: size, height: size)

            // Matterya logo inset on the TV screen
            MatteryaAppIconView(size: size * 0.42)
                .offset(y: -size * 0.12)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(MatteryaCopy.matteryaHubs)
    }

    private func wobblyRoundedRect(_ rect: CGRect, corner: CGFloat, wobble: CGFloat) -> Path {
        // Approximate rounded rect with slightly jittered corners.
        let r = min(corner, min(rect.width, rect.height) / 2)
        var path = Path()
        let inset = wobble
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY + inset * 0.3))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY - inset * 0.2))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX + inset * 0.2, y: rect.minY + r),
            control: CGPoint(x: rect.maxX + inset, y: rect.minY - inset * 0.3)
        )
        path.addLine(to: CGPoint(x: rect.maxX - inset * 0.15, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY + inset * 0.25),
            control: CGPoint(x: rect.maxX + inset * 0.4, y: rect.maxY + inset * 0.2)
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY - inset * 0.1))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX - inset * 0.2, y: rect.maxY - r),
            control: CGPoint(x: rect.minX - inset * 0.5, y: rect.maxY + inset * 0.15)
        )
        path.addLine(to: CGPoint(x: rect.minX + inset * 0.1, y: rect.minY + r))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + r, y: rect.minY + inset * 0.3),
            control: CGPoint(x: rect.minX - inset * 0.3, y: rect.minY - inset * 0.2)
        )
        path.closeSubpath()
        return path
    }
}

/// Masquerade mark: simple Venetian half-mask (same glyph in header + tab bar).
struct MatteryaMasqueradeLogoView: View {
    var size: CGFloat = 26
    var ink: Color = Color(red: 0.22, green: 0.20, blue: 0.18)
    var fill: Color = Color(red: 0.97, green: 0.96, blue: 0.93)

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let stroke = max(1.4, size * 0.07)

            // Clean domino silhouette — wide across the eyes, soft cheek dips, no flourishes.
            var mask = Path()
            mask.move(to: CGPoint(x: w * 0.06, y: h * 0.46))
            mask.addQuadCurve(
                to: CGPoint(x: w * 0.22, y: h * 0.22),
                control: CGPoint(x: w * 0.05, y: h * 0.28)
            )
            mask.addQuadCurve(
                to: CGPoint(x: w * 0.50, y: h * 0.16),
                control: CGPoint(x: w * 0.34, y: h * 0.12)
            )
            mask.addQuadCurve(
                to: CGPoint(x: w * 0.78, y: h * 0.22),
                control: CGPoint(x: w * 0.66, y: h * 0.12)
            )
            mask.addQuadCurve(
                to: CGPoint(x: w * 0.94, y: h * 0.46),
                control: CGPoint(x: w * 0.95, y: h * 0.28)
            )
            mask.addQuadCurve(
                to: CGPoint(x: w * 0.78, y: h * 0.64),
                control: CGPoint(x: w * 0.96, y: h * 0.58)
            )
            mask.addQuadCurve(
                to: CGPoint(x: w * 0.50, y: h * 0.72),
                control: CGPoint(x: w * 0.66, y: h * 0.78)
            )
            mask.addQuadCurve(
                to: CGPoint(x: w * 0.22, y: h * 0.64),
                control: CGPoint(x: w * 0.34, y: h * 0.78)
            )
            mask.addQuadCurve(
                to: CGPoint(x: w * 0.06, y: h * 0.46),
                control: CGPoint(x: w * 0.04, y: h * 0.58)
            )
            mask.closeSubpath()

            context.fill(mask, with: .color(fill.opacity(0.97)))
            HandDrawnStroke.sketch(mask, in: context, color: ink, width: stroke)

            // Two simple almond eyes — solid, readable at tab-bar size.
            func eye(cx: CGFloat) -> Path {
                var p = Path()
                let left = cx - w * 0.11
                let right = cx + w * 0.11
                let midY = h * 0.44
                p.move(to: CGPoint(x: left, y: midY))
                p.addQuadCurve(
                    to: CGPoint(x: right, y: midY),
                    control: CGPoint(x: cx, y: midY - h * 0.11)
                )
                p.addQuadCurve(
                    to: CGPoint(x: left, y: midY),
                    control: CGPoint(x: cx, y: midY + h * 0.10)
                )
                p.closeSubpath()
                return p
            }
            HandDrawnStroke.brushFill(eye(cx: w * 0.32), in: context, color: ink.opacity(0.9))
            HandDrawnStroke.brushFill(eye(cx: w * 0.68), in: context, color: ink.opacity(0.9))

            // Tiny bridge notch between the eyes (classic mask cue).
            var bridge = Path()
            bridge.move(to: CGPoint(x: w * 0.46, y: h * 0.36))
            bridge.addQuadCurve(
                to: CGPoint(x: w * 0.54, y: h * 0.36),
                control: CGPoint(x: w * 0.50, y: h * 0.32)
            )
            HandDrawnStroke.sketch(bridge, in: context, color: ink.opacity(0.45), width: max(1.0, size * 0.04))
        }
        .frame(width: size, height: size)
        .accessibilityLabel(MatteryaCopy.matteryaMasquerade)
    }
}

/// Header brand mark — parallel to PlayBrandMark (Matterya Hubs).
struct MasqueradeBrandMark: View {
    var compact: Bool = false
    var ringSize: CGFloat = 24

    private var wordmark: Text {
        Text(AppConfig.appName)
            .font(.system(size: compact ? 16 : 19, weight: .regular, design: .serif))
            .tracking(0.35)
        + Text("\u{00A0}Masquerade")
            .font(compact ? .headline.weight(.bold) : .title3.weight(.bold))
    }

    var body: some View {
        HStack(spacing: compact ? 5 : 6) {
            // Match BottomTabBar Masquerade glyph (same art, same optical size band).
            MatteryaMasqueradeLogoView(size: compact ? 24 : max(ringSize, 26))
            wordmark
                .foregroundStyle(Theme.ink)
                .matteryaBrandLine(minScale: compact ? 0.78 : 0.84)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(MatteryaCopy.matteryaMasquerade)
    }
}

/// Big brush-drawn play triangle only — no circle. Off-white / warm yellow ink (iPad brush feel).
struct HandDrawnBrushPlayButton: View {
    /// Overall mark size (triangle fills most of this).
    var size: CGFloat = 88
    /// Warm off-white yellowish (like cream paper ink), not pure white.
    var ink: Color = Color(red: 0.98, green: 0.95, blue: 0.86)

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            // Triangle uses almost the full frame — big and bold.
            let tri = brushPlayTriangle(center: center, size: min(canvasSize.width, canvasSize.height) * 0.92)

            // Soft dark halo so the cream mark pops on bright posters too.
            var halo = context
            halo.addFilter(.shadow(color: .black.opacity(0.35), radius: 5, x: 0, y: 2))
            HandDrawnStroke.brushFill(tri, in: halo, color: ink)

            // Extra brush passes — thicker, imperfect outline.
            HandDrawnStroke.sketch(tri, in: context, color: ink, width: max(2.4, size * 0.048))
            // Slight second stroke offset for “double brush” texture.
            var ctx2 = context
            ctx2.translateBy(x: 0.6, y: -0.4)
            HandDrawnStroke.sketch(tri, in: ctx2, color: ink.opacity(0.35), width: max(1.6, size * 0.03))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Play")
        .accessibilityAddTraits(.isButton)
    }

    private func brushPlayTriangle(center: CGPoint, size: CGFloat) -> Path {
        // Classic ▶ — large, slightly hand-skewed edges.
        let h = size * 0.88
        let w = size * 0.78
        let ox = size * 0.05
        let tip = CGPoint(x: center.x + w * 0.50 + ox, y: center.y + 0.6)
        let top = CGPoint(x: center.x - w * 0.46 + ox, y: center.y - h * 0.50)
        let bot = CGPoint(x: center.x - w * 0.44 + ox, y: center.y + h * 0.52)

        let midTop = CGPoint(
            x: (tip.x + top.x) / 2 + size * 0.03,
            y: (tip.y + top.y) / 2 - size * 0.025
        )
        let midBot = CGPoint(
            x: (tip.x + bot.x) / 2 - size * 0.02,
            y: (tip.y + bot.y) / 2 + size * 0.03
        )
        let midBack = CGPoint(
            x: (top.x + bot.x) / 2 - size * 0.035,
            y: (top.y + bot.y) / 2 + size * 0.01
        )

        var path = Path()
        path.move(to: top)
        path.addQuadCurve(to: tip, control: midTop)
        path.addQuadCurve(to: bot, control: midBot)
        path.addQuadCurve(to: top, control: midBack)
        path.closeSubpath()
        return path
    }
}
