import SceneKit
import UIKit

/// Builds a single clean globe sphere with our hand-drawn map texture.
enum CustomGlobeBuilder {
    private static var cachedSphere: SCNGeometry?
    private static var cachedEntryCount = 0

    struct BuiltGlobe {
        let sphereNode: SCNNode
    }

    @MainActor
    static func prepare(entries: [CountryMapEntry]) -> BuiltGlobe {
        let sphereGeometry: SCNGeometry
        if let cachedSphere, cachedEntryCount == entries.count {
            sphereGeometry = cachedSphere
        } else {
            let mesh = GlobeMeshBuilder.texturedSphere(radius: CountryMapData.globeRadius)
            sphereGeometry = GlobeMeshBuilder.scnGeometry(from: mesh)
            cachedSphere = sphereGeometry
            cachedEntryCount = entries.count
        }

        let material = SCNMaterial()
        material.diffuse.contents = CartoonGlobeTexture.image(for: entries, selectedISO: nil)
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .clamp
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.9
        material.metalness.contents = 0.01
        sphereGeometry.materials = [material]

        let sphereNode = SCNNode(geometry: sphereGeometry)
        sphereNode.name = "globe-sphere"
        return BuiltGlobe(sphereNode: sphereNode)
    }

    static func attach(to globeNode: SCNNode, assets: BuiltGlobe) {
        globeNode.childNodes.forEach { $0.removeFromParentNode() }
        globeNode.addChildNode(assets.sphereNode)
    }

    static func updateTexture(on assets: BuiltGlobe, entries: [CountryMapEntry], selectedISO: String?) {
        assets.sphereNode.geometry?.firstMaterial?.diffuse.contents = CartoonGlobeTexture.image(
            for: entries,
            selectedISO: selectedISO
        )
    }
}