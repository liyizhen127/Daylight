import SwiftUI
import DaylightCore

struct TaskChecklist: View {
    @EnvironmentObject var model: AppModel
    let scope: GoalScope?
    let day: Day
    private var draft: Binding<String> { model.draftBinding(scope: scope, day: day) }
    @State private var deleting: GoalTask?
    private var tasks: [GoalTask] { model.planner.tasks(scope, on: day) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(tasks) { task in
                taskRow(task)
                if task.id != tasks.last?.id { Divider().opacity(0.5) }
            }
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "plus.circle").foregroundStyle(Palette.green)
                NativeTextEditor(text: draft, placeholder: "添加任务，可粘贴多行或 - [ ] 清单", fontSize: 13)
                    .frame(height: 53).accessibilityIdentifier("new-task")
                Button("添加") {
                    commitActiveTextEditing()
                    model.addTasks(draft.wrappedValue, scope: scope, day: day)
                    draft.wrappedValue = ""
                }.buttonStyle(QuietButton()).help("把每一行添加为独立任务")
            }
            if tasks.isEmpty {
                Text("每行一件事。完成后勾选，文字会划线并保留。")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
        }
        .disabled(model.loadFailed)
        .alert("删除这项任务？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("删除任务", role: .destructive) {
                if let deleting { model.removeTask(deleting.id, scope: scope, day: day) }
                deleting = nil
            }
        } message: { Text("已记录的番茄时段和日历日程会保留。完成任务只需勾选，无需删除。") }
    }
    private func taskRow(_ task: GoalTask) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Button {
                commitActiveTextEditing()
                model.updateTask(task.id, scope: scope, day: day) { $0.isCompleted.toggle() }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18)).foregroundStyle(task.isCompleted ? Palette.green : Palette.secondary)
            }.buttonStyle(.plain).padding(.top, 12)
                .accessibilityLabel("\(task.isCompleted ? "取消完成" : "完成")：\(task.title)")
            VStack(alignment: .leading, spacing: 3) {
                NativeTextEditor(text: model.taskTitleBinding(task.id, scope: scope, day: day), placeholder: "任务标题", fontSize: 14, strikethrough: task.isCompleted)
                    .frame(height: max(42, min(160, CGFloat(task.title.count / (scope == nil ? 42 : 14) + task.title.filter { $0 == "\n" }.count + 1) * 23 + 16)))
                    .opacity(task.isCompleted ? 0.6 : 1)
                if scope == nil {
                    HStack(spacing: 10) {
                        Text("🍅 实际 \(model.planner.actualPomodoros(taskID: task.id, on: day))")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.green)
                        Stepper(value: Binding(get: { task.estimatedPomodoros }, set: { value in
                            model.updateTask(task.id, scope: nil, day: day) { $0.estimatedPomodoros = value }
                        }), in: 0...999) { Text("预估 \(task.estimatedPomodoros)").font(.system(size: 11)) }
                            .fixedSize().accessibilityLabel("\(task.title)的预估番茄数")
                        Spacer(minLength: 0)
                        Button {
                            model.startFocus(task.id, day: day)
                        } label: { Label("开始专注", systemImage: "play.fill").font(.system(size: 11, weight: .medium)) }
                            .buttonStyle(.plain).foregroundStyle(Palette.green)
                            .disabled(model.planner.activeTimer != nil || task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }.padding(.leading, 5).padding(.bottom, 5)
                }
            }
            Button { commitActiveTextEditing(); deleting = task } label: {
                Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }.buttonStyle(.plain).padding(.top, 15).help("删除任务").accessibilityLabel("删除：\(task.title)")
        }
    }
}
