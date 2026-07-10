import SwiftUI
import MapKit

struct AppleMapGlobeView: View {
    let resetGlobe: Bool
    let onSelectCountry: (Country) -> Void

    @State private var entries: [CountryMapEntry] = []
    @State private var apiCountries: [Country] = []

    var body: some View {
        AppleMapGlobeRepresentable(
            entries: entries,
            apiCountries: apiCountries,
            resetGlobe: resetGlobe,
            isActive: true,
            onSelectEntry: selectEntry
        )
        .task {
            if entries.isEmpty {
                entries = CountryMapData.load()
            }
            if apiCountries.isEmpty {
                apiCountries = (try? await ProfileService.shared.countries()) ?? []
            }
        }
    }

    private func selectEntry(_ entry: CountryMapEntry) {
        let match = apiCountries.first {
            $0.iso.uppercased() == entry.iso2.uppercased()
                || $0.iso.uppercased() == entry.iso3.uppercased()
                || $0.name.caseInsensitiveCompare(entry.name) == .orderedSame
        }
        let country = match ?? Country(
            id: entry.iso2,
            name: entry.name,
            iso: entry.iso2.uppercased(),
            continent: nil,
            centerLat: entry.lat,
            centerLng: entry.lng
        )
        onSelectCountry(country)
    }
}

struct AppleMapGlobeRepresentable: UIViewRepresentable {
    let entries: [CountryMapEntry]
    let apiCountries: [Country]
    let resetGlobe: Bool
    let isActive: Bool
    let onSelectEntry: (CountryMapEntry) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectEntry: onSelectEntry)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.backgroundColor = UIColor(red: 0.02, green: 0.05, blue: 0.10, alpha: 1)

        // Apple Maps 3D globe — realistic earth sphere, not flat map.
        let config = MKHybridMapConfiguration(elevationStyle: .realistic)
        config.pointOfInterestFilter = .excludingAll
        config.showsTraffic = false
        mapView.preferredConfiguration = config

        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.showsUserLocation = false

        // Lock to globe distances only — never drop into flat street map.
        let zoomRange = MKMapView.CameraZoomRange(
            minCenterCoordinateDistance: 18_000_000,
            maxCenterCoordinateDistance: 90_000_000
        )
        mapView.setCameraZoomRange(zoomRange, animated: false)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        mapView.addGestureRecognizer(tap)

        context.coordinator.mapView = mapView
        context.coordinator.showGlobe(animated: false)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.entries = entries
        context.coordinator.apiCountries = apiCountries
        mapView.isHidden = !isActive
        mapView.alpha = isActive ? 1 : 0
        if !isActive {
            mapView.isScrollEnabled = false
            mapView.isZoomEnabled = false
        } else {
            mapView.isScrollEnabled = true
            mapView.isZoomEnabled = true
        }
        if resetGlobe, context.coordinator.didFocusCountry {
            context.coordinator.didFocusCountry = false
            context.coordinator.showGlobe(animated: true)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        let onSelectEntry: (CountryMapEntry) -> Void
        weak var mapView: MKMapView?

        var entries: [CountryMapEntry] = []
        var apiCountries: [Country] = []
        var didFocusCountry = false

        private let globeDistance: CLLocationDistance = 42_000_000
        private let focusDistance: CLLocationDistance = 24_000_000

        init(onSelectEntry: @escaping (CountryMapEntry) -> Void) {
            self.onSelectEntry = onSelectEntry
            super.init()
        }

        func showGlobe(animated: Bool) {
            guard let mapView else { return }
            let camera = MKMapCamera(
                lookingAtCenter: CLLocationCoordinate2D(latitude: 20, longitude: 10),
                fromDistance: globeDistance,
                pitch: 0,
                heading: 0
            )
            mapView.setCamera(camera, animated: animated)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView, gesture.state == .ended else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)

            guard let entry = CountryMapData.country(
                containing: coordinate.longitude,
                lat: coordinate.latitude,
                in: entries
            ) else { return }

            focus(on: entry, animated: true)
            didFocusCountry = true
            onSelectEntry(entry)
        }

        /// Rotate the globe toward a country — stay on the sphere, don't dive into flat map.
        private func focus(on entry: CountryMapEntry, animated: Bool) {
            guard let mapView else { return }
            let camera = MKMapCamera(
                lookingAtCenter: CLLocationCoordinate2D(latitude: entry.lat, longitude: entry.lng),
                fromDistance: focusDistance,
                pitch: 8,
                heading: 0
            )
            mapView.setCamera(camera, animated: animated)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}