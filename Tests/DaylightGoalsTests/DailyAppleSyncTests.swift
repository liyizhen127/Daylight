import XCTest
import DaylightCore
@testable import DaylightGoals

@MainActor private final class DailyTestGateway: DailyAppleGateway {
    var items: [String: DailyAppleItem] = [:]
    var writes = 0
    var failAfterWrite = false
    var denied: Set<DailyChannel> = []
    func authorize(_ channel: DailyChannel) async throws {
        if denied.contains(channel) { throw DailyAppleError.access(channel) }
    }
    func destinations(_ channel: DailyChannel) -> [CalendarOption] { [CalendarOption(id: channel.rawValue, title: "测试")] }
    func defaultID(_ channel: DailyChannel) -> String? { channel.rawValue }
    func beginPass() {}
    func reconcile(_ item: DailyAppleItem?, key: String, day: Day, channel: DailyChannel,
                   destination: String, knownID: String?) async throws -> String? {
        guard !denied.contains(channel) else { throw DailyAppleError.access(channel) }
        XCTAssertEqual(destination, channel.rawValue)
        items[key] = item
        writes += 1
        if failAfterWrite { throw DailyAppleError.readFailed }
        return item == nil ? nil : key
    }
}

@MainActor final class DailyAppleSyncTests: XCTestCase {
    private let day = Day(rawValue: "2026-11-21")
    private var morning: Date { day.date()! }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func settle(_ model: AppModel) async {
        for _ in 0..<3 { await Task.yield() }
        for _ in 0..<100 where model.dailyApple.running { try? await Task.sleep(nanoseconds: 5_000_000) }
    }
    private func enable(_ channel: DailyChannel, in model: AppModel) {
        model.dailyApple.configure(channel, destination: channel.rawValue)
    }
    func testDailyReminderTracksEditsCompletionCountsAndDeletion() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let gateway = DailyTestGateway()
        let model = try AppModel(directory: dir, dailyGateway: gateway)
        model.dailyApple.clock = { self.morning }
        model.addTasks("学习", scope: nil, day: day)
        model.addTasks("周任务", scope: .week, day: day)
        model.updatePomodoroSettings { $0.focusMinutes = 1 }
        model.flush()
        await settle(model)
        XCTAssertTrue(gateway.items.isEmpty)
        enable(.reminders, in: model)
        await settle(model)
        let id = model.planner.record(on: day).tasks[0].id
        XCTAssertEqual(gateway.items[id.uuidString]?.title, "学习 · 🍅 0/1")
        model.updateTask(id, scope: nil, day: day) { $0.title = "阅读"; $0.estimatedPomodoros = 3; $0.isCompleted = true }
        model.startFocus(id, day: day, now: morning)
        model.stopTimer(now: morning.addingTimeInterval(5))
        await settle(model)
        XCTAssertEqual(gateway.items[id.uuidString]?.title, "阅读 · 🍅 0/3")
        model.startFocus(id, day: day, now: morning.addingTimeInterval(10))
        model.startBreak(now: morning.addingTimeInterval(80))
        await settle(model)
        let entry = try XCTUnwrap(gateway.items[id.uuidString])
        XCTAssertEqual(entry.title, "阅读 · 🍅 1/3")
        XCTAssertEqual(entry.notes, "预估番茄：3\n实际完成：1")
        XCTAssertEqual(entry.day, day)
        XCTAssertEqual(entry.completed, true)
        XCTAssertEqual(gateway.items.count, 1)
        model.removeTask(id, scope: nil, day: day)
        XCTAssertTrue(model.flush())
        await settle(model)
        XCTAssertTrue(gateway.items.isEmpty)
    }

    func testReflectionWaitsForLocalElevenPMAndCatchesUpAfterRelaunch() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let gateway = DailyTestGateway()
        var model: AppModel? = try AppModel(directory: dir, dailyGateway: gateway)
        let eleven = Calendar.planner.date(bySettingHour: 23, minute: 0, second: 0, of: morning)!
        model!.dailyApple.clock = { eleven.addingTimeInterval(-1) }
        enable(.reflections, in: model!)
        model!.dailyBinding(.actual, day: day).wrappedValue = "今天读完一章"
        model!.flush()
        await settle(model!)
        XCTAssertTrue(gateway.items.isEmpty)
        model = nil
        model = try AppModel(directory: dir, dailyGateway: gateway)
        model!.dailyApple.clock = { eleven.addingTimeInterval(9 * 3600) }
        model!.tick(now: eleven.addingTimeInterval(9 * 3600))
        await settle(model!)
        XCTAssertEqual(gateway.items[day.rawValue]?.start, eleven)
        XCTAssertEqual(gateway.items[day.rawValue]?.notes, "今天读完一章")
        model!.dailyBinding(.actual, day: day).wrappedValue = "补记：明天继续"
        model!.flush()
        await settle(model!)
        XCTAssertEqual(gateway.items.count, 1)
        XCTAssertEqual(gateway.items[day.rawValue]?.notes, "补记：明天继续")
        model!.dailyBinding(.actual, day: day).wrappedValue = ""
        model!.flush()
        await settle(model!)
        XCTAssertTrue(gateway.items.isEmpty)
    }

    func testManualSyncScopesHistoricalDaysAndRecreatesMissingItems() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let gateway = DailyTestGateway()
        let model = try AppModel(directory: dir, dailyGateway: gateway)
        model.dailyApple.clock = { self.morning }
        let oldDay = day.adding(-7)
        model.addTasks("旧计划", scope: nil, day: oldDay)
        model.dailyBinding(.actual, day: oldDay).wrappedValue = "旧反思"
        model.dailyBinding(.actual, day: day).wrappedValue = "提前记录"
        model.flush()
        enable(.reminders, in: model)
        await settle(model)
        enable(.reflections, in: model)
        await settle(model)
        XCTAssertTrue(gateway.items.isEmpty)
        model.select(oldDay)
        model.syncSelectedDay()
        await settle(model)
        XCTAssertEqual(gateway.items.count, 2)
        gateway.items.removeAll()
        model.syncSelectedDay()
        await settle(model)
        XCTAssertEqual(gateway.items.count, 2)
        model.select(day)
        model.syncSelectedDay()
        await settle(model)
        XCTAssertEqual(Calendar.planner.component(.hour, from: try XCTUnwrap(gateway.items[day.rawValue]?.start)), 23)
    }

    func testElevenPMWritesOnceAndPermissionFailureIsIndependent() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let gateway = DailyTestGateway()
        let model = try AppModel(directory: dir, dailyGateway: gateway)
        let eleven = Calendar.planner.date(bySettingHour: 23, minute: 0, second: 0, of: morning)!
        var now = eleven.addingTimeInterval(-1)
        model.dailyApple.clock = { now }
        gateway.denied.insert(.reminders)
        let choices = await model.dailyApple.requestDestinations(.reminders)
        XCTAssertTrue(choices.isEmpty)
        XCTAssertFalse(model.dailyApple.enabled(.reminders))
        model.dailyBinding(.actual, day: day).wrappedValue = "今天的反思"
        model.flush()
        enable(.reflections, in: model)
        await settle(model)
        XCTAssertEqual(gateway.writes, 0)
        now = eleven
        model.tick(now: now)
        await settle(model)
        XCTAssertEqual(gateway.writes, 1)
        XCTAssertEqual(gateway.items[day.rawValue]?.start, eleven)
        model.tick(now: eleven.addingTimeInterval(60))
        await settle(model)
        XCTAssertEqual(gateway.writes, 1)
        model.dailyApple.configure(.reflections, destination: nil)
        model.dailyBinding(.actual, day: day).wrappedValue = "关闭后的本地修改"
        model.flush()
        await settle(model)
        XCTAssertEqual(gateway.items[day.rawValue]?.notes, "今天的反思")
    }

    func testFailureAfterRemoteWriteRetriesAcrossRestartAndRemoval() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let gateway = DailyTestGateway()
        var model: AppModel? = try AppModel(directory: dir, dailyGateway: gateway)
        model!.dailyApple.clock = { self.morning }
        model!.addTasks("可重试的任务", scope: nil, day: day)
        model!.flush()
        gateway.failAfterWrite = true
        enable(.reminders, in: model!)
        await settle(model!)
        XCTAssertEqual(gateway.items.count, 1)
        XCTAssertNotNil(model!.dailyApple.messages[.reminders])
        model = nil
        model = try AppModel(directory: dir, dailyGateway: gateway)
        model!.dailyApple.clock = { self.morning }
        gateway.failAfterWrite = false
        model!.tick(now: morning)
        await settle(model!)
        XCTAssertEqual(gateway.items.count, 1)
        let writes = gateway.writes
        model!.tick(now: morning.addingTimeInterval(60))
        await settle(model!)
        XCTAssertEqual(gateway.writes, writes)
        model!.removeTask(model!.planner.record(on: day).tasks[0].id, scope: nil, day: day)
        model!.flush()
        await settle(model!)
        XCTAssertTrue(gateway.items.isEmpty)
    }
}
