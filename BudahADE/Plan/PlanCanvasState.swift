import SwiftUI
import Combine

@MainActor
final class PlanCanvasState: ObservableObject {
    // Content
    @Published var elements: [CanvasElement] = []
    @Published var terminals: [UUID: TerminalPanel] = [:]

    // Viewport
    @Published var zoom: CGFloat = 1.0
    @Published var panOffset: CGSize = .zero

    // Interaction
    @Published var selectedId: UUID?
    @Published var draggingId: UUID?
    @Published var resizingId: UUID?
    @Published var hoveredFrameId: UUID?
    @Published var frameInsertIndex: Int?
    @Published var guides: [AlignmentGuide] = []

    let worktreePath: String
    let taskName: String
    let branchName: String

    init(worktreePath: String, taskName: String, branchName: String) {
        self.worktreePath = worktreePath
        self.taskName = taskName
        self.branchName = branchName
    }

    // MARK: - Add Tile (unified)

    @discardableResult
    func addTile(type: TileType, at position: CGPoint, parentFrameId: UUID? = nil) -> UUID {
        var element = CanvasElement(
            kind: .tile(type),
            position: position,
            size: CanvasElement.defaultSize,
            title: type.displayName
        )

        // If terminal, set up the panel
        if case .terminal(let panelId, let agent) = type {
            let panel = terminals[panelId] ?? {
                let p = TerminalPanel(workingDirectory: worktreePath)
                terminals[p.id] = p
                // Update the element's tile type with the real panel ID
                element = CanvasElement(
                    id: element.id,
                    kind: .tile(.terminal(panelId: p.id, agent: agent)),
                    position: position,
                    size: CanvasElement.defaultSize,
                    title: agent.displayName
                )
                launchAgent(panel: p, agent: agent)
                return p
            }()
            _ = panel // suppress unused warning
        }

        // Handle image asset copying
        if case .image(let path) = type {
            let assetsDir = (worktreePath as NSString).appendingPathComponent(".budahade/assets")
            try? FileManager.default.createDirectory(
                atPath: assetsDir, withIntermediateDirectories: true
            )
            let filename = (path as NSString).lastPathComponent
            let destPath = (assetsDir as NSString).appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: destPath) {
                try? FileManager.default.copyItem(atPath: path, toPath: destPath)
            }
            element = CanvasElement(
                id: element.id,
                kind: .tile(.image(path: destPath)),
                position: position,
                size: CanvasElement.defaultSize,
                title: filename
            )
        }

        if let frameId = parentFrameId {
            insertIntoFrame(element, frameId: frameId)
        } else {
            elements.append(element)
        }

