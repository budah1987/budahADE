import SwiftUI
import UniformTypeIdentifiers

// MARK: - Split Pane State

/// Tracks which tab is shown in the secondary pane and the split direction.
struct SplitPaneState: Equatable {
    var secondaryTabId: UUID
    var orientation: SplitOrientation
}

// MARK: - Pane Position

enum PanePosition: Equatable {
    case primary
    case secondary
}

// MARK: - Pane Focus Direction

enum PaneFocusDirection {
    case next
    case previous
}

// MARK: - Drop Zone

/// Where a dragged tab can be dropped to create a split.
enum DropZone: Equatable {
    case left, right, top, bottom

    var orientation: SplitOrientation {
        switch self {
        case .left, .right: return .horizontal
        case .top, .bottom: return .vertical
        }
    }

    /// Whether the dropped tab becomes the first (leading/top) pane.
    var isFirst: Bool {
        switch self {
        case .left, .top: return true
        case .right, .bottom: return false
        }
    }
}

// MARK: - Split Drop Overlay

/// Overlay that shows drop zone highlights when a tab is dragged over the content area.
struct SplitDropOverlay: View {
    let onDrop: (DropZone, String) -> Void
    @State private var activeZone: DropZone?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                dropZone(.left, frame: leftFrame(geo))
                dropZone(.right, frame: rightFrame(geo))
                dropZone(.top, frame: topFrame(geo))
                dropZone(.bottom, frame: bottomFrame(geo))
            }
        }
        .allowsHitTesting(true)
    }

    private func dropZone(_ zone: DropZone, frame: CGRect) -> some View {
        let isActive = activeZone == zone
        return Rectangle()
            .fill(isActive ? Theme.accent.opacity(0.12) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Theme.accent.opacity(isActive ? 0.6 : 0), lineWidth: 2)
                    .padding(4)
            )
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .onDrop(of: [UTType.text], isTargeted: Binding(
                get: { activeZone == zone },
                set: { targeted in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if targeted { activeZone = zone }
                        else if activeZone == zone { activeZone = nil }
                    }
                }
            )) { providers in
                guard let provider = providers.first else { return false }
                provider.loadObject(ofClass: String.self) { tabIdString, _ in
                    if let tabIdString {
                        DispatchQueue.main.async {
                            onDrop(zone, tabIdString)
                        }
                    }
                }
                return true
            }
    }

    // MARK: - Zone Frames

    private func leftFrame(_ geo: GeometryProxy) -> CGRect {
        CGRect(x: 0, y: 0, width: geo.size.width * 0.3, height: geo.size.height)
    }

    private func rightFrame(_ geo: GeometryProxy) -> CGRect {
        CGRect(x: geo.size.width * 0.7, y: 0, width: geo.size.width * 0.3, height: geo.size.height)
    }

    private func topFrame(_ geo: GeometryProxy) -> CGRect {
        CGRect(x: geo.size.width * 0.3, y: 0, width: geo.size.width * 0.4, height: geo.size.height * 0.3)
    }

    private func bottomFrame(_ geo: GeometryProxy) -> CGRect {
        CGRect(x: geo.size.width * 0.3, y: geo.size.height * 0.7, width: geo.size.width * 0.4, height: geo.size.height * 0.3)
    }
}
