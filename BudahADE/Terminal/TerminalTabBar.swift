import SwiftUI
import UniformTypeIdentifiers

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
    var onReorderTab: ((UUID, Int) -> Void)?

    @State private var insertionIndex: Int?
    @State private var tabMidpoints: [CGFloat] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    ZStack(alignment: .leading) {
                        // Insertion indicator before this tab
                        if insertionIndex == index {
                            insertionIndicator
                                .offset(x: -4)
                        }

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
                        .background(GeometryReader { geo in
                            Color.clear.preference(
                                key: TabMidpointKey.self,
                                value: [index: geo.frame(in: .named("tabbar")).midX]
                            )
                        })
                    }
                }

                // Insertion indicator after last tab
                if insertionIndex == tabs.count {
                    insertionIndicator
                }

                Spacer(minLength: 0)

                NewTabMenu(
                    onNewTerminal: onNewTab,
                    onNewBrowser: onNewBrowserTab ?? {}
                )
                .padding(.trailing, 8)
            }
            .padding(.top, 6)
            .frame(height: 44)  // Consistent height: 6px padding + 32px tab + 6px bottom
            .coordinateSpace(name: "tabbar")
            .onPreferenceChange(TabMidpointKey.self) { midpoints in
                tabMidpoints = (0..<tabs.count).map { midpoints[$0] ?? 0 }
            }
            .onDrop(of: [UTType.text], delegate: TabBarReorderDelegate(
                tabs: tabs,
                midpoints: tabMidpoints,
                insertionIndex: $insertionIndex,
                onReorder: { tabId, newIndex in onReorderTab?(tabId, newIndex) }
            ))
        }
    }

    private var insertionIndicator: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Theme.Colors.accent)
            .frame(width: 2, height: 20)
            .shadow(color: Theme.Colors.accent.opacity(0.5), radius: 4)
    }
}

// MARK: - Tab Midpoint Preference Key

private struct TabMidpointKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Tab Bar Reorder Delegate

