import SwiftUI

enum Theme {
    static let background = Color.black
    static let cardBackground = Color(hex: "1C1C1E")
    static let cardBorder = Color(hex: "2C2C2E")
    static let accent = Color(hex: "00E5A0")
    static let accentAI = Color(hex: "00B4D8")
    static let warning = Color(hex: "FFD60A")
    static let critical = Color(hex: "FF453A")
    static let success = Color(hex: "30D158")
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "8E8E93")
    static let textTertiary = Color(hex: "636366")

    static let paddingSM: CGFloat = 8
    static let paddingMD: CGFloat = 12
    static let paddingLG: CGFloat = 16
    static let paddingXL: CGFloat = 24
    static let cornerRadius: CGFloat = 10
    static let cornerRadiusSM: CGFloat = 6

    static func statusColor(_ level: StatusLevel) -> Color {
        switch level {
        case .healthy: return success
        case .warning: return warning
        case .critical: return critical
        case .offline: return textTertiary
        }
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
    func body(content: Content) -> some View {
        content
            .padding(Theme.paddingLG)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(Theme.cardBorder, lineWidth: 0.5)
            )
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}
