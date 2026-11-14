import SwiftUI
import DaylightCore

struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13).fill(Palette.green).frame(width: 42, height: 42)
                    Image(systemName: "sun.horizon").font(.system(size: 23, weight: .light)).foregroundStyle(Color(hex: 0xF7F0DA))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Daylight").font(.system(size: 21, weight: .semibold)).lineLimit(1)
                    Text("D A Y L I G H T").font(.system(size: 8, weight: .medium)).foregroundStyle(Palette.secondary)
                }
            }.padding(.top, 23).padding(.bottom, 30)
            navButton("每日计划", icon: "square.grid.2x2", selected: !model.isReview) { model.setReview(false) }
            navButton("一周回顾", icon: "book.closed", selected: model.isReview) { model.setReview(true) }.padding(.top, 6)
            Rectangle().fill(Palette.line).frame(height: 1).padding(.vertical, 25)
            calendar
            Rectangle().fill(Palette.line).frame(height: 1).padding(.vertical, 25)
            weekProgress
            Spacer(minLength: 28)
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "quote.opening").font(.system(size: 15)).foregroundStyle(Palette.green.opacity(0.6))
                Text("不必每一天都完美，\n只要每一天都在靠近。").font(.system(size: 11)).lineSpacing(6).foregroundStyle(Palette.secondary)
            }.padding(.bottom, 24)
            HStack {
                Button { model.showingHelp = true } label: { Label("使用说明", systemImage: "questionmark.circle") }
                Spacer()
                Button { model.revealData() } label: { Image(systemName: "externaldrive") }.help("打开数据文件夹").accessibilityLabel("打开数据文件夹")
            }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.secondary).padding(.bottom, 20)
        }.padding(.horizontal, 20).background(Palette.sidebar)
    }
    private func navButton(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon).font(.system(size: 14))
                Text(title).font(.system(size: 12, weight: selected ? .semibold : .regular))
                Spacer()
                if selected { Circle().fill(Palette.green).frame(width: 4, height: 4) }
            }.foregroundStyle(selected ? Palette.green : Palette.secondary).padding(.horizontal, 12).padding(.vertical, 11)
                .background(selected ? Palette.greenLight : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }
    private var calendar: some View {
        VStack(spacing: 14) {
            HStack(spacing: 5) {
                Text(monthTitle).font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { model.moveMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 20, height: 20) }.help("上个月")
                Button { model.moveMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 20, height: 20) }.help("下个月")
            }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.ink)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { name in
                    Text(name).font(.system(size: 9)).foregroundStyle(Palette.secondary).frame(height: 19)
                }
                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        Button { model.select(day) } label: {
                            VStack(spacing: 2) {
                                Text(day.number).font(.system(size: 10, weight: day == model.today ? .bold : .regular))
                                Circle().fill(!model.planner.record(on: day).isEmpty ? (day == model.selectedDay ? .white : Palette.green) : .clear).frame(width: 3, height: 3)
                            }.frame(maxWidth: .infinity).frame(height: 26)
                                .foregroundStyle(day == model.selectedDay ? .white : day == model.today ? Palette.green : Palette.ink)
                                .background(day == model.selectedDay ? Palette.green : .clear, in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(day == model.today && day != model.selectedDay ? Palette.green.opacity(0.45) : .clear))
                        }.buttonStyle(.plain).accessibilityLabel("选择日期 \(day.rawValue)")
                    } else { Color.clear.frame(height: 26) }
                }
            }
            HStack(spacing: 5) {
                Circle().fill(Palette.green).frame(width: 3, height: 3)
                Text("有记录的日子").font(.system(size: 9)).foregroundStyle(Palette.secondary)
                Spacer()
            }
        }
    }
    private var monthTitle: String {
        let p = model.calendarMonth.monthKey.split(separator: "-")
        return "\(p[0]) 年 \(Int(p[1]) ?? 1) 月"
    }
    private var monthDays: [Day?] {
        let first = Day(rawValue: model.calendarMonth.monthKey + "-01")
        guard let date = first.date(), let count = Calendar.planner.range(of: .day, in: .month, for: date)?.count else { return [] }
        let leading = (Calendar.planner.component(.weekday, from: date) + 5) % 7
        return Array(repeating: nil, count: leading) + (0..<count).map { Optional(first.adding($0)) }
    }
    private var weekProgress: some View {
        let week = model.selectedDay.week()
        let planned = week.filter { model.planner.record(on: $0).hasPlan }.count
        let reviewed = week.filter { model.planner.record(on: $0).hasReview }.count
        return VStack(alignment: .leading, spacing: 13) {
            Text("这一周的节奏").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(reviewed)").font(.system(size: 28, weight: .medium, design: .rounded)).foregroundStyle(Palette.green)
                Text("/ 7 天已复盘").font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
            HStack(spacing: 5) {
                ForEach(week) { day in
                    Capsule().fill(model.planner.record(on: day).hasReview ? Palette.green : Palette.line).frame(height: 5)
                }
            }
            Text("\(planned) 天写下期待，\(reviewed) 天留下回响。")
                .font(.system(size: 10)).foregroundStyle(Palette.secondary)
        }
    }
}

