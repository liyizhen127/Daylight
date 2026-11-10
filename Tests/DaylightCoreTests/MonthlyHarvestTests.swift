import XCTest
@testable import DaylightCore

final class MonthlyHarvestTests: XCTestCase {
    private func session(end: String, outcome: FocusOutcome = .completed) -> FocusSession {
        let ended = ISO8601DateFormatter().date(from: end)!
        let timer = ActiveTimer(taskID: UUID(), day: Day(rawValue: "2026-10-31"), title: "阅读", phase: .focus,
                                startedAt: ended.addingTimeInterval(-1500), seconds: 1500)
        return FocusSession(timer: timer, endedAt: ended, outcome: outcome, settings: PomodoroSettings())
    }
    func testMonthUsesLocalCompletionTimeAndExcludesInterruptions() {
        var calendar = Calendar.planner
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let previousMonth = session(end: "2026-10-31T15:59:59Z")
        let first = session(end: "2026-10-31T16:00:00Z")
        let last = session(end: "2026-11-30T15:59:59Z")
        let nextMonth = session(end: "2026-11-30T16:00:00Z")
        let stopped = session(end: "2026-11-10T03:00:00Z", outcome: .interrupted)
        let result = MonthlyHarvest(monthKey: "2026-11", sessions: [last, stopped, first, previousMonth, nextMonth], calendar: calendar)
        XCTAssertEqual(result.total, 2)
        XCTAssertEqual(result.tomatoes.map(\.id), [first.id, last.id])
        XCTAssertEqual(result.perTomato, 1)
    }
    func testLargeHarvestRetainsExactCountWithBoundedPhysicsBodies() {
        let sessions = (0..<1001).map { _ in session(end: "2026-11-10T03:00:00Z") }
        for count in [0, 1, 239, 240, 241, 1001] {
            let result = MonthlyHarvest(monthKey: "2026-11", sessions: Array(sessions.prefix(count)))
            XCTAssertEqual(result.total, count)
            XCTAssertEqual(result.tomatoes.reduce(0) { $0 + $1.count }, count)
            XCTAssertLessThanOrEqual(result.tomatoes.count, 240)
            XCTAssertEqual(Set(result.tomatoes.map(\.id)).count, result.tomatoes.count)
            XCTAssertTrue(result.tomatoes.allSatisfy { $0.count > 0 && $0.count <= result.perTomato })
        }
    }
}
