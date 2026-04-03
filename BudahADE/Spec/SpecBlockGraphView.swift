import SwiftUI

/// Horizontal row of fixed-width blocks — one per spec item.
/// Colors: dim (pending), pulsing accent (active), green (done), red (blocked).
/// Sits between the spec progress header and task checklist.
struct SpecBlockGraphView: View {
    @ObservedObject var specState: SpecState
    @ObservedObject var buildStatus: BuildStatusState

    var body: some View {
        let tasks = specState.activeSpec?.tasks ?? []
        if !tasks.isEmpty {
            let completedCount = tasks.filter(\.isCompleted).count
            let percentage = Int((Double(completedCount) / Double(tasks.count)) * 100)

            HStack(spacing: 2) {
                HStack(spacing: 2) {
                    ForEach(tasks) { task in
                        blockView(for: task)
                    }
                }

                Spacer(minLength: 8)

                Text("\(percentage)%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(
                        completedCount == tasks.count ? Theme.Colors.statusDone : Theme.Colors.textSecondary
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func blockView(for task: SpecTask) -> some View {
        let state = blockState(for: task)

        RoundedRectangle(cornerRadius: 1.5)
            .fill(state.color)
            .frame(width: 8, height: 14)
            .modifier(PulsingBlockModifier(enabled: state == .active))
            .help(tooltipText(for: task))
    }

    private func tooltipText(for task: SpecTask) -> String {
        if let sectionId = task.sectionId {
            return "\(sectionId) — \(task.title)"
        }
        return task.title
    }

    // MARK: - Block State

    private enum BlockState: Equatable {
        case completed
        case active
        case blocked
        case pending

        var color: Color {
            switch self {
            case .completed: return Theme.Colors.statusDone
            case .active:    return Theme.Colors.accent
            case .blocked:   return Color(hex: 0xE06C75)
            case .pending:   return Color.white.opacity(0.1)
            }
        }
    }

    private func blockState(for task: SpecTask) -> BlockState {
        if task.isCompleted { return .completed }

        // Check if this is the actively building task
        let isActiveTask: Bool
        if let buildIndex = buildStatus.currentTaskIndex {
            isActiveTask = task.id == buildIndex
        } else {
            isActiveTask = task.id == specState.activeSpec?.tasks.first(where: { !$0.isCompleted })?.id
        }

        if isActiveTask {
            if buildStatus.status == .blocked { return .blocked }
            if buildStatus.status == .working { return .active }
        }

        return .pending
    }
}

// MARK: - Pulsing Block Modifier

private struct PulsingBlockModifier: ViewModifier {
    var enabled: Bool
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(enabled && isPulsing ? 0.4 : 1.0)
            .animation(
                enabled
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onAppear {
                if enabled { isPulsing = true }
            }
            .onChange(of: enabled) { _, newValue in
                if newValue {
                    isPulsing = true
                } else {
                    isPulsing = false
                }
            }
    }
}
