import SwiftUI
import MapKit

struct AppleMapGlobeView: View {
    let resetGlobe: Bool
    /// When false, the globe is view-only (rotate/zoom only — no country feeds).
    var allowsCountrySelection: Bool = true
    let onSelectCountry: (Country) -> Void

    @State private var entries: [CountryMapEntry] = []
    @State private var apiCountries: [Country] = []
    @Bindable private var globePresence = GlobePresenceService.shared

    var body: some View {
        AppleMapGlobeRepresentable(
            entries: entries,
            apiCountries: apiCountries,
            resetGlobe: resetGlobe,
            dots: globePresence.dots,
            isActive: true,
            allowsCountrySelection: allowsCountrySelection,
            onSelectEntry: selectEntry
        )
        .task {
            if entries.isEmpty {
                entries = CountryMapData.load()
            }
            if apiCountries.isEmpty {
                apiCountries = (try? await ProfileService.shared.countries()) ?? []
            }
            globePresence.startPolling()
        }
        .onDisappear {
            globePresence.stopPolling()
        }
    }

    private func selectEntry(_ entry: CountryMapEntry) {
        guard allowsCountrySelection else { return }
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
    let dots: [GlobePresenceDot]
    let isActive: Bool
    var allowsCountrySelection: Bool = true
    let onSelectEntry: (CountryMapEntry) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectEntry: onSelectEntry, allowsCountrySelection: allowsCountrySelection)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.backgroundColor = UIColor(red: 0.02, green: 0.05, blue: 0.10, alpha: 1)

        let config = MKHybridMapConfiguration(elevationStyle: .realistic)
        config.showsTraffic = false
        mapView.preferredConfiguration = config

        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.showsUserLocation = false
        mapView.setCameraZoomRange(nil, animated: false)

        if allowsCountrySelection {
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            tap.delegate = context.coordinator
            mapView.addGestureRecognizer(tap)
        }

        context.coordinator.mapView = mapView
        context.coordinator.allowsCountrySelection = allowsCountrySelection
        context.coordinator.showGlobe(animated: false)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.entries = entries
        context.coordinator.apiCountries = apiCountries
        context.coordinator.dots = dots
        context.coordinator.allowsCountrySelection = allowsCountrySelection
        mapView.isHidden = !isActive
        mapView.alpha = isActive ? 1 : 0
        if !isActive {
            mapView.isScrollEnabled = false
            mapView.isZoomEnabled = false
        } else {
            mapView.isScrollEnabled = true
            mapView.isZoomEnabled = true
        }
        context.coordinator.syncDotAnnotations()
        if resetGlobe, context.coordinator.didFocusCountry {
            context.coordinator.didFocusCountry = false
            mapView.setCameraZoomRange(nil, animated: false)
            context.coordinator.showGlobe(animated: true)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        let onSelectEntry: (CountryMapEntry) -> Void
        var allowsCountrySelection: Bool
        weak var mapView: MKMapView?

        var entries: [CountryMapEntry] = []
        var apiCountries: [Country] = []
        var dots: [GlobePresenceDot] = []
        var didFocusCountry = false
        private var lastPrecision = 0
        private var dotAnnotations: [String: PresenceDotAnnotation] = [:]
        private var lastDotScale: CGFloat = 1

        private let globeDistance: CLLocationDistance = 42_000_000
        private let focusDistance: CLLocationDistance = 2_800_000

        init(
            onSelectEntry: @escaping (CountryMapEntry) -> Void,
            allowsCountrySelection: Bool = true
        ) {
            self.onSelectEntry = onSelectEntry
            self.allowsCountrySelection = allowsCountrySelection
            super.init()
        }

        func showGlobe(animated: Bool) {
            guard let mapView else { return }
            mapView.setCameraZoomRange(nil, animated: false)
            let camera = MKMapCamera(
                lookingAtCenter: CLLocationCoordinate2D(latitude: 20, longitude: 10),
                fromDistance: globeDistance,
                pitch: 0,
                heading: 0
            )
            mapView.setCamera(camera, animated: animated)
            syncDotAnnotations()
        }

        func syncDotAnnotations() {
            guard let mapView else { return }

            let incoming = Dictionary(uniqueKeysWithValues: dots.map { ($0.id, $0) })
            let removedIDs = Set(dotAnnotations.keys).subtracting(incoming.keys)
            for id in removedIDs {
                if let annotation = dotAnnotations.removeValue(forKey: id) {
                    mapView.removeAnnotation(annotation)
                }
            }

            for (id, dot) in incoming {
                let coordinate = CLLocationCoordinate2D(latitude: dot.lat, longitude: dot.lng)
                if let existing = dotAnnotations[id] {
                    let unchanged = existing.coordinate.latitude == coordinate.latitude
                        && existing.coordinate.longitude == coordinate.longitude
                        && existing.count == dot.count
                    if unchanged { continue }
                    mapView.removeAnnotation(existing)
                }
                let annotation = PresenceDotAnnotation(dot: dot)
                dotAnnotations[id] = annotation
                mapView.addAnnotation(annotation)
            }

            refreshDotAppearance()
        }

        private func refreshDotAppearance() {
            guard let mapView else { return }
            let scale = GlobePresenceDotRenderer.zoomScale(for: mapView.camera.centerCoordinateDistance)
            guard scale != lastDotScale else { return }
            lastDotScale = scale
            for annotation in mapView.annotations {
                guard let view = mapView.view(for: annotation) as? PresenceDotAnnotationView else { continue }
                view.apply(scale: scale)
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard allowsCountrySelection else { return }
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

        private func focus(on entry: CountryMapEntry, animated: Bool) {
            guard let mapView else { return }
            mapView.setCameraZoomRange(nil, animated: false)
            let camera = MKMapCamera(
                lookingAtCenter: CLLocationCoordinate2D(latitude: entry.lat, longitude: entry.lng),
                fromDistance: focusDistance,
                pitch: 12,
                heading: 0
            )
            mapView.setCamera(camera, animated: animated)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is PresenceDotAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: PresenceDotAnnotationView.reuseID)
                as? PresenceDotAnnotationView
                ?? PresenceDotAnnotationView(annotation: annotation, reuseIdentifier: PresenceDotAnnotationView.reuseID)
            view.annotation = annotation
            view.apply(scale: GlobePresenceDotRenderer.zoomScale(for: mapView.camera.centerCoordinateDistance))
            return view
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            syncPrecision(with: mapView)
            refreshDotAppearance()
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            syncPrecision(with: mapView)
            refreshDotAppearance()
        }

        private func syncPrecision(with mapView: MKMapView) {
            let precision = Self.presencePrecision(for: mapView.camera.centerCoordinateDistance)
            guard precision != lastPrecision else { return }
            lastPrecision = precision
            GlobePresenceService.shared.updatePrecision(precision)
        }

        private static func presencePrecision(for distance: CLLocationDistance) -> Int {
            switch distance {
            case ..<1_500_000: return 5
            case ..<4_500_000: return 4
            case ..<18_000_000: return 3
            case ..<40_000_000: return 2
            default: return 1
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}