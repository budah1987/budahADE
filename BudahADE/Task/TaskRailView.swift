import SwiftUI

struct TaskRailView: View {
    @ObservedObject var workspace: WorkspaceState
    @Binding var editingTaskId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("TASKS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.textMuted)
                    .tracking(0.8)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // Task list
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(workspace.tasks) { task in
                        TaskRowView(
                            task: task,
                            isActive: task.id == workspace.activeTaskId,
                            isEditing: task.id == editingTaskId,
                            onSelect: { workspace.selectTask(task.id) },
                            onComplete: { workspace.taskForCompletion = task },
                            onDelete: { workspace.deleteTask(task.id) },
                            onCommitRename: { newName in
                                task.name = newName
                                editingTaskId = nil
                            }
                        )
                    }
                }
                .padding(.horizontal, 6)
            }

            Spacer(minLength: 0)

            Divider()
                .background(Theme.border)
                .padding(.horizontal, 8)

            Button {
                workspace.showNewTaskSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                    Text("New Task")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 160)
        .background(Theme.panelSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelCornerRadius))
        .sheet(item: $workspace.taskForCompletion) { task in
            TaskCompletionSheet(workspace: workspace, task: task)
                .background(Theme.appBackground)
        }
    }
}

// MARK: - Task Row

private struct TaskRowView: View {
    @ObservedObject var task: TaskState
    let isActive: Bool
    let isEditing: Bool
    let onSelect: () -> Void
    let onComplete: () -> Void
    let onDelete: () -> Void
    let onCommitRename: (String) -> Void

    @State private var editText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
                    .padding(.leading, 2)

                VStack(alignment: .leading, spacing: 2) {
                    if isEditing {
                        TextField("", text: $editText)
                            .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                            .foregroundColor(isActive ? Theme.textPrimary : Theme.textSecondary)
                            .textFieldStyle(.plain)
                            .lineLimit(1)
                            .focused($isFocused)
                            .onSubmit { onCommitRename(editText) }
                            .onExitCommand { onCommitRename(editText) }
                    } else {
                        Text(task.name)
                            .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                            .foregroundColor(isActive ? Theme.textPrimary : Theme.textSecondary)
                            .lineLimit(1)
                    }

                    Text(task.branchName)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Theme.elevated : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onChange(of: isEditing) { _, editing in
            if editing {
                editText = task.name
                isFocused = true
            }
        }
        .contextMenu {
            Button("Rename") { onCommitRename(task.name) } // triggers edit mode via parent
            Button("Complete Task...") { onComplete() }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete Task", systemImage: "trash")
            }
        }
    }

    private var dotColor: Color {
        switch task.status {
        case .active:    return isActive ? Theme.accent : Theme.textMuted.opacity(0.5)
        case .completed: return Theme.success
        }
    }
}
