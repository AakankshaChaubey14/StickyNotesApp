// One editable task line. A plain NSTextView so the strike-through can be drawn from the real
// text layout: one stroke per wrapped line, through the middle of the lowercase letters, exactly
// as long as the words on that line. Copy, cut, paste and select-all are handled here directly,
// so they work even though the panel never activates the app.

import AppKit
import SwiftUI

final class TaskTextView: FormattingTextView {
    var onReturn: (() -> Void)?
    var onPasteLines: (([String]) -> Void)?
    var onDeleteWhenEmpty: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    var placeholder: NSAttributedString? { didSet { needsDisplay = true } }
    var strikeColor: NSColor = .black { didSet { needsDisplay = true } }

    private(set) var struck = false
    private var progress: CGFloat = 0
    private var animation: Timer?

    func setStruck(_ on: Bool, animated: Bool) {
        guard on != struck else { return }
        struck = on
        animation?.invalidate()
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            progress = on ? 1 : 0; needsDisplay = true; return
        }
        let from = progress, to: CGFloat = on ? 1 : 0, start = CACurrentMediaTime()
        let duration = on ? 0.26 : 0.16
        animation = Timer.scheduledTimer(withTimeInterval: 1 / 120, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { t.invalidate(); return }
                let k = min(1, (CACurrentMediaTime() - start) / duration)
                let eased = 1 - pow(1 - k, 4)                       // strong ease-out
                self.progress = from + (to - from) * eased
                self.needsDisplay = true
                if k >= 1 { t.invalidate() }
            }
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty, let placeholder { placeholder.draw(at: textContainerOrigin) }
        guard progress > 0, let lm = layoutManager, let tc = textContainer, let font else { return }
        let lines = strikeLines(lm, tc, font)
        var budget = lines.reduce(0) { $0 + $1.width } * progress   // draw line by line, left to right
        strikeColor.setStroke()
        for line in lines where budget > 0 {
            let w = min(line.width, budget); budget -= w
            let path = NSBezierPath()
            path.move(to: CGPoint(x: line.minX, y: line.midY))
            path.line(to: CGPoint(x: line.minX + w, y: line.midY))
            path.lineWidth = 1.5; path.lineCapStyle = .round
            path.stroke()
        }
    }

    /// One rect per wrapped line: from the first to the last visible character (trailing spaces ignored),
    /// vertically on the middle of the x-height of that line.
    private func strikeLines(_ lm: NSLayoutManager, _ tc: NSTextContainer, _ font: NSFont) -> [CGRect] {
        let ns = string as NSString
        var out: [CGRect] = []
        let origin = textContainerOrigin
        lm.enumerateLineFragments(forGlyphRange: lm.glyphRange(for: tc)) { rect, _, _, glyphs, _ in
            var chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            while chars.length > 0, let u = UnicodeScalar(ns.character(at: chars.location + chars.length - 1)),
                  CharacterSet.whitespacesAndNewlines.contains(u) { chars.length -= 1 }
            guard chars.length > 0 else { return }
            let trimmed = lm.glyphRange(forCharacterRange: chars, actualCharacterRange: nil)
            let box = lm.boundingRect(forGlyphRange: trimmed, in: tc)
            let baseline = lm.location(forGlyphAt: glyphs.location).y
            let y = rect.minY + baseline - font.xHeight / 2 + origin.y
            out.append(CGRect(x: box.minX + origin.x - 2, y: y, width: box.width + 4, height: 0))
        }
        return out
    }

    override func didChangeText() { super.didChangeText(); needsDisplay = true }

    // MARK: Keys

    override func doCommand(by selector: Selector) {
        if selector == #selector(insertNewline(_:)) || selector == #selector(insertLineBreak(_:)) { onReturn?(); return }
        if selector == #selector(deleteBackward(_:)), string.isEmpty { onDeleteWhenEmpty?(); return }
        super.doCommand(by: selector)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        if formatKey(event) { return true }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch (mods, event.charactersIgnoringModifiers?.lowercased()) {
        case (.command, "c"): copy(nil); return true
        case (.command, "x"): cut(nil); return true
        case (.command, "v"), ([.command, .option, .shift], "v"): paste(nil); return true
        case (.command, "a"): selectAll(nil); return true
        case (.command, "z"): undoManager?.undo(); return true
        case ([.command, .shift], "z"): undoManager?.redo(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    /// Always plain text. Several non-empty lines become several tasks.
    override func paste(_ sender: Any?) {
        guard let s = NSPasteboard.general.string(forType: .string) else { return }
        let lines = Store.lines(from: s)
        if lines.count > 1, let onPasteLines { onPasteLines(lines); return }
        insertText(lines.first ?? s.trimmingCharacters(in: .whitespacesAndNewlines), replacementRange: selectedRange())
    }
    override func pasteAsPlainText(_ sender: Any?) { paste(sender) }
    override func pasteAsRichText(_ sender: Any?) { paste(sender) }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder(); if ok { onFocusChange?(true) }; return ok
    }
    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok {
            onFocusChange?(false)
            resigning = true                     // keep lastSelection for the B / I buttons
            setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
            resigning = false
        }
        return ok
    }
}

