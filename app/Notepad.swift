// The notepad page: free text with bold and italic. Formatting is kept as flags on the text,
// not as fonts, so bold and italic words survive switching looks (and with them, fonts).

import AppKit
import SwiftUI

struct NotepadDoc: Codable, Equatable {
    struct Run: Codable, Equatable { var location: Int; var length: Int; var bold: Bool; var italic: Bool }
    var text = ""
    var runs: [Run] = []                 // UTF-16 ranges, only where something is bold or italic

    /// Without surrounding whitespace and newlines, runs shifted to match.
    func trimmed() -> NotepadDoc {
        let ns = text as NSString
        let set = CharacterSet.whitespacesAndNewlines
        var start = 0, end = ns.length
        while start < end, let u = UnicodeScalar(ns.character(at: start)), set.contains(u) { start += 1 }
        while end > start, let u = UnicodeScalar(ns.character(at: end - 1)), set.contains(u) { end -= 1 }
        let kept = runs.compactMap { r -> Run? in
            let lo = max(r.location, start), hi = min(r.location + r.length, end)
            return hi > lo ? Run(location: lo - start, length: hi - lo, bold: r.bold, italic: r.italic) : nil
        }
        return NotepadDoc(text: ns.substring(with: NSRange(location: start, length: end - start)), runs: kept)
    }
}

extension NSAttributedString.Key {
    static let noteBold = NSAttributedString.Key("scrapbook.bold")
    static let noteItalic = NSAttributedString.Key("scrapbook.italic")
}

/// The four faces of a look's font. Courier Prime has no bold, so torn paper fakes it with a heavier
/// outline; brass already writes in semibold, so its bold gets a lighter extra outline to stand out.
struct NoteFaces: Equatable {
    let regular, bold, italic, boldItalic: NSFont
    let boldOutline: CGFloat                 // extra stroke for bold, as a percentage of the font size; 0 for none

    static func of(_ style: NoteStyle, size: CGFloat) -> NoteFaces {
        func f(_ name: String) -> NSFont { NSFont(name: name, size: size) ?? .systemFont(ofSize: size * 0.8) }
        switch style {
        case .brass: return NoteFaces(regular: f("CormorantGaramond-SemiBold"), bold: f("CormorantGaramond-Bold"),
                                      italic: f("CormorantGaramond-SemiBoldItalic"), boldItalic: f("CormorantGaramond-BoldItalic"), boldOutline: 2)
        case .wax: return NoteFaces(regular: f("EBGaramond-Regular"), bold: f("EBGaramond-Bold"),
                                    italic: f("EBGaramond-Italic"), boldItalic: f("EBGaramond-BoldItalic"), boldOutline: 0)
        case .torn: return NoteFaces(regular: f("CourierPrime-Regular"), bold: f("CourierPrime-Regular"),
                                     italic: f("CourierPrime-Italic"), boldItalic: f("CourierPrime-Italic"), boldOutline: 3.5)
        }
    }

    func attributes(bold: Bool, italic: Bool, ink: NSColor) -> [NSAttributedString.Key: Any] {
        var a: [NSAttributedString.Key: Any] = [.foregroundColor: ink, .noteBold: bold, .noteItalic: italic,
                                                .font: bold ? (italic ? boldItalic : self.bold) : (italic ? self.italic : regular)]
        if bold && boldOutline > 0 { a[.strokeWidth] = -boldOutline; a[.strokeColor] = ink }   // negative width: fill and outline
        return a
    }
}

/// A text view whose words can be bold or italic in the current look's fonts.
/// Shared by the notepad and the task lines.
class FormattingTextView: NSTextView {
    var faces: NoteFaces?
    var ink: NSColor = .black
    weak var formatController: FormatController?

