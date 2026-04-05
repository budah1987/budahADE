import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var state: WorkspaceState

    /// Rename palette state
    @State private var renameTarget: RenameTarget? = nil
    @State private var renameText: String = ""
    @FocusState private var renameFieldFocused: Bool

    /// Tab close confirmation
    @State private var tabCloseRequest: TabCloseRequest? = nil
    @State private var showCloseConfirmation: Bool = false

    /// Role selection modal (shown as sheet when adding new plan tab)
    @State private var showRoleModal: Bool = false

    /// Plan → Build transition overlay
    @State private var buildTransition: BuildTransitionState? = nil

    /// True while a tab drag session is in progress — gates the inter-pane drop overlay
    @State private var isTabDragging = false

    /// Drop highlight for inter-pane content area drops
    @State private var primaryContentDropTargeted = false
    @State private var secondaryContentDropTargeted = false


    var body: some View {
        coreView
            .onReceive(NotificationCenter.default.publisher(for: .selectTabByIndex)) { notification in
                guard !appState.isWorkspaceSwitcherOpen,
                      let index = notification.userInfo?["index"] as? Int else { return }
                if let task = state.activeTask, task.mode == .plan {
                    task.selectPlanTabByIndex(index)
                } else {
                    state.activeTask?.selectTabByIndex(index)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .newTask)) { _ in
                state.showNewTaskSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .selectTaskByIndex)) { notification in
                guard let index = notification.userInfo?["index"] as? Int else { return }
                state.selectTaskByIndex(index)
            }
            .onReceive(NotificationCenter.default.publisher(for: .renameTab)) { _ in
                guard let task = state.activeTask else { return }
                let tabId: UUID?
                if task.focusedPane == .secondary, let split = task.splitPane {
                    tabId = split.secondarySelectedId
                } else {
                    tabId = task.selectedTabId
                }
                guard let tabId, let tab = task.tabs.first(where: { $0.id == tabId }) else { return }
                renameText = tab.title
                renameTarget = .tab(taskId: task.id, tabId: tabId)
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleTaskMode)) { _ in
                if let task = state.activeTask {
                    if task.mode == .plan { task.enterBuildMode() }
                    else { task.enterPlanMode() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .renameTask)) { _ in
                guard let task = state.activeTask else { return }
                renameText = task.name
                renameTarget = .task(taskId: task.id)
            }
            .onChange(of: renameTarget) { _, newValue in
                if newValue != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        renameFieldFocused = true
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .tabDragBegan)) { _ in
                isTabDragging = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .tabDragEnded)) { _ in
                isTabDragging = false
            }
    }

    private var coreView: some View {
        ZStack {
            // Unified app chrome background
            Theme.Colors.sidebarBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── APP BAR (full width: dropdown + resource meter) ──
                AppBar(workspace: state)
                    .zIndex(50)

                // ── BODY: sidebar + content ──
                HStack(spacing: 0) {
                    // ── TASK RAIL ──
                    TaskRailView(workspace: state, renameTarget: renameTarget)
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(Theme.Colors.borderSubtle).frame(width: 1)
                        }

                    // ── CONTENT ZONE ──
                    VStack(spacing: 0) {
                    // Content
                    if let task = state.activeTask, task.mode == .plan {
                        // Plan mode: tabs on chrome, chat in dark inset
                        VStack(spacing: 0) {
                            if task.planTabs.isEmpty {
                                RoleSelectionModal { role in
                                    task.createPlanTab(role: role)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                // Plan: tabs on chrome, chat in dark inset
                                PlanTabBar(
                                    selectedTabID: Binding(
                                        get: { task.selectedPlanTabId ?? UUID() },
                                        set: { task.selectPlanTab($0) }
                                    ),
                                    tabs: task.planTabs,
                                    onSelectTab: { task.selectPlanTab($0) },
                                    onCloseTab: { requestCloseTab(.plan($0)) },
                                    onNewTab: { showRoleModal = true }
                                )
                                .padding(.horizontal, Theme.Spacing.lg)

                                Group {
                                    if let planChat = task.activePlanChat,
                                       let selectedId = task.selectedPlanTabId {
                                        PlanChatView(
                                            state: planChat,
                                            siblingTabs: task.planTabs.filter { $0.id != selectedId },
                                            onHandOff: { targetId in
                                                task.handOff(from: selectedId, to: targetId)
                                            },
                                            onCreateAndHandOff: { role in
                                                let newTabId = task.createPlanTab(role: role)
                                                task.handOff(from: selectedId, to: newTabId)
                                            },
                                            onApproveToBuild: { itemCount in
                                                startBuildTransition(task: task, itemCount: itemCount)
                                            }
                                        )
                                        .id(task.selectedPlanTabId)
                                    }
                                }
                                .background(Theme.Colors.appBackground)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                                .padding(.top, Theme.Spacing.sm)
                                .padding(.bottom, Theme.Spacing.lg)
                                .padding(.horizontal, Theme.Spacing.lg)
                            }
                        }
                        .sheet(isPresented: $showRoleModal) {
                            RoleSelectionModal { role in
                                task.createPlanTab(role: role)
                                showRoleModal = false
                            }
                        }
                    } else {
                        // Build mode: file tree + tabs (chrome) + agent content (dark inset) + git panel
                        HStack(spacing: 0) {
                            LeftPanelView(
                                state: state,
                                worktreePath: state.activeTask?.repoPath ?? state.projectPath
                            )
                            .frame(width: state.leftPanelVisible ? nil : 0)
                            .clipped()
                            .allowsHitTesting(state.leftPanelVisible)

                            // Tabs on chrome, agent content in dark rounded inset
                            VStack(spacing: 0) {
                                buildModeTabBar
                                    .padding(.horizontal, Theme.Spacing.lg)

                                agentContentArea
                                    .background(Theme.Colors.appBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                                    .padding(.top, Theme.Spacing.sm)
                                    .padding(.bottom, Theme.Spacing.lg)
                                    .padding(.horizontal, Theme.Spacing.lg)
                            }

                            if state.rightPanelVisible, let task = state.activeTask {
                                GitSidebarView(task: task, projectPath: state.projectPath)
                                    .id(state.activeTaskId)
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                            }
                        }
                    }
                }
                } // end HStack (body)
            } // end VStack (appbar + body)
            .blur(radius: renameTarget != nil ? 2 : 0)
            .animation(.easeOut(duration: 0.15), value: renameTarget != nil)

            // ── RENAME PALETTE ──
            if renameTarget != nil {
                renamePalette
            }

            // ── BUILD TRANSITION OVERLAY ──
            if let transition = buildTransition {
                BuildTransitionOverlay(state: transition)
            }
        }
        .coordinateSpace(name: "workspace")
        .animation(.easeInOut(duration: 0.2), value: state.leftPanelVisible)
        .animation(.easeInOut(duration: 0.2), value: state.rightPanelVisible)
        .animation(.easeOut(duration: 0.15), value: renameTarget != nil)
        .sheet(isPresented: $state.showNewTaskSheet) {
            NewTaskSheet(workspace: state)
                .background(Theme.Colors.appBackground)
        }
        .alert("Close conversation?", isPresented: $showCloseConfirmation) {
            Button("Cancel", role: .cancel) {
                tabCloseRequest = nil
            }
            Button("Close") {
                if let request = tabCloseRequest {
                    performCloseTab(request)
                }
                tabCloseRequest = nil
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text("This conversation has messages that will be lost.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleLeftPanel)) { _ in
            state.leftPanelVisible.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleRightPanel)) { _ in
            state.rightPanelVisible.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTerminalTab)) { _ in
            if let task = state.activeTask {
                if task.mode == .plan {
                    showRoleModal = true
                } else if task.focusedPane == .secondary && task.splitPane != nil {
                    task.createTabInSecondaryPane()
                } else {
                    task.createTab()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleBrowser)) { _ in
            if let task = state.activeTask, task.mode == .build {
                if task.focusedPane == .secondary && task.splitPane != nil {
                    task.createBrowserTabInSecondaryPane()
                } else {
                    task.createBrowserTab()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusLeftPane)) { _ in
            state.activeTask?.focusPane(arrow: .left)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusRightPane)) { _ in
            state.activeTask?.focusPane(arrow: .right)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusTopPane)) { _ in
            state.activeTask?.focusPane(arrow: .up)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusBottomPane)) { _ in
            state.activeTask?.focusPane(arrow: .down)
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeSplit)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                state.activeTask?.closeSplit()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeTerminalTab)) { _ in
            if let task = state.activeTask {
                if task.mode == .plan {
                    if let id = task.selectedPlanTabId {
                        requestCloseTab(.plan(id))
                    }
                } else {
                    let tabId: UUID?
                    if task.focusedPane == .secondary, let split = task.splitPane {
                        tabId = split.secondarySelectedId
                    } else {
                        tabId = task.selectedTabId
                    }
                    if let id = tabId {
                        requestCloseTab(.build(id))
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeTask)) { _ in
            if let task = state.activeTask {
                state.deleteTask(task.id)
            }
        }
    }

    // MARK: - Build Transition

    // MARK: - Builder Agent Launch

    private func launchBuilderAgent(task: TaskState) {
        guard let agent = task.builderAgent, let session = task.builderSession else { return }

        let specPath = task.specState.activeSpec?.filePath
            ?? (task.worktreePath as NSString).appendingPathComponent(".budahade/spec.md")

        agent.launch(
            worktreePath: task.worktreePath,
            specFilePath: specPath,
            specProgress: (completed: session.completedCount, total: session.totalCount),
            taskName: task.name,
            branchName: task.branchName
        )
    }

    private func startBuildTransition(task: TaskState, itemCount: Int) {
        print("[BuildTransition] Starting — \(itemCount) items, worktree: \(task.worktreePath)")
        let transition = BuildTransitionState()
        buildTransition = transition

        // Step 1: Writing spec.md… (already done by handleApprove)
        transition.step = .writingSpec

        // Generate context summary from the active plan conversation
        let contextSummary = task.activePlanChat?.generateContextSummary() ?? ""

        Task { @MainActor in
            // Brief pause for the overlay animation
            try? await Task.sleep(nanoseconds: 700_000_000)

            // Step 2: Create builder session with parsed spec
            print("[BuildTransition] Step 2 — parsing spec")
            transition.step = .launchingBuilder

            let specPath = (task.worktreePath as NSString).appendingPathComponent(".budahade/spec.md")
            if let spec = SpecParser.parse(fileAt: specPath) {
                print("[BuildTransition] Spec parsed: \(spec.tasks.count) tasks, creating builder tab")
                task.createBuilderSession(from: spec, contextSummary: contextSummary)
                print("[BuildTransition] Builder tab created, session: \(task.builderSession != nil)")
            } else {
                print("[BuildTransition] ⚠️ Could not parse spec at \(specPath), creating fallback builder")
                let section = SpecSection(
                    id: "build", title: "Build", level: 2,
                    content: "", tasks: [SpecTask(id: 0, title: "Implement spec", isCompleted: false, sectionId: "build")],
                    lineRange: 0..<1
                )
                let fallback = SpecParseResult(
                    title: "Build", sections: [section],
                    rawContent: "", filePath: specPath
                )
                task.createBuilderSession(from: fallback, contextSummary: contextSummary)
            }

            try? await Task.sleep(nanoseconds: 700_000_000)

            // Step 3: Switch to build mode — set mode directly since we already
            // have a builder session. Calling enterBuildMode() would re-scan for
            // specs and potentially create a duplicate session.
            print("[BuildTransition] Step 3 — switching to build mode + showing builder")
            transition.step = .switchingMode
            task.mode = .build
            task.showBuilderChat = true

            try? await Task.sleep(nanoseconds: 600_000_000)

            // Dismiss overlay
            print("[BuildTransition] Dismissing overlay")
            withAnimation(.easeOut(duration: 0.3)) {
                buildTransition = nil
            }
        }
    }

    // MARK: - Terminal Area (content zone — opaque dark)

    // MARK: - Build Mode Tab Bar (sits on app chrome)

    @ViewBuilder
    private var buildModeTabBar: some View {
        if let task = state.activeTask {
            VStack(spacing: 0) {
                if task.splitPane == nil {
                    TerminalTabBar(
                        selectedTabID: Binding(
                            get: { task.selectedTabId ?? UUID() },
                            set: {
                                task.selectTab($0)
                                task.showBuilderChat = false
                            }
                        ),
                        tabs: task.tabs.filter { $0.tabType != .builder },
                        renameTarget: renameTarget,
                        onSelectTab: {
                            task.selectTab($0)
                            task.showBuilderChat = false
                        },
                        onCloseTab: { requestCloseTab(.build($0)) },
                        onNewTab: { task.createTab() },
                        onNewBrowserTab: { task.createBrowserTab() },
                        onReorderTab: { tabId, newIndex in task.reorderTab(tabId, toIndex: newIndex) }
                    )
                }

                if task.builderSession != nil {
                    BuilderTabRow(task: task)
                }
            }
        }
    }

    // MARK: - Agent Content Area (dark rounded inset)

    private var agentContentArea: some View {
        ZStack {
            // Builder chat — persisted once session exists, hidden via opacity
            if let task = state.activeTask,
               let builderSession = task.builderSession {
                BuilderChatView(
                    session: builderSession,
                    specTitle: task.specState.activeSpec?.title ?? "Spec",
                    specContent: task.specState.activeSpec?.rawContent,
                    specFilePath: task.specState.activeSpec?.filePath,
                    agentSession: task.builderAgent?.agentSession,
                    builderAgent: task.builderAgent,
                    onLaunchAgent: { launchBuilderAgent(task: task) },
                    onBackToPlan: { task.enterPlanMode() },
                    onEditSpec: nil,
                    branchName: task.branchName
                )
                .opacity(task.showBuilderChat ? 1 : 0)
                .allowsHitTesting(task.showBuilderChat)
            }

            // Terminal/browser content — hidden when builder chat is shown
            ZStack(alignment: .top) {
                // Tab content panels (terminal + browser) — single or split
                if let task = state.activeTask, let split = task.splitPane {
                    // Split mode: each pane owns its own tab bar + content
                    PaneLayout(orientation: split.orientation) {
                        VStack(spacing: 0) {
                            TerminalTabBar(
                                selectedTabID: Binding(
                                    get: { task.selectedTabId ?? UUID() },
                                    set: { task.focusedPane = .primary; task.selectTab($0) }
                                ),
                                tabs: task.primaryTabs,
                                renameTarget: renameTarget,
                                onSelectTab: { task.focusedPane = .primary; task.selectTab($0) },
                                onCloseTab: { requestCloseTab(.build($0)) },
                                onNewTab: { task.createTab() },
                                onNewBrowserTab: { task.createBrowserTab() },
                                onReorderTab: { tabId, newIndex in task.reorderTab(tabId, toIndex: newIndex, inPane: .primary) }
                            )
                            ZStack {
                                ForEach(task.primaryTabs) { tab in
                                    tabContentPanel(task: task, tab: tab)
                                        .opacity(tab.id == task.selectedTabId ? 1 : 0)
                                        .allowsHitTesting(tab.id == task.selectedTabId)
                                }
                                if primaryContentDropTargeted {
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(Theme.Colors.accent.opacity(0.6), lineWidth: 2)
                                        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.Colors.accent.opacity(0.08)))
                                        .padding(4)
                                        .allowsHitTesting(false)
                                }
                            }
                            .onDrop(of: [UTType.text], isTargeted: $primaryContentDropTargeted) { _ in
                                guard let tabId = currentlyDraggingTabId else { return false }
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    task.moveTab(tabId, to: .primary)
                                }
                                return true
                            }
                            .overlay(paneFocusBorder(focused: task.focusedPane == .primary))
                        }
                        .opacity(task.focusedPane == .primary ? 1.0 : 0.6)
                        .animation(.easeInOut(duration: 0.15), value: task.focusedPane)
                    } second: {
                        VStack(spacing: 0) {
                            TerminalTabBar(
                                selectedTabID: Binding(
                                    get: { split.secondarySelectedId ?? UUID() },
                                    set: { task.focusedPane = .secondary; task.selectSecondaryTab($0) }
                                ),
                                tabs: task.secondaryTabs,
                                renameTarget: renameTarget,
                                onSelectTab: { task.focusedPane = .secondary; task.selectSecondaryTab($0) },
                                onCloseTab: { requestCloseTab(.build($0)) },
                                onNewTab: { task.createTabInSecondaryPane() },
                                onNewBrowserTab: { task.createBrowserTabInSecondaryPane() },
                                onReorderTab: { tabId, newIndex in task.reorderTab(tabId, toIndex: newIndex, inPane: .secondary) }
                            )
                            ZStack {
                                ForEach(task.secondaryTabs) { tab in
                                    tabContentPanel(task: task, tab: tab)
                                        .opacity(tab.id == split.secondarySelectedId ? 1 : 0)
                                        .allowsHitTesting(tab.id == split.secondarySelectedId)
                                }
                                if secondaryContentDropTargeted {
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(Theme.Colors.accent.opacity(0.6), lineWidth: 2)
                                        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.Colors.accent.opacity(0.08)))
                                        .padding(4)
                                        .allowsHitTesting(false)
                                }
                            }
                            .onDrop(of: [UTType.text], isTargeted: $secondaryContentDropTargeted) { _ in
                                guard let tabId = currentlyDraggingTabId else { return false }
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    task.moveTab(tabId, to: .secondary)
                                }
                                return true
                            }
                            .overlay(paneFocusBorder(focused: task.focusedPane == .secondary))
                        }
                        .opacity(task.focusedPane == .secondary ? 1.0 : 0.6)
                        .animation(.easeInOut(duration: 0.15), value: task.focusedPane)
                    }
                } else {
                    ZStack {
                        if let task = state.activeTask {
                            ForEach(task.tabs) { tab in
                                let isVisible = tab.id == task.selectedTabId
                                tabContentPanel(task: task, tab: tab)
                                    .opacity(isVisible ? 1 : 0)
                                    .allowsHitTesting(isVisible)
                            }
                        }

                        if state.tasks.isEmpty {
                            VStack(spacing: 8) {
                                Text("No tasks yet")
                                    .font(Theme.label(14))
                                    .foregroundColor(Theme.Colors.textTertiary)
                                Text("Press ⌘N to create a task")
                                    .font(Theme.caption(12))
                                    .foregroundColor(Theme.Colors.textTertiary.opacity(0.6))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }

                // Create-split drag overlay — only during active tab drag and when not already split
                if let task = state.activeTask, task.splitPane == nil, isTabDragging {
                    SplitDropOverlay { zone, tabIdString in
                        if let tabId = UUID(uuidString: tabIdString) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                task.splitTab(tabId, to: zone)
                            }
                        }
                    }
                }

                // Builder drawer overlay — slides down from top
                if let task = state.activeTask,
                   task.isBuilderDrawerOpen,
                   let builderPanel = task.builderPanel {
                    BuilderDrawerView(
                        panel: builderPanel,
                        buildStatus: task.buildStatus,
                        onClose: { task.isBuilderDrawerOpen = false }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .background(Theme.Colors.appBackground)
            .animation(.easeInOut(duration: 0.25), value: state.activeTask?.isBuilderDrawerOpen)
            .opacity(state.activeTask?.showBuilderChat != true ? 1 : 0)
            .allowsHitTesting(state.activeTask?.showBuilderChat != true)
        }
    }

    // MARK: - Tab Content Helpers

    /// Render a single tab's content panel (terminal or browser).
    @ViewBuilder
    private func tabContentPanel(task: TaskState, tab: TabInfo) -> some View {
        if tab.isTerminal, let panel = task.terminals[tab.id] {
            TerminalPanelView(panel: panel)
        } else if tab.isBrowser, let panel = task.browserPanels[tab.id] {
            BrowserPanelView(
                state: panel.state,
                assignedPort: task.assignedPort,
                detectedURLs: task.devServerManager?.detectedURLs ?? [],
                onPopOut: { panel.popOut() },
                onActivatePicker: {
                    guard let wv = panel.state.webView else { return }
                    panel.state.elementPicker.activate(in: wv)
                }
            )
        }
    }

    /// Render the content for a specific tab ID (used by split pane).
    @ViewBuilder
    private func tabContentView(for task: TaskState, tabId: UUID?) -> some View {
        if let tabId, let tab = task.tabs.first(where: { $0.id == tabId }) {
            tabContentPanel(task: task, tab: tab)
        } else {
            Color.clear
        }
    }

    private func paneFocusBorder(focused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .strokeBorder(focused ? Theme.Colors.accent.opacity(0.4) : Color.clear, lineWidth: 1.5)
            .allowsHitTesting(false)
    }


    // MARK: - Rename Palette

    @State private var spotlightFrame: CGRect = .zero

    private var renamePalette: some View {
        ZStack {
            // Dim scrim with spotlight cutout
            Color.black.opacity(0.25)
                .mask(
                    Rectangle()
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .padding(-3)
                                .frame(
                                    width: spotlightFrame.width + 6,
                                    height: spotlightFrame.height + 6
                                )
                                .position(
                                    x: spotlightFrame.midX,
                                    y: spotlightFrame.midY
                                )
                                .blendMode(.destinationOut)
                        )
                )
                .compositingGroup()
                .ignoresSafeArea()
                .onTapGesture { dismissRename() }
                .onPreferenceChange(RenameSpotlightKey.self) { frame in
                    spotlightFrame = frame
                }

            // Spotlight ring around the target element
            if spotlightFrame != .zero {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.Colors.accent.opacity(0.5), lineWidth: 1.5)
                    .frame(
                        width: spotlightFrame.width + 6,
                        height: spotlightFrame.height + 6
                    )
                    .position(
                        x: spotlightFrame.midX,
                        y: spotlightFrame.midY
                    )
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                // Label
                HStack(spacing: 6) {
                    Image(systemName: renameTarget?.icon ?? "pencil")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text(renameTarget?.label ?? "Rename")
                        .font(Theme.label(12))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Text("esc to cancel")
                        .font(Theme.caption(10))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Rectangle().fill(Theme.Colors.borderSubtle).frame(height: 1)

                // Text field
                TextField("", text: $renameText)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .textFieldStyle(.plain)
                    .focused($renameFieldFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { dismissRename() }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
            .frame(width: 380)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.Colors.borderLight, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
            )
            .offset(y: -60)
        }
        .transition(.opacity)
    }

    private func commitRename() {
        guard let target = renameTarget else { return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { dismissRename(); return }

        switch target {
        case .task(let taskId):
            if let task = state.tasks.first(where: { $0.id == taskId }) {
                task.name = name
            }
        case .tab(let taskId, let tabId):
            if let task = state.tasks.first(where: { $0.id == taskId }),
               let index = task.tabs.firstIndex(where: { $0.id == tabId }) {
                task.tabs[index].title = name
                task.tabs[index].restoredTitle = name
            }
        }
        dismissRename()
    }

    private func dismissRename() {
        renameTarget = nil
        renameText = ""
        renameFieldFocused = false
    }

    // MARK: - Tab Close with Confirmation

    private func requestCloseTab(_ request: TabCloseRequest) {
        guard let task = state.activeTask else { return }

        let hasDialogue: Bool
        switch request {
        case .plan(let id):
            hasDialogue = task.planChats[id]?.plannerSession?.messages.isEmpty == false
        case .build(let id):
            let tab = task.tabs.first(where: { $0.id == id })
            hasDialogue = tab?.hadActivity == true
        }

        if hasDialogue {
            tabCloseRequest = request
            showCloseConfirmation = true
        } else {
            performCloseTab(request)
        }
    }

    private func performCloseTab(_ request: TabCloseRequest) {
        guard let task = state.activeTask else { return }
        switch request {
        case .plan(let id):
            task.closePlanTab(id)
        case .build(let id):
            task.closeTab(id)
        }
    }
}

// MARK: - Tab Close Request

enum TabCloseRequest {
    case plan(UUID)
    case build(UUID)
}

// MARK: - Builder Tab Row (below conversation tabs)

struct BuilderTabRow: View {
    @ObservedObject var task: TaskState

    var body: some View {
        HStack(spacing: 0) {
            Button {
                task.showBuilderChat = true
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(builderStatusColor)
                        .frame(width: 6, height: 6)

                    if let session = task.builderSession {
                        Text("\(session.completedCount)/\(session.totalCount)")
                            .font(Theme.code(9))
                            .foregroundColor(Theme.Colors.statusWorking.opacity(0.5))
                    }

                    Text(task.specState.activeSpec?.title ?? "Builder")
                        .font(Theme.label(11))
                        .foregroundColor(
                            task.showBuilderChat
                                ? Theme.Colors.textPrimary
                                : Theme.Colors.textSecondary
                        )
                        .lineLimit(1)

                    if let session = task.builderSession {
                        SpecProgressBar(steps: session.steps, size: .mini)
                            .frame(width: 120)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(task.showBuilderChat
                              ? Theme.Colors.tabSelectedGlass
                              : Theme.Colors.tabGlassBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            task.showBuilderChat
                                ? Theme.Colors.statusWorking.opacity(0.2)
                                : Theme.Colors.tabGlassBorder,
                            lineWidth: 0.5
                        )
                )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .background(GlassBackground())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Colors.borderSubtle)
                .frame(height: 0.5)
        }
    }

    private var builderStatusColor: Color {
        guard let session = task.builderSession else { return Theme.Colors.statusIdle }
        switch session.buildState {
        case .building: return Theme.Colors.statusWorking
        case .done:     return Theme.Colors.statusDone
        case .failed:   return Theme.Colors.error
        case .ready:    return Theme.Colors.statusIdle
        case .paused:   return Theme.Colors.warning
        }
    }
}

// MARK: - Rename Spotlight Preference

struct RenameSpotlightKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

// MARK: - Rename Target

// MARK: - Build Transition State

@MainActor
final class BuildTransitionState: ObservableObject {
    enum Step: Int, CaseIterable {
        case writingSpec
        case launchingBuilder
        case switchingMode

        var label: String {
            switch self {
            case .writingSpec:      return "Writing spec.md\u{2026}"
            case .launchingBuilder: return "Launching builder agent\u{2026}"
            case .switchingMode:    return "Switching to Build mode\u{2026}"
            }
        }
    }

    @Published var step: Step = .writingSpec
}

// MARK: - Build Transition Overlay

struct BuildTransitionOverlay: View {
    @ObservedObject var state: BuildTransitionState

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 8) {
                ForEach(BuildTransitionState.Step.allCases, id: \.rawValue) { step in
                    HStack(spacing: 8) {
                        if step.rawValue < state.step.rawValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Theme.Colors.statusDone)
                                .frame(width: 14)
                        } else if step == state.step {
                            ProgressView()
                                .controlSize(.mini)
                                .frame(width: 14)
                        } else {
                            Circle()
                                .fill(Theme.Colors.textTertiary.opacity(0.3))
                                .frame(width: 6, height: 6)
                                .frame(width: 14)
                        }

                        Text(step.label)
                            .font(.system(size: 13, weight: step == state.step ? .medium : .regular))
                            .foregroundColor(
                                step.rawValue <= state.step.rawValue
                                    ? Theme.Colors.textPrimary
                                    : Theme.Colors.textTertiary
                            )
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.Colors.borderSubtle, lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
            )
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: state.step)
    }
}

// MARK: - Rename Target

enum RenameTarget: Equatable {
    case task(taskId: UUID)
    case tab(taskId: UUID, tabId: UUID)

    var label: String {
        switch self {
        case .task:  return "Rename Task"
        case .tab:   return "Rename Conversation"
        }
    }

    var icon: String {
        switch self {
        case .task:  return "checklist"
        case .tab:   return "message"
        }
    }

    var tabId: UUID? {
        if case .tab(_, let tabId) = self { return tabId }
        return nil
    }
}

