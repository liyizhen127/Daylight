import SwiftUI
import DaylightCore

enum Palette {
    static let background = Color(hex: 0xF9F8F4)
    static let sidebar = Color(hex: 0xF0F0E8)
    static let ink = Color(hex: 0x303D35)
    static let secondary = Color(hex: 0x778078)
    static let green = Color(hex: 0x56735E)
    static let greenLight = Color(hex: 0xE5EBDD)
    static let line = Color(hex: 0xDFE3D9)
    static let morning = Color(hex: 0xFCF7EC)
    static let evening = Color(hex: 0xEEF2F2)
    static let amber = Color(hex: 0xB48046)
    static let blue = Color(hex: 0x67838E)
}
extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

struct QuietButton: ButtonStyle {
    var active = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(active ? Color.white : Palette.ink)
            .padding(.horizontal, 13).padding(.vertical, 9)
            .background(active ? Palette.green : Color.white.opacity(configuration.isPressed ? 0.5 : 0.9), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(active ? Palette.green : Palette.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct WritingArea: View {
    @Binding var text: String
    let placeholder: String
    var fontSize: CGFloat = 13
    var minHeight: CGFloat = 100
    var body: some View {
        NativeTextEditor(text: $text, placeholder: placeholder, fontSize: fontSize)
            .frame(minHeight: minHeight)
    }
}

struct SectionHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
            Text(subtitle).font(.system(size: 11)).foregroundStyle(Palette.secondary)
            Spacer()
        }
    }
}

struct GoalCard: View {
    @EnvironmentObject var model: AppModel
    let scope: GoalScope
    let day: Day
    private var title: String { scope == .longTerm ? "长期目标" : scope == .month ? "月目标" : "周目标" }
    private var icon: String { scope == .longTerm ? "mountain.2" : scope == .month ? "calendar" : "leaf" }
    private var period: String {
        switch scope {
        case .longTerm: return "始终在这里 · 随时可改"
        case .month: return day.monthKey.replacingOccurrences(of: "-", with: " 年 ") + " 月"
        case .week: return "\(day.week().first!.short) — \(day.week().last!.short)"
        }
    }
    private var placeholder: String {
        switch scope {
        case .longTerm: return "你想持续靠近的方向…\n写下值得长期坚持的事"
        case .month: return "这个月，想实现什么？\n给方向一个阶段性的落点"
        case .week: return "这一周，专注哪几件事？\n把目标变成具体的行动"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Palette.green)
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                if !model.planner.goal(scope, on: day).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Circle().fill(Palette.green).frame(width: 5, height: 5)
                }
            }.foregroundStyle(Palette.ink)
            Text(period).font(.system(size: 10)).foregroundStyle(Palette.secondary)
            Rectangle().fill(Palette.line.opacity(0.65)).frame(height: 1)
            TaskChecklist(scope: scope, day: day)
                .id("\(scope.rawValue)-\(scope == .longTerm ? "all" : scope == .month ? day.monthKey : day.weekKey)")
                .disabled(model.loadFailed)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line.opacity(0.8), lineWidth: 1))
    }
}

struct DailyCard: View {
    @EnvironmentObject var model: AppModel
    let day: Day
    let field: DailyField
    private var morning: Bool { field == .expected }
    private var tint: Color { morning ? Palette.amber : Palette.blue }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: morning ? "sun.max" : "moon.stars")
                    .font(.system(size: 19, weight: .light)).foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(morning ? "预期完成" : "每日反思").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                    Text(morning ? "早间 · 为今天留一点期待" : "晚间 · 回顾进展，也照顾自己").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Text(morning ? "PLAN" : "REFLECT").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.8).foregroundStyle(tint)
            }
            Rectangle().fill(tint.opacity(0.15)).frame(height: 1)
            if morning {
                TaskChecklist(scope: nil, day: day)
            } else {
                WritingArea(text: model.dailyBinding(.actual, day: day), placeholder: "今天有哪些收获？什么可以调整？\n为明天留一句话…", fontSize: 14, minHeight: 130)
                    .id("reflection-\(day.rawValue)").disabled(model.loadFailed)
            }
            HStack {
                Text(morning ? "把重要的事，放在今天。" : "每一小步，都值得被看见。")
                Spacer()
                let record = model.planner.record(on: day)
                Text(morning ? "\(record.tasks.filter(\.isCompleted).count) / \(record.tasks.count) 项完成" : "\(record.reflection.count) 字")
            }.font(.system(size: 10)).foregroundStyle(Palette.secondary)
        }
        .padding(20).frame(maxWidth: .infinity)
        .background(morning ? Palette.morning : Palette.evening, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(tint.opacity(0.16), lineWidth: 1))
    }
}