    /// The selection as the user left it. Clicking a B / I button can take focus from the text,
    /// and task lines collapse their selection when they lose focus, so remember it.
    private(set) var lastSelection = NSRange(location: 0, length: 0)
    var resigning = false

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if !resigning { lastSelection = selectedRange() }
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { formatController?.attach(self) }
        return ok
    }

    /// The text's own right-click menu (Cut, Copy, Paste…), plus a way to quit.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        if !menu.items.contains(where: { $0.action == #selector(NSApplication.terminate(_:)) }) {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Sticky Note", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        }
        return menu
    }

    func flags(_ a: [NSAttributedString.Key: Any]) -> (Bool, Bool) { (a[.noteBold] as? Bool ?? false, a[.noteItalic] as? Bool ?? false) }

    /// Dresses every run in the current look's fonts, keeping its bold / italic flags.
    func restyle() {
        guard let faces, let ts = textStorage else { return }
        ts.beginEditing()
        ts.enumerateAttributes(in: NSRange(location: 0, length: ts.length)) { attrs, range, _ in
            let (b, i) = flags(attrs)
            ts.removeAttribute(.strokeWidth, range: range)
            ts.addAttributes(faces.attributes(bold: b, italic: i, ink: ink), range: range)
        }
        ts.endEditing()
        let (b, i) = flags(typingAttributes)
        typingAttributes = faces.attributes(bold: b, italic: i, ink: ink)
    }

    /// Is the selection (or, with nothing selected, what you're about to type) bold / italic?
    func isOn(_ key: NSAttributedString.Key) -> Bool {
        let r = selectedRange()
        guard r.length > 0, let ts = textStorage else { return typingAttributes[key] as? Bool ?? false }
        var all = true
        ts.enumerateAttribute(key, in: r) { v, _, stop in if !(v as? Bool ?? false) { all = false; stop.pointee = true } }
        return all
    }

    /// Bold / italic on the selection, or for the next thing typed when nothing is selected.
    func toggle(_ key: NSAttributedString.Key) {
        guard let faces else { return }
        let r = selectedRange(), on = !isOn(key)
        if r.length == 0 {
            var t = typingAttributes; t[key] = on
            let (b, i) = flags(t)
            typingAttributes = faces.attributes(bold: b, italic: i, ink: ink)
            return
        }
        guard let ts = textStorage, shouldChangeText(in: r, replacementString: nil) else { return }   // undoable
        ts.addAttribute(key, value: on, range: r)
        restyle()
        didChangeText()
    }

    var doc: NotepadDoc {
        var d = NotepadDoc(text: string)
        textStorage?.enumerateAttributes(in: NSRange(location: 0, length: textStorage?.length ?? 0)) { attrs, range, _ in
            let (b, i) = flags(attrs)
            if b || i { d.runs.append(.init(location: range.location, length: range.length, bold: b, italic: i)) }
        }
        return d
    }

    func load(_ d: NotepadDoc) {
        let keep = selectedRange()
        string = d.text
        let length = (d.text as NSString).length
        for run in d.runs where run.location >= 0 && run.length > 0 && run.location + run.length <= length {
            let range = NSRange(location: run.location, length: run.length)
            textStorage?.addAttributes([.noteBold: run.bold, .noteItalic: run.italic], range: range)
        }
        restyle()
        (self as? NotepadTextView)?.indentBullets()
        if NSMaxRange(keep) <= length { setSelectedRange(keep) }
    }

    private var length: Int { (string as NSString).length }

    /// ⌘B / ⌘I. Called from each subclass's own key handling.
    func formatKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "b": toggle(.noteBold)
        case "i": toggle(.noteItalic)
        default: return false
        }
        formatController?.refresh()
        return true
    }

    /// For the B / I buttons: put back the selection the user made, then format it.
    func toggleFromButton(_ key: NSAttributedString.Key) {
        let sel = lastSelection
        if let w = window, w.firstResponder !== self { w.makeKey(); w.makeFirstResponder(self) }
        if NSMaxRange(sel) <= length { setSelectedRange(sel) }
        toggle(key)
    }
}

final class NotepadTextView: FormattingTextView {
    var onFocusChange: ((Bool) -> Void)?
    var placeholder: NSAttributedString? { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty, let placeholder { placeholder.draw(at: textContainerOrigin) }
    }

    // MARK: Keys: the panel never activates the app, so handle the shortcuts here (as TaskTextView does).

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        if formatKey(event) { return true }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == [.command, .shift], event.keyCode == 26 { toggleBullets(); return true }   // ⇧⌘7, as in Apple Notes
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

