import Foundation
import Combine

// MARK: - Task Mode

enum TaskMode: String {
    case plan
    case build
}

// MARK: - Task Status

enum TaskStatus {
    case active
    case completed
}

// MARK: - Task State

@MainActor
final class TaskState: ObservableObject, Identifiable {
    let id: UUID
    @Published var name: String
    @Published var branchName: String
    let baseBranch: String
    let worktreePath: String
    let repoPath: String
    @Published var status: TaskStatus = .active
    @Published var mode: TaskMode = .build
    @Published var tabs: [TabInfo] = []
    @Published var selectedTabId: UUID?
    @Published var terminals: [UUID: TerminalPanel] = [:]
    @Published var planCanvas: PlanCanvasState?  // Legacy — kept for existing canvas references
    @Published var planTabId: UUID?  // Dedicated plan conversation tab
    let specState = SpecState()
    let buildStatus = BuildStatusState()
    private var specWatcher: SpecWatcher?
    private var buildStatusWatcher: BuildStatusWatcher?
    let createdAt: Date = Date()

    /// Formatted elapsed time since task creation
    var elapsedTime: String {
        let interval = Date().timeIntervalSince(createdAt)
        let minutes = Int(interval) / 60
        if minutes < 60 { return "\(max(1, minutes))m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }

    /// Summary of agent statuses across all tabs
    var statusSummary: [(AgentStatus, Int)] {
        var counts: [Int] = [0, 0, 0, 0] // inactive, thinking, working, completed
        for tab in tabs {
            switch tab.agentStatus {
            case .inactive:  counts[0] += 1
            case .thinking:  counts[1] += 1
            case .working:   counts[2] += 1
            case .completed: counts[3] += 1
            }
        }
        var result: [(AgentStatus, Int)] = []
        if counts[2] > 0 { result.append((.working, counts[2])) }
        if counts[1] > 0 { result.append((.thinking, counts[1])) }
        if counts[0] > 0 { result.append((.inactive, counts[0])) }
        if counts[3] > 0 { result.append((.completed, counts[3])) }
        return result
    }

    private var previousStatuses: [UUID: AgentStatus] = [:]
    private var cancellables = Set<AnyCancellable>()

    init(
        id: UUID = UUID(),
        name: String,
        branchName: String,
        baseBranch: String = "main",
        worktreePath: String,
        repoPath: String
    ) {
        self.id = id
        self.name = name
        self.branchName = branchName
        self.baseBranch = baseBranch
        self.worktreePath = worktreePath
        self.repoPath = repoPath

        observeTitleChanges()
    }

    /// Call after the worktree directory is ready on disk.
    func startTerminal() {
        guard tabs.isEmpty else { return } // Already started
        createTab()
        autoLaunchClaude()
        specWatcher = SpecWatcher(worktreePath: worktreePath, specState: specState)
        specWatcher?.startWatching()
    }

    // MARK: - Plan/Build Mode

    func enterPlanMode() {
        if planCanvas == nil {
            let canvas = PlanCanvasState(
                worktreePath: worktreePath,
                taskName: name,
                branchName: branchName
            )
            if let snapshot = CanvasPersistence.load(from: worktreePath) {
                canvas.restore(from: snapshot)
            }
            planCanvas = canvas
        }
        mode = .plan
    }

    func enterBuildMode() {
        mode = .build
        focusActiveTerminal()
        // Start build status watcher if we have a spec
        if specState.hasSpec && buildStatusWatcher == nil {
            buildStatusWatcher = BuildStatusWatcher(worktreePath: worktreePath, buildStatus: buildStatus)
            buildStatusWatcher?.startWatching()
        }
    }

    // MARK: - Tab Management

    @discardableResult
    func createTab(launchAgent: Bool = false, agent: AgentMode? = nil) -> UUID {
        let panel = TerminalPanel(workingDirectory: worktreePath)
        let id = panel.id
        var tab = TabInfo(id: id, title: "Terminal", isRunning: false)
        tab.agentMode = agent
        tabs.append(tab)
        terminals[id] = panel
        selectedTabId = id

        if launchAgent {
            launchClaudeInTab(id, agent: agent)
        }

        return id
    }

    /// Launch Claude in a specific tab with spec awareness
    func launchClaudeInTab(_ tabId: UUID, agent: AgentMode? = nil) {
        guard let panel = terminals[tabId] else { return }

        let specPath = specState.activeSpec?.filePath
        let progress: (completed: Int, total: Int)? = specState.activeSpec.map {
            (completed: $0.completedCount, total: $0.totalCount)
        }

        let command: String
        if let specPath, let progress, agent == nil {
            // Builder mode: spec-focused execution
            command = AgentPrompts.builderLaunchCommand(
                taskName: name,
                branchName: branchName,
                worktreePath: worktreePath,
                specFilePath: specPath,
                specProgress: progress
            )
        } else {
            // Agent mode or no spec: use role prompt with optional spec context
            command = AgentPrompts.launchCommand(
                agent: agent ?? .claude,
                taskName: name,
                branchName: branchName,
                worktreePath: worktreePath,
                panelId: panel.id,
                specFilePath: specPath,
                specProgress: progress
            )
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            panel.sendCommand(command)
        }
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        terminals[id]?.close()
        terminals.removeValue(forKey: id)
        tabs.remove(at: index)

        if planTabId == id {
            planTabId = nil
        }

        if selectedTabId == id {
            if !tabs.isEmpty {
                selectedTabId = tabs[min(index, tabs.count - 1)].id
            } else {
                selectedTabId = nil
            }
        }
    }

    func selectTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        selectedTabId = id
        // Clear completed state when user opens the tab
        if tabs[index].agentStatus == .completed {
            tabs[index].agentStatus = .inactive
        }
    }

    func selectTabByIndex(_ index: Int) {
        guard !tabs.isEmpty else { return }
        let targetId: UUID?
        if index == 9 {
            targetId = tabs.last?.id
        } else {
            let zeroIndex = index - 1
            guard zeroIndex >= 0, zeroIndex < tabs.count else { return }
            targetId = tabs[zeroIndex].id
        }
        if let id = targetId {
            selectTab(id)
        }
    }

    // MARK: - Focus Management

    func focusActiveTerminal() {
        if let id = selectedTabId, let panel = terminals[id] {
            panel.focus()
        }
    }

    func unfocusAllTerminals() {
        for panel in terminals.values {
            panel.unfocus()
        }
    }

    // MARK: - Close All

    func closeAllTerminals() {
        for panel in terminals.values {
            panel.close()
        }
        terminals.removeAll()
        tabs.removeAll()
        selectedTabId = nil
        specWatcher?.stopWatching()
        buildStatusWatcher?.stopWatching()
        planCanvas?.saveNow()
        planCanvas?.closeAll()
    }

    // MARK: - Session Persistence

    func saveSessionState() {
        var tabSnapshots: [TabSnapshot] = []

        for tab in tabs {
            var scrollbackPath: String?
            if let panel = terminals[tab.id] {
                if let text = panel.readScrollback(), !text.isEmpty {
                    scrollbackPath = try? SessionPersistence.saveScrollback(
                        text, tabId: tab.id, to: worktreePath
                    )
                }
            }

            tabSnapshots.append(TabSnapshot(
                id: tab.id,
                title: tab.title,
                claudeSessionId: tab.claudeSessionId,
                agentMode: tab.agentMode?.rawValue,
                isActive: tab.id == selectedTabId,
                scrollbackPath: scrollbackPath
            ))
        }

        let session = SessionSnapshot(tabs: tabSnapshots, selectedTabId: selectedTabId)
        try? SessionPersistence.save(session, to: worktreePath)
    }

    // MARK: - Private

    private func autoLaunchClaude() {
        guard let firstTabId = tabs.first?.id else { return }
        launchClaudeInTab(firstTabId)
    }

    private func observeTitleChanges() {
        NotificationCenter.default.publisher(for: .terminalTitleChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let info = notification.userInfo,
                      let surfaceId = info["surfaceId"] as? UUID,
                      let title = info["title"] as? String,
                      let index = self.tabs.firstIndex(where: { $0.id == surfaceId }) else { return }

                self.tabs[index].title = title
                let newStatus = Self.parseAgentStatus(from: title)
                print("[AgentStatus] title=\"\(title)\" → \(newStatus)")
                let oldStatus = self.previousStatuses[surfaceId] ?? .inactive
                self.previousStatuses[surfaceId] = newStatus

                // Transition from active → idle: mark completed (persists until user opens tab)
                if (oldStatus == .working || oldStatus == .thinking) && newStatus == .inactive {
                    self.tabs[index].agentStatus = .completed
                } else if self.tabs[index].agentStatus == .completed && newStatus == .inactive {
                    // Stay completed — don't overwrite with inactive until user opens the tab
                } else {
                    self.tabs[index].agentStatus = newStatus
                }
            }
            .store(in: &cancellables)
    }

    /// Map terminal title patterns to agent status.
    /// Claude CLI sets terminal titles with two patterns:
    ///   - "✳ Claude Code" → idle at prompt (ready for input) → .thinking (Claude is present)
    ///   - "⠂ Claude Code" / Braille spinner dots → actively processing → .working
    ///   - Shell prompt (%, $, ❯) → Claude not running → .inactive
    ///   - Transition from active → inactive triggers .completed (handled in observeTitleChanges)
    private static func parseAgentStatus(from title: String) -> AgentStatus {
        let t = title.trimmingCharacters(in: .whitespaces)
        let tl = t.lowercased()

        // Shell prompt — Claude not running
        if tl.hasSuffix("%") || tl.hasSuffix("$") || tl.hasSuffix("❯") ||
           tl == "zsh" || tl == "bash" || tl == "fish" {
            return .inactive
        }

        // Braille spinner dots (U+2800–U+28FF) → Claude is actively processing
        let hasBrailleSpinner = t.unicodeScalars.contains { $0.value >= 0x2800 && $0.value <= 0x28FF }
        if hasBrailleSpinner {
            return .working
        }

        // "✳ Claude Code" or similar — Claude running, waiting for input
        if tl.contains("claude") {
            return .thinking
        }

        // Everything else
        return .inactive
    }
}