        didMutate()
        return element.id
    }

    /// Convenience: add a terminal tile with a new panel
    @discardableResult
    func addTerminalTile(agent: AgentMode, at position: CGPoint, parentFrameId: UUID? = nil) -> UUID {
        let panel = TerminalPanel(workingDirectory: worktreePath)
        terminals[panel.id] = panel
        let type = TileType.terminal(panelId: panel.id, agent: agent)
        let element = CanvasElement(
            kind: .tile(type),
            position: position,
            size: CanvasElement.defaultSize,
            title: agent.displayName
        )

        if let frameId = parentFrameId {
            insertIntoFrame(element, frameId: frameId)
        } else {
            elements.append(element)
        }

        launchAgent(panel: panel, agent: agent)
        didMutate()
        return element.id
    }

    // MARK: - Add Frame

    @discardableResult
    func addFrame(at position: CGPoint, axis: Axis = .horizontal, title: String = "Frame") -> UUID {
        let frame = CanvasElement(
            kind: .frame(FrameData(axis: axis)),
            position: position,
            size: FrameData().computedSize,
            title: title
        )
        elements.append(frame)
        didMutate()
        return frame.id
    }

    // MARK: - Add Text

    @discardableResult
    func addText(at position: CGPoint) -> UUID {
        let data = TextData()
        let fitted = data.measuredSize(maxWidth: 200)
        let text = CanvasElement(
            kind: .text(data),
            position: position,
            size: CGSize(width: 200, height: max(fitted.height, 32)),
            title: ""
        )
        elements.append(text)
        selectedId = text.id
        didMutate()
        return text.id
    }

    // MARK: - Remove Element

    func removeElement(_ id: UUID) {
        // Clean up terminal if it's a tile
        if let element = findElement(id) {
            cleanupElement(element)
        }

        // Try removing from root level
        if elements.contains(where: { $0.id == id }) {
            elements.removeAll { $0.id == id }
            didMutate()
            return
        }

        // Try removing from frames
        for i in elements.indices {
            if case .frame(var frameData) = elements[i].kind {
                if frameData.children.contains(where: { $0.id == id }) {
                    frameData.children.removeAll { $0.id == id }
                    elements[i].kind = .frame(frameData)
                    elements[i].size = frameData.computedSize
                    didMutate()
                    return
                }
            }
        }
    }

    // MARK: - Move Element

    func moveElement(_ id: UUID, to newPosition: CGPoint) {
        if let idx = elements.firstIndex(where: { $0.id == id }) {
            elements[idx].position = newPosition
            didMutate()
        }
    }

    // MARK: - Rename Element

    func renameElement(_ id: UUID, to newTitle: String) {
        if let idx = elements.firstIndex(where: { $0.id == id }) {
            elements[idx].title = newTitle
            didMutate()
        }
    }

    // MARK: - Resize Element

    func resizeElement(_ id: UUID, to newSize: CGSize) {
        let clamped = CGSize(
            width: max(newSize.width, CanvasElement.minSize.width),
            height: max(newSize.height, CanvasElement.minSize.height)
        )

        // Check root level
        if let idx = elements.firstIndex(where: { $0.id == id }) {
            if case .frame = elements[idx].kind { return } // frames auto-size
            elements[idx].size = clamped
            // If inside a frame, recalculate parent
            recalculateParentFrames()
            didMutate()
            return
        }

        // Check inside frames
        for i in elements.indices {
            if case .frame(var frameData) = elements[i].kind {
                if let j = frameData.children.firstIndex(where: { $0.id == id }) {
                    if case .frame = frameData.children[j].kind { return }
                    frameData.children[j].size = clamped
                    elements[i].kind = .frame(frameData)
                    elements[i].size = frameData.computedSize
                    didMutate()
                    return
                }
            }
        }
    }

    // MARK: - Z-Order

    func bringToFront(_ id: UUID) {
        guard let idx = elements.firstIndex(where: { $0.id == id }) else { return }
        let element = elements.remove(at: idx)
        elements.append(element)
    }

    // MARK: - Frame Operations

    func reparent(_ elementId: UUID, into frameId: UUID?, at index: Int? = nil) {
        // Find and remove the element from its current location
        guard let element = extractElement(elementId) else { return }

        if let frameId = frameId {
            insertIntoFrame(element, frameId: frameId, at: index)
        } else {
            // Place as free element — preserve its canvas position
            elements.append(element)
        }
        didMutate()
    }

    func reorderInFrame(_ elementId: UUID, to newIndex: Int) {
        for i in elements.indices {
            if case .frame(var frameData) = elements[i].kind {
                if let oldIdx = frameData.children.firstIndex(where: { $0.id == elementId }) {
                    let element = frameData.children.remove(at: oldIdx)
                    let safeIndex = min(newIndex, frameData.children.count)
                    frameData.children.insert(element, at: safeIndex)
                    elements[i].kind = .frame(frameData)
                    elements[i].size = frameData.computedSize
                    didMutate()
                    return
                }
            }
        }
    }

    func toggleFrameAxis(_ frameId: UUID) {
        guard let idx = elements.firstIndex(where: { $0.id == frameId }),
              case .frame(var frameData) = elements[idx].kind else { return }
        frameData.axis = frameData.axis == .horizontal ? .vertical : .horizontal
        elements[idx].kind = .frame(frameData)
        elements[idx].size = frameData.computedSize
        didMutate()
    }

    // MARK: - Text Operations

    func updateText(_ id: UUID, data: TextData) {
        if let idx = elements.firstIndex(where: { $0.id == id }),
           case .text = elements[idx].kind {
            elements[idx].kind = .text(data)
            // Auto-fit height to text content
            let currentWidth = max(elements[idx].size.width, 120)
            let fitted = data.measuredSize(maxWidth: currentWidth)
            elements[idx].size = CGSize(
                width: currentWidth,
                height: max(fitted.height, 32)
            )
            didMutate()
        }
    }

    // MARK: - Viewport

    func screenToCanvas(_ screenPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (screenPoint.x - panOffset.width) / zoom,
            y: (screenPoint.y - panOffset.height) / zoom
        )
    }

    func canvasToScreen(_ canvasPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: canvasPoint.x * zoom + panOffset.width,
            y: canvasPoint.y * zoom + panOffset.height
        )
    }

    /// Zoom to a new level, keeping the point under `screenAnchor` fixed
    func zoomAt(newZoom: CGFloat, screenAnchor: CGPoint) {
        let clamped = newZoom.clamped(to: 0.1...3.0)
        // Canvas point under cursor before zoom
        let canvasX = (screenAnchor.x - panOffset.width) / zoom
        let canvasY = (screenAnchor.y - panOffset.height) / zoom
        // After zoom, adjust panOffset so the same canvas point stays under cursor
        zoom = clamped
        panOffset = CGSize(
            width: screenAnchor.x - canvasX * clamped,
            height: screenAnchor.y - canvasY * clamped
        )
    }

    func resetZoom() {
        withAnimation(.easeOut(duration: 0.25)) {
            zoom = 1.0
            panOffset = .zero
        }
    }

    func zoomToFit(viewportSize: CGSize) {
        let allRects = allElementRects()
        guard !allRects.isEmpty else { return }

        let bounds = allRects.reduce(allRects[0]) { $0.union($1) }
        let margin: CGFloat = 48

        let scaleX = (viewportSize.width - margin * 2) / bounds.width
        let scaleY = (viewportSize.height - margin * 2) / bounds.height
        let newZoom = min(min(scaleX, scaleY), 3.0).clamped(to: 0.1...3.0)

        let centerX = bounds.midX * newZoom
        let centerY = bounds.midY * newZoom

        withAnimation(.easeOut(duration: 0.3)) {
            zoom = newZoom
            panOffset = CGSize(
                width: viewportSize.width / 2 - centerX,
                height: viewportSize.height / 2 - centerY
            )
        }
    }

    // MARK: - Smart Placement

    func nextFreePosition(size: CGSize = CanvasElement.defaultSize) -> CGPoint {
        guard !elements.isEmpty else {
            return .zero
        }

        let rects = allElementRects()
        let rightEdge = rects.map(\.maxX).max() ?? 0
        let topY = rects.map(\.minY).min() ?? 0

        return CGPoint(x: rightEdge + 24, y: topY)
    }

    // MARK: - Queries

    /// All tiles (including inside frames) — for ContextManifest
    var allTiles: [CanvasElement] {
        var result: [CanvasElement] = []
        for element in elements {
            switch element.kind {
            case .tile:
                result.append(element)
            case .frame(let data):
                for child in data.children {
                    if case .tile = child.kind {
                        result.append(child)
                    }
                }
            case .text:
                break
            }
        }
        return result
    }

    // MARK: - Cleanup

    func closeAll() {
        for panel in terminals.values {
            panel.close()
        }
        terminals.removeAll()
        elements.removeAll()
    }

    // MARK: - Private

    private func didMutate() {
        ContextManifest.write(canvas: self)
    }

    private func findElement(_ id: UUID) -> CanvasElement? {
        if let el = elements.first(where: { $0.id == id }) { return el }
        for element in elements {
            if case .frame(let data) = element.kind {
                if let child = data.children.first(where: { $0.id == id }) {
                    return child
                }
            }
        }
        return nil
    }

    /// Remove element from wherever it lives, returning it
    private func extractElement(_ id: UUID) -> CanvasElement? {
        // Try root level
        if let idx = elements.firstIndex(where: { $0.id == id }) {
            return elements.remove(at: idx)
        }

        // Try inside frames
        for i in elements.indices {
            if case .frame(var frameData) = elements[i].kind {
                if let j = frameData.children.firstIndex(where: { $0.id == id }) {
                    let child = frameData.children.remove(at: j)
                    elements[i].kind = .frame(frameData)
                    elements[i].size = frameData.computedSize
                    return child
                }
            }
        }
        return nil
    }

    private func insertIntoFrame(_ element: CanvasElement, frameId: UUID, at index: Int? = nil) {
        guard let idx = elements.firstIndex(where: { $0.id == frameId }),
              case .frame(var frameData) = elements[idx].kind else { return }

        var child = element
        child.position = .zero  // Reset — frame handles positioning via auto-layout

        if let index = index {
            let safeIndex = min(index, frameData.children.count)
            frameData.children.insert(child, at: safeIndex)
        } else {
            frameData.children.append(child)
        }
        elements[idx].kind = .frame(frameData)
        elements[idx].size = frameData.computedSize
    }

    private func recalculateParentFrames() {
        for i in elements.indices {
            if case .frame(let data) = elements[i].kind {
                elements[i].size = data.computedSize
            }
        }
    }

    private func cleanupElement(_ element: CanvasElement) {
        switch element.kind {
        case .tile(let tileType):
            if case .terminal(let panelId, _) = tileType {
                terminals[panelId]?.close()
                terminals.removeValue(forKey: panelId)
            }
        case .frame(let data):
            for child in data.children {
                cleanupElement(child)
            }
        case .text:
            break
        }
    }

    private func allElementRects() -> [CGRect] {
        elements.map { CGRect(origin: $0.position, size: $0.size) }
    }

    // MARK: - Agent Launch

    private func launchAgent(panel: TerminalPanel, agent: AgentMode) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            let command = AgentPrompts.launchCommand(
                agent: agent,
                taskName: self.taskName,
                branchName: self.branchName,
                worktreePath: self.worktreePath
            )
            panel.sendCommand(command)
        }
    }
}

// MARK: - CGFloat Clamping

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
