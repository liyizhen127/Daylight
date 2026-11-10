import XCTest
import AppKit
import SpriteKit
import DaylightCore
@testable import DaylightGoals

@MainActor final class HarvestSceneTests: XCTestCase {
    func testHiddenAndReducedMotionDoNotAnimateOrDuplicateFruitOnRefresh() {
        _ = NSApplication.shared
        let now = Date()
        let timer = ActiveTimer(taskID: UUID(), day: Day(now), title: "阅读", phase: .focus, startedAt: now.addingTimeInterval(-1500), seconds: 1500)
        let session = FocusSession(timer: timer, endedAt: now, outcome: .completed, settings: PomodoroSettings())
        let harvest = MonthlyHarvest(monthKey: Day(now).monthKey, sessions: [session])
        let scene = TomatoHarvestScene(size: CGSize(width: 900, height: 115))
        let view = HarvestSKView(frame: NSRect(x: 0, y: 0, width: 900, height: 115))
        view.presentScene(scene)
        defer { view.presentScene(nil) }
        scene.configure(harvest: harvest, visible: true, reduceMotion: true)
        XCTAssertTrue(view.isPaused)
        let originalFruit = scene.children.compactMap { $0 as? SKSpriteNode }
        XCTAssertEqual(originalFruit.count, 1)
        for _ in 0..<5 { scene.configure(harvest: harvest, visible: true, reduceMotion: true) }
        let afterRefresh = scene.children.compactMap { $0 as? SKSpriteNode }
        XCTAssertTrue(afterRefresh.first === originalFruit.first, "Autosave/timer refreshes must not reset the scene")
        scene.configure(harvest: harvest, visible: false, reduceMotion: false)
        XCTAssertTrue(view.isPaused)
        scene.configure(harvest: harvest, visible: true, reduceMotion: false)
        XCTAssertFalse(view.isPaused)
        scene.configure(harvest: harvest, visible: false, reduceMotion: false)
        XCTAssertTrue(view.isPaused)
    }
}
