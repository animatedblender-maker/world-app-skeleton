import Foundation

enum GlobePresenceGeo {
    private static let ttlSeconds = 70

    static func ttlCutoffISO() -> String {
        let cutoff = Date().addingTimeInterval(-Double(ttlSeconds))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: cutoff)
    }

    static func buildDots(
        users: [OnlinePresenceUser],
        coordinates: [String: (lat: Double, lng: Double)]
    ) -> [GlobePresenceDot] {
        clusterDots(users: users, coordinates: coordinates, precision: 5)
    }

    static func clusterDots(
        users: [OnlinePresenceUser],
        coordinates: [String: (lat: Double, lng: Double)],
        precision: Int
    ) -> [GlobePresenceDot] {
        let cellSize = cellSize(for: precision)
        var buckets: [String: (lat: Double, lng: Double, count: Int)] = [:]

        for user in users {
            guard let coordinate = coordinates[user.userID],
                  coordinate.lat.isFinite,
                  coordinate.lng.isFinite
            else { continue }

            let latBucket = Int(floor(coordinate.lat / cellSize))
            let lngBucket = Int(floor(normalizeLongitude(coordinate.lng) / cellSize))
            let key = "\(latBucket):\(lngBucket)"

            if var bucket = buckets[key] {
                let total = Double(bucket.count)
                bucket.lat = ((bucket.lat * total) + coordinate.lat) / (total + 1)
                bucket.lng = ((bucket.lng * total) + normalizeLongitude(coordinate.lng)) / (total + 1)
                bucket.count += 1
                buckets[key] = bucket
            } else {
                buckets[key] = (coordinate.lat, normalizeLongitude(coordinate.lng), 1)
            }
        }

        return buckets.map { key, bucket in
            GlobePresenceDot(
                id: key,
                lat: bucket.lat,
                lng: bucket.lng,
                count: bucket.count
            )
        }
    }

    private static func cellSize(for precision: Int) -> Double {
        switch precision {
        case 5: return 0.08
        case 4: return 0.35
        case 3: return 1.2
        case 2: return 4.0
        default: return 12.0
        }
    }

    static func normalizeLongitude(_ lng: Double) -> Double {
        var value = lng
        while value > 180 { value -= 360 }
        while value < -180 { value += 360 }
        return value
    }
}

struct OnlinePresenceUser: Sendable {
    let userID: String
    let countryCode: String
    let cityName: String?
    let countryName: String?
}