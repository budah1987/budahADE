import SwiftUI

// MARK: - Step Detail Modal

/// Modal presented when clicking any step row.
/// Variants: done, building, queued, failed, skipped.
/// No edit mode — structural changes require re-planning.
/// "Notes for Builder" is the only additive field (queued + failed).
struct StepDetailModal: View {
    @Binding var step: BuildStep
    let stepIndex: Int
    let totalSteps: Int
    var onJumpToChat: (() -> Void)? = nil
    var onViewDiff: (() -> Void)? = nil
    var onRetry: (() -> Void)? = nil
    var onSkip: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil
    var onSave: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    stateBody
                }
                .padding(16)
            }

            Divider().opacity(0.3)
            stateActions
        }
        .frame(width: 420)
        .frame(minHeight: 280, maxHeight: 520)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            stateDot
            Text(step.title)
                .font(Theme.label(14))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2)
            Spacer()
            stateBadge
        }
        .padding(16)
    }

    @ViewBuilder
    private var stateDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 10, height: 10)
    }

    @ViewBuilder
    private var stateBadge: some View {
        Text(step.state.rawValue.uppercased())
            .font(Theme.caption(9))
            .foregroundStyle(dotColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(dotColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - State Body

    @ViewBuilder
    private var stateBody: some View {
        switch step.state {
        case .done:     doneBody
        case .building: buildingBody
        case .queued:   queuedBody
        case .failed:   failedBody
        case .skipped:  skippedBody
        }
    }

    // MARK: Done

    private var doneBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !step.description.isEmpty {
                Text(step.description)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            if !step.filesChanged.isEmpty {
                sectionLabel("Files Changed")
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(step.filesChanged, id: \.self) { file in
                        Text(file)
                            .font(Theme.code(11))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: Building

    private var buildingBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !step.description.isEmpty {
                Text(step.description)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            if !step.subTasks.isEmpty {
                sectionLabel("Sub-tasks")
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(step.subTasks) { subTask in
                        HStack(spacing: 6) {
                            subTaskIndicator(subTask.state)
                            Text(subTask.title)
                                .font(Theme.body(12))
                                .foregroundStyle(subTask.state == .building ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: Queued

    private var queuedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Position")
            Text("Step \(stepIndex + 1) of \(totalSteps)")
                .font(Theme.body(13))
                .foregroundStyle(Theme.Colors.textSecondary)

            if !step.description.isEmpty {
                sectionLabel("Description")
                Text(step.description)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            sectionLabel("Notes for Builder")
            TextEditor(text: $step.notesForBuilder)
                .font(Theme.body(13))
                .foregroundStyle(Theme.Colors.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 60, maxHeight: 120)
                .padding(8)
                .background(Theme.Colors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    Group {
                        if step.notesForBuilder.isEmpty {
                            Text("Add context for the builder agent…")
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .allowsHitTesting(false)
                                .padding(10)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    }
                )
        }
    }

    // MARK: Failed

    private var failedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !step.description.isEmpty {
                Text(step.description)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            if let error = step.error {
                sectionLabel("Error")
                Text(error)
                    .font(Theme.code(11))
                    .foregroundStyle(Theme.Colors.error)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.error.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if !step.filesChanged.isEmpty {
                sectionLabel("Files Changed")
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(step.filesChanged, id: \.self) { file in
                        Text(file)
                            .font(Theme.code(11))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }

            HStack(spacing: 4) {
                Text("Attempts:")
                    .font(Theme.caption(11))
                    .foregroundStyle(Theme.Colors.textTertiary)
                Text("\(step.attemptCount)")
                    .font(Theme.code(11))
                    .foregroundStyle(Theme.Colors.error)
            }

            sectionLabel("Notes for Builder")
            TextEditor(text: $step.notesForBuilder)
                .font(Theme.body(13))
                .foregroundStyle(Theme.Colors.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 50, maxHeight: 100)
                .padding(8)
                .background(Theme.Colors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    Group {
                        if step.notesForBuilder.isEmpty {
                            Text("Add context for retry…")
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .allowsHitTesting(false)
                                .padding(10)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    }
                )
        }
    }

    // MARK: Skipped

    private var skippedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This step was skipped.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.Colors.textTertiary)
                .italic()
        }
    }

    // MARK: - State Actions

    @ViewBuilder
    private var stateActions: some View {
        HStack(spacing: 8) {
            switch step.state {
            case .done:
                actionButton("View Diff", icon: "doc.text.magnifyingglass") { onViewDiff?(); dismiss() }
                Spacer()
                actionButton("Jump to Chat", icon: "arrow.right.circle") { onJumpToChat?(); dismiss() }

            case .building:
                Spacer()
                actionButton("Jump to Chat", icon: "arrow.right.circle") { onJumpToChat?(); dismiss() }

            case .queued:
                destructiveButton("Remove") { onRemove?(); dismiss() }
                Spacer()
                actionButton("Skip", icon: "forward.fill") { onSkip?(); dismiss() }

            case .failed:
                actionButton("Retry", icon: "arrow.clockwise") { onRetry?(); dismiss() }
                Spacer()
                actionButton("Skip", icon: "forward.fill") { onSkip?(); dismiss() }

            case .skipped:
                Spacer()
            }
        }
        .padding(12)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Theme.caption(10))
            .foregroundStyle(Theme.Colors.textTertiary)
            .tracking(0.5)
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(Theme.label(12))
            }
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.Colors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func destructiveButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.label(12))
                .foregroundStyle(Theme.Colors.error)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.Colors.error.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func subTaskIndicator(_ state: StepState) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.Colors.statusDone)
        case .building:
            Circle().fill(Theme.Colors.statusWorking).frame(width: 6, height: 6)
        case .queued:
            Circle().strokeBorder(Theme.Colors.textTertiary, lineWidth: 1).frame(width: 6, height: 6)
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.Colors.error)
        case .skipped:
            Image(systemName: "forward.fill")
                .font(.system(size: 7))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    // MARK: - Colors

    private var dotColor: Color {
        switch step.state {
        case .done:     return Theme.Colors.statusDone
        case .building: return Theme.Colors.statusWorking
        case .queued:   return Theme.Colors.textTertiary
        case .failed:   return Theme.Colors.error
        case .skipped:  return Theme.Colors.textTertiary
        }
    }

    private var borderColor: Color {
        switch step.state {
        case .building: return Theme.Colors.statusWorking.opacity(0.5)
        case .failed:   return Theme.Colors.error.opacity(0.3)
        default:        return Theme.Colors.borderLight
        }
    }
}
