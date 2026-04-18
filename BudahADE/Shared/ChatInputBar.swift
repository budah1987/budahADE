import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Input Height Key

struct InputHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Model Selector Menu

struct ModelSelectorMenu: View {
    @Binding var selectedModel: AgentModel
    @Binding var isShowing: Bool

    var body: some View {
        VStack(spacing: 0) {
            ForEach(AgentModel.allCases) { model in
                Button {
                    selectedModel = model
                    withAnimation(.easeOut(duration: 0.15)) {
                        isShowing = false
                    }
                } label: {
                    HStack {
                        Text(model.displayName)
                            .font(Theme.body(13))
                            .foregroundColor(model == selectedModel ? .white : Color(hex: 0x938d8d))
                        Spacer()
                        if model == selectedModel {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(model == selectedModel ? Color.white.opacity(0.06) : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            ZStack {
                GlassBackground(material: .popover, cornerRadius: 8)
                Color(hex: 0x1b1b1e).opacity(0.85)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .frame(width: 180)
        .shadow(color: .black.opacity(0.4), radius: 12)
    }
}

// MARK: - Context Memory Overlay

struct ContextMemoryOverlay: View {
    let session: AgentSession?
    let model: AgentModel
    var onDismiss: (() -> Void)? = nil

    private var totalTokens: Int { session?.totalTokens ?? 0 }
    private var inputTokens: Int { session?.totalInputTokens ?? 0 }
    private var outputTokens: Int { session?.totalOutputTokens ?? 0 }
    private var contextWindow: Int { model.contextWindowTokens }
    private var utilization: Double { session?.contextUtilization ?? 0 }

    private func fmt(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fk", Double(count) / 1_000) }
        return "\(count)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Context")
                    .font(Theme.label(13))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text("\(fmt(totalTokens))/\(fmt(contextWindow))")
                    .font(Theme.code(12))
                    .foregroundColor(Color(hex: 0x938d8d))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: 0x555555).opacity(0.4))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.85))
                        .frame(width: geo.size.width * utilization, height: 6)
                }
            }
            .frame(height: 6)

            VStack(spacing: 6) {
                tokenRow(label: "Input tokens", count: inputTokens, fraction: Double(inputTokens) / max(Double(totalTokens), 1))
                tokenRow(label: "Output tokens", count: outputTokens, fraction: Double(outputTokens) / max(Double(totalTokens), 1))
                if let session {
                    tokenRow(label: "Messages", count: session.messages.count, fraction: nil)
                }
            }
        }
        .padding(14)
        .frame(width: 240)
        .background(
            ZStack {
                GlassBackground(material: .popover, cornerRadius: 10)
                Color(hex: 0x1b1b1e).opacity(0.9)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 16)
    }

    @ViewBuilder
    private func tokenRow(label: String, count: Int, fraction: Double?) -> some View {
        HStack {
            Text(label)
                .font(Theme.body(11))
                .foregroundColor(Color(hex: 0x938d8d))
            Spacer()
            if let fraction {
                Text(String(format: "%.1f%%", fraction * 100))
                    .font(Theme.code(11))
                    .foregroundColor(Color(hex: 0x938d8d))
            } else {
                Text("\(count)")
                    .font(Theme.code(11))
                    .foregroundColor(Color(hex: 0x938d8d))
            }
        }
    }
}

// MARK: - Chat Input Bar

/// Shared input bar used by both Plan and Builder modes.
/// Generic view slots allow mode-specific UI to be injected without diverging the core component.
///
/// - `AboveInput`: Content rendered above the input pill (slash popover, pipeline bar, done-state controls)
/// - `TopBarExtras`: Extra buttons between model selector and context ring (fast thinking, plan mode toggles)
struct ChatInputBar<AboveInput: View, TopBarExtras: View>: View {

    // MARK: - Data bindings (parent owns state)

    @Binding var inputText: String
    @Binding var selectedModel: AgentModel

    // MARK: - Read-only state from parent

    var session: AgentSession?
    var isRunning: Bool

    // MARK: - Document mentions

    /// Working directory for @ mention file scanning. When non-nil, typing `@` triggers a file picker popover.
    var workingDirectory: String? = nil

    // MARK: - Actions

