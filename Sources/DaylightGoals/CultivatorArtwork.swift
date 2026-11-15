import AppKit

/// Original vector artwork, sized for the menu bar rather than a scaled-down illustration.
@MainActor enum CultivatorArtwork {
    static let size = NSSize(width: 44, height: 24)

    static func draw(in rect: NSRect, focusing: Bool, time: TimeInterval, dark: Bool) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.translateBy(x: rect.minX, y: rect.minY)
        ctx.scaleBy(x: rect.width / size.width, y: rect.height / size.height)
        ctx.translateBy(x: 5, y: 0)
        let gold = dark ? NSColor(calibratedRed: 1, green: 0.79, blue: 0.34, alpha: 1)
                        : NSColor(calibratedRed: 0.65, green: 0.39, blue: 0.07, alpha: 1)
        let ink = dark ? NSColor(calibratedRed: 0.35, green: 0.23, blue: 0.12, alpha: 1)
                       : NSColor(calibratedRed: 0.31, green: 0.22, blue: 0.12, alpha: 1)
        let robe = dark ? NSColor(calibratedRed: 1, green: 0.91, blue: 0.66, alpha: 1)
                       : NSColor(calibratedRed: 1, green: 0.95, blue: 0.81, alpha: 1)
        let breath = focusing ? sin(time * .pi * 2 / 1.6) : 0

        if focusing {
            let surge = (breath + 1) / 2
            let flame = NSBezierPath()
            let points: [NSPoint] = [
                .init(x: 10, y: 2), .init(x: 5, y: 5), .init(x: 7, y: 8),
                .init(x: 2.5 - surge, y: 12 + surge), .init(x: 8, y: 11),
                .init(x: 6 - surge, y: 19 + surge), .init(x: 11, y: 15),
                .init(x: 12, y: 22 + surge), .init(x: 15, y: 19),
                .init(x: 17, y: 23.5), .init(x: 19, y: 19),
                .init(x: 23, y: 22 + surge), .init(x: 23, y: 15),
                .init(x: 29 + surge, y: 19 + surge), .init(x: 26, y: 11),
                .init(x: 31.5 + surge, y: 13 + surge), .init(x: 27, y: 7),
                .init(x: 30, y: 5), .init(x: 24, y: 2)
            ]
            flame.move(to: points[0]); for point in points.dropFirst() { flame.line(to: point) }; flame.close()
            NSGradient(starting: NSColor(calibratedRed: 1, green: 0.50, blue: 0.04, alpha: 0.58 + surge * 0.17),
                       ending: NSColor(calibratedRed: 1, green: 0.85, blue: 0.28, alpha: 0.20 + surge * 0.25))?.draw(in: flame, angle: 90)
            gold.withAlphaComponent(0.65).setStroke(); flame.lineWidth = 0.65; flame.stroke()
            // A slow expanding pressure wave makes the surge readable without a strobe.
            let wave = (time / 1.6).truncatingRemainder(dividingBy: 1)
            let radius = 6 + 14 * wave
            let shock = NSBezierPath(ovalIn: NSRect(x: 17 - radius, y: 10 - radius * 0.45, width: radius * 2, height: radius * 0.9))
            gold.withAlphaComponent((1 - wave) * 0.8).setStroke(); shock.lineWidth = 1.3; shock.stroke()
        }

