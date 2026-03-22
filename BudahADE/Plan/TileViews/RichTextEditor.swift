import SwiftUI
import AppKit

/// NSTextView wrapper with rich text editing, Cmd+B/I support,
/// and markdown-backed storage
struct RichTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onSave: () -> Void
    var onCoordinatorReady: ((Coordinator) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let textView = RichEditorTextView()
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        textView.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        textView.textColor = Theme.nsTextPrimary
        textView.backgroundColor = NSColor(Theme.contentBg)
        textView.insertionPointColor = Theme.nsTextPrimary
        textView.textContainerInset = NSSize(width: 12, height: 12)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        textView.delegate = context.coordinator
        textView.coordinator = context.coordinator
        context.coordinator.textView = textView

        // Load initial content as attributed string from markdown
        let attributed = context.coordinator.markdownToAttributed(text)
        textView.textStorage?.setAttributedString(attributed)

        // Notify parent that coordinator is ready
        DispatchQueue.main.async {
            self.onCoordinatorReady?(context.coordinator)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // Only update if text changed externally (not from user typing)
        guard !context.coordinator.isEditing else { return }
        let textView = scrollView.documentView as! NSTextView
        let attributed = context.coordinator.markdownToAttributed(text)
        textView.textStorage?.setAttributedString(attributed)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        let parent: RichTextEditor
        weak var textView: NSTextView?
        var isEditing = false
        private var saveTask: Task<Void, Never>?

        init(parent: RichTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            isEditing = true
            // Convert attributed text back to markdown
            if let textView = textView {
                let markdown = attributedToMarkdown(textView.attributedString())
                parent.text = markdown
                debounceSave()
            }
            isEditing = false
        }

        // MARK: - Keyboard Shortcuts

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            false // Let default handling occur
        }

        // Handle Cmd+B and Cmd+I via key bindings
        @objc func toggleBold() {
            guard let textView = textView else { return }
            let range = textView.selectedRange()

            if range.length == 0 {
                // Toggle typing attributes for next typed characters
                var typingAttrs = textView.typingAttributes
                let currentFont = typingAttrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: 14)
                let isBold = currentFont.fontDescriptor.symbolicTraits.contains(.bold)
                let newFont = isBold
                    ? NSFontManager.shared.convert(currentFont, toNotHaveTrait: .boldFontMask)
                    : NSFontManager.shared.convert(currentFont, toHaveTrait: .boldFontMask)
                typingAttrs[.font] = newFont
                textView.typingAttributes = typingAttrs
                return
            }

            let storage = textView.textStorage!
            let attrs = storage.attributes(at: range.location, effectiveRange: nil)
            let currentFont = attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: 14)

            let isBold = currentFont.fontDescriptor.symbolicTraits.contains(.bold)
            let newFont: NSFont
            if isBold {
                newFont = NSFontManager.shared.convert(currentFont, toNotHaveTrait: .boldFontMask)
            } else {
                newFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .boldFontMask)
            }

            storage.addAttribute(.font, value: newFont, range: range)
            textDidChange(Notification(name: .init("")))
        }

        @objc func toggleItalic() {
            guard let textView = textView else { return }
            let range = textView.selectedRange()

            if range.length == 0 {
                // Toggle typing attributes for next typed characters
                var typingAttrs = textView.typingAttributes
                let currentFont = typingAttrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: 14)
                let isItalic = currentFont.fontDescriptor.symbolicTraits.contains(.italic)
                let newFont = isItalic
                    ? NSFontManager.shared.convert(currentFont, toNotHaveTrait: .italicFontMask)
                    : NSFontManager.shared.convert(currentFont, toHaveTrait: .italicFontMask)
                typingAttrs[.font] = newFont
                textView.typingAttributes = typingAttrs
                return
            }

            let storage = textView.textStorage!
            let attrs = storage.attributes(at: range.location, effectiveRange: nil)
            let currentFont = attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: 14)

            let isItalic = currentFont.fontDescriptor.symbolicTraits.contains(.italic)
            let newFont: NSFont
            if isItalic {
                newFont = NSFontManager.shared.convert(currentFont, toNotHaveTrait: .italicFontMask)
            } else {
                newFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .italicFontMask)
            }

            storage.addAttribute(.font, value: newFont, range: range)
            textDidChange(Notification(name: .init("")))
        }

        // MARK: - Markdown ↔ AttributedString

        func markdownToAttributed(_ markdown: String) -> NSAttributedString {
            let result = NSMutableAttributedString()
            let baseFont = NSFont.systemFont(ofSize: 14, weight: .regular)
            let boldFont = NSFont.systemFont(ofSize: 14, weight: .bold)
            let baseColor = Theme.nsTextPrimary
            let defaultAttrs: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: baseColor
            ]

            let lines = markdown.components(separatedBy: "\n")
            for (i, line) in lines.enumerated() {
                if line.hasPrefix("# ") {
                    let heading = String(line.dropFirst(2))
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 22, weight: .bold),
                        .foregroundColor: baseColor
                    ]
                    result.append(NSAttributedString(string: heading, attributes: attrs))
                } else if line.hasPrefix("## ") {
                    let heading = String(line.dropFirst(3))
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 18, weight: .bold),
                        .foregroundColor: baseColor
                    ]
                    result.append(NSAttributedString(string: heading, attributes: attrs))
                } else if line.hasPrefix("### ") {
                    let heading = String(line.dropFirst(4))
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                        .foregroundColor: baseColor
                    ]
                    result.append(NSAttributedString(string: heading, attributes: attrs))
                } else {
                    // Parse inline formatting
                    let parsed = parseInline(line, baseFont: baseFont, boldFont: boldFont, color: baseColor)
                    result.append(parsed)
                }

                if i < lines.count - 1 {
                    result.append(NSAttributedString(string: "\n", attributes: defaultAttrs))
                }
            }

            return result
        }

        private func parseInline(
            _ text: String,
            baseFont: NSFont,
            boldFont: NSFont,
            color: NSColor
        ) -> NSAttributedString {
            let result = NSMutableAttributedString()
            var remaining = text[text.startIndex...]

            while !remaining.isEmpty {
                // Bold: **text**
                if remaining.hasPrefix("**"),
                   let endRange = remaining.dropFirst(2).range(of: "**") {
                    let inner = remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<endRange.lowerBound]
                    result.append(NSAttributedString(string: String(inner), attributes: [
                        .font: boldFont,
                        .foregroundColor: color
                    ]))
                    remaining = remaining[endRange.upperBound...]
                }
                // Italic: *text*
                else if remaining.hasPrefix("*"),
                        let endRange = remaining.dropFirst(1).range(of: "*") {
                    let inner = remaining[remaining.index(after: remaining.startIndex)..<endRange.lowerBound]
                    let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
                    result.append(NSAttributedString(string: String(inner), attributes: [
                        .font: italicFont,
                        .foregroundColor: color
                    ]))
                    remaining = remaining[endRange.upperBound...]
                }
                // Code: `text`
                else if remaining.hasPrefix("`"),
                        let endRange = remaining.dropFirst(1).range(of: "`") {
                    let inner = remaining[remaining.index(after: remaining.startIndex)..<endRange.lowerBound]
                    let monoFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                    result.append(NSAttributedString(string: String(inner), attributes: [
                        .font: monoFont,
                        .foregroundColor: color,
                        .backgroundColor: NSColor(Theme.surface3)
                    ]))
                    remaining = remaining[endRange.upperBound...]
                }
                // Regular character
                else {
                    let char = remaining[remaining.startIndex]
                    result.append(NSAttributedString(string: String(char), attributes: [
                        .font: baseFont,
                        .foregroundColor: color
                    ]))
                    remaining = remaining[remaining.index(after: remaining.startIndex)...]
                }
            }

            return result
        }

        func attributedToMarkdown(_ attributed: NSAttributedString) -> String {
            var result = ""
            attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attrs, range, _ in
                let text = (attributed.string as NSString).substring(with: range)
                let font = attrs[.font] as? NSFont

                if let font = font {
                    let traits = font.fontDescriptor.symbolicTraits
                    let isBold = traits.contains(.bold)
                    let isItalic = traits.contains(.italic)
                    let isMono = font.isFixedPitch

                    // Heading detection by font size
                    if font.pointSize >= 22 && isBold && !text.contains("\n") {
                        result += "# \(text)"
                        return
                    } else if font.pointSize >= 18 && isBold && !text.contains("\n") {
                        result += "## \(text)"
                        return
                    } else if font.pointSize >= 15 && isBold && !text.contains("\n") {
                        result += "### \(text)"
                        return
                    }

                    if isMono {
                        result += "`\(text)`"
                    } else if isBold && isItalic {
                        result += "***\(text)***"
                    } else if isBold {
                        result += "**\(text)**"
                    } else if isItalic {
                        result += "*\(text)*"
                    } else {
                        result += text
                    }
                } else {
                    result += text
                }
            }
            return result
        }

        private func debounceSave() {
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await MainActor.run { parent.onSave() }
            }
        }
    }
}

/// Custom NSTextView subclass to handle Cmd+B / Cmd+I
class RichEditorTextView: NSTextView {
    weak var coordinator: RichTextEditor.Coordinator?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "b":
                coordinator?.toggleBold()
                return
            case "i":
                coordinator?.toggleItalic()
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
    }
}
