import SwiftUI
import AppKit

// MARK: - Resize Corner

enum ResizeCorner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var alignment: Alignment {
        switch self {
        case .topLeft:     return .topLeading
        case .topRight:    return .topTrailing
        case .bottomLeft:  return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }

    /// How translation maps to size delta (sign) and position delta
    var widthSign: CGFloat {
        switch self {
        case .topLeft, .bottomLeft: return -1
        case .topRight, .bottomRight: return 1
        }
    }

    var heightSign: CGFloat {
        switch self {
        case .topLeft, .topRight: return -1
        case .bottomLeft, .bottomRight: return 1
        }
    }

    /// Whether dragging this corner should move the origin
    var adjustsX: Bool { self == .topLeft || self == .bottomLeft }
    var adjustsY: Bool { self == .topLeft || self == .topRight }

    var cursor: NSCursor {
        switch self {
        case .topLeft, .bottomRight:
            return NSCursor(image: Self.nwseImage, hotSpot: NSPoint(x: 8, y: 8))
        case .topRight, .bottomLeft:
            return NSCursor(image: Self.neswImage, hotSpot: NSPoint(x: 8, y: 8))
        }
    }

    // Diagonal resize cursor images
    private static let nwseImage: NSImage = {
        let img = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.white.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.5
            // NW-SE diagonal line
            path.move(to: NSPoint(x: 3, y: 13))
            path.line(to: NSPoint(x: 13, y: 3))
            // NW arrowhead
            path.move(to: NSPoint(x: 3, y: 13))
            path.line(to: NSPoint(x: 7, y: 13))
            path.move(to: NSPoint(x: 3, y: 13))
            path.line(to: NSPoint(x: 3, y: 9))
            // SE arrowhead
            path.move(to: NSPoint(x: 13, y: 3))
            path.line(to: NSPoint(x: 9, y: 3))
            path.move(to: NSPoint(x: 13, y: 3))
            path.line(to: NSPoint(x: 13, y: 7))
            path.stroke()
            return true
        }
        return img
    }()

    private static let neswImage: NSImage = {
        let img = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.white.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.5
            // NE-SW diagonal line
            path.move(to: NSPoint(x: 13, y: 13))
            path.line(to: NSPoint(x: 3, y: 3))
            // NE arrowhead
            path.move(to: NSPoint(x: 13, y: 13))
            path.line(to: NSPoint(x: 9, y: 13))
            path.move(to: NSPoint(x: 13, y: 13))
            path.line(to: NSPoint(x: 13, y: 9))
            // SW arrowhead
            path.move(to: NSPoint(x: 3, y: 3))
            path.line(to: NSPoint(x: 7, y: 3))
            path.move(to: NSPoint(x: 3, y: 3))
            path.line(to: NSPoint(x: 3, y: 7))
            path.stroke()
            return true
        }
        return img
    }()
}

// MARK: - Resize Handles (4 corners + 4 edges)

struct ResizeHandles: View {
    let element: CanvasElement
    @ObservedObject var canvas: PlanCanvasState

    var body: some View {
        ZStack {
            ForEach(ResizeCorner.allCases, id: \.self) { corner in
                CornerHandle(corner: corner, element: element, canvas: canvas)
            }
            ForEach(ResizeEdge.allCases, id: \.self) { edge in
                EdgeHandle(edge: edge, element: element, canvas: canvas)
            }
        }
    }
}

// MARK: - Frame Child Resize Handle (bottom-right only, no position adjustment)

struct FrameChildResizeHandle: View {
    let element: CanvasElement
    @ObservedObject var canvas: PlanCanvasState

    @State private var initialSize: CGSize = .zero
    @State private var isHovered = false

    private let handleSize: CGFloat = 8
    private let hitAreaSize: CGFloat = 16

    var body: some View {
        Color.clear
            .frame(width: hitAreaSize, height: hitAreaSize)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isHovered ? Theme.accent : Theme.accent.opacity(0.7))
                    .frame(width: handleSize, height: handleSize)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .offset(x: hitAreaSize / 2, y: hitAreaSize / 2)
            .highPriorityGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if initialSize == .zero {
                            initialSize = element.size
                            canvas.resizingId = element.id
                        }
                        let dx = value.translation.width / canvas.zoom
                        let dy = value.translation.height / canvas.zoom
                        let newSize = CGSize(
                            width: initialSize.width + dx,
                            height: initialSize.height + dy
                        )
                        canvas.resizeElement(element.id, to: newSize)
                    }
                    .onEnded { _ in
                        initialSize = .zero
                        canvas.resizingId = nil
                    }
            )
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    ResizeCorner.bottomRight.cursor.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

// MARK: - Corner Handle

struct CornerHandle: View {
    let corner: ResizeCorner
    let element: CanvasElement
    @ObservedObject var canvas: PlanCanvasState

    @State private var initialSize: CGSize = .zero
    @State private var initialPosition: CGPoint = .zero
    @State private var isHovered = false

    private let handleSize: CGFloat = 8
    private let hitAreaSize: CGFloat = 16

    var body: some View {
        // Invisible hit area with visible dot
        Color.clear
            .frame(width: hitAreaSize, height: hitAreaSize)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isHovered ? Theme.accent : Theme.accent.opacity(0.7))
                    .frame(width: handleSize, height: handleSize)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
            .offset(
                x: corner.alignment == .topLeading || corner.alignment == .bottomLeading ? -hitAreaSize / 2 : hitAreaSize / 2,
                y: corner.alignment == .topLeading || corner.alignment == .topTrailing ? -hitAreaSize / 2 : hitAreaSize / 2
            )
            .highPriorityGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if initialSize == .zero {
                            initialSize = element.size
                            initialPosition = element.position
                            canvas.resizingId = element.id
                        }

