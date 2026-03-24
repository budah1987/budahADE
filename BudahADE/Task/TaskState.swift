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
        if restoreSessionState() {
            specWatcher = SpecWatcher(worktreePath: worktreePath, specState: specState)
            specWatcher?.startWatching()
            return
        }
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

    /// Launch Claude in a specific tab with spec awareness.
    /// If tmuxSession is provided and alive, reattaches instead of launching fresh.
    func launchClaudeInTab(_ tabId: UUID, agent: AgentMode? = nil, tmuxSession: String? = nil) {
        guard let panel = terminals[tabId] else { return }

        // If we have a tmux session that's still alive, just reattach — Claude is still running
        if TmuxSessionManager.isAvailable,
           let sessionName = tmuxSession,
           TmuxSessionManager.sessionExists(sessionName) {
            print("[TaskState] Reattaching tmux session: \(sessionName)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                panel.sendCommand(TmuxSessionManager.attachCommand(name: sessionName))
            }
            return
        }

        // Build the Claude launch command
        let specPath = specState.activeSpec?.filePath
        let progress: (completed: Int, total: Int)? = specState.activeSpec.map {
            (completed: $0.completedCount, total: $0.totalCount)
        }

        let claudeCommand: String
        if let specPath, let progress, agent == nil {
            claudeCommand = AgentPrompts.builderLaunchCommand(
                taskName: name,
                branchName: branchName,
                worktreePath: worktreePath,
                specFilePath: specPath,
                specProgress: progress
            )
        } else {
            claudeCommand = AgentPrompts.launchCommand(
                agent: agent ?? .claude,
                taskName: name,
                branchName: branchName,
                worktreePath: worktreePath,
                panelId: panel.id,
                specFilePath: specPath,
                specProgress: progress
            )
        }

        if TmuxSessionManager.isAvailable {
            // Launch inside a new tmux session
            let sessionName = tmuxSession ?? TmuxSessionManager.sessionName(for: tabId)
            print("[TaskState] Creating tmux session: \(sessionName)")

            // Create tmux session and run Claude inside it
            let tmuxCmd = TmuxSessionManager.newSessionCommand(
                name: sessionName, workingDirectory: worktreePath
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                panel.sendCommand(tmuxCmd)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                panel.sendCommand(claudeCommand)
            }

            // Track tmux session on the tab
            if let idx = self.tabs.firstIndex(where: { $0.id == tabId }) {
                self.tabs[idx].tmuxSession = sessionName
            }
        } else {
            // No tmux — launch Claude directly (old behavior)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                panel.sendCommand(claudeCommand)
            }
        }
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        // Kill tmux session when user explicitly closes a tab
        if let tmuxName = tabs[index].tmuxSession {
            TmuxSessionManager.killSession(tmuxName)
        }
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

    /// Restore tabs from saved session state. Returns true if state was restored.
    @discardableResult
    func restoreSessionState() -> Bool {
        guard let snapshot = SessionPersistence.load(from: worktreePath),
              !snapshot.tabs.isEmpty else {
            return false
        }

        for tabSnapshot in snapshot.tabs {
            let panel = TerminalPanel(workingDirectory: worktreePath)
            let tabId = panel.id
            panel.title = tabSnapshot.title

            var tab = TabInfo(id: tabId, title: tabSnapshot.title, isRunning: false)
            tab.claudeSessionId = tabSnapshot.claudeSessionId
            tab.tmuxSession = tabSnapshot.tmuxSession
            if let modeRaw = tabSnapshot.agentMode {
                tab.agentMode = AgentMode(rawValue: modeRaw)
            }

            tabs.append(tab)
            terminals[tabId] = panel

            // tmux reattach (conversation intact) or fresh launch
            launchClaudeInTab(tabId, agent: tab.agentMode, tmuxSession: tabSnapshot.tmuxSession)
        }

        // Restore selected tab by position
        if let activeSnapshot = snapshot.tabs.first(where: { $0.isActive }),
           let index = snapshot.tabs.firstIndex(where: { $0.id == activeSnapshot.id }),
           index < tabs.count {
            selectedTabId = tabs[index].id
        } else {
            selectedTabId = tabs.first?.id
        }

        return true
    }

    func saveSessionState() {
        print("[SessionPersistence] Saving \(tabs.count) tabs to \(worktreePath)")
        var tabSnapshots: [TabSnapshot] = []

        for tab in tabs {
            var scrollbackPath: String?
            var sessionId = tab.claudeSessionId

            if let panel = terminals[tab.id] {
                if let text = panel.readScrollback(), !text.isEmpty {
                    scrollbackPath = try? SessionPersistence.saveScrollback(
                        text, tabId: tab.id, to: worktreePath
                    )
                    // Note: scrollback-based session extraction removed — using filesystem approach below
                }
            }

            // Fallback: scan .claude/projects/ for the most recent session file
            if sessionId == nil {
                sessionId = Self.findLatestClaudeSessionId(worktreePath: worktreePath)
            }

            tabSnapshots.append(TabSnapshot(
                id: tab.id,
                title: tab.title,
                claudeSessionId: sessionId,
                agentMode: tab.agentMode?.rawValue,
                isActive: tab.id == selectedTabId,
                scrollbackPath: scrollbackPath,
                tmuxSession: tab.tmuxSession
            ))
        }

        let session = SessionSnapshot(tabs: tabSnapshots, selectedTabId: selectedTabId)
        do {
            try SessionPersistence.save(session, to: worktreePath)
            print("[SessionPersistence] Saved \(tabSnapshots.count) tabs successfully")
        } catch {
            print("[SessionPersistence] Save failed: \(error)")
        }
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

    /// Extract Claude session ID from terminal scrollback text.
    /// Not used for --resume (that needs the local UUID from .claude/projects/).
    /// Kept as a reference but the filesystem approach is preferred.
    private static func extractSessionIdFromScrollback(from text: String) -> String? {
        guard let range = text.range(of: "session_[A-Za-z0-9]+", options: [.regularExpression, .backwards]) else {
            return nil
        }
        return String(text[range])
    }

    /// Find the most recent Claude session ID by scanning the .claude/projects/ directory.
    /// Claude stores sessions as JSONL files; the session_XXXXX ID is inside.
    private static func findLatestClaudeSessionId(worktreePath: String) -> String? {
        // Claude project dir slug: path with / → -, space → -, dot removed
        // e.g. "/Users/amir/Documents/Cursor Projects/.budahade-worktrees/Ghost/feat-test"
        //    → "-Users-amir-Documents-Cursor-Projects--budahade-worktrees-Ghost-feat-test"
        let projectSlug = worktreePath
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let claudeProjectDir = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".claude/projects/\(projectSlug)")

        let fm = FileManager.default
        guard fm.fileExists(atPath: claudeProjectDir) else { return nil }

        // Find the most recently modified .jsonl file
        guard let files = try? fm.contentsOfDirectory(atPath: claudeProjectDir) else { return nil }
        let jsonlFiles = files.filter { $0.hasSuffix(".jsonl") }
            .compactMap { filename -> (String, Date)? in
                let path = (claudeProjectDir as NSString).appendingPathComponent(filename)
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let modified = attrs[.modificationDate] as? Date else { return nil }
                return (path, modified)
            }
            .sorted { $0.1 > $1.1 }  // Most recent first

        guard let mostRecent = jsonlFiles.first else { return nil }

        // The local session ID is the JSONL filename (UUID) without extension.
        // Claude CLI's --resume expects this UUID, not the API session_XXXXX.
        let filename = ((mostRecent.0 as NSString).lastPathComponent as NSString).deletingPathExtension
        print("[SessionPersistence] Found Claude session: \(filename) from \(mostRecent.0)")
        return filename
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
