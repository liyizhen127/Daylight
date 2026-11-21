import DaylightCore
import EventKit
import Foundation

enum DailyChannel: String, Codable, CaseIterable {
    case reminders, reflections

    var entity: EKEntityType { self == .reminders ? .reminder : .event }
    var destinationLabel: String { self == .reminders ? "提醒事项清单" : "反思日历" }
}

struct DailyAppleItem: Codable, Equatable {
    let key: String
    let day: Day
    let title: String
    let notes: String
    var completed: Bool?
    var start: Date?

    static func reminder(_ task: GoalTask, day: Day, actual: Int) -> Self {
        Self(key: task.id.uuidString, day: day,
             title: "\(task.title) · 🍅 \(actual)/\(task.estimatedPomodoros)",
             notes: "预估番茄：\(task.estimatedPomodoros)\n实际完成：\(actual)",
             completed: task.isCompleted)
    }

    static func reflection(_ text: String, day: Day) -> Self? {
        let calendar = Calendar.planner
        guard let date = day.date(calendar: calendar),
              let start = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: date) else { return nil }
        return Self(key: day.rawValue, day: day, title: "每日反思", notes: text, start: start)
    }
}

@MainActor protocol DailyAppleGateway {
    func authorize(_ channel: DailyChannel) async throws
    func destinations(_ channel: DailyChannel) -> [CalendarOption]
    func defaultID(_ channel: DailyChannel) -> String?
    func reconcile(_ item: DailyAppleItem?, key: String, day: Day, channel: DailyChannel,
                   destination: String, knownID: String?) async throws -> String?
    func beginPass()
}

enum DailyAppleError: LocalizedError {
    case access(DailyChannel), unavailable(DailyChannel), readFailed

    var errorDescription: String? {
        switch self {
        case .access(let channel):
            return "请在系统设置的「隐私与安全性」中允许 Daylight 访问\(channel == .reminders ? "提醒事项" : "日历")。"
        case .unavailable(let channel):
            return "所选\(channel.destinationLabel)不可写，请重新选择。"
        case .readFailed:
            return "未能读取苹果提醒事项，请稍后重试。"
        }
    }
}

@MainActor final class EventKitDailyGateway: DailyAppleGateway {
    private lazy var store = EKEventStore()
    private var remindersByMarker: [URL: EKReminder]?

    func authorize(_ channel: DailyChannel) async throws {
        guard EKEventStore.authorizationStatus(for: channel.entity) != .fullAccess else { return }
        let granted: Bool
        switch channel {
        case .reminders: granted = try await store.requestFullAccessToReminders()
        case .reflections: granted = try await store.requestFullAccessToEvents()
        }
        guard granted else { throw DailyAppleError.access(channel) }
    }

    func destinations(_ channel: DailyChannel) -> [CalendarOption] {
        guard EKEventStore.authorizationStatus(for: channel.entity) == .fullAccess else { return [] }
        return store.calendars(for: channel.entity).filter(\.allowsContentModifications).map {
            CalendarOption(id: $0.calendarIdentifier, title: "\($0.title) · \($0.source.title)")
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func defaultID(_ channel: DailyChannel) -> String? {
        guard EKEventStore.authorizationStatus(for: channel.entity) == .fullAccess else { return nil }
        let calendar = channel == .reminders ? store.defaultCalendarForNewReminders() : store.defaultCalendarForNewEvents
        return calendar?.calendarIdentifier
    }

    func beginPass() { remindersByMarker = nil }

    private func reminder(with marker: URL, knownID: String?) async throws -> EKReminder? {
        if let knownID, let reminder = store.calendarItem(withIdentifier: knownID) as? EKReminder, reminder.url == marker { return reminder }
        if remindersByMarker == nil {
            let predicate = store.predicateForReminders(in: nil)
            let results: [EKReminder]? = await withCheckedContinuation { continuation in
                store.fetchReminders(matching: predicate) { continuation.resume(returning: $0) }
            }
            guard let results else { throw DailyAppleError.readFailed }
            var index: [URL: EKReminder] = [:]
            for row in results {
                if let url = row.url, url.scheme == "daylight-daily", url.host == "reminders" { index[url] = row }
            }
            remindersByMarker = index
        }
        return remindersByMarker?[marker]
    }

    func reconcile(_ item: DailyAppleItem?, key: String, day: Day, channel: DailyChannel,
                   destination: String, knownID: String?) async throws -> String? {
        guard EKEventStore.authorizationStatus(for: channel.entity) == .fullAccess else { throw DailyAppleError.access(channel) }
        guard let marker = URL(string: "daylight-daily://\(channel.rawValue)/\(key)"), let date = day.date() else {
            throw PlannerError.invalidData
        }
        let target = store.calendar(withIdentifier: destination)
        if item != nil {
            let type: EKEntityMask = channel == .reminders ? .reminder : .event
            guard let target, target.allowsContentModifications, target.allowedEntityTypes.contains(type) else {
                throw DailyAppleError.unavailable(channel)
            }
        }
        switch channel {
        case .reminders:
            let existing = try await reminder(with: marker, knownID: knownID)
            try Task.checkCancellation()
            guard let item else {
                if let existing { try store.remove(existing, commit: true) }
                remindersByMarker?[marker] = nil
                return nil
            }
            let reminder = existing ?? EKReminder(eventStore: store)
            reminder.calendar = target
            reminder.title = item.title
            reminder.notes = item.notes
            reminder.url = marker
            var due = Calendar.planner.dateComponents([.year, .month, .day], from: date)
            due.calendar = Calendar.planner
            reminder.dueDateComponents = due
            if reminder.isCompleted != (item.completed == true) { reminder.isCompleted = item.completed == true }
            try store.save(reminder, commit: true)
            remindersByMarker?[marker] = reminder
            return reminder.calendarItemIdentifier
        case .reflections:
            let existing: EKEvent?
            if let knownID, let event = store.event(withIdentifier: knownID), event.url == marker {
                existing = event
            } else {
                guard let interval = Calendar.planner.dateInterval(of: .day, for: date) else { throw PlannerError.invalidData }
                let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
                existing = store.events(matching: predicate).first { $0.url == marker }
            }
            guard let item else {
                if let existing { try store.remove(existing, span: .thisEvent, commit: true) }
                return nil
            }
            guard let start = item.start else { throw PlannerError.invalidData }
            let event = existing ?? EKEvent(eventStore: store)
            event.calendar = target
            event.title = item.title
            event.notes = item.notes
            event.url = marker
            event.isAllDay = false
            event.timeZone = .current
            event.startDate = start
            event.endDate = start.addingTimeInterval(15 * 60)
            try store.save(event, span: .thisEvent, commit: true)
            guard let id = event.eventIdentifier else { throw CalendarSyncError.missingIdentifier }
            return id
        }
    }
}
