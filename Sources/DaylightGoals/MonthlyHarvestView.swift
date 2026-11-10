import SwiftUI
import SpriteKit
import DaylightCore

struct MonthlyHarvestView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var harvest: MonthlyHarvest { model.planner.monthlyHarvest(on: model.today) }
    var body: some View {
        let current = harvest
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("本月的收获").font(.system(size: 13, weight: .semibold))
                Text("\(Int(model.today.monthKey.suffix(2)) ?? 1) 月 · 完成 \(current.total) 颗")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.secondary)
                Spacer()
                if current.perTomato > 1 {
                    Text("每颗代表 \(current.perTomato) 次，尾颗按实际数量标注")
                        .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                } else if current.total > 0 && !reduceMotion {
                    Text("轻点番茄，弹一弹").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
            }.padding(.horizontal, 18).padding(.top, 12)
            ZStack {
                TomatoHarvestCanvas(harvest: current, visible: model.ropeVisible, reduceMotion: reduceMotion)
                if current.total == 0 {
                    Text("每完成一颗番茄，这里就会多一份收获。")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .allowsHitTesting(false)
                }
            }.frame(maxHeight: .infinity)
        }
        .foregroundStyle(Palette.ink)
        .background(Color(hex: 0xFFF8EE).opacity(0.97), in: RoundedRectangle(cornerRadius: 21))
        .clipShape(RoundedRectangle(cornerRadius: 21))
        .overlay(RoundedRectangle(cornerRadius: 21).strokeBorder(Color.white.opacity(0.75)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(current.monthKey) 已完成 \(current.total) 颗番茄")
    }
}

struct TomatoHarvestCanvas: NSViewRepresentable {
    let harvest: MonthlyHarvest
    let visible: Bool
    let reduceMotion: Bool
    func makeNSView(context: Context) -> HarvestSKView {
        let view = HarvestSKView(frame: .zero)
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 30
        view.isPaused = true
        let scene = TomatoHarvestScene(size: NSSize(width: 1000, height: 110))
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        view.presentScene(scene)
        scene.configure(harvest: harvest, visible: visible, reduceMotion: reduceMotion)
        return view
    }
    func updateNSView(_ view: HarvestSKView, context: Context) {
        (view.scene as? TomatoHarvestScene)?.configure(harvest: harvest, visible: visible, reduceMotion: reduceMotion)
    }
    static func dismantleNSView(_ view: HarvestSKView, coordinator: ()) {
        view.isPaused = true
        view.scene?.removeAllActions()
        view.presentScene(nil)
    }
}

final class HarvestSKView: SKView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        guard let scene = scene as? TomatoHarvestScene else { return }
        let point = convert(event.locationInWindow, from: nil)
        scene.bounce(at: scene.convertPoint(fromView: point))
    }
}

/// SpriteKit supplies gravity, circle collisions, friction and restitution. Rendering stops when hidden or settled.
final class TomatoHarvestScene: SKScene {
    private var harvest: MonthlyHarvest?
    private var visible = false
    private var reducedMotion = false
    private var settleAt: TimeInterval?
    private var needsSettleDeadline = true
    private var sprites: [SKSpriteNode] = []
    private var textures: [SKTexture] = []

