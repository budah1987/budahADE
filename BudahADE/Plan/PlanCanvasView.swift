import SwiftUI
import UniformTypeIdentifiers

struct PlanCanvasView: View {
    @ObservedObject var canvas: PlanCanvasState
    @State private var lastZoom: CGFloat = 1.0
    @State private var contextMenuPosition: CGPoint = .zero
    @State private var mousePosition: CGPoint? = nil
    @State private var viewportSize: CGSize = .zero

    // Local viewport state — avoids @Published rebuilds during gestures
    @State private var localZoom: CGFloat = 1.0
    @State private var localPanOffset: CGSize = .zero

    // Spacebar panning
    @State private var isSpacePanning: Bool = false

    // Debounced commit to canvas state
    @State private var commitTask: DispatchWorkItem?

    // Viewport culling cache
    @State private var cachedVisibleIds: Set<UUID> = []
    @State private var cullingDebounce: DispatchWorkItem?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background layer (dot grid)
                canvasBackground

                // Connections layer (arrows between tiles, in canvas coords)
                ConnectionsLayer(canvas: canvas)
                    .scaleEffect(localZoom, anchor: .topLeading)
                    .offset(localPanOffset)

                // Content layer (zoom + pan transform)
                canvasContent
                    .allowsHitTesting(!isSpacePanning)

                // Connection ports layer (above tiles so drag gesture wins)
                ConnectionPortsLayer(canvas: canvas, hoveredElementId: canvas.hoveredTileId)
                    .scaleEffect(localZoom, anchor: .topLeading)
                    .offset(localPanOffset)
                    .allowsHitTesting(!isSpacePanning)

                // Smart guides overlay (in canvas coords, transformed)
                SmartGuidesOverlay(guides: canvas.guides)
                    .scaleEffect(localZoom, anchor: .topLeading)
                    .offset(localPanOffset)
                    .allowsHitTesting(false)

                // HUD (not affected by zoom)
                hudOverlay

