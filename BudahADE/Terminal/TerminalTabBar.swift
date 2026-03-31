import SwiftUI

// MARK: - Agent Status

enum AgentStatus: Equatable {
    case inactive
    case thinking
    case working
    case completed
}

// MARK: - Tab Agent State

enum TabAgentState: Equatable {
    case idle, working, completed

    init(from status: AgentStatus) {
        switch status {
        case .inactive:            self = .idle
        case .thinking, .working:  self = .working
        case .completed:           self = .completed
        }
    }
}

// MARK: - Tab Model

struct TabInfo: Identifiable, Equatable {
    let id: UUID
    var title: String
    var isRunning: Bool
    var agentStatus: AgentStatus = .inactive
    var claudeSessionId: String?   // For --resume fallback (when tmux unavailable)
    var agentMode: AgentMode?      // Which agent role launched this tab
    var tmuxSession: String?       // tmux session name for persistence
    var restoredTitle: String?     // Saved title — preserved until Claude sets a real one
    var hadActivity: Bool = false  // True once agent has run — used for close confirmation

    static func == (lhs: TabInfo, rhs: TabInfo) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.isRunning == rhs.isRunning &&
        lhs.agentStatus == rhs.agentStatus
    }
}

// MARK: - TerminalTabBar

struct TerminalTabBar: View {
    @Binding var selectedTabID: UUID
    let tabs: [TabInfo]
    var renameTarget: RenameTarget? = nil
    let onSelectTab: (UUID) -> Void
    let onCloseTab: (UUID) -> Void
    let onNewTab: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(tabs) { tab in
                    ConversationTab(
                        title: tab.title,
                        isSelected: tab.id == selectedTabID,
                        isSpotlit: renameTarget?.tabId == tab.id,
                        agentState: TabAgentState(from: tab.agentStatus),
                        onSelect: { onSelectTab(tab.id) },
                        onClose: { onCloseTab(tab.id) }
                    )
                }

                Spacer(minLength: 0)

                NewAgentTabButton(action: onNewTab)
                    .padding(.trailing, 8)
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .background(GlassBackground())

            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 0.5)
        }
    }
}

// MARK: - Conversation Tab

struct ConversationTab: View {
    let title: String
    let isSelected: Bool
    var isSpotlit: Bool = false
    let agentState: TabAgentState
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var glowBreathing: Bool = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Theme.textMuted)
                }
                .buttonStyle(.plain)

                Text(title)
                    .font(Theme.label(11))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)

                if agentState != .idle {
                    Text(agentState == .working ? "working" : "done")
                        .font(Theme.mono(9))
                        .foregroundStyle(
                            agentState == .working
                                ? Color(hex: 0x818cf8)
                                : Theme.success
                        )
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(tabBackground)
            .overlay(alignment: .bottom) {
                // GlowBar outside clipped background so shadows can bleed
                GlowBar(state: agentState)
                    .frame(height: 3)
                    .shadow(color: glowInnerShadow, radius: 10, y: 0)
                    .shadow(color: glowOuterShadow, radius: 20, y: 2)
                    .opacity(agentState == .idle ? 0 : 1)
            }
            .fixedSize()
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: RenameSpotlightKey.self,
                            value: isSpotlit
                                ? geo.frame(in: .named("workspace"))
                                : .zero
                        )
                }
            )
        }
        .buttonStyle(.plain)
        .overlay(MiddleClickOverlay(action: onClose))
        .onAppear { startBreathing() }
        .onChange(of: agentState) { _, _ in startBreathing() }
    }

    // MARK: - Tab Background

    @ViewBuilder
    private var tabBackground: some View {
        ZStack {
            // Glass fill
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Theme.tabSelectedGlass : Theme.tabGlassBackground)

            // Glass border
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isSelected ? Theme.tabSelectedBorder : Theme.tabGlassBorder,
                    lineWidth: 0.5
                )

            // State tint — strong wash that fills the tab body
            if agentState == .working {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0x6366f1).opacity(glowBreathing ? 0.18 : 0.10),
                                Color(hex: 0x8b5cf6).opacity(glowBreathing ? 0.12 : 0.06)
                            ],
                            startPoint: .bottom, endPoint: .top
                        )
                    )
            } else if agentState == .completed {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0x22c55e).opacity(0.15),
                                Color(hex: 0x14b8a6).opacity(0.08)
                            ],
                            startPoint: .bottom, endPoint: .top
                        )
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    // MARK: - Glow Helpers

    private func startBreathing() {
        if agentState == .working {
            glowBreathing = false
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                glowBreathing = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.3)) {
                glowBreathing = false
            }
        }
    }

    private var glowInnerShadow: Color {
        switch agentState {
        case .working:   return Color(hex: 0x6366f1).opacity(0.7)
        case .completed: return Color(hex: 0x22c55e).opacity(0.55)
        case .idle:      return .clear
        }
    }

    private var glowOuterShadow: Color {
        switch agentState {
        case .working:   return Color(hex: 0x8b5cf6).opacity(0.4)
        case .completed: return Color(hex: 0x14b8a6).opacity(0.3)
        case .idle:      return .clear
        }
    }
}

// MARK: - Glow Bar

struct GlowBar: View {
    let state: TabAgentState
    @State private var opacity: Double

    init(state: TabAgentState) {
        self.state = state
        _opacity = State(initialValue: state == .working ? 0.5 : 1.0)
    }

    var body: some View {
        gradient
            .opacity(opacity)
            .onAppear { startAnimation() }
            .onChange(of: state) { _, _ in startAnimation() }
            .animation(.default, value: state)
    }

    private var gradient: LinearGradient {
        switch state {
        case .working:
            return LinearGradient(
                colors: [Color(hex: 0x6366f1), Color(hex: 0x8b5cf6)],
                startPoint: .leading, endPoint: .trailing
            )
        case .completed:
            return LinearGradient(
                colors: [Color(hex: 0x22c55e), Color(hex: 0x14b8a6)],
                startPoint: .leading, endPoint: .trailing
            )
        case .idle:
            return LinearGradient(colors: [.clear], startPoint: .leading, endPoint: .trailing)
        }
    }

    private func startAnimation() {
        switch state {
        case .working:
            opacity = 0.6
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                opacity = 1.0
            }
        case .completed:
            opacity = 1.0
            withAnimation(.easeOut(duration: 0.8).delay(0.1)) {
                opacity = 0.7
            }
        case .idle:
            withAnimation(.easeOut(duration: 0.4)) {
                opacity = 0
            }
        }
    }
}

// MARK: - New Tab Button

struct NewAgentTabButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isHovered ? Theme.textSecondary : Theme.textMuted)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isHovered ? Theme.tabGlassBackground : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            isHovered ? Theme.tabGlassBorder : Color.clear,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
    }
}

// MARK: - Middle Click Overlay

struct MiddleClickOverlay: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> MiddleClickView {
        let view = MiddleClickView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: MiddleClickView, context: Context) {
        nsView.action = action
    }

    class MiddleClickView: NSView {
        var action: (() -> Void)?

        override func otherMouseDown(with event: NSEvent) {
            if event.buttonNumber == 2 {
                action?()
            } else {
                super.otherMouseDown(with: event)
            }
        }
    }
}
