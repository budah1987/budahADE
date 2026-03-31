import SwiftUI

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


    var body: some View {
        ZStack {
            Theme.appBackground.ignoresSafeArea()

            HStack(spacing: 0) {
                // ── TASK RAIL ──
                TaskRailView(workspace: state, renameTarget: renameTarget)
                    .background(Theme.sidebar)

                Rectangle()
                    .fill(Theme.border)
                    .frame(width: 1)

                // ── CONTENT ZONE ──
                VStack(spacing: 0) {
                    // Content
                    if let task = state.activeTask, task.mode == .plan {
                        // Plan mode: role modal or tab bar + chat
                        VStack(spacing: 0) {
                            if task.planTabs.isEmpty {
                                // No tabs — show role selection
                                RoleSelectionModal { role in
                                    task.createPlanTab(role: role)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
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

                                if let planChat = task.activePlanChat,
                                   let selectedId = task.selectedPlanTabId {
                                    PlanChatView(
                                        state: planChat,
                                        siblingTabs: task.planTabs.filter { $0.id != selectedId },
                                        onHandOff: { targetId in
                                            task.handOff(from: selectedId, to: targetId)
                                        },
                                        onApproveToBuild: { itemCount in
                                            startBuildTransition(task: task, itemCount: itemCount)
                                        }
                                    )
                                    .id(task.selectedPlanTabId)
                                }
                            }
                        }
                        .sheet(isPresented: $showRoleModal) {
                            RoleSelectionModal { role in
                                task.createPlanTab(role: role)
                                showRoleModal = false
                            }
                        }
                    } else {
                        // Build mode: sidebar + terminal area + git panel
                        HStack(spacing: 0) {
                            if state.leftPanelVisible {
                                LeftPanelView(
                                    state: state,
                                    worktreePath: state.activeTask?.worktreePath ?? state.projectPath
                                )
                                .id("\(state.activeTaskId?.uuidString ?? "")-\(state.activeTask?.tabs.count ?? 0)")
                                .transition(.move(edge: .leading).combined(with: .opacity))
                                .background(Theme.sidebar)

                                Rectangle()
                                    .fill(Theme.border)
                                    .frame(width: 1)
                            }

                            terminalArea

                            if state.rightPanelVisible, let task = state.activeTask {
                                Rectangle()
                                    .fill(Theme.border)
                                    .frame(width: 1)

                                GitSidebarView(task: task, projectPath: state.projectPath)
                                    .id(state.activeTaskId)
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                            }
                        }
                    }
                }
            }
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
                .background(Theme.appBackground)
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
                } else {
                    task.createTab()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleBrowser)) { _ in
            if let task = state.activeTask, task.mode == .build {
                if let existing = task.tabs.first(where: { $0.isBrowser }) {
                    task.selectTab(existing.id)
                } else {
                    task.createBrowserTab()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusNextPane)) { _ in
            state.activeTask?.moveFocus(.next)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusPrevPane)) { _ in
            state.activeTask?.moveFocus(.previous)
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
                    if let id = task.selectedTabId {
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
            guard let task = state.activeTask,
                  let tabId = task.selectedTabId,
                  let tab = task.tabs.first(where: { $0.id == tabId }) else { return }
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
    }

    // MARK: - Build Transition

    private func startBuildTransition(task: TaskState, itemCount: Int) {
        let transition = BuildTransitionState()
        buildTransition = transition

        // Step 1: Writing spec.md… (already done by handleApprove)
        transition.step = .writingSpec

        // Step 2: Launching builder agent…
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            transition.step = .launchingBuilder
        }

        // Step 3: Switching to Build mode…
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            transition.step = .switchingMode
            task.enterBuildMode()
        }

        // Dismiss overlay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.3)) {
                buildTransition = nil
            }
        }
    }

    // MARK: - Terminal Area (content zone — opaque dark)

    private var terminalArea: some View {
        VStack(spacing: 0) {
            if let task = state.activeTask {
                TerminalTabBar(
                    selectedTabID: Binding(
                        get: { task.selectedTabId ?? UUID() },
                        set: { task.selectTab($0) }
                    ),
                    tabs: task.tabs,
                    renameTarget: renameTarget,
                    onSelectTab: { task.selectTab($0) },
                    onCloseTab: { requestCloseTab(.build($0)) },
                    onNewTab: { task.createTab() },
                    onNewBrowserTab: { task.createBrowserTab() }
                )

                // Inline spec strip (only when spec exists)
                if task.specState.hasSpec {
                    SpecStripView(
                        specState: task.specState,
                        buildStatus: task.buildStatus,
                        variant: .inline,
                        hasBuilder: task.builderPanel != nil,
                        isBuilderDrawerOpen: Binding(
                            get: { task.isBuilderDrawerOpen },
                            set: { task.isBuilderDrawerOpen = $0 }
                        )
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))

                    Rectangle()
                        .fill(Theme.borderSubtle)
                        .frame(height: 0.5)
                }
            }

            ZStack(alignment: .top) {
                // Tab content panels (terminal + browser) — single or split
                if let task = state.activeTask, let split = task.splitPane {
                    PaneLayout(orientation: split.orientation) {
                        tabContentView(for: task, tabId: task.selectedTabId)
                            .overlay(paneFocusBorder(focused: task.focusedPane == .primary))
                            .onTapGesture { task.focusedPane = .primary }
                    } second: {
                        tabContentView(for: task, tabId: split.secondaryTabId)
                            .overlay(paneFocusBorder(focused: task.focusedPane == .secondary))
                            .onTapGesture { task.focusedPane = .secondary }
                    }
                } else {
                    ZStack {
                        ForEach(state.tasks) { task in
                            let isActiveTask = task.id == state.activeTaskId
                            ForEach(task.tabs) { tab in
                                let isVisible = isActiveTask && tab.id == task.selectedTabId
                                tabContentPanel(task: task, tab: tab)
                                    .opacity(isVisible ? 1 : 0)
                                    .allowsHitTesting(isVisible)
                            }
                        }

                        if state.tasks.isEmpty {
                            VStack(spacing: 8) {
                                Text("No tasks yet")
                                    .font(Theme.label(14))
                                    .foregroundColor(Theme.textMuted)
                                Text("Press ⌘N to create a task")
                                    .font(Theme.caption(12))
                                    .foregroundColor(Theme.textMuted.opacity(0.6))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }

                // Drop zone overlay for tab splitting (always present, invisible until drag targets)
                if let task = state.activeTask, task.splitPane == nil {
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
            .background(Theme.contentBg)
            .animation(.easeInOut(duration: 0.25), value: state.activeTask?.isBuilderDrawerOpen)
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
                onPopOut: { panel.popOut() }
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
            .strokeBorder(focused ? Theme.accent.opacity(0.4) : Color.clear, lineWidth: 1.5)
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
                    .strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1.5)
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
                        .foregroundStyle(Theme.textMuted)
                    Text(renameTarget?.label ?? "Rename")
                        .font(Theme.label(12))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("esc to cancel")
                        .font(Theme.caption(10))
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Rectangle().fill(Theme.borderSubtle).frame(height: 1)

                // Text field
                TextField("", text: $renameText)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
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
                    .fill(Theme.surface2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1)
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
                                .foregroundColor(Theme.success)
                                .frame(width: 14)
                        } else if step == state.step {
                            ProgressView()
                                .controlSize(.mini)
                                .frame(width: 14)
                        } else {
                            Circle()
                                .fill(Theme.textMuted.opacity(0.3))
                                .frame(width: 6, height: 6)
                                .frame(width: 14)
                        }

                        Text(step.label)
                            .font(.system(size: 13, weight: step == state.step ? .medium : .regular))
                            .foregroundColor(
                                step.rawValue <= state.step.rawValue
                                    ? Theme.textPrimary
                                    : Theme.textMuted
                            )
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.surface2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.borderSubtle, lineWidth: 0.5)
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

