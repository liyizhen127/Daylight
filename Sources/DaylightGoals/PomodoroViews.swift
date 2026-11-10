import SwiftUI
import DaylightCore

func timerText(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }

struct PomodoroBar: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 14) {
            Text("🍅").font(.system(size: 24))
            if let active = model.planner.activeTimer {
                VStack(alignment: .leading, spacing: 4) {
                    Text(active.phase == .focus ? active.title : "\(active.phase.title) · \(active.title)")
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(active.phase == .focus ? "专注完成后自动开始休息" : "休息结束后，自主选择下一项任务")
                        .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 6)
                Text(timerText(active.remaining(at: model.timerNow)))
                    .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                Button(active.phase == .focus ? "中断" : "跳过休息") { model.stopTimer() }.buttonStyle(QuietButton())
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日完成 \(model.planner.completedPomodoros(on: model.today)) 颗番茄")
                        .font(.system(size: 13, weight: .semibold))
                    Text(model.timerMessage.isEmpty ? "从任务右侧或状态栏选择一项，开始专注。" : model.timerMessage)
                        .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 5)
            }
            Button { commitActiveTextEditing(); model.showingPomodoroSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(.plain).help("番茄钟与日历设置").accessibilityLabel("番茄钟与日历设置")
        }.padding(15).background(Palette.greenLight.opacity(0.7), in: RoundedRectangle(cornerRadius: 13))
    }
}

struct PomodoroSettingsView: View {
    @EnvironmentObject var model: AppModel
    private func number(_ keyPath: WritableKeyPath<PomodoroSettings, Int>) -> Binding<Int> {
        Binding(get: { model.planner.pomodoro[keyPath: keyPath] }, set: { value in model.updatePomodoroSettings { $0[keyPath: keyPath] = value } })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("🍅 番茄钟与日历").font(.system(size: 22, weight: .semibold))
                Spacer()
                Button("完成") { model.showingPomodoroSettings = false; model.flush() }.buttonStyle(QuietButton(active: true))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 14) {
                        duration("专注时长", value: number(\.focusMinutes), range: 1...180, suffix: "分钟")
                        duration("普通休息", value: number(\.shortBreakMinutes), range: 1...60, suffix: "分钟")
                        duration("每完成", value: number(\.longBreakEvery), range: 1...12, suffix: "颗番茄，进入长休息")
                        duration("长休息", value: number(\.longBreakMinutes), range: 1...120, suffix: "分钟")
                        Text("专注结束自动进入休息；下一次专注由你开始。设置用于下一段计时。完整专注计 1 颗，中断保留时段但不计入完成数。")
                            .font(.system(size: 11)).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 13) {
                        Toggle("同步专注时段到苹果日历", isOn: Binding(get: { model.planner.pomodoro.calendarEnabled }, set: { model.enableCalendar($0) }))
                            .toggleStyle(.switch).disabled(model.requestingCalendar || model.loadFailed)
                        Text("每次完成或中断后，以任务标题创建日程，使用实际起止时间；休息不写入日历。开启后新产生的专注记录会同步。")
                            .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        if model.requestingCalendar { ProgressView("正在请求日历授权…").controlSize(.small) }
                        if model.planner.pomodoro.calendarEnabled {
                            Picker("目标日历", selection: Binding(get: { model.planner.pomodoro.calendarIdentifier ?? "" }, set: { id in model.updatePomodoroSettings { $0.calendarIdentifier = id } })) {
                                if !model.calendarOptions.contains(where: { $0.id == model.planner.pomodoro.calendarIdentifier }) {
                                    Text("请选择可写日历").tag(model.planner.pomodoro.calendarIdentifier ?? "")
                                }
                                ForEach(model.calendarOptions) { item in Text(item.title).tag(item.id) }
                            }
                            let pending = model.planner.sessions.filter { $0.calendarState == .pending }.count
                            HStack {
                                Text(pending == 0 ? "所有待同步时段已处理" : "\(pending) 条时段等待同步").font(.system(size: 11))
                                Spacer()
                                Button("刷新日历") { model.refreshCalendars() }
                                Button("重试同步") { model.retryCalendarWithSelected() }.disabled(pending == 0)
                            }
                        }
                        if let message = model.calendarMessage { Text(message).font(.system(size: 11)).foregroundStyle(.red).textSelection(.enabled) }
                    }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 10) {
                        Text("最近专注记录").font(.system(size: 13, weight: .semibold))
                        if model.planner.sessions.isEmpty { Text("完成或中断一次专注后，会显示在这里。").font(.system(size: 11)).foregroundStyle(Palette.secondary) }
                        ForEach(Array(model.planner.sessions.suffix(20).reversed())) { session in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(session.title).font(.system(size: 12)).lineLimit(1)
                                    Text("\(session.startedAt.formatted(date: .abbreviated, time: .shortened)) — \(session.endedAt.formatted(date: .omitted, time: .shortened))")
                                        .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                                }
                                Spacer()
                                Text(session.outcome == .completed ? "已完成" : "已中断").font(.system(size: 11))
                                Text(session.calendarState == .synced ? "已同步" : session.calendarState == .pending ? "待同步" : "本地")
                                    .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                            }
                            Divider()
                        }
                    }
                }.padding(.trailing, 6)
            }
        }.padding(25).frame(width: 590, height: 640).background(Palette.background).foregroundStyle(Palette.ink)
            .onAppear { model.refreshCalendars() }
    }
    private func duration(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, suffix: String) -> some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer()
            TextField("数值", value: value, formatter: integerFormatter).frame(width: 48).textFieldStyle(.roundedBorder)
            Text(suffix).font(.system(size: 12)).frame(width: 175, alignment: .leading)
            Stepper("", value: value, in: range).labelsHidden().accessibilityLabel(title)
        }
    }
    private var integerFormatter: NumberFormatter {
        let f = NumberFormatter(); f.numberStyle = .none; f.allowsFloats = false; return f
    }
}
