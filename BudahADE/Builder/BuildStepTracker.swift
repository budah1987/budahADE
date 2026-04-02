import Foundation

// MARK: - Build Step Tracker

/// Parses agent output for step progress markers and updates BuilderSession accordingly.
/// Markers are HTML comments that the agent emits per the builder prompt instructions.
@MainActor
final class BuildStepTracker {
    weak var session: BuilderSession?

    /// Regex patterns for step markers
    private static let stepStartPattern = /<!-- STEP_START:(\d+) -->/
    private static let stepDonePattern = /<!-- STEP_DONE:(\d+) -->/
    private static let stepFailPattern = /<!-- STEP_FAIL:(\d+) -->/
    private static let subtaskPattern = /<!-- SUBTASK:(\d+)\.(\d+):(\w+) -->/
    private static let buildCompletePattern = /<!-- BUILD_COMPLETE -->/

    /// Process a chunk of text (streaming delta or full message) for markers.
    /// Returns the text with markers stripped (for display in chat).
    func processText(_ text: String) -> String {
        guard let session else { return text }

        var cleanText = text

        // STEP_START
        for match in text.matches(of: Self.stepStartPattern) {
            if let index = Int(match.1), session.steps.indices.contains(index) {
                session.startStep(at: index)
                if let lastMsg = session.messages.last {
                    session.steps[index].chatMessageRange = BuildStep.ChatMessageRange(start: lastMsg.id)
                }
            }
            cleanText = cleanText.replacingOccurrences(of: String(match.0), with: "")
        }

        // STEP_DONE
        for match in text.matches(of: Self.stepDonePattern) {
            if let index = Int(match.1), session.steps.indices.contains(index) {
                if let lastMsg = session.messages.last {
                    session.steps[index].chatMessageRange?.end = lastMsg.id
                }
                session.completeStep(at: index)
            }
            cleanText = cleanText.replacingOccurrences(of: String(match.0), with: "")
        }

        // STEP_FAIL
        for match in text.matches(of: Self.stepFailPattern) {
            if let index = Int(match.1), session.steps.indices.contains(index) {
                if let lastMsg = session.messages.last {
                    session.steps[index].chatMessageRange?.end = lastMsg.id
                }
                session.failStep(at: index, error: "Step failed — check chat for details")
            }
            cleanText = cleanText.replacingOccurrences(of: String(match.0), with: "")
        }

        // SUBTASK
        for match in text.matches(of: Self.subtaskPattern) {
            if let stepIdx = Int(match.1),
               let subIdx = Int(match.2),
               session.steps.indices.contains(stepIdx),
               session.steps[stepIdx].subTasks.indices.contains(subIdx) {
                let state: StepState = String(match.3) == "done" ? .done : .building
                session.steps[stepIdx].subTasks[subIdx].state = state
            }
            cleanText = cleanText.replacingOccurrences(of: String(match.0), with: "")
        }

        // BUILD_COMPLETE
        if text.contains("<!-- BUILD_COMPLETE -->") {
            session.buildState = .done
            session.activeStepIndex = nil
            cleanText = cleanText.replacingOccurrences(of: "<!-- BUILD_COMPLETE -->", with: "")
        }

        return cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Check if text contains any step markers
    static func containsMarkers(_ text: String) -> Bool {
        text.contains("<!-- STEP_") || text.contains("<!-- SUBTASK:") || text.contains("<!-- BUILD_COMPLETE -->")
    }
}
