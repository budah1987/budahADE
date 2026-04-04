import SwiftUI

// MARK: - Side Panel Display Mode

enum SidePanelMode: Equatable {
    case hidden     // not shown at all (pre-build)
    case collapsed  // icon rail (~36px) — state dots only
    case expanded   // full panel (~260px) — accordion steps
}

// MARK: - Builder Side Panel

/// Left-side step panel for the builder. Shows accordion sections per step,
/// with state dots, sub-task progress, and sub-agent cards.
/// Toggles between expanded (~260px) and collapsed icon rail (~36px).
struct BuilderSidePanel: View {
    @Bindable var session: BuilderSession
    var mode: SidePanelMode
    var onToggle: () -> Void
    var onStepTap: (Int) -> Void

    // Track which accordion sections are expanded
    @State private var expandedSteps: Set<String> = []

    var body: some View {
        Group {
            switch mode {
            case .hidden:
                EmptyView()
            case .collapsed:
                collapsedRail
            case .expanded:
                expandedPanel
            }
        }
        .animation(.easeInOut(duration: 0.2), value: mode)
    }

    // MARK: - Collapsed Icon Rail

    private var collapsedRail: some View {
        VStack(spacing: 0) {
            // Toggle button at top
            Button(action: onToggle) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(width: 36, height: 32)
            }
            .buttonStyle(.plain)

            // Progress fraction
            Text("\(session.completedCount)/\(session.totalCount)")
                .font(Theme.code(9))
                .foregroundStyle(stepStateColor)
                .padding(.bottom, 8)

            // State dots — one per step
            VStack(spacing: 6) {
                ForEach(Array(session.steps.enumerated()), id: \.element.id) { index, step in
                    railDot(step: step, index: index)
                }
            }
            .padding(.horizontal, 8)

            Spacer()
        }
        .frame(width: 36)
        .background(Theme.Colors.surface)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.Colors.borderSubtle).frame(width: 0.5)
        }
    }

    private func railDot(step: BuildStep, index: Int) -> some View {
        Button {
            onStepTap(index)
        } label: {
            Group {
                switch step.state {
                case .done:
                    Circle()
                        .fill(Theme.Colors.statusDone)
                        .frame(width: 6, height: 6)
                case .building:
                    Circle()
                        .fill(Theme.Colors.statusWorking)
                        .frame(width: 6, height: 6)
                        .modifier(PulsingDotModifier())
                case .failed:
                    Circle()
                        .fill(Theme.Colors.error)
                        .frame(width: 6, height: 6)
                case .queued:
                    Circle()
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                        .frame(width: 6, height: 6)
                case .skipped:
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(width: 20, height: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(step.title)
    }

    // MARK: - Expanded Panel

    private var expandedPanel: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider().opacity(0.3)
            stepList
            Spacer(minLength: 0)
        }
        .frame(width: 260)
        .background(Theme.Colors.surface)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.Colors.borderSubtle).frame(width: 0.5)
        }
    }

    // MARK: - Panel Header

    private var panelHeader: some View {
        HStack(spacing: 8) {
            // State dot
            Circle()
                .fill(stepStateColor)
                .frame(width: 6, height: 6)
                .modifier(PulsingDotModifier())
                .opacity(session.buildState == .building ? 1 : 0)
                .overlay {
                    if session.buildState != .building {
                        Circle().fill(stepStateColor).frame(width: 6, height: 6)
                    }
                }

            // Progress fraction
            Text("\(session.completedCount)/\(session.totalCount)")
                .font(Theme.code(11, weight: .medium))
                .foregroundStyle(stepStateColor)

            // Title
            Text("Steps")
                .font(Theme.label(11))
                .foregroundStyle(Theme.Colors.textTertiary)

            Spacer()

            // Collapse button
            Button(action: onToggle) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(width: 22, height: 22)
                    .background(Theme.Colors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
    }

    // MARK: - Step List (Accordion)

    private var stepList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(session.steps.enumerated()), id: \.element.id) { index, step in
                        accordionSection(step: step, index: index)
                            .id(step.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: session.activeStepIndex) { _, newIndex in
                guard let idx = newIndex, session.steps.indices.contains(idx) else { return }
                // Auto-expand the active step
                expandedSteps.insert(session.steps[idx].id)
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(session.steps[idx].id, anchor: .center)
                }
            }
        }
    }

    // MARK: - Accordion Section

    private func accordionSection(step: BuildStep, index: Int) -> some View {
        let isActive = index == session.activeStepIndex
        let isExpanded = expandedSteps.contains(step.id) || isActive

        return VStack(alignment: .leading, spacing: 0) {
            // Accordion header row
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if expandedSteps.contains(step.id) {
                        expandedSteps.remove(step.id)
                    } else {
                        expandedSteps.insert(step.id)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    // Chevron
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.2))
                        .frame(width: 10)

                    // State indicator
                    stepIndicator(state: step.state, isActive: isActive)

                    // Title
                    Text(step.title)
                        .font(Theme.body(11))
                        .fontWeight(isActive ? .semibold : .regular)
                        .foregroundStyle(
                            step.state == .done ? Color.white.opacity(0.3) :
                            isActive ? Color.white.opacity(0.85) :
                            Color.white.opacity(0.45)
                        )
                        .strikethrough(step.state == .done, color: Color.white.opacity(0.15))
                        .lineLimit(1)

                    Spacer()

                    // Sub-task count
                    if !step.subTasks.isEmpty {
                        Text("\(step.subTasksDone)/\(step.subTasksTotal)")
                            .font(Theme.code(9))
                            .foregroundStyle(
                                isActive ? Theme.Colors.statusWorking :
                                step.state == .done ? Theme.Colors.statusDone.opacity(0.5) :
                                Theme.Colors.textTertiary
                            )
                    }

                    // Failed badge
                    if step.state == .failed {
                        Text("\u{00D7}\(step.attemptCount)")
                            .font(Theme.caption(9))
                            .foregroundStyle(Theme.Colors.error.opacity(0.7))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isActive
                        ? RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(hex: 0xA78BFA).opacity(0.05))
                            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Color(hex: 0xA78BFA).opacity(0.12), lineWidth: 1))
                        : nil
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("View Details") { onStepTap(index) }
                if step.state == .building || isActive {
                    Button("Pause Build") { /* wired by parent */ }
                }
                if step.state == .queued {
                    Button("Skip Step") { session.skipStep(at: index) }
                }
            }

            // Expanded content: sub-tasks
            if isExpanded && !step.subTasks.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(step.subTasks) { subTask in
                        HStack(spacing: 6) {
                            subTaskIndicator(state: subTask.state)
                            Text(subTask.title)
                                .font(Theme.body(10))
                                .foregroundStyle(
                                    subTask.state == .done ? Color.white.opacity(0.2) :
                                    subTask.state == .building ? Color.white.opacity(0.7) :
                                    Color.white.opacity(0.3)
                                )
                                .strikethrough(subTask.state == .done, color: Color.white.opacity(0.12))
                                .lineLimit(2)
                        }
                        .padding(.leading, 30)
                        .padding(.trailing, 12)
                        .padding(.vertical, 3)
                    }
                }
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Indicators

    @ViewBuilder
    private func stepIndicator(state: StepState, isActive: Bool) -> some View {
        switch state {
        case .done:
            Text("\u{2713}")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.Colors.statusDone)
                .frame(width: 12)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(Theme.Colors.error)
                .frame(width: 12)
        case .skipped:
            Image(systemName: "forward.fill")
                .font(.system(size: 7))
                .foregroundStyle(Color.white.opacity(0.2))
                .frame(width: 12)
        case .building:
            Circle()
                .fill(Theme.Colors.statusWorking)
                .frame(width: 5, height: 5)
                .modifier(PulsingDotModifier())
                .frame(width: 12)
        case .queued:
            Circle()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                .frame(width: 6, height: 6)
                .frame(width: 12)
        }
    }

    @ViewBuilder
    private func subTaskIndicator(state: StepState) -> some View {
        switch state {
        case .done:
            Text("\u{2713}")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Theme.Colors.statusDone.opacity(0.6))
                .frame(width: 10)
        case .building:
            Circle()
                .fill(Theme.Colors.statusWorking)
                .frame(width: 3, height: 3)
                .modifier(PulsingDotModifier())
                .frame(width: 10)
        default:
            Circle()
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                .frame(width: 4, height: 4)
                .frame(width: 10)
        }
    }

    // MARK: - Helpers

    private var stepStateColor: Color {
        switch session.buildState {
        case .ready:    return Theme.Colors.textTertiary
        case .building: return Theme.Colors.statusWorking
        case .paused:   return Theme.Colors.warning
        case .done:     return Theme.Colors.statusDone
        case .failed:   return Theme.Colors.error
        }
    }
}

// MARK: - Pulsing Dot Modifier

private struct PulsingDotModifier: ViewModifier {
    @State private var isPulsing = false
    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
