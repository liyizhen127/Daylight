import SwiftUI
import AppKit
import DaylightCore

enum EditorScope: String, CaseIterable, Identifiable {
    case daily = "日目标", week = "周目标", month = "月目标", longTerm = "长期目标"
    var id: String { rawValue }
    var goalScope: GoalScope? {
        switch self {
        case .daily: return nil
        case .week: return .week
        case .month: return .month
        case .longTerm: return .longTerm
        }
    }
}

struct ClotheslineView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let edit: (EditorScope, Day) -> Void
    let dashboard: () -> Void
    let hide: () -> Void
    private let weekdayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
    private let paperColors: [Color] = [Color(hex: 0xF6F0DF), Color(hex: 0xE6EEE3), Color(hex: 0xECEAF3), Color(hex: 0xF4E9DE), Color(hex: 0xE4EDEF), Color(hex: 0xF2E6E8), Color(hex: 0xEDEEDC)]

    var body: some View {
        VStack(spacing: 12) {
            toolbar
            ScrollView(.vertical) {
              VStack(spacing: 17) {
            HangingRow {
                HStack(alignment: .top, spacing: 20) {
                    directionCard(.longTerm, icon: "mountain.2", color: Color(hex: 0xE9EFDF))
                    directionCard(.month, icon: "calendar", color: Color(hex: 0xF5EDDC))
                    directionCard(.week, icon: "leaf", color: Color(hex: 0xE5EEF0))
                }.padding(.horizontal, 18)
            }
            HangingRow {
                HStack(alignment: .top, spacing: 13) {
                    ForEach(Array(model.selectedDay.week().enumerated()), id: \.element.id) { index, day in
                        dayCard(day, index: index)
                    }
                }.padding(.horizontal, 18)
            }
              }.padding(.top, 2).padding(.bottom, 10)
            }.scrollBounceBehavior(.basedOnSize)
            HStack(spacing: 6) {
                Image(systemName: "pencil.tip")
                Text("点便签，写目标 · 修改自动保存")
                Text("·")
                Text(model.ropePinned ? "已固定在桌面上方" : "点击空白处收起")
                if model.saveError != nil { Text("· 保存异常，请打开便签查看").foregroundStyle(.red) }
            }.font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.ink)
                .padding(.horizontal, 15).padding(.vertical, 8)
                .background { if reduceTransparency { Capsule().fill(Palette.background) } else { Capsule().fill(.regularMaterial) } }
            MonthlyHarvestView().frame(height: 155)
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 18)
        .foregroundStyle(Palette.ink)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.horizon").font(.system(size: 19)).foregroundStyle(Palette.green)
            Text("Daylight").font(.system(size: 17, weight: .semibold))
            Rectangle().fill(Palette.green.opacity(0.2)).frame(width: 1, height: 22)
            Button { model.moveWeek(-1) } label: { Image(systemName: "chevron.left").frame(width: 22, height: 24) }.help("上一周").accessibilityLabel("上一周")
            let days = model.selectedDay.week()
            Text("\(days.first!.short) — \(days.last!.short)").font(.system(size: 13, weight: .medium, design: .rounded))
            Button { model.moveWeek(1) } label: { Image(systemName: "chevron.right").frame(width: 22, height: 24) }.help("下一周").accessibilityLabel("下一周")
            Button("回到本周") { model.goToday() }.font(.system(size: 11)).foregroundStyle(Palette.green)
            Spacer(minLength: 12)
            Button { edit(.daily, model.today) } label: { Label("写今天", systemImage: "square.and.pencil") }.buttonStyle(QuietButton(active: true))
            Button(action: dashboard) { Image(systemName: "rectangle.split.2x1").frame(width: 27, height: 25) }.help("打开完整计划").accessibilityLabel("打开完整计划")
            Button { model.ropePinned.toggle() } label: { Image(systemName: model.ropePinned ? "pin.fill" : "pin").frame(width: 27, height: 25) }
                .foregroundStyle(model.ropePinned ? Palette.green : Palette.secondary).help(model.ropePinned ? "取消固定" : "固定挂衣绳").accessibilityLabel(model.ropePinned ? "取消固定" : "固定挂衣绳")
            Button(action: hide) { Image(systemName: "xmark").frame(width: 27, height: 25) }.help("收起挂衣绳").accessibilityLabel("收起挂衣绳")
        }.buttonStyle(.plain).padding(.horizontal, 18).padding(.vertical, 11)
            .background { if reduceTransparency { RoundedRectangle(cornerRadius: 22).fill(Palette.background) } else { RoundedRectangle(cornerRadius: 22).fill(.regularMaterial) } }
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.55)))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    private func directionCard(_ scope: EditorScope, icon: String, color: Color) -> some View {
        let day = model.selectedDay
        let tasks = model.planner.tasks(scope.goalScope!, on: day)
        let period = scope == .longTerm ? "持续保留 · 随时修改" : scope == .month ? day.monthKey + " · 按月保存" : "\(day.week().first!.short) — \(day.week().last!.short) · 周一至周日"
        return VStack(alignment: .leading, spacing: 8) {
            Button { edit(scope, day) } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon).foregroundStyle(Palette.green)
                    Text(scope.rawValue).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Image(systemName: "pencil").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
            }.buttonStyle(.plain).accessibilityLabel("编辑\(scope.rawValue)，\(period)")
            Text(period + (tasks.count > 3 ? " · 共 \(tasks.count) 项" : "")).font(.system(size: 10)).foregroundStyle(Palette.secondary)
            if tasks.isEmpty {
                Button("点击写下\(scope.rawValue)…") { edit(scope, day) }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.secondary)
            } else {
                ForEach(Array(tasks.prefix(3))) { task in previewTask(task, scope: scope.goalScope, day: day, fontSize: 12) }
            }
            Spacer(minLength: 0)

        }.padding(.horizontal, 18).padding(.top, 23).padding(.bottom, 12).frame(maxWidth: .infinity, alignment: .leading).frame(height: 149)
            .background(color, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(.white.opacity(0.7)))
            .shadow(color: .black.opacity(0.13), radius: 7, y: 5)
            .overlay(alignment: .top) { Clothespeg(color: Palette.green).offset(y: -12) }
    }
    private func previewTask(_ task: GoalTask, scope: GoalScope?, day: Day, fontSize: CGFloat) -> some View {
        Button {
            model.updateTask(task.id, scope: scope, day: day) { $0.isCompleted.toggle() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: task.isCompleted ? "checkmark.square.fill" : "square")
                    .foregroundStyle(task.isCompleted ? Palette.green : Palette.secondary)
                Text(task.title).strikethrough(task.isCompleted).lineLimit(1)
                    .foregroundStyle(task.isCompleted ? Palette.secondary : Palette.ink)
                Spacer(minLength: 0)
            }.font(.system(size: fontSize)).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(model.loadFailed)
            .accessibilityLabel("\(task.isCompleted ? "取消完成" : "完成")：\(task.title)")
    }
    private func dayCard(_ day: Day, index: Int) -> some View {
        let record = model.planner.record(on: day)
        let isToday = day == model.today
        return VStack(alignment: .leading, spacing: 9) {
            Button { edit(.daily, day) } label: {
                HStack {
                    Text(weekdayNames[index]).font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 2)
                    Text(day.short).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(Palette.secondary)
                }
            }.buttonStyle(.plain).accessibilityLabel("编辑日目标 \(day.rawValue)")
            VStack(alignment: .leading, spacing: 5) {
                Label("预期完成", systemImage: "sun.max").font(.system(size: 9, weight: .medium)).foregroundStyle(Palette.amber)
                if record.tasks.isEmpty {
                    Button("写下今天的计划…") { edit(.daily, day) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                } else {
                    ForEach(Array(record.tasks.prefix(2))) { task in previewTask(task, scope: nil, day: day, fontSize: 11) }
                }
            }.frame(height: 49, alignment: .top)
            Rectangle().fill(Palette.ink.opacity(0.09)).frame(height: 1)
            Button { edit(.daily, day) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label("每日反思", systemImage: "moon").font(.system(size: 9, weight: .medium)).foregroundStyle(Palette.blue)
                    Text(record.hasReview ? record.actual : "留给晚上的回响…").font(.system(size: 11)).lineSpacing(3).lineLimit(2)
                        .foregroundStyle(record.hasReview ? Palette.ink : Palette.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).frame(height: 49, alignment: .top)
            }.buttonStyle(.plain)
            Button { edit(.daily, day) } label: {
                HStack {
                    Text("\(record.tasks.filter(\.isCompleted).count)/\(record.tasks.count) 项 · \(isToday ? "今天" : "编辑")")
                    Spacer()
                    Image(systemName: "pencil")
                }.font(.system(size: 9, weight: .medium)).foregroundStyle(isToday ? Palette.green : Palette.secondary)
            }.buttonStyle(.plain)
        }.padding(.horizontal, 12).padding(.top, 23).padding(.bottom, 12).frame(maxWidth: .infinity).frame(height: 205)
            .background(paperColors[index], in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isToday ? Palette.green.opacity(0.7) : .white.opacity(0.6), lineWidth: isToday ? 1.5 : 1))
            .shadow(color: .black.opacity(0.13), radius: 7, y: 5)
            .overlay(alignment: .top) { Clothespeg(color: isToday ? Palette.amber : Palette.green.opacity(0.75)).offset(y: -12) }
    }
}