/// SwiftUI wrapper. Height follows the wrapped text; width comes from the row.
struct TaskText: NSViewRepresentable {
    @Binding var content: NotepadDoc             // the words and which of them are bold / italic
    var done: Bool
    var faces: NoteFaces
    var controller: FormatController
    var font: NSFont { faces.regular }
    var ink: NSColor
    var doneInk: NSColor
    var strike: NSColor
    var placeholder: String? = nil
    var placeholderFont: NSFont? = nil
    var focusRequested = false
    var onReturn: () -> Void = {}
    var onPasteLines: ([String]) -> Void = { _ in }
    var onDeleteWhenEmpty: () -> Void = {}
    var onFocusChange: (Bool) -> Void = { _ in }
    var onFocused: () -> Void = {}

    func makeNSView(context: Context) -> TaskTextView {
        let v = TaskTextView(frame: .zero)
        v.isRichText = true                      // for bold / italic; pasting still brings plain text
        v.importsGraphics = false
        v.allowsUndo = true
        v.drawsBackground = false
        v.isVerticallyResizable = true
        v.isHorizontallyResizable = false
        v.textContainerInset = .zero
        v.textContainer?.lineFragmentPadding = 0
        v.textContainer?.widthTracksTextView = true
        v.focusRingType = .none
        v.isAutomaticQuoteSubstitutionEnabled = false
        v.isAutomaticDashSubstitutionEnabled = false
        v.isAutomaticTextReplacementEnabled = false
        v.delegate = context.coordinator
        v.faces = faces
        v.ink = done ? doneInk : ink
        v.formatController = controller
        v.load(content)
        v.setStruck(done, animated: false)
        return v
    }

    func updateNSView(_ v: TaskTextView, context: Context) {
        context.coordinator.parent = self
        let inkNow = done ? doneInk : ink
        if v.faces != faces || v.ink != inkNow { v.faces = faces; v.ink = inkNow; v.restyle() }
        if v.doc != content { v.load(content) }          // changed from outside, not by typing here
        v.formatController = controller
        v.insertionPointColor = ink
        v.selectedTextAttributes = [.backgroundColor: ink.withAlphaComponent(0.14)]
        v.strikeColor = strike
        v.setStruck(done, animated: true)
        v.placeholder = placeholder.map {
            NSAttributedString(string: $0, attributes: [.font: placeholderFont ?? font, .foregroundColor: doneInk])
        }
        v.onReturn = onReturn
        v.onPasteLines = onPasteLines
        v.onDeleteWhenEmpty = onDeleteWhenEmpty
        v.onFocusChange = onFocusChange
        if focusRequested {
            DispatchQueue.main.async {
                if let w = v.window, w.firstResponder !== v { w.makeKey(); w.makeFirstResponder(v) }
                onFocused()
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView v: TaskTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 200
        guard let lm = v.layoutManager, let tc = v.textContainer else { return nil }
        tc.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        lm.ensureLayout(for: tc)
        let line = lm.defaultLineHeight(for: font)
        return CGSize(width: width, height: max(ceil(lm.usedRect(for: tc).height), ceil(line)))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TaskText
        init(_ p: TaskText) { parent = p }
        func textDidChange(_ n: Notification) {
            guard let v = n.object as? TaskTextView else { return }
            parent.content = v.doc
            v.invalidateIntrinsicContentSize()
        }
        func textViewDidChangeSelection(_ n: Notification) {
            guard let v = n.object as? TaskTextView, v.window?.firstResponder === v else { return }
            MainActor.assumeIsolated { parent.controller.refresh() }
        }
    }
}

extension NSFont {
    /// Distance from the top of a line to the middle of its lowercase letters.
    var firstLineXMid: CGFloat { NSLayoutManager().defaultBaselineOffset(for: self) - xHeight / 2 }
}
