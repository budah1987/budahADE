import SwiftUI

/// Full-width app bar: traffic lights area, project dropdown, resource meter.
/// Conversation tabs live in the terminal area for natural alignment with content.
struct AppBar: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var workspace: WorkspaceState

    var body: some View {
        HStack(spacing: 0) {
            // Left zone: traffic lights + project dropdown (matches sidebar width)
            HStack(spacing: 0) {
                Color.clear.frame(width: 68)
                WorkspaceDropdown()
                Spacer(minLength: 0)
            }
            .frame(width: Theme.Layout.sidebarWidth)

            Spacer(minLength: 0)

            // Right: resource meter placeholder
            ResourceMeterPlaceholder()
                .padding(.trailing, Theme.Spacing.lg)
        }
        .frame(height: Theme.Layout.appBarHeight)
    }
}

// MARK: - Resource Meter Placeholder

private struct ResourceMeterPlaceholder: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "externaldrive")
                .font(.system(size: 10))
            Text("101.3")
                .font(Theme.code(11))
            Text("MB")
                .font(Theme.caption(11))
        }
        .foregroundColor(Theme.Colors.textTertiary)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(Theme.Colors.hoverFill)
        )
    }
}
