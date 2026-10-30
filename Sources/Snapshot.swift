import SwiftUI

/// `Portside --snapshot <folder>` renders the panel in each state, in light and dark,
/// plus the menu bar icon states and Settings, to PNG files, then exits. Uses made-up
/// data (Demo) so screenshots are reproducible and private. Used to review the design.
enum PanelSnapshot {
    @MainActor
    static func write(to dir: URL) {
        let app = NSApplication.shared
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let states: [(String, PortStore, PanelPreview)] = [
            ("panel", Demo.store(), PanelPreview()),
            ("hover", Demo.store(), PanelPreview(hovered: "pid:41233")),
            ("apps", Demo.store(), PanelPreview(showApps: true)),
            ("lookup-held", Demo.store(), PanelPreview(query: "3000")),
            ("lookup-free", Demo.store(), PanelPreview(query: "3001")),
            ("lookup-hidden", Demo.store(), PanelPreview(query: "631")),
            ("filter", Demo.store(), PanelPreview(query: "acme")),
            ("stopping", Demo.store(stopping: ["pid:41233": .stopping(since: Date()), "pid:52011": .stuck]),
             PanelPreview(confirmStopAll: true)),
            ("empty", PortStore(servers: []), PanelPreview()),
            ("selected", Demo.store(), PanelPreview(selected: "pid:41301")),
            ("projects", Demo.store(pinned: ["dev|blog"]), PanelPreview(byProject: true)),
        ]

        for (scheme, name) in [(ColorScheme.light, "light"), (.dark, "dark")] {
            let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!
            app.appearance = appearance
            for (state, store, preview) in states {
                let view = PanelView(preview: preview)
                    .environmentObject(store)
                    .environment(\.colorScheme, scheme)
                    .environment(\.isSnapshot, true)
                    .background(scheme == .dark ? Color(white: 0.13) : Color(white: 0.955))
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                appearance.performAsCurrentDrawingAppearance {
                    save(renderer, to: dir.appendingPathComponent("\(state)-\(name).png"))
                }
            }
            capture(SettingsView().environmentObject(Demo.store()).tint(.harbor),
                    appearance: appearance, to: dir.appendingPathComponent("settings-\(name).png"))
        }
        let renderer = ImageRenderer(content: menuBarStates)
        renderer.scale = 3
        save(renderer, to: dir.appendingPathComponent("menubar.png"))
    }

    @MainActor
    private static func save<V: View>(_ renderer: ImageRenderer<V>, to url: URL) {
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }

    /// Standard controls don't draw in ImageRenderer, so capture from an offscreen window.
    @MainActor
    private static func capture<V: View>(_ view: V, appearance: NSAppearance, to url: URL) {
        let host = NSHostingView(rootView: view)
        host.appearance = appearance
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static var menuBarStates: some View {
        let states: [(String, Int, Bool, Bool)] = [
            ("3 running", 3, false, true),
                        ("Nothing running", 0, false, true),
            ("Count hidden", 3, false, false),
        ]
        return HStack(spacing: 0) {
            ForEach([true, false], id: \.self) { dark in
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(states.indices, id: \.self) { i in
                        HStack(spacing: 14) {
                            MenuBarLabel(count: states[i].1, exposed: states[i].2, showCount: states[i].3).content
                            Image(systemName: "wifi")
                            Image(systemName: "battery.75percent")
                            Text("Thu 9:30 PM").font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text(states[i].0).font(.system(size: 10)).opacity(0.6)
                        }
                        .font(.system(size: 14))
                        .foregroundStyle(dark ? .white : .black)
                        .padding(.horizontal, 10)
                        .frame(width: 380, height: 24)
                        .background(dark ? Color(white: 0.16) : Color(white: 0.93))
                    }
                }
                .padding(10)
                .background(dark ? Color(white: 0.08) : Color.white)
            }
        }
    }
}