    var onSend: (String, [DocumentAttachment]) -> Void
    var onCancel: (() -> Void)? = nil
    /// Called to persist image data; returns file path. If nil, clipboard paste is disabled.
    var saveImage: ((Data) -> String?)? = nil

    // MARK: - Customization

    var placeholder: String = "BeepBoopBeep..."
    var ghostText: String? = nil
    /// When set, the characters at this range are rendered in accent blue (skill like "/grill-me").
    var skillHighlightRange: (start: Int, length: Int)? = nil

    // MARK: - Key event overrides (called before built-in handlers)

    /// Return key handler; return `.handled` to suppress the default send action.
    var onReturnKey: ((KeyPress) -> KeyPress.Result)? = nil
    /// Tab key handler.
    var onTabKey: ((KeyPress) -> KeyPress.Result)? = nil

    // MARK: - View slots

    var aboveInput: AboveInput
    var topBarExtras: TopBarExtras

    // MARK: - Init

    init(
        inputText: Binding<String>,
        selectedModel: Binding<AgentModel>,
        session: AgentSession? = nil,
        isRunning: Bool = false,
        onSend: @escaping (String, [DocumentAttachment]) -> Void,
        onCancel: (() -> Void)? = nil,
        saveImage: ((Data) -> String?)? = nil,
        placeholder: String = "BeepBoopBeep...",
        ghostText: String? = nil,
        workingDirectory: String? = nil,
        skillHighlightRange: (start: Int, length: Int)? = nil,
        onReturnKey: ((KeyPress) -> KeyPress.Result)? = nil,
        onTabKey: ((KeyPress) -> KeyPress.Result)? = nil,
        @ViewBuilder aboveInput: () -> AboveInput,
        @ViewBuilder topBarExtras: () -> TopBarExtras
    ) {
        self._inputText = inputText
        self._selectedModel = selectedModel
        self.session = session
        self.isRunning = isRunning
        self.onSend = onSend
        self.onCancel = onCancel
        self.saveImage = saveImage
        self.placeholder = placeholder
        self.ghostText = ghostText
        self.workingDirectory = workingDirectory
        self.skillHighlightRange = skillHighlightRange
        self.onReturnKey = onReturnKey
        self.onTabKey = onTabKey
        self.aboveInput = aboveInput()
        self.topBarExtras = topBarExtras()
    }

    // MARK: - Internal state

    @FocusState private var inputFocused: Bool
    @State private var inputTextHeight: CGFloat = 36
    @State private var pendingImage: NSImage?
    @State private var pendingImagePath: String?
    @State private var pendingDocuments: [(path: String, relativePath: String, lineCount: Int)] = []
    @State private var showFilePicker: Bool = false
    @State private var showModelMenu: Bool = false
    @State private var showContextMemoryOverlay: Bool = false
    @State private var attachHovering: Bool = false

    // MARK: - Document mention state

    @State private var mentionPopoverIndex: Int = 0
    @StateObject private var mentionState = MentionPopoverState()
    @State private var mentionDismissed: Bool = false
    @State private var cachedMentionFiles: [FileMentionItem] = []
    @State private var mentionKeyMonitor: Any?
    /// Current folder being browsed in the mention popover (relative to workingDirectory, "" = root)
    @State private var mentionBrowsePath: String = ""

    /// Finds the active `@query` token at the end of the current input.
    /// Returns the query text (after `@`) and the range of the full `@query` token, or nil if not in a mention context.
    private var activeMentionContext: (query: String, range: Range<String.Index>)? {
        guard workingDirectory != nil, !mentionDismissed else { return nil }
        let text = inputText

        // Find the last `@` that isn't preceded by a letter/digit (word boundary)
        guard let atIndex = text.lastIndex(of: "@") else { return nil }

        // `@` must be at start or preceded by whitespace
        if atIndex != text.startIndex {
            let before = text.index(before: atIndex)
            let charBefore = text[before]
            guard charBefore.isWhitespace || charBefore == "\n" else { return nil }
        }

        let afterAt = text.index(after: atIndex)
        // Check the query doesn't contain a space (not yet completed)
        let querySubstring = text[afterAt...]
        if querySubstring.contains(" ") { return nil }

        let query = String(querySubstring)
        return (query: query, range: atIndex..<text.endIndex)
    }

