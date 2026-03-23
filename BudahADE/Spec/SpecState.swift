import SwiftUI
import Combine

@MainActor
final class SpecState: ObservableObject {
    @Published var allSpecs: [SpecParseResult] = []
    @Published var selectedSpecIndex: Int?

    // MARK: - Active Spec (selected or first)

    var activeSpec: SpecParseResult? {
        guard let idx = selectedSpecIndex, idx < allSpecs.count else { return nil }
        return allSpecs[idx]
    }

    // MARK: - Backward-compatible accessors (delegate to activeSpec)

    var result: SpecParseResult? { activeSpec }
    var hasSpec: Bool { activeSpec != nil }
    var progress: Double { activeSpec?.progress ?? 0 }
    var completedCount: Int { activeSpec?.completedCount ?? 0 }
    var totalCount: Int { activeSpec?.totalCount ?? 0 }
    var sections: [SpecSection] { activeSpec?.sections ?? [] }

    var currentTaskIndex: Int? {
        activeSpec?.tasks.firstIndex(where: { !$0.isCompleted })
    }

    var currentTaskTitle: String? {
        guard let idx = currentTaskIndex,
              let spec = activeSpec,
              idx < spec.tasks.count else { return nil }
        return spec.tasks[idx].title
    }

    /// The section containing the current (first unchecked) task
    var currentSection: SpecSection? {
        guard let task = activeSpec?.tasks.first(where: { !$0.isCompleted }),
              let sectionId = task.sectionId else { return nil }
        return sections.first(where: { $0.id == sectionId })
    }

    // MARK: - Selection

    func selectSpec(at index: Int) {
        guard index >= 0, index < allSpecs.count else { return }
        selectedSpecIndex = index
    }

    func selectSpec(filePath: String) {
        if let idx = allSpecs.firstIndex(where: { $0.filePath == filePath }) {
            selectedSpecIndex = idx
        }
    }

    // MARK: - Bulk Update (preserves selection)

    func updateAll(from specs: [SpecParseResult]) {
        // Preserve selection by file path
        let previousPath = activeSpec?.filePath

        allSpecs = specs

        if let path = previousPath,
           let idx = specs.firstIndex(where: { $0.filePath == path }) {
            selectedSpecIndex = idx
        } else if !specs.isEmpty {
            selectedSpecIndex = 0
        } else {
            selectedSpecIndex = nil
        }
    }
}
