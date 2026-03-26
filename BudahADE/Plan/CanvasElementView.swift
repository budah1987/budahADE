import SwiftUI

// MARK: - Canvas Element View (dispatch)

struct CanvasElementView: View {
    let element: CanvasElement
    @ObservedObject var canvas: PlanCanvasState
    var isInsideFrame: Bool = false

    @State private var dragOffset: CGSize = .zero
    @State private var isHovered = false

    private var isSelected: Bool { canvas.selectedId == element.id }

    /// Chat tiles clip themselves — skip outer clipShape so the glow shadow isn't clipped.
    private var isChatAgentTile: Bool {
        guard case .tile(let t) = element.kind, case .chatAgent = t else { return false }
        return true
    }

    @ViewBuilder
    private func baseContent(clipped: Bool) -> some View {
        if clipped {
            elementContent
                .frame(width: element.size.width, height: element.size.height)
                .background(TileSelectionChrome.elementBackground(for: element))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            elementContent
                .frame(width: element.size.width, height: element.size.height)
                .background(TileSelectionChrome.elementBackground(for: element))
        }
    }

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
                baseContent(clipped: !isChatAgentTile)
                    .overlay(TileSelectionChrome.selectionBorder(isSelected: isSelected, isHovered: isHovered))
                    .overlay(alignment: .topTrailing) {
                        TileSelectionChrome.specSectionBadge(for: element)
                    }
                    // Close button on hover for text elements (no TileChrome = no built-in X)
                    .overlay(alignment: .topTrailing) {
                        if isHovered, case .text = element.kind {
                            Button {
                                canvas.removeElement(element.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(Theme.textMuted)
                                    .frame(width: 16, height: 16)
                                    .background(
                                        Circle()
                                            .fill(Theme.surface2)
                                            .overlay(Circle().strokeBorder(Theme.borderSubtle, lineWidth: 0.5))
                                    )
                            }
                            .buttonStyle(.plain)
                            .offset(x: 6, y: -6)
                            .transition(.opacity)
                        }
                    }
                    .overlay {
                        if isChatAgentTile {
                            ChatTileResizeOverlay(elementId: element.id, canvas: canvas)
                        } else if isSelected, case .tile = element.kind {
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
                    // Destination highlight during connection drag
                    .overlay {
                        ConnectionDestinationHighlight(element: element, canvas: canvas)
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
                    .simultaneousGesture(TapGesture().onEnded {
                        canvas.selectedId = element.id
                        canvas.bringToFront(element.id)
                    })
                    .onHover { hovering in
                        isHovered = hovering
                        if hovering {
                            canvas.hoveredTileId = element.id
                        } else if canvas.hoveredTileId == element.id {
                            canvas.hoveredTileId = nil
                        }
                        if !hovering {
                            NSCursor.arrow.set()
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
            BrowserTileView(url: url, onClose: {
                canvas.removeElement(elementId)
            }, isVisible: true)

        case .chatAgent(let sessionId, let role):
            if let session = canvas.chatSessions[sessionId] {
                ChatTileView(session: session, role: role, canvas: canvas, elementId: elementId) {
                    canvas.removeElement(elementId)
                }
            }
        }
    }
}
