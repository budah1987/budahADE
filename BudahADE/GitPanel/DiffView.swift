import SwiftUI

struct DiffView: View {
    let diff: String

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diff.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(lineColor(for: line))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 0.5)
                        .background(lineBackground(for: line))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.appBackground)
    }

    private func lineColor(for line: String) -> Color {
        if line.hasPrefix("@@") {
            return Theme.info
        } else if line.hasPrefix("+") {
            return Theme.success
        } else if line.hasPrefix("-") {
            return Theme.error.opacity(0.85)
        } else {
            return Theme.textSecondary
        }
    }

    private func lineBackground(for line: String) -> Color {
        if line.hasPrefix("+") {
            return Theme.success.opacity(0.06)
        } else if line.hasPrefix("-") {
            return Theme.error.opacity(0.05)
        } else {
            return .clear
        }
    }
}
