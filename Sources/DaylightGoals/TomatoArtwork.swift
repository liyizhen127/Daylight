import AppKit

/// Original vector artwork shared by the template menu icon and the physics sprites.
@MainActor enum TomatoArtwork {
    static let menuIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 21), flipped: false) { rect in
            draw(in: rect, monochrome: true, variant: 0)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "番茄"
        return image
    }()

    static func fruit(variant: Int) -> NSImage {
        NSImage(size: NSSize(width: 128, height: 128), flipped: false) { rect in
            draw(in: rect, monochrome: false, variant: variant)
            return true
        }
    }

    static func draw(in rect: NSRect, monochrome: Bool, variant: Int) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / 100, y: rect.height / 100)
        let body = NSBezierPath()
        body.move(to: NSPoint(x: 50, y: 7))
        body.curve(to: NSPoint(x: 9, y: 43), controlPoint1: NSPoint(x: 23, y: 5), controlPoint2: NSPoint(x: 9, y: 18))
        body.curve(to: NSPoint(x: 50, y: 80), controlPoint1: NSPoint(x: 7, y: 70), controlPoint2: NSPoint(x: 28, y: 85))
        body.curve(to: NSPoint(x: 91, y: 43), controlPoint1: NSPoint(x: 73, y: 86), controlPoint2: NSPoint(x: 94, y: 70))
        body.curve(to: NSPoint(x: 50, y: 7), controlPoint1: NSPoint(x: 92, y: 17), controlPoint2: NSPoint(x: 77, y: 5))
        body.close()
        let colors = [NSColor(calibratedRed: 1, green: 0.52, blue: 0.20, alpha: 1),
                      NSColor(calibratedRed: 0.97, green: 0.43, blue: 0.18, alpha: 1),
                      NSColor(calibratedRed: 1, green: 0.58, blue: 0.24, alpha: 1)]
        (monochrome ? NSColor.black : colors[abs(variant) % colors.count]).setFill()
        body.fill()

        let leaves = NSBezierPath()
        leaves.move(to: NSPoint(x: 49, y: 78))
        leaves.curve(to: NSPoint(x: 60, y: 96), controlPoint1: NSPoint(x: 51, y: 86), controlPoint2: NSPoint(x: 55, y: 94))
        leaves.curve(to: NSPoint(x: 53, y: 80), controlPoint1: NSPoint(x: 69, y: 99), controlPoint2: NSPoint(x: 59, y: 85))
        leaves.curve(to: NSPoint(x: 76, y: 77), controlPoint1: NSPoint(x: 62, y: 81), controlPoint2: NSPoint(x: 71, y: 81))
        leaves.line(to: NSPoint(x: 62, y: 69))
        leaves.line(to: NSPoint(x: 65, y: 58))
        leaves.line(to: NSPoint(x: 50, y: 65))
        leaves.line(to: NSPoint(x: 35, y: 58))
        leaves.line(to: NSPoint(x: 39, y: 71))
        leaves.curve(to: NSPoint(x: 27, y: 78), controlPoint1: NSPoint(x: 31, y: 71), controlPoint2: NSPoint(x: 25, y: 75))
        leaves.close()
        (monochrome ? NSColor.black : NSColor(calibratedRed: 0.24, green: 0.66, blue: 0.16, alpha: 1)).setFill()
        leaves.fill()

        if monochrome {
            context.setBlendMode(.clear)
            // Keep the leaf crown readable when the entire icon uses one menu-bar color.
            let leafSeam = NSBezierPath()
            leafSeam.move(to: NSPoint(x: 27, y: 78))
            leafSeam.curve(to: NSPoint(x: 39, y: 71), controlPoint1: NSPoint(x: 25, y: 75), controlPoint2: NSPoint(x: 31, y: 71))
            for point in [NSPoint(x: 35, y: 58), NSPoint(x: 50, y: 65), NSPoint(x: 65, y: 58), NSPoint(x: 62, y: 69), NSPoint(x: 76, y: 77)] {
                leafSeam.line(to: point)
            }
            leafSeam.lineWidth = 3.6
            leafSeam.lineCapStyle = .round
            leafSeam.lineJoinStyle = .round
            NSColor.black.setStroke()
            leafSeam.stroke()
        }
        (monochrome ? NSColor.black : NSColor(calibratedRed: 0.30, green: 0.19, blue: 0.10, alpha: 1)).setFill()
        for x in [37.0, 60.0] {
            NSBezierPath(ovalIn: NSRect(x: x - 3, y: 43, width: 6, height: 8)).fill()
        }
        let smile = NSBezierPath()
        smile.move(to: NSPoint(x: 43, y: 32))
        smile.curve(to: NSPoint(x: 56, y: 32), controlPoint1: NSPoint(x: 46, y: 25), controlPoint2: NSPoint(x: 53, y: 25))
        smile.lineWidth = 3.2; smile.lineCapStyle = .round
        (monochrome ? NSColor.black : NSColor(calibratedRed: 0.30, green: 0.19, blue: 0.10, alpha: 1)).setStroke()
        smile.stroke()
        context.restoreGState()
    }
}