                        let dx = value.translation.width / canvas.zoom
                        let dy = value.translation.height / canvas.zoom

                        let newWidth = initialSize.width + dx * corner.widthSign
                        let newHeight = initialSize.height + dy * corner.heightSign

                        let clampedWidth = max(newWidth, CanvasElement.minSize.width)
                        let clampedHeight = max(newHeight, CanvasElement.minSize.height)

                        // Compute how much size actually changed (accounting for clamping)
                        let actualDW = clampedWidth - initialSize.width
                        let actualDH = clampedHeight - initialSize.height

                        // Move origin for left/top corners
                        var newPos = initialPosition
                        if corner.adjustsX {
                            newPos.x = initialPosition.x - actualDW
                        }
                        if corner.adjustsY {
                            newPos.y = initialPosition.y - actualDH
                        }

                        canvas.resizeElement(element.id, to: CGSize(width: clampedWidth, height: clampedHeight))
                        canvas.moveElement(element.id, to: newPos)
                    }
                    .onEnded { _ in
                        // Grid-snap final size and position
                        if let idx = canvas.elements.firstIndex(where: { $0.id == element.id }) {
                            let snappedSize = GridSnap.snapSize(canvas.elements[idx].size, min: CanvasElement.minSize)
                            let snappedPos = GridSnap.snapPoint(canvas.elements[idx].position)
                            canvas.resizeElement(element.id, to: snappedSize)
                            canvas.moveElement(element.id, to: snappedPos)
                        }
                        initialSize = .zero
                        initialPosition = .zero
                        canvas.resizingId = nil
                    }
            )
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    corner.cursor.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

// MARK: - Resize Edge

enum ResizeEdge: CaseIterable {
    case top, bottom, left, right

    var isHorizontal: Bool { self == .top || self == .bottom }

    var widthSign: CGFloat {
        switch self {
        case .left: return -1
        case .right: return 1
        case .top, .bottom: return 0
        }
    }

    var heightSign: CGFloat {
        switch self {
        case .top: return -1
        case .bottom: return 1
        case .left, .right: return 0
        }
    }

    var adjustsX: Bool { self == .left }
    var adjustsY: Bool { self == .top }

    var cursor: NSCursor {
        isHorizontal ? .resizeUpDown : .resizeLeftRight
    }
}

// MARK: - Edge Handle

struct EdgeHandle: View {
    let edge: ResizeEdge
    let element: CanvasElement
    @ObservedObject var canvas: PlanCanvasState

    @State private var initialSize: CGSize = .zero
    @State private var initialPosition: CGPoint = .zero
    @State private var isHovered = false

    private let hitThickness: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            Color.clear
                .frame(
                    width: edge.isHorizontal ? w : hitThickness,
                    height: edge.isHorizontal ? hitThickness : h
                )
                .contentShape(Rectangle())
                .overlay(
                    // Visual indicator on hover
                    Rectangle()
                        .fill(isHovered ? Theme.accent.opacity(0.6) : Color.clear)
                        .frame(
                            width: edge.isHorizontal ? w : 2,
                            height: edge.isHorizontal ? 2 : h
                        )
                )
                .position(edgeCenter(viewWidth: w, viewHeight: h))
                .highPriorityGesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if initialSize == .zero {
                                initialSize = element.size
                                initialPosition = element.position
                                canvas.resizingId = element.id
                            }

                            let dx = value.translation.width / canvas.zoom
                            let dy = value.translation.height / canvas.zoom

                            let newWidth = initialSize.width + dx * edge.widthSign
                            let newHeight = initialSize.height + dy * edge.heightSign

                            let clampedWidth = max(newWidth, CanvasElement.minSize.width)
                            let clampedHeight = max(newHeight, CanvasElement.minSize.height)

                            let actualDW = clampedWidth - initialSize.width
                            let actualDH = clampedHeight - initialSize.height

                            var newPos = initialPosition
                            if edge.adjustsX { newPos.x = initialPosition.x - actualDW }
                            if edge.adjustsY { newPos.y = initialPosition.y - actualDH }

                            canvas.resizeElement(element.id, to: CGSize(width: clampedWidth, height: clampedHeight))
                            canvas.moveElement(element.id, to: newPos)
                        }
                        .onEnded { _ in
                            // Grid-snap final size and position
                            if let idx = canvas.elements.firstIndex(where: { $0.id == element.id }) {
                                let snappedSize = GridSnap.snapSize(canvas.elements[idx].size, min: CanvasElement.minSize)
                                let snappedPos = GridSnap.snapPoint(canvas.elements[idx].position)
                                canvas.resizeElement(element.id, to: snappedSize)
                                canvas.moveElement(element.id, to: snappedPos)
                            }
                            initialSize = .zero
                            initialPosition = .zero
                            canvas.resizingId = nil
                        }
                )
                .onHover { hovering in
                    isHovered = hovering
                    if hovering {
                        edge.cursor.push()
                    } else {
                        NSCursor.pop()
                    }
                }
        }
        .allowsHitTesting(true)
    }

    private func edgeCenter(viewWidth w: CGFloat, viewHeight h: CGFloat) -> CGPoint {
        switch edge {
        case .top:    return CGPoint(x: w / 2, y: 0)
        case .bottom: return CGPoint(x: w / 2, y: h)
        case .left:   return CGPoint(x: 0, y: h / 2)
        case .right:  return CGPoint(x: w, y: h / 2)
        }
    }
}
