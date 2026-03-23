import SwiftUI

// MARK: - Canvas Element

struct CanvasElement: Identifiable, Equatable {
    let id: UUID
    var kind: ElementKind
    var position: CGPoint
    var size: CGSize
    var title: String
    var specSection: String?
    var specOrder: Int = 0

    init(
        id: UUID = UUID(),
        kind: ElementKind,
        position: CGPoint = .zero,
        size: CGSize = CanvasElement.defaultSize,
        title: String = "",
        specSection: String? = nil,
        specOrder: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.position = position
        self.size = size
        self.title = title
        self.specSection = specSection
        self.specOrder = specOrder
    }

    static let defaultSize = CGSize(width: 480, height: 360)
    static let minSize = CGSize(width: 200, height: 150)
}

// MARK: - Spec Section Definitions

enum SpecSectionKind: String, CaseIterable, Identifiable {
    case problem = "Problem"
    case goals = "Goals"
    case architecture = "Architecture"
    case edgeCases = "Edge Cases"
    case tasks = "Tasks"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var iconName: String {
        switch self {
        case .problem:      return "exclamationmark.triangle"
        case .goals:        return "target"
        case .architecture: return "building.2"
        case .edgeCases:    return "bolt.trianglebadge.exclamationmark"
        case .tasks:        return "checklist"
        }
    }

    var badgeColor: UInt32 {
        switch self {
        case .problem:      return 0xE06C75
        case .goals:        return 0x61AFEF
        case .architecture: return 0xC678DD
        case .edgeCases:    return 0xE5C07B
        case .tasks:        return 0x98C379
        }
    }
}

// MARK: - Element Kind

enum ElementKind: Equatable {
    case tile(TileType)
    case frame(FrameData)
    case text(TextData)
}

// MARK: - Frame Data

struct FrameData: Equatable {
    var axis: Axis = .horizontal
    var children: [CanvasElement] = []
    var gap: CGFloat = 32
    var padding: CGFloat = 48
    var headerHeight: CGFloat = 40

    /// Computed size from children
    var computedSize: CGSize {
        guard !children.isEmpty else {
            // Empty frame — generous minimum size for easy drop targeting
            return CGSize(width: 240, height: 180)
        }

        switch axis {
        case .horizontal:
            let totalWidth = children.reduce(CGFloat(0)) { $0 + $1.size.width }
                + gap * CGFloat(children.count - 1)
                + padding * 2
            let maxHeight = children.map(\.size.height).max() ?? 0
            return CGSize(width: totalWidth, height: maxHeight + padding * 2 + headerHeight)

        case .vertical:
            let maxWidth = children.map(\.size.width).max() ?? 0
            let totalHeight = children.reduce(CGFloat(0)) { $0 + $1.size.height }
                + gap * CGFloat(children.count - 1)
                + padding * 2 + headerHeight
            return CGSize(width: maxWidth + padding * 2, height: totalHeight)
        }
    }

    /// Computed positions for children relative to frame origin
    func childPositions() -> [CGPoint] {
        var positions: [CGPoint] = []
        var offset: CGFloat = 0

        for (i, child) in children.enumerated() {
            switch axis {
            case .horizontal:
                positions.append(CGPoint(
                    x: padding + offset,
                    y: padding + headerHeight
                ))
                offset += child.size.width + (i < children.count - 1 ? gap : 0)

            case .vertical:
                positions.append(CGPoint(
                    x: padding,
                    y: headerHeight + padding + offset
                ))
                offset += child.size.height + (i < children.count - 1 ? gap : 0)
            }
        }
        return positions
    }
}

// MARK: - Text Data

struct TextData: Equatable {
    var content: String = "Text"
    var fontSize: CGFloat = 16
    var weight: TextWeight = .regular
    var fontFamily: TextFontFamily = .system
    var colorHex: UInt32 = 0xe5e5e5
    var isBold: Bool = false
    var isItalic: Bool = false

    var color: Color { Color(hex: colorHex) }

    var font: Font {
        let w: Font.Weight = isBold ? .bold : weight.fontWeight
        switch fontFamily {
        case .system:
            return .system(size: fontSize, weight: w)
        case .monospace:
            return .system(size: fontSize, weight: w, design: .monospaced)
        case .serif:
            return .system(size: fontSize, weight: w, design: .serif)
        }
    }

    var nsFont: NSFont {
        let w: NSFont.Weight = isBold ? .bold : weight.nsFontWeight
        switch fontFamily {
        case .system:
            return NSFont.systemFont(ofSize: fontSize, weight: w)
        case .monospace:
            return NSFont.monospacedSystemFont(ofSize: fontSize, weight: w)
        case .serif:
            // macOS has no built-in serif system font factory; use New York if available
            let descriptor = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body)
                .withDesign(.serif) ?? NSFontDescriptor(name: "Georgia", size: fontSize)
            return NSFont(descriptor: descriptor, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: w)
        }
    }

    /// Measure text size for a given max width, returning the bounding size with padding.
    func measuredSize(maxWidth: CGFloat, padding: CGFloat = 8) -> CGSize {
        let text = content.isEmpty ? " " : content
        let attrString = NSAttributedString(
            string: text,
            attributes: [
                .font: nsFont,
                .paragraphStyle: {
                    let style = NSMutableParagraphStyle()
                    style.lineBreakMode = .byWordWrapping
                    return style
                }()
            ]
        )
        let constraintWidth = maxWidth - padding * 2
        let boundingRect = attrString.boundingRect(
            with: NSSize(width: constraintWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return CGSize(
            width: maxWidth,
            height: ceil(boundingRect.height) + padding * 2
        )
    }
}

enum TextWeight: String, CaseIterable, Equatable {
    case light, regular, medium, semibold, bold, heavy, black

    var fontWeight: Font.Weight {
        switch self {
        case .light:    return .light
        case .regular:  return .regular
        case .medium:   return .medium
        case .semibold: return .semibold
        case .bold:     return .bold
        case .heavy:    return .heavy
        case .black:    return .black
        }
    }

    var nsFontWeight: NSFont.Weight {
        switch self {
        case .light:    return .light
        case .regular:  return .regular
        case .medium:   return .medium
        case .semibold: return .semibold
        case .bold:     return .bold
        case .heavy:    return .heavy
        case .black:    return .black
        }
    }
}

enum TextFontFamily: String, CaseIterable, Equatable {
    case system
    case monospace
    case serif
}
