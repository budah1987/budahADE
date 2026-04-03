import SwiftUI

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
                .fill(Theme.Colors.sidebarBackground.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isDropTarget ? Theme.Colors.accent.opacity(0.6) : Theme.Colors.borderSubtle,
                            lineWidth: isDropTarget ? 2 : 0.5
                        )
                )
        )
    }

    private var frameHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.Colors.textTertiary)

            if isEditingTitle {
                TextField("Frame", text: $editTitle)
                    .textFieldStyle(.plain)
                    .font(Theme.label(14))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .onSubmit {
                        canvas.renameElement(element.id, to: editTitle)
                        isEditingTitle = false
                    }
            } else {
                Text(element.title.isEmpty ? "Frame" : element.title)
                    .font(Theme.label(14))
                    .foregroundColor(Theme.Colors.textSecondary)
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
                    .foregroundColor(Theme.Colors.textTertiary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.Colors.hoverFill)
                    )
            }
            .buttonStyle(.plain)

            Button {
                canvas.removeElement(element.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Theme.Colors.textTertiary)
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
                .foregroundColor(Theme.Colors.textTertiary)
            Text("Drag tiles here or right-click to add")
                .font(Theme.caption(11))
                .foregroundColor(Theme.Colors.textTertiary)
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
                .fill(Theme.Colors.accent)
                .frame(width: 3, height: frameData.children.first?.size.height ?? 100)
                .offset(x: indicatorPos.x - 1.5, y: indicatorPos.y)
        } else {
            RoundedRectangle(cornerRadius: 1)
                .fill(Theme.Colors.accent)
                .frame(width: frameData.children.first?.size.width ?? 200, height: 3)
                .offset(x: indicatorPos.x, y: indicatorPos.y - 1.5)
        }
    }
}
