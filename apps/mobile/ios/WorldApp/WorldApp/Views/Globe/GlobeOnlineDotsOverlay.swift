import MapKit
import UIKit

final class PresenceDotAnnotation: NSObject, MKAnnotation {
    let dotID: String
    let count: Int
    dynamic var coordinate: CLLocationCoordinate2D

    init(dot: GlobePresenceDot) {
        dotID = dot.id
        count = dot.count
        coordinate = CLLocationCoordinate2D(latitude: dot.lat, longitude: dot.lng)
        super.init()
    }
}

enum GlobePresenceDotRenderer {
    private static let teal = UIColor(red: 0.0, green: 1.0, blue: 0.82, alpha: 1.0)

    static func zoomScale(for cameraDistance: CLLocationDistance) -> CGFloat {
        switch cameraDistance {
        case ..<1_500_000: return 1.35
        case ..<4_500_000: return 1.15
        case ..<18_000_000: return 1.0
        case ..<40_000_000: return 0.85
        default: return 0.7
        }
    }

    static func baseRadius(count: Int) -> CGFloat {
        count > 1 ? 4.5 : 3.5
    }

    static func drawDot(
        in context: CGContext,
        at point: CGPoint,
        count: Int,
        scale: CGFloat
    ) {
        let radius = baseRadius(count: count) * scale
        let glowRect = CGRect(
            x: point.x - radius * 1.35,
            y: point.y - radius * 1.35,
            width: radius * 2.7,
            height: radius * 2.7
        )
        context.setFillColor(teal.withAlphaComponent(0.18).cgColor)
        context.fillEllipse(in: glowRect)

        let coreRect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.setFillColor(teal.withAlphaComponent(0.96).cgColor)
        context.fillEllipse(in: coreRect)
    }

    static func renderImage(count: Int, scale: CGFloat) -> UIImage {
        let radius = baseRadius(count: count) * scale
        let size = CGSize(width: radius * 3.2, height: radius * 3.2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            drawDot(in: context.cgContext, at: center, count: count, scale: 1)
        }
    }
}

final class PresenceDotAnnotationView: MKAnnotationView {
    static let reuseID = "PresenceDotAnnotation"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        canShowCallout = false
        displayPriority = .required
        collisionMode = .none
        centerOffset = .zero
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func apply(scale: CGFloat) {
        guard let annotation = annotation as? PresenceDotAnnotation else { return }
        let image = GlobePresenceDotRenderer.renderImage(count: annotation.count, scale: scale)
        self.image = image
        frame = CGRect(origin: .zero, size: image.size)
    }
}