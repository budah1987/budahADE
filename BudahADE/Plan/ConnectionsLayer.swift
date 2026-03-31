import SwiftUI

// MARK: - Connections Layer

/// Renders arrow connections between tiles using Canvas draw API,
/// plus invisible hit-test paths for right-click delete.
struct ConnectionsLayer: View {
    @ObservedObject var canvas: PlanCanvasState

    var body: some View {
        // Read drag state in the ViewBuilder scope so SwiftUI registers these as
        // dependencies of this view. Canvas closures are NOT tracked by SwiftUI's
        // dependency system — without this, the Canvas never redraws during a drag.
        let dragSource = canvas.connectionDragSource
        let dragEndpoint = canvas.connectionDragEndpoint

        ZStack {
            // Rendered arrows (Canvas draw API — no hit testing)
            Canvas { context, size in
                // Draw established connections
                for connection in canvas.connections {
                    guard let source = canvas.findElement(connection.sourceId),
                          let dest = canvas.findElement(connection.destinationId) else { continue }

                    let startPt = rightEdgeCenter(of: source)
                    let endPt = leftEdgeCenter(of: dest)
                    let sourceColor = tileColor(for: source)
                    let destColor = tileColor(for: dest)
                    let blended = blendedColor(sourceColor, destColor, opacity: 0.4)
                    let isStale = connection.cachedSummary == nil

                    drawArrow(
                        in: &context,
                        from: startPt,
                        to: endPt,
                        color: blended,
                        dashed: isStale
                    )
                }

                // Draw in-progress drag line
                if let sourceId = dragSource,
                   let endpoint = dragEndpoint,
                   let source = canvas.findElement(sourceId) {
                    let startPt = rightEdgeCenter(of: source)
                    drawArrow(
                        in: &context,
                        from: startPt,
                        to: endpoint,
                        color: Theme.accent.opacity(0.85),
                        dashed: false,
                        lineWidth: 2.5
                    )

                    // Endpoint anchor dot
                    let dotRect = CGRect(x: endpoint.x - 5, y: endpoint.y - 5, width: 10, height: 10)
                    context.fill(Path(ellipseIn: dotRect), with: .color(Theme.accent))
                }
            }
            .allowsHitTesting(false)

            // Invisible fat-stroked paths for right-click context menus
            ForEach(canvas.connections) { connection in
                if let source = canvas.findElement(connection.sourceId),
                   let dest = canvas.findElement(connection.destinationId) {
                    let startPt = rightEdgeCenter(of: source)
                    let endPt = leftEdgeCenter(of: dest)

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

    // MARK: - Arrow Drawing

    private func drawArrow(
        in context: inout GraphicsContext,
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        dashed: Bool,
        lineWidth: CGFloat = 2
    ) {
        // Bezier curve
        let dx = abs(end.x - start.x) * 0.5
        let cp1 = CGPoint(x: start.x + dx, y: start.y)
        let cp2 = CGPoint(x: end.x - dx, y: end.y)

        var path = Path()
        path.move(to: start)
        path.addCurve(to: end, control1: cp1, control2: cp2)

        let style: StrokeStyle
        if dashed {
            style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [6, 4])
        } else {
            style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        }

        context.stroke(path, with: .color(color), style: style)

        // Arrowhead at destination
        let arrowSize: CGFloat = 8
        // Approximate arrival angle from control point 2 to end
        let angle = atan2(end.y - cp2.y, end.x - cp2.x)

        var arrowPath = Path()
        arrowPath.move(to: end)
        arrowPath.addLine(to: CGPoint(
            x: end.x - arrowSize * cos(angle - .pi / 6),
            y: end.y - arrowSize * sin(angle - .pi / 6)
        ))
        arrowPath.addLine(to: CGPoint(
            x: end.x - arrowSize * cos(angle + .pi / 6),
            y: end.y - arrowSize * sin(angle + .pi / 6)
        ))
        arrowPath.closeSubpath()

        context.fill(arrowPath, with: .color(color))
    }

    // MARK: - Helpers

    private func rightEdgeCenter(of element: CanvasElement) -> CGPoint {
        CGPoint(
            x: element.position.x + element.size.width,
            y: element.position.y + element.size.height / 2
        )
    }

    private func leftEdgeCenter(of element: CanvasElement) -> CGPoint {
        CGPoint(
            x: element.position.x,
            y: element.position.y + element.size.height / 2
        )
    }

    private func tileColor(for element: CanvasElement) -> Color {
        guard case .tile(let tileType) = element.kind else { return Theme.textMuted }
        switch tileType {
        case .chatAgent(_, let role): return role.color
        case .terminal(_, let agent): return agent.dotColor
        default: return Theme.textMuted
        }
    }

    private func blendedColor(_ c1: Color, _ c2: Color, opacity: Double) -> Color {
        // Use the average as a simple blend — Canvas doesn't support gradient strokes
        // We'll just use a midpoint color at the desired opacity
        let resolved1 = NSColor(c1).usingColorSpace(.sRGB) ?? .gray
        let resolved2 = NSColor(c2).usingColorSpace(.sRGB) ?? .gray
        let r = (resolved1.redComponent + resolved2.redComponent) / 2
        let g = (resolved1.greenComponent + resolved2.greenComponent) / 2
        let b = (resolved1.blueComponent + resolved2.blueComponent) / 2
        return Color(nsColor: NSColor(red: r, green: g, blue: b, alpha: opacity))
    }
}

// MARK: - Connection Hit Target (for right-click delete)

private struct ConnectionHitTarget: View {
    let start: CGPoint
    let end: CGPoint
    let connectionId: UUID
    @ObservedObject var canvas: PlanCanvasState

    private var bezierPath: Path {
        let dx = abs(end.x - start.x) * 0.5
        let cp1 = CGPoint(x: start.x + dx, y: start.y)
        let cp2 = CGPoint(x: end.x - dx, y: end.y)
        var path = Path()
        path.move(to: start)
        path.addCurve(to: end, control1: cp1, control2: cp2)
        return path
    }

    var body: some View {
        bezierPath
            .stroke(Color.clear, lineWidth: 12)  // fat invisible stroke for hit area
            .contentShape(bezierPath.strokedPath(StrokeStyle(lineWidth: 12, lineCap: .round)))
            .contextMenu {
                Button("Delete Connection", role: .destructive) {
                    canvas.removeConnection(connectionId)
                }
            }
    }
}

// MARK: - Connection Port Overlay

/// Port circles in canvas space. Hidden at rest, revealed on tile hover.
/// Rendered in a separate layer above tiles so drag gestures don't conflict.
struct ConnectionPortsLayer: View {
    @ObservedObject var canvas: PlanCanvasState

    var body: some View {
        ForEach(canvas.elements.filter(isTile)) { element in
            OutputPort(element: element, canvas: canvas)
            InputPort(element: element, canvas: canvas)
        }
    }

    private func isTile(_ element: CanvasElement) -> Bool {
        if case .tile = element.kind { return true }
        return false
    }
}

// MARK: - Output Port (draggable)

private struct OutputPort: View {
    let element: CanvasElement
    @ObservedObject var canvas: PlanCanvasState
    @State private var isHovered = false

    private let dotSize: CGFloat = 12
    private let hitSize: CGFloat = 28  // larger invisible hit area

    private var isDragging: Bool { canvas.connectionDragSource == element.id }
    private var anyDragActive: Bool { canvas.connectionDragSource != nil }
    private var isTileHovered: Bool { canvas.hoveredTileId == element.id }
    // Port stays revealed if tile is hovered OR cursor is directly on the port.
    // This prevents the dot from vanishing when the cursor moves off the tile onto the dot.
    private var isRevealed: Bool { isTileHovered || isDragging || isHovered }

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
        // Large invisible hit area — always present so the cursor can trigger hover
        Color.clear
            .frame(width: hitSize, height: hitSize)
            .contentShape(Circle().size(width: hitSize, height: hitSize))
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
            .position(
                x: element.position.x + element.size.width,
                y: element.position.y + element.size.height / 2
            )
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.crosshair.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        canvas.connectionDragSource = element.id
                        let startX = element.position.x + element.size.width
                        let startY = element.position.y + element.size.height / 2
                        let zoom = max(canvas.zoom, 0.01)
                        canvas.connectionDragEndpoint = CGPoint(
                            x: startX + value.translation.width / zoom,
                            y: startY + value.translation.height / zoom
                        )
                    }
                    .onEnded { _ in
                        if let endpoint = canvas.connectionDragEndpoint,
                           let targetId = canvas.elementAt(point: endpoint),
                           targetId != element.id {
                            canvas.addConnection(sourceId: element.id, destinationId: targetId)
                        }
                        canvas.connectionDragSource = nil
                        canvas.connectionDragEndpoint = nil
                    }
            )
    }
}

// MARK: - Input Port (visual indicator only)

private struct InputPort: View {
    let element: CanvasElement
    @ObservedObject var canvas: PlanCanvasState

    private let dotSize: CGFloat = 12
    private var anyDragActive: Bool { canvas.connectionDragSource != nil }

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
            .position(
                x: element.position.x,
                y: element.position.y + element.size.height / 2
            )
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
        // The endpoint is in canvas content space; the element rect is also in canvas content space
        // But CanvasElementView uses .position() which centers, so we need the origin-based rect
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