private struct TabBarReorderDelegate: DropDelegate {
    let tabs: [TabInfo]
    let midpoints: [CGFloat]
    @Binding var insertionIndex: Int?
    let onReorder: (UUID, Int) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard let draggingId = currentlyDraggingTabId else {
            return DropProposal(operation: .forbidden)
        }
        let x = info.location.x
        var index = tabs.count
        for (i, mid) in midpoints.enumerated() where mid > 0 {
            if x < mid { index = i; break }
        }
        // Don't show indicator at the tab's own position
        if let currentIndex = tabs.firstIndex(where: { $0.id == draggingId }) {
            if index == currentIndex || index == currentIndex + 1 {
                withAnimation(.easeInOut(duration: 0.1)) { insertionIndex = nil }
                return DropProposal(operation: .move)
            }
        }
        withAnimation(.easeInOut(duration: 0.1)) { insertionIndex = index }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        withAnimation(.easeInOut(duration: 0.1)) { insertionIndex = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { withAnimation(.easeInOut(duration: 0.1)) { insertionIndex = nil } }
        guard let index = insertionIndex else { return false }
        if let tabId = currentlyDraggingTabId {
            onReorder(tabId, index)
            return true
        }
        return false
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

    @State private var isCloseHovered = false
    @State private var isDragging = false

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

            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isCloseHovered ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .frame(width: 16, height: 16)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isCloseHovered ? 0.12 : 0))
                        .frame(width: 18, height: 18)
                )
                .animation(.easeInOut(duration: 0.1), value: isCloseHovered)
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
        .opacity(isDragging ? 0.4 : 1.0)
        .overlay(TabDragClickHandler(
            dragId: id.uuidString,
            onClick: onSelect,
            onMiddleClick: onClose,
            onCloseClick: onClose,
            onCloseHoverChanged: { isCloseHovered = $0 },
            onDragStateChanged: { isDragging = $0 }
        ))
    }

    // MARK: - Tab Background

    @ViewBuilder
    private var tabBackground: some View {
        ZStack {
            // Glass fill
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Theme.Colors.tabSelectedGlass : Theme.Colors.tabGlassBackground)

            // Border — solid state color for crisp edges
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)

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

    // MARK: - Border & Shadow

    private var borderColor: Color {
        switch agentState {
        case .working:   return Color(hex: 0x8b5cf6).opacity(0.5)
        case .completed: return Color(hex: 0x22c55e).opacity(0.5)
        case .idle:      return isSelected ? Theme.Colors.tabSelectedBorder : Theme.Colors.tabGlassBorder
        }
    }

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
    /// Whether the completion sweep has finished — freeze to static border
    @State private var sweepDone = false

    private let workingCycle: Double = 9.0       // seconds per full rotation
    private let doneSweepDuration: Double = 1.5  // seconds for single sweep
    private let cornerRadius: CGFloat = 7
    private let borderWidth: CGFloat = 1.5

    /// Whether the TimelineView should be active (avoids 60fps when idle or sweep done)
    private var isAnimating: Bool {
        switch state {
        case .working: return true
        case .completed: return !sweepDone
        case .idle: return false
        }
    }

    var body: some View {
        Group {
            if isAnimating {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    let angle = computeAngle(at: timeline.date)
                    glowBorder(angle: angle)
                }
            } else if state == .completed && sweepDone {
                // Static frozen border — no TimelineView, zero GPU cost
                glowBorder(angle: 360)
            } else {
                // Idle — no glow
                EmptyView()
            }
        }
        .allowsHitTesting(false)
        .onChange(of: state) { _, newState in
            if newState == .completed {
                sweepStart = Date()
                sweepDone = false
            } else {
                sweepDone = false
            }
        }
    }

    private func glowBorder(angle: Double) -> some View {
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

    private func computeAngle(at date: Date) -> Double {
        switch state {
        case .working:
            let t = date.timeIntervalSinceReferenceDate
            return (t / workingCycle).truncatingRemainder(dividingBy: 1.0) * 360
        case .completed:
            let elapsed = date.timeIntervalSince(sweepStart)
            let progress = min(elapsed / doneSweepDuration, 1.0)
            if progress >= 1.0 {
                // Schedule freeze on next frame
                DispatchQueue.main.async { sweepDone = true }
            }
            let eased = 1 - pow(1 - progress, 3)  // ease-out cubic
            return eased * 360
        case .idle:
            return 0
        }
    }

    private var lightGradient: Gradient {
        let (bright, dim): (Color, Color) = {
            switch state {
            case .working:
                return (
                    Color(hex: 0x8b5cf6).opacity(0.45),
                    Color(hex: 0x6366f1).opacity(0.0)
                )
            case .completed:
                return (
                    Color(hex: 0x22c55e).opacity(0.45),
                    Color(hex: 0x14b8a6).opacity(0.0)
                )
            case .idle:
                return (
                    Color.white.opacity(0.10),
                    Color.white.opacity(0.0)
                )
            }
        }()

        return Gradient(stops: [
            .init(color: bright, location: 0.0),
            .init(color: dim, location: 0.20),
            .init(color: .clear, location: 0.40),
            .init(color: .clear, location: 0.60),
            .init(color: dim, location: 0.80),
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
    var onCloseClick: (() -> Void)?
    var onCloseHoverChanged: ((Bool) -> Void)?
    var onDragStateChanged: ((Bool) -> Void)?

    func makeNSView(context: Context) -> TabDragView {
        let view = TabDragView()
        view.dragId = dragId
        view.onClick = onClick
        view.onCloseClick = onCloseClick
        view.onCloseHoverChanged = onCloseHoverChanged
        view.onDragStateChanged = onDragStateChanged
        return view
    }

    func updateNSView(_ nsView: TabDragView, context: Context) {
        nsView.dragId = dragId
        nsView.onClick = onClick
        nsView.onMiddleClick = onMiddleClick
        nsView.onCloseClick = onCloseClick
        nsView.onCloseHoverChanged = onCloseHoverChanged
        nsView.onDragStateChanged = onDragStateChanged
    }

    class TabDragView: NSView, NSDraggingSource {
        var dragId: String = ""
        var onClick: (() -> Void)?
        var onMiddleClick: (() -> Void)?
        var onCloseClick: (() -> Void)?
        var onCloseHoverChanged: ((Bool) -> Void)?
        var onDragStateChanged: ((Bool) -> Void)?
        private let closeZoneWidth: CGFloat = 28
        private var isInCloseZone = false

        private var mouseDownEvent: NSEvent?
        private var dragStarted = false

        private static let dragThreshold: CGFloat = 5

        override var acceptsFirstResponder: Bool { false }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach { removeTrackingArea($0) }
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow],
                owner: self
            ))
        }

        override func mouseMoved(with event: NSEvent) {
            let loc = convert(event.locationInWindow, from: nil)
            let inZone = bounds.contains(loc) && loc.x > bounds.width - closeZoneWidth
            if inZone != isInCloseZone {
                isInCloseZone = inZone
                DispatchQueue.main.async { [weak self] in
                    self?.onCloseHoverChanged?(inZone)
                }
            }
        }

        override func mouseExited(with event: NSEvent) {
            if isInCloseZone {
                isInCloseZone = false
                DispatchQueue.main.async { [weak self] in
                    self?.onCloseHoverChanged?(false)
                }
            }
        }

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
            DispatchQueue.main.async { [weak self] in self?.onDragStateChanged?(true) }
            NotificationCenter.default.post(name: .tabDragBegan, object: nil)
            let item = NSDraggingItem(pasteboardWriter: dragId as NSString)
            let dragImg = Self.makeDragImage(size: bounds.size)
            item.setDraggingFrame(NSRect(origin: .zero, size: bounds.size), contents: dragImg)
            beginDraggingSession(with: [item], event: origin, source: self)
        }

        override func mouseUp(with event: NSEvent) {
            defer {
                mouseDownEvent = nil
                dragStarted = false
            }
            guard !dragStarted else { return }
            let loc = convert(event.locationInWindow, from: nil)
            guard bounds.contains(loc) else { return }
            // Trailing edge click → close tab
            if let onCloseClick, loc.x > bounds.width - closeZoneWidth {
                DispatchQueue.main.async { onCloseClick() }
            } else {
                DispatchQueue.main.async { [weak self] in self?.onClick?() }
            }
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
            DispatchQueue.main.async { [weak self] in
                self?.onDragStateChanged?(false)
                NotificationCenter.default.post(name: .tabDragEnded, object: nil)
            }
        }

        /// Render a ghost pill for the drag preview
        private static func makeDragImage(size: NSSize) -> NSImage {
            let img = NSImage(size: size)
            img.lockFocus()
            let rect = NSRect(origin: .zero, size: size)
            let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
            NSColor(white: 0.25, alpha: 0.7).setFill()
            path.fill()
            NSColor(white: 1.0, alpha: 0.2).setStroke()
            path.lineWidth = 1
            path.stroke()
            img.unlockFocus()
            return img
        }
    }
}
