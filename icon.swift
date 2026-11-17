// Renders the app icon: swift icon.swift AppIcon.png  (make icon turns it into AppIcon.icns)
// Plain bezier shapes only: SF Symbols may not be used in app icons.
import Cocoa

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let top = NSColor(red: 1.0, green: 0.72, blue: 0.30, alpha: 1)
let bottom = NSColor(red: 0.93, green: 0.40, blue: 0.20, alpha: 1)

// macOS icon grid: 824pt rounded square centred in 1024.
let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGradient(starting: top, ending: bottom)!.draw(in: tile, angle: -90)

// Keyboard with a grid of keys.
NSColor.white.withAlphaComponent(0.9).setFill()
NSBezierPath(roundedRect: NSRect(x: 210, y: 190, width: 604, height: 170), xRadius: 34, yRadius: 34).fill()
bottom.withAlphaComponent(0.45).setFill()
for row in 0..<3 {
    for col in 0..<10 {
        NSBezierPath(roundedRect: NSRect(x: 240 + col * 55, y: 215 + row * 45, width: 46, height: 34), xRadius: 8, yRadius: 8).fill()
    }
}

// Sitting cat, seen from the front, on the keyboard.
NSColor.white.setFill()
NSColor.white.setStroke()
let tail = NSBezierPath()
tail.move(to: NSPoint(x: 640, y: 380))
tail.curve(to: NSPoint(x: 760, y: 600), controlPoint1: NSPoint(x: 800, y: 380), controlPoint2: NSPoint(x: 820, y: 520))
tail.lineWidth = 52
tail.lineCapStyle = .round
tail.stroke()

let body = NSBezierPath()
body.move(to: NSPoint(x: 372, y: 345))
body.curve(to: NSPoint(x: 445, y: 640), controlPoint1: NSPoint(x: 350, y: 470), controlPoint2: NSPoint(x: 395, y: 580))
body.line(to: NSPoint(x: 579, y: 640))
body.curve(to: NSPoint(x: 652, y: 345), controlPoint1: NSPoint(x: 629, y: 580), controlPoint2: NSPoint(x: 674, y: 470))
body.close()
body.fill()

NSBezierPath(ovalIn: NSRect(x: 377, y: 565, width: 270, height: 240)).fill()
for s: CGFloat in [-1, 1] { // ears
    let ear = NSBezierPath()
    ear.move(to: NSPoint(x: 512 + s * 135, y: 700))
    ear.line(to: NSPoint(x: 512 + s * 125, y: 875))
    ear.line(to: NSPoint(x: 512 + s * 30, y: 790))
    ear.close()
    ear.fill()
}

bottom.setFill()
for s: CGFloat in [-1, 1] { // eyes
    NSBezierPath(ovalIn: NSRect(x: 512 + s * 55 - 18, y: 665, width: 36, height: 50)).fill()
}
let nose = NSBezierPath()
nose.move(to: NSPoint(x: 496, y: 645)); nose.line(to: NSPoint(x: 528, y: 645)); nose.line(to: NSPoint(x: 512, y: 627)); nose.close()
nose.fill()

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
