import SwiftUI
import Markdown

// MARK: - Data Model

struct MarkdownBlockItem: Identifiable {
    let id = UUID()
    let kind: MarkdownBlock
    let sourceText: String
}

enum MarkdownBlock {
    case heading(level: Int, inlines: [InlineNode])
    case paragraph(inlines: [InlineNode])
    case codeBlock(language: String?, code: String)
    case unorderedList(items: [ListItem])
    case orderedList(start: Int, items: [ListItem])
    case table(headers: [[InlineNode]], rows: [[[InlineNode]]], alignments: [MarkdownTableAlignment?])
    case thematicBreak
}

enum InlineNode {
    case text(String)
    case code(String)
    case emphasis([InlineNode])
    case strong([InlineNode])
    case link(destination: String, children: [InlineNode])
    case lineBreak
}

struct ListItem {
    let content: [InlineNode]
    let children: [MarkdownBlockItem]
}

enum MarkdownTableAlignment {
    case left, center, right
}

// MARK: - Parser

struct MarkdownParser {
    static func parse(_ markdown: String) -> [MarkdownBlockItem] {
        let document = Document(parsing: markdown)
        var walker = BlockWalker(source: markdown)
        walker.visit(document)
        return walker.blocks
    }

    static func splitAtStableBoundary(_ markdown: String) -> (String, String) {
        guard !markdown.isEmpty else { return ("", "") }
        let doubleNewlines = findDoubleNewlines(in: markdown)
        guard !doubleNewlines.isEmpty else { return ("", markdown) }
        for splitPos in doubleNewlines.reversed() {
            let prefix = String(markdown[markdown.startIndex..<splitPos])
            let suffix = String(markdown[splitPos...]).trimmingCharacters(in: .newlines)
            if isCodeFenceBalanced(prefix) {
                return (prefix.trimmingCharacters(in: .whitespacesAndNewlines), suffix)
            }
        }
        return ("", markdown)
    }

    private static func findDoubleNewlines(in text: String) -> [String.Index] {
        var positions: [String.Index] = []
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "\n" {
                let next = text.index(after: i)
                if next < text.endIndex && text[next] == "\n" {
                    positions.append(next)
                }
            }
            i = text.index(after: i)
        }
        return positions
    }

    private static func isCodeFenceBalanced(_ text: String) -> Bool {
        var count = 0
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { count += 1 }
        }
        return count % 2 == 0
    }
}

// MARK: - AST Walker

private struct BlockWalker: MarkupWalker {
    let source: String
    var blocks: [MarkdownBlockItem] = []

    mutating func visitHeading(_ heading: Heading) {
        let inlines = parseInlines(heading.children)
        let sourceText = extractSource(heading)
        blocks.append(MarkdownBlockItem(kind: .heading(level: heading.level, inlines: inlines), sourceText: sourceText))
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        let inlines = parseInlines(paragraph.children)
        let sourceText = extractSource(paragraph)
        blocks.append(MarkdownBlockItem(kind: .paragraph(inlines: inlines), sourceText: sourceText))
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let language = codeBlock.language?.isEmpty == false ? codeBlock.language : nil
        let code = codeBlock.code.hasSuffix("\n") ? String(codeBlock.code.dropLast()) : codeBlock.code
        let sourceText = extractSource(codeBlock)
        blocks.append(MarkdownBlockItem(kind: .codeBlock(language: language, code: code), sourceText: sourceText))
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        let items = parseListItems(unorderedList.children)
        let sourceText = extractSource(unorderedList)
        blocks.append(MarkdownBlockItem(kind: .unorderedList(items: items), sourceText: sourceText))
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        let items = parseListItems(orderedList.children)
        let start = Int(orderedList.startIndex)
        let sourceText = extractSource(orderedList)
        blocks.append(MarkdownBlockItem(kind: .orderedList(start: start, items: items), sourceText: sourceText))
    }

