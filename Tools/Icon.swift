import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func render(_ pixels: Int) -> Data {
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let outer = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 205, yRadius: 205)
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.16); shadow.shadowBlurRadius = 35; shadow.shadowOffset = NSSize(width: 0, height: -12)
    NSGraphicsContext.saveGraphicsState(); shadow.set()
    NSGradient(starting: NSColor(calibratedRed: 0.43, green: 0.63, blue: 0.92, alpha: 1), ending: NSColor(calibratedRed: 0.23, green: 0.40, blue: 0.72, alpha: 1))!.draw(in: outer, angle: -75)
    NSGraphicsContext.restoreGraphicsState()
    let folder = NSBezierPath()
    folder.move(to: NSPoint(x: 230, y: 653))
    folder.curve(to: NSPoint(x: 259, y: 682), controlPoint1: NSPoint(x: 230, y: 674), controlPoint2: NSPoint(x: 239, y: 682))
    folder.line(to: NSPoint(x: 419, y: 682))
    folder.curve(to: NSPoint(x: 448, y: 668), controlPoint1: NSPoint(x: 433, y: 682), controlPoint2: NSPoint(x: 441, y: 676))
    folder.line(to: NSPoint(x: 482, y: 633))
    folder.line(to: NSPoint(x: 766, y: 633))
    folder.curve(to: NSPoint(x: 795, y: 604), controlPoint1: NSPoint(x: 786, y: 633), controlPoint2: NSPoint(x: 795, y: 624))
    folder.line(to: NSPoint(x: 795, y: 347))
    folder.curve(to: NSPoint(x: 766, y: 318), controlPoint1: NSPoint(x: 795, y: 327), controlPoint2: NSPoint(x: 786, y: 318))
    folder.line(to: NSPoint(x: 259, y: 318))
    folder.curve(to: NSPoint(x: 230, y: 347), controlPoint1: NSPoint(x: 239, y: 318), controlPoint2: NSPoint(x: 230, y: 327))
    folder.close()
    NSColor.white.withAlphaComponent(0.97).setFill(); folder.fill()
    NSColor(calibratedRed: 0.32, green: 0.50, blue: 0.80, alpha: 1).setFill()
    for i in 0..<3 { NSBezierPath(roundedRect: NSRect(x: 351 + i * 115, y: 407, width: 91, height: 91), xRadius: 15, yRadius: 15).fill() }
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}
for (points, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let filename = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try render(points * scale).write(to: output.appendingPathComponent(filename))
}
