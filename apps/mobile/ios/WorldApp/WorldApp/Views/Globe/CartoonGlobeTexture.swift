import UIKit
import CoreGraphics

enum CartoonGlobeTexture {
    private static let textureSize = CGSize(width: 2048, height: 1024)
    private static var cacheKey: String?
    private static var cachedImage: UIImage?

    static func image(for entries: [CountryMapEntry], selectedISO: String?) -> UIImage {
        let key = "v3-\(entries.count)-\(selectedISO ?? "none")"
        if cacheKey == key, let cachedImage { return cachedImage }

        let renderer = UIGraphicsImageRenderer(size: textureSize)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            paintOcean(in: cg)

            let sorted = entries.sorted { boundingArea($0) > boundingArea($1) }
            let selected = selectedISO?.uppercased()

            for entry in sorted {
                let isSelected = selected == entry.iso3.uppercased()
                    || selected == entry.iso2.uppercased()

                for ring in entry.rings {
                    let path = sketchPath(for: ring, wobble: 0.8)
                    let bounds = path.boundingBox

                    cg.saveGState()
                    cg.addPath(path)
                    cg.clip()
                    paintLandShading(in: cg, bounds: bounds, selected: isSelected, iso3: entry.iso3)
                    cg.restoreGState()

                    cg.setFillColor(landFill(iso3: entry.iso3, selected: isSelected).cgColor)
                    cg.addPath(path)
                    cg.fillPath()

                    drawSketchStroke(path, in: cg, selected: isSelected)
                    paintHatching(in: cg, path: path, selected: isSelected)
                }
            }

            paintLabels(entries: entries, in: cg)
            paintPaperGrain(in: cg)
        }

