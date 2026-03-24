import SwiftUI
import Combine

@MainActor
final class PlanCanvasState: ObservableObject {
    // Content
    @Published var elements: [CanvasElement] = []
    @Published var terminals: [UUID: TerminalPanel] = [:]

    // Chat agent sessions
    @Published var chatSessions: [UUID: AgentSession] = [:]
    let chatManager = CLISubprocessManager()

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
    @Published var mutationCount: Int = 0

    let worktreePath: String
    let taskName: String
    let branchName: String
    private var saveDebounce: DispatchWorkItem?

    init(worktreePath: String, taskName: String, branchName: String) {
        self.worktreePath = worktreePath
        self.taskName = taskName
        self.branchName = branchName
    }

    // MARK: - Add Tile (unified)

    @discardableResult
    func addTile(type: TileType, at position: CGPoint, parentFrameId: UUID? = nil) -> UUID {
        // TextBox gets a compact initial size; other tiles use default
        let initialSize: CGSize = {
            switch type {
            case .stickyNote: return CGSize(width: 200, height: 160)
            default: return CanvasElement.defaultSize
            }
        }()

        var element = CanvasElement(
            kind: .tile(type),
            position: position,
            size: initialSize,
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

        // Auto-select text tiles so they start in edit mode
        if case .stickyNote = type { selectedId = element.id }

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

    /// Add a chat agent tile to the canvas
    @discardableResult
    func addChatTile(agent: AgentMode, at position: CGPoint, parentFrameId: UUID? = nil) -> UUID {
        let role = AgentRole.from(agent: agent, taskName: taskName, branchName: branchName)
        let session = chatManager.createSession(
            model: role.defaultModel,
            agentMode: agent,
            systemPrompt: role.systemPrompt,
            workingDirectory: worktreePath
        )
        chatSessions[session.id] = session

        let element = CanvasElement(
            kind: .tile(.chatAgent(sessionId: session.id, role: role)),
            position: position,
            size: CGSize(width: 400, height: 500),
            title: role.name
        )

        if let frameId = parentFrameId {
            insertIntoFrame(element, frameId: frameId)
        } else {
            elements.append(element)
        }

        didMutate()
        return element.id
    }

    // MARK: - Chat Agent Actions

    func sendChatMessage(sessionId: UUID, prompt: String, model: AgentModel) {
        chatManager.send(sessionId: sessionId, prompt: prompt, model: model)
    }

    func sendToSpec(content: String, fromAgent: AgentRole) {
        // Find the first markdown tile on the canvas
        guard let specElement = allTiles.first(where: {
            if case .tile(.markdown) = $0.kind { return true }
            return false
        }),
        case .tile(.markdown(let path)) = specElement.kind else { return }

        let section = "\n\n## From \(fromAgent.name)\n\n<!-- source: \(fromAgent.id) -->\n\n\(content)"

        if let existing = try? String(contentsOfFile: path, encoding: .utf8) {
            try? (existing + section).write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    func sendToAgent(content: String, fromAgent: AgentRole, targetAgent: AgentMode) {
        let targetSession: AgentSession
        if let existing = chatSessions.values.first(where: { $0.agentMode == targetAgent }) {
            targetSession = existing
        } else {
            let pos = nextFreePosition(size: CGSize(width: 400, height: 500))
            let elementId = addChatTile(agent: targetAgent, at: pos)
            guard let element = findElement(elementId),
                  case .tile(.chatAgent(let sessionId, _)) = element.kind,
                  let session = chatSessions[sessionId] else { return }
            targetSession = session
        }

        // Stage the content — the destination tile's input field will prompt for an instruction
        targetSession.stagedContent = AgentSession.StagedContent(
            content: content,
            fromAgent: fromAgent.name
        )
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
        // Text elements (labels) use a smaller minimum size
        let minSize: CGSize = {
            if let el = findElement(id), case .text = el.kind {
                return CGSize(width: 60, height: 30)
            }
            return CanvasElement.minSize
        }()
        let clamped = CGSize(
            width: max(newSize.width, minSize.width),
            height: max(newSize.height, minSize.height)
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

    // MARK: - Spec Tagging

    func tagElement(_ id: UUID, section: String) {
        if let idx = elements.firstIndex(where: { $0.id == id }) {
            elements[idx].specSection = section
            didMutate()
            return
        }
        // Check inside frames
        for i in elements.indices {
            if case .frame(var frameData) = elements[i].kind {
                if let j = frameData.children.firstIndex(where: { $0.id == id }) {
                    frameData.children[j].specSection = section
                    elements[i].kind = .frame(frameData)
                    didMutate()
                    return
                }
            }
        }
    }

    func untagElement(_ id: UUID) {
        if let idx = elements.firstIndex(where: { $0.id == id }) {
            elements[idx].specSection = nil
            didMutate()
            return
        }
        for i in elements.indices {
            if case .frame(var frameData) = elements[i].kind {
                if let j = frameData.children.firstIndex(where: { $0.id == id }) {
                    frameData.children[j].specSection = nil
                    elements[i].kind = .frame(frameData)
                    didMutate()
                    return
                }
            }
        }
    }

    /// Assemble spec from tagged elements, returns path and auto-adds spec tile
    func assembleSpec() -> String? {
        guard let path = SpecAssembler.assemble(
            canvas: self,
            taskName: taskName,
            worktreePath: worktreePath
        ) else { return nil }

        // Auto-add a spec document tile to the canvas if one doesn't exist
        let hasSpecTile = elements.contains { el in
            if case .tile(.markdown) = el.kind { return true }
            return false
        }
        if !hasSpecTile {
            let position = nextFreePosition(size: CGSize(width: 400, height: 500))
            addTile(type: .markdown(path: path), at: position)
        }

        return path
    }

    // MARK: - Detach / Merge

    /// Extract a spec section into a new document tile for editing
    func detachSpecSection(specTileId: UUID, sectionId: String, specPath: String) {
        guard let spec = SpecParser.parse(fileAt: specPath),
              let section = spec.sections.first(where: { $0.id == sectionId }) else { return }

        // Create a temp file with the section content
        let dir = (worktreePath as NSString).appendingPathComponent(".budahade/sections")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let filename = "\(sectionId).md"
        let filePath = (dir as NSString).appendingPathComponent(filename)

        // Write section content with header
        let content = "## \(section.title)\n\n\(section.content)"
        try? content.write(toFile: filePath, atomically: true, encoding: .utf8)

        // Find the spec tile position to place the new tile nearby
        let specPos = findElement(specTileId)?.position ?? .zero
        let specSize = findElement(specTileId)?.size ?? CanvasElement.defaultSize
        let newPos = CGPoint(x: specPos.x + specSize.width + 24, y: specPos.y)

        // Create document tile, auto-tagged with the section
        let element = CanvasElement(
            kind: .tile(.markdown(path: filePath)),
            position: newPos,
            size: CGSize(width: 400, height: 300),
            title: "Edit: \(section.title)",
            specSection: section.title
        )
        elements.append(element)
        selectedId = element.id
        didMutate()
    }

    /// Merge a detached section tile back into the spec file
    func mergeIntoSpec(tileId: UUID, specPath: String) {
        guard let tile = findElement(tileId),
              case .tile(.markdown(let docPath)) = tile.kind,
              let sectionName = tile.specSection else { return }

        // Read the edited content
        guard let editedContent = try? String(contentsOfFile: docPath, encoding: .utf8) else { return }

        // Read the spec file
        guard var specContent = try? String(contentsOfFile: specPath, encoding: .utf8) else { return }
        guard let spec = SpecParser.parse(fileAt: specPath),
              let section = spec.sections.first(where: { $0.title == sectionName }) else { return }

        // Replace the section in the spec file using line range
        var lines = specContent.components(separatedBy: .newlines)
        let range = section.lineRange
        guard range.lowerBound < lines.count else { return }
        let upperBound = min(range.upperBound, lines.count)

        // Replace the section lines with the edited content
        let editedLines = editedContent.components(separatedBy: .newlines)
        lines.replaceSubrange(range.lowerBound..<upperBound, with: editedLines)

        specContent = lines.joined(separator: "\n")
        try? specContent.write(toFile: specPath, atomically: true, encoding: .utf8)

        // Remove the detached tile
        removeElement(tileId)

        // Clean up the temp file
        try? FileManager.default.removeItem(atPath: docPath)
    }

    // MARK: - Persistence

    func snapshot() -> CanvasSnapshot {
        var chatMessages: [UUID: [ChatMessage]] = [:]
        for (sessionId, session) in chatSessions {
            if !session.messages.isEmpty {
                chatMessages[sessionId] = session.messages
            }
        }
        return CanvasSnapshot(
            elements: elements,
            zoom: zoom,
            panOffsetWidth: panOffset.width,
            panOffsetHeight: panOffset.height,
            chatMessages: chatMessages
        )
    }

    func restore(from snapshot: CanvasSnapshot) {
        elements = snapshot.elements
        zoom = snapshot.zoom
        panOffset = CGSize(width: snapshot.panOffsetWidth, height: snapshot.panOffsetHeight)

        // Restore chat agent sessions from persisted messages
        for element in allTiles {
            if case .tile(.chatAgent(let sessionId, let role)) = element.kind {
                let restoredSession = AgentSession(
                    id: sessionId,
                    model: role.defaultModel,
                    agentMode: AgentMode(rawValue: role.id),
                    systemPrompt: role.systemPrompt,
                    workingDirectory: worktreePath
                )
                if let messages = snapshot.chatMessages[sessionId] {
                    restoredSession.messages = messages
                    restoredSession.totalInputTokens = messages.reduce(0) { $0 + $1.inputTokens }
                    restoredSession.totalOutputTokens = messages.reduce(0) { $0 + $1.outputTokens }
                }
                chatManager.sessions[sessionId] = restoredSession
                chatSessions[sessionId] = restoredSession
            }
        }

        // Restore terminal tile panels (empty shells — user relaunches Claude manually)
        restoreTerminalPanels()
    }

    func saveNow() {
        do {
            try CanvasPersistence.save(snapshot(), to: worktreePath)
        } catch {
            print("[CanvasPersistence] Save failed: \(error)")
        }
    }

    private func scheduleSave() {
        saveDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.saveNow()
            }
        }
        saveDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    // MARK: - Cleanup

    func closeAll() {
        for panel in terminals.values {
            panel.close()
        }
        terminals.removeAll()
        for sessionId in chatSessions.keys {
            chatManager.cancel(sessionId: sessionId)
        }
        chatSessions.removeAll()
        elements.removeAll()
    }

    // MARK: - Private

    private func didMutate() {
        mutationCount += 1
        ContextManifest.write(canvas: self)
        scheduleSave()
    }

    func findElement(_ id: UUID) -> CanvasElement? {
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
            } else if case .chatAgent(let sessionId, _) = tileType {
                chatManager.cancel(sessionId: sessionId)
                chatSessions.removeValue(forKey: sessionId)
            }
        case .frame(let data):
            for child in data.children {
                cleanupElement(child)
            }
        case .text:
            break
        }
    }

    private func restoreTerminalPanels() {
        // Check root elements
        for i in elements.indices {
            if case .tile(.terminal(let panelId, let agent)) = elements[i].kind {
                if terminals[panelId] == nil {
                    let panel = TerminalPanel(workingDirectory: worktreePath)
                    terminals[panel.id] = panel
                    elements[i].kind = .tile(.terminal(panelId: panel.id, agent: agent))
                }
            }
            // Check frame children
            if case .frame(var frameData) = elements[i].kind {
                var changed = false
                for j in frameData.children.indices {
                    if case .tile(.terminal(let panelId, let agent)) = frameData.children[j].kind {
                        if terminals[panelId] == nil {
                            let panel = TerminalPanel(workingDirectory: worktreePath)
                            terminals[panel.id] = panel
                            frameData.children[j].kind = .tile(.terminal(panelId: panel.id, agent: agent))
                            changed = true
                        }
                    }
                }
                if changed {
                    elements[i].kind = .frame(frameData)
                }
            }
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
                worktreePath: self.worktreePath,
                panelId: panel.id
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
