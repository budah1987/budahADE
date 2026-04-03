import SwiftUI
import AppKit

// MARK: - ChatTileResizeOverlay

/// NSViewRepresentable that provides resize handles for Chat Agent tiles.
/// Uses NSTrackingArea + mouse events at the AppKit level to bypass SwiftUI
/// gesture conflicts with ScrollView, TextEditor, and .onDrop().
struct ChatTileResizeOverlay: NSViewRepresentable {
    let elementId: UUID
    @ObservedObject var canvas: PlanCanvasState

    func makeNSView(context: Context) -> ChatResizeNSView {
        let view = ChatResizeNSView()
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: ChatResizeNSView, context: Context) {
        let coordinator = context.coordinator
        // Update element snapshot for resize calculations
        if let element = canvas.elements.first(where: { $0.id == elementId }) {
            coordinator.currentSize = element.size
            coordinator.currentPosition = element.position
        }
        coordinator.zoom = canvas.zoom
        coordinator.elementId = elementId
        coordinator.canvas = canvas
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator {
        var elementId: UUID = UUID()
        weak var canvas: PlanCanvasState?
        var zoom: CGFloat = 1.0
        var currentSize: CGSize = .zero
        var currentPosition: CGPoint = .zero

        // Drag state
        var initialSize: CGSize = .zero
        var initialPosition: CGPoint = .zero
        var activeEdge: EdgeRegion?

        func beginResize(at point: CGPoint, in bounds: CGSize) {
            guard let region = edgeRegion(at: point, in: bounds) else { return }
            activeEdge = region
            initialSize = currentSize
            initialPosition = currentPosition
            canvas?.resizingId = elementId
        }

        func continueResize(delta: CGPoint) {
            guard let region = activeEdge, let canvas = canvas else { return }

            let dx = delta.x / zoom
            let dy = delta.y / zoom

            let newWidth = initialSize.width + dx * region.widthSign
            let newHeight = initialSize.height + dy * region.heightSign

            let clampedWidth = max(newWidth, CanvasElement.minSize.width)
            let clampedHeight = max(newHeight, CanvasElement.minSize.height)

            let actualDW = clampedWidth - initialSize.width
            let actualDH = clampedHeight - initialSize.height

            var newPos = initialPosition
            if region.adjustsX { newPos.x = initialPosition.x - actualDW }
            if region.adjustsY { newPos.y = initialPosition.y - actualDH }

            canvas.resizeElement(elementId, to: CGSize(width: clampedWidth, height: clampedHeight))
            canvas.moveElement(elementId, to: newPos)
        }

        func endResize() {
            guard let canvas = canvas else { return }
            if let idx = canvas.elements.firstIndex(where: { $0.id == elementId }) {
                let snappedSize = GridSnap.snapSize(canvas.elements[idx].size, min: CanvasElement.minSize)
                let snappedPos = GridSnap.snapPoint(canvas.elements[idx].position)
                canvas.resizeElement(elementId, to: snappedSize)
                canvas.moveElement(elementId, to: snappedPos)
            }
            activeEdge = nil
            initialSize = .zero
            initialPosition = .zero
            canvas.resizingId = nil
        }
    }
}

// MARK: - Edge Region

enum EdgeRegion {
    case top, bottom, left, right
    case topLeft, topRight, bottomLeft, bottomRight

    var widthSign: CGFloat {
        switch self {
        case .left, .topLeft, .bottomLeft: return -1
        case .right, .topRight, .bottomRight: return 1
        case .top, .bottom: return 0
        }
    }

    var heightSign: CGFloat {
        switch self {
        case .top, .topLeft, .topRight: return -1
        case .bottom, .bottomLeft, .bottomRight: return 1
        case .left, .right: return 0
        }
    }

    var adjustsX: Bool {
        switch self {
        case .left, .topLeft, .bottomLeft: return true
        default: return false
        }
    }

    var adjustsY: Bool {
        switch self {
        case .top, .topLeft, .topRight: return true
        default: return false
        }
    }

