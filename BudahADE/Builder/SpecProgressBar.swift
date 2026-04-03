import SwiftUI

// MARK: - Progress Bar Size

enum ProgressBarSize {
    case mini      // thin bar graph — spec bar, task cards, panels
    case standard  // same height, slightly more gap
    case large     // same height, legacy alias

    var height: CGFloat { 4 }

    var gap: CGFloat {
        switch self {
        case .mini: return 1
        case .standard, .large: return 2
        }
    }
}

// MARK: - Spec Progress Bar

struct SpecProgressBar: View {
    let steps: [BuildStep]
    var size: ProgressBarSize = .standard
    var onSegmentTap: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: size.gap) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                segmentView(for: step, at: index)
            }
        }
        .frame(height: size.height)
    }

    @ViewBuilder
    private func segmentView(for step: BuildStep, at index: Int) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(color(for: step.state))
            .overlay {
                if step.state == .building {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(0))
                        .modifier(PulsingSegment())
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onSegmentTap?(index)
            }
    }

    private func color(for state: StepState) -> Color {
        switch state {
        case .done:     return Theme.Colors.statusDone                  // #4ADE80 bright green
        case .building: return Theme.Colors.statusWorking                // #A78BFA bright violet
        case .queued:   return Color.white.opacity(0.078)      // #FFFFFF14
        case .failed:   return Theme.Colors.error
        case .skipped:  return Color.white.opacity(0.05)
        }
    }
}

// MARK: - Pulsing Segment (building state animation)

private struct PulsingSegment: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(isPulsing ? 0.18 : 0))
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isPulsing)
            )
            .onAppear { isPulsing = true }
    }
}

// MARK: - Preview

#Preview("SpecProgressBar") {
    let steps: [BuildStep] = [
        BuildStep(id: "1", title: "Setup project", state: .done),
        BuildStep(id: "2", title: "Create models", state: .done),
        BuildStep(id: "3", title: "Build views", state: .done),
        BuildStep(id: "4", title: "Write tests", state: .building),
        BuildStep(id: "5", title: "Add networking", state: .queued),
        BuildStep(id: "6", title: "Polish UI", state: .queued),
        BuildStep(id: "7", title: "Documentation", state: .queued),
        BuildStep(id: "8", title: "Deploy", state: .failed),
    ]

    VStack(alignment: .leading, spacing: 20) {
        Text("Mini (4px, 1px gap)").font(Theme.caption(11)).foregroundStyle(Theme.Colors.textSecondary)
        SpecProgressBar(steps: steps, size: .mini).frame(width: 200)

        Text("Standard (4px, 2px gap)").font(Theme.caption(11)).foregroundStyle(Theme.Colors.textSecondary)
        SpecProgressBar(steps: steps, size: .standard).frame(width: 300)

        Text("Large (4px, 2px gap)").font(Theme.caption(11)).foregroundStyle(Theme.Colors.textSecondary)
        SpecProgressBar(steps: steps, size: .large).frame(width: 400)
    }
    .padding(24)
    .background(Theme.Colors.appBackground)
}
