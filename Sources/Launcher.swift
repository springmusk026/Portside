// Opens a project folder in your editor or terminal, and toggles the panel from a global shortcut.

import AppKit
import Carbon.HIToolbox

struct ExternalApp: Identifiable, Hashable {
    let name: String
    let bundleID: String
    var id: String { bundleID }

    var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    var installed: Bool { url != nil }
}

enum Launcher {
    static let editors: [ExternalApp] = [
        ExternalApp(name: "Visual Studio Code", bundleID: "com.microsoft.VSCode"),
        ExternalApp(name: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92"),
        ExternalApp(name: "Zed", bundleID: "dev.zed.Zed"),
        ExternalApp(name: "Windsurf", bundleID: "com.exafunction.windsurf"),
        ExternalApp(name: "ZCode", bundleID: "dev.zcode.app"),
        ExternalApp(name: "Sublime Text", bundleID: "com.sublimetext.4"),
        ExternalApp(name: "Nova", bundleID: "com.panic.Nova"),
        ExternalApp(name: "IntelliJ IDEA", bundleID: "com.jetbrains.intellij"),
        ExternalApp(name: "WebStorm", bundleID: "com.jetbrains.WebStorm"),
        ExternalApp(name: "PyCharm", bundleID: "com.jetbrains.pycharm"),
        ExternalApp(name: "RubyMine", bundleID: "com.jetbrains.rubymine"),
        ExternalApp(name: "GoLand", bundleID: "com.jetbrains.goland"),
        ExternalApp(name: "Fleet", bundleID: "com.jetbrains.fleet"),
    ]

    static let terminals: [ExternalApp] = [
        ExternalApp(name: "Terminal", bundleID: "com.apple.Terminal"),
        ExternalApp(name: "iTerm", bundleID: "com.googlecode.iterm2"),
        ExternalApp(name: "Ghostty", bundleID: "com.mitchellh.ghostty"),
        ExternalApp(name: "Warp", bundleID: "dev.warp.Warp-Stable"),
    ]

    /// The editor chosen in Settings, or the first one installed.
    static var editor: ExternalApp? {
        let chosen = UserDefaults.standard.string(forKey: "editor")
        return editors.first { $0.bundleID == chosen && $0.installed } ?? editors.first(where: \.installed)
    }

    static var terminal: ExternalApp {
        let chosen = UserDefaults.standard.string(forKey: "terminal")
        return terminals.first { $0.bundleID == chosen && $0.installed } ?? terminals[0]
    }

    static func open(_ folder: String, with app: ExternalApp) {
        guard let url = app.url else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: folder)], withApplicationAt: url,
                                configuration: NSWorkspace.OpenConfiguration())
    }
}

// MARK: - Global shortcut

enum Shortcut: String, CaseIterable, Identifiable {
    case off, optionCommandP, controlOptionP, controlOptionCommandP, controlOptionSpace

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off:                   return "None"
        case .optionCommandP:        return "⌥⌘P"
        case .controlOptionP:        return "⌃⌥P"
        case .controlOptionCommandP: return "⌃⌥⌘P"
        case .controlOptionSpace:    return "⌃⌥Space"
        }
    }

    fileprivate var key: (code: Int, modifiers: Int)? {
        switch self {
        case .off:                   return nil
        case .optionCommandP:        return (kVK_ANSI_P, optionKey | cmdKey)
        case .controlOptionP:        return (kVK_ANSI_P, controlKey | optionKey)
        case .controlOptionCommandP: return (kVK_ANSI_P, controlKey | optionKey | cmdKey)
        case .controlOptionSpace:    return (kVK_Space, controlKey | optionKey)
        }
    }
}

/// A system-wide shortcut through Carbon's hot key API, which needs no accessibility permission.
@MainActor
enum Hotkey {
    private static var ref: EventHotKeyRef?
    private static var handlerInstalled = false

    static func apply(_ shortcut: Shortcut) {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        guard let key = shortcut.key else { return }
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { Hotkey.togglePanel() } }
                return noErr
            }, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x5054_5344), id: 1)   // "PTSD"
        RegisterEventHotKey(UInt32(key.code), UInt32(key.modifiers), id, GetApplicationEventTarget(), 0, &ref)
    }

    /// Clicks Portside's menu bar item, which opens or closes the panel.
    static func togglePanel() {
        for window in NSApp.windows where window.className.contains("StatusBarWindow") {
            if let button = statusButton(in: window.contentView) {
                NSApp.activate(ignoringOtherApps: true)
                button.performClick(nil)
                return
            }
        }
    }

    private static func statusButton(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton { return button }
        for sub in view.subviews { if let b = statusButton(in: sub) { return b } }
        return nil
    }
}
