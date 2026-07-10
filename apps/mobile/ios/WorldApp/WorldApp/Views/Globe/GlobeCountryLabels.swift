import SceneKit
import UIKit

enum GlobeCountryLabels {
    private static let maxLabels = 110

    static func buildNodes(from entries: [CountryMapEntry], selectedISO: String?) -> SCNNode {
        let container = SCNNode()
        container.name = "globe-labels"

        let selected = selectedISO?.uppercased()
        for entry in candidates(from: entries) {
            let isSelected = selected == entry.iso3.uppercased() || selected == entry.iso2.uppercased()
            let node = makeLabelNode(for: entry, selected: isSelected)
            container.addChildNode(node)
        }
        return container
    }

    static func refreshSelection(on container: SCNNode, entries: [CountryMapEntry], selectedISO: String?) {
        let selected = selectedISO?.uppercased()
        for child in container.childNodes {
            guard let iso = child.name?.replacingOccurrences(of: "label-", with: "") else { continue }
            let entry = entries.first { $0.iso3 == iso || $0.iso2 == iso }
            guard let entry else { continue }
            let isSelected = selected == entry.iso3.uppercased() || selected == entry.iso2.uppercased()
            updateLabelNode(child, entry: entry, selected: isSelected)
        }
    }

    static func updateVisibility(
        container: SCNNode,
        globeWorldTransform: SCNMatrix4,
        cameraWorldPosition: SCNVector3
    ) {
        let center = SCNVector3(
            globeWorldTransform.m41,
            globeWorldTransform.m42,
            globeWorldTransform.m43
        )
        let toCamera = normalize(SCNVector3(
            cameraWorldPosition.x - center.x,
            cameraWorldPosition.y - center.y,
            cameraWorldPosition.z - center.z
        ))

        for child in container.childNodes {
            let worldPos = child.worldPosition
            let toLabel = normalize(SCNVector3(
                worldPos.x - center.x,
                worldPos.y - center.y,
                worldPos.z - center.z
            ))
            let facing = dot(toCamera, toLabel)
            child.isHidden = facing < 0.18
            child.opacity = CGFloat(min(1, max(0.35, (facing - 0.15) * 1.8)))
        }
    }

    private static func candidates(from entries: [CountryMapEntry]) -> [CountryMapEntry] {
        entries
            .filter { $0.name.count <= 24 }
            .sorted { area($0) > area($1) }
            .prefix(maxLabels)
            .map { $0 }
    }

    private static func makeLabelNode(for entry: CountryMapEntry, selected: Bool) -> SCNNode {
        let image = renderLabelImage(name: displayName(entry.name), selected: selected)
        let plane = SCNPlane(
            width: selected ? 0.15 : 0.12,
            height: max(0.028, 0.12 * (image.size.height / max(image.size.width, 1)))
        )
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        plane.firstMaterial = material

        let node = SCNNode(geometry: plane)
        let coord = CountryMapData.sphereCoordinate(
            lat: entry.lat,
            lng: entry.lng,
            radius: CountryMapData.globeRadius + 0.014
        )
        node.position = SCNVector3(coord.x, coord.y, coord.z)
        node.name = "label-\(entry.iso3)"
        node.categoryBitMask = PhotorealGlobeBuilder.decorCategory

        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .Y
        node.constraints = [billboard]
        return node
    }

    private static func updateLabelNode(_ node: SCNNode, entry: CountryMapEntry, selected: Bool) {
        let image = renderLabelImage(name: displayName(entry.name), selected: selected)
        if let plane = node.geometry as? SCNPlane {
            plane.width = selected ? 0.15 : 0.12
            plane.height = max(0.028, 0.12 * (image.size.height / max(image.size.width, 1)))
            plane.firstMaterial?.diffuse.contents = image
        }
    }

    private static func renderLabelImage(name: String, selected: Bool) -> UIImage {
        let font = UIFont.systemFont(ofSize: selected ? 13 : 11, weight: selected ? .bold : .semibold)
        let textColor = selected
            ? UIColor(red: 1.0, green: 0.92, blue: 0.62, alpha: 1)
            : UIColor(white: 0.97, alpha: 0.95)

        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.75)
        shadow.shadowOffset = CGSize(width: 0, height: 1)
        shadow.shadowBlurRadius = 3

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .shadow: shadow,
        ]
        let text = name as NSString
        let textSize = text.size(withAttributes: attrs)
        let padding = UIEdgeInsets(top: 5, left: 9, bottom: 5, right: 9)
        let canvas = CGSize(
            width: textSize.width + padding.left + padding.right,
            height: textSize.height + padding.top + padding.bottom
        )

        let renderer = UIGraphicsImageRenderer(size: canvas)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: canvas)
            let capsule = UIBezierPath(roundedRect: rect, cornerRadius: rect.height * 0.5)
            let fill = selected
                ? UIColor(red: 0.20, green: 0.14, blue: 0.05, alpha: 0.82)
                : UIColor(red: 0.03, green: 0.06, blue: 0.12, alpha: 0.62)
            fill.setFill()
            capsule.fill()

            if selected {
                UIColor(red: 1.0, green: 0.78, blue: 0.28, alpha: 0.9).setStroke()
                capsule.lineWidth = 1.2
                capsule.stroke()
            } else {
                UIColor(white: 1, alpha: 0.14).setStroke()
                capsule.lineWidth = 0.6
                capsule.stroke()
            }

            text.draw(
                at: CGPoint(x: padding.left, y: padding.top),
                withAttributes: attrs
            )
        }
    }

    private static func displayName(_ name: String) -> String {
        switch name.uppercased() {
        case "UNITED STATES OF AMERICA", "UNITED STATES": return "United States"
        case "UNITED KINGDOM": return "UK"
        case "RUSSIAN FEDERATION": return "Russia"
        case "DEMOCRATIC REPUBLIC OF THE CONGO": return "DR Congo"
        case "CENTRAL AFRICAN REPUBLIC": return "CAR"
        case "UNITED ARAB EMIRATES": return "UAE"
        default:
            return name.count > 22 ? String(name.prefix(20)) + "…" : name
        }
    }

    private static func area(_ entry: CountryMapEntry) -> Double {
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

    private static func normalize(_ vector: SCNVector3) -> SCNVector3 {
        let length = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
        guard length > 0.0001 else { return vector }
        return SCNVector3(vector.x / length, vector.y / length, vector.z / length)
    }

    private static func dot(_ a: SCNVector3, _ b: SCNVector3) -> Float {
        a.x * b.x + a.y * b.y + a.z * b.z
    }
}