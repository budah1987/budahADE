import Foundation

// MARK: - Build State

enum BuildState: Equatable {
    case ready       // Spec loaded, not started — user reviews/edits
    case building    // Agent working on a spec item
    case paused      // User paused the builder
    case done        // All spec items complete
    case failed      // One or more items failed
}

// MARK: - Step State

enum StepState: String, Equatable {
    case done
    case building
    case queued
    case failed
    case skipped
}

// MARK: - Build Sub-Task

struct BuildSubTask: Identifiable, Equatable {
    let id: String
    var title: String
    var state: StepState

    init(id: String = UUID().uuidString, title: String, state: StepState = .queued) {
        self.id = id
        self.title = title
        self.state = state
    }
}

// MARK: - Build Step

struct BuildStep: Identifiable, Equatable {
    let id: String
    var title: String
    var description: String
    var state: StepState
    var subTasks: [BuildSubTask]
    var filesChanged: [String]
    var error: String?
    var attemptCount: Int
    var notesForBuilder: String
    var chatMessageRange: ChatMessageRange?

    struct ChatMessageRange: Equatable {
        let start: UUID
        var end: UUID?
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        description: String = "",
        state: StepState = .queued,
        subTasks: [BuildSubTask] = [],
        filesChanged: [String] = [],
        error: String? = nil,
        attemptCount: Int = 0,
        notesForBuilder: String = "",
        chatMessageRange: ChatMessageRange? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.state = state
        self.subTasks = subTasks
        self.filesChanged = filesChanged
        self.error = error
        self.attemptCount = attemptCount
        self.notesForBuilder = notesForBuilder
        self.chatMessageRange = chatMessageRange
    }

    var subTasksDone: Int { subTasks.filter { $0.state == .done }.count }
    var subTasksTotal: Int { subTasks.count }
}

// MARK: - Chat Turn Marker

struct ChatTurnMarker: Identifiable, Equatable {
    let id: UUID
    let messageId: UUID
    var preview: String      // truncated first line (~60 chars)
    var fullText: String     // full user message for hover tooltip
    var stepIndex: Int?      // which build step this falls under (nil = pre-build)

    init(messageId: UUID, preview: String, fullText: String, stepIndex: Int? = nil) {
        self.id = UUID()
        self.messageId = messageId
        self.preview = preview
        self.fullText = fullText
        self.stepIndex = stepIndex
    }

    /// Create a marker from a ChatMessage, auto-truncating preview
    static func from(_ message: ChatMessage, stepIndex: Int? = nil) -> ChatTurnMarker {
        let firstLine = message.content.components(separatedBy: .newlines).first ?? message.content
        let preview = firstLine.count > 60 ? String(firstLine.prefix(57)) + "..." : firstLine
        return ChatTurnMarker(
            messageId: message.id,
            preview: preview,
            fullText: message.content,
            stepIndex: stepIndex
        )
    }
}

// MARK: - Builder Session

@MainActor @Observable
final class BuilderSession {
    var buildState: BuildState = .ready
    var steps: [BuildStep] = []
    var activeStepIndex: Int? = nil
    var messages: [ChatMessage] = []
    var turnMarkers: [ChatTurnMarker] = []
    var isStreaming: Bool = false
    var currentActivity: String? = nil
    var contextSummary: String = ""

    // Agent session reference (set when build starts)
    var agentSessionId: UUID? = nil

    // MARK: - Computed

    var completedCount: Int { steps.filter { $0.state == .done }.count }
    var totalCount: Int { steps.count }

    var activeStep: BuildStep? {
        guard let idx = activeStepIndex, steps.indices.contains(idx) else { return nil }
        return steps[idx]
    }

    var failedSteps: [BuildStep] { steps.filter { $0.state == .failed } }

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    // MARK: - Factory

    /// Create a BuilderSession from a parsed spec result.
    /// Prefers sections as steps (H2/H3 headings). Falls back to flat checkbox list.
    static func from(spec: SpecParseResult, contextSummary: String = "") -> BuilderSession {
        let session = BuilderSession()
        session.contextSummary = contextSummary

        if !spec.sections.isEmpty {
            // Each section → one BuildStep; its checkboxes → sub-tasks
            session.steps = spec.sections.map { section in
                let subTasks = section.tasks.map { task in
                    BuildSubTask(title: task.title, state: task.isCompleted ? .done : .queued)
                }
                let allDone = !subTasks.isEmpty && subTasks.allSatisfy { $0.state == .done }
                return BuildStep(
                    id: section.id,
                    title: section.title,
                    description: section.content,
                    state: allDone ? .done : .queued,
                    subTasks: subTasks
                )
            }
        } else {
            // Fallback: flat checkbox list → each checkbox is a step
            session.steps = spec.tasks.map { task in
                BuildStep(
                    id: "\(task.id)",
                    title: task.title,
                    state: task.isCompleted ? .done : .queued
                )
            }
        }
        return session
    }

    // MARK: - Step Transitions

    func startStep(at index: Int) {
        guard steps.indices.contains(index) else { return }
        activeStepIndex = index
        steps[index].state = .building
        buildState = .building
    }

    func completeStep(at index: Int, filesChanged: [String] = []) {
        guard steps.indices.contains(index) else { return }
        steps[index].state = .done
        steps[index].filesChanged = filesChanged

        // Advance to next queued step
        if let next = steps.indices.first(where: { steps[$0].state == .queued }) {
            activeStepIndex = next
        } else if failedSteps.isEmpty {
            activeStepIndex = nil
            buildState = .done
        } else {
            activeStepIndex = nil
            buildState = .failed
        }
    }

    func failStep(at index: Int, error: String) {
        guard steps.indices.contains(index) else { return }
        steps[index].state = .failed
        steps[index].error = error
        steps[index].attemptCount += 1
        buildState = .failed
    }

    func skipStep(at index: Int) {
        guard steps.indices.contains(index) else { return }
        steps[index].state = .skipped

        // Advance to next queued step
        if let next = steps.indices.first(where: { steps[$0].state == .queued }) {
            activeStepIndex = next
        } else {
            activeStepIndex = nil
            buildState = failedSteps.isEmpty ? .done : .failed
        }
    }

    // MARK: - Turn Markers

    func addTurnMarker(for message: ChatMessage) {
        guard message.role == .user else { return }
        let marker = ChatTurnMarker.from(message, stepIndex: activeStepIndex)
        turnMarkers.append(marker)
    }
}
