// Renders the 1024px app icon PNG: a graphite squircle with a white port (the menu bar glyph).
// Usage: swift tools/make-icon.swift <output.png>

import AppKit

let size = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824px body centred on a 1024px canvas
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(calibratedWhite: 0.10, alpha: 1),
           ending: NSColor(calibratedWhite: 0.27, alpha: 1))!.draw(in: shape, angle: 90)
NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
shape.lineWidth = 4
shape.stroke()

// A soft harbor-blue light behind the port: something is listening
NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSGradient(colors: [NSColor(srgbRed: 0.38, green: 0.76, blue: 0.90, alpha: 0.28), .clear])!
    .draw(fromCenter: NSPoint(x: 512, y: 470), radius: 0, toCenter: NSPoint(x: 512, y: 470), radius: 420, options: [])
NSGraphicsContext.restoreGraphicsState()

// The port: the menu bar glyph at icon size (16pt grid scaled to a 520px square, y flipped)
let u: CGFloat = 520 / 16, ox: CGFloat = 252, oy: CGFloat = 252
func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: ox + x * u, y: oy + (16 - y) * u) }
let socket = NSBezierPath(roundedRect: NSRect(x: ox + 1.5 * u, y: oy + 1.5 * u, width: 13 * u, height: 13 * u),
                          xRadius: 3.2 * u, yRadius: 3.2 * u)
NSColor.white.setStroke()
socket.lineWidth = 1.5 * u
socket.stroke()
let jack = NSBezierPath()
jack.move(to: p(4.6, 4.8))
for (x, y) in [(11.4, 4.8), (11.4, 9.4), (9.6, 9.4), (9.6, 11.4), (6.4, 11.4), (6.4, 9.4), (4.6, 9.4)] { jack.line(to: p(x, y)) }
jack.close()
NSColor.white.setFill()
jack.fill()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
