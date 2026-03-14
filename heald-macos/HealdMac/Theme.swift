import SwiftUI

enum Theme {
    // Deep dark backgrounds
    static let background = Color(hex: "08090E")
    static let surfacePrimary = Color(hex: "0F1117")
    static let cardBackground = Color(hex: "13151C")
    static let cardBorder = Color(hex: "1E2030")
    static let cardBorderHover = Color(hex: "2A2D42")

    // Accent palette — cool cyan/teal
    static let accent = Color(hex: "38F8C2")
    static let accentDim = Color(hex: "38F8C2").opacity(0.15)
    static let accentAI = Color(hex: "6C8EFF")
    static let accentAIDim = Color(hex: "6C8EFF").opacity(0.15)

    // Semantic colors
    static let warning = Color(hex: "FFB224")
    static let critical = Color(hex: "F5424E")
    static let success = Color(hex: "38F8C2")

    // Text hierarchy
    static let textPrimary = Color(hex: "E8EAF0")
    static let textSecondary = Color(hex: "7B7F96")
    static let textTertiary = Color(hex: "464A5E")

    // Spacing
    static let paddingSM: CGFloat = 8
    static let paddingMD: CGFloat = 12
    static let paddingLG: CGFloat = 16
    static let paddingXL: CGFloat = 24

    // Radii
    static let cornerRadius: CGFloat = 12
    static let cornerRadiusSM: CGFloat = 8

    static func statusColor(_ level: StatusLevel) -> Color {
        switch level {
        case .healthy: return success
        case .warning: return warning
        case .critical: return critical
        case .offline: return textTertiary
        }
    }

    // Glow shadow for accent highlights
    static func glowShadow(_ color: Color, radius: CGFloat = 12) -> some View {
        color.opacity(0.25).blur(radius: radius)
    }
}

enum StatusLevel: String, Codable {
    case healthy, warning, critical, offline
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct CardStyle: ViewModifier {
    var glow: Color? = nil

    func body(content: Content) -> some View {
        content
            .padding(Theme.paddingLG)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Theme.cardBorder.opacity(0.8), Theme.cardBorder.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: (glow ?? .clear).opacity(0.08), radius: 16, x: 0, y: 4)
    }
}

extension View {
    func cardStyle(glow: Color? = nil) -> some View {
        modifier(CardStyle(glow: glow))
    }
}
