import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 08) & 0xff) / 255,
            blue: Double((hex >> 00) & 0xff) / 255,
            opacity: alpha
        )
    }
}

extension AccentTheme {
    var color: Color {
        switch self {
        case .volt:    return Color(hex: 0x6B55F4)
        case .cyan:    return Color(hex: 0x21D4D6)
        case .magenta: return Color(hex: 0xE45FD0)
        case .green:   return Color(hex: 0x34C759)
        case .orange:  return Color(hex: 0xFF9F0A)
        }
    }
    var gradient: LinearGradient {
        let second: Color
        switch self {
        case .volt:    second = Color(hex: 0x21D4F2)
        case .cyan:    second = Color(hex: 0x6B55F4)
        case .magenta: second = Color(hex: 0x6B55F4)
        case .green:   second = Color(hex: 0x21D4D6)
        case .orange:  second = Color(hex: 0xE45FD0)
        }
        return LinearGradient(colors: [color, second],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension AppTheme {
    var colorScheme: ColorScheme? {
        switch self {
        case .system:           return nil
        case .light:            return .light
        case .dark, .midnight, .volt: return .dark
        }
    }

    /// Custom background for non-system themes; nil = use default.
    var background: Color? {
        switch self {
        case .midnight: return Color(hex: 0x0A0E1A)
        case .volt:     return Color(hex: 0x0D0A1F)
        case .dark:     return Color(hex: 0x000000)
        default:        return nil
        }
    }

    var card: Color? {
        switch self {
        case .midnight: return Color(hex: 0x141A2E)
        case .volt:     return Color(hex: 0x1A1430)
        case .dark:     return Color(hex: 0x1C1C1E)
        default:        return nil
        }
    }
}
