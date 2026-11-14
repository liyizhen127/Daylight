import Foundation

/// Civil dates have no UTC offset. Week keys are Monday's civil date, including at year boundaries.
public struct Day: RawRepresentable, Codable, Hashable, Comparable, Identifiable, Sendable {
    public let rawValue: String
    public var id: String { rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    public init(_ date: Date, calendar: Calendar = .planner) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        rawValue = String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    public func date(calendar: Calendar = .planner) -> Date? {
        let p = rawValue.split(separator: "-", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard p.count == 3, rawValue.count == 10, (1...9999).contains(p[0]),
              let date = calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12)),
              Day(date, calendar: calendar) == self else { return nil }
        return date
    }
    public func adding(_ days: Int, calendar: Calendar = .planner) -> Day {
        guard let date = date(calendar: calendar),
              let next = calendar.date(byAdding: .day, value: days, to: date) else { return self }
        return Day(next, calendar: calendar)
    }
    public func week(calendar: Calendar = .planner) -> [Day] {
        guard let date = date(calendar: calendar) else { return [] }
        let weekday = calendar.component(.weekday, from: date)
        let monday = adding(-((weekday + 5) % 7), calendar: calendar)
        return (0..<7).map { monday.adding($0, calendar: calendar) }
    }
    public var monthKey: String { String(rawValue.prefix(7)) }
    public var weekKey: String { week().first?.rawValue ?? rawValue }
    public var number: String { String(Int(rawValue.suffix(2)) ?? 1) }
    public var short: String { "\(Int(rawValue.dropFirst(5).prefix(2)) ?? 1)/\(number)" }
}

public extension Calendar {
    static var planner: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "zh_CN")
        c.timeZone = .current
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }
}

public enum GoalScope: String, CaseIterable, Sendable { case longTerm, month, week }
public enum DailyField: String, Sendable { case expected, actual }

public struct GoalTask: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var isCompleted: Bool
    public var estimatedPomodoros: Int
    public init(id: UUID = UUID(), title: String, isCompleted: Bool = false, estimatedPomodoros: Int = 1) {
        self.id = id; self.title = title; self.isCompleted = isCompleted; self.estimatedPomodoros = estimatedPomodoros
    }
    public static func parse(_ text: String, preserving old: [GoalTask] = []) -> [GoalTask] {
        var remaining = old
        return text.components(separatedBy: .newlines).compactMap { line in
            var title = line.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return nil }
            var checked: Bool?
            for prefix in ["- [ ] ", "- [] ", "- [x] ", "- [X] ", "[ ] ", "[x] ", "[X] ", "- ", "• "] where title.hasPrefix(prefix) {
                checked = prefix.lowercased().contains("[x]") ? true : prefix.contains("[") ? false : nil
                title = String(title.dropFirst(prefix.count)); break
            }
            if let index = remaining.firstIndex(where: { $0.title == title }) {
                var task = remaining.remove(at: index)
                if let checked { task.isCompleted = checked }
                return task
            }
            return GoalTask(title: title, isCompleted: checked ?? false)
        }
    }
    public var markdown: String { "- [\(isCompleted ? "x" : " ")] \(title)" }
}

public struct DayRecord: Codable, Equatable, Sendable {
    public var tasks: [GoalTask]
    public var reflection: String
    public var modifiedAt: Date?
    public var expected: String {
        get { tasks.map(\.title).joined(separator: "\n") }
        set { tasks = GoalTask.parse(newValue, preserving: tasks) }
    }
    public var actual: String { get { reflection } set { reflection = newValue } }
    public init(expected: String = "", actual: String = "", modifiedAt: Date? = nil) {
        tasks = GoalTask.parse(expected); reflection = actual; self.modifiedAt = modifiedAt
    }
    public var hasPlan: Bool { !tasks.isEmpty }
    public var hasReview: Bool { !reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var isEmpty: Bool { tasks.isEmpty && reflection.isEmpty }
    enum CodingKeys: String, CodingKey { case tasks, reflection, expected, actual, modifiedAt }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.tasks) {
            tasks = try c.decode([GoalTask].self, forKey: .tasks)
            reflection = try c.decode(String.self, forKey: .reflection)
        } else {
            tasks = GoalTask.parse(try c.decode(String.self, forKey: .expected))
            reflection = try c.decode(String.self, forKey: .actual)
        }
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(tasks, forKey: .tasks); try c.encode(reflection, forKey: .reflection)
        try c.encodeIfPresent(modifiedAt, forKey: .modifiedAt)
    }
}

