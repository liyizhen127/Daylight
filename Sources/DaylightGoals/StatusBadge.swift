import AppKit

/// An image-backed status button keeps the time in a rounded badge in both menu bar appearances.
@MainActor enum StatusBadge {
    static func image(name: String, time: String) -> NSImage {
        let nameFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        let nameAttributes: [NSAttributedString.Key: Any] = [.font: nameFont, .foregroundColor: NSColor.labelColor]
        let timeAttributes: [NSAttributedString.Key: Any] = [.font: timeFont, .foregroundColor: NSColor.white]
        let shortName = name.count > 16 ? String(name.prefix(15)) + "…" : name
        let nameWidth = (shortName as NSString).size(withAttributes: nameAttributes).width
        let timeWidth = max(43, (time as NSString).size(withAttributes: timeAttributes).width + 14)
        let size = NSSize(width: nameWidth + timeWidth + 23, height: 24)
        return NSImage(size: size, flipped: false) { bounds in
            NSColor.labelColor.withAlphaComponent(0.09).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 11, yRadius: 11).fill()
            (shortName as NSString).draw(at: NSPoint(x: 9, y: 5), withAttributes: nameAttributes)
            let badge = NSRect(x: nameWidth + 15, y: 2, width: timeWidth, height: 20)
            NSColor(calibratedWhite: 0.18, alpha: 1).setFill()
            NSBezierPath(roundedRect: badge, xRadius: 10, yRadius: 10).fill()
            (time as NSString).draw(at: NSPoint(x: badge.midX - (time as NSString).size(withAttributes: timeAttributes).width / 2, y: 5), withAttributes: timeAttributes)
            return true
        }
    }
}
