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
    @Published var planChats: [UUID: PlanChatState] = [:]
    @Published var planTabs: [PlanTabInfo] = []
    @Published var selectedPlanTabId: UUID?
    let specState = SpecState()
    let buildStatus = BuildStatusState()
    /// Dedicated builder terminal — lives outside the tab bar, shown in spec strip drawer
    @Published var builderPanel: TerminalPanel?
    @Published var isBuilderDrawerOpen: Bool = false
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
        mode = .plan
        // Don't auto-create tab — role selection modal handles it
    }

    func enterBuildMode() {
        mode = .build

        // Launch builder in dedicated panel (not in tab bar)
        if builderPanel == nil && specState.hasSpec {
            launchBuilder()
        }

        // Create a regular CLI tab if none exist
        if tabs.isEmpty {
            createTab()
        } else {
            focusActiveTerminal()
        }

        // Start build status watcher if we have a spec
        if specState.hasSpec && buildStatusWatcher == nil {
            buildStatusWatcher = BuildStatusWatcher(worktreePath: worktreePath, buildStatus: buildStatus)
            buildStatusWatcher?.startWatching()
        }
    }

    // MARK: - Builder Panel

    /// Launch the builder agent in a dedicated terminal panel (outside the tab bar).
    func launchBuilder() {
        let panel = TerminalPanel(workingDirectory: worktreePath)
        builderPanel = panel

        let specPath = specState.activeSpec?.filePath
        let progress: (completed: Int, total: Int)? = specState.activeSpec.map {
            (completed: $0.completedCount, total: $0.totalCount)
        }

        let claudeCommand: String
        if let specPath, let progress {
            claudeCommand = AgentPrompts.builderLaunchCommand(
                taskName: name,
                branchName: branchName,
                worktreePath: worktreePath,
                specFilePath: specPath,
                specProgress: progress
            )
        } else {
            claudeCommand = AgentPrompts.launchCommand(
                agent: .claude,
                taskName: name,
                branchName: branchName,
                worktreePath: worktreePath
            )
        }

        if TmuxSessionManager.isAvailable {
            let sessionName = "builder-\(id.uuidString.prefix(8))"
            let tmuxCmd = TmuxSessionManager.newSessionCommand(
                name: sessionName, workingDirectory: worktreePath
            )
            panel.sendCommandWhenReady(tmuxCmd)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                panel.sendCommandWhenReady(claudeCommand)
            }
            panel.tmuxSession = sessionName
        } else {
            panel.sendCommandWhenReady(claudeCommand)
        }

        isBuilderDrawerOpen = true
    }

    /// Stop the builder and clean up its panel.
    func stopBuilder() {
        if let tmux = builderPanel?.tmuxSession {
            TmuxSessionManager.killSession(tmux)
        }
        builderPanel?.close()
        builderPanel = nil
        isBuilderDrawerOpen = false
    }

    // MARK: - Plan Tab Management

    /// The active plan chat for the selected plan tab
    var activePlanChat: PlanChatState? {
        guard let id = selectedPlanTabId else { return nil }
        return planChats[id]
    }

    @discardableResult
    func createPlanTab(role: AgentMode = .researcher) -> UUID {
        let tabId = UUID()
        let chatState = PlanChatState(
            tabId: tabId,
            worktreePath: worktreePath,
            taskName: name,
            branchName: branchName,
            role: role
        )
        let tab = PlanTabInfo(id: tabId, title: role.displayName, status: .idle, role: role)
        planTabs.append(tab)
        planChats[tabId] = chatState
        selectedPlanTabId = tabId

        // Observe session status to update tab indicators
        observePlanChatStatus(chatState, tabId: tabId)

        return tabId
    }

    func closePlanTab(_ id: UUID) {
        guard let index = planTabs.firstIndex(where: { $0.id == id }) else { return }

        planChats[id]?.cancel()
        planChats.removeValue(forKey: id)
        planTabs.remove(at: index)

        if selectedPlanTabId == id {
            if !planTabs.isEmpty {
                selectedPlanTabId = planTabs[min(index, planTabs.count - 1)].id
            } else {
                selectedPlanTabId = nil
            }
        }

        // If last tab closed, leave empty — role selection modal will appear in WorkspaceView
    }

    func selectPlanTab(_ id: UUID) {
        guard planTabs.contains(where: { $0.id == id }) else { return }
        selectedPlanTabId = id
        // Clear "done" status when user selects the tab
        if let index = planTabs.firstIndex(where: { $0.id == id }),
           planTabs[index].status == .done {
            planTabs[index].status = .idle
        }
    }

    /// Routes the last assistant message from sourceTab to targetTab as handed-off context.
    func handOff(from sourceTabId: UUID, to targetTabId: UUID) {
        guard let sourceChat = planChats[sourceTabId],
              let targetChat = planChats[targetTabId],
              let sourceSession = sourceChat.plannerSession,
              let lastAssistant = sourceSession.messages.last(where: { $0.role == .assistant }) else { return }
        targetChat.receiveHandOff(from: sourceChat.role, content: lastAssistant.content)
        // Switch to the target tab so the user sees the result
        selectPlanTab(targetTabId)
    }

    func selectPlanTabByIndex(_ index: Int) {
        guard !planTabs.isEmpty else { return }
        if index == 9 {
            selectedPlanTabId = planTabs.last?.id
        } else {
            let zeroIndex = index - 1
            guard zeroIndex >= 0, zeroIndex < planTabs.count else { return }
            selectedPlanTabId = planTabs[zeroIndex].id
        }
    }

    private func observePlanChatStatus(_ chatState: PlanChatState, tabId: UUID) {
        chatState.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self,
                      let idx = self.planTabs.firstIndex(where: { $0.id == tabId }),
                      let session = chatState.plannerSession else { return }
                let newStatus: PlanTabStatus
                switch session.status {
                case .idle:         newStatus = .idle
                case .connecting:   newStatus = .connecting
                case .streaming:    newStatus = .streaming
                case .done:         newStatus = .done
                case .error:        newStatus = .idle
                }
                if self.planTabs[idx].status != newStatus {
                    self.planTabs[idx].status = newStatus
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Tab Management

    @discardableResult
    func createTab(launchAgent: Bool = false, agent: AgentMode? = nil) -> UUID {
        let panel = TerminalPanel(workingDirectory: worktreePath)
        let id = panel.id
        var tab = TabInfo(id: id, title: "Claude", isRunning: false)
        tab.restoredTitle = "Claude"  // Protect from shell/path title overwrites
        tab.agentMode = agent
        tabs.append(tab)
        terminals[id] = panel
        selectedTabId = id
        // Focus the new tab — deferred so SwiftUI has time to render the view first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.terminals[id]?.focus()
        }

        if launchAgent {
            launchClaudeInTab(id, agent: agent)
        } else if TmuxSessionManager.isAvailable {
            // Wrap even bare shell tabs in tmux for persistence
            let sessionName = TmuxSessionManager.sessionName(for: id)
            let tmuxCmd = TmuxSessionManager.newSessionCommand(
                name: sessionName, workingDirectory: worktreePath
            )
            panel.sendCommandWhenReady(tmuxCmd)
            if let idx = tabs.firstIndex(where: { $0.id == id }) {
                tabs[idx].tmuxSession = sessionName
            }
            panel.tmuxSession = sessionName
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
            panel.sendCommandWhenReady(TmuxSessionManager.attachCommand(name: sessionName))
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
            // Launch inside a new tmux session, then run Claude inside it
            let sessionName = tmuxSession ?? TmuxSessionManager.sessionName(for: tabId)
            print("[TaskState] Creating tmux session: \(sessionName)")

            let tmuxCmd = TmuxSessionManager.newSessionCommand(
                name: sessionName, workingDirectory: worktreePath
            )
            // Wait for surface, send tmux, then send Claude after tmux starts
            panel.sendCommandWhenReady(tmuxCmd)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                panel.sendCommandWhenReady(claudeCommand)
            }

            // Track tmux session on the tab and panel
            if let idx = self.tabs.firstIndex(where: { $0.id == tabId }) {
                self.tabs[idx].tmuxSession = sessionName
            }
            terminals[tabId]?.tmuxSession = sessionName
        } else {
            // No tmux — launch Claude directly
            panel.sendCommandWhenReady(claudeCommand)
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
        // Make terminal first responder so keyboard events (paste, Shift+Enter) go to the right tab
        terminals[id]?.focus()
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
        stopBuilder()
        for panel in terminals.values {
            panel.close()
        }
        terminals.removeAll()
        tabs.removeAll()
        selectedTabId = nil
        specWatcher?.stopWatching()
        buildStatusWatcher?.stopWatching()
        for (_, chat) in planChats { chat.cancel() }
        planChats.removeAll()
        planTabs.removeAll()
        selectedPlanTabId = nil
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
            tab.restoredTitle = tabSnapshot.title  // Protect from shell title overwrites
            if let modeRaw = tabSnapshot.agentMode {
                tab.agentMode = AgentMode(rawValue: modeRaw)
            }

            panel.tmuxSession = tabSnapshot.tmuxSession
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

        // Focus the restored active tab after SwiftUI renders all the terminal views
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.focusActiveTerminal()
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

                // If we have a restored title, don't let shell/path titles overwrite it.
                // Only accept titles from Claude (contain "Claude" or spinner indicators).
                if let restoredTitle = self.tabs[index].restoredTitle {
                    let isClaude = title.contains("Claude") ||
                        title.unicodeScalars.contains { $0.value >= 0x2800 && $0.value <= 0x28FF } ||
                        title.contains("✳")
                    if isClaude {
                        // Claude set a real title — accept it and clear the restored flag
                        self.tabs[index].title = title
                        self.tabs[index].restoredTitle = nil
                    }
                    // Otherwise keep the restored title (ignore shell/path/tmux titles)
                } else {
                    self.tabs[index].title = title
                }
                let newStatus = Self.parseAgentStatus(from: title)
                print("[AgentStatus] title=\"\(title)\" → \(newStatus)")
                let oldStatus = self.previousStatuses[surfaceId] ?? .inactive
                self.previousStatuses[surfaceId] = newStatus

                // Mark tab as having had activity once Claude runs
                if newStatus == .working || newStatus == .thinking {
                    self.tabs[index].hadActivity = true
                }

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