struct ReviewView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeading(title: "这一周的方向", subtitle: "点击文字，随时调整")
                Button { model.exportMarkdown(week: true) } label: { Label("导出周回顾", systemImage: "square.and.arrow.up") }.buttonStyle(QuietButton())
            }
            GoalCard(scope: .week, day: model.selectedDay)
            ForEach(model.selectedDay.week()) { day in
                reviewCard(day)
            }
        }
    }
    private func reviewCard(_ day: Day) -> some View {
        let record = model.planner.record(on: day)
        return VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(day.rawValue).font(.system(size: 13, weight: .semibold, design: .rounded))
                if day == model.today { Text("今天").font(.system(size: 10)).foregroundStyle(Palette.green) }
                Spacer()
                Button("编辑这一天 →") { model.select(day); model.setReview(false) }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.green)
            }
            HStack(alignment: .top, spacing: 25) {
                reviewColumn("预期完成", text: model.planner.dailyChecklist(on: day), color: Palette.amber)
                Rectangle().fill(Palette.line).frame(width: 1)
                reviewColumn("每日反思", text: record.actual, color: Palette.blue)
            }.fixedSize(horizontal: false, vertical: true)
        }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))
    }
    private func reviewColumn(_ title: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(color)
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "尚未填写" : text)
                .font(.system(size: 12)).lineSpacing(6).foregroundStyle(text.isEmpty ? Palette.secondary : Palette.ink)
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HelpView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "sun.horizon").font(.system(size: 31, weight: .light)).foregroundStyle(Palette.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daylight").font(.system(size: 22, weight: .semibold))
                    Text("每一天，都有方向。  v2.2.0").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                Spacer()
            }
            Divider()
            helpRow("menubar.rectangle", "状态栏挂衣绳", "左键状态栏展开挂衣绳，右键选择今天的任务开始专注。计时中显示名称与剩余时间，空闲时显示今日完成数。到时弹出额外专注窗口，点击开始休息后可评价并写感受。番茄设置中可查看记录、配置休息和日历同步。")
            helpRow("mountain.2", "长期目标", "所有日期共用同一份内容，持续保留；修改后会在所有日期显示最新内容。")
            helpRow("calendar", "月目标与周目标", "月目标按自然月保存，周目标按周一到周日保存。新周期从空白开始，切换日期即可查看、修改历史或未来目标。")
            helpRow("sun.max", "任务清单 / 每日反思", "所有目标都支持勾选并保留划线任务。日目标可以预估番茄数，完整完成一次专注会累计实际数量；下方单独记录每日反思。")
            helpRow("externaldrive", "本地保存与备份", "停止输入约 0.35 秒后自动保存；切换日期、关闭窗口或退出时立即保存。右上角可导出 Markdown、备份全部数据及恢复备份。")
            helpRow("keyboard", "快捷键", "⌘T 回到今天   ·   ⌘1 每日计划   ·   ⌘2 一周回顾\n⌘[ / ⌘] 切换周   ·   ⌘S 保存   ·   ⌘E 导出当天")
            Text("灵感来自开源项目 AetherNote 的一周便签与本地记录方式。Daylight是独立的目标规划应用，数据单独保存。")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(4)
            HStack {
                Link("AetherNote ↗", destination: URL(string: "https://github.com/bcblr1993/AetherNote")!)
                Spacer()
                Button("开始记录") { model.showingHelp = false }.buttonStyle(QuietButton(active: true)).keyboardShortcut(.defaultAction)
            }
        }.padding(30).frame(width: 540).background(Palette.background).foregroundStyle(Palette.ink)
    }
    private func helpRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(Palette.green).frame(width: 22).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 11)).lineSpacing(4).foregroundStyle(Palette.secondary)
            }
        }
    }
}
