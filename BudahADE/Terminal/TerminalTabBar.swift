import SwiftUI

// MARK: - Tab Drag Tracking
//
// Module-level var so SplitDropDelegate can read the dragging tab ID without
// relying on NSItemProvider's async pasteboard API (which is unreliable for
// AppKit NSDraggingSession items in SwiftUI DropDelegate).
var currentlyDraggingTabId: UUID?

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
        case .inactive, .thinking: self = .idle     // thinking = Claude at prompt, not actively processing
        case .working:             self = .working  // braille spinner = actively processing
        case .completed:           self = .completed
        }
    }
}

// MARK: - Tab Type

enum TabType: Equatable {
    case terminal
    case browser(url: URL?)
    case builder
}

// MARK: - Tab Model

struct TabInfo: Identifiable, Equatable {
    let id: UUID
    var title: String
    var isRunning: Bool
    var tabType: TabType = .terminal
    var agentStatus: AgentStatus = .inactive
    var claudeSessionId: String?   // For --resume fallback (when tmux unavailable)
    var agentMode: AgentMode?      // Which agent role launched this tab
    var tmuxSession: String?       // tmux session name for persistence
    var restoredTitle: String?     // Saved title — preserved until Claude sets a real one
    var hadActivity: Bool = false  // True once agent has run — used for close confirmation

    var isTerminal: Bool { if case .terminal = tabType { return true } else { return false } }
    var isBrowser: Bool { if case .browser = tabType { return true } else { return false } }

    static func == (lhs: TabInfo, rhs: TabInfo) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.isRunning == rhs.isRunning &&
        lhs.tabType == rhs.tabType &&
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
    var onNewBrowserTab: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(tabs) { tab in
                    ConversationTab(
                        id: tab.id,
                        title: tab.title,
                        isSelected: tab.id == selectedTabID,
                        isSpotlit: renameTarget?.tabId == tab.id,
                        tabType: tab.tabType,
                        agentState: TabAgentState(from: tab.agentStatus),
                        onSelect: { onSelectTab(tab.id) },
                        onClose: { onCloseTab(tab.id) }
                    )
                }

                Spacer(minLength: 0)

                NewTabMenu(
                    onNewTerminal: onNewTab,
                    onNewBrowser: onNewBrowserTab ?? {}
                )
                .padding(.trailing, 8)
            }
            .padding(.top, 6)
        }
    }
}

// MARK: - Conversation Tab

struct ConversationTab: View {
    let id: UUID
    let title: String
    let isSelected: Bool
    var isSpotlit: Bool = false
    var tabType: TabType = .terminal
    let agentState: TabAgentState
    let onSelect: () -> Void
    let onClose: () -> Void

    private var isBrowser: Bool {
        if case .browser = tabType { return true } else { return false }
    }

    private var isBuilder: Bool {
        if case .builder = tabType { return true } else { return false }
    }

    var body: some View {
        HStack(spacing: 6) {
            if isBuilder {
                Circle()
                    .fill(Theme.Colors.statusWorking)
                    .frame(width: 7, height: 7)
            } else if isBrowser {
                Image(systemName: "globe")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textTertiary)
            }

            Text(title)
                .font(Theme.label(11))
                .foregroundStyle(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .lineLimit(1)

            if agentState != .idle {
                Text(agentState == .working ? "Working" : "Done")
                    .font(Theme.caption(9))
                    .foregroundStyle(
                        agentState == .working
                            ? Color(hex: 0x818cf8)
                            : Theme.Colors.statusDone
                    )
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(tabBackground)
        .overlay { RotatingBorderGlow(state: agentState) }
        .shadow(color: stateShadow, radius: 4)
        .shadow(color: stateShadow, radius: 14)
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
        .overlay(TabDragClickHandler(dragId: id.uuidString, onClick: onSelect, onMiddleClick: onClose))
    }

    // MARK: - Tab Background

    @ViewBuilder
    private var tabBackground: some View {
        ZStack {
            // Glass fill
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Theme.Colors.tabSelectedGlass : Theme.Colors.tabGlassBackground)

            // Glass border
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isSelected ? Theme.Colors.tabSelectedBorder : Theme.Colors.tabGlassBorder,
                    lineWidth: 0.5
                )

            // Subtle state tint
            if agentState == .working {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(hex: 0x6366f1).opacity(0.06))
            } else if agentState == .completed {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(hex: 0x22c55e).opacity(0.05))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    // MARK: - State Shadow

    private var stateShadow: Color {
        switch agentState {
        case .working:   return Color(hex: 0x8b5cf6).opacity(0.4)
        case .completed: return Color(hex: 0x22c55e).opacity(0.35)
        case .idle:      return .clear
        }
    }
}

// MARK: - Rotating Border Glow

struct RotatingBorderGlow: View {
    let state: TabAgentState

    @State private var sweepStart = Date()

