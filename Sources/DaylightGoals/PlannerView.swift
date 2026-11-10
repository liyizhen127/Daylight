import SwiftUI
import AppKit
import DaylightCore

struct PlannerView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            SidebarView().frame(width: 214)
            Rectangle().fill(Palette.line).frame(width: 1)
            VStack(spacing: 0) {
                topBar
                ScrollViewReader { scrollProxy in
                  ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        pageHeading
                        WeekLine()
                        PomodoroBar()
                        if let error = model.saveError { errorBanner(error) }
                        if model.isReview {
                            ReviewView()
                        } else {
                            VStack(spacing: 12) {
                                SectionHeading(title: "心有方向", subtitle: "从长远，到这一周")
                                HStack(alignment: .top, spacing: 12) {
                                    ForEach(GoalScope.allCases, id: \.self) { scope in GoalCard(scope: scope, day: model.selectedDay) }
                                }
                            }
                            VStack(spacing: 12) {
                                SectionHeading(title: model.selectedDay == model.today ? "落在今天" : "落在这一天", subtitle: "\(model.selectedDay.rawValue) · 完成一件，勾选一件")
                                VStack(alignment: .leading, spacing: 14) {
                                    DailyCard(day: model.selectedDay, field: .expected)
                                    DailyCard(day: model.selectedDay, field: .actual)
                                }
                            }
                        }
                        HStack(spacing: 5) {
                            Image(systemName: "lock.shield").font(.system(size: 10))
                            Text("目标保存在本机 · 可选同步专注时段到日历")
                            Spacer()
                            Text("慢慢来，日子会留下答案。")
                        }.font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    }.padding(.horizontal, 28).padding(.top, 18).padding(.bottom, 24).id("page-top")
                  }
                  .onChange(of: model.isReview) { _, _ in scrollProxy.scrollTo("page-top", anchor: .top) }
                  .onChange(of: model.selectedDay) { _, _ in scrollProxy.scrollTo("page-top", anchor: .top) }
                }
            }.background(Palette.background)
        }
        .foregroundStyle(Palette.ink)
        .background(Palette.background)
        .frame(minWidth: 1040, minHeight: 660)
        .sheet(isPresented: $model.showingHelp) { HelpView() }
        .sheet(isPresented: $model.showingPomodoroSettings) { PomodoroSettingsView() }
    }
    private var topBar: some View {
        HStack(spacing: 10) {
            Text(model.isReview ? "一周回顾" : "每日计划").font(.system(size: 12, weight: .medium))
            Text("/").foregroundStyle(Palette.line)
            Text(model.selectedDay.monthKey.replacingOccurrences(of: "-", with: ".")).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.secondary)
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: model.saveError == nil ? "checkmark.circle" : "exclamationmark.circle")
                Text(model.saveStatus)
            }.font(.system(size: 10)).foregroundStyle(model.saveError == nil ? Palette.secondary : .red)
            Button { model.togglePin() } label: { Image(systemName: model.isPinned ? "pin.fill" : "pin") }
                .buttonStyle(.plain).padding(.horizontal, 8).foregroundStyle(model.isPinned ? Palette.green : Palette.secondary)
                .help(model.isPinned ? "取消窗口置顶" : "窗口置顶").accessibilityLabel("窗口置顶")
            Menu {
                Button("导出当天 Markdown…") { model.exportMarkdown() }
                Button("导出本周 Markdown…") { model.exportMarkdown(week: true) }
                Divider()
                Button("导出完整备份…") { model.exportBackup() }
                Button("恢复备份…") { model.restoreBackup() }
                Button("打开数据文件夹") { model.revealData() }
            } label: { Image(systemName: "square.and.arrow.up").font(.system(size: 13)) }
                .menuStyle(.borderlessButton).fixedSize().help("导出与备份").accessibilityLabel("导出与备份")
        }.padding(.horizontal, 28).frame(height: 39)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line.opacity(0.6)).frame(height: 1) }
    }
    private var pageHeading: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(model.isReview ? "把一周，轻轻回望。" : formattedDate)
                        .font(.system(size: 27, weight: .semibold, design: .rounded)).tracking(0.5)
                    if !model.isReview {
                        Text(weekday).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        if model.selectedDay == model.today {
                            Text("今天").font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.green)
                                .padding(.horizontal, 8).padding(.vertical, 4).background(Palette.greenLight, in: Capsule())
                        }
                    }
                }
                Text(model.isReview ? "看见已经走过的路，也为下一周留一点空间。" : "早有计划，晚有回响。让每一天，都朝着想去的方向。")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 10)
            HStack(spacing: 0) {
                Button { model.moveWeek(-1) } label: { Image(systemName: "chevron.left").frame(width: 28, height: 30) }.help("上一周 · ⌘[")
                Button("回到今天") { model.goToday() }.padding(.horizontal, 7).help("回到今天 · ⌘T")
                Button { model.moveWeek(1) } label: { Image(systemName: "chevron.right").frame(width: 28, height: 30) }.help("下一周 · ⌘]")
            }.buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                .padding(3).background(.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line, lineWidth: 1))
        }
    }
    private var formattedDate: String {
        let p = model.selectedDay.rawValue.split(separator: "-")
        return "\(Int(p[1]) ?? 1) 月 \(Int(p[2]) ?? 1) 日"
    }
    private var weekday: String {
        guard let d = model.selectedDay.date() else { return "" }
        return ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"][Calendar.planner.component(.weekday, from: d) - 1]
    }
    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
            Text(error).font(.system(size: 12))
            Spacer()
            if model.loadFailed { Button("恢复备份") { model.restoreBackup() } }
            else { Button("重试保存") { model.flush() }; Button("导出备份") { model.exportBackup() } }
        }.foregroundStyle(.red).padding(14).background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct WeekLine: View {
    @EnvironmentObject var model: AppModel
    private let labels = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("一周的足迹").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.secondary)
                Spacer()
                let days = model.selectedDay.week()
                Text("\(days.first!.rawValue) — \(days.last!.rawValue)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.secondary)
            }
            ZStack(alignment: .top) {
                GeometryReader { proxy in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 8))
                        path.addQuadCurve(to: CGPoint(x: proxy.size.width, y: 8), control: CGPoint(x: proxy.size.width / 2, y: 22))
                    }.stroke(Palette.green.opacity(0.26), lineWidth: 1.4)
                }.frame(height: 24).accessibilityHidden(true)
                HStack(spacing: 10) {
                    ForEach(Array(model.selectedDay.week().enumerated()), id: \.element.id) { index, day in
                        dayCard(day, index: index)
                    }
                }.padding(.top, 12)
            }
        }
    }
    private func dayCard(_ day: Day, index: Int) -> some View {
        let selected = day == model.selectedDay
        let record = model.planner.record(on: day)
        return Button { model.select(day) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(labels[index]).font(.system(size: 10, weight: .medium))
                    Spacer(minLength: 1)
                    if day == model.today { Circle().fill(selected ? Color.white : Palette.green).frame(width: 4, height: 4) }
                }
                Text(day.number).font(.system(size: 25, weight: .medium, design: .rounded))
                HStack(spacing: 4) {
                    Circle().fill(record.hasPlan ? (selected ? Color.white : Palette.amber) : (selected ? Color.white.opacity(0.22) : Palette.line)).frame(width: 4, height: 4)
                    Circle().fill(record.hasReview ? (selected ? Color.white : Palette.green) : (selected ? Color.white.opacity(0.22) : Palette.line)).frame(width: 4, height: 4)
                    Text(record.hasReview ? "已复盘" : record.hasPlan ? "已计划" : "待落笔").font(.system(size: 9)).lineLimit(1)
                }.foregroundStyle(selected ? Color.white.opacity(0.8) : Palette.secondary)
            }.foregroundStyle(selected ? Color.white : Palette.ink)
                .padding(.horizontal, 13).padding(.top, 16).padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Palette.green : index > 4 ? Color(hex: 0xF0EFE8) : Color.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Palette.green : Palette.line, lineWidth: 1))
                .overlay(alignment: .top) {
                    Capsule().fill(selected ? Palette.amber : Color(hex: 0xBBC4B6)).frame(width: 5, height: 14).offset(y: -7)
                }
        }.buttonStyle(.plain).accessibilityLabel("\(day.rawValue)，\(record.hasPlan ? "已计划" : "未计划")，\(record.hasReview ? "已复盘" : "未复盘")")
            .help("打开 \(day.rawValue) 的计划和记录")
    }
}
