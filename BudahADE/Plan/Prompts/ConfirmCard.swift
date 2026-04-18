import SwiftUI

/// A confirm prompt is a snap yes/no decision. No counter, no dots, no chrome —
/// two buttons side by side with the recommended action highlighted. Cmd+Enter
/// accepts. Escape dismisses.
struct ConfirmCard: View {
    let prompt: AgentSession.QueuedPrompt
    let namespace: Namespace.ID
    let onAnswer: (String) -> Void
    let onDismiss: () -> Void

    @State private var pulseYes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Theme.Colors.accent.opacity(0.4))
                .frame(height: 1.5)
                .matchedGeometryEffect(id: "accent", in: namespace)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    if !prompt.context.isEmpty {
                        Text(cleanContext(prompt.context))
                            .font(Theme.body(12))
                            .foregroundColor(Theme.Colors.textTertiary)
                            .lineLimit(2)
                    }
                    Text(cleanBold(prompt.question))
                        .font(Theme.body(14))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .matchedGeometryEffect(id: "question-\(prompt.id)", in: namespace)
                }

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { onAnswer("No") }
                    } label: {
                        Text("No")
                            .font(Theme.label(12))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Theme.Colors.hoverFill)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { pulseYes = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            withAnimation(.easeOut(duration: 0.15)) { onAnswer("Yes") }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text("Yes")
                                .font(Theme.label(12))
                                .foregroundColor(.black)
                            Text("\u{2318}\u{21A9}")
                                .font(Theme.caption(10))
                                .foregroundColor(.black.opacity(0.45))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(white: 0.94))
                        )
                        .scaleEffect(pulseYes ? 0.95 : 1.0)
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { onDismiss() }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Theme.Colors.textTertiary)
                            .frame(width: 22, height: 22)
                            .background(Theme.Colors.hoverFill)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .matchedGeometryEffect(id: "dismiss", in: namespace)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .background(Theme.Colors.sidebarBackground)
        .onKeyPress(.escape) {
            withAnimation(.easeOut(duration: 0.15)) { onDismiss() }
            return .handled
        }
    }

    private func cleanBold(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "")
    }

    private func cleanContext(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .components(separatedBy: "\n")
            .map { line in
                var l = line
                if l.hasPrefix("• ") { l = String(l.dropFirst(2)) }
                if l.hasPrefix("- ") { l = String(l.dropFirst(2)) }
                return l
            }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
