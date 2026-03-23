import SwiftUI

// MARK: - Canvas Element View (dispatch)

struct CanvasElementView: View {
    let element: CanvasElement
    @ObservedObject var canvas: PlanCanvasState
    var isInsideFrame: Bool = false

    @State private var dragOffset: CGSize = .zero
    @State private var isHovered = false

    private var isSelected: Bool { canvas.selectedId == element.id }

    var body: some View {
        Group {
            if isInsideFrame {
                // Inside a frame: no drag, no position transform, content is interactive
                elementContent
                    .frame(width: element.size.width, height: element.size.height)
                    .background(elementBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isSelected ? Theme.accent.opacity(0.6) : Color.white.opacity(0.10),
                                lineWidth: isSelected ? 1.5 : 0.5
                            )
                    )
                    .overlay(alignment: .topTrailing) {
                        specSectionBadge
                    }
                    .overlay {
                        if isSelected, case .tile = element.kind {
                            FrameChildResizeHandle(element: element, canvas: canvas)
                        }
                    }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            canvas.selectedId = element.id
                        }
                    )
            } else {
                // Free on canvas: draggable, positioned, selectable
                elementContent
                    .frame(width: element.size.width, height: element.size.height)
                    .background(elementBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(selectionBorder)
                    .overlay(alignment: .topTrailing) {
                        specSectionBadge
                    }
                    .overlay {
                        if isSelected, case .tile = element.kind {
                            ResizeHandles(element: element, canvas: canvas)
                        }
                        if isSelected, case .text = element.kind {
                            ResizeHandles(element: element, canvas: canvas)
                        }
                    }
                    // Text style toolbar — floats above, outside clipShape
                    .overlay(alignment: .top) {
                        if isSelected, case .text(let td) = element.kind {
                            TextStyleToolbar(element: element, textData: td, canvas: canvas)
                                .offset(y: -38)
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .animation(.easeOut(duration: 0.2), value: isSelected)
                        }
                    }
                    .shadow(
                        color: .black.opacity(isSelected ? 0.25 : 0.15),
                        radius: isSelected ? 10 : 4,
                        y: 2
                    )
                    .position(
                        x: element.position.x + element.size.width / 2 + dragOffset.width,
                        y: element.position.y + element.size.height / 2 + dragOffset.height
                    )
                    .onTapGesture {
                        canvas.selectedId = element.id
                        canvas.bringToFront(element.id)
                    }
                    .onHover { hovering in
                        isHovered = hovering
                        if hovering && !isSelected {
                            NSCursor.openHand.push()
                        } else if !hovering {
                            NSCursor.pop()
                        }
                    }
                    .gesture(borderDragGesture)
            }
        }
    }

    // MARK: - Spec Section Badge

    @ViewBuilder
    private var specSectionBadge: some View {
        if let section = element.specSection,
           let kind = SpecSectionKind.allCases.first(where: { $0.rawValue == section }) {
            HStack(spacing: 3) {
                Image(systemName: kind.iconName)
                    .font(.system(size: 8, weight: .bold))
                Text(kind.displayName)
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundColor(Color(hex: kind.badgeColor))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color(hex: kind.badgeColor).opacity(0.15))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color(hex: kind.badgeColor).opacity(0.3), lineWidth: 0.5)
                    )
            )
            .padding(6)
        }
    }

    // MARK: - Content Dispatch

    @ViewBuilder
    private var elementContent: some View {
        switch element.kind {
        case .tile(let tileType):
            TileContentView(tileType: tileType, elementId: element.id, canvas: canvas)

        case .frame(let frameData):
            FrameContentView(
                element: element,
                frameData: frameData,
                canvas: canvas
            )

        case .text(let textData):
            TextContentView(
                element: element,
                textData: textData,
                canvas: canvas
            )
        }
    }

    // MARK: - Background & Border

    @ViewBuilder
    private var elementBackground: some View {
        switch element.kind {
        case .tile:
            Theme.contentBg
        case .frame:
            Color.clear
        case .text:
            Color.clear
        }
    }

    @ViewBuilder
    private var selectionBorder: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1.5)
        } else if isHovered {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        }
    }

    // MARK: - Border Drag Gesture

    private var borderDragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                // Yield to resize gesture
                guard canvas.resizingId == nil else { return }

                if canvas.draggingId != element.id {
                    NSCursor.closedHand.push()
                }
                let translation = CGSize(
                    width: value.translation.width / canvas.zoom,
                    height: value.translation.height / canvas.zoom
                )
                dragOffset = translation
                canvas.draggingId = element.id

                // Compute smart guides
                let proposedRect = CGRect(
                    origin: CGPoint(
                        x: element.position.x + translation.width,
                        y: element.position.y + translation.height
                    ),
                    size: element.size
                )
                let otherRects = canvas.elements
                    .filter { $0.id != element.id }
                    .map { CGRect(origin: $0.position, size: $0.size) }

                let result = SmartGuides.compute(moving: proposedRect, others: otherRects)
                canvas.guides = result.guides
                dragOffset = CGSize(
                    width: translation.width + result.snapDelta.width,
                    height: translation.height + result.snapDelta.height
                )

                // Check if hovering over a frame (for drag-into feedback)
                if case .tile = element.kind {
                    let tileRect = CGRect(
                        origin: CGPoint(
                            x: element.position.x + dragOffset.width,
                            y: element.position.y + dragOffset.height
                        ),
                        size: element.size
                    )
                    if let targetFrame = canvas.elements.first(where: { other in
                        guard other.id != element.id, case .frame = other.kind else { return false }
                        let frameRect = CGRect(origin: other.position, size: other.size)
                        return frameRect.intersects(tileRect)
                    }) {
                        canvas.hoveredFrameId = targetFrame.id
                        // Compute insertion index
                        if case .frame(let fData) = targetFrame.kind {
                            let positions = fData.childPositions()
                            let tileMid = CGPoint(x: tileRect.midX, y: tileRect.midY)
                            let relativePoint = CGPoint(
                                x: tileMid.x - targetFrame.position.x,
                                y: tileMid.y - targetFrame.position.y
                            )
                            var idx = fData.children.count
                            for (i, pos) in positions.enumerated() {
                                let childMid: CGFloat
                                if fData.axis == .horizontal {
                                    childMid = pos.x + fData.children[i].size.width / 2
                                    if relativePoint.x < childMid { idx = i; break }
                                } else {
                                    childMid = pos.y + fData.children[i].size.height / 2
                                    if relativePoint.y < childMid { idx = i; break }
                                }
                            }
                            canvas.frameInsertIndex = idx
                        }
                    } else {
                        canvas.hoveredFrameId = nil
                        canvas.frameInsertIndex = nil
                    }
                }
            }
            .onEnded { _ in
                // If resize was active, just clean up
                guard canvas.resizingId == nil else {
                    dragOffset = .zero
                    return
                }

                NSCursor.pop()
                let newPosition = CGPoint(
                    x: element.position.x + dragOffset.width,
                    y: element.position.y + dragOffset.height
                )

                // Check if dropped on a frame (reparent into frame)
                if case .tile = element.kind {
                    let tileRect = CGRect(origin: newPosition, size: element.size)
                    if let targetFrame = canvas.elements.first(where: { other in
                        guard other.id != element.id, case .frame = other.kind else { return false }
                        let frameRect = CGRect(origin: other.position, size: other.size)
                        return frameRect.intersects(tileRect)
                    }) {
                        canvas.reparent(element.id, into: targetFrame.id, at: canvas.frameInsertIndex)
                        dragOffset = .zero
                        canvas.draggingId = nil
                        canvas.hoveredFrameId = nil
                        canvas.frameInsertIndex = nil
                        canvas.guides = []
                        return
                    }
                }

                let snapped = GridSnap.snapPoint(newPosition)
                canvas.moveElement(element.id, to: snapped)
                dragOffset = .zero
                canvas.draggingId = nil
                canvas.hoveredFrameId = nil
                canvas.frameInsertIndex = nil
                canvas.guides = []
            }
    }
}

