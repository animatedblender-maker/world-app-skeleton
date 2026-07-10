import SceneKit
import simd

enum GlobeMeshBuilder {
    struct Mesh: Sendable {
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var textureCoordinates: [CGPoint] = []
        var indices: [Int32] = []
    }

    /// Single clean sphere with equirectangular UVs aligned to our country map.
    static func texturedSphere(radius: Float, latSegments: Int = 64, lngSegments: Int = 128) -> Mesh {
        var mesh = Mesh()

        for lat in 0...latSegments {
            let latRad = Float.pi * Float(lat) / Float(latSegments) - Float.pi / 2
            let cosLat = cos(latRad)
            let sinLat = sin(latRad)

            for lng in 0...lngSegments {
                let lngRad = 2 * Float.pi * Float(lng) / Float(lngSegments) - Float.pi
                let cosLng = cos(lngRad)
                let sinLng = sin(lngRad)

                let x = radius * cosLat * cosLng
                let y = radius * sinLat
                let z = radius * cosLat * sinLng
                mesh.positions.append(SCNVector3(x, y, z))
                mesh.normals.append(normalize(SCNVector3(x, y, z)))

                let u = CGFloat((lngRad / (2 * Float.pi)) + 0.5)
                let v = CGFloat((latRad / Float.pi) + 0.5)
                mesh.textureCoordinates.append(CGPoint(x: u, y: v))
            }
        }

        let row = lngSegments + 1
        for lat in 0..<latSegments {
            for lng in 0..<lngSegments {
                let topLeft = Int32(lat * row + lng)
                let topRight = topLeft + 1
                let bottomLeft = Int32((lat + 1) * row + lng)
                let bottomRight = bottomLeft + 1
                mesh.indices.append(contentsOf: [topLeft, bottomLeft, topRight, topRight, bottomLeft, bottomRight])
            }
        }

        return mesh
    }

    static func scnGeometry(from mesh: Mesh) -> SCNGeometry {
        let vertexSource = SCNGeometrySource(vertices: mesh.positions)
        let normalSource = SCNGeometrySource(normals: mesh.normals)
        let uvSource = SCNGeometrySource(textureCoordinates: mesh.textureCoordinates)
        let element = SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)
        return SCNGeometry(sources: [vertexSource, normalSource, uvSource], elements: [element])
    }

    private static func normalize(_ vector: SCNVector3) -> SCNVector3 {
        let v = simd_float3(vector.x, vector.y, vector.z)
        let n = simd_normalize(v)
        return SCNVector3(n.x, n.y, n.z)
    }
}