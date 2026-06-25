import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 08) & 0xff) / 255,
                  blue: Double((hex >> 00) & 0xff) / 255,
                  opacity: alpha)
    }
    init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt(s, radix: 16) else { return nil }
        self.init(hex: v)
    }
    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
    }
}

extension AccentTheme {
    func color(custom: Color) -> Color {
        switch self {
        case .volt:    return Color(hex: 0x6B55F4)
        case .cyan:    return Color(hex: 0x21D4D6)
        case .magenta: return Color(hex: 0xE45FD0)
        case .green:   return Color(hex: 0x34C759)
        case .orange:  return Color(hex: 0xFF9F0A)
        case .mono:    return Color(hex: 0xFFFFFF)
        case .custom:  return custom
        }
    }
    func gradient(custom: Color) -> LinearGradient {
        let c = color(custom: custom)
        let second: Color
        switch self {
        case .volt:    second = Color(hex: 0x21D4F2)
        case .cyan:    second = Color(hex: 0x6B55F4)
        case .magenta: second = Color(hex: 0x6B55F4)
        case .green:   second = Color(hex: 0x21D4D6)
        case .orange:  second = Color(hex: 0xE45FD0)
        case .mono:    second = Color(hex: 0x8E8E93)
        case .custom:  second = c.opacity(0.6)
        }
        return LinearGradient(colors: [c, second], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension AppTheme {
    func colorScheme(custom: ColorScheme?) -> ColorScheme? {
        switch self {
        case .system:                  return nil
        case .light:                   return .light
        case .dark, .midnight, .volt:  return .dark
        case .mono:                    return .dark
        case .custom:                  return custom
        }
    }
    func background(custom: Color?) -> Color? {
        switch self {
        case .midnight: return Color(hex: 0x0A0E1A)
        case .volt:     return Color(hex: 0x0D0A1F)
        case .dark:     return Color(hex: 0x000000)
        case .mono:     return Color(hex: 0x000000)
        case .custom:   return custom
        default:        return nil
        }
    }
    func card(custom: Color?) -> Color? {
        switch self {
        case .midnight: return Color(hex: 0x141A2E)
        case .volt:     return Color(hex: 0x1A1430)
        case .dark:     return Color(hex: 0x1C1C1E)
        case .mono:     return Color(hex: 0x161616)
        case .custom:   return custom
        default:        return nil
        }
    }
}
