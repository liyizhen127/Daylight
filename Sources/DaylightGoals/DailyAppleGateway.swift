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
        let title = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let calendar = Calendar.planner
        guard !title.isEmpty, let date = day.date(calendar: calendar),
              let start = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: date) else { return nil }
        return Self(key: day.rawValue, day: day, title: title, notes: text, start: start)
    }
}

struct DailyDestinations {
    let visibleCount: Int
    let writable: [CalendarOption]
    let defaultID: String?
}

@MainActor protocol DailyAppleGateway {
    func authorize(_ channel: DailyChannel) async throws
    func destinations(_ channel: DailyChannel, refresh: Bool) -> DailyDestinations
    func reconcile(_ item: DailyAppleItem?, key: String, day: Day, channel: DailyChannel,
                   destination: String, knownID: String?) async throws -> String?
    func beginPass()
}

enum DailyAppleError: LocalizedError {
    case access(DailyChannel), restricted(DailyChannel), noDestinations(DailyChannel), allReadOnly(DailyChannel)
    case missingDestination(DailyChannel), readOnly(DailyChannel), readFailed

    var errorDescription: String? {
        switch self {
        case .access(let channel):
            return "请在系统设置的「隐私与安全性」中允许 Daylight 访问\(channel == .reminders ? "提醒事项" : "日历")。"
        case .restricted(let channel):
            return "系统限制了对\(channel.destinationLabel)的访问，请检查此 Mac 的访问限制。"
        case .noDestinations(.reminders):
            return "系统没有返回提醒事项清单。请在「提醒事项」中确认有一个可以添加提醒的普通清单，然后重试。"
        case .noDestinations(.reflections):
            return "系统没有返回日历。请在「日历」中确认有一个可以添加日程的日历，然后重试。"
        case .allReadOnly(let channel):
            return "目前可见的\(channel.destinationLabel)均为只读。请创建可编辑的\(channel.destinationLabel)，或向共享者申请编辑权限，然后重试。"
        case .missingDestination(let channel):
            return "找不到之前选择的\(channel.destinationLabel)。请确认账户已启用，或关闭同步后重新选择。"
        case .readOnly(let channel):
            return "之前选择的\(channel.destinationLabel)目前为只读。请检查编辑权限，或关闭同步后重新选择。"
        case .readFailed:
            return "未能读取苹果提醒事项，请稍后重试。"
        }
    }
}

@MainActor final class EventKitDailyGateway: DailyAppleGateway {
    private lazy var store = EKEventStore()
    private var remindersByMarker: [URL: EKReminder]?

    func authorize(_ channel: DailyChannel) async throws {
        switch EKEventStore.authorizationStatus(for: channel.entity) {
        case .fullAccess: return
        case .restricted: throw DailyAppleError.restricted(channel)
        default: break
        }
        let granted: Bool
        switch channel {
        case .reminders: granted = try await store.requestFullAccessToReminders()
        case .reflections: granted = try await store.requestFullAccessToEvents()
        }
        guard granted else { throw DailyAppleError.access(channel) }
    }

    private func defaultCalendar(_ channel: DailyChannel) -> EKCalendar? {
        channel == .reminders ? store.defaultCalendarForNewReminders() : store.defaultCalendarForNewEvents
    }

    private func calendars(_ channel: DailyChannel, including preferred: EKCalendar?) -> [EKCalendar] {
        var calendars = store.calendars(for: channel.entity)
        if let preferred, !calendars.contains(where: { $0.calendarIdentifier == preferred.calendarIdentifier }) {
            calendars.append(preferred)
        }
        return calendars
    }

    func destinations(_ channel: DailyChannel, refresh: Bool) -> DailyDestinations {
        // On explicit selection, EventKit has just granted access on this store.
        // Rechecking the static status here can discard a successful grant.
        if refresh {
            store.refreshSourcesIfNecessary()
        } else if EKEventStore.authorizationStatus(for: channel.entity) != .fullAccess {
            return DailyDestinations(visibleCount: 0, writable: [], defaultID: nil)
        }
        let preferred = defaultCalendar(channel)
        let calendars = calendars(channel, including: preferred)
        let writable = calendars.filter(\.allowsContentModifications).map {
            CalendarOption(id: $0.calendarIdentifier, title: "\($0.title) · \($0.source.title)")
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        return DailyDestinations(visibleCount: calendars.count, writable: writable, defaultID: preferred?.calendarIdentifier)
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
        try await authorize(channel)
        guard let marker = URL(string: "daylight-daily://\(channel.rawValue)/\(key)"), let date = day.date() else {
            throw PlannerError.invalidData
        }
        var target: EKCalendar?
        if item != nil {
            let available = calendars(channel, including: defaultCalendar(channel))
            guard let match = available.first(where: { $0.calendarIdentifier == destination }) else {
                throw DailyAppleError.missingDestination(channel)
            }
            guard match.allowsContentModifications else { throw DailyAppleError.readOnly(channel) }
            target = match
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
