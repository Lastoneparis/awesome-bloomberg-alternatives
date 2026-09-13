import Foundation
import SceneKit
import CriticalStrikeCore

/// Hand-built geometry with world-space texture coordinates.
///
/// `SCNBox` maps 0…1 across every face, so a 20-metre wall and a 1-metre crate would show
/// the same number of texture repeats — the single most obvious tell of untextured
/// placeholder geometry. Generating the box mesh directly lets the UVs be baked in metres,
/// which keeps texel density constant across the whole level *and* lets every brush of a
/// given surface share one material, so the level still flattens into a handful of draw
/// calls.
enum GeometryFactory {

    /// A box whose texture coordinates are in world units.
    /// - Parameter metresPerTile: how many metres one texture repeat covers.
    static func box(size: Vec3, metresPerTile: Float = 2.5) -> SCNGeometry {
        let hx = max(size.x, 0.02) * 0.5
        let hy = max(size.y, 0.02) * 0.5
        let hz = max(size.z, 0.02) * 0.5
        let inverseTile = 1 / max(metresPerTile, 0.01)

        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var texcoords: [CGPoint] = []
        var indices: [Int32] = []

        /// Appends one quad with UVs scaled by the face's real dimensions.
        func face(origin: SCNVector3, right: SCNVector3, up: SCNVector3,
                  normal: SCNVector3, width: Float, height: Float) {
            let base = Int32(positions.count)
            let u = width * inverseTile
            let v = height * inverseTile

            positions.append(origin)
            positions.append(SCNVector3(origin.x + right.x, origin.y + right.y, origin.z + right.z))
            positions.append(SCNVector3(origin.x + right.x + up.x,
                                        origin.y + right.y + up.y,
                                        origin.z + right.z + up.z))
            positions.append(SCNVector3(origin.x + up.x, origin.y + up.y, origin.z + up.z))

            for _ in 0..<4 { normals.append(normal) }
            texcoords.append(CGPoint(x: 0, y: 0))
            texcoords.append(CGPoint(x: CGFloat(u), y: 0))
            texcoords.append(CGPoint(x: CGFloat(u), y: CGFloat(v)))
            texcoords.append(CGPoint(x: 0, y: CGFloat(v)))

            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }

        // +X and −X: UVs run along Z (width) and Y (height).
        face(origin: SCNVector3(hx, -hy, hz), right: SCNVector3(0, 0, -2 * hz),
             up: SCNVector3(0, 2 * hy, 0), normal: SCNVector3(1, 0, 0),
             width: 2 * hz, height: 2 * hy)
        face(origin: SCNVector3(-hx, -hy, -hz), right: SCNVector3(0, 0, 2 * hz),
             up: SCNVector3(0, 2 * hy, 0), normal: SCNVector3(-1, 0, 0),
             width: 2 * hz, height: 2 * hy)

        // +Y and −Y: UVs run along X and Z. Floors and ceilings.
        face(origin: SCNVector3(-hx, hy, hz), right: SCNVector3(2 * hx, 0, 0),
             up: SCNVector3(0, 0, -2 * hz), normal: SCNVector3(0, 1, 0),
             width: 2 * hx, height: 2 * hz)
        face(origin: SCNVector3(-hx, -hy, -hz), right: SCNVector3(2 * hx, 0, 0),
             up: SCNVector3(0, 0, 2 * hz), normal: SCNVector3(0, -1, 0),
             width: 2 * hx, height: 2 * hz)

        // +Z and −Z: UVs run along X and Y.
        face(origin: SCNVector3(-hx, -hy, hz), right: SCNVector3(2 * hx, 0, 0),
             up: SCNVector3(0, 2 * hy, 0), normal: SCNVector3(0, 0, 1),
             width: 2 * hx, height: 2 * hy)
        face(origin: SCNVector3(hx, -hy, -hz), right: SCNVector3(-2 * hx, 0, 0),
             up: SCNVector3(0, 2 * hy, 0), normal: SCNVector3(0, 0, -1),
             width: 2 * hx, height: 2 * hy)

        let vertexSource = SCNGeometrySource(vertices: positions)
        let normalSource = SCNGeometrySource(normals: normals)
        let texcoordSource = SCNGeometrySource(textureCoordinates: texcoords)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: [vertexSource, normalSource, texcoordSource],
                           elements: [element])
    }

    /// A ground plane subdivided enough that vertex-interpolated lighting does not band
    /// across it, with world-space UVs.
    static func plane(width: Float, depth: Float, segments: Int = 8,
                      metresPerTile: Float = 2.5) -> SCNGeometry {
        let plane = SCNPlane(width: CGFloat(width), height: CGFloat(depth))
        plane.widthSegmentCount = segments
        plane.heightSegmentCount = segments
        let material = SCNMaterial()
        material.diffuse.contentsTransform = SCNMatrix4MakeScale(width / metresPerTile,
                                                                 depth / metresPerTile, 1)
        plane.materials = [material]
        return plane
    }
}
