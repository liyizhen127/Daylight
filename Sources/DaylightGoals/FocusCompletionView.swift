import AppKit
import SwiftUI
import DaylightCore

enum FocusPromptPresentation: Equatable {
    case overtime(UUID), review(UUID)
}

/// A movable, non-modal window. Each transition presents it once, never on every timer tick.
@MainActor final class FocusPromptController: NSObject, NSWindowDelegate {
    let model: AppModel
    let window: NSWindow
    private(set) var presentation: FocusPromptPresentation?
    private var hasPresented = false

    init(model: AppModel) {
        self.model = model
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 320),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor(calibratedRed: 0.976, green: 0.973, blue: 0.956, alpha: 1)
    }

    func refresh() {
        let next: FocusPromptPresentation?
        if let active = model.planner.activeTimer, active.isOvertime(at: model.timerNow) {
            next = .overtime(active.id)
        } else if let id = model.reviewSessionID, model.session(id) != nil {
            next = .review(id)
        } else { next = nil }
        guard next != presentation else { return }
        // Finish IME composition before replacing a review's hosting view.
        commitActiveTextEditing(in: window)
        presentation = next
        guard let next else { window.orderOut(nil); return }
        let overtime: Bool
        if case .overtime = next { overtime = true } else { overtime = false }
        window.title = overtime ? "Daylight · 额外专注" : "Daylight · 番茄评价"
        window.standardWindowButton(.closeButton)?.isEnabled = !overtime
        window.contentView = NSHostingView(rootView: FocusCompletionView(presentation: next)
            .environmentObject(model).environment(\.colorScheme, .light))
        window.setContentSize(NSSize(width: 450, height: overtime ? 320 : 475))
        if !hasPresented { window.center(); hasPresented = true }
        show()
    }

    func show() {
        guard presentation != nil else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if case .overtime = presentation { return false }
        commitActiveTextEditing(in: window)
        if model.dismissReview() { refresh() }
        return false
    }
}

struct FocusCompletionView: View {
    @EnvironmentObject var model: AppModel
    let presentation: FocusPromptPresentation

    var body: some View {
        Group {
            switch presentation {
            case .overtime(let id):
                if let active = model.planner.activeTimer, active.id == id { overtime(active) }
            case .review(let id):
                if let session = model.session(id) { review(session) }
            }
        }
        .padding(26).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background).foregroundStyle(Palette.ink)
    }

    private func overtime(_ active: ActiveTimer) -> some View {
        let seconds = active.overtimeSeconds(at: model.timerNow)
        return VStack(spacing: 15) {
            Text("🍅").font(.system(size: 35))
            Text(active.title).font(.system(size: 16, weight: .semibold)).lineLimit(2)
            Text("当前已经额外专注").font(.system(size: 13)).foregroundStyle(Palette.secondary)
            Text("\(seconds / 60) 分 \(seconds % 60) 秒")
                .font(.system(size: 38, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Palette.green).lineLimit(1).minimumScaleFactor(0.6)
                .accessibilityLabel("额外专注 \(seconds / 60) 分 \(seconds % 60) 秒")
            Text("还想继续？把窗口拖到一边，计时会一直继续。")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            Button("开始休息") { model.startBreak() }
                .buttonStyle(QuietButton(active: true)).controlSize(.large)
                .padding(.top, 5)
        }
    }

    private func review(_ session: FocusSession) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text("这一颗番茄，感觉如何？").font(.system(size: 20, weight: .semibold))
                Spacer()
                Text("🍅").font(.system(size: 27))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(session.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                Text("实际专注 \(durationText(session.durationSeconds)) · 额外 \(durationText(session.overtimeSeconds))")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            HStack(spacing: 10) {
                ForEach(FocusRating.allCases, id: \.self) { rating in
                    let selected = session.review?.rating == rating
                    Button { model.setReviewRating(rating, sessionID: session.id) } label: {
                        Text(rating.title).font(.system(size: 14, weight: .medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .foregroundStyle(selected ? .white : Palette.ink)
                            .background(selected ? Palette.green : .white, in: RoundedRectangle(cornerRadius: 11))
                            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(selected ? Palette.green : Palette.line))
                    }.buttonStyle(.plain).accessibilityLabel("评价：\(rating.title)\(selected ? "，已选择" : "")")
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("完成后的感受（选填）").font(.system(size: 12, weight: .medium))
                NativeTextEditor(text: model.reviewReflectionBinding(session.id), placeholder: "写下完成这颗番茄后的感受…", fontSize: 13)
                    .padding(.horizontal, 10).frame(height: 135)
                    .background(.white, in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Palette.line))
            }
            if let error = model.saveError {
                Text(error).font(.system(size: 10)).foregroundStyle(.red).lineLimit(2)
            } else if let active = model.planner.activeTimer, active.phase != .focus {
                Text("正在\(active.phase.title) · 剩余 \(timerText(active.remaining(at: model.timerNow)))")
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(Palette.secondary)
            } else {
                Text("感受自动保存，可在最近专注记录中再次查看。")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            HStack {
                Button("稍后再评") { model.dismissReview() }.buttonStyle(QuietButton())
                Spacer()
                Button("保存评价") { model.submitReview(session.id) }
                    .buttonStyle(QuietButton(active: true)).disabled(session.review?.rating == nil)
            }
        }
    }
}

func durationText(_ seconds: Int) -> String { "\(seconds / 60) 分 \(seconds % 60) 秒" }
