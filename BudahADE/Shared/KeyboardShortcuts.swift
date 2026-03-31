import AppKit
import Carbon.HIToolbox

enum KeyboardShortcuts {
    // Panel management
    static let toggleLeftPanel = KeyShortcut(.b, modifiers: .command)
    static let toggleRightPanel = KeyShortcut(.g, modifiers: [.command, .shift])
    static let splitRight = KeyShortcut(.d, modifiers: .command)
    static let splitDown = KeyShortcut(.d, modifiers: [.command, .shift])

    // Pane navigation
    static let paneUp = KeyShortcut(.upArrow, modifiers: [.command, .option])
    static let paneDown = KeyShortcut(.downArrow, modifiers: [.command, .option])
    static let paneLeft = KeyShortcut(.leftArrow, modifiers: [.command, .option])
    static let paneRight = KeyShortcut(.rightArrow, modifiers: [.command, .option])

    // Tabs
    static let newTab = KeyShortcut(.t, modifiers: .command)
    static let closeTab = KeyShortcut(.w, modifiers: .command)
    static let nextTab = KeyShortcut(.rightBracket, modifiers: [.command, .shift])
    static let prevTab = KeyShortcut(.leftBracket, modifiers: [.command, .shift])

    // Tab switching (Cmd+1..9 handled via menu commands in BudahADEApp)

    // Workspace
    static let workspaceSwitcher = KeyShortcut(.o, modifiers: [.command, .shift])

    // Browser
    static let toggleBrowser = KeyShortcut(.b, modifiers: [.command, .shift])

    // Tasks
    static let newTask = KeyShortcut(.n, modifiers: .command)
    static let closeTask = KeyShortcut(.w, modifiers: [.command, .shift])
    // selectTaskByIndex: Ctrl+1..9 — handled via menu commands in BudahADEApp
}

struct KeyShortcut {
    let key: KeyEquivalent
    let modifiers: NSEvent.ModifierFlags

    init(_ key: KeyEquivalent, modifiers: NSEvent.ModifierFlags) {
        self.key = key
        self.modifiers = modifiers
    }
}

enum KeyEquivalent {
    case b, d, g, n, t, w, o, m
    case upArrow, downArrow, leftArrow, rightArrow
    case rightBracket, leftBracket
}
