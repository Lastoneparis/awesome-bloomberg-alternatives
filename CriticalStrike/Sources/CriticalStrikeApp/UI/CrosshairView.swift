import SwiftUI
import CriticalStrikeCore

/// The crosshair is the game's most-looked-at pixel. It expands with the actual spread
/// value the simulation uses, so what the player sees is literally the cone their bullets
/// can land in — no cosmetic approximation.
struct CrosshairView: View {
    let spread: Float
    let kind: CrosshairKind
    let colorHex: UInt32
    let scale: Float
    let onTarget: Bool
    let screenHeight: CGFloat

    private var color: Color { Color(hex: colorHex) }

    /// Converts the spread angle into a screen radius using the same small-angle
    /// approximation the renderer's FOV implies.
    private var gap: CGFloat {
        let pointsPerRadian = screenHeight / (78 * CGFloat(MathUtil.deg2rad))
        return max(3, CGFloat(spread) * pointsPerRadian * 0.5) * CGFloat(scale)
    }

    var body: some View {
        ZStack {
            switch kind {
            case .cross:
                crossCrosshair
            case .dot:
                Circle()
                    .fill(displayColor)
                    .frame(width: 4 * CGFloat(scale), height: 4 * CGFloat(scale))
            case .circle:
                Circle()
                    .strokeBorder(displayColor, lineWidth: 1.5)
                    .frame(width: gap * 2, height: gap * 2)
                Circle().fill(displayColor).frame(width: 2, height: 2)
            case .shotgun:
                Circle()
                    .strokeBorder(displayColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 5]))
                    .frame(width: gap * 2.6, height: gap * 2.6)
            case .sniper, .none:
                Circle().fill(displayColor).frame(width: 3, height: 3)
            }
        }
        .animation(.easeOut(duration: 0.06), value: gap)
        .allowsHitTesting(false)
    }

    /// Turns red over an enemy — the standard mobile affordance, and the only thing that
    /// makes auto-fire legible.
    private var displayColor: Color {
        onTarget ? Theme.danger : color
    }

    private var crossCrosshair: some View {
        let length: CGFloat = 7 * CGFloat(scale)
        let thickness: CGFloat = 2
        return ZStack {
            // Four ticks plus a centre dot, each offset by the current spread.
            Rectangle().fill(displayColor)
                .frame(width: thickness, height: length)
                .offset(y: -(gap + length / 2))
            Rectangle().fill(displayColor)
                .frame(width: thickness, height: length)
                .offset(y: gap + length / 2)
            Rectangle().fill(displayColor)
                .frame(width: length, height: thickness)
                .offset(x: -(gap + length / 2))
            Rectangle().fill(displayColor)
                .frame(width: length, height: thickness)
                .offset(x: gap + length / 2)
            Circle().fill(displayColor).frame(width: 2, height: 2)
        }
        .shadow(color: .black.opacity(0.8), radius: 1)
    }
}

struct KillFeedView: View {
    let entries: [KillFeedEntry]
    let colorBlind: ColorBlindMode

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            ForEach(entries.suffix(5)) { entry in
                HStack(spacing: 5) {
                    Text(entry.killerName)
                        .foregroundStyle(Color(hex: colorBlind.teamColor(entry.killerTeam)))
                    if entry.wallbang {
                        Image(systemName: "rectangle.split.2x1")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.warning)
                    }
                    Image(systemName: weaponIcon(entry.weapon))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                    if entry.headshot {
                        Image(systemName: "scope")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.danger)
                    }
                    Text(entry.victimName)
                        .foregroundStyle(Color(hex: colorBlind.teamColor(entry.victimTeam)))
                }
                .font(Theme.caption(11))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.42)))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: entries.count)
        .hudText()
    }

    private func weaponIcon(_ id: WeaponID) -> String {
        guard let weapon = WeaponDatabase.weapon(id) else { return "bolt.fill" }
        switch weapon.weaponClass {
        case .melee: return "scissors"
        case .grenade: return "burst.fill"
        case .sniperRifle, .marksman: return "scope"
        case .shotgun: return "wind"
        case .pistol: return "bolt.fill"
        default: return "flame.fill"
        }
    }
}

/// Top-down minimap drawn straight from the map's brush data with a Canvas — no baked
/// image, so every map gets a correct minimap for free and it stays in sync with layout
/// changes.
struct MinimapView: View {
    let hud: HUDState
    let map: MapData
    let localPosition: Vec3
    let localYaw: Float
    let colorBlind: ColorBlindMode

    private let sizePoints: CGFloat = 118

    var body: some View {
        Canvas { context, canvasSize in
            let bounds = map.bounds
            let worldWidth = max(bounds.size.x, 1)
            let worldDepth = max(bounds.size.z, 1)
            let scale = min(canvasSize.width / CGFloat(worldWidth),
                            canvasSize.height / CGFloat(worldDepth))

            func point(_ position: Vec3) -> CGPoint {
                CGPoint(x: (CGFloat(position.x - bounds.min.x)) * scale,
                        y: (CGFloat(position.z - bounds.min.z)) * scale)
            }

            // Walls, drawn as their footprint.
            for brush in map.brushes where !brush.isClip && brush.box.size.y > 1.2 {
                let min = point(brush.box.min)
                let max = point(brush.box.max)
                let rect = CGRect(x: min.x, y: min.y, width: max.x - min.x, height: max.y - min.y)
                context.fill(Path(rect), with: .color(Theme.stroke.opacity(0.85)))
            }

            // Objectives.
            for site in map.bombSites {
                let centre = point(site.center)
                let radius = CGFloat(site.radius) * scale
                context.stroke(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                                                      width: radius * 2, height: radius * 2)),
                               with: .color(Theme.accent.opacity(0.7)), lineWidth: 1.5)
            }

            // Teammates.
            for marker in hud.teammates {
                let p = point(marker.position)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
                             with: .color(Color(hex: colorBlind.teamColor(marker.team))))
            }

            // Enemies that have given themselves away.
            for marker in hud.minimapEnemies {
                let p = point(marker.position)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)),
                             with: .color(Theme.danger))
            }

            // Bomb.
            if hud.bombPlanted {
                let p = point(Vec3(0, 0, 0))
                context.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)),
                             with: .color(Theme.warning))
            }

            // The player, drawn as a facing arrow.
            let me = point(localPosition)
            var arrow = Path()
            let heading = CGFloat(-localYaw)
            let tip = CGPoint(x: me.x + sin(heading) * 7, y: me.y - cos(heading) * 7)
            let left = CGPoint(x: me.x + sin(heading + 2.5) * 5, y: me.y - cos(heading + 2.5) * 5)
            let right = CGPoint(x: me.x + sin(heading - 2.5) * 5, y: me.y - cos(heading - 2.5) * 5)
            arrow.move(to: tip)
            arrow.addLine(to: left)
            arrow.addLine(to: right)
            arrow.closeSubpath()
            context.fill(arrow, with: .color(.white))
        }
        .frame(width: sizePoints, height: sizePoints)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.stroke, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