public enum PlannerError: Error, LocalizedError {
    case unsupportedVersion, invalidData, alreadyOpen, unavailableDirectory
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "这份数据来自更新的应用版本，请先升级Daylight。"
        case .invalidData: return "数据格式不正确。原文件已保留，请从有效的备份恢复。"
        case .alreadyOpen: return "此数据目录已由另一个Daylight窗口使用，请先关闭另一个应用实例。"
        case .unavailableDirectory: return "无法访问数据目录，请检查文件夹权限。"
        }
    }
}

public struct Planner: Codable, Equatable, Sendable {
    public var schemaVersion = 3
    public var longTermTasks: [GoalTask] = []
    public var monthTasks: [String: [GoalTask]] = [:]
    public var weekTasks: [String: [GoalTask]] = [:]
    public var days: [String: DayRecord] = [:]
    public var taskDrafts: [String: String] = [:]
    public var pomodoro = PomodoroSettings()
    public var sessions: [FocusSession] = []
    public var activeTimer: ActiveTimer?
    public var cycleCompleted = 0
    public init() {}
    // Text adapters for legacy exports and integrations. Task identity is authoritative in v2.
    public var longTerm: String {
        get { longTermTasks.map(\.title).joined(separator: "\n") }
        set { longTermTasks = GoalTask.parse(newValue, preserving: longTermTasks) }
    }
    public var months: [String: String] {
        get { monthTasks.mapValues { $0.map(\.title).joined(separator: "\n") } }
        set { monthTasks = newValue.mapValues { GoalTask.parse($0) } }
    }
    public var weeks: [String: String] {
        get { weekTasks.mapValues { $0.map(\.title).joined(separator: "\n") } }
        set { weekTasks = newValue.mapValues { GoalTask.parse($0) } }
    }
    enum CodingKeys: String, CodingKey {
        case schemaVersion, longTerm, months, weeks, longTermTasks, monthTasks, weekTasks, days, taskDrafts, pomodoro, sessions, activeTimer, cycleCompleted
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .schemaVersion)
        guard (1...3).contains(version) else { throw PlannerError.unsupportedVersion }
        days = try c.decode([String: DayRecord].self, forKey: .days)
        if version == 1 {
            longTermTasks = GoalTask.parse(try c.decode(String.self, forKey: .longTerm))
            monthTasks = try c.decode([String: String].self, forKey: .months).mapValues { GoalTask.parse($0) }
            weekTasks = try c.decode([String: String].self, forKey: .weeks).mapValues { GoalTask.parse($0) }
        } else {
            longTermTasks = try c.decode([GoalTask].self, forKey: .longTermTasks)
            monthTasks = try c.decode([String: [GoalTask]].self, forKey: .monthTasks)
            weekTasks = try c.decode([String: [GoalTask]].self, forKey: .weekTasks)
            taskDrafts = try c.decodeIfPresent([String: String].self, forKey: .taskDrafts) ?? [:]
            pomodoro = try c.decode(PomodoroSettings.self, forKey: .pomodoro)
            sessions = try c.decode([FocusSession].self, forKey: .sessions)
            activeTimer = try c.decodeIfPresent(ActiveTimer.self, forKey: .activeTimer)
            cycleCompleted = try c.decode(Int.self, forKey: .cycleCompleted)
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(longTermTasks, forKey: .longTermTasks)
        try c.encode(monthTasks, forKey: .monthTasks); try c.encode(weekTasks, forKey: .weekTasks)
        try c.encode(taskDrafts, forKey: .taskDrafts)
        try c.encode(days, forKey: .days); try c.encode(pomodoro, forKey: .pomodoro)
        try c.encode(sessions, forKey: .sessions); try c.encodeIfPresent(activeTimer, forKey: .activeTimer)
        try c.encode(cycleCompleted, forKey: .cycleCompleted)
    }
    public func tasks(_ scope: GoalScope?, on day: Day) -> [GoalTask] {
        switch scope {
        case .longTerm: return longTermTasks
        case .month: return monthTasks[day.monthKey] ?? []
        case .week: return weekTasks[day.weekKey] ?? []
        case nil: return record(on: day).tasks
        }
    }
    public mutating func setTasks(_ tasks: [GoalTask], scope: GoalScope?, on day: Day, now: Date = Date()) {
        switch scope {
        case .longTerm: longTermTasks = tasks
        case .month: monthTasks[day.monthKey] = tasks.isEmpty ? nil : tasks
        case .week: weekTasks[day.weekKey] = tasks.isEmpty ? nil : tasks
        case nil:
            var r = record(on: day); r.tasks = tasks; r.modifiedAt = now
            days[day.rawValue] = r.isEmpty ? nil : r
        }
    }
    public func goal(_ scope: GoalScope, on day: Day) -> String { tasks(scope, on: day).map(\.title).joined(separator: "\n") }
    public mutating func setGoal(_ scope: GoalScope, on day: Day, text: String) {
        setTasks(GoalTask.parse(text, preserving: tasks(scope, on: day)), scope: scope, on: day)
    }
    public func record(on day: Day) -> DayRecord { days[day.rawValue] ?? DayRecord() }
    public mutating func setDaily(_ field: DailyField, on day: Day, text: String, now: Date = Date()) {
        var r = record(on: day)
        switch field { case .expected: r.expected = text; case .actual: r.reflection = text }
        r.modifiedAt = now; days[day.rawValue] = r.isEmpty ? nil : r
    }
    public func actualPomodoros(taskID: UUID, on day: Day) -> Int {
        sessions.filter { $0.taskID == taskID && $0.day == day && $0.outcome == .completed }.count
    }
    public func completedPomodoros(on day: Day) -> Int {
        sessions.filter { $0.outcome == .completed && Day($0.endedAt) == day }.count
    }
    public func validate() throws {
        guard schemaVersion == 3 else { throw PlannerError.unsupportedVersion }
        for key in monthTasks.keys {
            guard key.count == 7, Day(rawValue: key + "-01").date() != nil else { throw PlannerError.invalidData }
        }
        for key in weekTasks.keys {
            let day = Day(rawValue: key)
            guard day.date() != nil, day.weekKey == key else { throw PlannerError.invalidData }
        }
        for (key, value) in days {
            guard Day(rawValue: key).date() != nil, value.modifiedAt?.timeIntervalSince1970.isFinite ?? true else { throw PlannerError.invalidData }
        }
        let allTasks = longTermTasks + monthTasks.values.flatMap { $0 } + weekTasks.values.flatMap { $0 } + days.values.flatMap(\.tasks)
        guard Set(allTasks.map(\.id)).count == allTasks.count,
              allTasks.allSatisfy({ (0...999).contains($0.estimatedPomodoros) }),
              pomodoro.isValid, cycleCompleted >= 0,
              Set(sessions.map(\.id)).count == sessions.count,
              sessions.allSatisfy({ $0.isValid }), activeTimer?.isValid ?? true else { throw PlannerError.invalidData }
    }
    public func markdown(for day: Day) -> String {
        let r = record(on: day)
        return "# Daylight · \(day.rawValue)\n\n## 长期目标\n\n\(checklist(longTermTasks))\n\n## 月目标 · \(day.monthKey)\n\n\(checklist(tasks(.month, on: day)))\n\n## 周目标 · \(day.weekKey)\n\n\(checklist(tasks(.week, on: day)))\n\n## 预期完成\n\n\(dailyChecklist(on: day))\n\n## 每日反思\n\n\(r.reflection)\n"
    }
    private func checklist(_ tasks: [GoalTask]) -> String { tasks.isEmpty ? "（尚未填写）" : tasks.map(\.markdown).joined(separator: "\n") }
    public func dailyChecklist(on day: Day) -> String {
        record(on: day).tasks.map { "\($0.markdown)  🍅 \(actualPomodoros(taskID: $0.id, on: day))/\($0.estimatedPomodoros)" }.joined(separator: "\n")
    }
    public func weekMarkdown(for day: Day) -> String {
        let week = day.week()
        var parts = ["# Daylight · 一周回顾 · \(week.first!.rawValue) — \(week.last!.rawValue)", "## 长期目标\n\n\(checklist(longTermTasks))", "## 周目标\n\n\(checklist(tasks(.week, on: day)))"]
        for month in Set(week.map(\.monthKey)).sorted() { parts.append("## 月目标 · \(month)\n\n\(checklist(monthTasks[month] ?? []))") }
        for d in week { parts.append("## \(d.rawValue)\n\n### 预期完成\n\n\(dailyChecklist(on: d))\n\n### 每日反思\n\n\(record(on: d).reflection)") }
        return parts.joined(separator: "\n\n") + "\n"
    }
}