        // A quiet halo remains visible when resting; light circulates only while focusing.
        let halo = NSRect(x: 6.7, y: 1.7, width: 20.6, height: 20.6)
        gold.withAlphaComponent(focusing ? 0.13 + 0.035 * breath : 0.07).setFill()
        NSBezierPath(ovalIn: halo).fill()
        gold.withAlphaComponent(focusing ? 0.65 : 0.27).setStroke()
        let ring = NSBezierPath(ovalIn: halo); ring.lineWidth = 0.65; ring.stroke()
        if focusing {
            for offset in [0.0, 180.0] {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: NSPoint(x: 17, y: 12), radius: 10.3,
                              startAngle: CGFloat(time * 90 + offset), endAngle: CGFloat(time * 90 + offset + 65))
                arc.lineWidth = 1.25; arc.lineCapStyle = .round
                gold.withAlphaComponent(0.9).setStroke(); arc.stroke()
            }
        }

        // Lotus cushion, crossed legs, draped sleeves and a topknot silhouette.
        gold.withAlphaComponent(0.26).setFill()
        NSBezierPath(ovalIn: NSRect(x: 8, y: 1.3, width: 18, height: 2.5)).fill()
        ctx.saveGState()
        ctx.translateBy(x: 0, y: breath * 0.18)
        let body = NSBezierPath()
        body.move(to: NSPoint(x: 14.2, y: 14.6))
        body.curve(to: NSPoint(x: 10.5, y: 11), controlPoint1: NSPoint(x: 12.6, y: 14.1), controlPoint2: NSPoint(x: 12.1, y: 11.9))
        body.line(to: NSPoint(x: 6.9, y: 8.9))
        body.curve(to: NSPoint(x: 10.5, y: 7), controlPoint1: NSPoint(x: 6.9, y: 7.3), controlPoint2: NSPoint(x: 8.7, y: 6.8))
        body.line(to: NSPoint(x: 13.2, y: 9.3))
        body.line(to: NSPoint(x: 13, y: 6.7))
        body.curve(to: NSPoint(x: 8, y: 4.8), controlPoint1: NSPoint(x: 8.8, y: 7.5), controlPoint2: NSPoint(x: 7.5, y: 6))
        body.curve(to: NSPoint(x: 17, y: 2.8), controlPoint1: NSPoint(x: 8.6, y: 2.6), controlPoint2: NSPoint(x: 14.5, y: 3))
        body.curve(to: NSPoint(x: 26, y: 4.8), controlPoint1: NSPoint(x: 19.5, y: 3), controlPoint2: NSPoint(x: 25.4, y: 2.6))
        body.curve(to: NSPoint(x: 21, y: 6.7), controlPoint1: NSPoint(x: 26.5, y: 6), controlPoint2: NSPoint(x: 25.2, y: 7.5))
        body.line(to: NSPoint(x: 20.8, y: 9.3))
        body.line(to: NSPoint(x: 23.5, y: 7))
        body.curve(to: NSPoint(x: 27.1, y: 8.9), controlPoint1: NSPoint(x: 25.3, y: 6.8), controlPoint2: NSPoint(x: 27.1, y: 7.3))
        body.line(to: NSPoint(x: 23.5, y: 11))
        body.curve(to: NSPoint(x: 19.8, y: 14.6), controlPoint1: NSPoint(x: 21.9, y: 11.9), controlPoint2: NSPoint(x: 21.4, y: 14.1))
        body.close()
        robe.setFill(); body.fill()
        gold.setStroke(); body.lineWidth = 0.7; body.lineJoinStyle = .round; body.stroke()
        let folds = NSBezierPath()
        folds.move(to: NSPoint(x: 14.5, y: 14)); folds.line(to: NSPoint(x: 18.9, y: 8.4))
        folds.move(to: NSPoint(x: 19.5, y: 14)); folds.line(to: NSPoint(x: 15, y: 8.2))
        folds.move(to: NSPoint(x: 11.5, y: 5.7)); folds.line(to: NSPoint(x: 21, y: 3.6))
        folds.move(to: NSPoint(x: 22.5, y: 5.7)); folds.line(to: NSPoint(x: 17, y: 4.4))
        folds.lineWidth = 0.6; folds.lineCapStyle = .round
        gold.withAlphaComponent(0.75).setStroke(); folds.stroke()

        ink.setFill()
        NSBezierPath(ovalIn: NSRect(x: 14.1, y: 15, width: 5.8, height: 5.8)).fill()
        NSBezierPath(ovalIn: NSRect(x: 15.5, y: 20.1, width: 3, height: 2.5)).fill()
        NSColor(calibratedRed: 0.98, green: 0.78, blue: 0.50, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 14.8, y: 14.5, width: 4.4, height: 4.9)).fill()
        for x in [7.0, 25.2] {
            NSBezierPath(ovalIn: NSRect(x: x, y: 8.7, width: 1.8, height: 1.1)).fill()
        }
        let eyes = NSBezierPath()
        eyes.move(to: NSPoint(x: 15.6, y: 17)); eyes.line(to: NSPoint(x: 16.4, y: 16.85))
        eyes.move(to: NSPoint(x: 17.6, y: 16.85)); eyes.line(to: NSPoint(x: 18.4, y: 17))
        eyes.lineWidth = 0.45; eyes.lineCapStyle = .round; ink.setStroke(); eyes.stroke()
        gold.setFill(); NSBezierPath(ovalIn: NSRect(x: 15.4, y: 20.3, width: 3.2, height: 0.6)).fill()
        ctx.restoreGState()

        if focusing {
            // Long, bright streaks converge from outside the aura into the lower torso.
            for i in 0..<12 {
                let progress = (time / 1.15 + Double(i) / 12).truncatingRemainder(dividingBy: 1)
                func point(_ p: Double) -> NSPoint {
                    let angle = Double(i) * .pi / 6 + p * 0.55
                    let radius = 21 * (1 - p) + 0.25
                    return NSPoint(x: 17 + cos(angle) * radius, y: 10.2 + sin(angle) * radius * 0.47)
                }
                let alpha = min(1, progress * 5) * min(1, (1 - progress) * 6)
                let trail = NSBezierPath()
                trail.move(to: point(max(0, progress - 0.28)))
                trail.curve(to: point(progress), controlPoint1: point(max(0, progress - 0.18)), controlPoint2: point(max(0, progress - 0.08)))
                trail.lineCapStyle = .round
                gold.withAlphaComponent(alpha * 0.22).setStroke(); trail.lineWidth = 3.4; trail.stroke()
                gold.withAlphaComponent(alpha).setStroke(); trail.lineWidth = 1.35; trail.stroke()
                let center = point(progress)
                (dark ? NSColor(calibratedRed: 1, green: 0.97, blue: 0.78, alpha: alpha) : NSColor(calibratedRed: 0.91, green: 0.43, blue: 0.03, alpha: alpha)).setFill()
                NSBezierPath(ovalIn: NSRect(x: center.x - 0.85, y: center.y - 0.85, width: 1.7, height: 1.7)).fill()
            }
            gold.withAlphaComponent(0.7).setFill()
            NSBezierPath(ovalIn: NSRect(x: 15.3, y: 8.5, width: 3.4, height: 3.4)).fill()
            NSColor(calibratedRed: 1, green: 0.97, blue: 0.78, alpha: 0.9).setFill()
            NSBezierPath(ovalIn: NSRect(x: 16.2, y: 9.4, width: 1.6, height: 1.6)).fill()
        }
    }
}

