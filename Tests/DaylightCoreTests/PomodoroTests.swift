import XCTest
@testable import DaylightCore

final class PomodoroTests: XCTestCase {
    let day = Day(rawValue: "2026-11-10")
    let start = ISO8601DateFormatter().date(from: "2026-11-10T01:00:00Z")!
    func planner() -> Planner {
        var p = Planner()
        p.setDaily(.expected, on: day, text: "阅读论文\n实验整理")
        p.pomodoro.focusMinutes = 1; p.pomodoro.shortBreakMinutes = 1
        p.pomodoro.longBreakMinutes = 3; p.pomodoro.longBreakEvery = 2
        return p
    }
    func testChecklistsKeepCompletedItemsAndIdentityAfterEditing() throws {
        var p = planner()
        var tasks = p.record(on: day).tasks
        let id = tasks[0].id
        tasks[0].title = "阅读新论文"; tasks[0].isCompleted = true; tasks[0].estimatedPomodoros = 5
        p.setTasks(tasks, scope: nil, on: day)
        let reopened = try PlannerDisk.decode(PlannerDisk.encode(p))
        XCTAssertEqual(reopened.record(on: day).tasks[0].id, id)
        XCTAssertEqual(reopened.record(on: day).tasks.count, 2)
        XCTAssertTrue(reopened.markdown(for: day).contains("- [x] 阅读新论文"))
        XCTAssertTrue(reopened.markdown(for: day).contains("🍅 0/5"))
    }
    func testMarkdownTaskImportAndAllGoalPeriods() {
        var p = planner()
        for scope in GoalScope.allCases {
            p.setGoal(scope, on: day, text: "- [ ] 未完成\n- [x] 已完成\n普通任务")
            let tasks = p.tasks(scope, on: day)
            XCTAssertEqual(tasks.map(\.title), ["未完成", "已完成", "普通任务"])
            XCTAssertEqual(tasks.map(\.isCompleted), [false, true, false])
            p.setGoal(scope, on: day, text: "未完成\n已完成\n普通任务")
            XCTAssertEqual(p.tasks(scope, on: day), tasks)
        }
    }
    func testCompletionIsExactlyOnceAndLongBreakCadence() throws {
        var p = planner(); let task = p.record(on: day).tasks[0]
        XCTAssertTrue(p.startFocus(taskID: task.id, on: day, now: start))
        XCTAssertFalse(p.startFocus(taskID: task.id, on: day, now: start))
        XCTAssertEqual(p.activeTimer?.remaining(at: start.addingTimeInterval(1.2)), 59)
        XCTAssertEqual(p.advanceTimer(now: start.addingTimeInterval(59)), [])
        XCTAssertEqual(p.advanceTimer(now: start.addingTimeInterval(60)), [.focusCompleted])
        XCTAssertEqual(p.activeTimer?.phase, .shortBreak)
        XCTAssertEqual(p.actualPomodoros(taskID: task.id, on: day), 1)
        XCTAssertEqual(p.advanceTimer(now: start.addingTimeInterval(61)), [])
        XCTAssertEqual(p.advanceTimer(now: start.addingTimeInterval(120)), [.breakCompleted])
        XCTAssertNil(p.activeTimer)
        XCTAssertTrue(p.startFocus(taskID: task.id, on: day, now: start.addingTimeInterval(120)))
        p.advanceTimer(now: start.addingTimeInterval(180))
        XCTAssertEqual(p.activeTimer?.phase, .longBreak)
        XCTAssertEqual(p.activeTimer?.remaining(at: start.addingTimeInterval(180)), 180)
        XCTAssertEqual(p.cycleCompleted, 0)
        XCTAssertEqual(p.completedPomodoros(on: Day(start)), 2)
        XCTAssertEqual(p.sessions.count, 2)
        XCTAssertFalse(p.record(on: day).tasks[0].isCompleted, "Finishing a tomato does not finish the whole task")
    }
    func testInterruptRecordsActualTimesButDoesNotCount() {
        var p = planner(); p.pomodoro.calendarEnabled = true; p.pomodoro.calendarIdentifier = "selected-calendar"
        let task = p.record(on: day).tasks[0]
        p.startFocus(taskID: task.id, on: day, now: start)
        XCTAssertTrue(p.stopTimer(now: start.addingTimeInterval(17)))
        XCTAssertFalse(p.stopTimer(now: start.addingTimeInterval(18)))
        XCTAssertEqual(p.sessions.count, 1)
        XCTAssertEqual(p.sessions[0].endedAt.timeIntervalSince(start), 17)
        XCTAssertEqual(p.sessions[0].outcome, .interrupted)
        XCTAssertEqual(p.sessions[0].calendarState, .pending)
        XCTAssertEqual(p.sessions[0].calendarIdentifier, "selected-calendar")
        XCTAssertEqual(p.actualPomodoros(taskID: task.id, on: day), 0)
        XCTAssertEqual(p.cycleCompleted, 0)
    }
    func testStoppingAtDeadlineCountsCompletionAndSkipsBreak() {
        var p = planner(); let id = p.record(on: day).tasks[0].id
        p.startFocus(taskID: id, on: day, now: start)
        p.stopTimer(now: start.addingTimeInterval(60))
        XCTAssertEqual(p.sessions[0].outcome, .completed)
        XCTAssertNil(p.activeTimer)
        XCTAssertEqual(p.actualPomodoros(taskID: id, on: day), 1)
    }
    func testSleepAndRestartOnlyCompleteOneFocus() throws {
        var p = planner(); let id = p.record(on: day).tasks[0].id
        p.startFocus(taskID: id, on: day, now: start)
        p = try PlannerDisk.decode(PlannerDisk.encode(p))
        XCTAssertEqual(p.advanceTimer(now: start.addingTimeInterval(5000)), [.focusCompleted, .breakCompleted])
        XCTAssertNil(p.activeTimer)
        XCTAssertEqual(p.sessions.count, 1)
        XCTAssertEqual(p.sessions[0].endedAt, start.addingTimeInterval(60))
        p = try PlannerDisk.decode(PlannerDisk.encode(p))
        XCTAssertEqual(p.advanceTimer(now: start.addingTimeInterval(6000)), [])
        XCTAssertEqual(p.sessions.count, 1)
    }
    func testTaskRenameAndDeletionRetainFocusHistory() {
        var p = planner(); var tasks = p.record(on: day).tasks; let id = tasks[0].id
        p.startFocus(taskID: id, on: day, now: start)
        p.advanceTimer(now: start.addingTimeInterval(60))
        tasks[0].title = "新名字"; p.setTasks(tasks, scope: nil, on: day)
        XCTAssertEqual(p.actualPomodoros(taskID: id, on: day), 1)
        p.setTasks([], scope: nil, on: day)
        XCTAssertEqual(p.sessions[0].title, "阅读论文")
        XCTAssertEqual(p.completedPomodoros(on: Day(start)), 1)
    }
    func testMidnightUsesCompletionDayForStatusButKeepsTaskDay() {
        var p = planner(); let id = p.record(on: day).tasks[0].id
        let nextDay = day.adding(1)
        let midnight = Calendar.planner.startOfDay(for: nextDay.date()!)
        p.startFocus(taskID: id, on: day, now: midnight.addingTimeInterval(-30))
        p.advanceTimer(now: midnight.addingTimeInterval(30))
        XCTAssertEqual(p.completedPomodoros(on: day), 0)
        XCTAssertEqual(p.completedPomodoros(on: nextDay), 1)
        XCTAssertEqual(p.actualPomodoros(taskID: id, on: day), 1)
        XCTAssertEqual(p.sessions[0].day, day)
    }
    func testDisabledCalendarAndBreaksNeverGeneratePendingEvents() {
        var p = planner(); let id = p.record(on: day).tasks[0].id
        p.startFocus(taskID: id, on: day, now: start)
        p.advanceTimer(now: start.addingTimeInterval(60))
        p.stopTimer(now: start.addingTimeInterval(70))
        XCTAssertEqual(p.sessions.count, 1)
        XCTAssertEqual(p.sessions[0].calendarState, .notRequested)
    }
    func testInvalidSettingsDuplicateIDsAndInvalidTimerRejected() throws {
        var p = planner(); p.pomodoro.focusMinutes = 0; XCTAssertThrowsError(try p.validate())
        p = planner(); p.pomodoro.longBreakEvery = 0; XCTAssertThrowsError(try p.validate())
        p = planner(); let task = p.record(on: day).tasks[0]; p.longTermTasks = [task]; XCTAssertThrowsError(try p.validate())
        p = planner(); p.activeTimer = ActiveTimer(taskID: task.id, day: day, title: "bad", phase: .focus, startedAt: start, seconds: -1)
        XCTAssertThrowsError(try p.validate())
    }
    func testLegacyMigrationKeepsPermanentOriginalAndReflection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DaylightMigration-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = try PlannerDisk(directory: directory)
        let legacy = Data(#"{"schemaVersion":1,"longTerm":"长期方向\n- [x] 已完成方向","months":{"2026-11":"月目标"},"weeks":{"2026-11-09":"周目标"},"days":{"2026-11-10":{"expected":"第一件事\n第二件事","actual":"旧版实际完成\n保留 🌱","modifiedAt":"2026-11-10T01:00:00Z"}}}"#.utf8)
        try legacy.write(to: disk.file)
        let p = try disk.load()
        XCTAssertEqual(p.schemaVersion, 2)
        XCTAssertEqual(p.record(on: day).tasks.map(\.title), ["第一件事", "第二件事"])
        XCTAssertEqual(p.record(on: day).reflection, "旧版实际完成\n保留 🌱")
        XCTAssertTrue(p.longTermTasks[1].isCompleted)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("planner.before-v2.json")), legacy)
        XCTAssertEqual(try disk.load(), p)
        try disk.save(p); try disk.save(p)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("planner.before-v2.json")), legacy)
    }
}
