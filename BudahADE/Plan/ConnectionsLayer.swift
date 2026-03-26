import SwiftUI

// MARK: - Connections Layer

/// Renders arrow connections between tiles using Canvas draw API,
/// plus invisible hit-test paths for right-click delete.
struct ConnectionsLayer: View {
    @ObservedObject var canvas: PlanCanvasState

    var body: some View {
        // Read drag state in ViewBuilder scope so SwiftUI registers these as
        // dependencies — Canvas closures are NOT tracked by SwiftUI's dependency system.
        let dragSource = canvas.connectionDragSource
        let dragEndpoint = canvas.connectionDragEndpoint
        let draggingId = canvas.draggingId
        let dragOffset = canvas.activeDragOffset

        ZStack {
            // Connection arrows (Path-based to avoid Canvas clipping)
            ForEach(canvas.connections) { connection in
                if let source = canvas.findElement(connection.sourceId),
                   let dest = canvas.findElement(connection.destinationId) {
                    let startPt = adjustedRightEdge(of: source, draggingId: draggingId, offset: dragOffset)
                    let endPt = adjustedLeftEdge(of: dest, draggingId: draggingId, offset: dragOffset)
                    let sourceColor = tileColor(for: source)
                    let destColor = tileColor(for: dest)
                    ConnectionArrow(
                        start: startPt,
                        end: endPt,
                        sourceColor: sourceColor,
                        destColor: destColor
                    )
                    .allowsHitTesting(false)
                }
            }

            // Drag preview line (Path-based to avoid Canvas clipping)
            if let sourceId = dragSource,
               let endpoint = dragEndpoint,
               let source = canvas.findElement(sourceId) {
                let startPt = adjustedRightEdge(of: source, draggingId: draggingId, offset: dragOffset)
                let hoveredTarget = canvas.elementAt(point: endpoint, margin: 20)
                let isOverTarget = hoveredTarget != nil && hoveredTarget != sourceId
                DragPreviewArrow(start: startPt, end: endpoint, isOverTarget: isOverTarget)
                    .allowsHitTesting(false)
            }

            // Invisible fat-stroked paths for right-click context menus
            ForEach(canvas.connections) { connection in
                if let source = canvas.findElement(connection.sourceId),
                   let dest = canvas.findElement(connection.destinationId) {
                    let startPt = adjustedRightEdge(of: source, draggingId: draggingId, offset: dragOffset)
                    let endPt = adjustedLeftEdge(of: dest, draggingId: draggingId, offset: dragOffset)

                    ConnectionHitTarget(
                        start: startPt,
                        end: endPt,
                        connectionId: connection.id,
                        canvas: canvas
                    )
                }
            }
        }
    }

    // MARK: - Position Helpers (drag-aware)

    /// Right edge center, offset if this element is being dragged.
    private func adjustedRightEdge(of element: CanvasElement, draggingId: UUID?, offset: CGSize) -> CGPoint {
        var pt = CGPoint(
            x: element.position.x + element.size.width,
            y: element.position.y + element.size.height / 2
        )
        if element.id == draggingId {
            pt.x += offset.width
            pt.y += offset.height
        }
        return pt
    }

    /// Left edge center, offset if this element is being dragged.
    private func adjustedLeftEdge(of element: CanvasElement, draggingId: UUID?, offset: CGSize) -> CGPoint {
        var pt = CGPoint(
            x: element.position.x,
            y: element.position.y + element.size.height / 2
        )
        if element.id == draggingId {
            pt.x += offset.width
            pt.y += offset.height
        }
        return pt
    }

    // MARK: - Color Helpers

    fileprivate func tileColor(for element: CanvasElement) -> Color {
        guard case .tile(let tileType) = element.kind else { return Theme.textMuted }
        switch tileType {
        case .chatAgent(_, let role): return role.color
        case .terminal(_, let agent): return agent.dotColor
        default: return Theme.textMuted
        }
    }
}

// MARK: - Connection Arrow (Path-based, no clipping)

/// Renders a single persistent connection arrow with glow and pulse.
private struct ConnectionArrow: View {
    let start: CGPoint
    let end: CGPoint
    let sourceColor: Color
    let destColor: Color

