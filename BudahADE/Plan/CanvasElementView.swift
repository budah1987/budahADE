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
                    .background(TileSelectionChrome.elementBackground(for: element))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isSelected ? Theme.accent.opacity(0.6) : Color.white.opacity(0.10),
                                lineWidth: isSelected ? 1.5 : 0.5
                            )
                    )
                    .overlay(alignment: .topTrailing) {
                        TileSelectionChrome.specSectionBadge(for: element)
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
                    .background(TileSelectionChrome.elementBackground(for: element))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(TileSelectionChrome.selectionBorder(isSelected: isSelected, isHovered: isHovered))
                    .overlay(alignment: .topTrailing) {
                        TileSelectionChrome.specSectionBadge(for: element)
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
                    .gesture(tileDragGesture(element: element, canvas: canvas, dragOffset: $dragOffset))
            }
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
            StickyNoteView(elementId: elementId, canvas: canvas) {
                canvas.removeElement(elementId)
            }

        case .textBox:
            TextBoxView(elementId: elementId, canvas: canvas) {
                canvas.removeElement(elementId)
            }

        case .markdown(let path):
            MarkdownTileView(
                path: path,
                canvas: canvas,
                elementId: elementId
            ) {
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