        cacheKey = key
        cachedImage = image
        return image
    }

    /// UV from SceneKit hit test (OpenGL: v=0 bottom). Converts to image-space point used when drawing.
    static func imagePoint(fromTextureUV u: CGFloat, v: CGFloat) -> CGPoint {
        CGPoint(
            x: u * textureSize.width,
            y: (1.0 - v) * textureSize.height
        )
    }

    static func country(atLng lng: Double, lat: Double, entries: [CountryMapEntry]) -> CountryMapEntry? {
        country(atMapPoint: equirectangular(lng: lng, lat: lat), entries: entries)
    }

    static func country(atTextureUV u: CGFloat, v: CGFloat, entries: [CountryMapEntry]) -> CountryMapEntry? {
        country(atMapPoint: imagePoint(fromTextureUV: u, v: v), entries: entries)
    }

    private static func country(atMapPoint point: CGPoint, entries: [CountryMapEntry]) -> CountryMapEntry? {
        let offsets: [CGFloat] = [0, -textureSize.width, textureSize.width]
        let reversed = entries.sorted { boundingArea($0) < boundingArea($1) }

        for dx in offsets {
            let test = CGPoint(x: point.x + dx, y: point.y)
            for entry in reversed {
                for ring in entry.rings {
                    if ring.count >= 3, pointInRing(test, ring: ring) {
                        return entry
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Theme palette

    private enum Palette {
        static let oceanTop = UIColor(red: 0.78, green: 0.84, blue: 0.88, alpha: 1)
        static let oceanBottom = UIColor(red: 0.62, green: 0.72, blue: 0.80, alpha: 1)
        static let ink = UIColor(red: 0.173, green: 0.157, blue: 0.145, alpha: 1)
        static let inkMuted = UIColor(red: 0.420, green: 0.392, blue: 0.365, alpha: 1)
        static let accent = UIColor(red: 0.482, green: 0.388, blue: 0.278, alpha: 1)
        static let landBase = UIColor(red: 0.910, green: 0.894, blue: 0.863, alpha: 1)
        static let landAlt = UIColor(red: 0.949, green: 0.941, blue: 0.925, alpha: 1)
        static let landWarm = UIColor(red: 0.929, green: 0.918, blue: 0.898, alpha: 1)
        static let landSelected = UIColor(red: 0.878, green: 0.839, blue: 0.776, alpha: 1)
        static let landTint = UIColor(red: 0.420, green: 0.345, blue: 0.255, alpha: 0.12)
    }

    // MARK: - Drawing

    private static func paintOcean(in ctx: CGContext) {
        let colors = [Palette.oceanTop.cgColor, Palette.oceanBottom.cgColor] as CFArray
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 1]
        ) {
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: textureSize.height),
                options: []
            )
        }

        ctx.setStrokeColor(Palette.ink.withAlphaComponent(0.04).cgColor)
        for index in 0..<12 {
            let y = CGFloat(index) * 88 + 30
            let wave = CGMutablePath()
            wave.move(to: CGPoint(x: 0, y: y))
            var x: CGFloat = 0
            while x <= textureSize.width {
                wave.addLine(to: CGPoint(x: x, y: y + sin(x * 0.02) * 6))
                x += 40
            }
            ctx.addPath(wave)
            ctx.strokePath()
        }
    }

    private static func paintLandShading(in ctx: CGContext, bounds: CGRect, selected: Bool, iso3: String) {
        let colors = [
            landFill(iso3: iso3, selected: selected).withAlphaComponent(0.0).cgColor,
            Palette.landTint.cgColor,
        ] as CFArray
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0.2, 1]
        ) {
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: bounds.minX, y: bounds.minY),
                end: CGPoint(x: bounds.minX, y: bounds.maxY),
                options: []
            )
        }
    }

    private static func drawSketchStroke(_ path: CGPath, in ctx: CGContext, selected: Bool) {
        let color = selected ? Palette.accent : Palette.ink.withAlphaComponent(0.82)
        ctx.saveGState()
        ctx.setStrokeColor(color.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(selected ? 1.8 : 1.1)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func paintHatching(in ctx: CGContext, path: CGPath, selected: Bool) {
        _ = ctx
        _ = path
        _ = selected
    }

    private static func paintLabels(entries: [CountryMapEntry], in ctx: CGContext) {
        for entry in entries where entry.name.count <= 18 {
            let center = equirectangular(lng: entry.lng, lat: entry.lat)
            let font = UIFont.systemFont(ofSize: entry.name.count > 12 ? 8 : 9, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: Palette.ink.withAlphaComponent(0.82),
            ]
            let text = entry.name as NSString
            let size = text.size(withAttributes: attrs)
            text.draw(
                at: CGPoint(x: center.x - size.width * 0.5, y: center.y - size.height * 0.5),
                withAttributes: attrs
            )
        }
    }

    private static func paintPaperGrain(in ctx: CGContext) {
        ctx.setBlendMode(.multiply)
        for _ in 0..<400 {
            let x = CGFloat.random(in: 0...textureSize.width)
            let y = CGFloat.random(in: 0...textureSize.height)
            ctx.setFillColor(UIColor(white: 0.4, alpha: CGFloat.random(in: 0.015...0.05)).cgColor)
            ctx.fillEllipse(in: CGRect(x: x, y: y, width: 1.2, height: 1.2))
        }
        ctx.setBlendMode(.normal)
    }

    private static func landFill(iso3: String, selected: Bool) -> UIColor {
        if selected { return Palette.landSelected }
        let hash = abs(iso3.utf8.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1) })
        switch hash % 3 {
        case 0: return Palette.landBase
        case 1: return Palette.landAlt
        default: return Palette.landWarm
        }
    }

    private static func sketchPath(for ring: [CountryMapEntry.MapPoint], wobble: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let points = ring.map { equirectangular(lng: $0.lng, lat: $0.lat) }
        guard let first = points.first else { return path }

        path.move(to: sketchPoint(first, wobble: wobble))
        for point in points.dropFirst() {
            path.addLine(to: sketchPoint(point, wobble: wobble))
        }
        path.closeSubpath()
        return path
    }

    private static func sketchPoint(_ point: CGPoint, wobble: CGFloat) -> CGPoint {
        CGPoint(
            x: point.x + sin(point.x * 0.05 + point.y * 0.04) * wobble,
            y: point.y + cos(point.x * 0.04 - point.y * 0.05) * wobble * 0.7
        )
    }

    private static func equirectangular(lng: Double, lat: Double) -> CGPoint {
        CGPoint(
            x: CGFloat((lng + 180.0) / 360.0) * textureSize.width,
            y: CGFloat((90.0 - lat) / 180.0) * textureSize.height
        )
    }

    private static func boundingArea(_ entry: CountryMapEntry) -> Double {
        var minLng = 180.0, maxLng = -180.0, minLat = 90.0, maxLat = -90.0
        for ring in entry.rings {
            for p in ring {
                minLng = min(minLng, p.lng)
                maxLng = max(maxLng, p.lng)
                minLat = min(minLat, p.lat)
                maxLat = max(maxLat, p.lat)
            }
        }
        return max(0.01, (maxLng - minLng) * (maxLat - minLat))
    }

    private static func pointInRing(_ point: CGPoint, ring: [CountryMapEntry.MapPoint]) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            var pi = equirectangular(lng: ring[i].lng, lat: ring[i].lat)
            var pj = equirectangular(lng: ring[j].lng, lat: ring[j].lat)
            if abs(pi.x - pj.x) > textureSize.width * 0.5 {
                if pi.x < pj.x { pi.x += textureSize.width } else { pj.x += textureSize.width }
            }
            var testX = point.x
            if abs(testX - pi.x) > textureSize.width * 0.5 {
                if testX < pi.x { testX += textureSize.width } else { testX -= textureSize.width }
            }
            let intersects = ((pi.y > point.y) != (pj.y > point.y))
                && (testX < (pj.x - pi.x) * (point.y - pi.y) / ((pj.y - pi.y) + 0.0001) + pi.x)
            if intersects { inside.toggle() }
            j = i
        }
        return inside
    }
}

private extension CGPath {
    var boundingBox: CGRect { boundingBoxOfPath }
}