    var cursor: NSCursor {
        switch self {
        case .left, .right:
            return .resizeLeftRight
        case .top, .bottom:
            return .resizeUpDown
        case .topLeft, .bottomRight:
            return NSCursor(image: diagonalCursorImage(nwse: true), hotSpot: NSPoint(x: 8, y: 8))
        case .topRight, .bottomLeft:
            return NSCursor(image: diagonalCursorImage(nwse: false), hotSpot: NSPoint(x: 8, y: 8))
        }
    }
}

private func diagonalCursorImage(nwse: Bool) -> NSImage {
    NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
        NSColor.white.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.5
        if nwse {
            path.move(to: NSPoint(x: 3, y: 13))
            path.line(to: NSPoint(x: 13, y: 3))
            path.move(to: NSPoint(x: 3, y: 13)); path.line(to: NSPoint(x: 7, y: 13))
            path.move(to: NSPoint(x: 3, y: 13)); path.line(to: NSPoint(x: 3, y: 9))
            path.move(to: NSPoint(x: 13, y: 3)); path.line(to: NSPoint(x: 9, y: 3))
            path.move(to: NSPoint(x: 13, y: 3)); path.line(to: NSPoint(x: 13, y: 7))
        } else {
            path.move(to: NSPoint(x: 13, y: 13))
            path.line(to: NSPoint(x: 3, y: 3))
            path.move(to: NSPoint(x: 13, y: 13)); path.line(to: NSPoint(x: 9, y: 13))
            path.move(to: NSPoint(x: 13, y: 13)); path.line(to: NSPoint(x: 13, y: 9))
            path.move(to: NSPoint(x: 3, y: 3)); path.line(to: NSPoint(x: 7, y: 3))
            path.move(to: NSPoint(x: 3, y: 3)); path.line(to: NSPoint(x: 3, y: 7))
        }
        path.stroke()
        return true
    }
}

/// Detect which edge/corner region a point falls in (nil = interior)
func edgeRegion(at point: CGPoint, in bounds: CGSize) -> EdgeRegion? {
    let t: CGFloat = 10 // edge thickness
    let nearLeft   = point.x < t
    let nearRight  = point.x > bounds.width - t
    let nearTop    = point.y < t
    let nearBottom = point.y > bounds.height - t

    if nearTop && nearLeft     { return .topLeft }
    if nearTop && nearRight    { return .topRight }
    if nearBottom && nearLeft  { return .bottomLeft }
    if nearBottom && nearRight { return .bottomRight }
    if nearTop    { return .top }
    if nearBottom { return .bottom }
    if nearLeft   { return .left }
    if nearRight  { return .right }
    return nil
}

// MARK: - ChatResizeNSView

class ChatResizeNSView: NSView {
    weak var delegate: ChatTileResizeOverlay.Coordinator?

    private var trackingArea: NSTrackingArea?
    private var dragStart: NSPoint?
    private var hoveredRegion: EdgeRegion?

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: Hit Testing — return nil for interior so events pass through

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        // If dragging, always claim events
        if dragStart != nil { return self }
        // Only claim edge regions
        if edgeRegion(at: CGPoint(x: local.x, y: local.y), in: bounds.size) != nil {
            return self
        }
        return nil
    }

    // MARK: Mouse Events

    override func mouseMoved(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let region = edgeRegion(at: CGPoint(x: local.x, y: local.y), in: bounds.size)
        if region != hoveredRegion {
            hoveredRegion = region
            if let r = region {
                r.cursor.set()
            } else {
                NSCursor.arrow.set()
            }
            needsDisplay = true
        }
    }

    override func mouseEntered(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        if hoveredRegion != nil {
            hoveredRegion = nil
            NSCursor.arrow.set()
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let point = CGPoint(x: local.x, y: local.y)
        guard edgeRegion(at: point, in: bounds.size) != nil else { return }
        dragStart = local
        delegate?.beginResize(at: point, in: bounds.size)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let local = convert(event.locationInWindow, from: nil)
        let delta = CGPoint(x: local.x - start.x, y: local.y - start.y)
        delegate?.continueResize(delta: delta)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        dragStart = nil
        delegate?.endResize()
    }

    // MARK: Drawing — visual feedback on hover

    override func draw(_ dirtyRect: NSRect) {
        guard let region = hoveredRegion else { return }

        let accent = NSColor(red: 0.77, green: 0.47, blue: 0.36, alpha: 1.0) // Theme.Colors.accent
        accent.withAlphaComponent(0.6).setFill()

        let t: CGFloat = 2 // visual indicator thickness
        let b = bounds

        switch region {
        case .top:
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: b.width, height: t)).fill()
        case .bottom:
            NSBezierPath(rect: NSRect(x: 0, y: b.height - t, width: b.width, height: t)).fill()
        case .left:
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: t, height: b.height)).fill()
        case .right:
            NSBezierPath(rect: NSRect(x: b.width - t, y: 0, width: t, height: b.height)).fill()
        case .topLeft:
            drawCornerDot(at: NSPoint(x: 0, y: 0), accent: accent)
        case .topRight:
            drawCornerDot(at: NSPoint(x: b.width - 8, y: 0), accent: accent)
        case .bottomLeft:
            drawCornerDot(at: NSPoint(x: 0, y: b.height - 8), accent: accent)
        case .bottomRight:
            drawCornerDot(at: NSPoint(x: b.width - 8, y: b.height - 8), accent: accent)
        }
    }

    private func drawCornerDot(at origin: NSPoint, accent: NSColor) {
        let rect = NSRect(origin: origin, size: NSSize(width: 8, height: 8))
        let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        accent.setFill()
        path.fill()
    }
}
