import SwiftUI
import CriticalStrikeCore

/// One place for every colour, font and reusable style. A shooter's UI lives or dies on
/// legibility over a bright, noisy 3D scene, so everything here assumes a dark base with
/// high-contrast accents and heavy use of shadow behind text.
enum Theme {
    // MARK: Colours
    static let background = Color(hex: 0x0B0E13)
    static let surface = Color(hex: 0x151A22)
    static let surfaceElevated = Color(hex: 0x1E2530)
    static let stroke = Color(hex: 0x2A3441)
    static let accent = Color(hex: 0xFF6B35)
    static let accentSecondary = Color(hex: 0x2EC4F1)
    static let success = Color(hex: 0x4CAF50)
    static let warning = Color(hex: 0xFFB300)
    static let danger = Color(hex: 0xFF3D71)
    static let textPrimary = Color(hex: 0xF2F5F8)
    static let textSecondary = Color(hex: 0x9AA6B4)
    static let textTertiary = Color(hex: 0x5E6B7A)

    static func team(_ team: Team, mode: ColorBlindMode = .none) -> Color {
        Color(hex: mode.teamColor(team))
    }

    static func rarity(_ rarity: Rarity) -> Color { Color(hex: rarity.colorHex) }

    // MARK: Typography
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .rounded)
    }
    static func title(_ size: CGFloat = 22) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
    static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }
    static func caption(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
    static func mono(_ size: CGFloat = 14) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }

    // MARK: Metrics
    static let cornerRadius: CGFloat = 14
    static let cornerRadiusSmall: CGFloat = 9
    static let spacing: CGFloat = 12
    static let hudShadow = Color.black.opacity(0.85)

    static let panelGradient = LinearGradient(
        colors: [Color(hex: 0x1B2430), Color(hex: 0x11161E)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let accentGradient = LinearGradient(
        colors: [Color(hex: 0xFF8A4C), Color(hex: 0xFF4D1F)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static func rarityGradient(_ rarity: Rarity) -> LinearGradient {
        let base = Color(hex: rarity.colorHex)
        return LinearGradient(colors: [base.opacity(0.85), base.opacity(0.25)],
                              startPoint: .top, endPoint: .bottom)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

// MARK: - Reusable styles

struct PanelBackground: ViewModifier {
    var elevated = false
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(elevated ? Theme.surfaceElevated : Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                            .strokeBorder(Theme.stroke, lineWidth: 1)
                    )
            )
    }
}

struct HUDText: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: Theme.hudShadow, radius: 2, x: 0, y: 1)
            .shadow(color: Theme.hudShadow.opacity(0.6), radius: 6, x: 0, y: 2)
    }
}

extension View {
    func panel(elevated: Bool = false) -> some View { modifier(PanelBackground(elevated: elevated)) }
    func hudText() -> some View { modifier(HUDText()) }
}

struct PrimaryButtonStyle: ButtonStyle {
    var wide = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.title(17))
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .padding(.horizontal, 26)
            .frame(maxWidth: wide ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.accentGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var wide = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(15))
            .foregroundStyle(Theme.textPrimary)
            .padding(.vertical, 11)
            .padding(.horizontal, 20)
            .frame(maxWidth: wide ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                    .fill(Theme.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                            .strokeBorder(Theme.stroke, lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
