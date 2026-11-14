import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DaylightCore

@MainActor final class AppModel: ObservableObject {
    @Published private(set) var planner = Planner()
    @Published var selectedDay = Day(Date())
    @Published var today = Day(Date())
    @Published var calendarMonth = Day(Date())
    @Published var isReview = false
    @Published var isPinned = false
    @Published var ropePinned = false
    @Published var ropeVisible = false
    @Published var saveStatus = "所有更改已保存"
    @Published var saveError: String?
    @Published var loadFailed = false
    @Published var showingHelp = false
    @Published var showingPomodoroSettings = false
    @Published var timerNow = Date()
    @Published var timerMessage = ""
    @Published private(set) var reviewSessionID: UUID?
    @Published var calendarMessage: String?
    @Published var calendarOptions: [CalendarOption] = []
    @Published var requestingCalendar = false
    let calendarGateway: CalendarGateway
    private var lastSyncAttempt = Date.distantPast
    var onTimerChange: (() -> Void)?
    let disk: PlannerDisk
    var onPin: ((Bool) -> Void)?
    private var pendingSave: DispatchWorkItem?
    private var dirty = false

    init(directory: URL, demo: Bool = false, calendarGateway: CalendarGateway? = nil) throws {
        self.calendarGateway = calendarGateway ?? EventKitCalendarGateway()
        disk = try PlannerDisk(directory: directory)
        do {
            planner = try disk.load()
            reviewSessionID = planner.sessions.last { $0.review != nil && $0.review?.submittedAt == nil }?.id
            if demo && !FileManager.default.fileExists(atPath: disk.file.path) {
                seedDemo()
                try disk.save(planner)
            }
        } catch {
            loadFailed = true
            saveError = "读取失败：\(error.localizedDescription)"
            saveStatus = "数据未载入"
        }
    }
    func goalBinding(_ scope: GoalScope, day: Day) -> Binding<String> {
        Binding(get: { self.planner.goal(scope, on: day) }, set: { text in
            guard !self.loadFailed, self.planner.goal(scope, on: day) != text else { return }
            self.planner.setGoal(scope, on: day, text: text)
            self.scheduleSave()
        })
    }
    func dailyBinding(_ field: DailyField, day: Day) -> Binding<String> {
        Binding(get: {
            let record = self.planner.record(on: day)
            return field == .expected ? record.expected : record.actual
        }, set: { text in
            guard !self.loadFailed else { return }
            let record = self.planner.record(on: day)
            guard (field == .expected ? record.expected : record.actual) != text else { return }
            self.planner.setDaily(field, on: day, text: text)
            self.scheduleSave()
        })
    }
    func taskTitleBinding(_ id: UUID, scope: GoalScope?, day: Day) -> Binding<String> {
        Binding(get: { self.planner.tasks(scope, on: day).first { $0.id == id }?.title ?? "" }, set: { text in
            self.updateTask(id, scope: scope, day: day) { $0.title = text }
        })
    }
    func updateTask(_ id: UUID, scope: GoalScope?, day: Day, change: (inout GoalTask) -> Void) {
        guard !loadFailed else { return }
        var tasks = planner.tasks(scope, on: day)
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        let old = tasks[i]; change(&tasks[i]); guard tasks[i] != old else { return }
        planner.setTasks(tasks, scope: scope, on: day)
        if scope == nil, planner.activeTimer?.taskID == id, planner.activeTimer?.day == day, planner.activeTimer?.phase == .focus, !tasks[i].title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            planner.activeTimer?.title = tasks[i].title
        }
        scheduleSave(); onTimerChange?()
    }
    func draftBinding(scope: GoalScope?, day: Day) -> Binding<String> {
        let key = scope == .longTerm ? "longTerm" : scope == .month ? "month-\(day.monthKey)" : scope == .week ? "week-\(day.weekKey)" : "day-\(day.rawValue)"
        return Binding(get: { self.planner.taskDrafts[key] ?? "" }, set: { value in
            guard !self.loadFailed, self.planner.taskDrafts[key] ?? "" != value else { return }
            self.planner.taskDrafts[key] = value.isEmpty ? nil : value
            self.scheduleSave()
        })
    }
    func addTasks(_ text: String, scope: GoalScope?, day: Day) {
        guard !loadFailed else { return }
        let added = GoalTask.parse(text)
        guard !added.isEmpty else { return }
        planner.setTasks(planner.tasks(scope, on: day) + added, scope: scope, on: day)
        scheduleSave()
    }
    func removeTask(_ id: UUID, scope: GoalScope?, day: Day) {
        guard !loadFailed else { return }
        commitActiveTextEditing()
        planner.setTasks(planner.tasks(scope, on: day).filter { $0.id != id }, scope: scope, on: day)
        scheduleSave()
    }
    func startFocus(_ taskID: UUID, day: Day, now: Date = Date()) {
        guard !loadFailed else { return }
        commitActiveTextEditing()
        tick(now: now)
        guard planner.activeTimer == nil else { timerMessage = "请先结束当前专注或跳过休息，再开始新番茄。"; return }
        guard planner.startFocus(taskID: taskID, on: day, now: now) else { return }
        timerNow = now; timerMessage = "专注中，慢慢靠近目标。"
        scheduleSave(); _ = flush(); onTimerChange?()
    }
    func stopTimer(now: Date = Date()) {
        guard !loadFailed else { return }
        let wasFocus = planner.activeTimer?.phase == .focus
        let finishingID = planner.activeTimer?.id
        guard planner.stopTimer(now: now) else { return }
        if let id = finishingID, planner.sessions.contains(where: { $0.id == id && $0.outcome == .completed }) { reviewSessionID = id }
        timerNow = now
        timerMessage = wasFocus ? "本次专注已结束，实际时段已记录。" : "休息已结束，可以选择下一项任务。"
        scheduleSave(); if flush() { syncCalendar() }; onTimerChange?()
    }
    func startBreak(now: Date = Date()) {
        guard !loadFailed else { return }
        commitActiveTextEditing()
        guard let id = planner.startBreak(now: now) else { return }
        timerNow = now; reviewSessionID = id
        timerMessage = "专注已记录，休息已开始。可以写下这颗番茄的评价。"
        scheduleSave(); if flush() { syncCalendar(now: now) }; onTimerChange?()
    }
    func session(_ id: UUID) -> FocusSession? { planner.sessions.first { $0.id == id } }
    func showReview(_ id: UUID) {
        guard !loadFailed, let i = planner.sessions.firstIndex(where: { $0.id == id && $0.outcome == .completed }) else { return }
        commitActiveTextEditing()
        if planner.sessions[i].review == nil { planner.sessions[i].review = FocusReview(); scheduleSave() }
        reviewSessionID = id; onTimerChange?()
    }
    func setReviewRating(_ rating: FocusRating, sessionID: UUID) {
        updateReview(sessionID) { $0.rating = rating }
    }
    func reviewReflectionBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { self.session(id)?.review?.reflection ?? "" }, set: { text in
            self.updateReview(id) { $0.reflection = text }
        })
    }
    private func updateReview(_ id: UUID, change: (inout FocusReview) -> Void) {
        guard !loadFailed, let i = planner.sessions.firstIndex(where: { $0.id == id && $0.outcome == .completed }) else { return }
        var review = planner.sessions[i].review ?? FocusReview()
        change(&review)
        guard review != planner.sessions[i].review else { return }
        planner.sessions[i].review = review; scheduleSave()
    }
    @discardableResult func submitReview(_ id: UUID, now: Date = Date()) -> Bool {
        commitActiveTextEditing()
        guard session(id)?.review?.rating != nil else { return false }
        updateReview(id) { $0.submittedAt = now }
        guard flush() else { return false }
        if reviewSessionID == id { reviewSessionID = nil }
        onTimerChange?(); return true
    }
    @discardableResult func dismissReview() -> Bool {
        commitActiveTextEditing()
        guard flush() else { return false }
        reviewSessionID = nil; onTimerChange?(); return true
    }
    func tick(now: Date = Date()) {
        refreshClock()
        if planner.activeTimer != nil { timerNow = now }
        guard !loadFailed else { return }
        let transitions = planner.advanceTimer(now: now)
        if !transitions.isEmpty {
            timerMessage = "休息结束，准备好后开始下一颗番茄。"
            scheduleSave(); _ = flush()
        }
        if now.timeIntervalSince(lastSyncAttempt) >= 60 && planner.sessions.contains(where: { $0.calendarState == .pending }) { syncCalendar(now: now) }
        onTimerChange?()
    }
    func updatePomodoroSettings(_ change: (inout PomodoroSettings) -> Void) {
        guard !loadFailed else { return }
        var settings = planner.pomodoro; change(&settings)
        guard settings.isValid, settings != planner.pomodoro else { return }
        planner.pomodoro = settings; scheduleSave()
    }
    func refreshCalendars() { calendarOptions = calendarGateway.calendars() }
    func enableCalendar(_ enabled: Bool) {
        guard !loadFailed else { return }
        if !enabled { updatePomodoroSettings { $0.calendarEnabled = false }; calendarMessage = nil; return }
        guard !requestingCalendar else { return }
        requestingCalendar = true
        Task { @MainActor in
            defer { requestingCalendar = false }
            do {
                let access = calendarGateway.hasAccess ? true : try await calendarGateway.requestAccess()
                guard access else { throw CalendarSyncError.denied }
                refreshCalendars()
                guard let selected = calendarOptions.first(where: { $0.id == planner.pomodoro.calendarIdentifier })?.id
                        ?? calendarOptions.first(where: { $0.id == calendarGateway.defaultCalendarID })?.id ?? calendarOptions.first?.id else { throw CalendarSyncError.missingCalendar }
                updatePomodoroSettings { $0.calendarEnabled = true; $0.calendarIdentifier = selected }
                calendarMessage = nil
                _ = flush(); syncCalendar()
            } catch { calendarMessage = error.localizedDescription }
        }
    }
    func syncCalendar(now: Date = Date()) {
        guard planner.pomodoro.calendarEnabled, !loadFailed, flush() else { return }
        lastSyncAttempt = now
        let ids = planner.sessions.filter { $0.calendarState == .pending }.map(\.id)
        guard !ids.isEmpty else { return }
        for id in ids {
            guard let i = planner.sessions.firstIndex(where: { $0.id == id }) else { continue }
            do {
                let session = planner.sessions[i]
                let eventID = try calendarGateway.save(session, calendarID: session.calendarIdentifier ?? planner.pomodoro.calendarIdentifier)
                planner.sessions[i].calendarEventIdentifier = eventID
                planner.sessions[i].calendarState = .synced
                scheduleSave()
                guard flush() else { return }
                calendarMessage = nil
            } catch { calendarMessage = "同步未完成：\(error.localizedDescription) 记录已保留，可重试。"; return }
        }
    }
    func retryCalendarWithSelected() {
        guard !loadFailed else { return }
        for i in planner.sessions.indices where planner.sessions[i].calendarState == .pending { planner.sessions[i].calendarIdentifier = planner.pomodoro.calendarIdentifier }
        scheduleSave(); if flush() { syncCalendar() }
    }
    private func scheduleSave() {
        dirty = true
        if saveStatus != "正在保存…" { saveStatus = "正在保存…" }
        pendingSave?.cancel()
        let job = DispatchWorkItem { [weak self] in self?.flush() }
        pendingSave = job
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: job)
    }
    @discardableResult func flush() -> Bool {
        pendingSave?.cancel(); pendingSave = nil
        guard dirty else { return !loadFailed }
        do {
            try disk.save(planner)
            dirty = false
            if saveError != nil { saveError = nil }
            if saveStatus != "所有更改已保存" { saveStatus = "所有更改已保存" }
            return true
        } catch {
            saveError = "保存失败：\(error.localizedDescription)"
            saveStatus = "尚未保存"
            return false
        }
    }
    func select(_ day: Day) {
        guard day.date() != nil else { return }
        commitActiveTextEditing()
        _ = flush()
        selectedDay = day
        calendarMonth = day
    }
    func goToday() { refreshClock(); select(today); setReview(false) }
    func setReview(_ review: Bool) {
        guard isReview != review else { return }
        commitActiveTextEditing()
        _ = flush()
        isReview = review
    }
    func moveWeek(_ offset: Int) { select(selectedDay.adding(offset * 7)) }
    func moveMonth(_ offset: Int) {
        guard let first = Day(rawValue: calendarMonth.monthKey + "-01").date(),
              let next = Calendar.planner.date(byAdding: .month, value: offset, to: first) else { return }
        calendarMonth = Day(next)
    }
    func refreshClock() {
        let current = Day(Date())
        if today != current { today = current }
    }
    func togglePin() { isPinned.toggle(); onPin?(isPinned) }
    func exportMarkdown(week: Bool = false) {
        commitActiveTextEditing()
        _ = flush()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "Daylight-\(week ? "周回顾-" : "")\(selectedDay.rawValue).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = week ? planner.weekMarkdown(for: selectedDay) : planner.markdown(for: selectedDay)
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch { showError(error) }
    }
    func exportBackup() {
        commitActiveTextEditing()
        _ = flush()
        guard !loadFailed else { revealData(); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Daylight-完整备份-\(Day(Date()).rawValue).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try PlannerDisk.encode(planner).write(to: url, options: .atomic) }
        catch { showError(error) }
    }
    func restoreBackup() {
        guard planner.activeTimer == nil else {
            timerMessage = "请先结束当前番茄或休息，再恢复备份。"; return
        }
        commitActiveTextEditing()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.message = "选择Daylight导出的完整 JSON 备份"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let incoming = try PlannerDisk.decode(data)
            let alert = NSAlert()
            alert.messageText = "恢复这份备份？"
            alert.informativeText = "将载入 \(incoming.days.count) 天记录、\(incoming.months.count) 个月目标和 \(incoming.weeks.count) 个周目标，并替换当前内容。恢复前会在数据文件夹保留一份原始文件。"
            alert.addButton(withTitle: "恢复备份"); alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            if dirty && !flush() { return }
            pendingSave?.cancel(); pendingSave = nil
            var restored = incoming
            restored.activeTimer = nil // A backup never resumes a historical running timer.
            planner = try disk.restore(PlannerDisk.encode(restored))
            reviewSessionID = planner.sessions.last { $0.review != nil && $0.review?.submittedAt == nil }?.id
            onTimerChange?()
            dirty = false; loadFailed = false; saveError = nil; saveStatus = "备份已恢复"
        } catch { showError(error) }
    }
    func revealData() { NSWorkspace.shared.open(disk.directory) }
    private func showError(_ error: Error) {
        let alert = NSAlert(); alert.messageText = "未能完成操作"; alert.informativeText = error.localizedDescription; alert.runModal()
    }
    private func seedDemo() {
        let day = today
        planner.longTerm = "保持好奇，持续学习。\n建立稳定的阅读与运动习惯。\n留出时间，认真生活。"
        planner.setGoal(.month, on: day, text: "完成一个学习项目\n读完 2 本书，留下阅读笔记\n累计运动 12 次")
        planner.setGoal(.week, on: day, text: "完成本周学习计划\n整理阅读笔记\n周末留半天给自己")
        planner.setDaily(.expected, on: day, text: "完成今天的学习任务\n阅读一篇文章，记录三个要点\n傍晚散步 30 分钟")
        for d in day.week() where d < day {
            planner.setDaily(.expected, on: d, text: "推进今天的学习任务\n阅读与整理笔记")
            planner.setDaily(.actual, on: d, text: "完成了学习计划，记录新的收获。\n读了几页书，让思路慢慢清晰。")
        }
    }
}
