import Foundation
import AppKit

/// Singleton managing the Ghostty runtime lifecycle.
/// Initializes libghostty, creates the app instance, and runs the tick loop.
final class GhosttyAppManager {
    static let shared = GhosttyAppManager()

    private(set) var app: ghostty_app_t?
    private(set) var config: ghostty_config_t?
    private var displayLink: CVDisplayLink?
    private var appObservers: [NSObjectProtocol] = []

    private init() {}

    func initialize() {
        // Initialize Ghostty library
        let result = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        guard result == GHOSTTY_SUCCESS else {
            print("[BudahADE] Failed to initialize ghostty: \(result)")
            return
        }

        // Create and load config
        guard let primaryConfig = ghostty_config_new() else {
            print("[BudahADE] Failed to create ghostty config")
            return
        }

        // Write BudahADE config override — ensures macos-option-as-alt wins
        let overridePath = ("~/.config/ghostty/budahade.conf" as NSString).expandingTildeInPath
        try? "macos-option-as-alt = true\n".write(toFile: overridePath, atomically: true, encoding: .utf8)

        ghostty_config_load_default_files(primaryConfig)
        ghostty_config_load_recursive_files(primaryConfig)
        // Load our override last so it takes precedence over user config
        overridePath.withCString { ghostty_config_load_file(primaryConfig, $0) }
        ghostty_config_finalize(primaryConfig)

        // Set up runtime callbacks
        var runtimeConfig = ghostty_runtime_config_s()
        runtimeConfig.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtimeConfig.supports_selection_clipboard = true

        runtimeConfig.wakeup_cb = { _ in
            DispatchQueue.main.async {
                GhosttyAppManager.shared.tick()
            }
        }

        runtimeConfig.action_cb = { app, target, action in
            return GhosttyAppManager.shared.handleAction(target: target, action: action)
        }

        runtimeConfig.read_clipboard_cb = { userdata, location, state in
            guard let userdata else { return }
            let context = Unmanaged<TerminalSurfaceCallbackContext>.fromOpaque(userdata).takeUnretainedValue()
            guard let surface = context.surface else { return }

            let pasteboard: NSPasteboard? = location == GHOSTTY_CLIPBOARD_STANDARD ? .general : nil
            let value = pasteboard?.string(forType: .string) ?? ""

            value.withCString { ptr in
                ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
            }
        }

        runtimeConfig.confirm_read_clipboard_cb = { userdata, content, state, _ in
            guard let content, let userdata else { return }
            let context = Unmanaged<TerminalSurfaceCallbackContext>.fromOpaque(userdata).takeUnretainedValue()
            guard let surface = context.surface else { return }
            ghostty_surface_complete_clipboard_request(surface, content, state, true)
        }

        runtimeConfig.write_clipboard_cb = { _, location, content, len, _ in
            guard let content, len > 0 else { return }
            let buffer = UnsafeBufferPointer(start: content, count: Int(len))
            for item in buffer {
                guard let dataPtr = item.data else { continue }
                let value = String(cString: dataPtr)
                if location == GHOSTTY_CLIPBOARD_STANDARD {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                }
                return
            }
        }

        runtimeConfig.close_surface_cb = { userdata, _ in
            guard let userdata else { return }
            let context = Unmanaged<TerminalSurfaceCallbackContext>.fromOpaque(userdata).takeUnretainedValue()
            let surfaceId = context.surfaceId
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .terminalSurfaceClosed,
                    object: nil,
                    userInfo: ["surfaceId": surfaceId]
                )
            }
        }

        // Create app
        if let created = ghostty_app_new(&runtimeConfig, primaryConfig) {
            self.app = created
            self.config = primaryConfig
        } else {
            print("[BudahADE] ghostty_app_new failed, trying fallback config")
            ghostty_config_free(primaryConfig)

            guard let fallbackConfig = ghostty_config_new() else {
                print("[BudahADE] Failed to create fallback config")
                return
            }
            ghostty_config_finalize(fallbackConfig)

            guard let created = ghostty_app_new(&runtimeConfig, fallbackConfig) else {
                print("[BudahADE] ghostty_app_new(fallback) failed")
                ghostty_config_free(fallbackConfig)
                return
            }
            self.app = created
            self.config = fallbackConfig
        }

        // Track app focus state
        appObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let app = self?.app else { return }
            ghostty_app_set_focus(app, true)
        })

        appObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let app = self?.app else { return }
            ghostty_app_set_focus(app, false)
        })

        // Set initial focus
        if let app {
            ghostty_app_set_focus(app, NSApp.isActive)
        }
    }

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    func shutdown() {
        for observer in appObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        appObservers.removeAll()

        if let app {
            ghostty_app_free(app)
            self.app = nil
        }
        if let config {
            ghostty_config_free(config)
            self.config = nil
        }
    }

    private func handleAction(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            if let titlePtr = action.action.set_title.title {
                let title = String(cString: titlePtr)
                if target.tag == GHOSTTY_TARGET_SURFACE, let surfacePtr = target.target.surface {
                    let userdata = ghostty_surface_userdata(surfacePtr)
                    if let userdata {
                        let context = Unmanaged<TerminalSurfaceCallbackContext>.fromOpaque(userdata).takeUnretainedValue()
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: .terminalTitleChanged,
                                object: nil,
                                userInfo: ["surfaceId": context.surfaceId, "title": title]
                            )
                        }
                    }
                }
            }
            return true

        case GHOSTTY_ACTION_PWD:
            if let pwdPtr = action.action.pwd.pwd {
                let pwd = String(cString: pwdPtr)
                if target.tag == GHOSTTY_TARGET_SURFACE, let surfacePtr = target.target.surface {
                    let userdata = ghostty_surface_userdata(surfacePtr)
                    if let userdata {
                        let context = Unmanaged<TerminalSurfaceCallbackContext>.fromOpaque(userdata).takeUnretainedValue()
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: .terminalPwdChanged,
                                object: nil,
                                userInfo: ["surfaceId": context.surfaceId, "pwd": pwd]
                            )
                        }
                    }
                }
            }
            return true

        case GHOSTTY_ACTION_RENDER:
            return true

        case GHOSTTY_ACTION_MOUSE_SHAPE:
            let shape = action.action.mouse_shape
            DispatchQueue.main.async {
                switch shape {
                case GHOSTTY_MOUSE_SHAPE_TEXT:
                    NSCursor.iBeam.set()
                case GHOSTTY_MOUSE_SHAPE_POINTER:
                    NSCursor.pointingHand.set()
                default:
                    NSCursor.arrow.set()
                }
            }
            return true

        case GHOSTTY_ACTION_OPEN_URL:
            if let urlPtr = action.action.open_url.url {
                let urlStr = String(cString: urlPtr)
                if let url = URL(string: urlStr) {
                    DispatchQueue.main.async {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            return true

        case GHOSTTY_ACTION_RING_BELL:
            DispatchQueue.main.async { NSSound.beep() }
            return true

        default:
            return false
        }
    }
}

// MARK: - Callback Context

final class TerminalSurfaceCallbackContext {
    weak var surfaceView: TerminalSurfaceView?
    let surfaceId: UUID
    var surface: ghostty_surface_t? { surfaceView?.terminalSurface?.surface }

    init(surfaceView: TerminalSurfaceView, surfaceId: UUID) {
        self.surfaceView = surfaceView
        self.surfaceId = surfaceId
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let terminalSurfaceClosed = Notification.Name("budahADE.terminalSurfaceClosed")
    static let terminalTitleChanged = Notification.Name("budahADE.terminalTitleChanged")
    static let terminalPwdChanged = Notification.Name("budahADE.terminalPwdChanged")
}