    mutating func visitTable(_ table: Markdown.Table) {
        let head = table.head
        let headers: [[InlineNode]] = head.cells.map { cell in parseInlines(cell.children) }
        let alignments: [MarkdownTableAlignment?] = table.columnAlignments.map { alignment in
            switch alignment {
            case .left: return .left
            case .center: return .center
            case .right: return .right
            default: return nil
            }
        }
        let rows: [[[InlineNode]]] = table.body.rows.map { row in
            row.cells.map { cell in parseInlines(cell.children) }
        }
        let sourceText = extractSource(table)
        blocks.append(MarkdownBlockItem(kind: .table(headers: headers, rows: rows, alignments: alignments), sourceText: sourceText))
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        let sourceText = extractSource(thematicBreak)
        blocks.append(MarkdownBlockItem(kind: .thematicBreak, sourceText: sourceText))
    }

    private func parseInlines(_ children: some Sequence<Markup>) -> [InlineNode] {
        var nodes: [InlineNode] = []
        for child in children {
            switch child {
            case let text as Markdown.Text:
                nodes.append(.text(text.string))
            case let code as InlineCode:
                nodes.append(.code(code.code))
            case let emphasis as Emphasis:
                nodes.append(.emphasis(parseInlines(emphasis.children)))
            case let strong as Strong:
                nodes.append(.strong(parseInlines(strong.children)))
            case let link as Markdown.Link:
                nodes.append(.link(destination: link.destination ?? "", children: parseInlines(link.children)))
            case _ as SoftBreak:
                nodes.append(.text(" "))
            case _ as LineBreak:
                nodes.append(.lineBreak)
            default:
                if let plainText = child as? any BasicInlineContainer {
                    nodes.append(contentsOf: parseInlines(plainText.children))
                }
            }
        }
        return nodes
    }

    private func parseListItems(_ children: some Sequence<Markup>) -> [ListItem] {
        children.compactMap { child -> ListItem? in
            guard let listItem = child as? Markdown.ListItem else { return nil }
            var inlines: [InlineNode] = []
            var nestedBlocks: [MarkdownBlockItem] = []
            for itemChild in listItem.children {
                if let paragraph = itemChild as? Paragraph {
                    inlines.append(contentsOf: parseInlines(paragraph.children))
                } else if itemChild is UnorderedList || itemChild is OrderedList {
                    var nestedWalker = BlockWalker(source: source)
                    nestedWalker.visit(itemChild)
                    nestedBlocks.append(contentsOf: nestedWalker.blocks)
                }
            }
            return ListItem(content: inlines, children: nestedBlocks)
        }
    }

    private func extractSource(_ markup: Markup) -> String {
        guard let range = markup.range else { return "" }
        let lines = source.components(separatedBy: "\n")
        let startLine = range.lowerBound.line - 1
        let endLine = range.upperBound.line - 1
        guard startLine >= 0, endLine < lines.count else { return "" }
        return lines[startLine...endLine].joined(separator: "\n")
    }
}

// MARK: - Inline Nodes View

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

// MARK: - Markdown Renderer View

struct MarkdownRenderer: View {
    let content: String
    let isStreaming: Bool

