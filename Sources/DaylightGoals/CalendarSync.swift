import EventKit
import Foundation
import DaylightCore

struct CalendarOption: Identifiable, Equatable {
    let id: String
    let title: String
}
@MainActor protocol CalendarGateway {
    var hasAccess: Bool { get }
    func requestAccess() async throws -> Bool
    func calendars() -> [CalendarOption]
    var defaultCalendarID: String? { get }
    func save(_ session: FocusSession, calendarID: String?) throws -> String
}
enum CalendarSyncError: LocalizedError {
    case denied, missingCalendar, missingIdentifier
    var errorDescription: String? {
        switch self {
        case .denied: return "日历访问尚未授权。请在系统设置 → 隐私与安全性 → 日历中允许Daylight访问。"
        case .missingIdentifier: return "日历尚未返回记录编号，请稍后重试。"
        case .missingCalendar: return "所选日历已不可写或不存在，请在番茄设置中重新选择日历。"
        }
    }
}
@MainActor final class EventKitCalendarGateway: CalendarGateway {
    private let store = EKEventStore()
    var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    var defaultCalendarID: String? { hasAccess ? store.defaultCalendarForNewEvents?.calendarIdentifier : nil }
    func requestAccess() async throws -> Bool { try await store.requestFullAccessToEvents() }
    func calendars() -> [CalendarOption] {
        guard hasAccess else { return [] }
        return store.calendars(for: .event).filter(\.allowsContentModifications).map {
            CalendarOption(id: $0.calendarIdentifier, title: "\($0.title) · \($0.source.title)")
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    func save(_ session: FocusSession, calendarID: String?) throws -> String {
        guard hasAccess else { throw CalendarSyncError.denied }
        // The marker is saved with the event itself. A retry after a crash never creates it twice.
        if let id = session.calendarEventIdentifier, let existing = store.event(withIdentifier: id), let eventID = existing.eventIdentifier { return eventID }
        let predicate = store.predicateForEvents(withStart: session.startedAt.addingTimeInterval(-1), end: session.endedAt.addingTimeInterval(1), calendars: nil)
        if let existing = store.events(matching: predicate).first(where: { $0.url == session.calendarURL }) {
            guard let id = existing.eventIdentifier else { throw CalendarSyncError.missingIdentifier }
            return id
        }
        guard let id = calendarID, let calendar = store.calendar(withIdentifier: id), calendar.allowsContentModifications else { throw CalendarSyncError.missingCalendar }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar; event.title = session.title
        event.startDate = session.startedAt; event.endDate = session.endedAt
        event.notes = session.calendarNotes; event.url = session.calendarURL
        event.isAllDay = false; event.alarms = []; event.timeZone = .current
        try store.save(event, span: .thisEvent, commit: true)
        guard let id = event.eventIdentifier else { throw CalendarSyncError.missingIdentifier }
        return id
    }
}
