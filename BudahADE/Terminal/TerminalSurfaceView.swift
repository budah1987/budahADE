import AppKit
import Carbon.HIToolbox

/// NSView that hosts the Ghostty Metal surface and forwards input events.
final class TerminalSurfaceView: NSView {
    weak var terminalSurface: TerminalSurface?
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.backgroundColor = NSColor(hex: 0x141416).cgColor
        updateTrackingAreas()
    }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    // MARK: - View Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        terminalSurface?.attachToView(self)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contentsScale = window.backingScaleFactor
        CATransaction.commit()

        // Ensure the terminal view grabs first responder so keyboard input works immediately
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let window {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contentsScale = window.backingScaleFactor
            CATransaction.commit()
        }
        updateSurfaceSize()
    }

    override func layout() {
        super.layout()
        updateSurfaceSize()
    }

    private func updateSurfaceSize() {
        guard let terminalSurface, bounds.width > 0, bounds.height > 0 else { return }
        let scale = max(1.0, window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0)
        terminalSurface.updateSize(width: bounds.width, height: bounds.height, scale: scale)
    }

    // MARK: - Keyboard Input

    override func keyDown(with event: NSEvent) {
        guard let surface = terminalSurface?.surface else {
            super.keyDown(with: event)
            return
        }

        let mods = modsFromEvent(event)

        // When Option is held, macOS produces composed characters (e.g., Opt+P → π).
        // Send the unmodified character instead so Ghostty receives 'p' + ALT modifier,
        // matching macos-option-as-alt behavior. This makes Opt+P work as Alt+P in Claude CLI.
        let text: String? = {
            let isOptionHeld = event.modifierFlags.contains(.option)
            let chars = isOptionHeld
                ? event.charactersIgnoringModifiers
                : event.characters
            guard let chars, !chars.isEmpty else { return nil }
            // Filter out Unicode private-use area (U+F700–U+F8FF) — arrow/function keys
            if let scalar = chars.unicodeScalars.first,
               scalar.value >= 0xF700, scalar.value <= 0xF8FF {
                return nil
            }
            return chars
        }()

        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_PRESS
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = mods
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.unshifted_codepoint = 0
        keyEvent.composing = false

        let handled: Bool
        if let text, !text.isEmpty {
            handled = text.withCString { ptr in
                keyEvent.text = ptr
                return ghostty_surface_key(surface, keyEvent)
            }
        } else {
            keyEvent.text = nil
            handled = ghostty_surface_key(surface, keyEvent)
        }

        if !handled {
            interpretKeyEvents([event])
        }
    }

    override func keyUp(with event: NSEvent) {
        guard let surface = terminalSurface?.surface else {
            super.keyUp(with: event)
            return
        }

        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_RELEASE
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = modsFromEvent(event)
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.text = nil
        keyEvent.unshifted_codepoint = 0
        keyEvent.composing = false
        _ = ghostty_surface_key(surface, keyEvent)
    }

    override func flagsChanged(with event: NSEvent) {
        guard let surface = terminalSurface?.surface else {
            super.flagsChanged(with: event)
            return
        }

        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_PRESS
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = modsFromEvent(event)
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.text = nil
        keyEvent.unshifted_codepoint = 0
        keyEvent.composing = false
        _ = ghostty_surface_key(surface, keyEvent)
    }

    override func insertText(_ insertString: Any) {
        guard let surface = terminalSurface?.surface else { return }
        guard let str = insertString as? String else { return }
        str.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(str.utf8.count))
        }
    }

    // MARK: - Mouse Input

    override func mouseDown(with event: NSEvent) {
        guard let surface = terminalSurface?.surface else { return }
        window?.makeFirstResponder(self)
        terminalSurface?.setFocus(true)
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, point.x, bounds.height - point.y, modsFromEvent(event))
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, modsFromEvent(event))
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface = terminalSurface?.surface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, modsFromEvent(event))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let surface = terminalSurface?.surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, point.x, bounds.height - point.y, modsFromEvent(event))
    }

    override func mouseMoved(with event: NSEvent) {
        guard let surface = terminalSurface?.surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, point.x, bounds.height - point.y, modsFromEvent(event))
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface = terminalSurface?.surface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, modsFromEvent(event))
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface = terminalSurface?.surface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, modsFromEvent(event))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface = terminalSurface?.surface else { return }
        let mods: Int32 = 0
        // Scroll mods is a packed int, not modifier flags
        ghostty_surface_mouse_scroll(surface, event.scrollingDeltaX, event.scrollingDeltaY, mods)
    }

    // MARK: - Tracking Areas

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    // MARK: - Focus

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            terminalSurface?.setFocus(true)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            terminalSurface?.setFocus(false)
        }
        return result
    }

    // MARK: - Paste

    @objc func paste(_ sender: Any?) {
        guard let surface = terminalSurface?.surface else { return }
        guard let str = NSPasteboard.general.string(forType: .string) else { return }
        str.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(str.utf8.count))
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Cmd+V → paste
        if flags == .command && event.keyCode == 9 {
            paste(nil)
            return true
        }
        // Cmd+C → copy selection
        if flags == .command && event.keyCode == 8 {
            if let surface = terminalSurface?.surface, ghostty_surface_has_selection(surface) {
                var textInfo = ghostty_text_s()
                if ghostty_surface_read_selection(surface, &textInfo), let ptr = textInfo.text {
                    let text = String(cString: ptr)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    ghostty_surface_free_text(surface, &textInfo)
                }
                return true
            }
        }

        // Claim arrow keys and other navigation keys so AppKit doesn't steal them
        // for focus traversal. Forward them to keyDown instead.
        let keyCode = event.keyCode
        if Self.terminalClaimedKeyCodes.contains(keyCode) && flags.isEmpty {
            keyDown(with: event)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    // Key codes that the terminal should always handle (not AppKit focus system).
    // Arrow keys, Home, End, Page Up/Down, Delete (forward), Function keys, Escape, Tab.
    private static let terminalClaimedKeyCodes: Set<UInt16> = {
        var codes: Set<UInt16> = []
        // Arrow keys
        codes.insert(UInt16(kVK_UpArrow))    // 126
        codes.insert(UInt16(kVK_DownArrow))  // 125
        codes.insert(UInt16(kVK_LeftArrow))  // 123
        codes.insert(UInt16(kVK_RightArrow)) // 124
        // Navigation
        codes.insert(UInt16(kVK_Home))       // 115
        codes.insert(UInt16(kVK_End))        // 119
        codes.insert(UInt16(kVK_PageUp))     // 116
        codes.insert(UInt16(kVK_PageDown))   // 121
        codes.insert(UInt16(kVK_ForwardDelete)) // 117
        codes.insert(UInt16(kVK_Escape))     // 53
        // Function keys
        for code: UInt16 in [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111] {
            codes.insert(code) // F1-F12
        }
        return codes
    }()

    // MARK: - Helpers

    private func modsFromEvent(_ event: NSEvent) -> ghostty_input_mods_e {
        let flags = event.modifierFlags
        var mods = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(rawValue: mods)
    }
}