                // Empty state
                if canvas.elements.isEmpty {
                    emptyCanvas
                        .allowsHitTesting(false)
                }
            }
            .onAppear {
                viewportSize = geo.size
                syncFromCanvas()
                debounceCulling()
            }
            .onChange(of: geo.size) { _, new in viewportSize = new }
            .onChange(of: localZoom) { _, _ in debounceCulling() }
            .onChange(of: localPanOffset) { _, _ in debounceCulling() }
            .onChange(of: canvas.mutationCount) { _, _ in debounceCulling() }
            .background(
                CanvasInputMonitor(
                    onScroll: { deltaX, deltaY, isZoom, isShiftPan in
                        if isZoom {
                            let newZoom = (localZoom + deltaY * 0.01).clamped(to: 0.1...3.0)
                            if let anchor = mousePosition {
                                zoomAtLocal(newZoom: newZoom, screenAnchor: anchor)
                            } else {
                                localZoom = newZoom
                            }
                            commitViewportToCanvas()
                        } else {
                            let horizontalMultiplier: CGFloat = isShiftPan ? 3.0 : 1.0
                            localPanOffset = CGSize(
                                width: localPanOffset.width + deltaX * horizontalMultiplier,
                                height: localPanOffset.height + deltaY
                            )
                            commitViewportToCanvas()
                        }
                    },
                    onPanDrag: { deltaX, deltaY in
                        localPanOffset = CGSize(
                            width: localPanOffset.width + deltaX,
                            height: localPanOffset.height + deltaY
                        )
                        commitViewportToCanvas()
                    },
                    onSpaceStateChanged: { isHeld in
                        isSpacePanning = isHeld
                    },
                    onEscape: {
                        canvas.selectedId = nil
                    }
                )
            )
            .gesture(canvasZoomGesture)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    mousePosition = point
                    contextMenuPosition = screenToCanvasLocal(point)
                case .ended:
                    mousePosition = nil
                }
            }
            .contextMenu {
                canvasContextMenu(at: contextMenuPosition)
            }
            .onTapGesture {
                canvas.selectedId = nil
            }
            .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
                handleDrop(providers)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .canvasResetZoom)) { _ in
            canvas.resetZoom()
            syncFromCanvas()
            lastZoom = 1.0
        }
        .onReceive(NotificationCenter.default.publisher(for: .canvasZoomToFit)) { _ in
            canvas.zoomToFit(viewportSize: viewportSize)
            syncFromCanvas()
            lastZoom = localZoom
        }
        // Sync when canvas state changes externally (e.g. resetZoom animation)
        .onChange(of: canvas.zoom) { _, new in
            if abs(localZoom - new) > 0.001 { localZoom = new }
        }
        .onChange(of: canvas.panOffset.width) { _, _ in
            let cp = canvas.panOffset
            if abs(localPanOffset.width - cp.width) > 0.5 ||
               abs(localPanOffset.height - cp.height) > 0.5 {
                localPanOffset = cp
            }
        }
    }

    // MARK: - Local Viewport Helpers

    private func syncFromCanvas() {
        localZoom = canvas.zoom
        localPanOffset = canvas.panOffset
    }

    private func commitViewportToCanvas() {
        // Debounce: only push to @Published after gestures settle (150ms)
        // This prevents full view tree rebuilds on every scroll frame
        commitTask?.cancel()
        let task = DispatchWorkItem { [localZoom, localPanOffset] in
            canvas.zoom = localZoom
            canvas.panOffset = localPanOffset
        }
        commitTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
    }

    private func zoomAtLocal(newZoom: CGFloat, screenAnchor: CGPoint) {
        let clamped = newZoom.clamped(to: 0.1...3.0)
        let canvasX = (screenAnchor.x - localPanOffset.width) / localZoom
        let canvasY = (screenAnchor.y - localPanOffset.height) / localZoom
        localZoom = clamped
        localPanOffset = CGSize(
            width: screenAnchor.x - canvasX * clamped,
            height: screenAnchor.y - canvasY * clamped
        )
    }

    private func screenToCanvasLocal(_ screenPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (screenPoint.x - localPanOffset.width) / localZoom,
            y: (screenPoint.y - localPanOffset.height) / localZoom
        )
    }

    // MARK: - Canvas Background

    private var canvasBackground: some View {
        Canvas { context, size in
            let spacing: CGFloat = CanvasGrid.unit * localZoom
            guard spacing > 2 else { return }

            let offsetX = localPanOffset.width.truncatingRemainder(dividingBy: spacing)
            let offsetY = localPanOffset.height.truncatingRemainder(dividingBy: spacing)

            // Compute grid index origin so we know which dots are major
            let originGridX = Int((-localPanOffset.width / spacing).rounded(.down))
            let originGridY = Int((-localPanOffset.height / spacing).rounded(.down))

            let minorColor = Color.white.opacity(0.10)
            let majorColor = Color.white.opacity(0.22)
            let minorSize: CGFloat = 1.5
            let majorSize: CGFloat = 2.5
            let majorN = CanvasGrid.majorEvery

            var ix = 0
            var x = offsetX
            while x < size.width {
                var iy = 0
                var y = offsetY
                while y < size.height {
                    let gx = originGridX + ix
                    let gy = originGridY + iy
                    let isMajor = (gx % majorN == 0) && (gy % majorN == 0)
                    let dotSize = isMajor ? majorSize : minorSize
                    let color = isMajor ? majorColor : minorColor

                    let rect = CGRect(
                        x: x - dotSize / 2,
                        y: y - dotSize / 2,
                        width: dotSize,
                        height: dotSize
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                    y += spacing
                    iy += 1
                }
                x += spacing
                ix += 1
            }
        }
        .background(Theme.appBackground)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Canvas Content (with viewport culling)

    private var canvasContent: some View {
        ZStack {
            ForEach(visibleElements) { element in
                CanvasElementView(element: element, canvas: canvas)
            }
        }
        .coordinateSpace(name: "canvasContent")
        .scaleEffect(localZoom, anchor: .topLeading)
        .offset(localPanOffset)
    }

    /// Only render elements whose screen-space rect intersects the viewport.
    /// Uses a debounced cache to avoid recomputing on every gesture frame.
    private var visibleElements: [CanvasElement] {
        if cachedVisibleIds.isEmpty {
            return canvas.elements // first render before debounce fires
        }
        return canvas.elements.filter { cachedVisibleIds.contains($0.id) }
    }

    private func debounceCulling() {
        cullingDebounce?.cancel()
        let zoom = localZoom
        let offset = localPanOffset
        let vpSize = viewportSize
        let elements = canvas.elements
        let task = DispatchWorkItem {
            let margin: CGFloat = 100
            let viewport = CGRect(
                x: -margin, y: -margin,
                width: vpSize.width + margin * 2,
                height: vpSize.height + margin * 2
            )
            let ids = Set(elements.filter { el in
                let screenRect = CGRect(
                    x: el.position.x * zoom + offset.width,
                    y: el.position.y * zoom + offset.height,
                    width: el.size.width * zoom,
                    height: el.size.height * zoom
                )
                return viewport.intersects(screenRect)
            }.map(\.id))
            cachedVisibleIds = ids
        }
        cullingDebounce = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: task)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func canvasContextMenu(at position: CGPoint) -> some View {
        // Agents
        Menu("Add Agent") {
            ForEach(AgentMode.allCases) { agent in
                Button {
                    canvas.addTerminalTile(agent: agent, at: position)
                } label: {
                    Label(agent.displayName, systemImage: agent.iconName)
                }
            }
        }

        Menu("Add Chat Agent") {
            ForEach(AgentMode.allCases) { agent in
                Button {
                    canvas.addChatTile(agent: agent, at: position)
                } label: {
                    Label("\(agent.displayName) Chat", systemImage: "bubble.left.and.text.bubble.right")
                }
            }
        }

        Button {
            canvas.addTile(type: .stickyNote, at: position)
        } label: {
            Label("Add Sticky Note", systemImage: "note.text")
        }

        Button {
            canvas.addText(at: position)
        } label: {
            Label("Add Text Box", systemImage: "text.alignleft")
        }

        Button {
            let name = "plan-notes-\(UUID().uuidString.prefix(4)).md"
            let path = (canvas.worktreePath as NSString).appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
            canvas.addTile(type: .markdown(path: path), at: position)
        } label: {
            Label("Add Markdown", systemImage: "doc.text")
        }

        Button {
            canvas.addTile(
                type: .browser(url: URL(string: "https://google.com")),
                at: position
            )
        } label: {
            Label("Add Browser", systemImage: "globe")
        }

        Divider()

        Menu("Add Frame") {
            Button("Horizontal") {
                canvas.addFrame(at: position, axis: .horizontal)
            }
            Button("Vertical") {
                canvas.addFrame(at: position, axis: .vertical)
            }
        }


        // Spec tagging (only when an element is selected)
        if let selectedId = canvas.selectedId {
            Divider()

            let currentTag = canvas.elements.first(where: { $0.id == selectedId })?.specSection

            Menu("Tag for Spec") {
                ForEach(SpecSectionKind.allCases) { section in
                    Button {
                        canvas.tagElement(selectedId, section: section.rawValue)
                    } label: {
                        HStack {
                            Label(section.displayName, systemImage: section.iconName)
                            if currentTag == section.rawValue {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                if currentTag != nil {
                    Divider()
                    Button("Remove Tag") {
                        canvas.untagElement(selectedId)
                    }
                }
            }
        }
    }

    // MARK: - HUD Overlay

    @State private var assembleResult: String?

    private var hudOverlay: some View {
        VStack {
            // Assembly success banner
            if let path = assembleResult {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.success)
                    Text("Spec assembled: \((path as NSString).lastPathComponent)")
                        .font(Theme.label(12))
                        .foregroundColor(Theme.textPrimary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.surface2.opacity(0.95))
                )
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation { assembleResult = nil }
                    }
                }
            }

            Spacer()

            HStack(alignment: .bottom) {
                // Zoom indicator
                Text("\(Int(localZoom * 100))%")
                    .font(Theme.mono(11))
                    .foregroundColor(Theme.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.surface2.opacity(0.8))
                    )
                    .padding(12)

                Spacer()

                // Assemble Spec button
                if hasTaggedElements {
                    Button {
                        if let path = canvas.assembleSpec() {
                            withAnimation { assembleResult = path }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.badge.gearshape")
                                .font(.system(size: 12, weight: .medium))
                            Text("Assemble Spec")
                                .font(Theme.label(12))
                        }
                        .foregroundColor(Theme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Theme.accent.opacity(0.2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Theme.accent.opacity(0.4), lineWidth: 0.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                }
            }
        }
    }

    private var hasTaggedElements: Bool {
        canvas.elements.contains(where: { $0.specSection != nil }) ||
        canvas.elements.contains(where: {
            if case .frame(let data) = $0.kind {
                return data.children.contains(where: { $0.specSection != nil })
            }
            return false
        })
    }

    // MARK: - Empty Canvas

    private var emptyCanvas: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.split.2x2")
                .font(.system(size: 32, weight: .thin))
                .foregroundColor(Theme.textMuted)
            Text("Plan your work")
                .font(Theme.headline(18))
                .foregroundColor(Theme.textPrimary)
            Text("Right-click to add tiles, frames, and text")
                .font(Theme.body(13))
                .foregroundColor(Theme.textMuted)
        }
    }

    // MARK: - Gestures

    private var canvasZoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newZoom = (lastZoom * value.magnification).clamped(to: 0.1...3.0)
                if let anchor = mousePosition {
                    zoomAtLocal(newZoom: newZoom, screenAnchor: anchor)
                } else {
                    localZoom = newZoom
                }
            }
            .onEnded { _ in
                lastZoom = localZoom
                commitViewportToCanvas()
            }
    }

    // MARK: - Drag and Drop (files)

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          url.isFileURL else { return }

                    let ext = url.pathExtension.lowercased()
                    let imageExts = ["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "tiff"]

                    Task { @MainActor in
                        let position = canvas.nextFreePosition()
                        if imageExts.contains(ext) {
                            canvas.addTile(type: .image(path: url.path), at: position)
                        } else if ext == "md" || ext == "txt" {
                            canvas.addTile(type: .markdown(path: url.path), at: position)
                        }
                    }
                }
                return true
            }
        }
        return false
    }
}
