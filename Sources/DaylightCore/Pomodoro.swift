import Foundation

public struct PomodoroSettings: Codable, Equatable, Sendable {
    public var focusMinutes = 25
    public var shortBreakMinutes = 5
    public var longBreakMinutes = 15
    public var longBreakEvery = 4
    public var calendarEnabled = false
    public var calendarIdentifier: String?
    public init() {}
    public var isValid: Bool {
        (1...180).contains(focusMinutes) && (1...60).contains(shortBreakMinutes) && (1...120).contains(longBreakMinutes) && (1...12).contains(longBreakEvery)
    }
}
public enum TimerPhase: String, Codable, Sendable { case focus, shortBreak, longBreak
    public var title: String { self == .focus ? "专注" : self == .shortBreak ? "休息" : "长休息" }
}
public enum FocusOutcome: String, Codable, Sendable { case completed, interrupted }
public enum FocusRating: String, Codable, CaseIterable, Sendable {
    case great, okay, poor
    public var title: String { switch self { case .great: return "很好"; case .okay: return "一般"; case .poor: return "差劲" } }
}
public struct FocusReview: Codable, Equatable, Sendable {
    public var rating: FocusRating?
    public var reflection: String
    public var submittedAt: Date?
    public init(rating: FocusRating? = nil, reflection: String = "", submittedAt: Date? = nil) {
        self.rating = rating; self.reflection = reflection; self.submittedAt = submittedAt
    }
    public var isValid: Bool { (submittedAt?.timeIntervalSince1970.isFinite ?? true) && (submittedAt == nil || rating != nil) }
}
public enum CalendarSyncState: String, Codable, Sendable { case notRequested, pending, synced }
public struct ActiveTimer: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var taskID: UUID
    public var day: Day
    public var title: String
    public var phase: TimerPhase
    public var startedAt: Date
    public var endsAt: Date
    public init(taskID: UUID, day: Day, title: String, phase: TimerPhase, startedAt: Date, seconds: TimeInterval) {
        id = UUID(); self.taskID = taskID; self.day = day; self.title = title; self.phase = phase
        self.startedAt = startedAt; endsAt = startedAt.addingTimeInterval(seconds)
    }
    public func isOvertime(at now: Date) -> Bool { phase == .focus && now >= endsAt }
    public func overtimeSeconds(at now: Date) -> Int { phase == .focus ? max(0, Int(floor(now.timeIntervalSince(endsAt)))) : 0 }
    public func remaining(at now: Date) -> Int { max(0, Int(ceil(endsAt.timeIntervalSince(now)))) }
    public var isValid: Bool { day.date() != nil && startedAt.timeIntervalSince1970.isFinite && endsAt.timeIntervalSince1970.isFinite && endsAt > startedAt && endsAt.timeIntervalSince(startedAt) <= 180 * 60 }
}
public struct FocusSession: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var taskID: UUID
    public var day: Day
    public var title: String
    public var startedAt: Date
    public var endedAt: Date
    public var plannedEndsAt: Date?
    public var review: FocusReview?
    public var outcome: FocusOutcome
    public var calendarState: CalendarSyncState
    public var calendarIdentifier: String?
    public var calendarEventIdentifier: String?
    public init(timer: ActiveTimer, endedAt: Date, outcome: FocusOutcome, settings: PomodoroSettings) {
        id = timer.id; taskID = timer.taskID; day = timer.day; title = timer.title
        startedAt = timer.startedAt; self.endedAt = max(endedAt, startedAt.addingTimeInterval(1))
        plannedEndsAt = timer.endsAt
        review = outcome == .completed ? FocusReview() : nil
        self.outcome = outcome; calendarState = settings.calendarEnabled ? .pending : .notRequested
        calendarIdentifier = settings.calendarIdentifier
    }
    public var durationSeconds: Int { max(1, Int(endedAt.timeIntervalSince(startedAt))) }
    public var overtimeSeconds: Int { plannedEndsAt.map { max(0, Int(floor(endedAt.timeIntervalSince($0)))) } ?? 0 }
    public var isValid: Bool {
        day.date() != nil && startedAt.timeIntervalSince1970.isFinite && endedAt.timeIntervalSince1970.isFinite && endedAt > startedAt
            && (plannedEndsAt.map { $0.timeIntervalSince1970.isFinite && $0 > startedAt && $0.timeIntervalSince(startedAt) <= 180 * 60 } ?? true)
            && (review?.isValid ?? true)
    }
    public var calendarURL: URL { URL(string: "daylight-focus://session/\(id.uuidString)")! }
    public var calendarNotes: String { "Daylight番茄钟 · \(outcome == .completed ? "已完成" : "已中断")\n任务日期：\(day.rawValue)\n实际专注：\(max(1, Int(endedAt.timeIntervalSince(startedAt)))) 秒\n记录编号：\(id.uuidString)" }
}
public enum TimerTransition: Equatable { case breakCompleted }
public extension Planner {
    @discardableResult mutating func startFocus(taskID: UUID, on day: Day, now: Date = Date()) -> Bool {
        guard activeTimer == nil, let task = record(on: day).tasks.first(where: { $0.id == taskID }), !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        activeTimer = ActiveTimer(taskID: task.id, day: day, title: task.title, phase: .focus, startedAt: now, seconds: TimeInterval(pomodoro.focusMinutes * 60))
        return true
    }
    /// A focus deadline only changes its presentation. The user decides when focus ends.
    @discardableResult mutating func advanceTimer(now: Date = Date()) -> [TimerTransition] {
        guard let active = activeTimer, active.phase != .focus, now >= active.endsAt else { return [] }
        activeTimer = nil
        return [.breakCompleted]
    }
    /// Finalize exactly one focus session, including overtime, and start a full break from this click.
    @discardableResult mutating func startBreak(now: Date = Date()) -> UUID? {
        guard let active = activeTimer, active.isOvertime(at: now), !sessions.contains(where: { $0.id == active.id }) else { return nil }
        finishFocus(active, now: now, outcome: .completed)
        let long = cycleCompleted >= pomodoro.longBreakEvery
        if long { cycleCompleted = 0 }
        activeTimer = ActiveTimer(taskID: active.taskID, day: active.day, title: active.title, phase: long ? .longBreak : .shortBreak,
                                  startedAt: now, seconds: TimeInterval((long ? pomodoro.longBreakMinutes : pomodoro.shortBreakMinutes) * 60))
        return active.id
    }
    private mutating func finishFocus(_ active: ActiveTimer, now: Date, outcome: FocusOutcome) {
        sessions.append(FocusSession(timer: active, endedAt: now, outcome: outcome, settings: pomodoro))
        if outcome == .completed { cycleCompleted += 1 }
    }
    @discardableResult mutating func stopTimer(now: Date = Date()) -> Bool {
        let transitions = advanceTimer(now: now)
        guard let active = activeTimer else { return !transitions.isEmpty }
        if active.phase == .focus && !sessions.contains(where: { $0.id == active.id }) {
            finishFocus(active, now: now, outcome: active.isOvertime(at: now) ? .completed : .interrupted)
        }
        activeTimer = nil
        return true
    }
}
