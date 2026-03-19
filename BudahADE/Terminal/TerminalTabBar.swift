import SwiftUI

// MARK: - Agent Status

/// Placeholder states — animations will be wired in a future pass.
enum AgentStatus {
    case inactive    // dim dot — no Claude running
    case thinking    // Claude reading/processing
    case working     // Claude executing tools
    case completed   // Task done
}

// MARK: - Tab Model

struct TabInfo: Identifiable, Equatable {
    let id: UUID
    var title: String
    var isRunning: Bool
    var agentStatus: AgentStatus = .inactive

    static func == (lhs: TabInfo, rhs: TabInfo) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.isRunning == rhs.isRunning
    }
}

// MARK: - TerminalTabBar

struct TerminalTabBar: View {
    @Binding var selectedTabID: UUID
    @Binding var editingTabId: UUID?
    let tabs: [TabInfo]
    let onSelectTab: (UUID) -> Void
    let onCloseTab: (UUID) -> Void
    let onNewTab: () -> Void
    let onRenameTab: (UUID, String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(tabs) { tab in
                        AgentTab(
                            tab: tab,
                            isSelected: tab.id == selectedTabID,
                            isEditing: tab.id == editingTabId,
                            onSelect: { onSelectTab(tab.id) },
                            onClose: { onCloseTab(tab.id) },
                            onCommitRename: { newTitle in
                                onRenameTab(tab.id, newTitle)
                                editingTabId = nil
                            }
                        )
                    }
                }
                .padding(.leading, 6)
                .padding(.trailing, 2)
            }

            Spacer(minLength: 0)

            Rectangle()
                .fill(Theme.border)
                .frame(width: 1, height: 16)

            NewAgentTabButton(action: onNewTab)
                .padding(.horizontal, 8)
        }
        .frame(height: 36)
        .background(Theme.panelSurface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
        }
    }
}

// MARK: - Agent Tab

private struct AgentTab: View {
    let tab: TabInfo
    let isSelected: Bool
    let isEditing: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onCommitRename: (String) -> Void

    @State private var isHovered = false
    @State private var editText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 7) {
                AgentStatusIndicator(status: tab.agentStatus, isSelected: isSelected)

                if isEditing {
                    TextField("", text: $editText)
                        .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                        .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)
                        .textFieldStyle(.plain)
                        .frame(maxWidth: 140, alignment: .leading)
                        .focused($isFocused)
                        .onSubmit { onCommitRename(editText) }
                        .onExitCommand { onCommitRename(editText) }
                } else {
                    Text(tab.title)
                        .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                        .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 140, alignment: .leading)
                }

                CloseTabButton(
                    isVisible: isEditing ? false : (isSelected || isHovered),
                    action: onClose
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tabBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .onChange(of: isEditing) { _, editing in
            if editing {
                editText = tab.title
                isFocused = true
            }
        }
    }

    @ViewBuilder
    private var tabBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 7)
                .fill(Theme.elevated)
        } else if isHovered {
            RoundedRectangle(cornerRadius: 7)
                .fill(Theme.hoverPill)
        } else {
            Color.clear
        }
    }
}

// MARK: - Status Indicator

private struct AgentStatusIndicator: View {
    let status: AgentStatus
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 7, height: 7)
    }

    private var dotColor: Color {
        switch status {
        case .inactive:  return isSelected ? Theme.textMuted : Theme.textMuted.opacity(0.4)
        case .thinking:  return Theme.accent
        case .working:   return Theme.info
        case .completed: return Theme.success
        }
    }
}

// MARK: - Close Button

private struct CloseTabButton: View {
    let isVisible: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundColor(isHovered ? Theme.textPrimary : Theme.textMuted)
                .frame(width: 15, height: 15)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isHovered ? Theme.elevated : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .opacity(isVisible ? 1 : 0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
    }
}

// MARK: - New Tab Button

private struct NewAgentTabButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isHovered ? Theme.textSecondary : Theme.textMuted)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovered ? Theme.hoverPill : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
    }
}
