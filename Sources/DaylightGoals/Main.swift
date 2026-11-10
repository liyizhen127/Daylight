import AppKit
import SwiftUI
import DaylightCore

final class ClotheslinePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@main enum DaylightMain {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var model: AppModel!
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var timer: Timer?
    var clothesline: ClotheslinePanel!
    var goalEditor: NSWindow?
    var globalClickMonitor: Any?
    var localClickMonitor: Any?
    var restoreClothesline = false
    var isTerminating = false
    private var statusKey = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let args = ProcessInfo.processInfo.arguments
        let explicitPath = args.firstIndex(of: "--data-dir").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        let directory = explicitPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DaylightGoals", isDirectory: true)
        do { model = try AppModel(directory: directory, demo: explicitPath != nil && args.contains("--demo")) }
        catch {
            let alert = NSAlert(); alert.messageText = "无法打开Daylight"; alert.informativeText = error.localizedDescription
            alert.runModal(); NSApp.terminate(nil); return
        }
        createMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1260, height: 880),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Daylight"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(calibratedRed: 0.976, green: 0.973, blue: 0.956, alpha: 1)
        window.appearance = NSAppearance(named: .aqua)
        window.minSize = NSSize(width: 1040, height: 700)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("DaylightMainWindow")
        window.contentView = NSHostingView(rootView: PlannerView().environmentObject(model).environment(\.colorScheme, .light))
        window.center()
        model.onPin = { [weak self] pinned in self?.window.level = pinned ? .floating : .normal }
        setupStatusItem()
        createClothesline()
        showClothesline()
        model.onTimerChange = { [weak self] in self?.updateStatusItem() }
        model.tick()
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
    }
    private func createMenu() {
        let main = NSMenu()
        let app = NSMenuItem(); let appMenu = NSMenu()
        add(appMenu, "关于Daylight", #selector(about), "")
        appMenu.addItem(.separator())
        add(appMenu, "隐藏Daylight", #selector(NSApplication.hide(_:)), "h", target: NSApp)
        appMenu.addItem(.separator())
        add(appMenu, "退出Daylight", #selector(NSApplication.terminate(_:)), "q", target: NSApp)
        app.submenu = appMenu; main.addItem(app)
        let file = NSMenuItem(title: "文件", action: nil, keyEquivalent: ""); let fileMenu = NSMenu(title: "文件")
        add(fileMenu, "回到今天", #selector(today), "t")
        add(fileMenu, "保存", #selector(save), "s")
        fileMenu.addItem(.separator())
        add(fileMenu, "导出当天 Markdown…", #selector(exportDay), "e")
        add(fileMenu, "导出完整备份…", #selector(backup), "")
        add(fileMenu, "恢复备份…", #selector(restore), "")
        fileMenu.addItem(.separator())
        add(fileMenu, "关闭窗口", #selector(NSWindow.performClose(_:)), "w", target: nil)
        file.submenu = fileMenu; main.addItem(file)
        let edit = NSMenuItem(title: "编辑", action: nil, keyEquivalent: ""); let editMenu = NSMenu(title: "编辑")
        add(editMenu, "撤销", Selector(("undo:")), "z", target: nil)
        let redo = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z"); redo.keyEquivalentModifierMask = [.command, .shift]; editMenu.addItem(redo)
        editMenu.addItem(.separator())
        for (name, selector, key) in [("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] {
            add(editMenu, name, selector, key, target: nil)
        }
        edit.submenu = editMenu; main.addItem(edit)
        let view = NSMenuItem(title: "显示", action: nil, keyEquivalent: ""); let viewMenu = NSMenu(title: "显示")
        add(viewMenu, "每日计划", #selector(daily), "1")
        add(viewMenu, "一周回顾", #selector(review), "2")
        add(viewMenu, "番茄钟与日历设置…", #selector(pomodoroSettings), ",")
        add(viewMenu, "展开 / 收起挂衣绳", #selector(toggleClothesline), "l")
        viewMenu.addItem(.separator())
        add(viewMenu, "上一周", #selector(previousWeek), "[")
        add(viewMenu, "下一周", #selector(nextWeek), "]")
        add(viewMenu, "窗口置顶 / 取消置顶", #selector(pin), "")
        view.submenu = viewMenu; main.addItem(view)
        let help = NSMenuItem(title: "帮助", action: nil, keyEquivalent: ""); let helpMenu = NSMenu(title: "帮助")
        add(helpMenu, "使用说明", #selector(about), "?")
        add(helpMenu, "打开数据文件夹", #selector(dataFolder), "")
        help.submenu = helpMenu; main.addItem(help)
        NSApp.mainMenu = main
    }
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String, target: AnyObject? = nil) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? (["undo:", "cut:", "copy:", "paste:", "selectAll:", "performClose:"].contains(action.description) ? nil : self)
        menu.addItem(item)
    }
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItem()
        statusItem.button?.toolTip = "Daylight · 点击展开挂衣绳，右键打开菜单"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
    func updateStatusItem() {
        guard let button = statusItem?.button, let model else { return }
        if let active = model.planner.activeTimer {
            let name = active.phase == .focus ? active.title : active.phase.title
            let time = timerText(active.remaining(at: model.timerNow))
            let key = "\(name)-\(time)-\(button.effectiveAppearance.name.rawValue)"
            guard key != statusKey else { return }; statusKey = key
            button.title = ""
            button.imagePosition = .imageOnly
            button.image = StatusBadge.image(name: name, time: time)
            button.toolTip = "\(active.phase.title) · \(active.title) · 剩余 \(time)\n左键挂衣绳 · 右键选择番茄任务"
            button.setAccessibilityLabel("\(active.phase.title) \(active.title) 剩余 \(time)")
        } else {
            let count = model.planner.completedPomodoros(on: model.today)
            let key = "idle-\(count)"
            guard statusKey != key else { return }; statusKey = key
            button.image = TomatoArtwork.menuIcon
            button.imagePosition = .imageLeft
            button.title = " \(count)"
            button.font = .systemFont(ofSize: 14, weight: .semibold)
            button.toolTip = "今日已完成 \(count) 颗番茄 · 左键挂衣绳 · 右键开始专注"
            button.setAccessibilityLabel("Daylight 今日已完成 \(count) 颗番茄")
        }
    }
    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showStatusMenu() }
        else { toggleClothesline() }
    }
    private func showStatusMenu() {
        statusItem.menu = makeStatusMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
    func makeStatusMenu() -> NSMenu {
        model.tick()
        let menu = NSMenu()
        if let active = model.planner.activeTimer {
            let info = NSMenuItem(title: "\(active.phase.title)：\(active.title)  \(timerText(active.remaining(at: model.timerNow)))", action: nil, keyEquivalent: "")
            info.isEnabled = false; menu.addItem(info)
            add(menu, active.phase == .focus ? "中断本次专注（保留时段）" : "跳过休息", #selector(stopPomodoro), "")
        } else {
            let heading = NSMenuItem(title: "今日任务 · 选择开始专注", action: nil, keyEquivalent: "")
            heading.isEnabled = false; menu.addItem(heading)
            let tasks = model.planner.record(on: model.today).tasks
            for task in tasks {
                let count = model.planner.actualPomodoros(taskID: task.id, on: model.today)
                let title = "\(task.isCompleted ? "☑" : "☐") \(task.title)  · 🍅 \(count)/\(task.estimatedPomodoros)"
                let item = NSMenuItem(title: title, action: #selector(startPomodoro(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = task.id.uuidString
                item.isEnabled = !model.loadFailed && !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                menu.addItem(item)
            }
            if tasks.isEmpty { add(menu, "添加今天的任务…", #selector(editToday), "") }
        }
        add(menu, "番茄钟与日历设置…", #selector(pomodoroSettings), "")
        menu.addItem(.separator())
        add(menu, clothesline?.isVisible == true ? "收起挂衣绳" : "展开挂衣绳", #selector(toggleClothesline), "")
        add(menu, "编辑今天的目标", #selector(editToday), "")
        add(menu, "打开完整计划", #selector(showWindow), "")
        add(menu, "一周回顾", #selector(review), "")
        menu.addItem(.separator())
        add(menu, "导出完整备份…", #selector(backup), "")
        menu.addItem(.separator())
        add(menu, "退出Daylight", #selector(NSApplication.terminate(_:)), "q", target: NSApp)
        return menu
    }
    @objc private func startPomodoro(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = UUID(uuidString: raw) else { return }
        model.startFocus(id, day: model.today)
    }
    @objc private func stopPomodoro() { model.stopTimer() }
    @objc func pomodoroSettings() { showWindow(); model.showingPomodoroSettings = true }
    private func createClothesline() {
        clothesline = ClotheslinePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        clothesline.title = "Daylight · 目标挂衣绳"
        clothesline.isFloatingPanel = true
        clothesline.level = .floating
        clothesline.isOpaque = false
        clothesline.backgroundColor = .clear
        clothesline.hasShadow = false
        clothesline.hidesOnDeactivate = false
        clothesline.isReleasedWhenClosed = false
        clothesline.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        clothesline.appearance = NSAppearance(named: .aqua)
        clothesline.contentView = NSHostingView(rootView: ClotheslineView(
            edit: { [weak self] scope, day in self?.openGoalEditor(scope, day: day) },
            dashboard: { [weak self] in self?.showWindow() },
            hide: { [weak self] in self?.hideClothesline() }
        ).environmentObject(model).environment(\.colorScheme, .light))
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissClotheslineIfOutside()
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.dismissClotheslineIfOutside()
            return event
        }
    }
    private func dismissClotheslineIfOutside() {
        guard clothesline.isVisible, !model.ropePinned else { return }
        let point = NSEvent.mouseLocation
        guard !clothesline.frame.contains(point), !(statusItem.button?.window?.frame.contains(point) ?? false) else { return }
        hideClothesline()
    }
    @objc func showClothesline() {
        guard goalEditor == nil else { goalEditor?.makeKeyAndOrderFront(nil); return }
        model.refreshClock()
        let screen = statusItem.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let width = min(1160, screen.visibleFrame.width - 24)
        let height = min(738, screen.visibleFrame.height - 20)
        clothesline.setFrame(NSRect(x: screen.visibleFrame.midX - width / 2, y: screen.visibleFrame.maxY - height - 8, width: width, height: height), display: true)
        model.ropeVisible = true
        clothesline.orderFrontRegardless()
        statusItem.button?.highlight(true)
    }
    @objc func hideClothesline() {
        model.ropeVisible = false
        clothesline.orderOut(nil)
        statusItem.button?.highlight(false)
    }
    @objc func toggleClothesline() {
        if let editor = goalEditor {
            restoreClothesline = true
            editor.performClose(nil)
            return
        }
        clothesline.isVisible ? hideClothesline() : showClothesline()
    }
    @objc func editToday() { openGoalEditor(.daily, day: model.today) }
    private func openGoalEditor(_ scope: EditorScope, day: Day) {
        if let editor = goalEditor { editor.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        model.select(day)
        window.orderOut(nil)
        restoreClothesline = true
        hideClothesline()
        let editor = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 750),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        editor.title = "Daylight · 编辑目标"
        editor.titlebarAppearsTransparent = true
        editor.titleVisibility = .hidden
        editor.backgroundColor = NSColor(calibratedRed: 0.976, green: 0.973, blue: 0.956, alpha: 1)
        editor.appearance = NSAppearance(named: .aqua)
        editor.minSize = NSSize(width: 790, height: 600)
        editor.isReleasedWhenClosed = false
        editor.delegate = self
        editor.level = .floating
        editor.contentView = NSHostingView(rootView: HangingEditorView(scope: scope, close: { [weak self] in self?.goalEditor?.performClose(nil) })
            .environmentObject(model).environment(\.colorScheme, .light))
        goalEditor = editor
        editor.center()
        editor.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func showWindow() {
        if let editor = goalEditor {
            commitActiveTextEditing(in: editor)
            guard model.flush() || model.loadFailed else { editor.makeKeyAndOrderFront(nil); return }
            restoreClothesline = false
            editor.close()
        }
        hideClothesline()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func today() { model.goToday(); showWindow() }
    @objc func daily() { model.setReview(false); showWindow() }
    @objc func review() { model.setReview(true); showWindow() }
    @objc func previousWeek() { model.moveWeek(-1) }
    @objc func nextWeek() { model.moveWeek(1) }
    @objc func save() { commitActiveTextEditing(); model.flush() }
    @objc func exportDay() { model.exportMarkdown() }
    @objc func backup() { showWindow(); model.exportBackup() }
    @objc func restore() { showWindow(); model.restoreBackup() }
    @objc func dataFolder() { model.revealData() }
    @objc func pin() { model.togglePin() }
    @objc func about() { showWindow(); model.showingHelp = true }
    @objc func wake() { model.tick() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showClothesline(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func windowShouldClose(_ sender: NSWindow) -> Bool { commitActiveTextEditing(in: sender); return model.flush() || model.loadFailed }
    func windowWillClose(_ notification: Notification) {
        if let closed = notification.object as? NSWindow, closed === goalEditor {
            goalEditor = nil
            let shouldRestore = restoreClothesline && !isTerminating
            restoreClothesline = false
            if shouldRestore { DispatchQueue.main.async { [weak self] in self?.showClothesline() } }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        commitActiveTextEditing(in: goalEditor)
        commitActiveTextEditing(in: window)
        guard model != nil else { return .terminateNow }
        if model.flush() || model.loadFailed { isTerminating = true; return .terminateNow }
        let alert = NSAlert(); alert.messageText = "还有更改未能保存"
        alert.informativeText = "请先导出完整备份，或检查数据文件夹权限后重试。"
        alert.addButton(withTitle: "返回应用"); alert.runModal(); showWindow(); return .terminateCancel
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        timer?.invalidate()
    }
}
