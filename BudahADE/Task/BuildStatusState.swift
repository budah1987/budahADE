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
}
