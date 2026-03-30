import SwiftUI

// MARK: - Agent Mode

enum AgentMode: String, CaseIterable, Identifiable, Codable {
    case claude
    case researcher
    case ideator
    case designer
    case developer
    case specAuthor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude:      return "Claude"
        case .researcher:  return "Researcher"
        case .ideator:     return "Ideator"
        case .designer:    return "Designer"
        case .developer:   return "Developer"
        case .specAuthor:  return "Spec Author"
        }
    }

    var description: String {
        switch self {
        case .claude:      return "Raw CLI, no restrictions"
        case .researcher:  return "Deep dives, structured reports"
        case .ideator:     return "Business partner, strategic thinking"
        case .designer:    return "UI/UX, component design, interaction patterns"
        case .developer:   return "Architecture, code, implementation"
        case .specAuthor:  return "Synthesizes findings into structured specs"
        }
    }

    var iconName: String {
        switch self {
        case .claude:      return "sparkle"
        case .researcher:  return "magnifyingglass"
        case .ideator:     return "lightbulb"
        case .designer:    return "paintbrush"
        case .developer:   return "hammer"
        case .specAuthor:  return "doc.text"
        }
    }

    var dotColor: Color {
        switch self {
        case .claude:      return Theme.textSecondary
        case .researcher:  return Color(hex: 0x7ab5a0)
        case .ideator:     return Color(hex: 0xc4a85c)
        case .designer:    return .pink
        case .developer:   return Theme.accent
        case .specAuthor:  return .orange
        }
    }

    var defaultChatModel: AgentModel {
        switch self {
        case .claude:      return .sonnet
        case .researcher:  return .sonnet
        case .ideator:     return .opus
        case .designer:    return .opus
        case .developer:   return .sonnet
        case .specAuthor:  return .opus
        }
    }

    /// Allowed tools for chat agent tiles. Nil = all tools allowed.
    var chatAllowedTools: [String]? {
        switch self {
        case .claude:      return nil
        case .researcher:  return ["WebSearch", "WebFetch", "Read", "Glob", "Grep"]
        case .ideator:     return ["Read", "Glob", "Grep"]
        case .designer:    return ["Read", "Glob", "Grep"]
        case .developer:   return ["Read", "Glob", "Grep", "Edit", "Write", "Bash"]
        case .specAuthor:  return ["Read", "Glob", "Grep", "Write"]
        }
    }

    /// Max agentic turns before the subprocess stops. Nil = unlimited.
    var chatMaxTurns: Int? {
        switch self {
        case .claude:      return nil
        case .researcher:  return 10
        case .ideator:     return 5
        case .designer:    return 5
        case .developer:   return 10
        case .specAuthor:  return nil
        }
    }

    /// Keyboard shortcut index (1-5) for plan role tabs. Nil for .claude.
    var roleShortcutIndex: Int? {
        switch self {
        case .claude:      return nil
        case .researcher:  return 1
        case .ideator:     return 2
        case .designer:    return 3
        case .developer:   return 4
        case .specAuthor:  return 5
        }
    }

    /// The 5 roles used in Plan mode (excludes .claude).
    static var planRoles: [AgentMode] {
        [.researcher, .ideator, .designer, .developer, .specAuthor]
    }
}
