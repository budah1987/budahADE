import SwiftUI
import AppKit

enum Theme {
    // MARK: - Backgrounds
    static let appBackground = Color(hex: 0x13111a)
    static let panelSurface = Color(hex: 0x1e1b2e)
    static let elevated = Color(hex: 0x252240)

    // MARK: - Borders
    static let border = Color(hex: 0x2e2a42)

    // MARK: - Text
    static let textPrimary = Color(hex: 0xe0dced)
    static let textSecondary = Color(hex: 0x9590a8)
    static let textMuted = Color(hex: 0x6b6680)

    // MARK: - Accent & Status
    static let accent = Color(hex: 0xc4785c)
    static let success = Color(hex: 0x6b9e6b)
    static let warning = Color(hex: 0xc4a85c)
    static let info = Color(hex: 0x7b6cb5)

    // MARK: - Glass & Hover
    static let glassPanelFill = Color.white.opacity(0.03)
    static let glassInputFill = Color(white: 0.43, opacity: 0.2)
    static let hoverPill = Color.white.opacity(0.05)

    // MARK: - NSColor equivalents
    static let nsAppBackground = NSColor(hex: 0x13111a)
    static let nsPanelSurface = NSColor(hex: 0x1e1b2e)
    static let nsElevated = NSColor(hex: 0x252240)
    static let nsBorder = NSColor(hex: 0x2e2a42)
    static let nsTextPrimary = NSColor(hex: 0xe0dced)
    static let nsTextSecondary = NSColor(hex: 0x9590a8)
    static let nsTextMuted = NSColor(hex: 0x6b6680)
    static let nsAccent = NSColor(hex: 0xc4785c)

    // MARK: - Layout
    static let panelCornerRadius: CGFloat = 12
    static let panelGap: CGFloat = 8
    static let edgePadding: CGFloat = 12

    // MARK: - Typography
    static let uiFont = "SF Pro"
    static let codeFont = "SF Mono"

    static func monoFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    static func uiFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: - Color Extensions

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }

    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        hex = hex.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&rgb), hex.count == 6 else { return nil }
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    func hexString() -> String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
