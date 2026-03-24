import SwiftUI

// MARK: - Connections Layer

/// Renders arrow connections between tiles using Canvas draw API,
/// plus invisible hit-test paths for right-click delete.
struct ConnectionsLayer: View {
    @ObservedObject var canvas: PlanCanvasState

    var body: some View {
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
                if let sourceId = canvas.connectionDragSource,
                   let endpoint = canvas.connectionDragEndpoint,
                   let source = canvas.findElement(sourceId) {
                    let startPt = rightEdgeCenter(of: source)
                    drawArrow(
                        in: &context,
                        from: startPt,
                        to: endpoint,
                        color: Color.white.opacity(0.3),
                        dashed: true
                    )
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
        dashed: Bool
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
            style = StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4])
        } else {
            style = StrokeStyle(lineWidth: 2, lineCap: .round)
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

/// Port circles rendered directly in canvas space (not inside CanvasElementView).
/// This avoids gesture conflicts with tile drag gestures.
struct ConnectionPortsLayer: View {
    @ObservedObject var canvas: PlanCanvasState
    let hoveredElementId: UUID?

    private let portSize: CGFloat = 12

    var body: some View {
        ForEach(canvas.elements.filter { isTile($0) }) { element in
            let showPorts = hoveredElementId == element.id || canvas.connectionDragSource != nil

            if showPorts {
                // Output port — right edge center
                Circle()
                    .fill(canvas.connectionDragSource == element.id ? Theme.accent : Theme.surface2)
                    .overlay(
                        Circle()
                            .strokeBorder(Theme.accent.opacity(0.8), lineWidth: 1.5)
                    )
                    .frame(width: portSize, height: portSize)
                    .position(
                        x: element.position.x + element.size.width,
                        y: element.position.y + element.size.height / 2
                    )
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                canvas.connectionDragSource = element.id
                                // Convert drag translation to canvas-space endpoint
                                let startX = element.position.x + element.size.width
                                let startY = element.position.y + element.size.height / 2
                                canvas.connectionDragEndpoint = CGPoint(
                                    x: startX + value.translation.width,
                                    y: startY + value.translation.height
                                )
                            }
                            .onEnded { value in
                                if let endpoint = canvas.connectionDragEndpoint,
                                   let targetId = canvas.elementAt(point: endpoint),
                                   targetId != element.id {
                                    canvas.addConnection(sourceId: element.id, destinationId: targetId)
                                }
                                canvas.connectionDragSource = nil
                                canvas.connectionDragEndpoint = nil
                            }
                    )
                    .onHover { hovering in
                        if hovering { NSCursor.crosshair.push() } else { NSCursor.pop() }
                    }

                // Input port — left edge center (visual only)
                Circle()
                    .fill(Theme.surface2)
                    .overlay(
                        Circle()
                            .strokeBorder(Theme.accent.opacity(0.8), lineWidth: 1.5)
                    )
                    .frame(width: portSize, height: portSize)
                    .position(
                        x: element.position.x,
                        y: element.position.y + element.size.height / 2
                    )
                    .allowsHitTesting(false)
            }
        }
    }

    private func isTile(_ element: CanvasElement) -> Bool {
        if case .tile = element.kind { return true }
        return false
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