// MARK: - Tile Content View

private struct TileContentView: View {
    let tileType: TileType
    let elementId: UUID
    @ObservedObject var canvas: PlanCanvasState

    var body: some View {
        switch tileType {
        case .terminal(let panelId, let agent):
            if let panel = canvas.terminals[panelId] {
                TerminalTileView(panel: panel, agent: agent) {
                    canvas.removeElement(elementId)
                }
            }

        case .stickyNote:
            Text("Sticky Note - TODO")

        case .textBox:
            Text("Text Box - TODO")

        case .markdown(let path):
            // Temporarily use SpecDocumentTileView until Task 6 replaces it
            SpecDocumentTileView(path: path, canvas: canvas, elementId: elementId) {
                canvas.removeElement(elementId)
            }

        case .image(let path):
            ImageTileView(path: path) {
                canvas.removeElement(elementId)
            }

        case .browser(let url):
            BrowserTileView(url: url) {
                canvas.removeElement(elementId)
            }
        }
    }
}

// MARK: - Frame Content View

struct FrameContentView: View {
    let element: CanvasElement
    let frameData: FrameData
    @ObservedObject var canvas: PlanCanvasState

    @State private var isEditingTitle = false
    @State private var editTitle: String = ""

    private var isDropTarget: Bool {
        canvas.hoveredFrameId == element.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            frameHeader

            if frameData.children.isEmpty {
                emptyFrameContent
            } else {
                childrenStack
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.surface1.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isDropTarget ? Theme.accent.opacity(0.6) : Theme.borderSubtle,
                            lineWidth: isDropTarget ? 2 : 0.5
                        )
                )
        )
    }

    private var frameHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textMuted)

            if isEditingTitle {
                TextField("Frame", text: $editTitle)
                    .textFieldStyle(.plain)
                    .font(Theme.label(14))
                    .foregroundColor(Theme.textPrimary)
                    .onSubmit {
                        canvas.renameElement(element.id, to: editTitle)
                        isEditingTitle = false
                    }
            } else {
                Text(element.title.isEmpty ? "Frame" : element.title)
                    .font(Theme.label(14))
                    .foregroundColor(Theme.textSecondary)
                    .onTapGesture(count: 2) {
                        editTitle = element.title
                        isEditingTitle = true
                    }
            }

            Spacer()

            // Axis toggle
            Button {
                canvas.toggleFrameAxis(element.id)
            } label: {
                Image(systemName: frameData.axis == .horizontal
                    ? "arrow.left.arrow.right" : "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.hoverFill)
                    )
            }
            .buttonStyle(.plain)

            Button {
                canvas.removeElement(element.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: frameData.headerHeight)
    }

    private var emptyFrameContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus.rectangle.on.rectangle")
                .font(.system(size: 20, weight: .thin))
                .foregroundColor(Theme.textMuted)
            Text("Drag tiles here or right-click to add")
                .font(Theme.caption(11))
                .foregroundColor(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(frameData.padding)
    }

    @ViewBuilder
    private var childrenStack: some View {
        let positions = frameData.childPositions()
        let showIndicator = isDropTarget && canvas.frameInsertIndex != nil
        // Explicit content area size so hit-testing covers all offset children
        let contentWidth = element.size.width
        let contentHeight = element.size.height - frameData.headerHeight

        ZStack(alignment: .topLeading) {
            // Transparent background to establish hit area for the full content region
            Color.clear
                .frame(width: contentWidth, height: contentHeight)
                .allowsHitTesting(false)

            ForEach(Array(frameData.children.enumerated()), id: \.element.id) { index, child in
                if index < positions.count {
                    CanvasElementView(element: child, canvas: canvas, isInsideFrame: true)
                        .frame(width: child.size.width, height: child.size.height)
                        .offset(
                            x: positions[index].x,
                            y: positions[index].y - frameData.headerHeight
                        )
                }
            }

            // Insertion indicator
            if showIndicator, let insertIdx = canvas.frameInsertIndex {
                insertionIndicator(at: insertIdx, positions: positions)
            }
        }
        .frame(width: contentWidth, height: contentHeight)
        .clipped()
    }

    @ViewBuilder
    private func insertionIndicator(at index: Int, positions: [CGPoint]) -> some View {
        // Positions are frame-relative (include headerHeight); subtract it for ZStack-relative coords
        let hh = frameData.headerHeight
        let indicatorPos: CGPoint = {
            if frameData.children.isEmpty || positions.isEmpty {
                return CGPoint(x: frameData.padding, y: frameData.padding)
            }
            if index >= frameData.children.count {
                let lastPos = positions[positions.count - 1]
                let lastChild = frameData.children[positions.count - 1]
                if frameData.axis == .horizontal {
                    return CGPoint(x: lastPos.x + lastChild.size.width + frameData.gap / 2, y: lastPos.y - hh)
                } else {
                    return CGPoint(x: lastPos.x, y: lastPos.y - hh + lastChild.size.height + frameData.gap / 2)
                }
            }
            let pos = positions[index]
            if frameData.axis == .horizontal {
                return CGPoint(x: pos.x - frameData.gap / 2, y: pos.y - hh)
            } else {
                return CGPoint(x: pos.x, y: pos.y - hh - frameData.gap / 2)
            }
        }()

        if frameData.axis == .horizontal {
            RoundedRectangle(cornerRadius: 1)
                .fill(Theme.accent)
                .frame(width: 3, height: frameData.children.first?.size.height ?? 100)
                .offset(x: indicatorPos.x - 1.5, y: indicatorPos.y)
        } else {
            RoundedRectangle(cornerRadius: 1)
                .fill(Theme.accent)
                .frame(width: frameData.children.first?.size.width ?? 200, height: 3)
                .offset(x: indicatorPos.x, y: indicatorPos.y - 1.5)
        }
    }
}

