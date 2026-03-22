import SwiftUI
import Combine

@MainActor
final class SpecState: ObservableObject {
    @Published var result: SpecParseResult?
    @Published var currentTaskIndex: Int?

    var hasSpec: Bool { result != nil }
    var progress: Double { result?.progress ?? 0 }
    var completedCount: Int { result?.completedCount ?? 0 }
    var totalCount: Int { result?.totalCount ?? 0 }

    var currentTaskTitle: String? {
        guard let idx = currentTaskIndex,
              let result,
              idx < result.tasks.count else { return nil }
        return result.tasks[idx].title
    }

    func update(from result: SpecParseResult?) {
        self.result = result
        self.currentTaskIndex = result?.tasks.firstIndex(where: { !$0.isCompleted })
    }
}
