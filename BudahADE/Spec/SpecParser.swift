import Foundation

// MARK: - Spec Task

struct SpecTask: Identifiable, Equatable {
    let id: Int
    let title: String
    let isCompleted: Bool
    let sectionId: String?  // which section this task belongs to
}

// MARK: - Spec Section

struct SpecSection: Identifiable, Equatable {
    let id: String           // slug of section title
    let title: String        // "Architecture", "Edge Cases", etc.
    let level: Int           // heading level (2 for ##, 3 for ###)
    let content: String      // raw markdown between this heading and the next
    let tasks: [SpecTask]    // checkboxes within this section
    let lineRange: Range<Int> // line numbers in the file (0-based)

    var completedCount: Int { tasks.filter(\.isCompleted).count }
    var totalCount: Int { tasks.count }
    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }
}

// MARK: - Spec Parse Result

struct SpecParseResult: Equatable {
    let title: String?
    let sections: [SpecSection]
    let rawContent: String
    let filePath: String

    // Backward-compatible: all tasks across all sections
    var tasks: [SpecTask] { sections.flatMap(\.tasks) }

    var completedCount: Int { tasks.filter(\.isCompleted).count }
    var totalCount: Int { tasks.count }
    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }
}

// MARK: - Spec Parser

enum SpecParser {

    /// Parse a markdown spec file with section awareness
    static func parse(fileAt path: String) -> SpecParseResult? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }

        let lines = content.components(separatedBy: .newlines)
        var title: String?
        var sections: [SpecSection] = []
        var taskIndex = 0

        // Track current section being built
        var currentSectionTitle: String?
        var currentSectionLevel: Int = 0
        var currentSectionStartLine: Int = 0
        var currentSectionLines: [String] = []
        var currentSectionTasks: [SpecTask] = []

        func flushSection(endLine: Int) {
            guard let sTitle = currentSectionTitle else { return }
            // Deduplicate section IDs — same pattern as parseMarkdownSections
            var sectionId = slugify(sTitle)
            let existingIds = sections.map(\.id)
            if existingIds.contains(sectionId) {
                var suffix = 2
                while existingIds.contains("\(sectionId)-\(suffix)") {
                    suffix += 1
                }
                sectionId = "\(sectionId)-\(suffix)"
            }
            let content = currentSectionLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            sections.append(SpecSection(
                id: sectionId,
                title: sTitle,
                level: currentSectionLevel,
                content: content,
                tasks: currentSectionTasks,
                lineRange: currentSectionStartLine..<endLine
            ))
            currentSectionTitle = nil
            currentSectionLines = []
            currentSectionTasks = []
        }

        for (lineIdx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // H1 title
            if title == nil && trimmed.hasPrefix("# ") && !trimmed.hasPrefix("## ") {
                title = String(trimmed.dropFirst(2))
                continue
            }

            // Detect heading (## or ###)
            let headingLevel: Int?
            let headingText: String?
            if trimmed.hasPrefix("### ") {
                headingLevel = 3
                headingText = String(trimmed.dropFirst(4))
            } else if trimmed.hasPrefix("## ") {
                headingLevel = 2
                headingText = String(trimmed.dropFirst(3))
            } else {
                headingLevel = nil
                headingText = nil
            }

            if let level = headingLevel, let text = headingText {
                // Flush previous section
                flushSection(endLine: lineIdx)
                // Start new section
                currentSectionTitle = text
                currentSectionLevel = level
                currentSectionStartLine = lineIdx
                currentSectionLines = []
                currentSectionTasks = []
                continue
            }

            // Checkbox tasks
            let sectionId = currentSectionTitle.map { slugify($0) }
            if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                let taskTitle = String(trimmed.dropFirst(6))
                let task = SpecTask(id: taskIndex, title: taskTitle, isCompleted: true, sectionId: sectionId)
                currentSectionTasks.append(task)
                taskIndex += 1
            } else if trimmed.hasPrefix("- [ ] ") {
                let taskTitle = String(trimmed.dropFirst(6))
                let task = SpecTask(id: taskIndex, title: taskTitle, isCompleted: false, sectionId: sectionId)
                currentSectionTasks.append(task)
                taskIndex += 1
            }

            // Accumulate section content
            if currentSectionTitle != nil {
                currentSectionLines.append(line)
            }
        }

        // Flush last section
        flushSection(endLine: lines.count)

        // Return nil only if no sections AND no tasks found
        // (a spec with sections but no checkboxes is still valid)
        guard !sections.isEmpty || taskIndex > 0 else { return nil }

        return SpecParseResult(
            title: title,
            sections: sections,
            rawContent: content,
            filePath: path
        )
    }

    /// Find spec files in a directory (root-level patterns + .budahade/spec.md)
    static func findSpecFiles(in directory: String) -> [String] {
        let fm = FileManager.default
        var results: [String] = []

        // Scan root for *-spec.md, *-plan.md, *.spec.md
        if let contents = try? fm.contentsOfDirectory(atPath: directory) {
            let specPatterns = ["-spec.md", "-plan.md", ".spec.md"]
            results = contents
                .filter { name in specPatterns.contains(where: { name.lowercased().hasSuffix($0) }) }
                .map { (directory as NSString).appendingPathComponent($0) }
        }

        // Also check .budahade/spec.md (written by SpecVersionManager.approve)
        let budahadeSpec = (directory as NSString).appendingPathComponent(".budahade/spec.md")
        if fm.fileExists(atPath: budahadeSpec), !results.contains(budahadeSpec) {
            results.append(budahadeSpec)
        }

        return results
    }

    // MARK: - Helpers

    static func slugify(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}

