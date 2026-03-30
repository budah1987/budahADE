import Foundation

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

    init(id: UUID = UUID(), title: String = "Plan", status: PlanTabStatus = .idle, role: AgentMode = .researcher) {
        self.id = id
        self.title = title
        self.status = status
        self.role = role
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
}
