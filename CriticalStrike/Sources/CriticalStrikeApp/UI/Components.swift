import SwiftUI
import CriticalStrikeCore

/// Shared building blocks for the menu screens.

struct ScreenHeader: View {
    let title: String
    var subtitle: String?
    var onBack: (() -> Void)?
    var trailing: AnyView?

    var body: some View {
        HStack(spacing: 12) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Theme.surfaceElevated))
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.display(22))
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.caption(11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            if let trailing { trailing }
        }
    }
}

struct CurrencyBar: View {
    let wallet: Wallet
    var onTapStore: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            pill(.coins, wallet.coins)
            pill(.gems, wallet.gems)
            if wallet.tokens > 0 { pill(.tokens, wallet.tokens) }
        }
    }

    private func pill(_ kind: CurrencyKind, _ amount: Int) -> some View {
        Button {
            onTapStore?()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(hex: kind.colorHex))
                    .frame(width: 9, height: 9)
                Text(amount.abbreviated)
                    .font(Theme.mono(13))
                    .foregroundStyle(Theme.textPrimary)
                if kind.isPremium {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.surfaceElevated))
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .disabled(onTapStore == nil)
    }
}

struct LevelProgressBar: View {
    let profile: PlayerProfile
    var compact = false

    var body: some View {
        let progress = profile.levelProgress
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("LEVEL \(progress.level)")
                    .font(Theme.caption(compact ? 10 : 12))
                    .foregroundStyle(Theme.textPrimary)
                if profile.prestige > 0 {
                    Text("★\(profile.prestige)")
                        .font(Theme.caption(10))
                        .foregroundStyle(Theme.warning)
                }
                Spacer()
                if !compact {
                    Text("\(progress.current) / \(progress.required) XP")
                        .font(Theme.caption(10))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceElevated).frame(height: compact ? 4 : 6)
                GeometryReader { geometry in
                    Capsule().fill(Theme.accentGradient)
                        .frame(width: geometry.size.width * CGFloat(progress.fraction))
                }
                .frame(height: compact ? 4 : 6)
            }
            .frame(height: compact ? 4 : 6)
        }
    }
}

struct StatBarRow: View {
    let label: String
    let value: Float
    var comparison: Float?

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(Theme.caption(10))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 64, alignment: .leading)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceElevated).frame(height: 6)
                GeometryReader { geometry in
                    // When comparing two weapons, the delta is drawn behind in green/red.
                    if let comparison, abs(comparison - value) > 0.5 {
                        let lower = min(comparison, value) / 100
                        let upper = max(comparison, value) / 100
                        Capsule()
                            .fill(comparison > value ? Theme.danger.opacity(0.5)
                                                     : Theme.success.opacity(0.5))
                            .frame(width: geometry.size.width * CGFloat(upper - lower))
                            .offset(x: geometry.size.width * CGFloat(lower))
                    }
                    Capsule().fill(barColor)
                        .frame(width: geometry.size.width * CGFloat(value / 100))
                }
                .frame(height: 6)
            }
            .frame(height: 6)
            Text("\(Int(value))")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 26, alignment: .trailing)
        }
    }

    private var barColor: Color {
        switch value {
        case ..<34: return Theme.danger
        case ..<67: return Theme.warning
        default: return Theme.success
        }
    }
}

struct RarityBadge: View {
    let rarity: Rarity

    var body: some View {
        Text(rarity.displayName.uppercased())
            .font(Theme.caption(9))
            .foregroundStyle(Theme.rarity(rarity))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.rarity(rarity).opacity(0.15)))
            .overlay(Capsule().strokeBorder(Theme.rarity(rarity).opacity(0.6), lineWidth: 1))
    }
}

struct LockedOverlay: View {
    let requirement: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                .fill(Color.black.opacity(0.6))
            VStack(spacing: 3) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .bold))
                Text(requirement)
                    .font(Theme.caption(9))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Theme.textSecondary)
        }
    }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.icon ?? defaultIcon)
                .font(.system(size: 14, weight: .bold))
            Text(toast.message)
                .font(Theme.body(14))
                .lineLimit(2)
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Theme.surfaceElevated)
                .overlay(Capsule().strokeBorder(accent, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
        )
    }

    private var accent: Color {
        switch toast.style {
        case .info: return Theme.accentSecondary
        case .success, .reward: return Theme.success
        case .warning: return Theme.warning
        case .error: return Theme.danger
        }
    }

    private var defaultIcon: String {
        switch toast.style {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        case .reward: return "gift.fill"
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(title)
                .font(Theme.title(16))
                .foregroundStyle(Theme.textSecondary)
            Text(message)
                .font(Theme.body(13))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
    }
}

extension Int {
    /// 12,500 → "12.5K". Currency strings get long, and the HUD has no room.
    var abbreviated: String {
        switch self {
        case ..<1000: return "\(self)"
        case ..<1_000_000:
            let value = Double(self) / 1000
            return value < 10 ? String(format: "%.1fK", value) : String(format: "%.0fK", value)
        default:
            return String(format: "%.1fM", Double(self) / 1_000_000)
        }
    }
}

extension TimeInterval {
    var compactDuration: String {
        let total = Int(self)
        if total >= 86400 { return "\(total / 86400)d \((total % 86400) / 3600)h" }
        if total >= 3600 { return "\(total / 3600)h \((total % 3600) / 60)m" }
        return "\(total / 60)m"
    }
}