    /// Whether the mention popover should be visible
    private var showMentionPopover: Bool {
        activeMentionContext != nil && !isRunning && !filteredMentionItems.isEmpty
    }

    /// Whether we're in browse mode (no query typed) vs search mode (query typed)
    private var isBrowseMode: Bool {
        guard let ctx = activeMentionContext else { return false }
        return ctx.query.isEmpty
    }

    /// Mention items filtered by current query, or directory listing in browse mode
    private var filteredMentionItems: [FileMentionItem] {
        guard let ctx = activeMentionContext, let dir = workingDirectory else { return [] }
        if ctx.query.isEmpty {
            // Browse mode — show contents of current browse directory
            return DocumentMentionScanner.listDirectory(rootPath: dir, subPath: mentionBrowsePath)
        }
        // Search mode — global fuzzy search across all cached files
        return DocumentMentionScanner.filter(cachedMentionFiles, query: ctx.query)
    }

    /// Ghost text for mention completion
    private var mentionGhostText: String? {
        guard showMentionPopover, let ctx = activeMentionContext else { return nil }
        let items = filteredMentionItems
        guard !items.isEmpty else { return nil }
        let idx = min(mentionPopoverIndex, items.count - 1)
        let item = items[idx]
        // Show the full @path as ghost
        let beforeAt = inputText[inputText.startIndex..<ctx.range.lowerBound]
        return beforeAt + "@\(item.relativePath)"
    }

    // MARK: - Computed

    private var hasInput: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSend: Bool {
        hasInput || pendingImagePath != nil || !pendingDocuments.isEmpty
    }

    private var totalTokens: Int { session?.totalTokens ?? 0 }

    private var tokenFraction: Double {
        guard totalTokens > 0 else { return 0 }
        let window = Double(selectedModel.contextWindowTokens)
        guard window > 0 else { return 0 }
        return min(Double(totalTokens) / window, 1.0)
    }

    private var tokenLabel: String {
        "\(formatTokenCount(totalTokens)) / \(formatTokenCount(selectedModel.contextWindowTokens))"
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.0fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fk", Double(count) / 1_000) }
        return "\(count)"
    }

    // MARK: - Body

    /// Effective ghost text — mention ghost takes priority over parent-provided ghost
    private var effectiveGhostText: String? {
        mentionGhostText ?? ghostText
    }

    /// Build an attributed string where the already-typed prefix is transparent
    /// and only the completion tail is visible in a faint color.
    private func ghostAttributedString(ghost: String, typed: String) -> AttributedString {
        var attr = AttributedString(ghost)
        attr.foregroundColor = Theme.Colors.textSecondary.opacity(0.5)

        // Make the typed prefix invisible so only the completion portion shows
        let typedCount = typed.count
        if typedCount > 0 && typedCount < ghost.count {
            let prefixEnd = attr.characters.index(attr.startIndex, offsetBy: typedCount)
            attr[attr.startIndex..<prefixEnd].foregroundColor = .clear
        } else if typedCount >= ghost.count {
            // Ghost matches typed text entirely — hide it all
            attr.foregroundColor = .clear
        }

        return attr
    }

    /// Build an attributed string with the skill command in blue and the rest in white.
    private var skillHighlightAttributedString: AttributedString {
        let text = inputText
        var attr = AttributedString(text)
        attr.foregroundColor = .white
        if let range = skillHighlightRange {
            let clampedStart = min(range.start, text.count)
            let clampedEnd = min(range.start + range.length, text.count)
            if clampedStart < clampedEnd {
                let start = attr.characters.index(attr.startIndex, offsetBy: clampedStart)
                let end = attr.characters.index(attr.startIndex, offsetBy: clampedEnd)
                attr[start..<end].foregroundColor = Color(hex: 0x5B9CF5)
            }
        }
        return attr
    }

