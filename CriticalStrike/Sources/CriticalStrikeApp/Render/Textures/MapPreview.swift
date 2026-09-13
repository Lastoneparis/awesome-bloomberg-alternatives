import Foundation
import UIKit
import CriticalStrikeCore

/// Renders a top-down preview of a map straight from its brush data.
///
/// The map picker and the loading screen both need a picture of each map. Rendering one
/// from the level data means it can never go stale the way a hand-exported screenshot
/// does — move a wall and the preview moves with it — and it costs nothing to ship.
enum MapPreviewRenderer {

    static func render(map: MapData, size: CGSize, showObjectives: Bool = true) -> UIImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0 else { return nil }

        let bounds = map.bounds
        let worldWidth = max(bounds.size.x, 1)
        let worldDepth = max(bounds.size.z, 1)
        // Fit the map into the image while preserving aspect, with a small margin.
        let scale = min(Float(width) / worldWidth, Float(height) / worldDepth) * 0.92
        let offsetX = (Float(width) - worldWidth * scale) * 0.5
        let offsetY = (Float(height) - worldDepth * scale) * 0.5

        func project(_ position: Vec3) -> CGPoint {
            CGPoint(x: CGFloat((position.x - bounds.min.x) * scale + offsetX),
                    y: CGFloat((position.z - bounds.min.z) * scale + offsetY))
        }

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext

            // Background: the map's own fog colour, darkened, so each preview carries the
            // map's palette before a single wall is drawn.
            let ground = UIColor(hex: map.environment.fogColorHex).darkened(by: 0.22)
            cg.setFillColor(ground.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            // Floors first, so walls read on top of them.
            let sorted = map.brushes.filter { !$0.isClip }
                .sorted { $0.box.max.y < $1.box.max.y }

            for brush in sorted {
                let min = project(brush.box.min)
                let max = project(brush.box.max)
                let rect = CGRect(x: min.x, y: min.y, width: max.x - min.x, height: max.y - min.y)
                guard rect.width > 0.4, rect.height > 0.4 else { continue }

                let isWall = brush.box.size.y > 1.4
                let base = previewColor(for: brush.surface)
                // Height shading: taller geometry is lighter, which is enough to read a
                // level's massing at a glance.
                let elevation = MathUtil.clamp((brush.box.max.y - bounds.min.y)
                                               / Swift.max(bounds.size.y, 1), 0, 1)
                let color = base.adjusted(brightness: CGFloat(elevation) * 0.22
                                          - (isWall ? 0 : 0.12))
                cg.setFillColor(color.withAlphaComponent(isWall ? 0.95 : 0.65).cgColor)
                cg.fill(rect)

                if isWall {
                    cg.setStrokeColor(UIColor.black.withAlphaComponent(0.35).cgColor)
                    cg.setLineWidth(0.5)
                    cg.stroke(rect)
                }
            }

            guard showObjectives else { return }

            // Objectives.
            for site in map.bombSites {
                drawObjective(cg, at: project(site.center), radius: CGFloat(site.radius) * CGFloat(scale),
                              label: site.name, color: UIColor(hex: 0xFF6B35))
            }
            if map.bombSites.isEmpty {
                for point in map.capturePoints {
                    drawObjective(cg, at: project(point.center),
                                  radius: CGFloat(point.radius) * CGFloat(scale),
                                  label: point.name, color: UIColor(hex: 0x2EC4F1))
                }
            }

            // Spawns, as small team-coloured dots.
            for spawn in map.spawns where spawn.team != .none {
                let point = project(spawn.position)
                cg.setFillColor(UIColor(hex: spawn.team.colorHex).withAlphaComponent(0.9).cgColor)
                cg.fillEllipse(in: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4))
            }

            // Vignette, so the preview sits comfortably inside a card.
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: [UIColor.clear.cgColor,
                                                  UIColor.black.withAlphaComponent(0.45).cgColor] as CFArray,
                                         locations: [0.55, 1]) {
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                cg.drawRadialGradient(gradient, startCenter: centre, startRadius: 0,
                                      endCenter: centre, endRadius: max(size.width, size.height) * 0.7,
                                      options: [])
            }
        }
    }

    private static func drawObjective(_ cg: CGContext, at point: CGPoint, radius: CGFloat,
                                      label: String, color: UIColor) {
        cg.setStrokeColor(color.withAlphaComponent(0.9).cgColor)
        cg.setLineWidth(1.5)
        cg.strokeEllipse(in: CGRect(x: point.x - radius, y: point.y - radius,
                                    width: radius * 2, height: radius * 2))
        cg.setFillColor(color.withAlphaComponent(0.18).cgColor)
        cg.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius,
                                  width: radius * 2, height: radius * 2))

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .black),
            .foregroundColor: color
        ]
        let text = label as NSString
        let textSize = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: point.x - textSize.width / 2, y: point.y - textSize.height / 2),
                  withAttributes: attributes)
    }

    private static func previewColor(for surface: SurfaceKind) -> UIColor {
        switch surface {
        case .concrete: return UIColor(hex: 0x8C8880)
        case .metal: return UIColor(hex: 0x6E7681)
        case .wood: return UIColor(hex: 0x8A6238)
        case .dirt: return UIColor(hex: 0x6B563C)
        case .sand: return UIColor(hex: 0xC8AE7D)
        case .grass: return UIColor(hex: 0x4C6B3A)
        case .water: return UIColor(hex: 0x2E5A72)
        case .glass: return UIColor(hex: 0xBFE0EA)
        case .fabric: return UIColor(hex: 0x7A5A4A)
        case .flesh: return UIColor(hex: 0x9B5A52)
        case .plastic: return UIColor(hex: 0x9AA3AB)
        case .tile: return UIColor(hex: 0xADB4BC)
        }
    }
}

/// Caches rendered previews so scrolling the map picker does not re-render them.
@MainActor
final class MapPreviewCache: ObservableObject {
    static let shared = MapPreviewCache()
    private var cache: [String: UIImage] = [:]

    func preview(for map: MapData, size: CGSize) -> UIImage? {
        let key = "\(map.id.value)_\(Int(size.width))x\(Int(size.height))"
        if let cached = cache[key] { return cached }
        guard let image = MapPreviewRenderer.render(map: map, size: size) else { return nil }
        cache[key] = image
        return image
    }

    func clear() { cache.removeAll() }
}