    @State private var pulsePhase: CGFloat = 0

    private var blendedColor: Color {
        let resolved1 = NSColor(sourceColor).usingColorSpace(.sRGB) ?? .gray
        let resolved2 = NSColor(destColor).usingColorSpace(.sRGB) ?? .gray
        let r = (resolved1.redComponent + resolved2.redComponent) / 2
        let g = (resolved1.greenComponent + resolved2.greenComponent) / 2
        let b = (resolved1.blueComponent + resolved2.blueComponent) / 2
        return Color(nsColor: NSColor(red: r, green: g, blue: b, alpha: 1))
    }

    var body: some View {
        let (cp1, cp2) = ConnectionsLayer.sharedControlPoints(from: start, to: end)
        let pulse = 0.45 + 0.25 * sin(pulsePhase * .pi * 2)

        // Glow layer
        Path { path in
            path.move(to: start)
            path.addCurve(to: end, control1: cp1, control2: cp2)
        }
        .stroke(blendedColor.opacity(0.25), style: StrokeStyle(lineWidth: 8, lineCap: .round))
        .blur(radius: 6)

        // Crisp line
        Path { path in
            path.move(to: start)
            path.addCurve(to: end, control1: cp1, control2: cp2)
        }
        .stroke(blendedColor.opacity(pulse), style: StrokeStyle(lineWidth: 2, lineCap: .round))

        // Arrowhead
        let arrowSize: CGFloat = 11
        let angle = atan2(end.y - cp2.y, end.x - cp2.x)
        Path { path in
            path.move(to: end)
            path.addLine(to: CGPoint(
                x: end.x - arrowSize * cos(angle - .pi / 5),
                y: end.y - arrowSize * sin(angle - .pi / 5)
            ))
            path.addLine(to: CGPoint(
                x: end.x - arrowSize * cos(angle + .pi / 5),
                y: end.y - arrowSize * sin(angle + .pi / 5)
            ))
            path.closeSubpath()
        }
        .fill(blendedColor.opacity(pulse))

        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                pulsePhase = 1
            }
        }
    }
}

// MARK: - Connection Hit Target (for right-click delete)

private struct ConnectionHitTarget: View {
    let start: CGPoint
    let end: CGPoint
    let connectionId: UUID
    @ObservedObject var canvas: PlanCanvasState

    private var bezierPath: Path {
        let (cp1, cp2) = ConnectionsLayer.sharedControlPoints(from: start, to: end)
        var path = Path()
        path.move(to: start)
        path.addCurve(to: end, control1: cp1, control2: cp2)
        return path
    }

    var body: some View {
        bezierPath
            .stroke(Color.clear, lineWidth: 12)
            .contentShape(bezierPath.strokedPath(StrokeStyle(lineWidth: 12, lineCap: .round)))
            .contextMenu {
                Button("Delete Connection", role: .destructive) {
                    canvas.removeConnection(connectionId)
                }
            }
    }
}

// MARK: - Shared control point calculation (used by hit target too)

extension ConnectionsLayer {
    static func sharedControlPoints(from start: CGPoint, to end: CGPoint) -> (CGPoint, CGPoint) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let dist = hypot(dx, dy)

        let minOffset: CGFloat = 60
        let offset = max(minOffset, min(abs(dx) * 0.4, dist * 0.5))

        if dx > 0 {
            let cp1 = CGPoint(x: start.x + offset, y: start.y)
            let cp2 = CGPoint(x: end.x - offset, y: end.y)
            return (cp1, cp2)
        } else {
            let loopOffset = max(minOffset, abs(dx) * 0.3 + 80)
            let yBulge = dy > 0 ? max(60, abs(dy) * 0.3) : min(-60, -abs(dy) * 0.3)
            let cp1 = CGPoint(x: start.x + loopOffset, y: start.y + yBulge)
            let cp2 = CGPoint(x: end.x - loopOffset, y: end.y - yBulge)
            return (cp1, cp2)
        }
    }
}

// MARK: - Drag Preview Arrow (Path-based, no clipping)

