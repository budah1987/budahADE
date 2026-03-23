import SwiftUI

// MARK: - Agent Mode

enum AgentMode: String, CaseIterable, Identifiable {
    case claude
    case researcher
    case ideator
    case developer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude:     return "Claude"
        case .researcher: return "Researcher"
        case .ideator:    return "Ideator"
        case .developer:  return "Developer"
        }
    }

    var description: String {
        switch self {
        case .claude:     return "General agent"
        case .researcher: return "Investigate, analyze, synthesize"
        case .ideator:    return "Product thinking, problem discovery"
        case .developer:  return "Technical feasibility, architecture"
        }
    }

    var iconName: String {
        switch self {
        case .claude:     return "sparkle"
        case .researcher: return "magnifyingglass"
        case .ideator:    return "lightbulb"
        case .developer:  return "hammer"
        }
    }

    var dotColor: Color {
        switch self {
        case .claude:     return Theme.textSecondary
        case .researcher: return Color(hex: 0x7ab5a0)
        case .ideator:    return Color(hex: 0xc4a85c)
        case .developer:  return Theme.accent
        }
    }
}

// MARK: - Tile Type

enum TileType: Equatable {
    case terminal(panelId: UUID, agent: AgentMode)
    case stickyNote
    case textBox
    case markdown(path: String)
    case image(path: String)
    case browser(url: URL?)

    var displayName: String {
        switch self {
        case .terminal(_, let agent): return agent.displayName
        case .stickyNote:             return "Sticky Note"
        case .textBox:                return "Text Box"
        case .markdown:               return "Markdown"
        case .image:                  return "Image"
        case .browser:                return "Browser"
        }
    }

    var iconName: String {
        switch self {
        case .terminal(_, let agent): return agent.iconName
        case .stickyNote:             return "note.text"
        case .textBox:                return "text.alignleft"
        case .markdown:               return "doc.text"
        case .image:                  return "photo"
        case .browser:                return "globe"
        }
    }
}
