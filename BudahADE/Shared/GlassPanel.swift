import SwiftUI

// MARK: - Glass Panel Style

enum GlassPanelStyle {
    case sidebar      // Heavier: ultraThinMaterial + sidebarBackground tint
    case actionBar    // Medium: actionBarBackground opacity
    case card         // Subtle: cardBackground + borderLight
    case cardActive   // Subtle: cardBackground + borderActive (selected state)
    case modal        // Medium: actionBarBackground + borderLight
    case input        // Bordered: transparent + borderInput
}

// MARK: - Glass Panel

struct GlassPanel<Content: View>: View {
    let style: GlassPanelStyle
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(backgroundForStyle)
            .clipShape(RoundedRectangle(cornerRadius: radiusForStyle, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radiusForStyle, style: .continuous)
                    .strokeBorder(borderForStyle, lineWidth: borderWidthForStyle)
            )
    }

    // MARK: - Style Mapping

    @ViewBuilder
    private var backgroundForStyle: some View {
        switch style {
        case .sidebar:
            ZStack {
                GlassBackground(material: .sidebar)
                Theme.Colors.sidebarBackground.opacity(0.85)
            }
        case .actionBar:
            ZStack {
                GlassBackground(material: .popover, cornerRadius: Theme.Radius.lg)
                Theme.Colors.actionBarBackground
            }
        case .card:
            ZStack {
                GlassBackground(material: .hudWindow, cornerRadius: Theme.Radius.md)
                Color.white.opacity(0.04)
            }
        case .cardActive:
            ZStack {
                GlassBackground(material: .hudWindow, cornerRadius: Theme.Radius.md)
                Color.white.opacity(0.06)
            }
        case .modal:
            ZStack {
                GlassBackground(material: .popover, cornerRadius: Theme.Radius.lg)
                Theme.Colors.actionBarBackground
            }
        case .input:
            Color.clear
        }
    }

    private var borderForStyle: Color {
        switch style {
        case .sidebar:     return .clear
        case .actionBar:   return .clear
        case .card:        return Theme.Colors.borderLight
        case .cardActive:  return Theme.Colors.borderActive
        case .modal:       return Theme.Colors.borderLight
        case .input:       return Theme.Colors.borderInput
        }
    }

    private var borderWidthForStyle: CGFloat {
        switch style {
        case .card, .cardActive, .modal: return 1
        case .input: return 1
        default: return 0
        }
    }

    private var radiusForStyle: CGFloat {
        switch style {
        case .sidebar:               return 0
        case .card, .cardActive:     return Theme.Radius.md
        case .actionBar, .modal:     return Theme.Radius.lg
        case .input:                 return Theme.Radius.lg
        }
    }
}
