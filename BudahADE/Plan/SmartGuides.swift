import SwiftUI

// MARK: - Canvas Grid Constants

enum CanvasGrid {
    static let unit: CGFloat = 20       // minor grid spacing (matches dot grid)
    static let majorEvery: Int = 4      // major grid every 4th unit = 80px
}

// MARK: - Grid Snapping

enum GridSnap {
    /// Snap a point to the nearest grid intersection
    static func snapPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x / CanvasGrid.unit).rounded() * CanvasGrid.unit,
            y: (point.y / CanvasGrid.unit).rounded() * CanvasGrid.unit
        )
    }

    /// Snap a size to the nearest grid increment, respecting minimum size
    static func snapSize(_ size: CGSize, min minSize: CGSize) -> CGSize {
        CGSize(
            width: max((size.width / CanvasGrid.unit).rounded() * CanvasGrid.unit, minSize.width),
            height: max((size.height / CanvasGrid.unit).rounded() * CanvasGrid.unit, minSize.height)
        )
    }
}

// MARK: - Alignment Guide

struct AlignmentGuide: Identifiable, Equatable {
    let id = UUID()
    let orientation: Axis     // .horizontal = horizontal line, .vertical = vertical line
    let position: CGFloat     // x for vertical, y for horizontal
    let start: CGFloat        // start of the guide line
    let end: CGFloat          // end of the guide line

    static func == (lhs: AlignmentGuide, rhs: AlignmentGuide) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Guide Computation

enum SmartGuides {

    static let snapThreshold: CGFloat = 4.0

    /// Compute alignment guides for a moving element against other elements
    static func compute(
        moving: CGRect,
        others: [CGRect]
    ) -> (guides: [AlignmentGuide], snapDelta: CGSize) {
        var guides: [AlignmentGuide] = []
        var snapDX: CGFloat = 0
        var snapDY: CGFloat = 0

        // Edges and centers of moving element
        let movingEdges = ElementEdges(rect: moving)

        for other in others {
            let otherEdges = ElementEdges(rect: other)

            // Vertical alignment (x-axis)
            for (mX, oX) in verticalPairs(movingEdges, otherEdges) {
                let diff = oX - mX
                if abs(diff) < snapThreshold {
                    snapDX = diff
                    let minY = min(moving.minY, other.minY) - 8
                    let maxY = max(moving.maxY, other.maxY) + 8
                    guides.append(AlignmentGuide(
                        orientation: .vertical,
                        position: oX,
                        start: minY,
                        end: maxY
                    ))
                }
            }

            // Horizontal alignment (y-axis)
            for (mY, oY) in horizontalPairs(movingEdges, otherEdges) {
                let diff = oY - mY
                if abs(diff) < snapThreshold {
                    snapDY = diff
                    let minX = min(moving.minX, other.minX) - 8
                    let maxX = max(moving.maxX, other.maxX) + 8
                    guides.append(AlignmentGuide(
                        orientation: .horizontal,
                        position: oY,
                        start: minX,
                        end: maxX
                    ))
                }
            }
        }

        return (guides, CGSize(width: snapDX, height: snapDY))
    }

    private static func verticalPairs(
        _ m: ElementEdges, _ o: ElementEdges
    ) -> [(CGFloat, CGFloat)] {
        [
            (m.left, o.left),
            (m.left, o.right),
            (m.right, o.left),
            (m.right, o.right),
            (m.centerX, o.centerX),
        ]
    }

    private static func horizontalPairs(
        _ m: ElementEdges, _ o: ElementEdges
    ) -> [(CGFloat, CGFloat)] {
        [
            (m.top, o.top),
            (m.top, o.bottom),
            (m.bottom, o.top),
            (m.bottom, o.bottom),
            (m.centerY, o.centerY),
        ]
    }
}

// MARK: - Element Edges

private struct ElementEdges {
    let left: CGFloat
    let right: CGFloat
    let top: CGFloat
    let bottom: CGFloat
    let centerX: CGFloat
    let centerY: CGFloat

    init(rect: CGRect) {
        left = rect.minX
        right = rect.maxX
        top = rect.minY
        bottom = rect.maxY
        centerX = rect.midX
        centerY = rect.midY
    }
}

// MARK: - Guide Overlay View

struct SmartGuidesOverlay: View {
    let guides: [AlignmentGuide]

    var body: some View {
        Canvas { context, _ in
            for guide in guides {
                var path = Path()
                switch guide.orientation {
                case .vertical:
                    path.move(to: CGPoint(x: guide.position, y: guide.start))
                    path.addLine(to: CGPoint(x: guide.position, y: guide.end))
                case .horizontal:
                    path.move(to: CGPoint(x: guide.start, y: guide.position))
                    path.addLine(to: CGPoint(x: guide.end, y: guide.position))
                }
                context.stroke(
                    path,
                    with: .color(.red.opacity(0.6)),
                    lineWidth: 0.5
                )
            }
        }
        .allowsHitTesting(false)
    }
}
