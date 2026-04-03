import SwiftUI

// MARK: - Chat Turn Scrubber

/// Vertical timeline of user message markers on the right edge of a chat view.
/// Shared across plan and builder wrappers.
///
/// - Markers represent user messages only
/// - Hover shows full message preview tooltip
/// - Click scrolls to that message via the provided callback
/// - Active marker (nearest to current scroll position) is highlighted
struct ChatTurnScrubber: View {
    let markers: [ChatTurnMarker]
    var activeMessageId: UUID? = nil
    var stepColorProvider: ((Int?) -> Color)? = nil
    var onMarkerTap: ((UUID) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            ForEach(markers) { marker in
                MarkerDash(
                    marker: marker,
                    isActive: marker.messageId == activeMessageId,
                    color: stepColorProvider?(marker.stepIndex) ?? Theme.Colors.textTertiary
                )
                .onTapGesture {
                    onMarkerTap?(marker.messageId)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 20)
        .padding(.vertical, 8)
    }
}

// MARK: - Marker Dash

private struct MarkerDash: View {
    let marker: ChatTurnMarker
    let isActive: Bool
    let color: Color

    @State private var isHovering = false

    var body: some View {
        Rectangle()
            .fill(isActive ? Theme.Colors.textPrimary : color)
            .frame(width: isActive ? 12 : 8, height: isActive ? 3 : 2)
            .frame(width: 20, height: 16)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
            }
            .popover(isPresented: $isHovering, arrowEdge: .leading) {
                Text(marker.fullText.prefix(100) + (marker.fullText.count > 100 ? "..." : ""))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(8)
                    .frame(maxWidth: 240, alignment: .leading)
                    .background(Theme.Colors.surface)
            }
    }
}

// MARK: - Step Color Provider (builder mode)

/// Default step color provider for builder mode scrubbers
func builderStepColor(for stepIndex: Int?, steps: [BuildStep]) -> Color {
    guard let idx = stepIndex, steps.indices.contains(idx) else {
        return Theme.Colors.textTertiary
    }
    switch steps[idx].state {
    case .done:     return Theme.Colors.statusDone
    case .building: return Theme.Colors.statusWorking
    case .queued:   return Theme.Colors.textTertiary
    case .failed:   return Theme.Colors.error
    case .skipped:  return Theme.Colors.textTertiary.opacity(0.5)
    }
}
