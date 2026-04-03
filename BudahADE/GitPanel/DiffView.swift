import SwiftUI

struct DiffView: View {
    let diff: String

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diff.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(Theme.code(11))
                        .foregroundColor(lineColor(for: line))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 0.5)
                        .background(lineBackground(for: line))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.Colors.appBackground)
    }

    private func lineColor(for line: String) -> Color {
        if line.hasPrefix("@@") {
            return Theme.Colors.info
        } else if line.hasPrefix("+") {
            return Theme.Colors.statusDone
        } else if line.hasPrefix("-") {
            return Theme.Colors.error.opacity(0.85)
        } else {
            return Theme.Colors.textSecondary
        }
    }

    private func lineBackground(for line: String) -> Color {
        if line.hasPrefix("+") {
            return Theme.Colors.statusDone.opacity(0.06)
        } else if line.hasPrefix("-") {
            return Theme.Colors.error.opacity(0.05)
        } else {
            return .clear
        }
    }
}