// MARK: - Markdown Section (for section-based editing in MarkdownTileView)

struct MarkdownSection: Identifiable, Equatable {
    let id: String          // slugified heading
    let heading: String
    let body: String
    var sourceId: String?   // from <!-- source: xxx --> comment
    let checkboxItems: [SpecTask]
    let lineRange: Range<Int>
}

extension SpecParser {
    /// Split markdown content by ## headings into editable sections.
    static func parseMarkdownSections(from content: String) -> [MarkdownSection] {
        let lines = content.components(separatedBy: .newlines)
        var sections: [MarkdownSection] = []
        var currentHeading: String?
        var currentStartLine: Int = 0
        var currentLines: [String] = []
        var currentSourceId: String?
        var currentTasks: [SpecTask] = []
        var taskIndex = 0

        func flush(endLine: Int) {
            guard let heading = currentHeading else { return }
            let body = currentLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Deduplicate section IDs
            var sectionId = slugify(heading)
            let existingIds = sections.map(\.id)
            if existingIds.contains(sectionId) {
                var suffix = 2
                while existingIds.contains("\(sectionId)-\(suffix)") {
                    suffix += 1
                }
                sectionId = "\(sectionId)-\(suffix)"
            }

            sections.append(MarkdownSection(
                id: sectionId,
                heading: heading,
                body: body,
                sourceId: currentSourceId,
                checkboxItems: currentTasks,
                lineRange: currentStartLine..<endLine
            ))
            currentHeading = nil
            currentLines = []
            currentSourceId = nil
            currentTasks = []
        }

        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("## ") && !trimmed.hasPrefix("### ") {
                flush(endLine: idx)
                currentHeading = String(trimmed.dropFirst(3))
                currentStartLine = idx
                continue
            }

            if currentHeading != nil {
                // Check for source attribution
                if trimmed.hasPrefix("<!-- source:"),
                   let end = trimmed.range(of: "-->") {
                    let start = trimmed.index(trimmed.startIndex, offsetBy: 13)
                    currentSourceId = String(trimmed[start..<end.lowerBound])
                        .trimmingCharacters(in: .whitespaces)
                }

                // Check for checkboxes
                let sectionSlug = currentHeading.map { slugify($0) }
                if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                    currentTasks.append(SpecTask(
                        id: taskIndex, title: String(trimmed.dropFirst(6)),
                        isCompleted: true, sectionId: sectionSlug
                    ))
                    taskIndex += 1
                } else if trimmed.hasPrefix("- [ ] ") {
                    currentTasks.append(SpecTask(
                        id: taskIndex, title: String(trimmed.dropFirst(6)),
                        isCompleted: false, sectionId: sectionSlug
                    ))
                    taskIndex += 1
                }

                currentLines.append(line)
            }
        }
        flush(endLine: lines.count)
        return sections
    }

    /// Update a task's title at the given index in the content string
    static func updateTaskTitle(in content: String, at taskIndex: Int, newTitle: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var newLines = lines
        var counter = 0
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                if counter == taskIndex {
                    let prefix = trimmed.hasPrefix("- [x] ") ? "- [x] " : "- [X] "
                    newLines[i] = prefix + newTitle
                    break
                }
                counter += 1
            } else if trimmed.hasPrefix("- [ ] ") {
                if counter == taskIndex {
                    newLines[i] = "- [ ] " + newTitle
                    break
                }
                counter += 1
            }
        }
        return newLines.joined(separator: "\n")
    }

    /// Update a spec file on disk with a modified task title
    static func updateTaskInFile(at path: String, taskIndex: Int, newTitle: String) -> Bool {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
        let updated = updateTaskTitle(in: content, at: taskIndex, newTitle: newTitle)
        do {
            try updated.write(toFile: path, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    /// Write build step changes back to the spec file.
    /// Updates task titles for modified steps.
    static func persistBuildSteps(_ steps: [BuildStep], to specPath: String) -> Bool {
        guard var content = try? String(contentsOfFile: specPath, encoding: .utf8) else { return false }

        // Update each step's title if it has been modified
        // We match by index since BuildStep IDs map to SpecTask indices
        for step in steps {
            guard let taskIndex = Int(step.id) else { continue }
            content = updateTaskTitle(in: content, at: taskIndex, newTitle: step.title)
        }

        do {
            try content.write(toFile: specPath, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    /// Toggle a checkbox at the given task index in the content string
    static func toggleCheckbox(in content: String, at taskIndex: Int) -> String {
        let lines = content.components(separatedBy: .newlines)
        var newLines = lines
        var counter = 0
        var insideSection = false
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Track section boundaries (same logic as parseMarkdownSections)
            if trimmed.hasPrefix("## ") && !trimmed.hasPrefix("### ") {
                insideSection = true
                continue
            }
            guard insideSection else { continue }
            if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") ||
               trimmed.hasPrefix("- [ ] ") {
                if counter == taskIndex {
                    if trimmed.hasPrefix("- [ ] ") {
                        newLines[i] = line.replacingOccurrences(of: "- [ ] ", with: "- [x] ")
                    } else {
                        newLines[i] = line
                            .replacingOccurrences(of: "- [x] ", with: "- [ ] ")
                            .replacingOccurrences(of: "- [X] ", with: "- [ ] ")
                    }
                    break
                }
                counter += 1
            }
        }
        return newLines.joined(separator: "\n")
    }
}