private struct DragPreviewArrow: View {
    let start: CGPoint
    let end: CGPoint
    let isOverTarget: Bool

    @State private var pulseOpacity: Double = 0.0

    private var arrowColor: Color {
        isOverTarget ? Color.green : Theme.accent
    }

    var body: some View {
        let (cp1, cp2) = ConnectionsLayer.sharedControlPoints(from: start, to: end)

        // Glow when over target
        if isOverTarget {
            Path { path in
                path.move(to: start)
                path.addCurve(to: end, control1: cp1, control2: cp2)
            }
            .stroke(Color.green.opacity(pulseOpacity), style: StrokeStyle(lineWidth: 8, lineCap: .round))
            .blur(radius: 4)
        }

        // Bezier curve
        Path { path in
            path.move(to: start)
            path.addCurve(to: end, control1: cp1, control2: cp2)
        }
        .stroke(arrowColor.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round))

        // Arrowhead
        let arrowSize: CGFloat = 11
        let angle = atan2(end.y - cp2.y, end.x - cp2.x)
        Path { path in
            path.move(to: end)
            path.addLine(to: CGPoint(
                x: end.x - arrowSize * cos(angle - .pi / 5),
                y: end.y - arrowSize * sin(angle - .pi / 5)
            ))
            path.addLine(to: CGPoint(
                x: end.x - arrowSize * cos(angle + .pi / 5),
                y: end.y - arrowSize * sin(angle + .pi / 5)
            ))
            path.closeSubpath()
        }
        .fill(arrowColor.opacity(0.85))

        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulseOpacity = 0.4
            }
        }
    }
}

// MARK: - Connection Ports Layer (standalone ZStack layer)

/// Port circles on tile edges for drag-to-connect. Rendered as its own ZStack layer
/// above canvasContent so port gestures win over tile drag gestures.
struct ConnectionPortsLayer: View {
    @ObservedObject var canvas: PlanCanvasState

    var body: some View {
        let draggingId = canvas.draggingId
        let dragOffset = canvas.activeDragOffset

        ForEach(canvas.elements.filter(isTile)) { element in
            OutputPort(element: element, canvas: canvas,
                       draggingId: draggingId, dragOffset: dragOffset)
            InputPort(element: element, canvas: canvas,
                      draggingId: draggingId, dragOffset: dragOffset)
        }
    }

    private func isTile(_ element: CanvasElement) -> Bool {
        if case .tile = element.kind { return true }
        return false
    }
}

// MARK: - Output Port (draggable)

struct OutputPort: View {
    let element: CanvasElement
    @ObservedObject var canvas: PlanCanvasState
    let draggingId: UUID?
    let dragOffset: CGSize
    @State private var isHovered = false

    private let dotSize: CGFloat = 12
    private let hitSize: CGFloat = 28

    private var isDragging: Bool { canvas.connectionDragSource == element.id }
    private var anyDragActive: Bool { canvas.connectionDragSource != nil }
    private var isTileHovered: Bool { canvas.hoveredTileId == element.id }
    private var isRevealed: Bool { isTileHovered || isDragging || isHovered }

    private var portPosition: CGPoint {
        var pt = CGPoint(
            x: element.position.x + element.size.width,
            y: element.position.y + element.size.height / 2
        )
        if element.id == draggingId {
            pt.x += dragOffset.width
            pt.y += dragOffset.height
        }
        return pt
    }

    private var dotOpacity: Double {
        if isDragging || isTileHovered || isHovered { return 1.0 }
        if anyDragActive { return 0.5 }
        return 0.0
    }

    private var dotScale: CGFloat {
        if isDragging { return 1.25 }
        if isTileHovered || isHovered { return 1.0 }
        if anyDragActive { return 0.85 }
        return 0.5
    }

    private var dotFill: Color {
        isRevealed ? Color.white.opacity(0.9) : Theme.surface2
    }

