import SwiftUI

// MARK: - Spec Bar (Content Area — below tab bar)

/// Persistent thin strip below the conversation tab bar.
/// Shows active step name (building) or spec title (ready), progress bar, live action text.
/// Click anywhere to toggle the builder chat view.
struct SpecBar: View {
    @Bindable var session: BuilderSession
    var specTitle: String = "Spec"
    var isBuilderTabActive: Bool = false
    /// Last streaming line from the agent — shown during active build
    var activeActionText: String? = nil
    var onTap: () -> Void

    private var displayTitle: String {
        if session.buildState == .building, let step = session.activeStep {
            return step.title
        }
        return specTitle
    }

    var body: some View {
        HStack(spacing: 6) {
            // Left content: title + count + bar + action text
            HStack(spacing: 6) {
                Text(displayTitle)
                    .font(Theme.label(11))
                    .foregroundStyle(Color(hex: 0xC4B5FD))
                    .lineLimit(1)
                    .fixedSize()

                Text("\(session.completedCount)/\(session.totalCount)")
                    .font(Theme.code(10))
                    .foregroundStyle(Color(hex: 0xA78BFA).opacity(0.5))
                    .fixedSize()

                SpecProgressBar(steps: session.steps, size: .mini)
                    .frame(width: max(CGFloat(session.steps.count) * 23, 40))
                    .fixedSize(horizontal: true, vertical: false)

                if let text = activeActionText,
                   !text.isEmpty,
                   session.buildState == .building {
                    Text(lastLine(of: text))
                        .font(Theme.body(10))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Close ×
            Button(action: onTap) {
                Text("×")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: 0xA78BFA).opacity(0.35))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 24)
        .padding(.trailing, 14)
        .padding(.vertical, 5)
        .background(Theme.Colors.sidebarBackground)
        .overlay(
            Rectangle()
                .inset(by: 0.5)
                .strokeBorder(Color(hex: 0xA78BFA).opacity(0.2), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private func lastLine(of text: String) -> String {
        text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.last ?? text
    }
}

// MARK: - Spec Bar Compact (Sidebar header — legacy, kept for compatibility)

struct SpecBarCompact: View {
    @Bindable var session: BuilderSession

    var body: some View {
        HStack(spacing: 8) {
            Text("\(session.completedCount)/\(session.totalCount)")
                .font(Theme.code(11, weight: .bold))
                .foregroundStyle(stateColor)

            SpecProgressBar(steps: session.steps, size: .mini)
                .frame(maxWidth: .infinity)

            statusBadge
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
    }

    private var stateColor: Color {
        switch session.buildState {
        case .ready:    return Theme.Colors.textTertiary
        case .building: return Theme.Colors.statusWorking
        case .paused:   return Theme.Colors.warning
        case .done:     return Theme.Colors.statusDone
        case .failed:   return Theme.Colors.error
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch session.buildState {
        case .ready:
            Text("READY").font(Theme.caption(9)).foregroundStyle(Theme.Colors.textTertiary)
        case .building:
            Text("BUILDING").font(Theme.caption(9)).foregroundStyle(Theme.Colors.statusWorking)
        case .paused:
            Text("PAUSED").font(Theme.caption(9)).foregroundStyle(Theme.Colors.warning)
        case .done:
            Text("DONE").font(Theme.caption(9)).foregroundStyle(Theme.Colors.statusDone)
        case .failed:
            Text("FAILED").font(Theme.caption(9)).foregroundStyle(Theme.Colors.error)
        }
    }
}
