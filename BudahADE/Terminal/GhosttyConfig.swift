import Foundation
import AppKit

struct GhosttyConfig {
    var fontFamily: String = "Menlo"
    var fontSize: CGFloat = 13
    var theme: String?
    var workingDirectory: String?
    var backgroundColor: NSColor = Theme.nsPanelSurface
    var backgroundOpacity: Double = 1.0
    var foregroundColor: NSColor = Theme.nsTextPrimary

    static func load() -> GhosttyConfig {
        var config = GhosttyConfig()
        let configPaths = [
            "~/.config/ghostty/config",
            "~/.config/ghostty/config.ghostty",
            "~/Library/Application Support/com.mitchellh.ghostty/config",
            "~/Library/Application Support/com.mitchellh.ghostty/config.ghostty",
        ].map { NSString(string: $0).expandingTildeInPath }

        for path in configPaths {
            if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
                config.parse(contents)
            }
        }

        if let themeName = config.theme {
            config.loadTheme(themeName)
        }

        return config
    }

    mutating func parse(_ contents: String) {
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

            switch key {
            case "font-family":
                fontFamily = value
            case "font-size":
                if let size = Double(value) { fontSize = CGFloat(size) }
            case "theme":
                theme = value
            case "working-directory":
                workingDirectory = value
            case "background":
                if let color = NSColor(hexString: value) { backgroundColor = color }
            case "background-opacity":
                if let opacity = Double(value) { backgroundOpacity = opacity }
            case "foreground":
                if let color = NSColor(hexString: value) { foregroundColor = color }
            default:
                break
            }
        }
    }

    mutating func loadTheme(_ name: String) {
        let searchPaths = [
            "/Applications/Ghostty.app/Contents/Resources/ghostty/themes/\(name)",
            "~/.config/ghostty/themes/\(name)",
            "~/Library/Application Support/com.mitchellh.ghostty/themes/\(name)",
        ].map { NSString(string: $0).expandingTildeInPath }

        for path in searchPaths {
            if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
                parse(contents)
                return
            }
        }
    }

    var resolvedFont: NSFont {
        if let font = NSFont(name: fontFamily, size: fontSize) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }
}
