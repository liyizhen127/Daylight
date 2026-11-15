import XCTest
import AppKit
import DaylightCore
@testable import DaylightGoals

@MainActor final class CultivatorTests: XCTestCase {
    func testMenuBarCultivatesThroughOvertimeAndStopsForBreakAndIdle() throws {
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DaylightCultivator-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = try AppModel(directory: dir, calendarGateway: FakeCalendar())
        let delegate = AppDelegate(); delegate.model = model; delegate.setupStatusItem()
        defer {
            model.onTimerChange = nil
            delegate.statusCultivator?.stopAnimation()
            NSStatusBar.system.removeStatusItem(delegate.statusItem)
        }
        let view = try XCTUnwrap(delegate.statusCultivator)
        view.reduceMotion = { false }
        model.onTimerChange = { [weak delegate] in delegate?.updateStatusItem() }
        XCTAssertFalse(view.isFocusing)
        XCTAssertNil(view.animationTimer)
        model.addTasks("阅读与整理", scope: nil, day: model.today)
        model.updatePomodoroSettings { $0.focusMinutes = 1 }
        let now = Date()
        model.startFocus(model.planner.record(on: model.today).tasks[0].id, day: model.today, now: now)
        XCTAssertTrue(view.isFocusing)
        let timer = try XCTUnwrap(view.animationTimer)
        let focusWidth = delegate.statusItem.length
        model.tick(now: now.addingTimeInterval(2))
        XCTAssertTrue(view.animationTimer === timer, "A one-second model update must not restart the animation")
        XCTAssertEqual(delegate.statusItem.length, focusWidth)
        model.tick(now: now.addingTimeInterval(75))
        XCTAssertTrue(view.isFocusing)
        XCTAssertTrue(view.animationTimer === timer)
        XCTAssertTrue(model.planner.sessions.isEmpty)
        model.startBreak(now: now.addingTimeInterval(76))
        XCTAssertFalse(view.isFocusing)
        XCTAssertNil(view.animationTimer)
        XCTAssertFalse(timer.isValid)
        XCTAssertEqual(model.planner.sessions.count, 1)
        model.stopTimer(now: now.addingTimeInterval(77))
        XCTAssertNil(view.animationTimer)
        XCTAssertFalse(view.isFocusing)
        XCTAssertTrue(delegate.statusItem.button?.accessibilityLabel()?.contains("今日已完成 1") == true)
        XCTAssertNotNil(delegate.statusItem.button?.action)
    }

    func testReducedMotionSleepAndDetachmentStopRenderingWithoutInterceptingClicks() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 30), styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = CultivatorStatusView(frame: NSRect(origin: .zero, size: CultivatorArtwork.size))
        var reduced = false
        view.reduceMotion = { reduced }
        window.contentView?.addSubview(view)
        view.setFocusing(true)
        XCTAssertNotNil(view.animationTimer)
        XCTAssertNil(view.hitTest(NSPoint(x: 17, y: 12)))
        reduced = true; view.refreshAnimation()
        XCTAssertNil(view.animationTimer)
        XCTAssertEqual(view.animationTime, 0)
        XCTAssertTrue(view.isFocusing, "Reduce Motion keeps the focused artwork, without movement")
        reduced = false; view.refreshAnimation()
        XCTAssertNotNil(view.animationTimer)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        XCTAssertNil(view.animationTimer)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertNotNil(view.animationTimer)
        view.removeFromSuperview()
        XCTAssertNil(view.animationTimer)
    }

    func testArtworkChangesDuringFocusButIdleIsStillInBothAppearances() throws {
        _ = NSApplication.shared
        func pixels(focusing: Bool, time: Double, dark: Bool) throws -> Data {
            let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 88, pixelsHigh: 48, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            CultivatorArtwork.draw(in: NSRect(x: 0, y: 0, width: 88, height: 48), focusing: focusing, time: time, dark: dark)
            NSGraphicsContext.restoreGraphicsState()
            return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        }
        for dark in [false, true] {
            XCTAssertEqual(try pixels(focusing: false, time: 0, dark: dark), try pixels(focusing: false, time: 1.4, dark: dark))
            XCTAssertNotEqual(try pixels(focusing: true, time: 0, dark: dark), try pixels(focusing: true, time: 1.4, dark: dark))
            XCTAssertNotEqual(try pixels(focusing: false, time: 0, dark: dark), try pixels(focusing: true, time: 0, dark: dark))
        }
    }
}
