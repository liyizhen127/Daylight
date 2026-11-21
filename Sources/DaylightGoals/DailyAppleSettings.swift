import DaylightCore
import SwiftUI

struct DailyAppleSettings: View {
    @ObservedObject var sync: DailyAppleSync
    let day: Day
    let syncDay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("每日计划同步").font(.headline)
            if let error = sync.loadError { Text(error).foregroundStyle(.red) }
            ForEach(DailyChannel.allCases, id: \.self) { channel in
                DailyDestinationPicker(sync: sync, channel: channel)
            }
            Text("开启后同步今天和以后日期的内容。编辑旧日期或选中它手动同步，也会同步该日。")
                .font(.caption).foregroundStyle(.secondary)
            Button("立即同步 · \(day.rawValue)", action: syncDay)
                .disabled(sync.running || !DailyChannel.allCases.contains(where: sync.enabled))
        }
        .disabled(sync.loadError != nil)
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct DailyDestinationPicker: View {
    @ObservedObject var sync: DailyAppleSync
    let channel: DailyChannel
    @State private var choices: [CalendarOption] = []
    @State private var selection = ""
    @State private var requesting = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(channel == .reminders ? "预期完成 → 提醒事项" : "每日反思 → 日历")
                .font(.system(size: 13, weight: .semibold))
            Text(channel == .reminders
                 ? "按目标日期创建提醒，标题中的 🍅 表示实际 / 预估。macOS 15 起，可在日历侧栏勾选「计划的提醒事项」。"
                 : "每天 23:00 将反思写入当日 23:00–23:15 的日程。稍后补写或修改时同步更新。")
                .font(.caption).foregroundStyle(.secondary)
            if sync.enabled(channel) {
                HStack {
                    Text(choices.first { $0.id == sync.destination(channel) }?.title ?? "已开启")
                    Spacer()
                    Button("关闭同步") { sync.configure(channel, destination: nil); choices = [] }
                }
            } else if choices.isEmpty {
                Button(requesting ? "正在读取…" : "选择\(channel.destinationLabel)…") {
                    requesting = true
                    Task {
                        choices = await sync.requestDestinations(channel)
                        let preferred = sync.destination(channel) ?? sync.defaultID(channel)
                        selection = choices.first { $0.id == preferred }?.id ?? choices.first?.id ?? ""
                        requesting = false
                    }
                }.disabled(requesting)
            } else {
                HStack {
                    Picker(channel.destinationLabel, selection: $selection) {
                        ForEach(choices) { Text($0.title).tag($0.id) }
                    }
                    Button("开启同步") { sync.configure(channel, destination: selection) }.disabled(selection.isEmpty)
                }
                if let old = sync.destination(channel), old != selection {
                    Text("更换目标后，已关联的记录也会移动到新位置。").font(.caption)
                }
            }
            if let message = sync.messages[channel] { Text(message).font(.caption).textSelection(.enabled) }
        }
        .onAppear { if sync.enabled(channel) { choices = sync.options(channel) } }
        .disabled(sync.running)
    }
}
