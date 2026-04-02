import SwiftUI

// MARK: - Step Index Wrapper (for sheet presentation)

private struct StepIndexWrapper: Identifiable {
    let index: Int
    var id: Int { index }
}

// MARK: - Pulsing Modifier

private struct PulsingDot: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

// MARK: - Spec Sidebar Panel

/// Builder side panel showing spec progress, block graph, and task checklist.
/// Matches the wireframe: SPEC PROGRESS header → block graph → task list with active expansion.
struct SpecSidebarPanel: View {
    @Bindable var session: BuilderSession
    @ObservedObject var specState: SpecState
    @ObservedObject var buildStatus: BuildStatusState
    var specFilePath: String? = nil
    var onJumpToChat: ((Int) -> Void)? = nil
    var onViewDiff: ((Int) -> Void)? = nil

    @State private var selectedStepIndex: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            // "SPEC PROGRESS N/M" header
            specProgressHeader
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)

            // Block graph
            SpecBlockGraphView(specState: specState, buildStatus: buildStatus)

            Divider().opacity(0.3)

            // Task checklist from SpecState with active step expansion from BuilderSession
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if let spec = specState.activeSpec {
                            ForEach(Array(spec.tasks.enumerated()), id: \.element.id) { index, task in
                                specTaskRow(task, at: index)
                                    .id(task.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if session.steps.indices.contains(index) {
                                            selectedStepIndex = index
                                        }
                                    }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
                .onChange(of: session.activeStepIndex) { _, newIndex in
                    guard let idx = newIndex,
                          let spec = specState.activeSpec,
                          idx < spec.tasks.count else { return }
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(spec.tasks[idx].id, anchor: .center)
                    }
                }
            }
        }
        .frame(minWidth: 200, idealWidth: 260, maxWidth: 320)
        .background(Theme.sidebar)
        .sheet(item: selectedStepBinding) { wrapper in
            StepDetailModal(
                step: $session.steps[wrapper.index],
                stepIndex: wrapper.index,
                totalSteps: session.totalCount,
                onJumpToChat: { onJumpToChat?(wrapper.index) },
                onViewDiff: { onViewDiff?(wrapper.index) },
                onRetry: {
                    session.steps[wrapper.index].state = .queued
                    session.steps[wrapper.index].error = nil
                    selectedStepIndex = nil
                },
                onSkip: {
                    session.skipStep(at: wrapper.index)
                    selectedStepIndex = nil
                },
                onRemove: {
                    session.steps.remove(at: wrapper.index)
                    selectedStepIndex = nil
                },
                onSave: {
                    if let path = specFilePath {
                        _ = SpecParser.persistBuildSteps(session.steps, to: path)
                    }
                    selectedStepIndex = nil
                }
            )
        }
    }

    // Wrapper to make Int work with sheet(item:)
    private var selectedStepBinding: Binding<StepIndexWrapper?> {
        Binding(
            get: {
                guard let idx = selectedStepIndex, session.steps.indices.contains(idx) else { return nil }
                return StepIndexWrapper(index: idx)
            },
            set: { wrapper in
                selectedStepIndex = wrapper?.index
            }
        )
    }

    // MARK: - Spec Progress Header

    private var specProgressHeader: some View {
        HStack(spacing: 6) {
            Text("SPEC PROGRESS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textMuted)

            Spacer()

            Text("\(specState.completedCount) / \(specState.totalCount)")
                .font(Theme.code(12, weight: .bold))
                .foregroundStyle(stateColor)

            // Pause button
            if session.buildState == .building {
                Button {
                    session.buildState = .paused
                } label: {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            } else if session.buildState == .paused {
                Button {
                    session.buildState = .building
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - State Color

    private var stateColor: Color {
        switch session.buildState {
        case .ready:    return Theme.textMuted
        case .building: return Theme.builder
        case .paused:   return Theme.warning
        case .done:     return Theme.success
        case .failed:   return Theme.error
        }
    }

    // MARK: - Spec Task Row

    @ViewBuilder
    private func specTaskRow(_ task: SpecTask, at index: Int) -> some View {
        let isActive = index == session.activeStepIndex
        let step = session.steps.indices.contains(index) ? session.steps[index] : nil

        VStack(alignment: .leading, spacing: 0) {
            // Main task row
            HStack(spacing: 8) {
                taskIndicator(task: task, step: step, isActive: isActive)

                Text(task.title)
                    .font(Theme.body(12))
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundStyle(taskTextColor(task: task, isActive: isActive))
                    .strikethrough(task.isCompleted, color: Theme.textMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                // Sub-task count for active step
                if isActive, let step, !step.subTasks.isEmpty {
                    Text("\(step.subTasksDone)/\(step.subTasksTotal)")
                        .font(Theme.code(10))
                        .foregroundStyle(Theme.builder)
                }

                // Failed attempt count
                if let step, step.state == .failed {
                    Text("×\(step.attemptCount)")
                        .font(Theme.caption(10))
                        .foregroundStyle(Theme.error.opacity(0.7))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isActive
                    ? RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.builder.opacity(0.08))
                    : nil
            )

            // Sub-tasks expanded under active step
            if isActive, let step, !step.subTasks.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(step.subTasks) { subTask in
                        subTaskRow(subTask)
                    }
                }
                .padding(.leading, 28)
                .padding(.trailing, 10)
                .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Task Indicator Icon

    @ViewBuilder
    private func taskIndicator(task: SpecTask, step: BuildStep?, isActive: Bool) -> some View {
        if task.isCompleted || step?.state == .done {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.success)
        } else if step?.state == .failed {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.error)
        } else if step?.state == .skipped {
            Image(systemName: "forward.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textMuted)
        } else if isActive {
            Circle()
                .fill(Theme.builder)
                .frame(width: 8, height: 8)
                .modifier(PulsingDot())
                .frame(width: 12) // align with checkmark width
        } else {
            Circle()
                .strokeBorder(Theme.textMuted.opacity(0.5), lineWidth: 1)
                .frame(width: 12, height: 12)
        }
    }

    private func taskTextColor(task: SpecTask, isActive: Bool) -> Color {
        if task.isCompleted { return Theme.textMuted }
        if isActive { return Theme.textPrimary }
        return Theme.textSecondary
    }

    // MARK: - Sub-Task Row

    private func subTaskRow(_ subTask: BuildSubTask) -> some View {
        HStack(spacing: 6) {
            // State dot
            switch subTask.state {
            case .done:
                Circle()
                    .fill(Theme.success)
                    .frame(width: 6, height: 6)
            case .building:
                Circle()
                    .fill(Theme.builder)
                    .frame(width: 6, height: 6)
                    .modifier(PulsingDot())
            case .failed:
                Circle()
                    .fill(Theme.error)
                    .frame(width: 6, height: 6)
            default:
                Circle()
                    .fill(Theme.textMuted.opacity(0.3))
                    .frame(width: 6, height: 6)
            }

            Text(subTask.title)
                .font(Theme.body(11))
                .foregroundStyle(subTaskTextColor(subTask.state))
                .strikethrough(subTask.state == .done)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            subTask.state == .building
                ? RoundedRectangle(cornerRadius: 3).fill(Theme.builder.opacity(0.06))
                : nil
        )
    }

    private func subTaskTextColor(_ state: StepState) -> Color {
        switch state {
        case .done:     return Theme.textMuted
        case .building: return Theme.textPrimary
        case .failed:   return Theme.error
        default:        return Theme.textMuted
        }
    }
}