    init(_ content: String, isStreaming: Bool = false) {
        self.content = content
        self.isStreaming = isStreaming
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isStreaming {
                streamingContent
            } else {
                renderedBlocks(from: content)
            }
        }
    }

    // MARK: - Streaming

    @ViewBuilder
    private var streamingContent: some View {
        let (stable, tail) = MarkdownParser.splitAtStableBoundary(content)

        if !stable.isEmpty {
            renderedBlocks(from: stable)
        }

        if !tail.isEmpty {
            Text(tail)
                .font(Theme.body(14))
                .foregroundColor(Theme.textPrimary)
                .textSelection(.enabled)
                .padding(.top, stable.isEmpty ? 0 : 8)
        }
    }

    // MARK: - Block Rendering

    @ViewBuilder
    private func renderedBlocks(from markdown: String) -> some View {
        let blocks = MarkdownParser.parse(markdown)
        ForEach(blocks) { block in
            blockView(for: block)
        }
    }

    @ViewBuilder
    private func blockView(for block: MarkdownBlockItem) -> some View {
        switch block.kind {
        case .heading(let level, let inlines):
            headingView(level: level, inlines: inlines)

        case .paragraph(let inlines):
            InlineNodesView(nodes: inlines)
                .font(Theme.body(14))
                .foregroundColor(Theme.textPrimary)
                .padding(.bottom, 8)

        case .codeBlock(let language, let code):
            CodeBlockView(code: code, language: language)
                .padding(.vertical, 4)

        case .unorderedList(let items):
            unorderedListView(items: items)
                .padding(.bottom, 8)

        case .orderedList(let start, let items):
            orderedListView(start: start, items: items)
                .padding(.bottom, 8)

        case .table(let headers, let rows, let alignments):
            MarkdownTableView(headers: headers, rows: rows, alignments: alignments)
                .padding(.vertical, 4)

        case .thematicBreak:
            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 1)
                .padding(.vertical, 12)
        }
    }

    // MARK: - Headings

    @ViewBuilder
    private func headingView(level: Int, inlines: [InlineNode]) -> some View {
        let (font, topPad, bottomPad): (Font, CGFloat, CGFloat) = {
            switch level {
            case 1: return (Theme.headline(22), 20, 8)
            case 2: return (Theme.headline(18), 16, 6)
            default: return (Theme.label(15), 12, 4)
            }
        }()

        InlineNodesView(nodes: inlines)
            .font(font)
            .foregroundColor(Theme.textPrimary)
            .padding(.top, topPad)
            .padding(.bottom, bottomPad)
    }

    // MARK: - Lists

    @ViewBuilder
    private func unorderedListView(items: [ListItem], indent: CGFloat = 0) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                        .font(Theme.body(14))
                        .foregroundColor(Theme.textMuted)
                    InlineNodesView(nodes: item.content)
                        .font(Theme.body(14))
                        .foregroundColor(Theme.textPrimary)
                }
                .padding(.leading, indent)

                ForEach(item.children) { child in
                    blockView(for: child)
                        .padding(.leading, indent + 20)
                }
            }
        }
    }

    @ViewBuilder
    private func orderedListView(start: Int, items: [ListItem], indent: CGFloat = 0) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(start + idx).")
                        .font(Theme.body(14))
                        .foregroundColor(Theme.textMuted)
                        .frame(minWidth: 20, alignment: .trailing)
                    InlineNodesView(nodes: item.content)
                        .font(Theme.body(14))
                        .foregroundColor(Theme.textPrimary)
                }
                .padding(.leading, indent)

                ForEach(item.children) { child in
                    blockView(for: child)
                        .padding(.leading, indent + 20)
                }
            }
        }
    }
}

// MARK: - Editable Markdown Renderer

struct EditableMarkdownRenderer: View {
    @Binding var content: String
    let onDone: () -> Void

    @State private var editingBlockId: UUID?
    @State private var editText: String = ""
    @State private var hoveredBlockId: UUID?

    var body: some View {
        let blocks = MarkdownParser.parse(content)

        VStack(alignment: .leading, spacing: 0) {
            ForEach(blocks) { block in
                if block.id == editingBlockId {
                    editableBlock(block: block)
                } else {
                    renderableBlock(block: block)
                }
            }

            // Done button
            HStack {
                Spacer()
                Button("Done") {
                    commitEdit()
                    onDone()
                }
                .font(Theme.label(12))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func renderableBlock(block: MarkdownBlockItem) -> some View {
        MarkdownRenderer(block.sourceText)
            .padding(4)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(
                        hoveredBlockId == block.id ? Theme.borderSubtle : Color.clear,
                        lineWidth: 1
                    )
            )
            .background(
                hoveredBlockId == block.id ? Theme.hoverFill : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .onHover { hovering in
                hoveredBlockId = hovering ? block.id : nil
                if hovering {
                    NSCursor.iBeam.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onTapGesture {
                commitEdit()
                editingBlockId = block.id
                editText = block.sourceText
            }
    }

    @ViewBuilder
    private func editableBlock(block: MarkdownBlockItem) -> some View {
        TextEditor(text: $editText)
            .font(Theme.mono(13))
            .foregroundColor(Theme.textPrimary)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 60)
            .padding(8)
            .background(Theme.surface2)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Theme.borderActive, lineWidth: 1)
            )
    }

    private func commitEdit() {
        guard let blockId = editingBlockId else { return }
        let blocks = MarkdownParser.parse(content)
        guard let block = blocks.first(where: { $0.id == blockId }) else { return }

        if let range = content.range(of: block.sourceText) {
            content.replaceSubrange(range, with: editText)
        }

        editingBlockId = nil
        editText = ""
    }
}
