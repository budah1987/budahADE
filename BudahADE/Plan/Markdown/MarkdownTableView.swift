import SwiftUI

struct MarkdownTableView: View {
    let headers: [[InlineNode]]
    let rows: [[[InlineNode]]]
    let alignments: [MarkdownTableAlignment?]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { colIdx, header in
                        InlineNodesView(nodes: header)
                            .font(Theme.label(13))
                            .foregroundColor(Theme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: alignment(for: colIdx))
                    }
                }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Theme.borderSubtle)
                        .frame(height: 1)
                }

                ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { colIdx, cell in
                            InlineNodesView(nodes: cell)
                                .font(Theme.body(13))
                                .foregroundColor(Theme.textPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: alignment(for: colIdx))
                        }
                    }
                    .background(rowIdx % 2 == 1 ? Color.white.opacity(0.02) : Color.clear)
                }
            }
        }
    }

    private func alignment(for column: Int) -> Alignment {
        guard column < alignments.count else { return .leading }
        switch alignments[column] {
        case .left, nil: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}
