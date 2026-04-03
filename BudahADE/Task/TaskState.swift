import Foundation
import Combine
import AppKit

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
    /// Split pane: when set, the content area shows two panes
    @Published var splitPane: SplitPaneState?
    /// Which pane is focused (for keyboard nav and visual indicator)
    @Published var focusedPane: PanePosition = .primary
    @Published var terminals: [UUID: TerminalPanel] = [:]
    @Published var browserPanels: [UUID: BrowserPanel] = [:]
    @Published var planChats: [UUID: PlanChatState] = [:]
    @Published var planTabs: [PlanTabInfo] = []
    @Published var selectedPlanTabId: UUID?
    @Published var archivedPlanTabs: [ArchivedPlanTab] = []
    @Published var showPlanArchive: Bool = false
    let specState = SpecState()
    let buildStatus = BuildStatusState()
    /// Dev server for this task (lazy — created on first browser tab)
    @Published var devServerManager: DevServerManager?
    var assignedPort: Int?
    /// Dedicated builder terminal — lives outside the tab bar, shown in spec strip drawer
    @Published var builderPanel: TerminalPanel?
    @Published var isBuilderDrawerOpen: Bool = false
    /// Builder GUI session — replaces raw terminal builder
    @Published var builderSession: BuilderSession?
    @Published var showBuilderChat: Bool = false
    @Published var builderAgent: BuilderAgent?
    private var specWatcher: SpecWatcher?
    private var buildStatusWatcher: BuildStatusWatcher?
    private var smartReloader: SmartReloader?
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
        startTmuxTitlePolling()
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
        print("[enterBuildMode] Starting — builderSession: \(builderSession != nil), hasSpec: \(specState.hasSpec)")
        mode = .build

        // Synchronous spec discovery — ensures we detect spec files that were
        // just written (e.g. via NewTaskSheet import) before the watcher polls.
        if !specState.hasSpec {
            let specFiles = SpecParser.findSpecFiles(in: worktreePath)
            if !specFiles.isEmpty {
                let results = specFiles.compactMap { SpecParser.parse(fileAt: $0) }
                specState.updateAll(from: results)
            }
        }

        // Create GUI builder session when a spec exists but no builder yet
        if builderSession == nil && specState.hasSpec {
            let specPath = specState.activeSpec?.filePath
                ?? (worktreePath as NSString).appendingPathComponent(".budahade/spec.md")
            if let spec = SpecParser.parse(fileAt: specPath) {
                createBuilderSession(from: spec)
            } else {
                // Fallback: create builder with single step
                let section = SpecSection(
                    id: "build", title: "Build", level: 2,
                    content: "", tasks: [SpecTask(id: 0, title: "Implement spec", isCompleted: false, sectionId: "build")],
                    lineRange: 0..<1
                )
                let fallback = SpecParseResult(
                    title: "Build", sections: [section],
                    rawContent: "", filePath: specPath
                )
                createBuilderSession(from: fallback)
            }
        }

        // Only create terminal tabs when NOT using the GUI builder
        if builderSession == nil {
            if tabs.isEmpty {
                createTab()
            } else {
                focusActiveTerminal()
            }
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

    /// Create builder session from a parsed spec (no tab — builder lives below the tab bar)
    func createBuilderSession(from spec: SpecParseResult, contextSummary: String = "") {
        let session = BuilderSession.from(spec: spec, contextSummary: contextSummary)
        builderSession = session

        // Create the builder agent coordinator
        let chatManager = CLISubprocessManager()
        let agent = BuilderAgent(builderSession: session, chatManager: chatManager)
        builderAgent = agent

        // Show the builder chat
        showBuilderChat = true
    }

    func closePlanTab(_ id: UUID) {
        guard let index = planTabs.firstIndex(where: { $0.id == id }) else { return }

        let tab = planTabs[index]

        // Archive the conversation if it had messages
        if let chatState = planChats[id] {
            let messageCount = chatState.plannerSession?.messages.count ?? 0
            if messageCount > 0 {
                let lastMessage = chatState.plannerSession?.messages.last
                let preview = lastMessage?.content.prefix(120).trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let archived = ArchivedPlanTab(
                    title: tab.title,
                    role: tab.role,
                    messageCount: messageCount,
                    preview: String(preview),
                    archivedAt: Date()
                )
                archivedPlanTabs.insert(archived, at: 0)
            }
            chatState.cancel()
        }

        planChats.removeValue(forKey: id)
        planTabs.remove(at: index)

        if selectedPlanTabId == id {
            if !planTabs.isEmpty {
                selectedPlanTabId = planTabs[min(index, planTabs.count - 1)].id
            } else {
                selectedPlanTabId = nil
            }
        }
    }

    func selectPlanTab(_ id: UUID) {
        guard planTabs.contains(where: { $0.id == id }) else { return }
        selectedPlanTabId = id
        // Clear "done" status when user selects the tab
        if let index = planTabs.firstIndex(where: { $0.id == id }),
           planTabs[index].status == .done {
            planTabs[index].status = .idle
        }
        // Request focus on the plan chat input
        NotificationCenter.default.post(name: .focusInput, object: nil)
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

    @discardableResult
    func createBrowserTab(url: URL? = nil) -> UUID {
        // Lazy dev server start: detect project and start server on first browser tab
        let resolvedURL: URL?
        if let url {
            resolvedURL = url
        } else {
            resolvedURL = startDevServerIfNeeded()
        }

        let panel = BrowserPanel(url: resolvedURL)
        let id = panel.id
        let tab = TabInfo(
            id: id,
            title: panel.state.title ?? "Browser",
            isRunning: false,
            tabType: .browser(url: resolvedURL)
        )
        tabs.append(tab)
        browserPanels[id] = panel
        selectedTabId = id

        // Wire SmartReloader to reload this panel's web view
        if let reloader = smartReloader {
            reloader.onReloadNeeded = { [weak panel] in panel?.state.reload() }
        }

        // Register with API server (starts server lazily on first registration)
        BrowserHTTPServer.shared.registerTask(id: id, state: panel.state)

        // Wire element picker → inject context into active terminal
        panel.state.elementPicker.onElementPicked = { [weak self] context in
            self?.injectElementContext(context)
        }

        // Sync browser page title → tab title
        observeBrowserTitle(id: id, state: panel.state)

        return id
    }

    /// Saves screenshot to .budahade/ and injects the context block into the active terminal
    /// as pending input (no Enter — user appends their instruction before submitting).
    func injectElementContext(_ context: ElementContext) {
        // Save screenshot PNG if present
        var finalContext = context
        if let image = context.screenshot, let filename = context.screenshotPath {
            let dir = (worktreePath as NSString).appendingPathComponent(".budahade")
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let path = (dir as NSString).appendingPathComponent(filename)
            if let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
                finalContext.screenshotPath = filename   // confirmed written
            } else {
                finalContext.screenshotPath = nil       // failed — omit from block
            }
        }

        let block = finalContext.terminalBlock()

        // Find the active terminal (skip browser tabs)
        let terminalTabId = tabs.first(where: { $0.isTerminal && $0.id == selectedTabId })?.id
            ?? tabs.first(where: { $0.isTerminal })?.id
        guard let tabId = terminalTabId, let panel = terminals[tabId] else { return }

        // Inject as pending input — no Enter, so user can append their instruction
        if let session = panel.tmuxSession {
            TmuxSessionManager.sendKeys(session: session, keys: block, literal: true)
        } else {
            panel.sendText(block)
        }
    }

    private func observeBrowserTitle(id: UUID, state: BrowserState) {
        Task { @MainActor [weak self] in
            while self?.browserPanels[id] != nil {
                let title = state.title
                withObservationTracking {
                    _ = state.title
                } onChange: {
                    Task { @MainActor [weak self] in
                        guard let self,
                              let idx = self.tabs.firstIndex(where: { $0.id == id }),
                              let newTitle = state.title, !newTitle.isEmpty else { return }
                        self.tabs[idx].title = newTitle
                    }
                }
                // Yield to avoid tight loop — onChange fires asynchronously
                try? await Task.sleep(for: .milliseconds(100))
                _ = title  // suppress unused warning
            }
        }
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index]

        if tab.isTerminal {
            // Kill tmux session when user explicitly closes a tab
            if let tmuxName = tab.tmuxSession {
                TmuxSessionManager.killSession(tmuxName)
            }
            terminals[id]?.close()
            terminals.removeValue(forKey: id)
        } else if tab.isBrowser {
            browserPanels.removeValue(forKey: id)
            BrowserHTTPServer.shared.unregisterTask(id: id)
        }

        // Update split pane ownership when a tab is closed
        if var split = splitPane {
            if split.secondaryTabIds.contains(id) {
                split.secondaryTabIds.removeAll { $0 == id }
                if split.secondaryTabIds.isEmpty {
                    splitPane = nil  // secondary is now empty — collapse split
                } else {
                    if split.secondarySelectedId == id {
                        split.secondarySelectedId = split.secondaryTabIds.last
                    }
                    splitPane = split
                }
            } else if selectedTabId == id {
                // Closing a primary tab — collapse split if primary becomes empty
                let remaining = tabs.filter { t in t.id != id && !split.secondaryTabIds.contains(t.id) }
                if remaining.isEmpty { splitPane = nil }
            }
        }

        tabs.remove(at: index)

        if selectedTabId == id {
            let secondaryIds = Set(splitPane?.secondaryTabIds ?? [])
            let remaining = tabs.filter { !secondaryIds.contains($0.id) }
            selectedTabId = remaining.isEmpty ? tabs.first?.id : remaining[min(max(index - 1, 0), remaining.count - 1)].id
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
        if tabs[index].isTerminal {
            terminals[id]?.focus()
            // Request focus on input (for consistency across tab types)
            NotificationCenter.default.post(name: .focusInput, object: nil)
        }
    }

    // MARK: - Split Pane

    /// Tabs currently in the primary (left/top) pane.
    var primaryTabs: [TabInfo] {
        guard let split = splitPane else { return tabs }
        let secondaryIds = Set(split.secondaryTabIds)
        return tabs.filter { !secondaryIds.contains($0.id) }
    }

    /// Tabs currently in the secondary (right/bottom) pane.
    var secondaryTabs: [TabInfo] {
        guard let split = splitPane else { return [] }
        let secondaryIds = Set(split.secondaryTabIds)
        return tabs.filter { secondaryIds.contains($0.id) }
    }

    func reorderTab(_ tabId: UUID, toIndex newIndex: Int) {
        guard splitPane == nil else {
            // Split mode: figure out which pane and reorder within that subset
            let isSecondary = splitPane?.secondaryTabIds.contains(tabId) ?? false
            var paneTabs = isSecondary ? secondaryTabs : primaryTabs
            guard let oldIndex = paneTabs.firstIndex(where: { $0.id == tabId }) else { return }
            let clamped = min(max(newIndex, 0), paneTabs.count)
            guard oldIndex != clamped else { return }
            let tab = paneTabs.remove(at: oldIndex)
            let insertAt = clamped > oldIndex ? clamped - 1 : clamped
            paneTabs.insert(tab, at: min(insertAt, paneTabs.count))
            // Rebuild full array: replace pane tabs in their new order
            let paneIds = Set(paneTabs.map(\.id))
            var rebuilt: [TabInfo] = []
            var pi = 0
            for t in tabs {
                if paneIds.contains(t.id) {
                    rebuilt.append(paneTabs[pi])
                    pi += 1
                } else {
                    rebuilt.append(t)
                }
            }
            tabs = rebuilt
            return
        }
        // Unsplit mode: simple array reorder
        guard let oldIndex = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        guard oldIndex != newIndex, newIndex >= 0, newIndex <= tabs.count else { return }
        let tab = tabs.remove(at: oldIndex)
        let insertAt = newIndex > oldIndex ? newIndex - 1 : newIndex
        tabs.insert(tab, at: min(insertAt, tabs.count))
    }

    func splitTab(_ tabId: UUID, to zone: DropZone) {
        guard tabs.contains(where: { $0.id == tabId }) else { return }
        if zone.isFirst {
            // Dragged tab → primary (left/top). Pick the previously-selected tab for secondary.
            let secId = selectedTabId != tabId ? selectedTabId : tabs.first(where: { $0.id != tabId })?.id
            guard let secId else { return }
            splitPane = SplitPaneState(
                secondaryTabIds: [secId],
                secondarySelectedId: secId,
                orientation: zone.orientation
            )
            selectedTabId = tabId
        } else {
            // Dragged tab → secondary (right/bottom). Primary keeps the current selection.
            if selectedTabId == tabId {
                selectedTabId = tabs.first(where: { $0.id != tabId })?.id
            }
            splitPane = SplitPaneState(
                secondaryTabIds: [tabId],
                secondarySelectedId: tabId,
                orientation: zone.orientation
            )
        }
    }

    func selectSecondaryTab(_ id: UUID) {
        guard let split = splitPane, split.secondaryTabIds.contains(id) else { return }
        splitPane?.secondarySelectedId = id
        focusedPane = .secondary
        if let index = tabs.firstIndex(where: { $0.id == id }) {
            if tabs[index].agentStatus == .completed { tabs[index].agentStatus = .inactive }
            if tabs[index].isTerminal {
                terminals[id]?.focus()
                // Request focus on input
                NotificationCenter.default.post(name: .focusInput, object: nil)
            }
        }
    }

    /// Move a tab from one pane to the other. Collapses split if secondary becomes empty.
    func moveTab(_ tabId: UUID, to pane: PanePosition) {
        guard var split = splitPane else { return }
        let isInSecondary = split.secondaryTabIds.contains(tabId)
        guard let tab = tabs.first(where: { $0.id == tabId }) else { return }

        switch pane {
        case .secondary:
            guard !isInSecondary else { return }
            split.secondaryTabIds.append(tabId)
            split.secondarySelectedId = tabId
            if selectedTabId == tabId {
                let remaining = tabs.filter { t in
                    t.id != tabId && !split.secondaryTabIds.contains(t.id)
                }
                selectedTabId = remaining.first?.id
            }
            splitPane = split
            focusedPane = .secondary
            // Focus the terminal in the target pane
            if tab.isTerminal {
                terminals[tabId]?.focus()
            }

        case .primary:
            guard isInSecondary else { return }
            split.secondaryTabIds.removeAll { $0 == tabId }
            if split.secondarySelectedId == tabId {
                split.secondarySelectedId = split.secondaryTabIds.last
            }
            if split.secondaryTabIds.isEmpty {
                splitPane = nil
            } else {
                splitPane = split
            }
            selectedTabId = tabId
            focusedPane = .primary
            // Focus the terminal in the target pane
            if tab.isTerminal {
                terminals[tabId]?.focus()
            }
        }
    }

    /// Create a new terminal tab assigned to the secondary pane.
    @discardableResult
    func createTabInSecondaryPane() -> UUID {
        guard splitPane != nil else { return createTab() }
        let prevSelected = selectedTabId
        let id = createTab()
        selectedTabId = prevSelected   // keep primary selection unchanged
        splitPane?.secondaryTabIds.append(id)
        splitPane?.secondarySelectedId = id
        return id
    }

    /// Create a new browser tab assigned to the secondary pane.
    @discardableResult
    func createBrowserTabInSecondaryPane() -> UUID {
        guard splitPane != nil else { return createBrowserTab() }
        let prevSelected = selectedTabId
        let id = createBrowserTab()
        selectedTabId = prevSelected   // keep primary selection unchanged
        splitPane?.secondaryTabIds.append(id)
        splitPane?.secondarySelectedId = id
        return id
    }

    func closeSplit() {
        // Secondary tabs return to the primary pool — they're already in task.tabs, just clear split.
        splitPane = nil
        focusedPane = .primary
    }

    func focusPane(arrow: PaneArrow) {
        guard let split = splitPane else { return }
        let newFocus: PanePosition?
        switch (split.orientation, arrow) {
        case (.horizontal, .left):  newFocus = .primary
        case (.horizontal, .right): newFocus = .secondary
        case (.vertical, .up):      newFocus = .primary
        case (.vertical, .down):    newFocus = .secondary
        default:                    newFocus = nil   // wrong axis — no-op
        }
        guard let newFocus else { return }
        focusedPane = newFocus
        let tabId = focusedPane == .primary ? selectedTabId : splitPane?.secondarySelectedId
        if let tabId, let idx = tabs.firstIndex(where: { $0.id == tabId }), tabs[idx].isTerminal {
            terminals[tabId]?.focus()
        }
    }

    // MARK: - Dev Server

    /// Detect project type and start dev server if applicable. Returns localhost URL or nil.
    private func startDevServerIfNeeded() -> URL? {
        // Don't start a second server if one is already running
        if let manager = devServerManager, manager.isRunning {
            return manager.detectedURL ?? URL(string: "http://localhost:\(manager.port)")
        }

        guard let config = DevServerDetector.detect(in: worktreePath) else { return nil }

        // TODO: Use WorkspaceState.projectIndex for port windowing
        guard let port = PortAllocator.shared.allocate(projectIndex: 0) else { return nil }

        assignedPort = port
        let manager = DevServerManager(config: config, port: port, worktreePath: worktreePath)
        devServerManager = manager

        let reloader = SmartReloader()
        smartReloader = reloader
        manager.onStdoutChunk = { [weak reloader] chunk in reloader?.handleStdoutChunk(chunk) }
        reloader.startWatching(worktreePath: worktreePath)

        manager.start()

        return URL(string: "http://localhost:\(port)")
    }

    func stopDevServer() {
        devServerManager?.stop()
        smartReloader?.stopWatching()
        if let port = assignedPort {
            PortAllocator.shared.release(port: port)
        }
        assignedPort = nil
        devServerManager = nil
        smartReloader = nil
    }

    func selectTabByIndex(_ index: Int) {
        // In split mode, cycle within the focused pane's tabs only
        let targetTabs: [TabInfo]
        let inSecondary = splitPane != nil && focusedPane == .secondary
        if splitPane != nil {
            targetTabs = inSecondary ? secondaryTabs : primaryTabs
        } else {
            targetTabs = tabs
        }

        guard !targetTabs.isEmpty else { return }
        let targetId: UUID?
        if index == 9 {
            targetId = targetTabs.last?.id
        } else {
            let zeroIndex = index - 1
            guard zeroIndex >= 0, zeroIndex < targetTabs.count else { return }
            targetId = targetTabs[zeroIndex].id
        }
        guard let id = targetId else { return }
        if inSecondary {
            selectSecondaryTab(id)
        } else {
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
        stopDevServer()
        for panel in terminals.values {
            panel.close()
        }
        terminals.removeAll()
        browserPanels.removeAll()
        splitPane = nil
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
            if tabSnapshot.isBrowser == true {
                // Restore browser tab
                let url = tabSnapshot.browserURL.flatMap(URL.init(string:))
                let panel = BrowserPanel(url: url)
                let tabId = panel.id
                let tab = TabInfo(
                    id: tabId,
                    title: tabSnapshot.title,
                    isRunning: false,
                    tabType: .browser(url: url)
                )
                tabs.append(tab)
                browserPanels[tabId] = panel
                observeBrowserTitle(id: tabId, state: panel.state)
            } else {
                // Restore terminal tab
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
                sessionId = SessionIdResolver.findLatest(worktreePath: worktreePath)
            }

            tabSnapshots.append(TabSnapshot(
                id: tab.id,
                title: tab.title,
                claudeSessionId: sessionId,
                agentMode: tab.agentMode?.rawValue,
                isActive: tab.id == selectedTabId,
                scrollbackPath: scrollbackPath,
                tmuxSession: tab.tmuxSession,
                isBrowser: tab.isBrowser ? true : nil,
                browserURL: browserPanels[tab.id]?.state.lastURL?.absoluteString
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
                // Only accept titles from Claude (spinner or "Claude" keyword).
                if self.tabs[index].restoredTitle != nil {
                    if Self.parseAgentStatus(from: title) != .inactive {
                        // Claude set a real title — accept it and clear the restored flag
                        self.tabs[index].title = title
                        self.tabs[index].restoredTitle = nil
                    }
                    // Otherwise keep the restored title (ignore shell/path/tmux titles)
                } else {
                    self.tabs[index].title = title
                }
                let newStatus = Self.parseAgentStatus(from: title)
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

    /// Poll tmux pane titles every ~1s. Ghostty's embedded library doesn't fire
    /// SET_TITLE through the action callback, so we read directly from tmux.
    private func startTmuxTitlePolling() {
        guard TmuxSessionManager.isAvailable else { return }
        Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                for tab in self.tabs {
                    guard let tmuxSession = tab.tmuxSession else { continue }
                    let title = await Task.detached(priority: .utility) {
                        TmuxSessionManager.paneTitle(session: tmuxSession)
                    }.value
                    guard let title, !title.isEmpty else { continue }
                    self.handleTitleUpdate(tabId: tab.id, title: title)
                }
            }
        }
    }

    /// Process a title update (shared by both Ghostty callback and tmux polling).
    private func handleTitleUpdate(tabId: UUID, title: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }

        if tabs[index].restoredTitle != nil {
            if Self.parseAgentStatus(from: title) != .inactive {
                tabs[index].title = title
                tabs[index].restoredTitle = nil
            }
        } else {
            tabs[index].title = title
        }
        let newStatus = Self.parseAgentStatus(from: title)
        let oldStatus = previousStatuses[tabId] ?? .inactive
        previousStatuses[tabId] = newStatus

        if newStatus == .working || newStatus == .thinking {
            tabs[index].hadActivity = true
        }

        if (oldStatus == .working || oldStatus == .thinking) && newStatus == .inactive {
            tabs[index].agentStatus = .completed
        } else if tabs[index].agentStatus == .completed && newStatus == .inactive {
            // Stay completed
        } else {
            tabs[index].agentStatus = newStatus
        }
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
