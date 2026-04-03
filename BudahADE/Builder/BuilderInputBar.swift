import SwiftUI

// MARK: - Builder Input Height Key

private struct BuilderInputHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 36
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

// MARK: - Builder Input Bar

/// Shared input harness for the builder — matches Plan mode's input area in structure.
/// Done-state controls (Review Diff / Commit) appear above the text field when applicable.
struct BuilderInputBar: View {
    @Bindable var session: BuilderSession
    var agentSession: AgentSession?
    var onSend: (String) -> Void
    var onReviewDiff: () -> Void
    var onCommit: () -> Void

    @State private var inputText: String = ""
    @FocusState private var inputFocused: Bool
    @State private var selectedModel: AgentModel = .sonnet
    @State private var inputTextHeight: CGFloat = 36
    @State private var pendingImage: NSImage? = nil
    @State private var pendingImagePath: String? = nil
    @State private var showFilePicker: Bool = false

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var totalTokens: Int { agentSession?.totalTokens ?? 0 }
    private var contextRatio: Double { min(Double(totalTokens) / 200_000.0, 1.0) }
    private var tokenLabel: String {
        guard totalTokens > 0 else { return "" }
        return totalTokens >= 1000 ? "\(totalTokens / 1000)k" : "\(totalTokens)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)

            // Done state: Review Diff + Commit buttons
            if session.buildState == .done {
                HStack(spacing: 8) {
                    Spacer()
                    Button(action: onReviewDiff) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 10))
                            Text("Review Diff")
                                .font(Theme.label(12))
                        }
                        .foregroundColor(Theme.Colors.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.Colors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button(action: onCommit) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 10))
                            Text("Commit")
                                .font(Theme.label(12))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.Colors.statusDone)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                Divider().opacity(0.3)
            }

            // Pending image preview
            if let img = pendingImage {
                HStack {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
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

            // Input pill
            VStack(spacing: 0) {
                // Model selector + context ring
                HStack(spacing: 4) {
                    // Model selector — tap to cycle
                    Button {
                        let all = AgentModel.allCases
                        if let idx = all.firstIndex(of: selectedModel) {
                            selectedModel = all[(idx + 1) % all.count]
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedModel.displayName.lowercased())
                                .font(Theme.code(14))
                                .foregroundColor(Color(hex: 0x938d8d))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9))
                                .foregroundColor(Color(hex: 0x938d8d))
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Tap to cycle model")

                    Spacer()

                    // Context memory ring + token count
                    if totalTokens > 0 {
                        HStack(spacing: 5) {
                            contextRingView
                            Text(tokenLabel)
                                .font(Theme.caption(10))
                                .foregroundColor(Color(hex: 0x938d8d))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)

                // Auto-expanding text editor
                ZStack(alignment: .topLeading) {
                    if inputText.isEmpty {
                        Text("Talk to the builder…")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.Colors.textTertiary)
                            .padding(.top, 2)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $inputText)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
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
                                .background(GeometryReader { geo in
                                    Color.clear.preference(
                                        key: BuilderInputHeightKey.self,
                                        value: geo.size.height
                                    )
                                })
                        )
                        .onPreferenceChange(BuilderInputHeightKey.self) { h in
                            if h > 0 { inputTextHeight = h }
                        }
                        .onKeyPress(.return, phases: .down) { press in
                            guard !press.modifiers.contains(.shift) else { return .ignored }
                            submit()
                            return .handled
                        }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)

                // Action row: paperclip | send
                HStack(spacing: 8) {
                    Button { showFilePicker = true } label: {
                        Image(systemName: "paperclip")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: 0x938d8d))
                    }
                    .buttonStyle(.plain)
                    .help("Attach image")

                    Spacer()

                    Button(action: submit) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(canSend ? Theme.Colors.statusWorking : Theme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
            .background(Color(hex: 0x6e6e6e).opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(hex: 0x9b8989).opacity(0.45), lineWidth: 0.75)
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.png, .jpeg, .tiff, .image],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                pendingImagePath = url.path
                pendingImage = NSImage(contentsOf: url)
            }
        }
        .background(Theme.Colors.appBackground)
    }

    // MARK: - Context Memory Ring

    private var contextRingView: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 2)
                .frame(width: 18, height: 18)
            if contextRatio > 0 {
                Circle()
                    .trim(from: 0, to: CGFloat(contextRatio))
                    .stroke(Color.white.opacity(0.6), lineWidth: 2)
                    .frame(width: 18, height: 18)
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    // MARK: - Actions

    private func submit() {
        guard canSend else { return }
        let text = inputText
        inputText = ""
        onSend(text)
    }
}
