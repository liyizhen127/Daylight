import XCTest
@testable import DaylightCore

final class PlannerTests: XCTestCase {
    func day(_ raw: String) -> Day { Day(rawValue: raw) }
    func testMonthlyAndWeeklyGoalsFollowSelectedDate() {
        var p = Planner()
        let friday = day("2026-10-30"), sunday = day("2026-11-01"), monday = day("2026-11-02")
        p.setGoal(.longTerm, on: friday, text: "长期研究")
        p.setGoal(.month, on: friday, text: "十月目标")
        p.setGoal(.week, on: friday, text: "跨月的一周")
        XCTAssertEqual(p.goal(.longTerm, on: monday), "长期研究")
        XCTAssertEqual(p.goal(.month, on: sunday), "")
        XCTAssertEqual(p.goal(.week, on: sunday), "跨月的一周")
        XCTAssertEqual(p.goal(.week, on: monday), "")
        p.setGoal(.month, on: sunday, text: "十一月目标")
        p.setGoal(.week, on: monday, text: "新周目标")
        XCTAssertEqual(p.goal(.month, on: friday), "十月目标")
        XCTAssertEqual(p.goal(.week, on: friday), "跨月的一周")
        p.setGoal(.longTerm, on: monday, text: "新的方向")
        XCTAssertEqual(p.goal(.longTerm, on: friday), "新的方向")
    }
    func testWeekAcrossYearAndLeapMonth() {
        XCTAssertEqual(day("2027-01-01").weekKey, "2026-12-28")
        XCTAssertEqual(day("2027-01-03").weekKey, "2026-12-28")
        XCTAssertEqual(day("2027-01-04").weekKey, "2027-01-04")
        XCTAssertEqual(day("2024-02-28").adding(1), day("2024-02-29"))
        XCTAssertEqual(day("2024-02-29").adding(1), day("2024-03-01"))
        XCTAssertNil(day("2026-02-29").date())
        XCTAssertNil(day("2026-13-01").date())
        XCTAssertNil(day("2026-1-01").date())
    }
    func testCivilDaysAcrossDST() {
        var calendar = Calendar.planner
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(day("2026-03-08").adding(1, calendar: calendar), day("2026-03-09"))
        XCTAssertEqual(day("2026-11-01").adding(1, calendar: calendar), day("2026-11-02"))
        XCTAssertEqual(day("2026-03-08").week(calendar: calendar).count, 7)
    }
    func testDailyFieldsAndDatesAreIndependent() {
        var p = Planner()
        let first = day("2026-10-23"), next = first.adding(1)
        p.setDaily(.expected, on: first, text: "计划\n第二行")
        p.setDaily(.actual, on: first, text: "实际做了这些 🌿")
        p.setDaily(.expected, on: next, text: "明日计划")
        XCTAssertEqual(p.record(on: first).expected, "计划\n第二行")
        XCTAssertEqual(p.record(on: first).actual, "实际做了这些 🌿")
        XCTAssertEqual(p.record(on: next).actual, "")
        p.setDaily(.expected, on: first, text: "")
        XCTAssertEqual(p.record(on: first).actual, "实际做了这些 🌿")
        p.setDaily(.actual, on: first, text: "")
        XCTAssertNil(p.days[first.rawValue])
        XCTAssertEqual(p.record(on: next).expected, "明日计划")
    }
    func testValidationRejectsWrongSchemaAndKeys() throws {
        var p = Planner()
        p.schemaVersion = 3
        XCTAssertThrowsError(try p.validate())
        p = Planner(); p.weeks["2026-10-23"] = "非周一"
        XCTAssertThrowsError(try p.validate())
        p = Planner(); p.months["2026-13"] = "不存在的月份"
        XCTAssertThrowsError(try p.validate())
        p = Planner(); p.days["2026-02-30"] = DayRecord(expected: "无效日期")
        XCTAssertThrowsError(try p.validate())
    }
    func testWeekExportIncludesBothMonthsAndDailyFields() {
        var p = Planner()
        p.months["2026-10"] = "十月"
        p.months["2026-11"] = "十一月"
        p.setDaily(.expected, on: day("2026-11-01"), text: "预期内容")
        p.setDaily(.actual, on: day("2026-11-01"), text: "实际内容")
        let output = p.weekMarkdown(for: day("2026-10-30"))
        for text in ["2026-10-26", "2026-11-01", "十月", "十一月", "预期内容", "实际内容"] {
            XCTAssertTrue(output.contains(text), text)
        }
    }
}

final class PersistenceTests: XCTestCase {
    var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("DaylightTests-\(UUID().uuidString)")
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }
    func testRestartRoundTripAndPreviousBackup() throws {
        var disk: PlannerDisk? = try PlannerDisk(directory: directory)
        var p = Planner(); p.longTerm = "长期目标\n中文与 emoji 🌱"
        p.setDaily(.expected, on: Day(rawValue: "2026-10-23"), text: "晨间计划", now: Date(timeIntervalSince1970: 1_800_000_000))
        try disk!.save(p)
        let first = p
        p.setDaily(.actual, on: Day(rawValue: "2026-10-23"), text: "晚间记录", now: Date(timeIntervalSince1970: 1_800_001_000))
        try disk!.save(p)
        XCTAssertEqual(try PlannerDisk.decode(Data(contentsOf: disk!.backup)), first)
        disk = nil
        let reopened = try PlannerDisk(directory: directory)
        XCTAssertEqual(try reopened.load(), p)
        let attributes = try FileManager.default.attributesOfItem(atPath: reopened.file.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testSecondWriterIsRejectedAndLockIsReleased() throws {
        var first: PlannerDisk? = try PlannerDisk(directory: directory)
        XCTAssertNotNil(first)
        XCTAssertThrowsError(try PlannerDisk(directory: directory))
        first = nil
        XCTAssertNoThrow(try PlannerDisk(directory: directory))
    }
    func testCorruptOriginalIsPreservedAndCanBeExplicitlyRestored() throws {
        let disk = try PlannerDisk(directory: directory)
        let broken = Data("{broken".utf8)
        try broken.write(to: disk.file)
        XCTAssertThrowsError(try disk.load())
        XCTAssertThrowsError(try disk.save(Planner()))
        XCTAssertEqual(try Data(contentsOf: disk.file), broken)
        var restored = Planner(); restored.longTerm = "恢复的目标"
        XCTAssertEqual(try disk.restore(PlannerDisk.encode(restored)), restored)
        XCTAssertEqual(try disk.load(), restored)
        let archived = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("before-restore-") }
        XCTAssertEqual(archived.count, 1)
        XCTAssertEqual(try Data(contentsOf: archived[0]), broken)
    }
    func testInvalidRestoreNeverReplacesGoodData() throws {
        let disk = try PlannerDisk(directory: directory)
        var p = Planner(); p.longTerm = "保留这条目标"
        try disk.save(p)
        XCTAssertThrowsError(try disk.restore(Data("{}".utf8)))
        XCTAssertEqual(try disk.load(), p)
    }
}
