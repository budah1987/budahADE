import SwiftUI

// MARK: - Chat Turn Scrubber

/// Vertical timeline of user message markers on the right edge of a chat view.
/// Shared across plan and builder wrappers.
///
/// - Markers represent user messages only
/// - Hover reveals message preview tooltip to the left
/// - Click scrolls to that message via the provided callback
/// - Active marker is highlighted, others dim on hover
/// - Container: semi-transparent glassmorphic strip
struct ChatTurnScrubber: View {
    let markers: [ChatTurnMarker]
    var activeMessageId: UUID? = nil
    var stepColorProvider: ((Int?) -> Color)? = nil
    var onMarkerTap: ((UUID) -> Void)? = nil

    @State private var hoveredMarkerId: UUID? = nil

    var body: some View {
        VStack(spacing: 3) {
            ForEach(markers) { marker in
                let isActive = marker.messageId == activeMessageId
                let isHovered = marker.messageId == hoveredMarkerId
                let baseColor = stepColorProvider?(marker.stepIndex) ?? Color.white
                let anyHovered = hoveredMarkerId != nil
                let dimmed = anyHovered && !isHovered && !isActive

                MarkerDash(
                    isActive: isActive,
                    isHovered: isHovered,
                    dimmed: dimmed,
                    color: baseColor
                )
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        hoveredMarkerId = hovering ? marker.messageId : nil
                    }
                }
                .onTapGesture {
                    onMarkerTap?(marker.messageId)
                }
                .popover(isPresented: Binding(
                    get: { hoveredMarkerId == marker.messageId },
                    set: { if !$0 { hoveredMarkerId = nil } }
                ), arrowEdge: .leading) {
                    Text(marker.fullText.prefix(150) + (marker.fullText.count > 150 ? "..." : ""))
                        .font(.custom("Geist-Regular", size: 11))
                        .foregroundStyle(Color.white)
                        .padding(12)
                        .frame(width: 200, alignment: .leading)
                        .background(Color(hex: 0x1c1f25).opacity(0.5))
                        .background(.ultraThinMaterial)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(hex: 0x1c1f25).opacity(0.5))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}

// MARK: - Marker Dash

private struct MarkerDash: View {
    let isActive: Bool
    let isHovered: Bool
    let dimmed: Bool
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.white.opacity(dashOpacity))
            .frame(width: 12, height: 2)
            .frame(width: 16, height: 14)
            .shadow(color: isHovered ? color.opacity(0.6) : .clear, radius: 4)
            .contentShape(Rectangle())
    }

    private var dashOpacity: Double {
        if isActive { return 0.95 }
        if isHovered { return 0.9 }
        if dimmed { return 0.2 }
        return 0.5
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
