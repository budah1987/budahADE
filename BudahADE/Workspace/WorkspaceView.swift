import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var state: WorkspaceState
    @State private var editingTabId: UUID? = nil
    @State private var editingTaskId: UUID? = nil

    var body: some View {
        ZStack {
            Theme.appBackground.ignoresSafeArea()

            HStack(spacing: Theme.panelGap) {
                TaskRailView(workspace: state, editingTaskId: $editingTaskId)

                if state.leftPanelVisible {
                    LeftPanelView(
                        state: state,
                        worktreePath: state.activeTask?.worktreePath ?? state.projectPath
                    )
                    .id(state.activeTaskId)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                terminalArea
            }
            .padding(Theme.edgePadding)
        }
        .animation(.easeInOut(duration: 0.2), value: state.leftPanelVisible)
        .sheet(isPresented: $state.showNewTaskSheet) {
            NewTaskSheet(workspace: state)
                .background(Theme.appBackground)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleLeftPanel)) { _ in
            state.leftPanelVisible.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTerminalTab)) { _ in
            state.activeTask?.createTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeTerminalTab)) { _ in
            if let id = state.activeTask?.selectedTabId {
                state.activeTask?.closeTab(id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectTabByIndex)) { notification in
            guard let index = notification.userInfo?["index"] as? Int else { return }
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
            editingTabId = state.activeTask?.selectedTabId
        }
        .onReceive(NotificationCenter.default.publisher(for: .renameTask)) { _ in
            editingTaskId = state.activeTaskId
        }
    }

    // MARK: - Terminal Area

    private var terminalArea: some View {
        VStack(spacing: 0) {
            if let task = state.activeTask {
                TerminalTabBar(
                    selectedTabID: Binding(
                        get: { task.selectedTabId ?? UUID() },
                        set: { task.selectTab($0) }
                    ),
                    editingTabId: $editingTabId,
                    tabs: task.tabs,
                    onSelectTab: { task.selectTab($0) },
                    onCloseTab: { task.closeTab($0) },
                    onNewTab: { task.createTab() },
                    onRenameTab: { id, newTitle in
                        if let index = task.tabs.firstIndex(where: { $0.id == id }) {
                            task.tabs[index].title = newTitle
                        }
                    }
                )
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
                    VStack(spacing: 12) {
                        Text("No tasks yet")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Theme.textMuted)
                        Text("Create a task to get started")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textMuted.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.panelCornerRadius)
                .fill(Theme.panelSurface)
        )
    }
}