    func configure(harvest: MonthlyHarvest, visible: Bool, reduceMotion: Bool) {
        let changed = self.harvest != harvest
        let reopening = visible && !self.visible
        let motionChanged = reducedMotion != reduceMotion
        self.harvest = harvest; self.visible = visible; reducedMotion = reduceMotion
        if !visible { view?.isPaused = true; return }
        if changed || reopening || motionChanged { rebuild() }
    }
    override func didChangeSize(_ oldSize: CGSize) {
        if size != oldSize, visible { rebuild() }
    }
    private func rebuild() {
        removeAllActions(); removeAllChildren(); sprites.removeAll()
        guard let harvest, size.width > 40, size.height > 30 else { return }
        physicsWorld.gravity = CGVector(dx: 0, dy: -7.5)
        let border = CGMutablePath()
        border.move(to: CGPoint(x: 2, y: size.height + 200))
        border.addLine(to: CGPoint(x: 2, y: 5))
        border.addLine(to: CGPoint(x: size.width - 2, y: 5))
        border.addLine(to: CGPoint(x: size.width - 2, y: size.height + 200))
        let boundary = SKNode()
        boundary.physicsBody = SKPhysicsBody(edgeChainFrom: border)
        boundary.physicsBody?.friction = 0.8
        boundary.physicsBody?.restitution = 0.12
        addChild(boundary)
        guard !harvest.tomatoes.isEmpty else { view?.isPaused = true; return }
        if textures.isEmpty {
            textures = (0..<3).map { SKTexture(image: TomatoArtwork.fruit(variant: $0)) }
        }
        let count = harvest.tomatoes.count
        let radius = min(23, max(6, sqrt(size.width * max(20, size.height - 12) * 0.30 / (CGFloat(count) * .pi))))
        let usedWidth = min(size.width - radius * 3, max(110, CGFloat(count) * radius * 1.6))
        for (index, token) in harvest.tomatoes.enumerated() {
            let seed = token.id.uuidString.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
            let variation = CGFloat(seed % 1000) / 1000
            let r = reducedMotion ? radius : radius * (0.85 + variation * 0.28)
            let fruit = SKSpriteNode(texture: textures[Int(seed % 3)])
            // Artwork's round body is centered at 50%, 43.5% of the texture.
            fruit.size = CGSize(width: r * 2.44, height: r * 2.44)
            fruit.anchorPoint = CGPoint(x: 0.5, y: 0.435)
            fruit.name = "tomato-\(token.id)"
            fruit.zPosition = 1
            if token.count > 1 || harvest.perTomato > 1 {
                let label = SKLabelNode(text: "\(token.count)")
                label.fontName = "HelveticaNeue-Bold"; label.fontSize = max(8, r * 0.58)
                label.fontColor = NSColor(calibratedRed: 0.32, green: 0.19, blue: 0.1, alpha: 1)
                label.position = CGPoint(x: r * 0.72, y: -r * 0.55)
                label.zPosition = 2
                fruit.addChild(label)
            }
            sprites.append(fruit)
            if reducedMotion {
                let step = r * 2.12
                let columns = max(1, Int((size.width - r * 2) / step))
                let row = index / columns
                fruit.position = CGPoint(x: r + 6 + CGFloat(index % columns) * step + (row % 2 == 1 ? r * 0.5 : 0), y: 5 + r + CGFloat(row) * r * 1.9)
                fruit.zRotation = (variation - 0.5) * 0.24
                addChild(fruit)
            } else {
                fruit.position = CGPoint(x: radius * 1.5 + variation * usedWidth, y: size.height + r * 1.5)
                fruit.zRotation = (variation - 0.5) * 0.5
                let body = SKPhysicsBody(circleOfRadius: r)
                body.restitution = 0.32; body.friction = 0.7
                body.linearDamping = 0.4; body.angularDamping = 0.7
                body.mass = max(0.02, r * r / 8000)
                body.allowsRotation = true; body.usesPreciseCollisionDetection = true
                body.angularVelocity = (variation - 0.5) * 2
                fruit.physicsBody = body
                let delay = Double(index) * min(0.095, 3.5 / Double(count))
                run(.sequence([.wait(forDuration: delay), .run { [weak self, weak fruit] in
                    guard let self, let fruit else { return }
                    self.addChild(fruit)
                }]))
            }
        }
        needsSettleDeadline = true; settleAt = nil
        view?.isPaused = reducedMotion
    }
    override func update(_ currentTime: TimeInterval) {
        guard visible else { view?.isPaused = true; return }
        if needsSettleDeadline { settleAt = currentTime + 13; needsSettleDeadline = false }
        if let settleAt, currentTime >= settleAt { view?.isPaused = true }
    }
    func bounce(at point: CGPoint) {
        guard visible, !reducedMotion else { return }
        guard let fruit = sprites.filter({ $0.parent != nil }).min(by: { hypot($0.position.x - point.x, $0.position.y - point.y) < hypot($1.position.x - point.x, $1.position.y - point.y) }),
              hypot(fruit.position.x - point.x, fruit.position.y - point.y) < max(25, fruit.size.width * 0.7),
              let body = fruit.physicsBody else { return }
        view?.isPaused = false
        needsSettleDeadline = true
        body.applyImpulse(CGVector(dx: (fruit.position.x - point.x) * body.mass * 2, dy: body.mass * 210))
        body.applyAngularImpulse(body.mass * 0.4)
    }
}
