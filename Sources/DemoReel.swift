import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// `Portside --demo-gif <file.gif>` renders the README animation from the real panel and
/// demo data: look up port 3000, free it, see the list without it. Frames are drawn like
/// snapshots (final states, no live animation) and crossfaded.
enum DemoReel {
    private struct Shot {
        let store: PortStore
        let preview: PanelPreview
        let hold: Double        // seconds on screen
        var fade = true         // crossfade in from the previous shot
    }

    @MainActor
    static func write(to url: URL) {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        let all = Demo.store()
        let stopping = Demo.store(stopping: ["pid:41233": .stopping(since: Date())])
        let after = PortStore(servers: Demo.servers.filter { $0.id != "pid:41233" })

        var shots = [
            Shot(store: all, preview: PanelPreview(), hold: 1.6, fade: false),
            Shot(store: all, preview: PanelPreview(caret: true), hold: 0.5),
        ]
        for typed in ["3", "30", "300"] {
            shots.append(Shot(store: all, preview: PanelPreview(query: typed, caret: true), hold: 0.14, fade: false))
        }
        shots += [
            Shot(store: all, preview: PanelPreview(query: "3000", caret: true), hold: 2.2, fade: false),
            Shot(store: stopping, preview: PanelPreview(query: "3000", caret: true), hold: 0.9),
            Shot(store: after, preview: PanelPreview(query: "3000", caret: true), hold: 1.8),
            Shot(store: after, preview: PanelPreview(), hold: 2.8),
        ]

        let images = shots.map { render($0) }
        guard let first = images.first, let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, images.count * 4, nil) else { return }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)

        func add(_ image: CGImage, _ delay: Double) {
            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay,
                                                kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
        }
        add(first, shots[0].hold)
        for i in 1..<images.count {
            if shots[i].fade {
                for step in 1...3 { add(blend(images[i - 1], images[i], Double(step) / 4), 0.04) }
            }
            add(images[i], shots[i].hold)
        }
        CGImageDestinationFinalize(destination)
    }

    /// The panel hanging under a menu bar, on a plain backdrop, at a fixed canvas size.
    @MainActor
    private static func render(_ shot: Shot) -> CGImage {
        let panel = PanelView(preview: shot.preview)
            .environmentObject(shot.store)
            .environment(\.isSnapshot, true)
            .environment(\.flatGlow, true)
            .environment(\.colorScheme, .dark)
            .background(Color(white: 0.14))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))

        let scene = VStack(spacing: 6) {
            menuBar(count: shot.store.visible.count)
            HStack {
                Spacer()
                panel.padding(.trailing, 28)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 470, height: 560, alignment: .top)
        .clipped()   // a long list runs off the bottom, like a cropped screenshot (a fade would band)
        .background(backdrop)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: scene)
        renderer.scale = 2
        var image: CGImage?
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance { image = renderer.cgImage }
        return image!
    }

    private static let backdrop = Color(white: 0.085)

    private static func menuBar(count: Int) -> some View {
        HStack(spacing: 16) {
            Spacer()
            MenuBarLabel(count: count, exposed: false).content
                .padding(.horizontal, 6)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.18)))
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Text("Thu 9:41 AM").font(.system(size: 13, weight: .medium))
        }
        .font(.system(size: 14))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(Color.black.opacity(0.35))
    }

    private static func blend(_ a: CGImage, _ b: CGImage, _ t: Double) -> CGImage {
        let ctx = CGContext(data: nil, width: a.width, height: a.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let rect = CGRect(x: 0, y: 0, width: a.width, height: a.height)
        ctx.draw(a, in: rect)
        ctx.setAlpha(t)
        ctx.draw(b, in: rect)
        return ctx.makeImage()!
    }
}
