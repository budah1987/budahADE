import Foundation

// MARK: - Archived Plan Tab

struct ArchivedPlanTab: Identifiable {
    let id: UUID = UUID()
    let title: String
    let role: AgentMode
    let messageCount: Int
    let preview: String
    let archivedAt: Date
}

// MARK: - Plan Tab Status

enum PlanTabStatus: Equatable {
    case idle
    case connecting
    case streaming
    case done
}

// MARK: - Plan Tab Info

struct PlanTabInfo: Identifiable, Equatable {
    let id: UUID
    var title: String
    var status: PlanTabStatus
    let role: AgentMode
    var isBuilder: Bool

    init(id: UUID = UUID(), title: String = "Plan", status: PlanTabStatus = .idle, role: AgentMode = .researcher, isBuilder: Bool = false) {
        self.id = id
        self.title = title
        self.status = status
        self.role = role
        self.isBuilder = isBuilder
    }

    /// Map to TabAgentState for reuse with ConversationTab rendering
    var agentState: TabAgentState {
        switch status {
        case .idle:       return .idle
        case .connecting: return .working
        case .streaming:  return .working
        case .done:       return .completed
        }
    }

    /// Tab type for ConversationTab rendering
    var tabType: TabType {
        isBuilder ? .builder : .terminal
    }
}
