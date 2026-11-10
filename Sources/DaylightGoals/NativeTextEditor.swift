import AppKit
import SwiftUI

/// NSTextView owns the provisional text until an input method confirms its candidate.
/// Model refreshes (including autosave status) must never replace that marked range.
final class CompositionTextView: NSTextView {
    var onCommittedChange: ((String) -> Void)?
    var placeholder = "" { didSet { if placeholder != oldValue { needsDisplay = true } } }
    private var inputMethodDepth = 0
    private var applyingModel = false

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        inputMethodDepth += 1
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        inputMethodDepth -= 1
        publishCommittedText() // Empty marked text can end/cancel composition without insertText.
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        inputMethodDepth += 1
        super.insertText(string, replacementRange: replacementRange)
        inputMethodDepth -= 1
        publishCommittedText()
    }

    override func unmarkText() {
        inputMethodDepth += 1
        super.unmarkText()
        inputMethodDepth -= 1
        // Some input methods confirm through unmarkText without another textDidChange.
        publishCommittedText()
    }

    override func didChangeText() {
        super.didChangeText()
        publishCommittedText() // Also covers delete, cut, paste, undo and redo.
    }

    private func publishCommittedText() {
        needsDisplay = true
        guard !applyingModel, inputMethodDepth == 0, !hasMarkedText() else { return }
        onCommittedChange?(string)
    }

    /// Called before changing a date/scope or closing the window, while its old binding still exists.
    func finishComposition() {
        if hasMarkedText() {
            unmarkText() // Preserve the currently visible text, even for an unfinished syllable.
            inputContext?.discardMarkedText()
        }
        publishCommittedText()
    }

    override func resignFirstResponder() -> Bool {
        finishComposition()
        return super.resignFirstResponder()
    }

    func applyModelText(_ value: String) {
        guard !hasMarkedText(), inputMethodDepth == 0, value != string else { return }
        let selection = selectedRange()
        applyingModel = true
        string = value
        applyingModel = false
        let length = (value as NSString).length
        let location = min(selection.location, length)
        setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
        // A real external replacement (e.g. restoring a backup) starts a fresh undo history.
        undoManager?.removeAllActions(withTarget: self)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText(), !placeholder.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 7
        let x = textContainerInset.width + (textContainer?.lineFragmentPadding ?? 5)
        let rect = NSRect(x: x, y: textContainerInset.height, width: max(0, bounds.width - x * 2), height: bounds.height)
        (placeholder as NSString).draw(in: rect, withAttributes: [
            .font: font ?? NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor(calibratedRed: 0.467, green: 0.502, blue: 0.471, alpha: 0.72),
            .paragraphStyle: paragraph
        ])
    }
}

struct NativeTextEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let fontSize: CGFloat
    var strikethrough = false
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(binding: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let view = CompositionTextView(frame: .zero)
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.drawsBackground = false
        view.font = .systemFont(ofSize: fontSize)
        view.textColor = NSColor(calibratedRed: 0.188, green: 0.239, blue: 0.208, alpha: 1)
        view.insertionPointColor = .controlAccentColor
        view.textContainerInset = NSSize(width: 0, height: 8)
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 7
        view.defaultParagraphStyle = paragraph
        view.typingAttributes = [.font: view.font!, .foregroundColor: view.textColor!, .paragraphStyle: paragraph]
        view.applyModelText(text)
        view.placeholder = placeholder
        view.isEditable = isEnabled
        view.setAccessibilityLabel(placeholder.components(separatedBy: "\n").first ?? "目标内容")
        view.onCommittedChange = { [weak coordinator = context.coordinator] value in coordinator?.receive(value) }
        scroll.documentView = view
        applyStyle(view)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? CompositionTextView else { return }
        context.coordinator.synchronize(view, binding: $text)
        view.placeholder = placeholder
        if view.isEditable != isEnabled { view.isEditable = isEnabled }
        // Never change text attributes while the input method owns a marked range.
        if !view.hasMarkedText(), view.font?.pointSize != fontSize { view.font = .systemFont(ofSize: fontSize) }
        if !view.hasMarkedText() { applyStyle(view) }
    }

    private func applyStyle(_ view: CompositionTextView) {
        let range = NSRange(location: 0, length: (view.string as NSString).length)
        let style = strikethrough ? NSUnderlineStyle.single.rawValue : 0
        if range.length > 0, (view.textStorage?.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int ?? 0) != style {
            view.textStorage?.addAttribute(.strikethroughStyle, value: style, range: range)
        }
        view.typingAttributes[.strikethroughStyle] = style
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        (scroll.documentView as? CompositionTextView)?.onCommittedChange = nil
    }

    final class Coordinator {
        private var binding: Binding<String>
        init(binding: Binding<String>) { self.binding = binding }
        func receive(_ value: String) {
            guard binding.wrappedValue != value else { return }
            binding.wrappedValue = value
        }
        func synchronize(_ view: CompositionTextView, binding: Binding<String>) {
            self.binding = binding
            view.applyModelText(binding.wrappedValue)
        }
    }
}

/// End composition before the SwiftUI identity/binding is changed or destroyed.
@MainActor func commitActiveTextEditing() { commitActiveTextEditing(in: NSApp.keyWindow) }

@MainActor func commitActiveTextEditing(in window: NSWindow?) {
    guard let window else { return }
    (window.firstResponder as? CompositionTextView)?.finishComposition()
    window.makeFirstResponder(nil)
}
