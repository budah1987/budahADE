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

            // Collapsed section summaries — one per step
            VStack(spacing: 2) {
                ForEach(Array(session.steps.enumerated()), id: \.element.id) { index, step in
                    collapsedSectionRow(step: step, index: index)
                }
            }
            .padding(.horizontal, 4)

            Spacer()
        }
        .frame(width: 36)
        .background(Theme.Colors.surface)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.Colors.borderSubtle).frame(width: 0.5)
        }
    }

    /// Collapsed row: state dot + mini bar graph + fraction
    private func collapsedSectionRow(step: BuildStep, index: Int) -> some View {
        let isActive = index == session.activeStepIndex

        return Button {
            onStepTap(index)
        } label: {
            VStack(spacing: 2) {
                // State dot
                stepDot(state: step.state, isActive: isActive)

                // Mini bar graph if has subtasks
                if !step.subTasks.isEmpty {
                    miniBarGraph(done: step.subTasksDone, total: step.subTasksTotal, isActive: isActive)
                }
            }
            .frame(width: 28, height: step.subTasks.isEmpty ? 16 : 28)
            .background(
                isActive
                    ? RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(hex: 0xA78BFA).opacity(0.12))
                    : nil
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(step.title)
    }

    private func stepDot(state: StepState, isActive: Bool) -> some View {
        Group {
            switch state {
            case .done:
                Circle().fill(Theme.Colors.statusDone).frame(width: 6, height: 6)
            case .building:
                Circle().fill(Theme.Colors.statusWorking).frame(width: 6, height: 6)
            case .failed:
                Circle().fill(Theme.Colors.error).frame(width: 6, height: 6)
            case .queued:
                Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1).frame(width: 6, height: 6)
            case .skipped:
                Circle().fill(Color.white.opacity(0.1)).frame(width: 6, height: 6)
            }
        }
    }

    /// Tiny vertical bars: filled = done, empty = remaining
    private func miniBarGraph(done: Int, total: Int, isActive: Bool) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<min(total, 8), id: \.self) { i in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(i < done
                        ? (isActive ? Color(hex: 0xA78BFA) : Theme.Colors.statusDone.opacity(0.6))
                        : Color.white.opacity(0.1))
                    .frame(width: 2, height: 6)
            }
        }
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
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(session.steps.enumerated()), id: \.element.id) { index, step in
                        accordionSection(step: step, index: index)
                            .id(step.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: session.activeStepIndex) { _, newIndex in
                guard let idx = newIndex, session.steps.indices.contains(idx) else { return }
                expandedSteps.insert(session.steps[idx].id)
                withAnimation(.easeOut(duration: 0.15)) {
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
            accordionHeader(step: step, index: index, isActive: isActive, isExpanded: isExpanded)

            if isExpanded && !step.subTasks.isEmpty {
                accordionSubTasks(step: step, isActive: isActive)
            }
        }
        .background(accordionBackground(isActive: isActive))
        .padding(.horizontal, 4)
    }

    private func accordionHeader(step: BuildStep, index: Int, isActive: Bool, isExpanded: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if expandedSteps.contains(step.id) {
                    expandedSteps.remove(step.id)
                } else {
                    expandedSteps.insert(step.id)
                }
            }
        } label: {
            HStack(spacing: 7) {
                stepIndicator(state: step.state, isActive: isActive)

                Text(step.title)
                    .font(Theme.body(11))
                    .fontWeight(isActive ? .medium : .regular)
                    .foregroundStyle(titleColor(state: step.state, isActive: isActive))
                    .lineLimit(1)

                Spacer()

                accordionTrailing(step: step, isActive: isActive, isExpanded: isExpanded)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, isActive ? 8 : 6)
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
    }

    @ViewBuilder
    private func accordionTrailing(step: BuildStep, isActive: Bool, isExpanded: Bool) -> some View {
        if !step.subTasks.isEmpty && !isExpanded {
            HStack(spacing: 4) {
                inlineBarGraph(done: step.subTasksDone, total: step.subTasksTotal, isActive: isActive)
                Text("\(step.subTasksDone)/\(step.subTasksTotal)")
                    .font(Theme.code(9))
                    .foregroundStyle(fractionColor(state: step.state, isActive: isActive))
            }
        } else if !step.subTasks.isEmpty {
            Text("\(step.subTasksDone)/\(step.subTasksTotal)")
                .font(Theme.code(9))
                .foregroundStyle(fractionColor(state: step.state, isActive: isActive))
        }

        if step.state == .failed {
            Text("\u{00D7}\(step.attemptCount)")
                .font(Theme.code(9, weight: .medium))
                .foregroundStyle(Theme.Colors.error)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Theme.Colors.error.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }

        if !step.subTasks.isEmpty {
            Image(systemName: "chevron.right")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(isActive ? Color.white.opacity(0.4) : Color.white.opacity(0.15))
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 10)
        }
    }

    private func accordionSubTasks(step: BuildStep, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(step.subTasks) { subTask in
                HStack(spacing: 6) {
                    subTaskIndicator(state: subTask.state)
                    Text(subTask.title)
                        .font(Theme.body(10))
                        .foregroundStyle(subTaskColor(state: subTask.state, isActive: isActive))
                        .lineLimit(2)
                }
                .padding(.leading, 28)
                .padding(.trailing, 12)
                .padding(.vertical, 3)
            }
        }
        .padding(.bottom, 4)
        .transition(.opacity)
    }

    @ViewBuilder
    private func accordionBackground(isActive: Bool) -> some View {
        if isActive {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(hex: 0xA78BFA).opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color(hex: 0xA78BFA).opacity(0.18), lineWidth: 1)
                )
        }
    }

    // MARK: - Color Helpers

    private func titleColor(state: StepState, isActive: Bool) -> Color {
        if isActive { return .white }
        switch state {
        case .done: return .white.opacity(0.35)
        case .failed: return Theme.Colors.error.opacity(0.85)
        default: return .white.opacity(0.5)
        }
    }

    private func fractionColor(state: StepState, isActive: Bool) -> Color {
        if isActive { return .white.opacity(0.7) }
        if state == .done { return Theme.Colors.statusDone.opacity(0.5) }
        return Theme.Colors.textTertiary
    }

    private func subTaskColor(state: StepState, isActive: Bool) -> Color {
        if isActive {
            switch state {
            case .done: return .white.opacity(0.5)
            case .building: return .white
            default: return .white.opacity(0.6)
            }
        } else {
            switch state {
            case .done: return .white.opacity(0.25)
            case .building: return .white.opacity(0.75)
            default: return .white.opacity(0.35)
            }
        }
    }

    /// Inline bar graph for collapsed accordion headers
    private func inlineBarGraph(done: Int, total: Int, isActive: Bool) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<min(total, 10), id: \.self) { i in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(i < done
                        ? (isActive ? Color.white.opacity(0.6) : Theme.Colors.statusDone.opacity(0.5))
                        : Color.white.opacity(0.08))
                    .frame(width: 2, height: 8)
            }
        }
    }

    // MARK: - Indicators

    @ViewBuilder
    private func stepIndicator(state: StepState, isActive: Bool) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Colors.statusDone.opacity(0.7))
                .frame(width: 16)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.error)
                .frame(width: 16)
        case .skipped:
            Image(systemName: "forward.circle")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.2))
                .frame(width: 16)
        case .building:
            Circle()
                .fill(Theme.Colors.statusWorking)
                .frame(width: 7, height: 7)
                .frame(width: 16)
        case .queued:
            Circle()
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                .frame(width: 8, height: 8)
                .frame(width: 16)
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
