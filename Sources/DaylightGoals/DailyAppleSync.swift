import CryptoKit
import DaylightCore
import Foundation
import SwiftUI

/// Device-local choices and write receipts. A portable planner backup cannot enable exports on another Mac.
private struct DailyReceipt: Codable {
    var day: Day
    var remoteID: String?
    var digest: String?
}
private struct DailyRoute: Codable {
    var since: Day?
    var destination: String?
    var earlierDays = Set<Day>()
    var receipts: [String: DailyReceipt] = [:]
}

@MainActor final class DailyAppleSync: ObservableObject {
    private let file: URL
    private let gateway: DailyAppleGateway
    private let encoder = JSONEncoder()
    private var routes: [String: DailyRoute] = [:]
    private(set) var loadError: String?
    @Published private(set) var messages: [DailyChannel: String] = [:]
    @Published private(set) var running = false
    var savedPlanner: (() -> Planner?)?
    private var worker: Task<Void, Never>?
    private var nextAutomatic = false
    private var manualDays: Set<Day> = []
    private var lastMinute: Int?
    var clock: () -> Date = Date.init

    init(directory: URL, gateway: DailyAppleGateway) {
        self.gateway = gateway
        file = directory.appendingPathComponent("daily-apple-sync.json")
        encoder.outputFormatting = [.sortedKeys]
        if FileManager.default.fileExists(atPath: file.path) {
            do { routes = try JSONDecoder().decode([String: DailyRoute].self, from: Data(contentsOf: file)) }
            catch { loadError = "无法读取每日同步设置：\(error.localizedDescription)" }
        }
    }

    func enabled(_ channel: DailyChannel) -> Bool { routes[channel.rawValue]?.since != nil }
    func destination(_ channel: DailyChannel) -> String? { routes[channel.rawValue]?.destination }
    func options(_ channel: DailyChannel) -> [CalendarOption] { gateway.destinations(channel) }
    func defaultID(_ channel: DailyChannel) -> String? { gateway.defaultID(channel) }

    func requestDestinations(_ channel: DailyChannel) async -> [CalendarOption] {
        do {
            try await gateway.authorize(channel)
            let options = gateway.destinations(channel)
            guard !options.isEmpty else { throw DailyAppleError.unavailable(channel) }
            messages[channel] = nil
            return options
        } catch {
            messages[channel] = error.localizedDescription
            return []
        }
    }

    /// Persist before acknowledging changes, including an intent receipt before the first remote write.
    private func store(_ route: DailyRoute, for channel: DailyChannel) throws {
        var updated = routes
        updated[channel.rawValue] = route
        try encoder.encode(updated).write(to: file, options: .atomic)
        routes = updated
    }

    func configure(_ channel: DailyChannel, destination: String?) {
        guard loadError == nil, !running else { return }
        var route = routes[channel.rawValue] ?? DailyRoute()
        route.since = destination.map { _ in route.since ?? Day(clock()) }
        if let destination { route.destination = destination }
        do {
            try store(route, for: channel)
            messages[channel] = destination == nil ? "已关闭自动同步" : nil
            saved()
        } catch { messages[channel] = error.localizedDescription }
    }

    func edited(_ day: Day, channel: DailyChannel) {
        guard var route = routes[channel.rawValue], let since = route.since, day < since,
              route.earlierDays.insert(day).inserted else { return }
        do { try store(route, for: channel) }
        catch { messages[channel] = error.localizedDescription }
    }

    func saved() {
        guard DailyChannel.allCases.contains(where: enabled) else { return }
        nextAutomatic = true
        startWorker()
    }

    func tick(now: Date) {
        let minute = Int(now.timeIntervalSince1970 / 60)
        guard lastMinute != minute else { return }
        lastMinute = minute
        saved()
    }

    func manual(_ day: Day) {
        guard DailyChannel.allCases.contains(where: enabled) else { return }
        for channel in DailyChannel.allCases { edited(day, channel: channel) }
        manualDays.insert(day)
        startWorker()
    }

