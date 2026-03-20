import SwiftUI

struct AgentsPanel: View {
    @ObservedObject var workspace: WorkspaceState

    private var activeTask: TaskState? { workspace.activeTask }

    var body: some View {
        VStack(spacing: 0) {
            if let task = activeTask, !task.tabs.isEmpty {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(task.tabs) { tab in
                            agentRow(tab: tab, task: task)
                        }
                    }
                    .padding(.vertical, 6)
                }
            } else {
                emptyState
            }
        }
    }

    // MARK: - Agent Row

    private func agentRow(tab: TabInfo, task: TaskState) -> some View {
        let isActive = tab.id == task.selectedTabId
        return Button {
            task.selectTab(tab.id)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(isActive ? Theme.accent : Theme.textMuted.opacity(0.4))
                    .frame(width: 5, height: 5)

                VStack(alignment: .leading, spacing: 1) {
                    Text(tab.title)
                        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                        .foregroundColor(isActive ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)

                    if tab.isRunning {
                        Text("Running")
                            .font(Theme.caption(10))
                            .foregroundColor(Theme.accent.opacity(0.7))
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Theme.pillCornerRadius)
                    .fill(isActive ? Theme.selectedFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No agents running")
                .font(Theme.label(12))
                .foregroundColor(Theme.textMuted)
            Text("Press ⌘T to start a new agent")
                .font(Theme.caption(11))
                .foregroundColor(Theme.textMuted.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
