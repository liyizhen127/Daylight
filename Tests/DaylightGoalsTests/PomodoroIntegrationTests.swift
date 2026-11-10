import XCTest
import AppKit
import SwiftUI
import DaylightCore
@testable import DaylightGoals

@MainActor final class FakeCalendar: CalendarGateway {
    var hasAccess = true
    var defaultCalendarID: String? = "test-calendar"
    var requests = 0
    var fail = false
    var calls: [FocusSession] = []
    var saved: [UUID: String] = [:]
    func requestAccess() async throws -> Bool { requests += 1; return hasAccess }
    func calendars() -> [CalendarOption] { hasAccess ? [CalendarOption(id: "test-calendar", title: "测试日历")] : [] }
    func save(_ session: FocusSession, calendarID: String?) throws -> String {
        calls.append(session)
        guard !fail, hasAccess else { throw CalendarSyncError.denied }
        guard calendarID == "test-calendar" else { throw CalendarSyncError.missingCalendar }
        let id = saved[session.id] ?? UUID().uuidString
        saved[session.id] = id
        return id
    }
}
@MainActor final class PomodoroIntegrationTests: XCTestCase {
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("DaylightIntegration-\(UUID())") }
    func testCompletedAndInterruptedSessionsPersistAndSyncExactlyOnce() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let calendar = FakeCalendar(); let model = try AppModel(directory: dir, calendarGateway: calendar)
        let day = Day(Date()); let now = Date()
        model.addTasks("论文", scope: nil, day: day)
        let id = model.planner.record(on: day).tasks[0].id
        model.updatePomodoroSettings { $0.focusMinutes = 1; $0.calendarEnabled = true; $0.calendarIdentifier = "test-calendar" }
        model.startFocus(id, day: day, now: now)
        model.tick(now: now.addingTimeInterval(60))
        XCTAssertEqual(calendar.saved.count, 1)
        XCTAssertEqual(calendar.calls[0].title, "论文")
        XCTAssertEqual(calendar.calls[0].endedAt, now.addingTimeInterval(60))
        XCTAssertEqual(model.planner.sessions[0].calendarState, .synced)
        XCTAssertEqual(try model.disk.load().sessions[0].calendarState, .synced)
        model.syncCalendar(); XCTAssertEqual(calendar.calls.count, 1)
        model.stopTimer(now: now.addingTimeInterval(61)) // skip break
        model.startFocus(id, day: day, now: now.addingTimeInterval(62))
        model.stopTimer(now: now.addingTimeInterval(75))
        XCTAssertEqual(calendar.saved.count, 2)
        XCTAssertEqual(calendar.calls.last?.outcome, .interrupted)
        XCTAssertEqual(model.planner.actualPomodoros(taskID: id, on: day), 1)
    }
    func testCalendarFailurePreservesPendingRecordAcrossRestartAndRetry() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let calendar = FakeCalendar(); calendar.fail = true
        var model: AppModel? = try AppModel(directory: dir, calendarGateway: calendar)
        let day = Day(Date()); let now = Date()
        model!.addTasks("整理实验", scope: nil, day: day)
        model!.updatePomodoroSettings { $0.calendarEnabled = true; $0.calendarIdentifier = "test-calendar" }
        model!.startFocus(model!.planner.record(on: day).tasks[0].id, day: day, now: now)
        model!.stopTimer(now: now.addingTimeInterval(20))
        XCTAssertEqual(model!.planner.sessions[0].calendarState, .pending)
        XCTAssertNotNil(model!.calendarMessage)
        let id = model!.planner.sessions[0].id
        model = nil
        calendar.fail = false
        model = try AppModel(directory: dir, calendarGateway: calendar)
        model!.syncCalendar()
        XCTAssertEqual(calendar.saved.count, 1)
        XCTAssertNotNil(calendar.saved[id])
        XCTAssertEqual(try model!.disk.load().sessions[0].calendarState, .synced)
    }
    func testUnsubmittedTaskDraftSurvivesDaySwitchAndRestart() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let day = Day(rawValue: "2026-11-10")
        var model: AppModel? = try AppModel(directory: dir, calendarGateway: FakeCalendar())
        model!.draftBinding(scope: nil, day: day).wrappedValue = "尚未点击添加的中文任务"
        model!.select(day.adding(1))
        XCTAssertEqual(model!.draftBinding(scope: nil, day: day.adding(1)).wrappedValue, "")
        model!.flush(); model = nil
        model = try AppModel(directory: dir, calendarGateway: FakeCalendar())
        XCTAssertEqual(model!.draftBinding(scope: nil, day: day).wrappedValue, "尚未点击添加的中文任务")
        XCTAssertTrue(model!.planner.record(on: day).tasks.isEmpty)
    }
    func testStatusMenuStartsSelectedTodayTaskAndOffersInterruption() throws {
        _ = NSApplication.shared
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let model = try AppModel(directory: dir, calendarGateway: FakeCalendar())
        model.addTasks("任务一\n任务二", scope: nil, day: model.today)
        model.select(model.today.adding(-1))
        let delegate = AppDelegate(); delegate.model = model
        let second = model.planner.record(on: model.today).tasks[1]
        let menu = delegate.makeStatusMenu()
        let item = try XCTUnwrap(menu.items.first { ($0.representedObject as? String) == second.id.uuidString })
        XCTAssertTrue(item.title.contains("任务二"))
        let action = try XCTUnwrap(item.action)
        _ = delegate.perform(action, with: item)
        XCTAssertEqual(model.planner.activeTimer?.taskID, second.id)
        XCTAssertEqual(model.planner.activeTimer?.day, model.today)
        XCTAssertTrue(delegate.makeStatusMenu().items.contains { $0.title == "中断本次专注（保留时段）" })
        model.stopTimer()
    }
    func testDeniedCalendarAccessDoesNotEnableSyncOrLoseTasks() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let calendar = FakeCalendar(); calendar.hasAccess = false
        let model = try AppModel(directory: dir, calendarGateway: calendar)
        model.addTasks("保留任务", scope: nil, day: model.today)
        model.enableCalendar(true)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(model.planner.pomodoro.calendarEnabled)
        XCTAssertEqual(model.planner.record(on: model.today).tasks.count, 1)
        XCTAssertNotNil(model.calendarMessage)
        model.flush()
    }
    func testTaskIMECompositionSurvivesTimerTicksAndCheckboxKeepsStats() async throws {
        _ = NSApplication.shared
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let model = try AppModel(directory: dir, calendarGateway: FakeCalendar())
        let day = model.today
        model.addTasks("任务", scope: nil, day: day)
        let id = model.planner.record(on: day).tasks[0].id
        let host = NSHostingView(rootView: NativeTextEditor(text: model.taskTitleBinding(id, scope: nil, day: day), placeholder: "任务", fontSize: 14).environmentObject(model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 150), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        func find(_ view: NSView) -> CompositionTextView? { (view as? CompositionTextView) ?? view.subviews.compactMap { find($0) }.first }
        try await Task.sleep(nanoseconds: 80_000_000)
        let view = try XCTUnwrap(find(host))
        model.startFocus(id, day: day)
        view.setSelectedRange(NSRange(location: 2, length: 0))
        view.setMarkedText("zhongwen", selectedRange: NSRange(location: 8, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        model.tick(); model.flush()
        try await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertTrue(view.hasMarkedText()); XCTAssertEqual(view.string, "任务zhongwen")
        view.insertText("中文", replacementRange: view.markedRange())
        XCTAssertEqual(model.planner.activeTimer?.title, "任务中文")
        model.updateTask(id, scope: nil, day: day) { $0.isCompleted = true }
        XCTAssertEqual(model.planner.record(on: day).tasks[0].id, id)
        XCTAssertEqual(model.planner.record(on: day).tasks.count, 1)
        model.stopTimer(); model.flush()
    }
}
