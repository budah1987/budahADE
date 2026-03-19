import SwiftUI

struct AgentsPanel: View {
    @ObservedObject var workspace: WorkspaceState

    private var activeTask: TaskState? { workspace.activeTask }

    var body: some View {
        VStack(spacing: 0) {
            if let task = activeTask, !task.tabs.isEmpty {
                ScrollView {
                    VStack(spacing: 2) {
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
                // Status dot
                Circle()
                    .fill(isActive ? Theme.accent : Theme.textMuted.opacity(0.3))
                    .frame(width: 6, height: 6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.title)
                        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                        .foregroundColor(isActive ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)

                    // Running indicator
                    if tab.isRunning {
                        Text("Running")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.accent.opacity(0.8))
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Theme.elevated : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No agents running")
                .font(.system(size: 13))
                .foregroundColor(Theme.textMuted)
            Text("Press ⌘T to start a new agent")
                .font(.system(size: 11))
                .foregroundColor(Theme.textMuted.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
