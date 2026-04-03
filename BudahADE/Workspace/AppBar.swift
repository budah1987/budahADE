import SwiftUI

/// Full-width app bar: traffic lights area, project dropdown, conversation tabs, resource meter.
/// Sits above both sidebar and content zone at 36px height.
struct AppBar: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var workspace: WorkspaceState
    var renameTarget: RenameTarget? = nil
    let onCloseTab: (UUID) -> Void
    let onNewTab: () -> Void
    var onNewBrowserTab: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            // Left: traffic light spacer + project dropdown
            HStack(spacing: 0) {
                // Space for macOS traffic lights (close/minimize/maximize)
                Color.clear.frame(width: 68)

                WorkspaceDropdown()
            }

            // Center: conversation tabs
            tabsSection
                .frame(maxWidth: .infinity, alignment: .leading)

            // Right: resource meter placeholder
            ResourceMeterPlaceholder()
                .padding(.trailing, Theme.Spacing.lg)
        }
        .frame(height: Theme.Layout.appBarHeight)
        .background(GlassBackground())
    }

    // MARK: - Tabs Section

    @ViewBuilder
    private var tabsSection: some View {
        if let task = workspace.activeTask {
            HStack(spacing: 4) {
                if task.mode == .plan {
                    // Plan mode tabs
                    ForEach(task.planTabs) { tab in
                        ConversationTab(
                            id: tab.id,
                            title: tab.title,
                            isSelected: tab.id == task.selectedPlanTabId,
                            isSpotlit: renameTarget?.tabId == tab.id,
                            tabType: tab.tabType,
                            agentState: tab.agentState,
                            onSelect: { task.selectPlanTab(tab.id) },
                            onClose: { onCloseTab(tab.id) }
                        )
                    }
                } else {
                    // Build mode tabs
                    ForEach(task.tabs) { tab in
                        ConversationTab(
                            id: tab.id,
                            title: tab.title,
                            isSelected: tab.id == task.selectedTabId,
                            isSpotlit: renameTarget?.tabId == tab.id,
                            tabType: tab.tabType,
                            agentState: TabAgentState(from: tab.agentStatus),
                            onSelect: { task.selectTab(tab.id) },
                            onClose: { onCloseTab(tab.id) }
                        )
                    }
                }

                // New tab button
                NewTabButton(action: onNewTab)
            }
            .padding(.leading, Theme.Spacing.lg)
        }
    }
}

// MARK: - New Tab Button (minimal "+" in app bar)

private struct NewTabButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("+")
                .font(.system(size: 16, weight: .light))
                .foregroundColor(Theme.Colors.textTertiary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
