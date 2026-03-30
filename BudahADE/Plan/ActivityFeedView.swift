import SwiftUI

struct ActivityFeedView: View {
    let activityFeed: [ActivityFeedEntry]
    let isThinking: Bool
    let startDate: Date?

    private let maxVisible = 4

    private static let brailleFrames: [String] = [
        "\u{280B}", "\u{2819}", "\u{2839}", "\u{2838}",
        "\u{283C}", "\u{2834}", "\u{2826}", "\u{2827}",
        "\u{2807}", "\u{280F}"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Activity entries — last 4
            ForEach(visibleEntries) { entry in
                activityRow(entry)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
            }

            // Braille spinner + elapsed timer
            HStack(spacing: 8) {
                TimelineView(.animation(minimumInterval: 0.08)) { timeline in
                    let idx = Int(timeline.date.timeIntervalSinceReferenceDate / 0.08) % Self.brailleFrames.count
                    Text(Self.brailleFrames[idx])
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                }

                if let startDate {
                    TimelineView(.animation(minimumInterval: 0.1)) { timeline in
                        let elapsed = timeline.date.timeIntervalSince(startDate)
                        Text(String(format: "%.1fs", elapsed))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Theme.textMuted)
                    }
                }

                Spacer()
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .animation(.easeOut(duration: 0.25), value: activityFeed.count)
    }

    private var visibleEntries: [ActivityFeedEntry] {
        if activityFeed.isEmpty && isThinking {
            return [ActivityFeedEntry(
                id: "thinking-placeholder",
                kind: .thinking,
                label: "Reasoning...",
                detail: nil,
                timestamp: Date(),
                status: .inProgress
            )]
        }
        return Array(activityFeed.suffix(maxVisible))
    }

    private func activityRow(_ entry: ActivityFeedEntry) -> some View {
        HStack(spacing: 6) {
            statusIcon(entry.status, kind: entry.kind)

            Text(entry.label)
                .font(Theme.mono(12))
                .foregroundColor(foregroundColor(for: entry))
                .lineLimit(1)

            Spacer()

            if let detail = entry.detail {
                Text(detail)
                    .font(Theme.mono(10))
                    .foregroundColor(Theme.textMuted)
                    .lineLimit(1)
            }
        }
        .frame(height: 22)
    }

    @ViewBuilder
    private func statusIcon(_ status: ActivityFeedEntry.ActivityStatus, kind: ActivityKind) -> some View {
        switch status {
        case .inProgress:
            Circle()
                .fill(kind == .rateLimit ? Color.orange : Theme.accent)
                .frame(width: 5, height: 5)
                .modifier(PulseModifier())

        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(Theme.textMuted)
                .frame(width: 12)

        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.red.opacity(0.7))
                .frame(width: 12)
        }
    }

    private func foregroundColor(for entry: ActivityFeedEntry) -> Color {
        switch entry.status {
        case .inProgress:
            return entry.kind == .rateLimit ? .orange : Theme.textPrimary
        case .completed:
            return Theme.textMuted.opacity(0.5)
        case .failed:
            return Color.red.opacity(0.7)
        }
    }
}

// MARK: - Pulse Animation

private struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
