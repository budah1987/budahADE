import SwiftUI

// MARK: - PlanActionButtons

struct PlanActionButtons: View {
    let onApprove: () -> Void
    let onEdit: () -> Void
    let onHandOff: (UUID) -> Void
    let siblingTabs: [PlanTabInfo]

    @State private var showHandOffPopover = false

    var body: some View {
        HStack(spacing: 8) {
            Spacer()

            // Edit button
            ActionButton(
                icon: "pencil",
                label: "Edit",
                action: onEdit
            )

            // Hand off button — show popover if siblings exist
            if siblingTabs.isEmpty {
                ActionButton(
                    icon: "arrowshape.turn.up.right",
                    label: "Hand off",
                    action: { /* no-op if no siblings */ }
                )
                .opacity(0.4)
                .allowsHitTesting(false)
            } else {
                ActionButton(
                    icon: "arrowshape.turn.up.right",
                    label: "Hand off",
                    action: { showHandOffPopover = true }
                )
                .popover(isPresented: $showHandOffPopover, arrowEdge: .top) {
                    HandOffPopover(
                        tabs: siblingTabs,
                        onSelect: { tabId in
                            showHandOffPopover = false
                            onHandOff(tabId)
                        }
                    )
                }
            }

            // Approve button (accent)
            ApproveButton(onApprove: onApprove)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

// MARK: - Action Button

private struct ActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(Theme.label(12))
            }
            .foregroundColor(isHovered ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isHovered ? Theme.Colors.hoverFill : Color.white.opacity(0.05))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Theme.Colors.borderSubtle, lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Approve Button

private struct ApproveButton: View {
    let onApprove: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onApprove) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                Text("Approve & Build")
                    .font(Theme.label(12))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(isHovered ? Theme.Colors.accent.opacity(0.85) : Theme.Colors.accent)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - HandOff Popover

private struct HandOffPopover: View {
    let tabs: [PlanTabInfo]
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Send to tab")
                .font(Theme.caption(11))
                .foregroundColor(Theme.Colors.textTertiary)
                .padding(.horizontal, 10)
                .padding(.top, 8)

            ForEach(tabs) { tab in
                Button {
                    onSelect(tab.id)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.Colors.textTertiary)
                        Text(tab.title)
                            .font(Theme.body(13))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 6)
            }
        }
        .padding(.bottom, 8)
        .frame(minWidth: 180)
        .background(
            ZStack {
                Color(hex: 0x1b1b1e).opacity(0.95)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        )
    }
}