    private func startWorker() {
        guard worker == nil, loadError == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            running = true
            defer {
                running = false
                worker = nil
            }
            while !Task.isCancelled, nextAutomatic || !manualDays.isEmpty {
                let manual = manualDays
                let automatic = nextAutomatic
                nextAutomatic = false
                manualDays.removeAll()
                guard let planner = savedPlanner?() else {
                    // An edit is waiting for its local save. flush() schedules the next pass.
                    manualDays.formUnion(manual)
                    return
                }
                gateway.beginPass()
                for channel in DailyChannel.allCases where enabled(channel) && !Task.isCancelled {
                    do {
                        try await reconcile(channel, planner: planner, manual: manual, automatic: automatic, now: clock())
                    } catch is CancellationError { return }
                    catch { messages[channel] = "待重试：\(error.localizedDescription)" }
                }
            }
        }
    }

    private func reconcile(_ channel: DailyChannel, planner: Planner, manual: Set<Day>, automatic: Bool, now: Date) async throws {
        guard let route = routes[channel.rawValue], let since = route.since, let destination = route.destination else { return }
        var days = manual
        if automatic {
            days.formUnion(planner.days.keys.map { Day(rawValue: $0) }.filter { $0 >= since || route.earlierDays.contains($0) })
            days.formUnion(route.receipts.values.map(\.day))
        }
        let linkedByDay = Dictionary(grouping: route.receipts.keys, by: { route.receipts[$0]!.day })
        var counts: [Day: [UUID: Int]] = [:]
        if channel == .reminders {
            for session in planner.sessions where session.outcome == .completed && days.contains(session.day) {
                counts[session.day, default: [:]][session.taskID, default: 0] += 1
            }
        }
        var wrote = false
        for day in days.sorted() {
            let record = planner.record(on: day)
            var desired: [String: DailyAppleItem] = [:]
            switch channel {
            case .reminders:
                for task in record.tasks where !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let item = DailyAppleItem.reminder(task, day: day, actual: counts[day]?[task.id] ?? 0)
                    desired[item.key] = item
                }
            case .reflections:
                if !record.reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let item = DailyAppleItem.reflection(record.reflection, day: day), let start = item.start {
                    if start > now && !manual.contains(day) && route.receipts[item.key] == nil { continue }
                    desired[item.key] = item
                }
            }
            for key in Set(desired.keys).union(linkedByDay[day] ?? []).sorted() {
                try Task.checkCancellation()
                let item = desired[key]
                let digest = try item.map { value in
                    let data = Data(destination.utf8) + (try encoder.encode(value))
                    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                }
                let old = route.receipts[key]
                if let digest, digest == old?.digest, !manual.contains(day) { continue }
                let pending = DailyReceipt(day: day, remoteID: old?.remoteID, digest: nil)
                if old == nil || old?.digest != nil { try setReceipt(pending, key: key, channel: channel) }
                let id = try await gateway.reconcile(item, key: key, day: day, channel: channel, destination: destination, knownID: old?.remoteID)
                try Task.checkCancellation()
                let receipt = id.map { DailyReceipt(day: day, remoteID: $0, digest: digest) }
                try setReceipt(receipt, key: key, channel: channel)
                wrote = true
            }
        }
        if wrote || !manual.isEmpty || messages[channel]?.hasPrefix("待重试") == true {
            messages[channel] = "已同步 · \(now.formatted(date: .omitted, time: .shortened))"
        }
    }

    private func setReceipt(_ receipt: DailyReceipt?, key: String, channel: DailyChannel) throws {
        guard var current = routes[channel.rawValue] else { throw CancellationError() }
        current.receipts[key] = receipt
        try store(current, for: channel)
    }

    func resetForRestore() throws {
        worker?.cancel()
        manualDays.removeAll()
        nextAutomatic = false
        if !routes.isEmpty || loadError != nil {
            try encoder.encode([String: DailyRoute]()).write(to: file, options: .atomic)
        }
        routes.removeAll()
        messages.removeAll()
        loadError = nil
    }
}
