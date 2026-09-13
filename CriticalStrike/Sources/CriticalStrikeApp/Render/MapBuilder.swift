import Foundation
import SceneKit
import UIKit
import CriticalStrikeCore

/// Turns a `MapData` into a SceneKit node tree.
///
/// Brushes are grouped by surface and flattened into one node per material, which takes a
/// 600-brush map from 600 draw calls down to about a dozen. Nothing here is animated, so
/// the whole level is marked static and gets baked lighting where the device allows it.
enum MapBuilder {
    struct BuildResult {
        var root: SCNNode
        var lightsNode: SCNNode
        var objectiveNodes: [Int: SCNNode]
        var spawnMarkers: SCNNode
    }

    static func build(map: MapData, materials: MaterialLibrary,
                      quality: GraphicsQuality) -> BuildResult {
        let root = SCNNode()
        root.name = "map_\(map.id.value)"

        // ── Geometry, grouped by surface so each group is one draw call ──
        var bySurface: [SurfaceKind: [MapBrush]] = [:]
        for brush in map.brushes where !brush.isClip {
            bySurface[brush.surface, default: []].append(brush)
        }

        for (surface, brushes) in bySurface {
            let group = SCNNode()
            group.name = "geometry_\(surface)"
            for brush in brushes {
                group.addChildNode(node(for: brush, materials: materials))
            }
            let flattened = group.flattenedClone()
            flattened.name = group.name
            flattened.castsShadow = quality.shadowsEnabled && surface != .glass
            root.addChildNode(flattened)
        }

        // ── Props ──
        let propsRoot = SCNNode()
        propsRoot.name = "props"
        for prop in map.props {
            propsRoot.addChildNode(propNode(prop, materials: materials))
        }
        root.addChildNode(propsRoot.flattenedClone())

        // ── Lighting ──
        let lights = SCNNode()
        lights.name = "lights"
        lights.addChildNode(sunNode(for: map, quality: quality))
        lights.addChildNode(ambientNode(for: map))
        // Point lights are expensive on mobile: keep the strongest ones and drop the rest
        // on lower tiers rather than letting the shader budget explode.
        let budget = pointLightBudget(for: quality)
        let sorted = map.lights.sorted { $0.intensity > $1.intensity }
        for light in sorted.prefix(budget) {
            lights.addChildNode(pointLightNode(light, quality: quality))
        }
        root.addChildNode(lights)

        // ── Objectives ──
        var objectiveNodes: [Int: SCNNode] = [:]
        for site in map.bombSites {
            let node = objectiveMarker(zone: site, color: UIColor(hex: 0xFF6B35), label: site.name)
            objectiveNodes[site.index] = node
            root.addChildNode(node)
        }
        for point in map.capturePoints where map.bombSites.isEmpty {
            let node = objectiveMarker(zone: point, color: UIColor(hex: 0x2EC4F1), label: point.name)
            objectiveNodes[point.index] = node
            root.addChildNode(node)
        }

        // ── Spawn markers (only shown in the warm-up) ──
        let spawnMarkers = SCNNode()
        spawnMarkers.name = "spawns"
        spawnMarkers.isHidden = true
        for spawn in map.spawns {
            let marker = SCNNode(geometry: SCNCylinder(radius: 0.5, height: 0.05))
            marker.geometry?.firstMaterial = materials.emissiveMaterial(
                color: UIColor(hex: spawn.team.colorHex), intensity: 0.6)
            marker.position = SCNVector3(spawn.position.x, spawn.position.y + 0.03, spawn.position.z)
            spawnMarkers.addChildNode(marker)
        }
        root.addChildNode(spawnMarkers)

        return BuildResult(root: root, lightsNode: lights,
                           objectiveNodes: objectiveNodes, spawnMarkers: spawnMarkers)
    }

    // MARK: - Pieces

