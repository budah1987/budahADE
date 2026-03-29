import SwiftUI

struct InlineNodesView: View {
    let nodes: [InlineNode]

    var body: some View {
        Self.render(nodes)
            .textSelection(.enabled)
    }

    static func render(_ nodes: [InlineNode]) -> SwiftUI.Text {
        var result = SwiftUI.Text("")
        for node in nodes {
            result = result + renderInline(node)
        }
        return result
    }

    private static func renderInline(_ node: InlineNode) -> SwiftUI.Text {
        switch node {
        case .text(let string):
            return SwiftUI.Text(string)

        case .code(let code):
            return SwiftUI.Text(code)
                .font(Theme.mono(13))
                .foregroundColor(Theme.textPrimary)

        case .emphasis(let children):
            return render(children)
                .italic()
                .foregroundColor(Theme.textSecondary)

        case .strong(let children):
            return render(children)
                .bold()
                .foregroundColor(.white)

        case .link(_, let children):
            return render(children)
                .foregroundColor(Theme.accent)
                .underline()

        case .lineBreak:
            return SwiftUI.Text("\n")
        }
    }
}