    private let workingCycle: Double = 9.0       // seconds per full rotation
    private let doneSweepDuration: Double = 1.5  // seconds for single sweep
    private let cornerRadius: CGFloat = 7
    private let borderWidth: CGFloat = 1.5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let angle = computeAngle(at: timeline.date)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        gradient: lightGradient,
                        center: .center,
                        angle: .degrees(angle)
                    ),
                    lineWidth: borderWidth
                )
        }
        .allowsHitTesting(false)
        .onChange(of: state) { _, newState in
            if newState == .completed { sweepStart = Date() }
        }
    }

    private func computeAngle(at date: Date) -> Double {
        switch state {
        case .working:
            let t = date.timeIntervalSinceReferenceDate
            return (t / workingCycle).truncatingRemainder(dividingBy: 1.0) * 360
        case .completed:
            let elapsed = date.timeIntervalSince(sweepStart)
            let progress = min(elapsed / doneSweepDuration, 1.0)
            let eased = 1 - pow(1 - progress, 3)  // ease-out cubic
            return eased * 360
        case .idle:
            let t = date.timeIntervalSinceReferenceDate
            return (t / workingCycle).truncatingRemainder(dividingBy: 1.0) * 360
        }
    }

    private var lightGradient: Gradient {
        let (bright, mid, dim): (Color, Color, Color) = {
            switch state {
            case .working:
                return (
                    Color(hex: 0x8b5cf6).opacity(0.85),
                    Color(hex: 0x7c3aed).opacity(0.35),
                    Color(hex: 0x6366f1).opacity(0.10)
                )
            case .completed:
                return (
                    Color(hex: 0x22c55e).opacity(0.85),
                    Color(hex: 0x10b981).opacity(0.35),
                    Color(hex: 0x14b8a6).opacity(0.10)
                )
            case .idle:
                return (
                    Color.white.opacity(0.12),
                    Color.white.opacity(0.05),
                    Color.white.opacity(0.02)
                )
            }
        }()

        return Gradient(stops: [
            .init(color: bright, location: 0.0),
            .init(color: mid, location: 0.12),
            .init(color: dim, location: 0.25),
            .init(color: .clear, location: 0.45),
            .init(color: .clear, location: 0.55),
            .init(color: dim, location: 0.75),
            .init(color: mid, location: 0.88),
            .init(color: bright, location: 1.0),
        ])
    }
}

// MARK: - New Tab Menu

struct NewTabMenu: View {
    let onNewTerminal: () -> Void
    let onNewBrowser: () -> Void
    @State private var isHovered = false

    var body: some View {
        Menu {
            Button(action: onNewTerminal) {
                Label("Terminal", systemImage: "terminal")
            }
            Button(action: onNewBrowser) {
                Label("Browser", systemImage: "globe")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isHovered ? Theme.Colors.textSecondary : Theme.Colors.textTertiary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isHovered ? Theme.Colors.tabGlassBackground : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            isHovered ? Theme.Colors.tabGlassBorder : Color.clear,
                            lineWidth: 1
                        )
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
    }
}

// MARK: - New Tab Button (simple, for PlanTabBar)

struct NewAgentTabButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isHovered ? Theme.Colors.textSecondary : Theme.Colors.textTertiary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isHovered ? Theme.Colors.tabGlassBackground : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            isHovered ? Theme.Colors.tabGlassBorder : Color.clear,
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

// MARK: - Tab Drag+Click Handler
//
// SwiftUI's .draggable modifier on macOS blocks ALL click events (Button and onTapGesture alike)
// because the NSDraggingSource machinery captures mouseDown before SwiftUI gestures can fire.
// This NSViewRepresentable handles both click and drag at the AppKit level, bypassing the conflict.

struct TabDragClickHandler: NSViewRepresentable {
    let dragId: String
    let onClick: () -> Void
    let onMiddleClick: () -> Void

    func makeNSView(context: Context) -> TabDragView {
        let view = TabDragView()
        view.dragId = dragId
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: TabDragView, context: Context) {
        nsView.dragId = dragId
        nsView.onClick = onClick
        nsView.onMiddleClick = onMiddleClick
    }

    class TabDragView: NSView, NSDraggingSource {
        var dragId: String = ""
        var onClick: (() -> Void)?
        var onMiddleClick: (() -> Void)?

        private var mouseDownEvent: NSEvent?
        private var dragStarted = false

        private static let dragThreshold: CGFloat = 5

        override var acceptsFirstResponder: Bool { false }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            mouseDownEvent = event
            dragStarted = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let origin = mouseDownEvent, !dragStarted else { return }
            let dx = event.locationInWindow.x - origin.locationInWindow.x
            let dy = event.locationInWindow.y - origin.locationInWindow.y
            guard sqrt(dx * dx + dy * dy) >= Self.dragThreshold else { return }

            dragStarted = true
            currentlyDraggingTabId = UUID(uuidString: dragId)
            NotificationCenter.default.post(name: .tabDragBegan, object: nil)
            let item = NSDraggingItem(pasteboardWriter: dragId as NSString)
            let img = NSImage(size: NSSize(width: 1, height: 1))
            item.setDraggingFrame(NSRect(origin: .zero, size: NSSize(width: 1, height: 1)), contents: img)
            beginDraggingSession(with: [item], event: origin, source: self)
        }

        override func mouseUp(with event: NSEvent) {
            defer {
                mouseDownEvent = nil
                dragStarted = false
            }
            guard !dragStarted else { return }
            // Confirm release is still within the view bounds
            let loc = convert(event.locationInWindow, from: nil)
            guard bounds.contains(loc) else { return }
            DispatchQueue.main.async { [weak self] in self?.onClick?() }
        }

        override func otherMouseDown(with event: NSEvent) {
            if event.buttonNumber == 2 {
                DispatchQueue.main.async { [weak self] in self?.onMiddleClick?() }
            } else {
                super.otherMouseDown(with: event)
            }
        }

        // MARK: NSDraggingSource
        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            return .move
        }

        func draggingSession(_ session: NSDraggingSession,
                             endedAt screenPoint: NSPoint,
                             operation: NSDragOperation) {
            currentlyDraggingTabId = nil
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .tabDragEnded, object: nil)
            }
        }
    }
}
