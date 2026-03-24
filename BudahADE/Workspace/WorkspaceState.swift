import Foundation
import Combine

// MARK: - Left Panel Tab

enum LeftPanelTab: String, CaseIterable {
    case files
    case spec
}

// MARK: - Workspace State

@MainActor
final class WorkspaceState: ObservableObject, Identifiable {
    let id = UUID()
    @Published var projectPath: String
    @Published var leftPanelVisible: Bool = true
    @Published var rightPanelVisible: Bool = false
    @Published var activeLeftTab: LeftPanelTab = .files
    @Published var tasks: [TaskState] = []
    @Published var activeTaskId: UUID?
    @Published var showNewTaskSheet: Bool = false
    @Published var taskForCompletion: TaskState?

    var projectName: String {
        (projectPath as NSString).lastPathComponent
    }

    var activeTask: TaskState? {
        guard let id = activeTaskId else { return nil }
        return tasks.first(where: { $0.id == id })
    }

    // Forward individual TaskState changes → WorkspaceState.objectWillChange
    // so WorkspaceView re-renders when tabs/terminals change inside a task.
    private var taskCancellables: [UUID: [AnyCancellable]] = [:]

    init(projectPath: String, restoring: Bool = false) {
        self.projectPath = projectPath
        ensureClaudeMd()
        if !restoring {
            // No auto-task creation — show "What are you working on?" prompt
            showNewTaskSheet = true
        }
    }

    // MARK: - Task Management

    func createTask(name: String, branchName: String, baseBranch: String = "main") {
        let worktreePath = GitWorktreeManager.worktreeDirectory(
            repoPath: projectPath,
            branchName: branchName
        )

        let task = TaskState(
            name: name,
            branchName: branchName,
            baseBranch: baseBranch,
            worktreePath: worktreePath,
            repoPath: projectPath
        )

        // Forward task's published changes → workspace so WorkspaceView re-renders
        var cancellables: [AnyCancellable] = []
        cancellables.append(
            task.objectWillChange
                .sink { [weak self] (_: Void) in self?.objectWillChange.send() }
        )
        cancellables.append(
            task.specState.objectWillChange
                .sink { [weak self] (_: Void) in self?.objectWillChange.send() }
        )
        taskCancellables[task.id] = cancellables

        tasks.append(task)
        activeTaskId = task.id

        // Create worktree, then start terminal once directory is ready
        Task {
            do {
                try await GitWorktreeManager.createWorktree(
                    repoPath: projectPath,
                    branchName: branchName,
                    baseBranch: baseBranch
                )
            } catch {
                print("Worktree creation failed: \(error.localizedDescription)")
            }
            // Start terminal even if worktree failed — falls back to worktreePath
            task.startTerminal()
        }
    }

    /// Restore a task from saved state (no worktree creation — already exists)
    func restoreTask(_ snapshot: TaskSnapshot) {
        let worktreePath = GitWorktreeManager.worktreeDirectory(
            repoPath: projectPath,
            branchName: snapshot.branchName
        )

        // Verify worktree directory exists
        guard FileManager.default.fileExists(atPath: worktreePath) else {
            print("[WorkspaceState] Skipping restore — worktree missing: \(worktreePath)")
            return
        }

        let task = TaskState(
            name: snapshot.name,
            branchName: snapshot.branchName,
            baseBranch: snapshot.baseBranch,
            worktreePath: worktreePath,
            repoPath: projectPath
        )

        var cancellables: [AnyCancellable] = []
        cancellables.append(
            task.objectWillChange
                .sink { [weak self] (_: Void) in self?.objectWillChange.send() }
        )
        cancellables.append(
            task.specState.objectWillChange
                .sink { [weak self] (_: Void) in self?.objectWillChange.send() }
        )
        taskCancellables[task.id] = cancellables

        tasks.append(task)
        activeTaskId = task.id

        // Start terminal — will try restoring saved session state first
        task.startTerminal()
    }

    func selectTask(_ id: UUID) {
        guard tasks.contains(where: { $0.id == id }) else { return }
        activeTask?.unfocusAllTerminals()
        activeTaskId = id
        activeTask?.focusActiveTerminal()

        // Reset left panel if spec tab selected but new task has no spec
        if activeLeftTab == .spec, activeTask?.specState.hasSpec != true {
            activeLeftTab = .files
        }
    }

    func selectTaskByIndex(_ index: Int) {
        guard !tasks.isEmpty else { return }
        if index == 9 {
            if let last = tasks.last { selectTask(last.id) }
            return
        }
        let zeroIndex = index - 1
        guard zeroIndex >= 0, zeroIndex < tasks.count else { return }
        selectTask(tasks[zeroIndex].id)
    }

    func deleteTask(_ id: UUID) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        let repoPath = task.repoPath
        let worktreePath = task.worktreePath

        task.saveSessionState()
        task.planCanvas?.saveNow()
        task.closeAllTerminals()

        if let index = tasks.firstIndex(where: { $0.id == id }) {
            tasks.remove(at: index)
        }

        taskCancellables.removeValue(forKey: id)

        if activeTaskId == id {
            activeTaskId = tasks.first?.id
        }

        if tasks.isEmpty {
            showNewTaskSheet = true
        }

        // Remove worktree from disk in background
        Task {
            try? await GitWorktreeManager.removeWorktree(
                repoPath: repoPath,
                worktreePath: worktreePath
            )
        }
    }

    func completeTask(_ id: UUID) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        task.status = .completed
    }

    // MARK: - Private

    private func ensureClaudeMd() {
        let claudeMdPath = (projectPath as NSString).appendingPathComponent("CLAUDE.md")
        guard !FileManager.default.fileExists(atPath: claudeMdPath) else { return }

        let content = """
        ## Session Continuity
        At the start of each session, check your auto-memory for prior context.
        Before ending a session, save a brief summary of work done to your auto-memory.
        """
        FileManager.default.createFile(atPath: claudeMdPath, contents: content.data(using: .utf8))
    }
}
