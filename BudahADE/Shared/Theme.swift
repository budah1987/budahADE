import SwiftUI
import AppKit

enum Theme {

    // MARK: - Colors

    enum Colors {
        // Backgrounds
        static let appBackground = Color(hex: 0x1a1a1c)
        static let sidebarBackground = Color(hex: 0x222224)
        static let cardBackground = Color.white.opacity(0.03)
        static let actionBarBackground = Color(red: 31/255, green: 31/255, blue: 31/255).opacity(0.45)

        // Surfaces (solid, for non-glass contexts)
        static let surface = Color(hex: 0x222224)
        static let surfaceElevated = Color(hex: 0x2a2a2e)

        // Text
        static let textPrimary = Color(hex: 0xdddddd)
        static let textSecondary = Color(hex: 0x888888)
        static let textTertiary = Color(hex: 0x555555)
        static let textPlaceholder = Color.white.opacity(0.4)
        static let textMuted = Color(hex: 0x777777)
        static let textMonoSecondary = Color(hex: 0x938d8d)

        // Status
        static let statusDone = Color(hex: 0x4add7f)
        static let statusWorking = Color(hex: 0xa78af9)
        static let statusIdle = Color(hex: 0x3a3c43)
        static let error = Color(hex: 0xc45c5c)
        static let warning = Color(hex: 0xc4a85c)
        static let info = Color(hex: 0x6b8fb5)

        // Borders
        static let borderSubtle = Color.white.opacity(0.06)
        static let borderLight = Color.white.opacity(0.08)
        static let borderActive = Color.white.opacity(0.5)
        static let borderInput = Color(hex: 0x858585)
        static let divider = Color.white.opacity(0.08)

        // Buttons
        static let buttonBackground = Color(hex: 0x1e1e1e)
        static let buttonText = Color(hex: 0x888888)
        static let primaryButtonBackground = Color.white
        static let primaryButtonText = Color(red: 30/255, green: 30/255, blue: 30/255).opacity(0.8)

        // Accent
        static let accent = Color(hex: 0xc4785c)

        // Interactive States
        static let hoverFill = Color.white.opacity(0.04)
        static let pressedFill = Color.white.opacity(0.06)
        static let selectedFill = Color.white.opacity(0.08)

        // Glass Effects
        static let tabGlassBackground = Color.white.opacity(0.10)
        static let tabGlassBorder = Color.white.opacity(0.22)
        static let tabSelectedGlass = Color.white.opacity(0.14)
        static let tabSelectedBorder = Color.white.opacity(0.28)
    }

    // MARK: - Radius (locked scale: 1 / 4 / 8 / 12 / 99)

    enum Radius {
        static let xs: CGFloat = 1   // progress bar segments
        static let sm: CGFloat = 4   // small elements
        static let md: CGFloat = 8   // cards, buttons
        static let lg: CGFloat = 12  // action bar, input bar, modals
        static let full: CGFloat = 99 // pills, toggles
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    // MARK: - Typography Constants

    enum Typography {
        static let titleSize: CGFloat = 13
        static let bodySize: CGFloat = 13
        static let captionSize: CGFloat = 11
        static let monoSize: CGFloat = 10
        static let labelSize: CGFloat = 12
        static let sectionHeaderSize: CGFloat = 16
        static let specTitleSize: CGFloat = 28
        static let metaSize: CGFloat = 12
    }

    // MARK: - Layout

    enum Layout {
        static let sidebarWidth: CGFloat = 220
        static let appBarHeight: CGFloat = 36
        static let taskCardHeight: CGFloat = 84
        static let taskCardGap: CGFloat = 8
        static let navItemHeight: CGFloat = 36
        static let actionBarHeight: CGFloat = 64
        static let inputBarHeight: CGFloat = 114
        static let progressBarHeight: CGFloat = 4
        static let progressBarGap: CGFloat = 1
    }

    // MARK: - Typography (Geist for UI, Menlo for terminal content)

    private static let geistName = "Geist"

    static func display(_ size: CGFloat) -> Font {
        .custom("\(geistName)-Black", size: size)
    }

    static func headline(_ size: CGFloat) -> Font {
        .custom("\(geistName)-Bold", size: size)
    }

    static func label(_ size: CGFloat) -> Font {
        .custom("\(geistName)-Medium", size: size)
    }

    static func body(_ size: CGFloat) -> Font {
        .custom("\(geistName)-Regular", size: size)
    }

    static func caption(_ size: CGFloat) -> Font {
        .custom("\(geistName)-Regular", size: size)
    }

    /// Terminal content only — diffs, code blocks, file preview
    static func code(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Menlo", size: size).weight(weight)
    }

    /// NSFont for AppKit contexts — canvas text measurement, attributed strings
    static func geistFont(size: CGFloat, name: String = "Geist-Regular") -> NSFont {
        NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
    }

    /// NSFont for terminal content in AppKit contexts
    static func codeFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont(name: "Menlo", size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    // MARK: - NSColor Equivalents

    static let nsAppBackground = NSColor(hex: 0x1a1a1c)
    static let nsSurface       = NSColor(hex: 0x222224)
    static let nsBorder        = NSColor(white: 1.0, alpha: 0.08)
    static let nsTextPrimary   = NSColor(hex: 0xdddddd)
    static let nsTextSecondary = NSColor(hex: 0x888888)
    static let nsTextMuted     = NSColor(hex: 0x555555)
    static let nsAccent        = NSColor(hex: 0xc4785c)
    static let nsBuilder       = NSColor(hex: 0xa78af9)

    // MARK: - Glass Materials

    static let tabBarMaterial: NSVisualEffectView.Material = .sidebar
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
