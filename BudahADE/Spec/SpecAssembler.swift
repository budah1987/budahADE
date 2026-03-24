import Foundation

// MARK: - Spec Assembler

/// Collects tagged canvas elements and assembles them into a structured spec markdown file
enum SpecAssembler {

    /// Assemble a spec from tagged canvas elements
    @MainActor
    static func assemble(
        canvas: PlanCanvasState,
        taskName: String,
        worktreePath: String,
        customSections: [String]? = nil
    ) -> String? {
        let sectionOrder = customSections ?? SpecSectionKind.allCases.map(\.rawValue)

        // Collect all elements (root + frame children) with spec tags
        let tagged = collectTaggedElements(from: canvas)
        guard !tagged.isEmpty else { return nil }

        // Group by section
        var sectionContent: [String: [(order: Int, content: String)]] = [:]
        for element in tagged {
            guard let section = element.specSection else { continue }
            let content = extractContent(from: element, worktreePath: worktreePath, canvas: canvas)
            guard !content.isEmpty else { continue }

            var entries = sectionContent[section] ?? []
            entries.append((order: element.specOrder, content: content))
            sectionContent[section] = entries
        }

        // Build markdown
        var lines: [String] = []
        let slug = slugify(taskName)
        lines.append("# \(taskName) Spec")
        lines.append("")

        for sectionName in sectionOrder {
            guard var entries = sectionContent[sectionName], !entries.isEmpty else { continue }
            entries.sort { $0.order < $1.order }

            lines.append("## \(sectionName)")
            lines.append("")
            for entry in entries {
                lines.append(entry.content)
                lines.append("")
            }
        }

        // Include any custom sections not in the default order
        for (sectionName, var entries) in sectionContent where !sectionOrder.contains(sectionName) {
            entries.sort { $0.order < $1.order }
            lines.append("## \(sectionName)")
            lines.append("")
            for entry in entries {
                lines.append(entry.content)
                lines.append("")
            }
        }

        let markdown = lines.joined(separator: "\n")

        // Write to file
        let filename = "\(slug)-spec.md"
        let path = (worktreePath as NSString).appendingPathComponent(filename)
        do {
            try markdown.write(toFile: path, atomically: true, encoding: .utf8)
            return path
        } catch {
            return nil
        }
    }

    // MARK: - Collect Tagged Elements

    @MainActor
    private static func collectTaggedElements(from canvas: PlanCanvasState) -> [CanvasElement] {
        var result: [CanvasElement] = []
        for element in canvas.elements {
            if element.specSection != nil {
                result.append(element)
            }
            if case .frame(let data) = element.kind {
                // If frame is tagged, include frame itself (children will be part of its content)
                // If frame children are individually tagged, include them
                for child in data.children where child.specSection != nil {
                    result.append(child)
                }
            }
        }
        return result
    }

    // MARK: - Extract Content

    @MainActor
    private static func extractContent(
        from element: CanvasElement,
        worktreePath: String,
        canvas: PlanCanvasState
    ) -> String {
        switch element.kind {
        case .text(let textData):
            return textData.content

        case .tile(let tileType):
            return extractTileContent(tileType: tileType, elementId: element.id, worktreePath: worktreePath, canvas: canvas)

        case .frame(let frameData):
            // Concatenate children content
            return frameData.children
                .compactMap { child -> String? in
                    let content = extractContent(from: child, worktreePath: worktreePath, canvas: canvas)
                    return content.isEmpty ? nil : content
                }
                .joined(separator: "\n\n")
        }
    }

    @MainActor
    private static func extractTileContent(
        tileType: TileType,
        elementId: UUID,
        worktreePath: String,
        canvas: PlanCanvasState
    ) -> String {
        switch tileType {
        case .markdown(let path):
            return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""

        case .browser(let url):
            guard let url else { return "" }
            return "- Reference: [\(url.host ?? url.absoluteString)](\(url.absoluteString))"

        case .image(let path):
            let filename = (path as NSString).lastPathComponent
            return "![Reference: \(filename)](\(path))"

        case .terminal(let panelId, let agent):
            // Try reading agent output file
            let outputDir = (worktreePath as NSString).appendingPathComponent(".budahade/agent-output")
            let outputPath = (outputDir as NSString).appendingPathComponent("\(panelId.uuidString).md")
            if let output = try? String(contentsOfFile: outputPath, encoding: .utf8), !output.isEmpty {
                return output
            }
            return "<!-- \(agent.displayName) agent output pending -->"

        case .stickyNote:
            return ""

        case .chatAgent:
            return ""
        }
    }

    // MARK: - Helpers

    private static func slugify(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}
