import XCTest
import AppKit
import SwiftUI
import DaylightCore
@testable import DaylightGoals

@MainActor final class CompositionTests: XCTestCase {
    private func pump(_ seconds: TimeInterval = 0.06) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
    private func findTextView(in view: NSView) -> NSTextView? {
        if let text = view as? NSTextView { return text }
        return view.subviews.compactMap { findTextView(in: $0) }.first
    }
    func testCompositionSurvivesAutosaveAndCandidateConfirmation() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DaylightIME-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try AppModel(directory: directory)
        let day = Day(rawValue: "2026-10-25")
        model.select(day)
        model.dailyBinding(.expected, day: day).wrappedValue = "计划："
        let host = NSHostingView(rootView: DailyCard(day: day, field: .expected).environmentObject(model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 350), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        await pump()
        let textView = try XCTUnwrap(findTextView(in: host))
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(textView.hasMarkedText())
        await pump(0.45) // Includes the real 350 ms autosave callback and SwiftUI update pass.
        XCTAssertTrue(textView.hasMarkedText(), "Saving must not end the IME composition")
        XCTAssertEqual(textView.string, "计划：zhong")
        XCTAssertEqual(model.planner.record(on: day).expected, "计划：", "Provisional pinyin must not be sent back through the model")
        model.saveStatus = "测试保存状态刷新"
        model.refreshClock()
        model.flush()
        await pump()
        XCTAssertTrue(textView.hasMarkedText())
        XCTAssertEqual(textView.string, "计划：zhong")
        textView.insertText("中文", replacementRange: textView.markedRange())
        await pump(0.45)
        XCTAssertEqual(textView.string, "计划：中文")
        XCTAssertEqual(model.planner.record(on: day).expected, "计划：中文")
        XCTAssertEqual(try model.disk.load().record(on: day).expected, "计划：中文")
    }

    func testRepeatedMarkedUpdatesDoNotOverwriteEmojiOrSuffix() async throws {
        _ = NSApplication.shared
        var committed = "🌱计划，继续"
        let binding = Binding(get: { committed }, set: { committed = $0 })
        let coordinator = NativeTextEditor.Coordinator(binding: binding)
        let view = CompositionTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.string = committed
        view.onCommittedChange = { coordinator.receive($0) }
        view.setSelectedRange(NSRange(location: ("🌱计划" as NSString).length, length: 0))
        for syllable in ["zh", "zhong", "zhongwen"] {
            view.setMarkedText(syllable, selectedRange: NSRange(location: syllable.utf16.count, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            let selected = view.selectedRange()
            coordinator.synchronize(view, binding: binding)
            XCTAssertTrue(view.hasMarkedText())
            XCTAssertEqual(view.string, "🌱计划\(syllable)，继续")
            XCTAssertEqual(view.selectedRange(), selected)
            XCTAssertEqual(committed, "🌱计划，继续")
        }
        view.insertText("中文", replacementRange: view.markedRange())
        coordinator.synchronize(view, binding: binding)
        XCTAssertEqual(committed, "🌱计划中文，继续")
        XCTAssertEqual(view.string, committed)
    }

    func testUnmarkConfirmsCandidateAndEmptyMarkedTextFinishesDeletion() async throws {
        _ = NSApplication.shared
        var committed = "旧目标"
        let binding = Binding(get: { committed }, set: { committed = $0 })
        let coordinator = NativeTextEditor.Coordinator(binding: binding)
        let view = CompositionTextView(frame: .zero)
        view.string = committed
        view.onCommittedChange = { coordinator.receive($0) }
        view.setMarkedText("新目标", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: 0, length: 3))
        XCTAssertEqual(committed, "旧目标")
        view.unmarkText()
        XCTAssertEqual(committed, "新目标")
        view.setMarkedText("shan", selectedRange: NSRange(location: 4, length: 0), replacementRange: NSRange(location: 0, length: 3))
        view.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: view.markedRange())
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(committed, "")
        coordinator.synchronize(view, binding: binding)
        XCTAssertEqual(view.string, "")
    }

    func testSwitchingDatesAndClosingPreserveUnfinishedCompositionInOriginalField() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DaylightIME-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try AppModel(directory: directory)
        let oldDay = Day(rawValue: "2026-10-25")
        model.select(oldDay)
        let host = NSHostingView(rootView: DailyCard(day: oldDay, field: .actual).environmentObject(model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 350), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        await pump()
        let view = try XCTUnwrap(findTextView(in: host) as? CompositionTextView)
        XCTAssertTrue(window.makeFirstResponder(view))
        view.setMarkedText("待确认的中文", selectedRange: NSRange(location: 6, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(model.planner.record(on: oldDay).actual, "")
        let delegate = AppDelegate()
        delegate.model = model
        XCTAssertTrue(delegate.windowShouldClose(window)) // Actual close/save code path.
        model.select(oldDay.adding(1))
        XCTAssertEqual(try model.disk.load().record(on: oldDay).actual, "待确认的中文")
        XCTAssertEqual(model.planner.record(on: oldDay).expected, "")
        XCTAssertTrue(model.planner.record(on: oldDay.adding(1)).isEmpty)
    }

    func testUndoRedoAndPlainEnglishStillSynchronize() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DaylightIME-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try AppModel(directory: directory)
        let day = Day(rawValue: "2026-10-25")
        let host = NSHostingView(rootView: WritingArea(text: model.dailyBinding(.expected, day: day), placeholder: "目标", minHeight: 140).environmentObject(model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 350), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        await pump()
        let view = try XCTUnwrap(findTextView(in: host) as? CompositionTextView)
        XCTAssertTrue(window.makeFirstResponder(view))
        let undo = try XCTUnwrap(view.undoManager)
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        view.insertText("English\n中文 🌱", replacementRange: NSRange(location: NSNotFound, length: 0))
        undo.endUndoGrouping()
        await pump()
        XCTAssertEqual(model.planner.record(on: day).expected, "English\n中文 🌱")
        XCTAssertTrue(undo.canUndo)
        undo.undo()
        XCTAssertEqual(view.string, "")
        XCTAssertEqual(model.planner.record(on: day).expected, "")
        undo.redo()
        XCTAssertEqual(view.string, "English\n中文 🌱")
        XCTAssertEqual(model.planner.record(on: day).expected, "English\n中文 🌱")
    }
}
