import AppKit
import Foundation
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(calibratedRed: 0.15, green: 0.17, blue: 0.13, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 210, yRadius: 210).fill()
        let lime = NSColor(calibratedRed: 0.85, green: 0.93, blue: 0.62, alpha: 1)
        lime.setStroke()
        let dial = NSBezierPath(ovalIn: NSRect(x: 225, y: 190, width: 574, height: 574)); dial.lineWidth = 42; dial.stroke()
        let hands = NSBezierPath(); hands.lineWidth = 42; hands.lineCapStyle = .round
        hands.move(to: NSPoint(x: 512, y: 684)); hands.line(to: NSPoint(x: 512, y: 477)); hands.line(to: NSPoint(x: 662, y: 392))
        hands.move(to: NSPoint(x: 432, y: 842)); hands.line(to: NSPoint(x: 592, y: 842))
        hands.move(to: NSPoint(x: 512, y: 842)); hands.line(to: NSPoint(x: 512, y: 770)); hands.stroke()
        let wave = NSBezierPath(); wave.lineWidth = 28; wave.lineJoinStyle = .round; wave.lineCapStyle = .round
        wave.move(to: NSPoint(x: 220, y: 477)); wave.line(to: NSPoint(x: 325, y: 477)); wave.line(to: NSPoint(x: 365, y: 567)); wave.line(to: NSPoint(x: 435, y: 357)); wave.line(to: NSPoint(x: 490, y: 477)); wave.stroke()
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let filename = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(filename))
    }
}
