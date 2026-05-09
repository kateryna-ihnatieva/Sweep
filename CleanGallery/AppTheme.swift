import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.06, green: 0.06, blue: 0.08)
    static let surface = Color(red: 0.11, green: 0.11, blue: 0.14)
    static let surfaceElevated = Color(red: 0.15, green: 0.15, blue: 0.19)
    static let border = Color.white.opacity(0.08)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let accent = Color(red: 0.35, green: 0.78, blue: 0.62)
    static let danger = Color(red: 0.95, green: 0.35, blue: 0.38)
    static let keep = Color(red: 0.45, green: 0.55, blue: 0.98)

    static let cardCorner: CGFloat = 20
    static let listRowCorner: CGFloat = 14
}

struct PrimaryButtonStyle: ButtonStyle {
    var role: PrimaryButtonRole = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(role == .destructive ? .white : Color.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(role == .destructive ? AppTheme.danger : AppTheme.accent)
                    .opacity(configuration.isPressed ? 0.85 : 1)
            )
    }
}

enum PrimaryButtonRole {
    case primary
    case destructive
}
