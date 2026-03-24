import Foundation
import AppKit
import Carbon.HIToolbox

/// Owns a ghostty_surface_t lifecycle. Manages IOSurface/Metal rendering,
/// input forwarding, and size management.
final class TerminalSurface: Identifiable, ObservableObject {
    private(set) var surface: ghostty_surface_t?
    let id: UUID
    private weak var attachedView: TerminalSurfaceView?
    private var callbackContext: Unmanaged<TerminalSurfaceCallbackContext>?
    private let workingDirectory: String?
    private var lastPixelWidth: UInt32 = 0
    private var lastPixelHeight: UInt32 = 0
    @Published var title: String = "Terminal"

    init(workingDirectory: String? = nil) {
        self.id = UUID()
        self.workingDirectory = workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    deinit {
        if let surface {
            ghostty_surface_free(surface)
        }
        callbackContext?.release()
    }

    func attachToView(_ view: TerminalSurfaceView) {
        guard attachedView !== view || surface == nil else { return }
        attachedView = view

        guard view.window != nil else { return }
        guard surface == nil else { return }
        createSurface(for: view)
    }

    private func createSurface(for view: TerminalSurfaceView) {
        guard let app = GhosttyAppManager.shared.app else {
            print("[BudahADE] Ghostty app not initialized, cannot create surface")
            return
        }

        var surfaceConfig = ghostty_surface_config_new()
        surfaceConfig.platform_tag = GHOSTTY_PLATFORM_MACOS
        surfaceConfig.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(view).toOpaque()
        ))

        let context = TerminalSurfaceCallbackContext(surfaceView: view, surfaceId: id)
        let unmanagedContext = Unmanaged.passRetained(context)
        callbackContext?.release()
        callbackContext = unmanagedContext
        surfaceConfig.userdata = unmanagedContext.toOpaque()

        let scale = max(1.0, view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0)
        surfaceConfig.scale_factor = scale
        surfaceConfig.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

        let createSurfaceFn = { [self] in
            self.surface = ghostty_surface_new(app, &surfaceConfig)
        }

        if let wd = workingDirectory, !wd.isEmpty {
            wd.withCString { cWd in
                surfaceConfig.working_directory = cWd
                createSurfaceFn()
            }
        } else {
            createSurfaceFn()
        }

        guard let createdSurface = surface else {
            print("[BudahADE] Failed to create ghostty surface")
            callbackContext?.release()
            callbackContext = nil
            return
        }

        // Set display id for vsync
        if let screen = view.window?.screen ?? NSScreen.main,
           let displayID = screen.displayID,
           displayID != 0 {
            ghostty_surface_set_display_id(createdSurface, displayID)
        }

        // Set content scale and initial size
        ghostty_surface_set_content_scale(createdSurface, scale, scale)
        let backingSize = view.convertToBacking(NSRect(origin: .zero, size: view.bounds.size)).size
        let wpx = UInt32(max(0, floor(backingSize.width)))
        let hpx = UInt32(max(0, floor(backingSize.height)))
        if wpx > 0, hpx > 0 {
            ghostty_surface_set_size(createdSurface, wpx, hpx)
            lastPixelWidth = wpx
            lastPixelHeight = hpx
        }

        ghostty_surface_refresh(createdSurface)
    }

    func updateSize(width: CGFloat, height: CGFloat, scale: CGFloat) {
        guard let surface else { return }
        let wpx = UInt32(max(0, floor(width * scale)))
        let hpx = UInt32(max(0, floor(height * scale)))
        guard wpx > 0, hpx > 0 else { return }
        guard wpx != lastPixelWidth || hpx != lastPixelHeight else { return }

        ghostty_surface_set_content_scale(surface, scale, scale)
        ghostty_surface_set_size(surface, wpx, hpx)
        lastPixelWidth = wpx
        lastPixelHeight = hpx
    }

    func setFocus(_ focused: Bool) {
        guard let surface else { return }
        ghostty_surface_set_focus(surface, focused)
    }

    // MARK: - Text Input

    func sendText(_ text: String) {
        guard let surface, let data = text.data(using: .utf8), !data.isEmpty else { return }
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: CChar.self) else { return }
            ghostty_surface_text(surface, baseAddress, UInt(rawBuffer.count))
        }
    }

    func sendCommand(_ text: String) {
        guard let surface else { return }
        // Send text as key event, then Enter
        text.withCString { ptr in
            var keyEvent = ghostty_input_key_s()
            keyEvent.action = GHOSTTY_ACTION_PRESS
            keyEvent.keycode = 0
            keyEvent.mods = GHOSTTY_MODS_NONE
            keyEvent.consumed_mods = GHOSTTY_MODS_NONE
            keyEvent.text = ptr
            keyEvent.unshifted_codepoint = 0
            keyEvent.composing = false
            _ = ghostty_surface_key(surface, keyEvent)
        }
        sendEnter()
    }

    func sendEnter() {
        guard let surface else { return }
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_PRESS
        keyEvent.keycode = UInt32(kVK_Return)
        keyEvent.mods = GHOSTTY_MODS_NONE
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.text = nil
        keyEvent.unshifted_codepoint = 0
        keyEvent.composing = false
        _ = ghostty_surface_key(surface, keyEvent)
    }

    func sendKeyEvent(_ event: NSEvent) {
        guard let surface else { return }

        let rawMods = modsFromEvent(event)
        let translatedMods = ghostty_surface_key_translation_mods(surface, rawMods)
        let translatedFlags = eventModifierFlags(from: translatedMods)

        let unshiftedCodepoint: UInt32 = {
            if let chars = event.charactersIgnoringModifiers,
               let scalar = chars.unicodeScalars.first,
               scalar.value < 0xF700 || scalar.value > 0xF8FF {
                return scalar.value
            }
            return 0
        }()

        let consumedMods = GHOSTTY_MODS_NONE

        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_PRESS
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = rawMods
        keyEvent.consumed_mods = consumedMods
        keyEvent.text = nil
        keyEvent.unshifted_codepoint = unshiftedCodepoint
        keyEvent.composing = false
        _ = ghostty_surface_key(surface, keyEvent)
    }

    private func modsFromEvent(_ event: NSEvent) -> ghostty_input_mods_e {
        return modsFromFlags(event.modifierFlags)
    }

    private func modsFromFlags(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(rawValue: mods)
    }

    private func eventModifierFlags(from mods: ghostty_input_mods_e) -> NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()
        if mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 { flags.insert(.shift) }
        if mods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 { flags.insert(.control) }
        if mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 { flags.insert(.option) }
        if mods.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0 { flags.insert(.command) }
        if mods.rawValue & GHOSTTY_MODS_CAPS.rawValue != 0 { flags.insert(.capsLock) }
        return flags
    }

    func requestClose() {
        guard let surface else { return }
        ghostty_surface_request_close(surface)
    }
}

// MARK: - NSScreen Display ID

extension NSScreen {
    var displayID: UInt32? {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return screenNumber.uint32Value
    }
}