    /// Pasting brings in the words, not someone else's fonts and colors.
    override func paste(_ sender: Any?) {
        guard let s = NSPasteboard.general.string(forType: .string) else { return }
        insertText(s, replacementRange: selectedRange())
    }

    // MARK: Bullets: plain "• " text at the start of a line. Typing "- " or "* " starts one,
    // Return carries the list on, Return on an empty bullet ends it, and ⇧⌘7 toggles lines.

    static let bullet = "• "

    /// Wrapped lines of a bullet start under its text, not under the dot.
    func indentBullets() {
        guard let faces, let ts = textStorage else { return }
        let ns = ts.string as NSString
        let indent = ceil((Self.bullet as NSString).size(withAttributes: [.font: faces.regular]).width)
        let plain = NSParagraphStyle.default, hanging = NSMutableParagraphStyle()
        hanging.headIndent = indent
        ts.beginEditing()
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs, .substringNotRequired]) { _, r, enclosing, _ in
            ts.addAttribute(.paragraphStyle, value: ns.substring(with: r).hasPrefix(Self.bullet) ? hanging : plain, range: enclosing)
        }
        ts.endEditing()
    }

    override func didChangeText() { super.didChangeText(); indentBullets() }

    private func line(at location: Int) -> NSRange { (string as NSString).lineRange(for: NSRange(location: location, length: 0)) }

    /// An undoable edit; inserted text gets the plain look, whatever is being typed.
    private func replace(_ range: NSRange, with text: String) {
        guard let faces, let ts = textStorage, shouldChangeText(in: range, replacementString: text) else { return }
        ts.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: faces.attributes(bold: false, italic: false, ink: ink)))
        didChangeText()
    }

    override func insertText(_ text: Any, replacementRange: NSRange) {
        super.insertText(text, replacementRange: replacementRange)
        guard ((text as? String) ?? (text as? NSAttributedString)?.string) == " " else { return }
        let caret = selectedRange().location, l = line(at: caret)
        let typed = (string as NSString).substring(with: NSRange(location: l.location, length: caret - l.location))
        guard typed == "- " || typed == "* " else { return }
        replace(NSRange(location: l.location, length: 2), with: Self.bullet)
        setSelectedRange(NSRange(location: l.location + 2, length: 0))
    }

    override func insertNewline(_ sender: Any?) {
        let l = line(at: selectedRange().location)
        let content = (string as NSString).substring(with: l).trimmingCharacters(in: .newlines)
        guard content.hasPrefix(Self.bullet) else { super.insertNewline(sender); return }
        if content == Self.bullet {                       // an empty bullet: end the list
            replace(NSRange(location: l.location, length: 2), with: "")
            setSelectedRange(NSRange(location: l.location, length: 0))
            return
        }
        super.insertNewline(sender)
        let at = selectedRange().location
        replace(NSRange(location: at, length: 0), with: Self.bullet)
        setSelectedRange(NSRange(location: at + 2, length: 0))
    }

    /// Bullets on for the lines in the selection, or off if they all have one already.
    func toggleBullets() {
        let ns = string as NSString, sel = selectedRange()
        var lines: [NSRange] = []
        ns.enumerateSubstrings(in: ns.lineRange(for: sel), options: [.byLines, .substringNotRequired]) { _, r, _, _ in lines.append(r) }
        if lines.isEmpty { lines = [NSRange(location: ns.lineRange(for: sel).location, length: 0)] }   // an empty line at the end
        let allOn = lines.allSatisfy { ns.substring(with: $0).hasPrefix(Self.bullet) }
        var changed = 0
        undoManager?.beginUndoGrouping()
        for r in lines.reversed() {                       // back to front, so the earlier ranges stay valid
            if allOn { replace(NSRange(location: r.location, length: 2), with: ""); changed += 1 }
            else if !ns.substring(with: r).hasPrefix(Self.bullet) { replace(NSRange(location: r.location, length: 0), with: Self.bullet); changed += 1 }
        }
        undoManager?.endUndoGrouping()
        let end = NSMaxRange(sel) + (allOn ? -2 : 2) * changed
        setSelectedRange(NSRange(location: max(0, min(end, (string as NSString).length)), length: 0))
    }

    override func pasteAsPlainText(_ sender: Any?) { paste(sender) }
    override func pasteAsRichText(_ sender: Any?) { paste(sender) }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder(); if ok { onFocusChange?(true) }; return ok
    }
    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder(); if ok { onFocusChange?(false) }; return ok
    }
}

