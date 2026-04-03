import SwiftUI

struct TaskRailView: View {
    @ObservedObject var workspace: WorkspaceState
    var renameTarget: RenameTarget? = nil

    @State private var hoveredTaskId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // View toggle: Plan / Build
            ViewToggle(mode: Binding(
                get: { workspace.activeTask?.mode ?? .plan },
                set: { newMode in
                    if newMode == .plan {
                        workspace.activeTask?.enterPlanMode()
                    } else {
                        workspace.activeTask?.enterBuildMode()
                        if workspace.activeTask?.builderSession != nil {
                            workspace.activeTask?.showBuilderChat = true
                        }
                    }
                }
            ))
            .padding(.horizontal, 14)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.lg)
            .disabled(workspace.activeTask == nil)

            // Notification Summary — aggregate progress across all tasks
            if !workspace.tasks.isEmpty {
                NotificationSummaryBar(tasks: workspace.tasks)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.lg)
            }

            // Task cards
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Theme.Layout.taskCardGap) {
                    ForEach(workspace.tasks) { task in
                        TaskCard(
                            task: task,
                            isActive: task.id == workspace.activeTaskId,
                            onSelect: {
                                workspace.selectTask(task.id)
                                if task.builderSession != nil {
                                    task.enterBuildMode()
                                    task.showBuilderChat = true
                                }
                            }
                        )
                        .onHover { hovering in
                            hoveredTaskId = hovering ? task.id : nil
                        }
                        .contextMenu {
                            Button("Rename") {
                                NotificationCenter.default.post(name: .renameTask, object: nil)
                            }
                            Button("Complete Task...") {
                                workspace.taskForCompletion = task
                            }
                            Divider()
                            Button(role: .destructive) {
                                workspace.deleteTask(task.id)
                            } label: {
                                Label("Delete Task", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.sm)
            }

            Spacer(minLength: 0)

            // Bottom nav items
            VStack(spacing: 0) {
                // Plan Archive (conditional)
                if let task = workspace.activeTask, !task.archivedPlanTabs.isEmpty {
                    SidebarNavItem(
                        icon: "archivebox",
                        label: "Plan Archive",
                        trailing: "\(task.archivedPlanTabs.count)",
                        showDivider: true
                    ) {
                        task.showPlanArchive = true
                    }
                }

                SidebarNavItem(icon: "archivebox", label: "Task Archive", showDivider: true) {
                    workspace.showTaskArchive = true
                }

                SidebarNavItem(icon: "plus.circle", label: "New Task", showDivider: true) {
                    workspace.showNewTaskSheet = true
                }

                SidebarNavItem(icon: "gearshape", label: "Settings", showDivider: false) {
                    // Settings action
                }
            }
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .frame(width: Theme.Layout.sidebarWidth)
        .sheet(item: $workspace.taskForCompletion) { task in
            TaskCompletionSheet(workspace: workspace, task: task)
                .background(Theme.Colors.appBackground)
        }
        .sheet(isPresented: $workspace.showTaskArchive) {
            TaskArchiveView(archive: workspace.taskArchive) { archived in
                workspace.reopenTask(archived)
            }
            .background(Theme.Colors.appBackground)
        }
        .sheet(isPresented: planArchiveBinding) {
            if let task = workspace.activeTask {
                PlanArchiveView(archivedTabs: task.archivedPlanTabs) { index in
                    task.archivedPlanTabs.remove(at: index)
                }
                .background(Theme.Colors.appBackground)
            }
        }
    }

    private var planArchiveBinding: Binding<Bool> {
        Binding(
            get: { workspace.activeTask?.showPlanArchive ?? false },
            set: { newValue in workspace.activeTask?.showPlanArchive = newValue }
        )
    }
}

// MARK: - View Toggle (Plan/Build)

struct ViewToggle: View {
    @Binding var mode: TaskMode

    var body: some View {
        HStack(spacing: 0) {
            togglePill("Plan", isActive: mode == .plan) { mode = .plan }
            togglePill("Build", isActive: mode == .build) { mode = .build }
        }
        .padding(2)
        .background(Color.white.opacity(0.05))
        .cornerRadius(6)
    }

    private func togglePill(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(isActive ? Theme.label(11) : Theme.body(11))
                .foregroundColor(isActive ? .white : Color.white.opacity(0.45))
                .frame(width: 94, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isActive ? Color.white.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Notification Summary Bar

private struct NotificationSummaryBar: View {
    let tasks: [TaskState]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack {
                Text("Notification Summary")
                    .font(Theme.body(9))
                    .foregroundColor(.white)
                Spacer()
                Text("\(doneCount)/\(totalCount)")
                    .font(Theme.body(9))
                    .foregroundColor(Theme.Colors.statusIdle)
            }

            SpecProgressBar(steps: aggregateSteps, size: .mini)
        }
    }

    private var aggregateSteps: [BuildStep] {
        // Collect build steps from all tasks, or synthesize from task status
        var steps: [BuildStep] = []
        for task in tasks {
            if let session = task.builderSession {
                steps.append(contentsOf: session.steps)
            } else {
                // Represent each task as a single step
                let state: StepState = task.status == .completed ? .done : .queued
                steps.append(BuildStep(id: task.id.uuidString, title: task.name, state: state))
            }
        }
        return steps
    }

    private var doneCount: Int {
        aggregateSteps.filter { $0.state == .done }.count
    }

    private var totalCount: Int {
        aggregateSteps.count
    }
}

// MARK: - Task Card

struct TaskCard: View {
    @ObservedObject var task: TaskState
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            GlassPanel(style: isActive ? .cardActive : .card) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    // Title
                    Text(task.name)
                        .font(.custom("Geist-SemiBold", size: Theme.Typography.titleSize))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(1)

                    // Branch + progress
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.Colors.textTertiary)
                            Text(task.branchName)
                                .font(Theme.code(Theme.Typography.monoSize))
                                .foregroundColor(Theme.Colors.textTertiary)
                                .lineLimit(1)
                        }

                        if let session = task.builderSession {
                            SpecProgressBar(steps: session.steps, size: .mini)
                        }
                    }

                    // Status counts row
                    statusCountsRow
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
            }
            .opacity(isActive ? 1 : 0.5)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusCountsRow: some View {
        let summary = task.statusSummary
        HStack {
            ForEach(Array(summary.enumerated()), id: \.offset) { _, entry in
                let (status, count) = entry
                Text("\(count) \(statusLabel(status))")
                    .font(Theme.caption(Theme.Typography.captionSize))
                    .foregroundColor(statusColor(status))
            }
            if summary.isEmpty && task.status == .completed {
                Text("Done")
                    .font(Theme.caption(Theme.Typography.captionSize))
                    .foregroundColor(Theme.Colors.statusDone)
            }
            Spacer()
        }
    }

    private func statusLabel(_ status: AgentStatus) -> String {
        switch status {
        case .working:   return "Working"
        case .completed: return "Done"
        case .thinking:  return "Active"
        case .inactive:  return "Idle"
        }
    }

    private func statusColor(_ status: AgentStatus) -> Color {
        switch status {
        case .working:   return Theme.Colors.statusWorking
        case .completed: return Theme.Colors.statusDone
        case .thinking:  return Theme.Colors.statusDone
        case .inactive:  return Theme.Colors.statusIdle
        }
    }
}

// MARK: - Sidebar Nav Item

private struct SidebarNavItem: View {
    let icon: String
    let label: String
    var trailing: String? = nil
    var showDivider: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 24, height: 24)

                Text(label)
                    .font(Theme.body(Theme.Typography.labelSize))

                if let trailing {
                    Spacer()
                    Text(trailing)
                        .font(Theme.caption(10))
                }
            }
            .foregroundColor(Theme.Colors.textTertiary)
            .frame(height: Theme.Layout.navItemHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if showDivider {
                Rectangle().fill(Theme.Colors.borderSubtle).frame(height: 1)
            }
        }
    }
}
