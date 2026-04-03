import SwiftUI
import UniformTypeIdentifiers

// MARK: - Split Pane State

/// Tracks which tabs belong to the secondary pane and the split direction.
/// The secondary pane owns a subset of the task's tabs; the rest belong to the primary pane.
struct SplitPaneState: Equatable {
    var secondaryTabIds: [UUID]
    var secondarySelectedId: UUID?
    var orientation: SplitOrientation
}

// MARK: - Pane Position

enum PanePosition: Equatable {
    case primary
    case secondary
}

// MARK: - Pane Arrow

enum PaneArrow {
    case left, right, up, down
}


// MARK: - Drop Zone

/// Where a dragged tab can be dropped to create a split.
enum DropZone: Equatable {
    case left, right, top, bottom

    var orientation: SplitOrientation {
        switch self {
        case .left, .right: return .horizontal
        case .top, .bottom: return .vertical
        }
    }

    /// Whether the dropped tab becomes the first (leading/top) pane.
    var isFirst: Bool {
        switch self {
        case .left, .top: return true
        case .right, .bottom: return false
        }
    }
}

// MARK: - Split Drop Overlay

/// Overlay that shows drop zone highlights when a tab is dragged over the content area.
/// Uses a single full-coverage DropDelegate so the zone is determined from the drop
/// location rather than relying on four competing .onDrop views — which is unreliable
/// when WKWebView or other NSViews are in the hierarchy.
struct SplitDropOverlay: View {
    let onDrop: (DropZone, String) -> Void
    @State private var activeZone: DropZone?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Visual-only zone indicators (non-interactive)
                zoneHighlight(.left,   geo: geo)
                zoneHighlight(.right,  geo: geo)
                zoneHighlight(.top,    geo: geo)
                zoneHighlight(.bottom, geo: geo)

                // Single full-coverage drop target — zone computed from cursor position
                Color.clear
                    .contentShape(Rectangle())
                    .onDrop(
                        of: [UTType.text],
                        delegate: SplitDropDelegate(
                            size: geo.size,
                            activeZone: $activeZone,
                            onDrop: onDrop
                        )
                    )
            }
        }
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private func zoneHighlight(_ zone: DropZone, geo: GeometryProxy) -> some View {
        let isActive = activeZone == zone
        let frame = highlightFrame(zone, geo: geo)
        Rectangle()
            .fill(isActive ? Theme.Colors.accent.opacity(0.12) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Theme.Colors.accent.opacity(isActive ? 0.6 : 0), lineWidth: 2)
                    .padding(4)
            )
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)
    }

    private func highlightFrame(_ zone: DropZone, geo: GeometryProxy) -> CGRect {
        let w = geo.size.width, h = geo.size.height
        switch zone {
        case .left:   return CGRect(x: 0,       y: 0,       width: w * 0.3, height: h)
        case .right:  return CGRect(x: w * 0.7,  y: 0,       width: w * 0.3, height: h)
        case .top:    return CGRect(x: w * 0.3,  y: 0,       width: w * 0.4, height: h * 0.3)
        case .bottom: return CGRect(x: w * 0.3,  y: h * 0.7, width: w * 0.4, height: h * 0.3)
        }
    }
}

// MARK: - Pane Move Drop Overlay

/// Overlay shown in split mode: dragging a tab over one half moves it to that pane.
struct PaneMoveDropOverlay: View {
    let orientation: SplitOrientation
    let onDrop: (PanePosition, String) -> Void
    @State private var activePane: PanePosition?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                paneTint(.primary, geo: geo)
                paneTint(.secondary, geo: geo)

