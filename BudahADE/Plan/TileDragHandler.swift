import SwiftUI
import AppKit

// MARK: - Tile Drag Handler

/// Creates a drag gesture for moving canvas elements, with smart guides and frame reparenting.
@MainActor
func tileDragGesture(
    element: CanvasElement,
    canvas: PlanCanvasState,
    dragOffset: Binding<CGSize>
) -> some Gesture {
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
            dragOffset.wrappedValue = translation
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
            dragOffset.wrappedValue = CGSize(
                width: translation.width + result.snapDelta.width,
                height: translation.height + result.snapDelta.height
            )

            // Check if hovering over a frame (for drag-into feedback)
            if case .tile = element.kind {
                let tileRect = CGRect(
                    origin: CGPoint(
                        x: element.position.x + dragOffset.wrappedValue.width,
                        y: element.position.y + dragOffset.wrappedValue.height
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
                dragOffset.wrappedValue = .zero
                return
            }

            NSCursor.pop()
            let newPosition = CGPoint(
                x: element.position.x + dragOffset.wrappedValue.width,
                y: element.position.y + dragOffset.wrappedValue.height
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
                    dragOffset.wrappedValue = .zero
                    canvas.draggingId = nil
                    canvas.hoveredFrameId = nil
                    canvas.frameInsertIndex = nil
                    canvas.guides = []
                    return
                }
            }

            let snapped = GridSnap.snapPoint(newPosition)
            canvas.moveElement(element.id, to: snapped)
            dragOffset.wrappedValue = .zero
            canvas.draggingId = nil
            canvas.hoveredFrameId = nil
            canvas.frameInsertIndex = nil
            canvas.guides = []
        }
}
