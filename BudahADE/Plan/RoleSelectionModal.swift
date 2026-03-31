import SwiftUI

// MARK: - Role Selection Modal

struct RoleSelectionModal: View {
    let onSelect: (AgentMode) -> Void

    @State private var hoveredRole: AgentMode? = nil
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("Choose a role")
                .font(Theme.label(13))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 0.5)
                .padding(.horizontal, 0)

            // Role rows
            VStack(spacing: 0) {
                ForEach(AgentMode.planRoles) { role in
                    RoleRow(
                        role: role,
                        isHovered: hoveredRole == role,
                        onSelect: { onSelect(role) }
                    )
                    .onHover { inside in
                        hoveredRole = inside ? role : nil
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(width: 420)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 40, y: 16)
        )
        .focusable()
        .focused($isFocused)
        .onKeyPress { press in
            for role in AgentMode.planRoles {
                if let idx = role.roleShortcutIndex,
                   press.characters == "\(idx)" {
                    onSelect(role)
                    return .handled
                }
            }
            return .ignored
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFocused = true
            }
        }
    }
}

// MARK: - Role Row

private struct RoleRow: View {
    let role: AgentMode
    let isHovered: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                // Shortcut badge
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Theme.surface2)
                        .frame(width: 22, height: 22)
                    Text(role.roleShortcutIndex.map { "\($0)" } ?? "")
                        .font(Theme.label(11))
                        .foregroundStyle(Theme.textMuted)
                }

                // Icon with role color
                ZStack {
                    Circle()
                        .fill(role.dotColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: role.iconName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(role.dotColor)
                }

                // Name + description
                VStack(alignment: .leading, spacing: 2) {
                    Text(role.displayName)
                        .font(Theme.label(13))
                        .foregroundStyle(Theme.textPrimary)
                    Text(role.description)
                        .font(Theme.caption(11))
                        .foregroundStyle(Theme.textMuted)
                }

                Spacer(minLength: 0)

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textMuted.opacity(isHovered ? 0.8 : 0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Theme.surface2.opacity(0.8) : Color.clear)
                    .padding(.horizontal, 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }
}