    var body: some View {
        VStack(spacing: 0) {
            // Document mention popover — floats above everything
            if showMentionPopover {
                DocumentMentionPopover(
                    items: filteredMentionItems,
                    filter: activeMentionContext?.query ?? "",
                    onSelect: { item in completeMention(item) },
                    onFolderOpen: { folder in openMentionFolder(folder) },
                    onDismiss: { mentionDismissed = true },
                    browsePath: mentionBrowsePath,
                    onBrowseBack: { mentionBrowseBack() },
                    selectedIndex: $mentionPopoverIndex
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Slot: above input (slash popover, pipeline bar, done-state controls)
            aboveInput

            // Pending attachment previews
            if pendingImage != nil || pendingImagePath != nil {
                attachmentPreview
            }
            if !pendingDocuments.isEmpty {
                documentAttachmentPreview
            }

            // Two-bar input container
            VStack(spacing: 0) {
                topBar
                bottomBar
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            // Model selector overlay
            .overlay(alignment: .topLeading) {
                if showModelMenu {
                    ModelSelectorMenu(selectedModel: $selectedModel, isShowing: $showModelMenu)
                        .offset(x: 12, y: -8)
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottomLeading)))
                }
            }
            // Context memory overlay
            .overlay(alignment: .topTrailing) {
                if showContextMemoryOverlay {
                    ContextMemoryOverlay(
                        session: session,
                        model: selectedModel,
                        onDismiss: { showContextMemoryOverlay = false }
                    )
                    .offset(x: -12, y: -8)
                    .fixedSize()
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottomTrailing)))
                }
            }
            .zIndex(showModelMenu || showContextMemoryOverlay ? 100 : 0)
            .onTapGesture {
                if showModelMenu {
                    withAnimation(.easeOut(duration: 0.15)) { showModelMenu = false }
                }
                if showContextMemoryOverlay {
                    withAnimation(.easeOut(duration: 0.15)) { showContextMemoryOverlay = false }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 80)
        .padding(.bottom, 16)
        .background(Color.clear)
        .onDrop(of: ["public.image", "public.file-url"], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [
                .png, .jpeg, .tiff, .image, .svg, .gif,
                .plainText, .sourceCode, .json, .yaml, .xml, .html,
                .pdf,
                .rtf, .rtfd,
                .commaSeparatedText, .tabSeparatedText,
                .data, // fallback — allows any file
            ],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result,
                  let url = urls.first else { return }
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }

            // Try to load as image first
            if let data = try? Data(contentsOf: url),
               let image = NSImage(data: data) {
                if let saveImage, let path = saveImage(data) {
                    pendingImage = image
                    pendingImagePath = path
                } else {
                    pendingImage = image
                    pendingImagePath = url.path
                }
            } else {
                // Non-image file — attach by path only (no preview)
                pendingImage = nil
                pendingImagePath = url.path
            }
        }
        .onAppear {
            scanMentionFilesIfNeeded()
            installMentionKeyMonitor()
        }
        .onDisappear {
            removeMentionKeyMonitor()
        }
        .onChange(of: workingDirectory) { _, _ in
            scanMentionFilesIfNeeded()
        }
        .onChange(of: inputText) { oldValue, newValue in
            // Reset mention dismiss and browse when @ context changes
            if !newValue.contains("@") {
                mentionDismissed = false
                mentionBrowsePath = ""
            } else if oldValue.count != newValue.count && activeMentionContext != nil {
                // User is typing after @, reset dismiss and reset selection
                mentionDismissed = false
                mentionPopoverIndex = 0
            }
            // Sync mention state for NSEvent monitor
            let visible = activeMentionContext != nil && !isRunning && !mentionDismissed
            mentionState.isVisible = visible
            mentionState.items = visible ? filteredMentionItems : []
            mentionState.selectedIndex = mentionPopoverIndex
        }
        .onChange(of: mentionState.selectedIndex) { _, newValue in
            mentionPopoverIndex = newValue
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 10) {
            // Model selector button
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    showModelMenu.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedModel.displayName.lowercased())
                        .font(Theme.code(12))
                        .foregroundColor(Color(hex: 0x938d8d))
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Color(hex: 0x938d8d))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            // Injected extras (fast thinking, plan mode, etc.)
            topBarExtras

            Spacer()

            // Context Memory dial
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    showContextMemoryOverlay.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .stroke(Color(hex: 0x555555).opacity(0.4), lineWidth: 2)
                            .frame(width: 16, height: 16)
                        Circle()
                            .trim(from: 0, to: tokenFraction)
                            .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .frame(width: 16, height: 16)
                            .rotationEffect(.degrees(-90))
                    }
                    Text(tokenLabel)
                        .font(Theme.code(10))
                        .foregroundColor(Color(hex: 0x938d8d))
                }
            }
            .buttonStyle(.plain)
            .help("Context memory")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            ZStack {
                GlassBackground(material: .hudWindow, cornerRadius: 0)
                Color(hex: 0x2a2a2e).opacity(0.5)
            }
        )
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if inputText.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.top, 2)
                        .allowsHitTesting(false)
                }
                if let ghost = effectiveGhostText, !ghost.isEmpty {
                    Text(ghostAttributedString(ghost: ghost, typed: inputText))
                        .font(.system(size: 14))
                        .padding(.top, 2)
                        .allowsHitTesting(false)
                }
                // Skill highlight overlay — shows "/command" in blue, rest in white
                if skillHighlightRange != nil, !inputText.isEmpty {
                    Text(skillHighlightAttributedString)
                        .font(.system(size: 14))
                        .padding(.top, 2)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $inputText)
                    .font(.system(size: 14))
                    .foregroundColor(skillHighlightRange != nil ? .clear : .white.opacity(hasInput ? 1.0 : 0.4))
                    .frame(height: min(max(inputTextHeight + 10, 36), 200))
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($inputFocused)
                    .background(
                        Text(inputText.isEmpty ? "A" : inputText)
                            .font(.system(size: 14))
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(0)
                            .background(GeometryReader { textGeo in
                                Color.clear.preference(
                                    key: InputHeightKey.self,
                                    value: textGeo.size.height
                                )
                            })
                    )
                    .onPreferenceChange(InputHeightKey.self) { h in
                        if h > 0 { inputTextHeight = h }
                    }
                    .onKeyPress(.return, phases: .down) { press in
                        guard !press.modifiers.contains(.shift) else { return .ignored }
                        // Let Cmd+Enter bubble up to parent views (plan/builder confirm handlers)
                        guard !press.modifiers.contains(.command) else { return .ignored }
                        // Mention popover intercepts Return
                        if showMentionPopover {
                            let items = filteredMentionItems
                            let idx = min(mentionPopoverIndex, items.count - 1)
                            if idx < items.count {
                                let item = items[idx]
                                if item.isDirectory && isBrowseMode {
                                    openMentionFolder(item)
                                } else {
                                    completeMention(item)
                                }
                                return .handled
                            }
                        }
                        if let handler = onReturnKey, handler(press) == .handled {
                            return .handled
                        }
                        send()
                        return .handled
                    }
                    .onKeyPress(.tab, phases: .down) { press in
                        // Mention popover intercepts Tab
                        if showMentionPopover {
                            let items = filteredMentionItems
                            let idx = min(mentionPopoverIndex, items.count - 1)
                            if idx < items.count {
                                let item = items[idx]
                                if item.isDirectory && isBrowseMode {
                                    openMentionFolder(item)
                                } else {
                                    completeMention(item)
                                }
                                return .handled
                            }
                        }
                        if let handler = onTabKey {
                            return handler(press)
                        }
                        return .ignored
                    }
                    .onKeyPress(.escape, phases: .down) { _ in
                        if showMentionPopover {
                            mentionDismissed = true
                            mentionBrowsePath = ""
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(characters: CharacterSet(charactersIn: "v"), phases: .down) { press in
                        guard press.modifiers.contains(.command) else { return .ignored }
                        if pasteImageFromClipboard() { return .handled }
                        return .ignored
                    }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)

            // Action row
            HStack(spacing: 8) {
                Button { showFilePicker = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(attachHovering ? .white : Color(hex: 0x938d8d))
                        .frame(width: 24, height: 24)
                        .background(attachHovering ? Color.white.opacity(0.08) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .onHover { hovering in attachHovering = hovering }
                .help("Attach file")

                Spacer()

                if isRunning && onCancel != nil {
                    Button(action: { onCancel?() }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(hasInput ? .white : .white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .background(Color(hex: 0x33343A))
    }

    // MARK: - Attachment Preview

    private var attachmentPreview: some View {
        HStack(spacing: 8) {
            if let img = pendingImage {
                // Image preview
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if let path = pendingImagePath {
                // Non-image file chip
                HStack(spacing: 6) {
                    Image(systemName: iconForFile(path))
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: 0x938d8d))
                    Text((path as NSString).lastPathComponent)
                        .font(Theme.code(12))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
            }
            Button {
                pendingImage = nil
                pendingImagePath = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var documentAttachmentPreview: some View {
        HStack(spacing: 6) {
            ForEach(Array(pendingDocuments.enumerated()), id: \.offset) { index, doc in
                HStack(spacing: 5) {
                    Image(systemName: iconForFile(doc.relativePath))
                        .font(.system(size: 10))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text((doc.relativePath as NSString).lastPathComponent)
                        .font(Theme.code(11))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(1)
                    Text("\(doc.lineCount) lines")
                        .font(Theme.caption(9))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Button {
                        pendingDocuments.remove(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private func iconForFile(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "md", "txt", "rtf":       return "doc.text"
        case "pdf":                     return "doc.richtext"
        case "json", "yaml", "yml":    return "curlybraces"
        case "swift", "py", "js", "ts", "rs", "go", "rb", "java", "c", "cpp", "h":
            return "chevron.left.forwardslash.chevron.right"
        case "html", "css", "xml":     return "globe"
        case "csv", "tsv":             return "tablecells"
        default:                        return "doc"
        }
    }

    // MARK: - Actions

    private func send() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }

        var prompt = trimmed

        // Expand any remaining @file mentions in text (legacy inline mentions)
        if let dir = workingDirectory {
            prompt = expandMentions(in: prompt, rootPath: dir)
        }

        // Append pending document contents for the agent (not shown in UI)
        var attachments: [DocumentAttachment] = []
        for doc in pendingDocuments {
            if let data = FileManager.default.contents(atPath: doc.path),
               let content = String(data: data, encoding: .utf8) {
                prompt += "\n<document path=\"\(doc.relativePath)\">\n\(content)\n</document>"
                attachments.append(DocumentAttachment(path: doc.relativePath, lineCount: doc.lineCount))
            }
        }

        if let imagePath = pendingImagePath {
            prompt = prompt.isEmpty ? "[Image: \(imagePath)]" : prompt + "\n[Image: \(imagePath)]"
        }

        inputText = ""
        pendingImage = nil
        pendingImagePath = nil
        pendingDocuments = []

        onSend(prompt, attachments)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            inputFocused = true
        }
    }

    /// Expand `@relativePath` tokens into `@relativePath` with file content appended.
    /// Matches `@` preceded by start-of-string or whitespace, followed by a non-space path.
    private func expandMentions(in text: String, rootPath: String) -> String {
        // Pattern: @ at word boundary followed by a non-space path
        let pattern = #"(?:^|(?<=\s))@(\S+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        guard !matches.isEmpty else { return text }

        var result = text
        var appendedContents: [String] = []

        for match in matches.reversed() {
            guard match.numberOfRanges >= 2 else { continue }
            let pathRange = match.range(at: 1)
            let relativePath = nsText.substring(with: pathRange)
            let absolutePath = (rootPath as NSString).appendingPathComponent(relativePath)

            // Check if the file exists and is readable
            let fm = FileManager.default
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: absolutePath, isDirectory: &isDir), !isDir.boolValue else { continue }

            // Read file content (limit to ~50KB to avoid huge payloads)
            if let data = fm.contents(atPath: absolutePath),
               data.count <= 50_000,
               let content = String(data: data, encoding: .utf8) {
                appendedContents.insert(
                    "\n<document path=\"\(relativePath)\">\n\(content)\n</document>",
                    at: 0
                )
            }
        }

        if !appendedContents.isEmpty {
            result += appendedContents.joined()
        }

        return result
    }

    @discardableResult
    private func pasteImageFromClipboard() -> Bool {
        guard let saveImage else { return false }
        let pb = NSPasteboard.general
        guard let imageData = pb.data(forType: .png) ?? pb.data(forType: .tiff) else { return false }
        guard let image = NSImage(data: imageData) else { return false }
        let pngData: Data
        if let png = pb.data(forType: .png) {
            pngData = png
        } else if let tiffRep = NSBitmapImageRep(data: imageData),
                  let converted = tiffRep.representation(using: .png, properties: [:]) {
            pngData = converted
        } else {
            return false
        }
        if let path = saveImage(pngData) {
            pendingImage = image
            pendingImagePath = path
            return true
        }
        return false
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.image") {
                provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
                    guard let data, let image = NSImage(data: data) else { return }
                    DispatchQueue.main.async {
                        if let saveImage, let path = saveImage(data) {
                            pendingImage = image
                            pendingImagePath = path
                        }
                    }
                }
                return true
            }
        }
        return false
    }

    // MARK: - Document Mention Helpers

    private func scanMentionFilesIfNeeded() {
        guard let dir = workingDirectory else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let items = DocumentMentionScanner.scan(rootPath: dir)
            DispatchQueue.main.async {
                cachedMentionFiles = items
            }
        }
    }

    private func completeMention(_ item: FileMentionItem) {
        guard let ctx = activeMentionContext, let dir = workingDirectory else { return }
        // Remove the @query from text
        var newText = inputText
        newText.replaceSubrange(ctx.range, with: "")
        inputText = newText
        mentionDismissed = false
        mentionPopoverIndex = 0
        mentionBrowsePath = ""

        // Add to pending documents (skip duplicates)
        let absolutePath = (dir as NSString).appendingPathComponent(item.relativePath)
        guard !pendingDocuments.contains(where: { $0.relativePath == item.relativePath }) else { return }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: absolutePath, isDirectory: &isDir), !isDir.boolValue else { return }
        if let data = fm.contents(atPath: absolutePath),
           data.count <= 50_000,
           let content = String(data: data, encoding: .utf8) {
            let lines = content.components(separatedBy: "\n").count
            pendingDocuments.append((path: absolutePath, relativePath: item.relativePath, lineCount: lines))
        }
    }

    private func openMentionFolder(_ folder: FileMentionItem) {
        guard folder.isDirectory else { return }
        mentionBrowsePath = folder.relativePath
        mentionPopoverIndex = 0
    }

    private func mentionBrowseBack() {
        if mentionBrowsePath.isEmpty { return }
        // Go up one directory level
        let parent = (mentionBrowsePath as NSString).deletingLastPathComponent
        mentionBrowsePath = parent == "." ? "" : parent
        mentionPopoverIndex = 0
    }

    private func installMentionKeyMonitor() {
        guard workingDirectory != nil else { return }
        let ms = mentionState
        mentionKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            guard ms.isVisible else { return event }
            switch Int(event.keyCode) {
            case 126: // up arrow
                DispatchQueue.main.async { ms.moveUp() }
                return nil
            case 125: // down arrow
                DispatchQueue.main.async { ms.moveDown() }
                return nil
            case 51: // delete/backspace — go back one folder when browsing and query is empty
                if !self.mentionBrowsePath.isEmpty && self.isBrowseMode {
                    DispatchQueue.main.async { self.mentionBrowseBack() }
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }

    private func removeMentionKeyMonitor() {
        if let monitor = mentionKeyMonitor {
            NSEvent.removeMonitor(monitor)
            mentionKeyMonitor = nil
        }
    }
}

// MARK: - Convenience Init (no slots)

extension ChatInputBar where AboveInput == EmptyView, TopBarExtras == EmptyView {
    init(
        inputText: Binding<String>,
        selectedModel: Binding<AgentModel>,
        session: AgentSession? = nil,
        isRunning: Bool = false,
        onSend: @escaping (String, [DocumentAttachment]) -> Void,
        onCancel: (() -> Void)? = nil,
        saveImage: ((Data) -> String?)? = nil,
        placeholder: String = "BeepBoopBeep...",
        ghostText: String? = nil,
        workingDirectory: String? = nil,
        skillHighlightRange: (start: Int, length: Int)? = nil,
        onReturnKey: ((KeyPress) -> KeyPress.Result)? = nil,
        onTabKey: ((KeyPress) -> KeyPress.Result)? = nil
    ) {
        self._inputText = inputText
        self._selectedModel = selectedModel
        self.session = session
        self.isRunning = isRunning
        self.onSend = onSend
        self.onCancel = onCancel
        self.saveImage = saveImage
        self.placeholder = placeholder
        self.ghostText = ghostText
        self.workingDirectory = workingDirectory
        self.skillHighlightRange = skillHighlightRange
        self.onReturnKey = onReturnKey
        self.onTabKey = onTabKey
        self.aboveInput = EmptyView()
        self.topBarExtras = EmptyView()
    }
}