// MARK: - Text Content View

struct TextContentView: View {
    let element: CanvasElement
    let textData: TextData
    @ObservedObject var canvas: PlanCanvasState

    @State private var isEditing = false
    @State private var editContent: String = ""

    private var isSelected: Bool { canvas.selectedId == element.id }

    var body: some View {
        VStack(spacing: 0) {
            if isEditing {
                TextField("Type text...", text: $editContent, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(textData.font)
                    .foregroundColor(textData.color)
                    .onSubmit {
                        commitEdit()
                    }
                    .onExitCommand {
                        commitEdit()
                    }
            } else {
                Text(textData.content)
                    .font(textData.font)
                    .italic(textData.isItalic)
                    .foregroundColor(textData.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        editContent = textData.content
                        isEditing = true
                    }
            }
        }
        .padding(8)
    }

    private func commitEdit() {
        isEditing = false
        var updated = textData
        updated.content = editContent
        canvas.updateText(element.id, data: updated)
    }

}

// MARK: - Text Style Toolbar (floats above text element)

struct TextStyleToolbar: View {
    let element: CanvasElement
    let textData: TextData
    @ObservedObject var canvas: PlanCanvasState

    var body: some View {
        HStack(spacing: 4) {
            tButton("B", isActive: textData.isBold, weight: .bold) {
                var updated = textData
                updated.isBold.toggle()
                canvas.updateText(element.id, data: updated)
            }

            tButton("I", isActive: textData.isItalic, italic: true) {
                var updated = textData
                updated.isItalic.toggle()
                canvas.updateText(element.id, data: updated)
            }

            Divider().frame(height: 14).padding(.horizontal, 2)

            Menu {
                ForEach([12, 14, 16, 20, 24, 32, 48, 64], id: \.self) { size in
                    Button("\(size)px") {
                        var updated = textData
                        updated.fontSize = CGFloat(size)
                        canvas.updateText(element.id, data: updated)
                    }
                }
            } label: {
                Text("\(Int(textData.fontSize))")
                    .font(Theme.mono(10))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.surface3.cornerRadius(3))
            }

            Menu {
                ForEach(TextWeight.allCases, id: \.self) { weight in
                    Button(weight.rawValue.capitalized) {
                        var updated = textData
                        updated.weight = weight
                        canvas.updateText(element.id, data: updated)
                    }
                }
            } label: {
                Text(textData.weight.rawValue.prefix(3).uppercased())
                    .font(Theme.mono(10))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.surface3.cornerRadius(3))
            }

            Menu {
                ForEach(TextFontFamily.allCases, id: \.self) { family in
                    Button(family.rawValue.capitalized) {
                        var updated = textData
                        updated.fontFamily = family
                        canvas.updateText(element.id, data: updated)
                    }
                }
            } label: {
                Text(textData.fontFamily.rawValue.prefix(4).uppercased())
                    .font(Theme.mono(10))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.surface3.cornerRadius(3))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.surface2)
                .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
        )
    }

    private func tButton(_ label: String, isActive: Bool, weight: Font.Weight = .regular, italic: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: weight))
                .italic(italic)
                .foregroundColor(isActive ? Theme.textPrimary : Theme.textMuted)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isActive ? Theme.selectedFill : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

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

private struct CornerHandle: View {
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

private struct EdgeHandle: View {
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
