import SwiftUI

// MARK: - Split Orientation

enum SplitOrientation {
    case horizontal
    case vertical
}

// MARK: - Pane Layout

struct PaneLayout<First: View, Second: View>: View {
    let orientation: SplitOrientation
    let first: First
    let second: Second

    @State private var splitRatio: CGFloat = 0.5

    init(
        orientation: SplitOrientation = .horizontal,
        @ViewBuilder first: () -> First,
        @ViewBuilder second: () -> Second
    ) {
        self.orientation = orientation
        self.first = first()
        self.second = second()
    }

    var body: some View {
        GeometryReader { geometry in
            let totalSize = orientation == .horizontal
                ? geometry.size.width
                : geometry.size.height
            let firstSize = totalSize * splitRatio
            let secondSize = totalSize - firstSize - 4 // 4px divider

            switch orientation {
            case .horizontal:
                HStack(spacing: 0) {
                    first
                        .frame(width: firstSize)
                    divider(totalSize: totalSize)
                    second
                        .frame(width: secondSize)
                }
            case .vertical:
                VStack(spacing: 0) {
                    first
                        .frame(height: firstSize)
                    divider(totalSize: totalSize)
                    second
                        .frame(height: secondSize)
                }
            }
        }
    }

    // MARK: - Divider

    private func divider(totalSize: CGFloat) -> some View {
        let isHorizontal = orientation == .horizontal

        return Rectangle()
            .fill(Theme.border)
            .frame(
                width: isHorizontal ? 4 : nil,
                height: isHorizontal ? nil : 4
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    if isHorizontal {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.resizeUpDown.push()
                    }
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let delta = isHorizontal
                            ? value.translation.width
                            : value.translation.height
                        let newRatio = splitRatio + (delta / totalSize)
                        splitRatio = min(max(newRatio, 0.15), 0.85)
                    }
            )
    }
}
