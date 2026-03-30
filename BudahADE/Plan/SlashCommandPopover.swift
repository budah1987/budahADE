import SwiftUI

struct SlashCommandPopover: View {
    let commands: [String]
    let filter: String  // text after "/" — e.g., "fig" for "/fig"
    let onSelect: (String) -> Void
    let onDismiss: () -> Void
    @Binding var selectedIndex: Int

    private var localCommands: Set<String> {
        ["clear", "model"]
    }

    /// Commands are already filtered by the caller
    private var filteredCommands: [String] { commands }

    var body: some View {
        if filteredCommands.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(filteredCommands.enumerated()), id: \.offset) { index, command in
                                CommandRow(
                                    command: command,
                                    isLocal: localCommands.contains(command),
                                    isSelected: index == selectedIndex,
                                    onSelect: { onSelect(command) }
                                )
                                .id(index)
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                    .onChange(of: selectedIndex) { _, newValue in
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }

                Rectangle().fill(Theme.borderSubtle).frame(height: 0.5)

                HStack(spacing: 12) {
                    HStack(spacing: 3) {
                        KeyHint("↑↓")
                        Text("navigate")
                    }
                    HStack(spacing: 3) {
                        KeyHint("tab")
                        Text("complete")
                    }
                    HStack(spacing: 3) {
                        KeyHint("⏎")
                        Text("select")
                    }
                    HStack(spacing: 3) {
                        KeyHint("esc")
                        Text("dismiss")
                    }
                }
                .font(Theme.caption(10))
                .foregroundColor(Theme.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.surface2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 16, y: -4)
            )
            .frame(width: 320)
        }
    }

    /// Move selection up
    func moveUp() {
        guard !filteredCommands.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + filteredCommands.count) % filteredCommands.count
    }

    /// Move selection down
    func moveDown() {
        guard !filteredCommands.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % filteredCommands.count
    }

    /// Get the currently selected command
    var selectedCommand: String? {
        guard !filteredCommands.isEmpty, selectedIndex < filteredCommands.count else { return nil }
        return filteredCommands[selectedIndex]
    }
}

// MARK: - Command Row

private struct CommandRow: View {
    let command: String
    let isLocal: Bool
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Text("/")
                    .font(Theme.mono(12))
                    .foregroundColor(Theme.textMuted)
                Text(command)
                    .font(Theme.body(13))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                if isLocal {
                    Text("local")
                        .font(Theme.caption(10))
                        .foregroundColor(Theme.textMuted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.hoverFill)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Theme.accent.opacity(0.15) : (isHovered ? Theme.hoverFill : Color.clear))
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Key Hint

private struct KeyHint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.mono(9))
            .foregroundColor(Theme.textMuted)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Theme.surface2.opacity(0.8))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Theme.borderSubtle, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
