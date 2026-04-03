import SwiftUI

// MARK: - Active Step Card

/// Purple-bordered card showing the currently building step with sub-tasks and mini progress.
struct ActiveStepCard: View {
    let step: BuildStep
    let stepNumber: Int
    let totalSteps: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: purple dot + title + sub-progress
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.Colors.statusWorking)
                    .frame(width: 8, height: 8)

                Text(step.title)
                    .font(Theme.label(12))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)

                Spacer()

                if !step.subTasks.isEmpty {
                    Text("\(step.subTasksDone)/\(step.subTasksTotal)")
                        .font(Theme.code(10))
                        .foregroundStyle(Theme.Colors.statusWorking)
                }
            }

            // Mini progress bar for sub-tasks
            if !step.subTasks.isEmpty {
                subTaskProgressBar
            }

            // Sub-task list
            if !step.subTasks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(step.subTasks) { subTask in
                        SubTaskRow(subTask: subTask)
                    }
                }
            }

            // Current activity
            if let activity = currentActivity(for: step) {
                Text(activity)
                    .font(Theme.caption(10))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .italic()
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(Theme.Colors.statusWorking.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .strokeBorder(Theme.Colors.statusWorking, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    // MARK: - Sub-task progress (mini bar using sub-task states)

    private var subTaskProgressBar: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(step.subTasks) { subTask in
                    Rectangle()
                        .fill(subTaskColor(subTask.state))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 4)
    }

    private func subTaskColor(_ state: StepState) -> Color {
        switch state {
        case .done:     return Theme.Colors.statusDone
        case .building: return Theme.Colors.statusWorking
        case .queued:   return Theme.Colors.textTertiary.opacity(0.3)
        case .failed:   return Theme.Colors.error
        case .skipped:  return Theme.Colors.textTertiary.opacity(0.15)
        }
    }

    private func currentActivity(for step: BuildStep) -> String? {
        guard step.state == .building else { return nil }
        if let active = step.subTasks.first(where: { $0.state == .building }) {
            return "Working on: \(active.title)"
        }
        return nil
    }
}

// MARK: - Sub-Task Row

private struct SubTaskRow: View {
    let subTask: BuildSubTask

    var body: some View {
        HStack(spacing: 6) {
            stateIndicator
            Text(subTask.title)
                .font(Theme.body(11))
                .foregroundStyle(textColor)
                .strikethrough(subTask.state == .done)
                .lineLimit(1)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .background(subTask.state == .building ? Theme.Colors.statusWorking.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch subTask.state {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.Colors.statusDone)
        case .building:
            Circle()
                .fill(Theme.Colors.statusWorking)
                .frame(width: 6, height: 6)
        case .queued:
            Circle()
                .strokeBorder(Theme.Colors.textTertiary, lineWidth: 1)
                .frame(width: 6, height: 6)
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

    private var textColor: Color {
        switch subTask.state {
        case .done:     return Theme.Colors.textTertiary
        case .building: return Theme.Colors.textPrimary
        case .queued:   return Theme.Colors.textTertiary
        case .failed:   return Theme.Colors.error
        case .skipped:  return Theme.Colors.textTertiary
        }
    }
}
