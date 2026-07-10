import SceneKit
import UIKit

/// Photorealistic Earth using standard sphere UVs + equirectangular textures.
enum PhotorealGlobeBuilder {
    static let earthHitCategory: Int = 1 << 0
    static let decorCategory: Int = 1 << 1

    struct BuiltGlobe {
        let earthNode: SCNNode
        let cloudsNode: SCNNode
    }

    @MainActor
    static func prepare() -> BuiltGlobe {
        let earthNode = makeEarthNode()
        let cloudsNode = makeCloudsNode() ?? SCNNode()
        cloudsNode.name = "globe-clouds"
        if cloudsNode.geometry == nil {
            cloudsNode.isHidden = true
        }
        return BuiltGlobe(earthNode: earthNode, cloudsNode: cloudsNode)
    }

    static func attach(to globeNode: SCNNode, assets: BuiltGlobe) {
        globeNode.childNodes
            .filter { $0.name == "globe-earth" || $0.name == "globe-clouds" }
            .forEach { $0.removeFromParentNode() }
        globeNode.addChildNode(assets.earthNode)
        if assets.cloudsNode.geometry != nil {
            globeNode.addChildNode(assets.cloudsNode)
        }
    }

    static func refreshTextures(on assets: BuiltGlobe) {
        if let earth = PhotorealGlobeTextures.earthDaymap {
            assets.earthNode.geometry?.firstMaterial?.diffuse.contents = earth
        }
        if let clouds = PhotorealGlobeTextures.earthClouds {
            assets.cloudsNode.geometry?.firstMaterial?.diffuse.contents = clouds
        }
    }

    private static func makeEarthNode() -> SCNNode {
        let sphere = SCNSphere(radius: CGFloat(CountryMapData.globeRadius))
        sphere.segmentCount = 128

        let material = SCNMaterial()
        material.diffuse.contents = earthTexture()
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .clamp
        material.diffuse.magnificationFilter = .linear
        material.diffuse.minificationFilter = .linear
        material.lightingModel = .constant
        material.isDoubleSided = false
        sphere.firstMaterial = material

        let node = SCNNode(geometry: sphere)
        node.name = "globe-earth"
        node.categoryBitMask = earthHitCategory
        return node
    }

    private static func makeCloudsNode() -> SCNNode? {
        guard PhotorealGlobeTextures.earthClouds != nil else { return nil }

        let sphere = SCNSphere(radius: CGFloat(CountryMapData.globeRadius * 1.006))
        sphere.segmentCount = 128

        let material = SCNMaterial()
        material.diffuse.contents = cloudTexture()
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .clamp
        material.lightingModel = .constant
        material.transparency = 0.45
        material.transparencyMode = .rgbZero
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.isDoubleSided = true
        sphere.firstMaterial = material

        let node = SCNNode(geometry: sphere)
        node.name = "globe-clouds"
        node.categoryBitMask = decorCategory
        return node
    }

    private static func earthTexture() -> Any {
        PhotorealGlobeTextures.earthDaymap
            ?? UIColor(red: 0.10, green: 0.35, blue: 0.68, alpha: 1)
    }

    private static func cloudTexture() -> Any? {
        PhotorealGlobeTextures.earthClouds
    }
}