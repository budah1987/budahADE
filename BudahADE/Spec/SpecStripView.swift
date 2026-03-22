import SwiftUI

/// Compact spec progress strip for the task rail
struct SpecStripView: View {
    @ObservedObject var specState: SpecState

    var body: some View {
        if specState.hasSpec {
            VStack(alignment: .leading, spacing: 4) {
                // Title + progress count
                HStack {
                    Text(specState.result?.title ?? "Spec")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(specState.completedCount)/\(specState.totalCount)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.textMuted)
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 3)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(progressColor)
                            .frame(width: geo.size.width * specState.progress, height: 3)
                            .animation(.easeOut(duration: 0.3), value: specState.progress)
                    }
                }
                .frame(height: 3)

                // Current task
                if let current = specState.currentTaskTitle {
                    Text(current)
                        .font(.system(size: 9))
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }

    private var progressColor: Color {
        if specState.progress >= 1.0 {
            return Theme.success
        }
        return Theme.accent
    }
}
