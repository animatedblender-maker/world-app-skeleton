import Foundation
import CoreGraphics
import UIKit

struct CountryMapEntry: Identifiable, Sendable {
    let id: String
    let iso2: String
    let iso3: String
    let name: String
    let lat: Double
    let lng: Double
    let rings: [[MapPoint]]

    struct MapPoint: Sendable {
        let lng: Double
        let lat: Double
    }
}

struct SphereCoordinate: Sendable {
    let x: Float
    let y: Float
    let z: Float
}

enum CountryMapData {
    static let globeRadius: Float = 1.0
    static let borderRadius: Float = 1.014
    static let labelRadius: Float = 1.05

    static func load() -> [CountryMapEntry] {
        guard let url = Bundle.main.url(forResource: "countries_map", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        return raw.compactMap { row in
            guard let iso3 = row["iso3"] as? String,
                  let iso2 = row["iso2"] as? String,
                  let name = row["name"] as? String,
                  let lat = row["lat"] as? Double,
                  let lng = row["lng"] as? Double,
                  let ringsRaw = row["rings"] as? [[[Double]]]
            else { return nil }

            let rings = ringsRaw.map { ring in
                ring.compactMap { pair -> CountryMapEntry.MapPoint? in
                    guard pair.count >= 2 else { return nil }
                    return .init(lng: pair[0], lat: pair[1])
                }
            }.filter { !$0.isEmpty }

            guard !rings.isEmpty else { return nil }
            return CountryMapEntry(id: iso3, iso2: iso2, iso3: iso3, name: name, lat: lat, lng: lng, rings: rings)
        }
    }

    /// Geographic lat/lng → unit-sphere XYZ (Y up, centered).
    static func sphereCoordinate(lat: Double, lng: Double, radius: Float = globeRadius) -> SphereCoordinate {
        let latRad = Float(lat * .pi / 180.0)
        let lngRad = Float(lng * .pi / 180.0)
        let cosLat = cos(latRad)
        let x = radius * cosLat * cos(lngRad)
        let y = radius * sin(latRad)
        let z = radius * cosLat * sin(lngRad)
        return SphereCoordinate(x: x, y: y, z: z)
    }

    /// Sphere XYZ (mesh local space) → geographic lat/lng.
    static func geographicCoordinate(x: Float, y: Float, z: Float) -> (lat: Double, lng: Double) {
        let radius = max(sqrt(x * x + y * y + z * z), 0.0001)
        let lat = Double(asin(min(1, max(-1, y / radius)))) * 180.0 / .pi
        let lng = Double(atan2(z, x)) * 180.0 / .pi
        return (lat, lng)
    }

    static func country(containing lng: Double, lat: Double, in entries: [CountryMapEntry]) -> CountryMapEntry? {
        let reversed = entries.sorted { countryArea($0) < countryArea($1) }
        for entry in reversed {
            for ring in entry.rings where ring.count >= 3 {
                if pointInGeoRing(lng: lng, lat: lat, ring: ring) {
                    return entry
                }
            }
        }
        return nil
    }

    private static func countryArea(_ entry: CountryMapEntry) -> Double {
        var minLng = 180.0, maxLng = -180.0, minLat = 90.0, maxLat = -90.0
        for ring in entry.rings {
            for point in ring {
                minLng = min(minLng, point.lng)
                maxLng = max(maxLng, point.lng)
                minLat = min(minLat, point.lat)
                maxLat = max(maxLat, point.lat)
            }
        }
        return max(0.01, (maxLng - minLng) * (maxLat - minLat))
    }

    private static func pointInGeoRing(lng: Double, lat: Double, ring: [CountryMapEntry.MapPoint]) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            var piLng = ring[i].lng
            let piLat = ring[i].lat
            var pjLng = ring[j].lng
            let pjLat = ring[j].lat
            if abs(piLng - pjLng) > 180 {
                if piLng < pjLng { piLng += 360 } else { pjLng += 360 }
            }
            var testLng = lng
            if abs(testLng - piLng) > 180 {
                if testLng < piLng { testLng += 360 } else { testLng -= 360 }
            }
            let intersects = ((piLat > lat) != (pjLat > lat))
                && (testLng < (pjLng - piLng) * (lat - piLat) / ((pjLat - piLat) + 0.0000001) + piLng)
            if intersects { inside.toggle() }
            j = i
        }
        return inside
    }

    static func paperSphereTexture(size: Int = 512) -> UIImage {
        let dim = CGSize(width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: dim)
        return renderer.image { ctx in
            let paper = UIColor(red: 0.973, green: 0.965, blue: 0.949, alpha: 1)
            let wash = UIColor(red: 0.878, green: 0.910, blue: 0.941, alpha: 0.22)
            paper.setFill()
            ctx.fill(CGRect(origin: .zero, size: dim))

            for _ in 0..<1400 {
                let x = CGFloat.random(in: 0...dim.width)
                let y = CGFloat.random(in: 0...dim.height)
                let alpha = CGFloat.random(in: 0.01...0.05)
                UIColor(white: 0.45, alpha: alpha).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: 1.2, height: 1.2))
            }

            wash.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: -20, y: dim.height * 0.45, width: dim.width + 40, height: dim.height * 0.6))

            UIColor(red: 0.42, green: 0.35, blue: 0.25, alpha: 0.04).setStroke()
            for y in stride(from: 0, through: Int(dim.height), by: 18) {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 0, y: CGFloat(y)))
                path.addLine(to: CGPoint(x: dim.width, y: CGFloat(y + 2)))
                path.lineWidth = 0.4
                path.stroke()
            }
        }
    }
}