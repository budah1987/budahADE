import Foundation
import Combine

// MARK: - Build Status

enum BuildStatus: String, Equatable {
    case idle
    case working
    case blocked
    case completed
}

// MARK: - Build Status State

@MainActor
final class BuildStatusState: ObservableObject {
    @Published var currentTaskTitle: String?
    @Published var currentTaskIndex: Int?
    @Published var lastAction: String?
    @Published var blockers: String?
    @Published var status: BuildStatus = .idle
    @Published var taskStartedAt: Date?

    /// Formatted elapsed time since current task started
    var elapsed: String? {
        guard let start = taskStartedAt, status == .working else { return nil }
        let interval = Date().timeIntervalSince(start)
        let seconds = Int(interval) % 60
        let minutes = Int(interval) / 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}