private struct Clothespeg: View {
    let color: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 3).fill(color.gradient).frame(width: 9, height: 25)
            .overlay { RoundedRectangle(cornerRadius: 2).strokeBorder(.white.opacity(0.4), lineWidth: 1) }
            .shadow(color: .black.opacity(0.15), radius: 2, y: 2)
            .accessibilityHidden(true)
    }
}

private struct HangingRow<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { geometry in
                Path { p in
                    p.move(to: CGPoint(x: 3, y: 7))
                    p.addQuadCurve(to: CGPoint(x: geometry.size.width - 3, y: 7), control: CGPoint(x: geometry.size.width / 2, y: 26))
                }.stroke(Color(hex: 0x9A9F93), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .shadow(color: .white.opacity(0.8), radius: 1, y: -1)
            }.frame(height: 28).accessibilityHidden(true)
            content().padding(.top, 17)
        }
    }
}

struct HangingEditorView: View {
    @EnvironmentObject var model: AppModel
    @State var scope: EditorScope
    let close: () -> Void
    private var day: Day { model.selectedDay }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "sun.horizon").font(.system(size: 22)).foregroundStyle(Palette.green)
                Text("写下目标，慢慢靠近。").font(.system(size: 19, weight: .semibold))
                Spacer()
                Button("返回挂衣绳", action: close).buttonStyle(QuietButton())
            }
            HStack {
                Picker("目标层级", selection: Binding(get: { scope }, set: { next in
                    commitActiveTextEditing()
                    model.flush()
                    scope = next
                })) {
                    ForEach(EditorScope.allCases) { item in Text(item.rawValue).tag(item) }
                }.pickerStyle(.segmented).frame(width: 345)
                Spacer()
                Button { move(-1) } label: { Image(systemName: "chevron.left") }.help("上一周期")
                DatePicker("日期", selection: Binding(get: { day.date() ?? Date() }, set: { model.select(Day($0)) }), displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.field).environment(\.locale, Locale(identifier: "zh_CN")).frame(width: 115)
                Button { move(1) } label: { Image(systemName: "chevron.right") }.help("下一周期")
            }.buttonStyle(.plain)
            if let error = model.saveError {
                HStack {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red)
                    Spacer()
                    if model.loadFailed { Button("恢复备份") { model.restoreBackup() } }
                    else { Button("重试保存") { model.flush() }; Button("导出备份") { model.exportBackup() } }
                }
            }
            ScrollView {
              VStack(alignment: .leading, spacing: 15) {
                PomodoroBar()
            if scope == .daily {
                VStack(alignment: .leading, spacing: 15) {
                    DailyCard(day: day, field: .expected)
                    DailyCard(day: day, field: .actual)
                }
            } else {
                GoalCard(scope: scope.goalScope!, day: day)
                Text(scope == .longTerm ? "长期目标始终共用这一份，不会随日期清空。" : scope == .month ? "同一个自然月共用这一份目标，其他月份单独保存。" : "周一到周日共用这一份目标，跨月的同一周保持一致。")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Spacer(minLength: 0)
            }
              }
            }
            HStack {
                Label(model.saveStatus, systemImage: model.saveError == nil ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(model.saveError == nil ? Palette.secondary : .red)
                Spacer()
                Text(day.rawValue).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.secondary)
                Button("完成", action: close).buttonStyle(QuietButton(active: true)).keyboardShortcut(.return, modifiers: .command)
            }
        }.padding(25).padding(.top, 12).frame(minWidth: 750, minHeight: 450)
            .background(Palette.background).foregroundStyle(Palette.ink)
            .sheet(isPresented: $model.showingPomodoroSettings) { PomodoroSettingsView() }
    }
    private func move(_ offset: Int) {
        if scope == .month, let first = Day(rawValue: day.monthKey + "-01").date(),
           let next = Calendar.planner.date(byAdding: .month, value: offset, to: first) { model.select(Day(next)) }
        else { model.select(day.adding(scope == .week ? offset * 7 : offset)) }
    }
}
