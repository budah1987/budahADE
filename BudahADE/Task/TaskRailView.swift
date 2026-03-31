import SwiftUI

struct TaskRailView: View {
    @ObservedObject var workspace: WorkspaceState
    var renameTarget: RenameTarget? = nil

    @State private var hoveredTaskId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Project name — like Attio's "Acme Tech" at top of sidebar
            WorkspaceDropdown()
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)

            // Plan/Build toggle
            if let task = workspace.activeTask {
                PlanBuildToggle(mode: Binding(
                    get: { task.mode },
                    set: { newMode in
                        if newMode == .plan { task.enterPlanMode() }
                        else { task.enterBuildMode() }
                    }
                ))
                .padding(.horizontal, 10)
                .padding(.bottom, 6)

                // Spec progress strip
                SpecStripView(specState: task.specState, buildStatus: task.buildStatus)
            }

            // Section header
            HStack(alignment: .firstTextBaseline) {
                Text("Tasks")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textMuted)
                Spacer()
                Text("\(workspace.tasks.count)")
                    .font(Theme.label(9))
                    .foregroundColor(Theme.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)

            // Task list
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(workspace.tasks) { task in
                        TaskCardView(
                            task: task,
                            isActive: task.id == workspace.activeTaskId,
                            isHovered: task.id == hoveredTaskId,
                            isSpotlit: renameTarget == .task(taskId: task.id),
                            onSelect: { workspace.selectTask(task.id) },
                            onComplete: { workspace.taskForCompletion = task },
                            onDelete: { workspace.deleteTask(task.id) }
                        )
                        .onHover { hovering in
                            hoveredTaskId = hovering ? task.id : nil
                        }
                    }
                }
                .padding(.horizontal, 6)
            }

            Spacer(minLength: 0)

            // Task Archive button
            Button {
                workspace.showTaskArchive = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 10, weight: .medium))
                    Text("Task Archive")
                        .font(Theme.label(12))
                }
                .foregroundColor(Theme.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.border).frame(height: 1)
            }

            // New Task button
            Button {
                workspace.showNewTaskSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                    Text("New Task")
                        .font(Theme.label(12))
                }
                .foregroundColor(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.borderSubtle).frame(height: 1)
            }
        }
        .frame(width: 160)
        .sheet(item: $workspace.taskForCompletion) { task in
            TaskCompletionSheet(workspace: workspace, task: task)
                .background(Theme.appBackground)
        }
        .sheet(isPresented: $workspace.showTaskArchive) {
            TaskArchiveView(archive: workspace.taskArchive) { archived in
                workspace.reopenTask(archived)
            }
            .background(Theme.appBackground)
        }
    }
}

// MARK: - Task Card

private struct TaskCardView: View {
    @ObservedObject var task: TaskState
    let isActive: Bool
    let isHovered: Bool
    var isSpotlit: Bool = false
    let onSelect: () -> Void
    let onComplete: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                // Row 1: Status indicator + Task name
                HStack(spacing: 6) {
                    AgentStatusView(status: leadingStatus)

                    Text(task.name)
                        .font(.system(size: 12, weight: isActive && task.status != .completed ? .semibold : .regular))
                        .foregroundColor(
                            task.status == .completed
                                ? Color.white.opacity(0.25)
                                : isActive
                                    ? Color.white.opacity(0.92)
                                    : Color.white.opacity(0.38)
                        )
                        .lineLimit(1)
                        .animation(.easeOut(duration: 0.12), value: isActive)
                }

                // Row 2: Branch name + port badge
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Theme.textMuted)

                    Text(task.branchName)
                        .font(Theme.caption(9))
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)

                    if let port = task.assignedPort, task.devServerManager?.isRunning == true {
                        Text(":\(port)")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundColor(Theme.accent)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Theme.accent.opacity(0.12))
                            .cornerRadius(3)
                    }
                }
                .padding(.leading, 12)

                // Row 3: Status summary + elapsed time
                statusSummaryRow
                    .padding(.leading, 12)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fillColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 0.5)
                    )
            )
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: leadingStatus)
            .contentShape(Rectangle())
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: RenameSpotlightKey.self,
                            value: isSpotlit
                                ? geo.frame(in: .named("workspace"))
                                : .zero
                        )
                }
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename") {
                NotificationCenter.default.post(name: .renameTask, object: nil)
            }
            Button("Complete Task...") { onComplete() }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete Task", systemImage: "trash")
            }
        }
    }

    // MARK: - Status Summary

    @ViewBuilder
    private var statusSummaryRow: some View {
        HStack {
            if task.status == .completed {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Theme.success)
                        .frame(width: 4, height: 4)
                    Text("completed")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.success)
                }
            } else {
                HStack(spacing: 3) {
                    ForEach(Array(task.statusSummary.enumerated()), id: \.offset) { _, entry in
                        let (status, count) = entry
                        Circle()
                            .fill(statusDotColor(status))
                            .frame(width: 4, height: 4)
                        Text("\(count) \(statusLabel(status))")
                            .font(.system(size: 9))
                            .foregroundColor(statusDotColor(status))
                    }
                }
            }

            Spacer()

            Text(task.elapsedTime)
                .font(Theme.caption(9))
                .foregroundColor(Color.white.opacity(0.18))
        }
    }

    // MARK: - Helpers

    private var fillColor: Color {
        switch leadingStatus {
        case .working:
            return isHovered
                ? Color(hex: 0x6366f1).opacity(0.10)
                : Color(hex: 0x6366f1).opacity(0.05)
        case .completed:
            return isHovered
                ? Color(hex: 0x5a9a6b).opacity(0.08)
                : Color(hex: 0x5a9a6b).opacity(0.04)
        default:
            return isHovered ? Color.white.opacity(0.03) : .clear
        }
    }

    private var borderColor: Color {
        switch leadingStatus {
        case .working:
            return isHovered
                ? Color(hex: 0x6366f1).opacity(0.28)
                : Color(hex: 0x6366f1).opacity(0.15)
        case .completed:
            return isHovered
                ? Color(hex: 0x5a9a6b).opacity(0.20)
                : Color(hex: 0x5a9a6b).opacity(0.12)
        default:
            return .clear
        }
    }

    /// Highest-priority agent status to show as the card's leading indicator
    private var leadingStatus: AgentStatus {
        if task.status == .completed { return .completed }
        // Show the most active status across all agents
        let statuses = task.tabs.map(\.agentStatus)
        if statuses.contains(.working) { return .working }
        if statuses.contains(.thinking) { return .thinking }
        return .inactive
    }

    private func statusDotColor(_ status: AgentStatus) -> Color {
        switch status {
        case .inactive:  return Theme.textMuted
        case .thinking:  return Theme.success
        case .working:   return Color(hex: 0x818cf8)
        case .completed: return Theme.success
        }
    }

    private func statusLabel(_ status: AgentStatus) -> String {
        switch status {
        case .inactive:  return "idle"
        case .thinking:  return "active"
        case .working:   return "working"
        case .completed: return "done"
        }
    }
}

// MARK: - Plan/Build Toggle

struct PlanBuildToggle: View {
    @Binding var mode: TaskMode

    var body: some View {
        HStack(spacing: 0) {
            toggleButton("Plan", isActive: mode == .plan) { mode = .plan }
            toggleButton("Build", isActive: mode == .build) { mode = .build }
        }
        .padding(2)
        .background(Theme.surface2)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.borderSubtle, lineWidth: 0.5)
        )
    }

    private func toggleButton(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Theme.label(11))
                .foregroundColor(isActive ? Theme.textPrimary : Theme.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isActive ? Color.white.opacity(0.08) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}
