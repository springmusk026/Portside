// Portside: a menu bar app that shows what's listening on your ports (dev servers,
// databases, containers), which project each belongs to, and lets you stop it.
// Reads process and socket information from the kernel; no network calls, no admin rights.

import SwiftUI

@main
struct PortsideApp: App {
    @StateObject private var store = PortStore()
    @AppStorage("countInMenuBar") private var countInMenuBar = true

    init() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            PanelSnapshot.write(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        if let i = args.firstIndex(of: "--demo-gif"), i + 1 < args.count {
            DemoReel.write(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        if CLI.wants(args) { exit(CLI.run(args)) }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                Hotkey.apply(Shortcut(rawValue: UserDefaults.standard.string(forKey: "shortcut") ?? "") ?? .off)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView().environmentObject(store)
        } label: {
            MenuBarLabel(count: store.visible.count, exposed: store.visible.contains(where: \.exposed),
                         showCount: countInMenuBar)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environmentObject(store).tint(.harbor)
        }
    }
}
