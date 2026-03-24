import SwiftUI

struct WorkspaceView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var state: WorkspaceState

    /// Rename palette state
    @State private var renameTarget: RenameTarget? = nil
    @State private var renameText: String = ""
    @FocusState private var renameFieldFocused: Bool

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
                    if let task = state.activeTask, task.mode == .plan,
                       let canvas = task.planCanvas {
                        // Plan mode: full-width canvas
                        PlanCanvasView(canvas: canvas)
                            .clipped()
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

                                GitSidebarView(task: task)
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
        }
        .coordinateSpace(name: "workspace")
        .animation(.easeInOut(duration: 0.2), value: state.leftPanelVisible)
        .animation(.easeInOut(duration: 0.2), value: state.rightPanelVisible)
        .animation(.easeOut(duration: 0.15), value: renameTarget != nil)
        .sheet(isPresented: $state.showNewTaskSheet) {
            NewTaskSheet(workspace: state)
                .background(Theme.appBackground)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleLeftPanel)) { _ in
            state.leftPanelVisible.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleRightPanel)) { _ in
            state.rightPanelVisible.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTerminalTab)) { _ in
            state.activeTask?.createTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeTerminalTab)) { _ in
            if let id = state.activeTask?.selectedTabId {
                state.activeTask?.closeTab(id)
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
            state.activeTask?.selectTabByIndex(index)
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
                    onCloseTab: { task.closeTab($0) },
                    onNewTab: { task.createTab() }
                )

                // Inline spec strip (only when spec exists)
                if task.specState.hasSpec {
                    SpecStripView(specState: task.specState, buildStatus: task.buildStatus, variant: .inline)
                        .transition(.opacity.combined(with: .move(edge: .top)))

                    Rectangle()
                        .fill(Theme.borderSubtle)
                        .frame(height: 0.5)
                }
            }

            ZStack {
                ForEach(state.tasks) { task in
                    ForEach(task.tabs) { tab in
                        if let panel = task.terminals[tab.id] {
                            TerminalPanelView(panel: panel)
                                .opacity(task.id == state.activeTaskId && tab.id == task.selectedTabId ? 1 : 0)
                                .allowsHitTesting(task.id == state.activeTaskId && tab.id == task.selectedTabId)
                        }
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
            .background(Theme.contentBg)
        }
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
                        .font(Theme.mono(10))
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

