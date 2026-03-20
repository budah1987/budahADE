import SwiftUI
import AppKit

enum Theme {

    // MARK: - Backgrounds (two-zone: sidebar vs content)

    static let appBackground  = Color(hex: 0x111113)
    static let sidebar        = Color(hex: 0x1a1a1e)   // sidebar zone — slightly warm
    static let contentBg      = Color(hex: 0x141416)   // content zone — cooler/darker
    static let surface2       = Color(hex: 0x222226)   // cards, popovers, inputs
    static let surface3       = Color(hex: 0x2a2a2e)   // active rows, hover cards

    /// Legacy aliases
    static let panelSurface = sidebar
    static let elevated = surface3
    static let surface1 = sidebar

    // MARK: - Borders

    static let borderSubtle  = Color.white.opacity(0.08)
    static let border        = Color.white.opacity(0.12)
    static let borderActive  = Color.white.opacity(0.18)

    // MARK: - Text (calibrated to warm palette)

    static let textPrimary   = Color(hex: 0xe5e5e5)
    static let textSecondary = Color(hex: 0x999999)
    static let textMuted     = Color(hex: 0x555555)

    // MARK: - Accent & Status

    static let accent  = Color(hex: 0xc4785c)   // terra cotta — use sparingly
    static let success = Color(hex: 0x5a9a6b)
    static let warning = Color(hex: 0xc4a85c)
    static let error   = Color(hex: 0xc45c5c)
    static let info    = Color(hex: 0x6b8fb5)

    // MARK: - Interactive States

    static let hoverFill     = Color.white.opacity(0.04)
    static let pressedFill   = Color.white.opacity(0.06)
    static let selectedFill  = Color.white.opacity(0.08)

    // MARK: - Glass Materials

    static let tabBarMaterial: NSVisualEffectView.Material = .sidebar
    static let tabGlassBackground = Color.white.opacity(0.10)
    static let tabGlassBorder     = Color.white.opacity(0.22)
    static let tabSelectedGlass   = Color.white.opacity(0.14)
    static let tabSelectedBorder  = Color.white.opacity(0.28)

    // MARK: - NSColor Equivalents

    static let nsAppBackground = NSColor(hex: 0x111113)
    static let nsSurface1      = NSColor(hex: 0x1a1a1e)
    static let nsSurface2      = NSColor(hex: 0x222226)
    static let nsBorder        = NSColor(white: 1.0, alpha: 0.12)
    static let nsTextPrimary   = NSColor(hex: 0xe5e5e5)
    static let nsTextSecondary = NSColor(hex: 0x999999)
    static let nsTextMuted     = NSColor(hex: 0x555555)
    static let nsAccent        = NSColor(hex: 0xc4785c)

    // MARK: - Layout

    static let panelCornerRadius: CGFloat = 0
    static let cardCornerRadius: CGFloat = 8
    static let pillCornerRadius: CGFloat = 6
    static let panelGap: CGFloat = 0
    static let edgePadding: CGFloat = 0

    // MARK: - Typography

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black)
    }

    static func headline(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold)
    }

    static func label(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium)
    }

    static func body(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular)
    }

    static func caption(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func monoFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// Legacy compat
    static func uiFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: - Glass Background (NSVisualEffectView wrapper)

struct GlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = Theme.tabBarMaterial
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .withinWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
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
