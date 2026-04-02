import SwiftUI

// MARK: - Progress Bar Size

enum ProgressBarSize {
    case mini      // 6pt — task cards, inline
    case standard  // 10pt — active step card
    case large     // 16pt — spec bar

    var height: CGFloat {
        switch self {
        case .mini: return 6
        case .standard: return 10
        case .large: return 16
        }
    }

    var gap: CGFloat {
        switch self {
        case .mini: return 1
        case .standard: return 2
        case .large: return 2
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .mini: return 3
        case .standard: return 5
        case .large: return 8
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
        .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius))
    }

    @ViewBuilder
    private func segmentView(for step: BuildStep, at index: Int) -> some View {
        let color = color(for: step.state)

        Rectangle()
            .fill(color)
            .overlay {
                if step.state == .building {
                    PulsingOverlay()
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onSegmentTap?(index)
            }
    }

    private func color(for state: StepState) -> Color {
        switch state {
        case .done:     return Theme.success
        case .building: return Theme.builder
        case .queued:   return Theme.textMuted.opacity(0.3)
        case .failed:   return Theme.error
        case .skipped:  return Theme.textMuted.opacity(0.15)
        }
    }
}

// MARK: - Pulsing Overlay (building state animation)

private struct PulsingOverlay: View {
    @State private var isPulsing = false

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(isPulsing ? 0.15 : 0))
            .animation(
                .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

// MARK: - Preview

#Preview("SpecProgressBar Sizes") {
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
        Text("Mini (6pt)").font(Theme.caption(11)).foregroundStyle(Theme.textSecondary)
        SpecProgressBar(steps: steps, size: .mini)
            .frame(width: 200)

        Text("Standard (10pt)").font(Theme.caption(11)).foregroundStyle(Theme.textSecondary)
        SpecProgressBar(steps: steps, size: .standard)
            .frame(width: 300)

        Text("Large (16pt)").font(Theme.caption(11)).foregroundStyle(Theme.textSecondary)
        SpecProgressBar(steps: steps, size: .large)
            .frame(width: 400)
    }
    .padding(24)
    .background(Theme.contentBg)
}
