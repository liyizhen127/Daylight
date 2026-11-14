import XCTest
import AppKit
import SwiftUI
import DaylightCore
@testable import DaylightGoals

@MainActor final class FocusCompletionTests: XCTestCase {
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("DaylightReview-\(UUID())") }

    func testOvertimeWindowPresentsOnceKeepsDraggedPositionAndChangesToReview() throws {
        _ = NSApplication.shared
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let model = try AppModel(directory: dir, calendarGateway: FakeCalendar())
        model.addTasks("继续阅读", scope: nil, day: model.today)
        model.updatePomodoroSettings { $0.focusMinutes = 1 }
        let now = Date(), id = model.planner.record(on: model.today).tasks[0].id
        model.startFocus(id, day: model.today, now: now.addingTimeInterval(-90))
        let controller = FocusPromptController(model: model)
        model.onTimerChange = { [weak controller] in controller?.refresh() }
        defer { model.onTimerChange = nil; controller.window.orderOut(nil) }
        model.tick(now: now)
        let timerID = try XCTUnwrap(model.planner.activeTimer?.id)
        XCTAssertEqual(controller.presentation, .overtime(timerID))
        XCTAssertTrue(controller.window.isVisible)
        XCTAssertFalse(controller.windowShouldClose(controller.window))
        XCTAssertFalse(controller.window.standardWindowButton(.closeButton)?.isEnabled ?? true)
        let hosting = controller.window.contentView
        controller.window.setFrameOrigin(NSPoint(x: 25, y: 25))
        let draggedFrame = controller.window.frame
        for offset in 1...4 { model.tick(now: now.addingTimeInterval(Double(offset))) }
        XCTAssertEqual(controller.window.frame, draggedFrame)
        XCTAssertTrue(controller.window.contentView === hosting)
        XCTAssertTrue(model.planner.sessions.isEmpty)
        model.startBreak(now: now.addingTimeInterval(10))
        XCTAssertEqual(controller.presentation, .review(timerID))
        XCTAssertTrue(controller.window.standardWindowButton(.closeButton)?.isEnabled ?? false)
        XCTAssertEqual(model.planner.sessions[0].overtimeSeconds, 40)
        XCTAssertEqual(model.planner.activeTimer?.phase, .shortBreak)
        XCTAssertEqual(model.planner.activeTimer?.startedAt, now.addingTimeInterval(10))
        XCTAssertFalse(model.submitReview(timerID), "A rating is required to submit; reflection is optional")
        model.setReviewRating(.great, sessionID: timerID)
        XCTAssertTrue(model.submitReview(timerID))
        XCTAssertNil(controller.presentation)
        XCTAssertFalse(controller.window.isVisible)
    }

    func testReviewDraftAndRatingSurviveRestartAndCanBeEditedWithoutResyncingCalendar() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let calendar = FakeCalendar(), now = Date()
        var model: AppModel? = try AppModel(directory: dir, calendarGateway: calendar)
        model!.addTasks("阅读", scope: nil, day: model!.today)
        model!.updatePomodoroSettings { $0.focusMinutes = 1; $0.calendarEnabled = true; $0.calendarIdentifier = "test-calendar" }
        model!.startFocus(model!.planner.record(on: model!.today).tasks[0].id, day: model!.today, now: now.addingTimeInterval(-100))
        model!.startBreak(now: now)
        let id = try XCTUnwrap(model!.reviewSessionID)
        model!.setReviewRating(.okay, sessionID: id)
        model!.reviewReflectionBinding(id).wrappedValue = "完成了阅读，下次提前整理提纲。"
        XCTAssertTrue(model!.dismissReview())
        XCTAssertNil(model!.reviewSessionID)
        XCTAssertNil(model!.session(id)?.review?.submittedAt)
        model = nil
        model = try AppModel(directory: dir, calendarGateway: calendar)
        XCTAssertEqual(model!.reviewSessionID, id)
        XCTAssertEqual(model!.session(id)?.review?.rating, .okay)
        XCTAssertEqual(model!.session(id)?.review?.reflection, "完成了阅读，下次提前整理提纲。")
        model!.setReviewRating(.great, sessionID: id)
        XCTAssertTrue(model!.submitReview(id))
        model = nil
        model = try AppModel(directory: dir, calendarGateway: calendar)
        XCTAssertNil(model!.reviewSessionID)
        model!.showReview(id)
        model!.setReviewRating(.poor, sessionID: id)
        XCTAssertTrue(model!.submitReview(id))
        model!.syncCalendar()
        XCTAssertEqual(calendar.calls.count, 1, "Private reflections are local and never create or resync Calendar events")
        XCTAssertEqual(try model!.disk.load().sessions[0].review?.rating, .poor)
    }

    func testOvertimeStatusMenuStartsBreakAndReviewFromTheSameSession() throws {
        _ = NSApplication.shared
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let model = try AppModel(directory: dir, calendarGateway: FakeCalendar())
        model.addTasks("阅读", scope: nil, day: model.today)
        model.updatePomodoroSettings { $0.focusMinutes = 1 }
        model.startFocus(model.planner.record(on: model.today).tasks[0].id, day: model.today, now: Date().addingTimeInterval(-80))
        let delegate = AppDelegate(); delegate.model = model
        let menu = delegate.makeStatusMenu()
        XCTAssertTrue(menu.items.contains { $0.title.contains("额外专注") && $0.title.contains("+") })
        let action = try XCTUnwrap(menu.items.first { $0.title == "开始休息并评价" }?.action)
        _ = delegate.perform(action)
        XCTAssertEqual(model.planner.sessions.count, 1)
        XCTAssertNotNil(model.reviewSessionID)
        XCTAssertEqual(model.planner.activeTimer?.phase, .shortBreak)
    }

    func testReviewIMECompositionSurvivesBreakTimerAndSavesConfirmedText() async throws {
        _ = NSApplication.shared
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let model = try AppModel(directory: dir, calendarGateway: FakeCalendar())
        model.addTasks("阅读", scope: nil, day: model.today)
        model.updatePomodoroSettings { $0.focusMinutes = 1 }
        model.startFocus(model.planner.record(on: model.today).tasks[0].id, day: model.today, now: Date().addingTimeInterval(-80))
        model.startBreak()
        let id = try XCTUnwrap(model.reviewSessionID)
        let host = NSHostingView(rootView: NativeTextEditor(text: model.reviewReflectionBinding(id), placeholder: "感受", fontSize: 13).environmentObject(model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 80_000_000)
        func find(_ view: NSView) -> CompositionTextView? { (view as? CompositionTextView) ?? view.subviews.compactMap { find($0) }.first }
        let editor = try XCTUnwrap(find(host))
        editor.setMarkedText("shouhuo", selectedRange: NSRange(location: 7, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        model.tick(); model.flush()
        try await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertEqual(editor.string, "shouhuo")
        XCTAssertEqual(model.session(id)?.review?.reflection, "")
        editor.insertText("收获", replacementRange: editor.markedRange())
        model.setReviewRating(.great, sessionID: id)
        XCTAssertTrue(model.submitReview(id))
        XCTAssertEqual(try model.disk.load().sessions[0].review?.reflection, "收获")
    }
}