    /// Texture density is baked into the mesh's UVs rather than set on the material, so
    /// every brush of a surface can share one material and still tile correctly — a shared
    /// material is what lets `flattenedClone` merge the level into a few draw calls.
    private static func node(for brush: MapBrush, materials: MaterialLibrary) -> SCNNode {
        let geometry = GeometryFactory.box(size: brush.box.size,
                                           metresPerTile: metresPerTile(for: brush.surface))
        geometry.firstMaterial = materials.material(for: brush.surface)
        let node = SCNNode(geometry: geometry)
        let center = brush.box.center
        node.position = SCNVector3(center.x, center.y, center.z)
        return node
    }

    /// How much world space one texture repeat covers. Fine materials tile more often;
    /// large architectural surfaces tile less so the repetition is not obvious.
    private static func metresPerTile(for surface: SurfaceKind) -> Float {
        switch surface {
        case .concrete, .dirt, .sand, .grass: return 3.0
        case .metal: return 2.0
        case .wood: return 2.4
        case .tile: return 1.6
        case .fabric: return 1.2
        case .glass, .water: return 4.0
        default: return 2.2
        }
    }

    private static func propNode(_ prop: MapProp, materials: MaterialLibrary) -> SCNNode {
        // Props are built from primitives rather than shipped meshes: it keeps the bundle
        // small, and at gameplay distance a well-proportioned primitive reads correctly.
        let node = SCNNode()
        let material = materials.material(for: prop.surface)

        switch prop.name {
        case "prop_barrel":
            let barrel = SCNCylinder(radius: 0.32, height: 0.95)
            barrel.firstMaterial = material
            let child = SCNNode(geometry: barrel)
            child.position = SCNVector3(0, 0.48, 0)
            node.addChildNode(child)
        case "prop_palm", "prop_pine":
            let trunk = SCNCylinder(radius: 0.18, height: 4.2)
            trunk.firstMaterial = materials.material(for: .wood)
            let trunkNode = SCNNode(geometry: trunk)
            trunkNode.position = SCNVector3(0, 2.1, 0)
            node.addChildNode(trunkNode)
            let canopy = SCNCone(topRadius: 0, bottomRadius: prop.name == "prop_pine" ? 1.5 : 2.1,
                                 height: prop.name == "prop_pine" ? 3.2 : 1.4)
            canopy.firstMaterial = materials.material(for: .grass)
            let canopyNode = SCNNode(geometry: canopy)
            canopyNode.position = SCNVector3(0, prop.name == "prop_pine" ? 4.6 : 4.4, 0)
            node.addChildNode(canopyNode)
        case "prop_car", "prop_truck", "prop_bus", "prop_forklift":
            let sizes: [String: (CGFloat, CGFloat, CGFloat)] = [
                "prop_car": (1.9, 1.4, 4.3), "prop_truck": (2.4, 2.6, 6.2),
                "prop_bus": (2.6, 3.0, 10.0), "prop_forklift": (1.6, 2.2, 2.8)
            ]
            let (w, h, l) = sizes[prop.name] ?? (2, 1.5, 4)
            let body = SCNBox(width: w, height: h * 0.6, length: l, chamferRadius: 0.15)
            body.firstMaterial = material
            let bodyNode = SCNNode(geometry: body)
            bodyNode.position = SCNVector3(0, Float(h * 0.3), 0)
            node.addChildNode(bodyNode)
            let cabin = SCNBox(width: w * 0.85, height: h * 0.45, length: l * 0.45, chamferRadius: 0.1)
            cabin.firstMaterial = materials.material(for: .glass)
            let cabinNode = SCNNode(geometry: cabin)
            cabinNode.position = SCNVector3(0, Float(h * 0.78), Float(-l * 0.1))
            node.addChildNode(cabinNode)
        case "prop_streetlight":
            let pole = SCNCylinder(radius: 0.09, height: 5.2)
            pole.firstMaterial = materials.material(for: .metal)
            let poleNode = SCNNode(geometry: pole)
            poleNode.position = SCNVector3(0, 2.6, 0)
            node.addChildNode(poleNode)
            let head = SCNBox(width: 0.6, height: 0.16, length: 0.3, chamferRadius: 0.05)
            head.firstMaterial = materials.emissiveMaterial(color: UIColor(hex: 0xCFE4FF), intensity: 0.8)
            let headNode = SCNNode(geometry: head)
            headNode.position = SCNVector3(0, 5.1, 0)
            node.addChildNode(headNode)
        case "prop_server_rack":
            let rack = SCNBox(width: 0.8, height: 2.0, length: 1.1, chamferRadius: 0.04)
            rack.firstMaterial = material
            let rackNode = SCNNode(geometry: rack)
            rackNode.position = SCNVector3(0, 1.0, 0)
            node.addChildNode(rackNode)
            let lights = SCNBox(width: 0.05, height: 1.6, length: 0.02, chamferRadius: 0)
            lights.firstMaterial = materials.emissiveMaterial(color: UIColor(hex: 0x4CFF9F), intensity: 1)
            let lightsNode = SCNNode(geometry: lights)
            lightsNode.position = SCNVector3(0.36, 1.0, 0.56)
            node.addChildNode(lightsNode)
        case "prop_market_stall":
            let canopy = SCNBox(width: 3.0, height: 0.12, length: 2.4, chamferRadius: 0)
            canopy.firstMaterial = materials.material(for: .fabric)
            let canopyNode = SCNNode(geometry: canopy)
            canopyNode.position = SCNVector3(0, 2.3, 0)
            node.addChildNode(canopyNode)
            for dx in [Float(-1.4), 1.4] {
                for dz in [Float(-1.1), 1.1] {
                    let post = SCNCylinder(radius: 0.06, height: 2.3)
                    post.firstMaterial = materials.material(for: .wood)
                    let postNode = SCNNode(geometry: post)
                    postNode.position = SCNVector3(dx, 1.15, dz)
                    node.addChildNode(postNode)
                }
            }
        case "prop_pipe_run":
            for offset in [Float(-0.5), 0, 0.5] {
                let pipe = SCNCylinder(radius: 0.22, height: 40)
                pipe.firstMaterial = materials.material(for: .metal)
                let pipeNode = SCNNode(geometry: pipe)
                pipeNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
                pipeNode.position = SCNVector3(offset, 0, 0)
                node.addChildNode(pipeNode)
            }
        case "prop_neon_sign":
            let sign = SCNBox(width: 2.4, height: 1.2, length: 0.12, chamferRadius: 0.05)
            sign.firstMaterial = materials.emissiveMaterial(color: UIColor(hex: 0xFF3D9B), intensity: 1)
            node.addChildNode(SCNNode(geometry: sign))
        default:
            let generic = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.05)
            generic.firstMaterial = material
            let child = SCNNode(geometry: generic)
            child.position = SCNVector3(0, 0.5, 0)
            node.addChildNode(child)
        }