    var body: some View {
        Color.clear
            .frame(width: hitSize, height: hitSize)
            .contentShape(Circle())
            .overlay {
                Circle()
                    .fill(dotFill)
                    .overlay(
                        Circle().strokeBorder(
                            Theme.accent.opacity(isRevealed ? 0.9 : 0.3),
                            lineWidth: 1.5
                        )
                    )
                    .shadow(color: Theme.accent.opacity(isRevealed ? 0.5 : 0), radius: 6)
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(dotScale)
                    .opacity(dotOpacity)
                    .animation(.spring(response: 0.2, dampingFraction: 0.65), value: dotOpacity)
                    .animation(.spring(response: 0.2, dampingFraction: 0.65), value: dotScale)
            }
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.crosshair.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        canvas.connectionDragSource = element.id
                        // Translation is already in canvas coords (gesture is inside scaleEffect)
                        canvas.connectionDragEndpoint = CGPoint(
                            x: portPosition.x + value.translation.width,
                            y: portPosition.y + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        let endpoint = canvas.connectionDragEndpoint
                        let targetId = endpoint.flatMap { canvas.elementAt(point: $0, margin: 20) }
                        print("[PORT-DROP] endpoint=\(String(describing: endpoint)) targetId=\(String(describing: targetId)) sourceId=\(element.id) match=\(targetId != nil && targetId != element.id)")
                        if let endpoint, let targetId, targetId != element.id {
                            canvas.addConnection(sourceId: element.id, destinationId: targetId)
                            print("[PORT-DROP] Connection added: \(element.id) -> \(targetId)")
                        }
                        canvas.connectionDragSource = nil
                        canvas.connectionDragEndpoint = nil
                    }
            )
            .position(portPosition)
    }
}

// MARK: - Input Port (visual indicator only)

struct InputPort: View {
    let element: CanvasElement
    @ObservedObject var canvas: PlanCanvasState
    let draggingId: UUID?
    let dragOffset: CGSize

    private let dotSize: CGFloat = 12
    private var anyDragActive: Bool { canvas.connectionDragSource != nil }

    private var portPosition: CGPoint {
        var pt = CGPoint(
            x: element.position.x,
            y: element.position.y + element.size.height / 2
        )
        if element.id == draggingId {
            pt.x += dragOffset.width
            pt.y += dragOffset.height
        }
        return pt
    }

    private var isHighlighted: Bool {
        guard let src = canvas.connectionDragSource, src != element.id,
              let ep = canvas.connectionDragEndpoint else { return false }
        return CGRect(origin: element.position, size: element.size).contains(ep)
    }

    private var dotOpacity: Double {
        if isHighlighted { return 1.0 }
        if anyDragActive { return 0.6 }
        return 0.0
    }

    private var dotScale: CGFloat {
        if isHighlighted { return 1.25 }
        if anyDragActive { return 1.0 }
        return 0.5
    }

    var body: some View {
        Circle()
            .fill(isHighlighted ? Color.white.opacity(0.9) : Theme.surface2)
            .overlay(
                Circle().strokeBorder(
                    Theme.accent.opacity(isHighlighted ? 0.9 : 0.3),
                    lineWidth: 1.5
                )
            )
            .shadow(color: Theme.accent.opacity(isHighlighted ? 0.5 : 0), radius: 6)
            .frame(width: dotSize, height: dotSize)
            .scaleEffect(dotScale)
            .opacity(dotOpacity)
            .animation(.spring(response: 0.2, dampingFraction: 0.65), value: dotOpacity)
            .animation(.spring(response: 0.2, dampingFraction: 0.65), value: dotScale)
            .position(portPosition)
            .allowsHitTesting(anyDragActive)
    }
}

// MARK: - Destination Highlight

/// Shows an accent glow on a tile when it's a potential connection target during drag.
struct ConnectionDestinationHighlight: View {
    let element: CanvasElement
    @ObservedObject var canvas: PlanCanvasState

    private var isHighlighted: Bool {
        guard canvas.connectionDragSource != nil,
              canvas.connectionDragSource != element.id,
              let endpoint = canvas.connectionDragEndpoint else { return false }
        let rect = CGRect(origin: element.position, size: element.size)
        return rect.contains(endpoint)
    }

    var body: some View {
        if isHighlighted {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.8), lineWidth: 2)
                .shadow(color: Theme.accent.opacity(0.4), radius: 8)
        }
    }
}
