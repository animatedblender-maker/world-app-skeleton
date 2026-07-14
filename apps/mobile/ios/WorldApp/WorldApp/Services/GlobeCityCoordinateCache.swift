import CoreLocation
import Foundation

@MainActor
final class GlobeCityCoordinateCache {
    static let shared = GlobeCityCoordinateCache()

    private var cache: [String: (lat: Double, lng: Double)] = [:]
    private let geocoder = CLGeocoder()

    private init() {}

    func resolve(user: OnlinePresenceUser, entries: [CountryMapEntry]) async -> (lat: Double, lng: Double) {
        let iso = user.countryCode.uppercased()
        guard !iso.isEmpty, iso != "XX" else { return (0, 0) }

        let entry = entries.first {
            $0.iso2.uppercased() == iso || $0.iso3.uppercased() == iso
        }
        let centerLat = entry?.lat ?? 0
        let centerLng = entry?.lng ?? 0

        if let city = user.cityName?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty {
            let key = "\(city.lowercased())|\(iso)"
            if let cached = cache[key] {
                return cached
            }

            let query = [city, user.countryName, iso]
                .compactMap { value -> String? in
                    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return trimmed.isEmpty ? nil : trimmed
                }
                .joined(separator: ", ")

            if let coordinate = await geocode(query) {
                cache[key] = coordinate
                return coordinate
            }
        }

        return jitteredPosition(
            userID: user.userID,
            centerLat: centerLat,
            centerLng: centerLng,
            maxOffset: 0.08
        )
    }

    func resolveCurrentUser(
        userID: String,
        countryCode: String?,
        cityName: String?,
        countryName: String?,
        entries: [CountryMapEntry]
    ) async -> (lat: Double, lng: Double)? {
        guard let code = countryCode?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty else {
            return nil
        }
        let user = OnlinePresenceUser(
            userID: userID,
            countryCode: code,
            cityName: cityName,
            countryName: countryName
        )
        let coordinate = await resolve(user: user, entries: entries)
        guard coordinate.lat.isFinite, coordinate.lng.isFinite else { return nil }
        return coordinate
    }

    private func geocode(_ query: String) async -> (lat: Double, lng: Double)? {
        await withCheckedContinuation { continuation in
            geocoder.geocodeAddressString(query) { placemarks, _ in
                guard let coordinate = placemarks?.first?.location?.coordinate else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (coordinate.latitude, coordinate.longitude))
            }
        }
    }

    private func jitteredPosition(
        userID: String,
        centerLat: Double,
        centerLng: Double,
        maxOffset: Double
    ) -> (lat: Double, lng: Double) {
        let seed = abs(hash32("\(userID):presence"))
        let latOffset = (Double(seed % 10_000) / 10_000.0 - 0.5) * maxOffset
        let lngOffset = (Double((seed / 10_000) % 10_000) / 10_000.0 - 0.5) * maxOffset
        return (
            lat: centerLat + latOffset,
            lng: GlobePresenceGeo.normalizeLongitude(centerLng + lngOffset)
        )
    }

    private func hash32(_ input: String) -> Int {
        var hash = 2_166_136_261
        for byte in input.utf8 {
            hash ^= Int(byte)
            hash = hash &* 16_777_619
        }
        return hash
    }
}