        node.position = SCNVector3(prop.position.x, prop.position.y, prop.position.z)
        node.eulerAngles = SCNVector3(0, prop.yaw, 0)
        node.scale = SCNVector3(prop.scale, prop.scale, prop.scale)
        return node
    }

    private static func sunNode(for map: MapData, quality: GraphicsQuality) -> SCNNode {
        let light = SCNLight()
        light.type = .directional
        light.color = UIColor(hex: map.environment.sunColorHex)
        light.intensity = CGFloat(map.environment.sunIntensity)
        light.castsShadow = quality.shadowsEnabled
        light.shadowMode = .deferred
        light.shadowMapSize = CGSize(width: quality.shadowMapSize, height: quality.shadowMapSize)
        light.shadowSampleCount = quality == .ultra ? 8 : 4
        light.shadowRadius = 3
        light.shadowColor = UIColor(white: 0, alpha: 0.55)
        // An orthographic shadow volume around the play space keeps texel density usable.
        light.orthographicScale = CGFloat(max(map.bounds.size.x, map.bounds.size.z) * 0.35)
        light.zFar = CGFloat(map.bounds.size.length + 60)
        light.automaticallyAdjustsShadowProjection = true

        let node = SCNNode()
        node.light = light
        node.name = "sun"
        let direction = map.environment.sunDirection.normalized
        node.position = SCNVector3(-direction.x * 60, -direction.y * 60 + 20, -direction.z * 60)
        node.look(at: SCNVector3(0, 0, 0))
        return node
    }

    private static func ambientNode(for map: MapData) -> SCNNode {
        let light = SCNLight()
        light.type = .ambient
        light.color = UIColor(hex: map.environment.ambientColorHex)
        light.intensity = CGFloat(map.environment.ambientIntensity)
        let node = SCNNode()
        node.light = light
        node.name = "ambient"
        return node
    }

    private static func pointLightNode(_ light: MapLight, quality: GraphicsQuality) -> SCNNode {
        let scnLight = SCNLight()
        switch light.kind {
        case .omni: scnLight.type = .omni
        case .spot: scnLight.type = .spot
        case .directional: scnLight.type = .directional
        case .area: scnLight.type = .area
        }
        scnLight.color = UIColor(hex: light.colorHex)
        scnLight.intensity = CGFloat(light.intensity)
        scnLight.attenuationEndDistance = CGFloat(light.range)
        scnLight.attenuationStartDistance = CGFloat(light.range * 0.25)
        scnLight.spotOuterAngle = CGFloat(light.spotAngle)
        scnLight.spotInnerAngle = CGFloat(light.spotAngle * 0.6)
        // Only a couple of shadow-casting point lights per map are affordable.
        scnLight.castsShadow = light.castsShadows && quality == .ultra
        if scnLight.castsShadow {
            scnLight.shadowMapSize = CGSize(width: 1024, height: 1024)
            scnLight.shadowMode = .deferred
        }

        let node = SCNNode()
        node.light = scnLight
        node.position = SCNVector3(light.position.x, light.position.y, light.position.z)
        if light.kind == .spot {
            let target = light.position + light.direction * 10
            node.look(at: SCNVector3(target.x, target.y, target.z))
        }
        return node
    }

    private static func pointLightBudget(for quality: GraphicsQuality) -> Int {
        switch quality {
        case .low: return 4
        case .medium: return 10
        case .high: return 18
        case .ultra: return 32
        }
    }

    private static func objectiveMarker(zone: ObjectiveZone, color: UIColor, label: String) -> SCNNode {
        let node = SCNNode()
        node.name = "objective_\(zone.index)"
        node.position = SCNVector3(zone.center.x, zone.center.y + 0.04, zone.center.z)

        let ring = SCNTube(innerRadius: CGFloat(zone.radius) - 0.18,
                           outerRadius: CGFloat(zone.radius), height: 0.04)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = color.withAlphaComponent(0.55)
        material.emission.contents = color.withAlphaComponent(0.45)
        material.blendMode = .add
        material.writesToDepthBuffer = false
        ring.firstMaterial = material
        node.addChildNode(SCNNode(geometry: ring))

        // A floating letter so callouts match what players see.
        let text = SCNText(string: label, extrusionDepth: 0.08)
        text.font = UIFont.systemFont(ofSize: 1.4, weight: .black)
        text.flatness = 0.05
        text.firstMaterial = material
        let textNode = SCNNode(geometry: text)
        let (minBounds, maxBounds) = text.boundingBox
        textNode.pivot = SCNMatrix4MakeTranslation((maxBounds.x - minBounds.x) / 2 + minBounds.x, 0, 0)
        textNode.position = SCNVector3(0, 1.6, 0)
        textNode.constraints = [SCNBillboardConstraint()]
        node.addChildNode(textNode)
        return node
    }
}

extension Vec3 {
    var scnVector: SCNVector3 { SCNVector3(x, y, z) }
}

extension SCNVector3 {
    var vec3: Vec3 { Vec3(x, y, z) }
}
