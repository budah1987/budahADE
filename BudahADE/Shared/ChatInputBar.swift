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

    // MARK: - Actions

    var onSend: (String) -> Void
    var onCancel: (() -> Void)? = nil
    /// Called to persist image data; returns file path. If nil, clipboard paste is disabled.
    var saveImage: ((Data) -> String?)? = nil

    // MARK: - Customization

    var placeholder: String = "BeepBoopBeep..."
    var ghostText: String? = nil

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
        onSend: @escaping (String) -> Void,
        onCancel: (() -> Void)? = nil,
        saveImage: ((Data) -> String?)? = nil,
        placeholder: String = "BeepBoopBeep...",
        ghostText: String? = nil,
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
    @State private var showFilePicker: Bool = false
    @State private var showModelMenu: Bool = false
    @State private var showContextMemoryOverlay: Bool = false
    @State private var attachHovering: Bool = false

    // MARK: - Computed

    private var hasInput: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSend: Bool {
        hasInput || pendingImagePath != nil
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

    var body: some View {
        VStack(spacing: 0) {
            // Slot: above input (slash popover, pipeline bar, done-state controls)
            aboveInput

            // Pending attachment preview
            if pendingImage != nil || pendingImagePath != nil {
                attachmentPreview
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
                if let ghost = ghostText, !ghost.isEmpty {
                    Text(ghost)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.Colors.textSecondary.opacity(0.5))
                        .padding(.top, 2)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $inputText)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(hasInput ? 1.0 : 0.4))
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
                        if let handler = onReturnKey, handler(press) == .handled {
                            return .handled
                        }
                        send()
                        return .handled
                    }
                    .onKeyPress(.tab, phases: .down) { press in
                        if let handler = onTabKey {
                            return handler(press)
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
        if let imagePath = pendingImagePath {
            prompt = prompt.isEmpty ? "[Image: \(imagePath)]" : prompt + "\n[Image: \(imagePath)]"
        }

        inputText = ""
        pendingImage = nil
        pendingImagePath = nil

        onSend(prompt)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            inputFocused = true
        }
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
}

// MARK: - Convenience Init (no slots)

extension ChatInputBar where AboveInput == EmptyView, TopBarExtras == EmptyView {
    init(
        inputText: Binding<String>,
        selectedModel: Binding<AgentModel>,
        session: AgentSession? = nil,
        isRunning: Bool = false,
        onSend: @escaping (String) -> Void,
        onCancel: (() -> Void)? = nil,
        saveImage: ((Data) -> String?)? = nil,
        placeholder: String = "BeepBoopBeep...",
        ghostText: String? = nil,
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
        self.onReturnKey = onReturnKey
        self.onTabKey = onTabKey
        self.aboveInput = EmptyView()
        self.topBarExtras = EmptyView()
    }
}