                Color.clear
                    .contentShape(Rectangle())
                    .onDrop(
                        of: [UTType.text],
                        delegate: PaneMoveDropDelegate(
                            size: geo.size,
                            orientation: orientation,
                            activePane: $activePane,
                            onDrop: onDrop
                        )
                    )
            }
        }
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private func paneTint(_ pane: PanePosition, geo: GeometryProxy) -> some View {
        let isActive = activePane == pane
        let frame = paneFrame(pane, geo: geo)
        Rectangle()
            .fill(isActive ? Theme.Colors.accent.opacity(0.12) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Theme.Colors.accent.opacity(isActive ? 0.6 : 0), lineWidth: 2)
                    .padding(4)
            )
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)
    }

    private func paneFrame(_ pane: PanePosition, geo: GeometryProxy) -> CGRect {
        let w = geo.size.width, h = geo.size.height
        switch (orientation, pane) {
        case (.horizontal, .primary):   return CGRect(x: 0,       y: 0, width: w * 0.5, height: h)
        case (.horizontal, .secondary): return CGRect(x: w * 0.5, y: 0, width: w * 0.5, height: h)
        case (.vertical,   .primary):   return CGRect(x: 0,       y: 0, width: w, height: h * 0.5)
        case (.vertical,   .secondary): return CGRect(x: 0, y: h * 0.5, width: w, height: h * 0.5)
        }
    }
}

private struct PaneMoveDropDelegate: DropDelegate {
    let size: CGSize
    let orientation: SplitOrientation
    @Binding var activePane: PanePosition?
    let onDrop: (PanePosition, String) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let pane = pane(for: info.location)
        withAnimation(.easeInOut(duration: 0.15)) { activePane = pane }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        withAnimation(.easeInOut(duration: 0.15)) { activePane = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        let pane = pane(for: info.location) ?? .primary
        if let tabId = currentlyDraggingTabId {
            DispatchQueue.main.async { onDrop(pane, tabId.uuidString) }
        } else {
            info.itemProviders(for: [UTType.text]).first?.loadObject(ofClass: String.self) { str, _ in
                if let str { DispatchQueue.main.async { onDrop(pane, str) } }
            }
        }
        withAnimation(.easeInOut(duration: 0.15)) { activePane = nil }
        return true
    }

    private func pane(for location: CGPoint) -> PanePosition? {
        switch orientation {
        case .horizontal: return location.x < size.width  * 0.5 ? .primary : .secondary
        case .vertical:   return location.y < size.height * 0.5 ? .primary : .secondary
        }
    }
}

// MARK: - Split Drop Delegate

private struct SplitDropDelegate: DropDelegate {
    let size: CGSize
    @Binding var activeZone: DropZone?
    let onDrop: (DropZone, String) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let zone = zone(for: info.location)
        withAnimation(.easeInOut(duration: 0.15)) { activeZone = zone }
        return DropProposal(operation: zone != nil ? .move : .forbidden)
    }

    func dropExited(info: DropInfo) {
        withAnimation(.easeInOut(duration: 0.15)) { activeZone = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let zone = zone(for: info.location) else {
            withAnimation(.easeInOut(duration: 0.15)) { activeZone = nil }
            return false
        }
        // Prefer the tracked drag ID — NSDraggingSession items are unreliable
        // through SwiftUI's NSItemProvider bridging (loadObject may return nil).
        if let tabId = currentlyDraggingTabId {
            DispatchQueue.main.async { onDrop(zone, tabId.uuidString) }
        } else {
            // Fallback: parse from pasteboard (works for SwiftUI-native drags)
            info.itemProviders(for: [UTType.text]).first?.loadObject(ofClass: String.self) { str, _ in
                if let str {
                    DispatchQueue.main.async { onDrop(zone, str) }
                }
            }
        }
        withAnimation(.easeInOut(duration: 0.15)) { activeZone = nil }
        return true
    }

    /// Map cursor position to a drop zone.
    /// Left/right take priority (full height strips); top/bottom occupy the centre column.
    private func zone(for location: CGPoint) -> DropZone? {
        let x = location.x / size.width
        let y = location.y / size.height
        if x < 0.3 { return .left }
        if x > 0.7 { return .right }
        if y < 0.3 { return .top }
        if y > 0.7 { return .bottom }
        return nil
    }
}
