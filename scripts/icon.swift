import AppKit
let output = CommandLine.arguments[1]
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let background = NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 216, yRadius: 216)
NSGradient(colors: [NSColor(calibratedRed: 0.24, green: 0.37, blue: 0.29, alpha: 1), NSColor(calibratedRed: 0.48, green: 0.59, blue: 0.44, alpha: 1)])!.draw(in: background, angle: 90)
let cream = NSColor(calibratedRed: 0.98, green: 0.93, blue: 0.78, alpha: 1)
cream.setFill()
let sun = NSBezierPath(ovalIn: NSRect(x: 328, y: 330, width: 368, height: 368)); sun.fill()
NSColor(calibratedRed: 0.31, green: 0.44, blue: 0.34, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 285, y: 300, width: 460, height: 184)).fill()
cream.setStroke()
for (y, inset) in [(474.0, 0.0), (382.0, 72.0), (290.0, 148.0)] {
    let line = NSBezierPath(); line.move(to: NSPoint(x: 235 + inset, y: y)); line.line(to: NSPoint(x: 789 - inset, y: y)); line.lineWidth = 24; line.lineCapStyle = .round; line.stroke()
}
for angle in [0.0, 45, 90, 135, 180] {
    let radians = angle * Double.pi / 180
    let ray = NSBezierPath()
    ray.move(to: NSPoint(x: 512 + cos(radians) * 244, y: 514 + sin(radians) * 244))
    ray.line(to: NSPoint(x: 512 + cos(radians) * 282, y: 514 + sin(radians) * 282))
    ray.lineWidth = 22; ray.lineCapStyle = .round; ray.stroke()
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
