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

/// The status item, drawn as one template image so it follows the menu bar's colors.
struct MenuBarLabel: View {
    let count: Int
    let exposed: Bool
    var showCount = true

    var body: some View {
        Image(nsImage: rendered)
    }

    var content: some View {
        HStack(spacing: 4) {
            MenuGlyph(active: count > 0).frame(width: 16, height: 16)
            if showCount && count > 0 {
                Text("\(count)").font(.system(size: 13, weight: .medium).monospacedDigit())
            }
        }
        .padding(.vertical, 1)
    }

    private var rendered: NSImage {
        let renderer = ImageRenderer(content: content.foregroundStyle(.black))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        image.accessibilityDescription = count == 0 ? "Portside, nothing running"
            : "Portside, \(count) running" + (exposed ? ", some open to your network" : "")
        return image
    }
}

/// An Ethernet-style port: a socket outline with the jack's silhouette inside,
/// filled while something is listening, outlined when nothing is.
struct MenuGlyph: View {
    let active: Bool

    var body: some View {
        Canvas { ctx, size in
            let u = size.width / 16
            let socket = Path(roundedRect: CGRect(x: 1.5 * u, y: 1.5 * u, width: 13 * u, height: 13 * u), cornerRadius: 3.2 * u)
            ctx.stroke(socket, with: .foreground, lineWidth: 1.5 * u)
            var jack = Path()
            jack.addLines([(4.6, 4.8), (11.4, 4.8), (11.4, 9.4), (9.6, 9.4), (9.6, 11.4), (6.4, 11.4), (6.4, 9.4), (4.6, 9.4)]
                .map { CGPoint(x: $0.0 * u, y: $0.1 * u) })
            jack.closeSubpath()
            if active {
                ctx.fill(jack, with: .foreground)
            } else {
                ctx.opacity = 0.5
                ctx.stroke(jack, with: .foreground, style: StrokeStyle(lineWidth: 1 * u, lineJoin: .round))
            }
        }
    }
}
