import SwiftUI

/// Full-width app bar: traffic lights area, project dropdown, conversation tabs, resource meter.
/// Sits above both sidebar and content zone at 36px height.
///
/// Layout: [sidebar-width zone | content-width zone]
/// The left zone matches sidebar width so tabs align with content area.
struct AppBar: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var workspace: WorkspaceState
    var renameTarget: RenameTarget? = nil
    let onCloseTab: (UUID) -> Void
    let onNewTab: () -> Void
    var onNewBrowserTab: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            // Left zone: traffic lights + project dropdown (matches sidebar width)
            HStack(spacing: 0) {
                // Space for macOS traffic lights (close/minimize/maximize)
                Color.clear.frame(width: 68)

                WorkspaceDropdown()

                Spacer(minLength: 0)
            }
            .frame(width: Theme.Layout.sidebarWidth)

            // Sidebar border continuation
            Rectangle()
                .fill(Theme.Colors.borderLight)
                .frame(width: 1)

            // Content zone: conversation tabs (non-builder only) + resource meter
            HStack(spacing: 0) {
                conversationTabs
                    .frame(maxWidth: .infinity, alignment: .leading)

                ResourceMeterPlaceholder()
                    .padding(.trailing, Theme.Spacing.lg)
            }
        }
        .frame(height: Theme.Layout.appBarHeight)
        .background(GlassBackground())
    }

    // MARK: - Conversation Tabs (excludes builder tabs)

    @ViewBuilder
    private var conversationTabs: some View {
        if let task = workspace.activeTask {
            HStack(spacing: 4) {
                if task.mode == .plan {
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
                    // Build mode: only non-builder tabs in the app bar
                    ForEach(task.tabs.filter { $0.tabType != .builder }) { tab in
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

                NewTabButton(action: onNewTab)
            }
            .padding(.leading, Theme.Spacing.lg)
        }
    }
}

// MARK: - New Tab Button

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
