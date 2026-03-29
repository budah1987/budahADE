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
