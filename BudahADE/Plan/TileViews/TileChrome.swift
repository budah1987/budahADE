import SwiftUI

struct TileChrome<Content: View>: View {
    let title: String
    let icon: String
    let dotColor: Color?
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isCloseHovered = false

    init(
        title: String,
        icon: String,
        dotColor: Color? = nil,
        onClose: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.dotColor = dotColor
        self.onClose = onClose
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack(spacing: 6) {
                if let dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.textMuted)
                }

                Text(title)
                    .font(Theme.label(11))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(isCloseHovered ? Theme.textSecondary : Theme.textMuted)
                        .frame(width: 18, height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isCloseHovered ? Theme.hoverFill : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .onHover { isCloseHovered = $0 }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.surface2)

            Rectangle().fill(Theme.borderSubtle).frame(height: 0.5)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.contentBg)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }
}
