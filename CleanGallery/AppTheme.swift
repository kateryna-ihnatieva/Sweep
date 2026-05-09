import SwiftUI

/// Centralised palette and shape tokens. All values come from system semantic colors
/// so the UI follows iOS automatically (light/dark, dynamic type, accessibility tints).
enum AppTheme {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let backgroundFlat = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let surfaceElevated = Color(uiColor: .tertiarySystemGroupedBackground)
    static let border = Color(uiColor: .separator)

    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color(uiColor: .tertiaryLabel)

    static let accent = Color.accentColor
    static let danger = Color.red
    static let keep = Color.green

    /// Always-dark backdrop for media (the swipe card behind the photo/video).
    /// Photos and videos look best on a neutral black plate regardless of system theme.
    static let mediaBackdrop = Color.black

    static let cardCorner: CGFloat = 22
    static let listRowCorner: CGFloat = 12
}

/// Full-width prominent button styled like a native `borderedProminent`.
/// Kept as a custom style so the same look applies across screens with a single source of truth.
struct PrimaryButtonStyle: ButtonStyle {
    var role: PrimaryButtonRole = .primary

    func makeBody(configuration: Configuration) -> some View {
        let tint: Color = (role == .destructive) ? AppTheme.danger : AppTheme.accent
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 22)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

enum PrimaryButtonRole {
    case primary
    case destructive
}
