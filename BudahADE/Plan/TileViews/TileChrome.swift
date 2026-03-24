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
                        .frame(width: 7, height: 7)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.textMuted)
                }

                Text(title)
                    .font(Theme.label(13))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isCloseHovered ? Theme.textSecondary : Theme.textMuted)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isCloseHovered ? Theme.hoverFill : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isCloseHovered = hovering
                    if hovering { NSCursor.arrow.set() }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
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
