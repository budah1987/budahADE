import SwiftUI

// MARK: - Tile Selection Chrome

/// Reusable view builders for element selection state, badges, and backgrounds.
enum TileSelectionChrome {

    @ViewBuilder
    static func specSectionBadge(for element: CanvasElement) -> some View {
        if let section = element.specSection,
           let kind = SpecSectionKind.allCases.first(where: { $0.rawValue == section }) {
            HStack(spacing: 3) {
                Image(systemName: kind.iconName)
                    .font(.system(size: 8, weight: .bold))
                Text(kind.displayName)
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundColor(Color(hex: kind.badgeColor))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color(hex: kind.badgeColor).opacity(0.15))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color(hex: kind.badgeColor).opacity(0.3), lineWidth: 0.5)
                    )
            )
            .padding(6)
        }
    }

    @ViewBuilder
    static func elementBackground(for element: CanvasElement) -> some View {
        switch element.kind {
        case .tile:
            Theme.Colors.appBackground
        case .frame:
            Color.clear
        case .text:
            Color.clear
        }
    }

    @ViewBuilder
    static func selectionBorder(isSelected: Bool, isHovered: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.Colors.accent.opacity(0.6), lineWidth: 1.5)
        } else if isHovered {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        }
    }
}
