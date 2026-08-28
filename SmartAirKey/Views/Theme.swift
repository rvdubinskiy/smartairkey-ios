import SwiftUI

/// Colors and reusable styling. Everything is system/semantic so light & dark
/// themes and Dynamic Type work automatically (UI req. 6).
enum Theme {

    static func color(for tint: DoorStatusTint) -> Color {
        switch tint {
        case .positive: return .green
        case .neutral: return .accentColor
        case .muted: return .secondary
        case .negative: return .orange
        }
    }
}

/// Card container used across the app.
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }
}

/// A card that uses Apple's **Liquid Glass** material on iOS 26+, and falls back
/// to the flat opaque card everywhere else (the app's minimum is iOS 16). Same
/// padding/shape either way, so layout is identical across OS versions.
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 20

    @ViewBuilder
    func body(content: Content) -> some View {
        let padded = content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)

        if #available(iOS 26.0, *) {
            padded.glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            padded.background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }

    /// Liquid Glass card on iOS 26+, flat card below.
    func glassCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }
}
