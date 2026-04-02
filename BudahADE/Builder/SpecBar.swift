import SwiftUI

// MARK: - Spec Bar (Content Area — below tab bar)

/// Persistent thin strip below the conversation tab bar.
/// Shows build progress summary. Click to select the builder tab.
struct SpecBar: View {
    @Bindable var session: BuilderSession
    var specTitle: String = "Spec"
    var isBuilderTabActive: Bool = false
    var onTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Purple accent line when builder tab active
            if isBuilderTabActive {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.builder)
                    .frame(width: 3, height: 20)
            }

            Text(specTitle)
                .font(Theme.label(11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)

            Text("\(session.completedCount)/\(session.totalCount)")
                .font(Theme.code(11))
                .foregroundStyle(Theme.textMuted)

            SpecProgressBar(steps: session.steps, size: .large)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Theme.surface2)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.borderSubtle).frame(height: 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Spec Bar Compact (Sidebar header)

/// Compact progress summary at top of the step list in the sidebar.
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
        case .ready:    return Theme.textMuted
        case .building: return Theme.builder
        case .paused:   return Theme.warning
        case .done:     return Theme.success
        case .failed:   return Theme.error
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch session.buildState {
        case .ready:
            Text("READY")
                .font(Theme.caption(9))
                .foregroundStyle(Theme.textMuted)
        case .building:
            Text("BUILDING")
                .font(Theme.caption(9))
                .foregroundStyle(Theme.builder)
        case .paused:
            Text("PAUSED")
                .font(Theme.caption(9))
                .foregroundStyle(Theme.warning)
        case .done:
            Text("DONE")
                .font(Theme.caption(9))
                .foregroundStyle(Theme.success)
        case .failed:
            Text("FAILED")
                .font(Theme.caption(9))
                .foregroundStyle(Theme.error)
        }
    }
}