/// Lets the B / I buttons reach the text being edited (the notepad, or the last task line
/// you clicked into) and light up for its selection.
@MainActor
final class FormatController: ObservableObject {
    private(set) weak var view: FormattingTextView?
    @Published var bold = false
    @Published var italic = false
    @Published var hasTarget = false

    func attach(_ v: FormattingTextView) {
        if view !== v { view = v }
        refresh()
    }

    func toggle(_ key: NSAttributedString.Key) {
        guard let v = view, v.window != nil else { refresh(); return }
        v.toggleFromButton(key)
        refresh()
    }

    func refresh() {
        let v = view.flatMap { $0.window == nil ? nil : $0 }
        let b = v?.isOn(.noteBold) ?? false, i = v?.isOn(.noteItalic) ?? false, t = v != nil
        if bold != b { bold = b }
        if italic != i { italic = i }
        if hasTarget != t { hasTarget = t }
    }
}

/// SwiftUI wrapper: grows with the text from `minLines` up to `maxHeight` (the room left in the note), then scrolls.
struct NotepadText: NSViewRepresentable {
    @Binding var doc: NotepadDoc
    var faces: NoteFaces
    var ink: NSColor
    var placeholderInk: NSColor
    var controller: FormatController
    var minLines: CGFloat = 4
    var maxHeight: CGFloat = 400
    var onFocusChange: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        let v = NotepadTextView(frame: .zero)
        v.isRichText = true
        v.importsGraphics = false
        v.allowsUndo = true
        v.drawsBackground = false
        v.isVerticallyResizable = true
        v.isHorizontallyResizable = false
        v.autoresizingMask = [.width]
        v.minSize = .zero
        v.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        v.textContainerInset = .zero
        v.textContainer?.lineFragmentPadding = 0
        v.textContainer?.widthTracksTextView = true
        v.focusRingType = .none
        v.isAutomaticQuoteSubstitutionEnabled = false
        v.isAutomaticDashSubstitutionEnabled = false
        v.isAutomaticTextReplacementEnabled = false
        v.delegate = context.coordinator
        v.faces = faces
        v.ink = ink
        v.formatController = controller
        v.load(doc)
        scroll.documentView = v
        DispatchQueue.main.async { controller.attach(v) }    // the notepad is the B / I target on its page
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let v = scroll.documentView as? NotepadTextView else { return }
        v.onFocusChange = onFocusChange
        if v.faces != faces || v.ink != ink { v.faces = faces; v.ink = ink; v.restyle(); v.indentBullets() }
        if v.doc != doc { v.load(doc) }                      // changed from outside, not by typing here
        if abs(context.coordinator.lastMaxHeight - maxHeight) > 0.5 { context.coordinator.lastMaxHeight = maxHeight; v.invalidateIntrinsicContentSize() }
        v.insertionPointColor = ink
        v.selectedTextAttributes = [.backgroundColor: ink.withAlphaComponent(0.14)]
        v.placeholder = NSAttributedString(string: "Write anything…", attributes: [.font: faces.italic, .foregroundColor: placeholderInk])
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView scroll: NSScrollView, context: Context) -> CGSize? {
        let width = proposal.width ?? 240
        guard let v = scroll.documentView as? NotepadTextView, let lm = v.layoutManager, let tc = v.textContainer else { return nil }
        tc.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        lm.ensureLayout(for: tc)
        let line = lm.defaultLineHeight(for: faces.regular)
        let used = ceil(lm.usedRect(for: tc).height)
        return CGSize(width: width, height: min(max(used, line * minLines), max(line * minLines, maxHeight)))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotepadText
        var lastMaxHeight: CGFloat = 0
        init(_ p: NotepadText) { parent = p }
        func textDidChange(_ n: Notification) {
            guard let v = n.object as? NotepadTextView else { return }
            parent.doc = v.doc
            v.invalidateIntrinsicContentSize()
        }
        func textViewDidChangeSelection(_ n: Notification) {
            MainActor.assumeIsolated { parent.controller.refresh() }
        }
    }
}
