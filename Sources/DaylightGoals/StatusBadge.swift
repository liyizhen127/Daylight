import AppKit

/// An image-backed status button keeps the time in a rounded badge in both menu bar appearances.
@MainActor enum StatusBadge {
    static let leadingWidth: CGFloat = CultivatorArtwork.size.width + 3

    static func idleImage(count: Int) -> NSImage {
        let text = "\(count)"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.labelColor]
        let width = (text as NSString).size(withAttributes: attributes).width
        return NSImage(size: NSSize(width: leadingWidth + 24 + width, height: 24), flipped: false) { _ in
            // Resolve the template tint explicitly because this image also reserves space for a color illustration.
            let tomato = TomatoArtwork.menuIcon.copy() as! NSImage
            tomato.isTemplate = false
            tomato.lockFocus()
            NSColor.labelColor.setFill()
            NSRect(origin: .zero, size: tomato.size).fill(using: .sourceIn)
            tomato.unlockFocus()
            tomato.draw(in: NSRect(x: leadingWidth, y: 1.5, width: 20, height: 21))
            (text as NSString).draw(at: NSPoint(x: leadingWidth + 24, y: 3.5), withAttributes: attributes)
            return true
        }
    }

    static func image(name: String, time: String) -> NSImage {
        let nameFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        let nameAttributes: [NSAttributedString.Key: Any] = [.font: nameFont, .foregroundColor: NSColor.labelColor]
        let timeAttributes: [NSAttributedString.Key: Any] = [.font: timeFont, .foregroundColor: NSColor.white]
        let shortName = name.count > 16 ? String(name.prefix(15)) + "…" : name
        let nameWidth = (shortName as NSString).size(withAttributes: nameAttributes).width
        let timeWidth = max(43, (time as NSString).size(withAttributes: timeAttributes).width + 14)
        let size = NSSize(width: leadingWidth + nameWidth + timeWidth + 23, height: 24)
        return NSImage(size: size, flipped: false) { bounds in
            NSColor.labelColor.withAlphaComponent(0.09).setFill()
            NSBezierPath(roundedRect: NSRect(x: leadingWidth + 1, y: 1, width: bounds.width - leadingWidth - 2, height: 22), xRadius: 11, yRadius: 11).fill()
            (shortName as NSString).draw(at: NSPoint(x: leadingWidth + 9, y: 5), withAttributes: nameAttributes)
            let badge = NSRect(x: leadingWidth + nameWidth + 15, y: 2, width: timeWidth, height: 20)
            NSColor(calibratedWhite: 0.18, alpha: 1).setFill()
            NSBezierPath(roundedRect: badge, xRadius: 10, yRadius: 10).fill()
            (time as NSString).draw(at: NSPoint(x: badge.midX - (time as NSString).size(withAttributes: timeAttributes).width / 2, y: 5), withAttributes: timeAttributes)
            return true
        }
    }
}