/// Only this small, click-through overlay animates. Timer/model updates stay at one second.
@MainActor final class CultivatorStatusView: NSView {
    private(set) var isFocusing = false
    private(set) var animationTimer: Timer?
    private(set) var animationTime: TimeInterval = 0
    private var animationStart: TimeInterval = 0
    private var sleeping = false
    private var observers: [NSObjectProtocol] = []
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if notification.name == NSWorkspace.willSleepNotification { self.sleeping = true }
                    if notification.name == NSWorkspace.didWakeNotification { self.sleeping = false }
                    self.refreshAnimation()
                }
            })
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        animationTimer?.invalidate()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refreshAnimation() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }

    func setFocusing(_ focusing: Bool) {
        if isFocusing != focusing { isFocusing = focusing; needsDisplay = true }
        refreshAnimation()
    }
    func refreshAnimation() {
        let shouldAnimate = isFocusing && window != nil && !sleeping && !reduceMotion()
        guard shouldAnimate else { stopAnimation(); return }
        guard animationTimer == nil else { return }
        animationStart = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.animationTime = ProcessInfo.processInfo.systemUptime - self.animationStart
                self.needsDisplay = true
            }
        }
        timer.tolerance = 0.01
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func stopAnimation() {
        animationTimer?.invalidate(); animationTimer = nil
        if animationTime != 0 { animationTime = 0; needsDisplay = true }
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        CultivatorArtwork.draw(in: bounds, focusing: isFocusing, time: animationTime, dark: dark)
    }
}
