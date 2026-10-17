// The note itself: three states (hidden / default / expanded) in three looks.

import AppKit
import SwiftUI

enum NoteState { case hidden, compact, expanded }
enum FocusTarget: Equatable { case task(UUID), add }

enum NoteStyle: String, CaseIterable, Identifiable {
    case brass, wax, torn
    var id: String { rawValue }
    var name: String { switch self { case .brass: "Brass clip"; case .wax: "Wax seal"; case .torn: "Torn paper" } }
}

struct Theme {
    let ink, done, strike: NSColor
    let tick: Color
    let font, italic: NSFont
    let roundBox: Bool
    let pad: EdgeInsets
    let width: CGFloat
    let overhang: CGFloat          // how far the fastener sticks out above the paper

    var inkColor: Color { Color(nsColor: ink) }
    var doneColor: Color { Color(nsColor: done) }

    static func of(_ s: NoteStyle) -> Theme {
        switch s {
        case .brass:
            Theme(ink: NSColor(hex: 0x2a251e), done: NSColor(hex: 0x9b9183), strike: NSColor(hex: 0x3a2f22), tick: Color(hex: 0x2a251e),
                  font: font("CormorantGaramond-SemiBold", 22), italic: font("CormorantGaramond-MediumItalic", 18), roundBox: false,
                  pad: EdgeInsets(top: 46, leading: 36, bottom: 22, trailing: 30), width: 300, overhang: 30)
        case .wax:
            Theme(ink: NSColor(hex: 0x323a2c), done: NSColor(hex: 0x9aa290), strike: NSColor(hex: 0x5b6a4b), tick: Color(hex: 0x5b6a4b),
                  font: font("EBGaramond-Regular", 21), italic: font("EBGaramond-Italic", 17), roundBox: true,
                  pad: EdgeInsets(top: 56, leading: 38, bottom: 28, trailing: 30), width: 300, overhang: 40)
        case .torn:
            Theme(ink: NSColor(hex: 0x2d2d2b), done: NSColor(hex: 0x9a968e), strike: NSColor(hex: 0x55534f), tick: Color(hex: 0x3c3b38),
                  font: font("CourierPrime-Regular", 15.5), italic: font("CourierPrime-Italic", 14), roundBox: false,
                  pad: EdgeInsets(top: 44, leading: 40, bottom: 42, trailing: 52), width: 332, overhang: 20)
        }
    }
    private static func font(_ name: String, _ size: CGFloat) -> NSFont { NSFont(name: name, size: size) ?? .systemFont(ofSize: size * 0.8) }
}

extension NSColor {
    convenience init(hex: UInt32) { self.init(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1) }
}

enum Motion {
    static let ui = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.2)        // strong ease-out
    static let drawer = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.3)    // opening
    static let morph = Animation.timingCurve(0.77, 0, 0.175, 1, duration: 0.24)   // on-screen movement
    static let tick = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.22)
}

struct NoteView: View {
    @ObservedObject var store: Store
    var forceHover = false                 // used only by the debug snapshot build
    @State private var hovering = false
    @State private var fastenerHover = false
    @State private var editing = false
    @State private var pickerOpen = false
    @State private var draft = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: Theme { Theme.of(store.style) }
    private var controlsVisible: Bool { hovering || forceHover || editing || pickerOpen }

    var body: some View {
        ZStack(alignment: .top) {
            if store.state == .hidden {
                token
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            } else {
                sheet
                    .transition(reduceMotion ? .opacity : .modifier(active: Reveal(progress: 0), identity: Reveal(progress: 1)))
            }
        }
        .id(store.style)
        .onChange(of: store.state) { fastenerHover = false }
        .transition(.modifier(active: BlurFade(on: true), identity: BlurFade(on: false)))
        .padding(.top, 52).padding(.horizontal, 24).padding(.bottom, 40)
    }

    // MARK: Hidden: just the fastener, about 1.5× the size of the old bubble

    private var token: some View {
        Group {
            switch store.style {
            case .brass:
                ZStack(alignment: .top) {
                    Deckle(amp: 1.6, seed: 3).fill(Ink.paper)
                        .overlay(Image(nsImage: Grain.image).resizable(resizingMode: .tile).clipShape(Deckle(amp: 1.6, seed: 3)))
                        .frame(width: 88, height: 40).padding(.top, 24)
                        .shadow(color: Color(hex: 0x46340f).opacity(0.2), radius: 5, y: 5)
                    BrassClip().frame(width: 84)
                }
            case .wax:
                WaxSeal().frame(width: 84, height: 84)
                    .shadow(color: Color(hex: 0x28321e).opacity(0.35), radius: 3, y: 4)
            case .torn:
                ZStack(alignment: .topLeading) {
                    TornPaper().frame(width: 84, height: 62).padding(.top, 16)
                    Paperclip().frame(width: 18, height: 60).offset(x: 52, y: 0)
                    StarSticker(size: 32, rotation: -12).offset(x: -12, y: 48)
                }
                .frame(width: 84, height: 84, alignment: .topLeading)
            }
        }
        .scaleEffect(fastenerHover ? 1.04 : 1)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(Motion.ui) { fastenerHover = h } }
        .pointerStyle(.link)
        .onTapGesture { withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Motion.drawer) { store.state = .compact } }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { store.tokenRect = $0 }
        .help("Show note")
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Show note")
    }

    // MARK: Default + expanded

    private var sheet: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                card
                    .id(store.page)
                    .transition(.asymmetric(insertion: .identity,
                                            removal: .modifier(active: TearOff(on: true), identity: TearOff(on: false))))
                fastener
            }
            .overlay(alignment: .topLeading) { styleButton }
            .overlay(alignment: .topTrailing) { restartButton }
            .overlay(alignment: .topLeading) { if pickerOpen { picker } }
            undoBar
        }
        .frame(width: theme.width)
        .onHover { h in withAnimation(Motion.ui) { hovering = h } }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { store.sheetRect = $0 }
        .contextMenu {
            Button("Copy All Tasks") { store.copyAll() }.disabled(store.tasks.isEmpty)
            Button("Paste as Tasks") { withAnimation(Motion.drawer) { store.pasteAsTasks() } }
            Divider()
            Button("Start Fresh") { withAnimation(Motion.ui) { store.restart() } }.disabled(store.tasks.isEmpty)
            Button("Hide Note") { hide() }
        }
    }

    /// Clicking the clip / seal / paperclip folds the note back to its hidden state.
    private var fastener: some View {
        Group {
            switch store.style {
            case .brass: BrassClip().frame(width: 112).alignmentGuide(.top) { $0[.top] + 30 }
            case .wax: WaxSeal().frame(width: 76, height: 76).shadow(color: Color(hex: 0x28321e).opacity(0.35), radius: 3, y: 4)
                    .alignmentGuide(.top) { $0[.top] + 40 }
            case .torn: Paperclip().frame(width: 26, height: 87).alignmentGuide(.top) { $0[.top] + 20 }
            }
        }
        .offset(y: fastenerHover ? -3 : 0)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(Motion.ui) { fastenerHover = h } }
        .pointerStyle(.link)
        .onTapGesture { hide() }
        .help("Hide note")
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Hide note")
        // Push the torn paperclip right *after* the tap area is set, so only the clip folds the note,
        // not a strip across the top of the card where the first tasks are typed.
        .frame(maxWidth: store.style == .torn ? .infinity : nil, alignment: .trailing)
        .padding(.trailing, store.style == .torn ? 20 : 0)
    }

    private func hide() {
        pickerOpen = false
        NSApp.keyWindow?.makeFirstResponder(nil)
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Motion.ui) { store.state = .hidden }
    }

    private var shownTasks: ArraySlice<TodoItem> { store.state == .expanded ? store.tasks[...] : store.tasks.prefix(2) }
    private var hiddenCount: Int { max(0, store.tasks.count - 2) }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shownTasks.enumerated()), id: \.element.id) { i, item in
                row(item, index: i)
                    .transition(i < 2 ? .identity : .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: -6)).animation(Motion.ui.delay(0.06 + Double(i - 2) * 0.04)),
                        removal: .opacity.animation(.easeOut(duration: 0.12))))
            }
            addRow                                   // always the line right after the visible tasks
            if hiddenCount > 0 { moreButton }
        }
        .padding(theme.pad)
        .frame(width: theme.width, alignment: .leading)
        .background(paper.gesture(WindowDragGesture()))
        .overlay { decorations }
    }

    @ViewBuilder private var paper: some View {
        switch store.style {
        case .brass: BrassPaper()
        case .wax: WaxPaper()
        case .torn: TornPaper()
        }
    }

    @ViewBuilder private var decorations: some View {
        if store.style == .torn {
            ZStack {
                StarSticker(size: 44, rotation: -10).position(x: 0, y: -4)
                StarSticker(size: 34, rotation: 14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).offset(x: 16, y: 12)
                StarSticker(size: 26, rotation: -8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).offset(x: -22, y: 24)
            }
            .allowsHitTesting(false)
        }
    }

    // "5 more" opens everything; "Show less" goes back to the first two.
    private var moreButton: some View {
        Button {
            let opening = store.state != .expanded
            if !opening { NSApp.keyWindow?.makeFirstResponder(nil) }
            withAnimation(opening ? Motion.drawer : Motion.ui) { store.state = opening ? .expanded : .compact }
        } label: {
            HStack(spacing: 6) {
                Text(store.state == .expanded ? "Show less" : "\(hiddenCount) more")
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(store.state == .expanded ? 180 : 0))
            }
            .font(Font(theme.italic))
            .padding(.vertical, 4).padding(.trailing, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(MoreButtonStyle(theme: theme))
        .padding(.leading, 27).padding(.top, 4)
    }

    // MARK: Rows

    private func row(_ item: TodoItem, index: Int) -> some View {
        let text = Binding(get: { store.tasks.first(where: { $0.id == item.id })?.text ?? "" },
                           set: { new in if let i = store.tasks.firstIndex(where: { $0.id == item.id }) { store.tasks[i].text = new } })
        return HStack(alignment: .top, spacing: 12) {
            Button { if let i = store.tasks.firstIndex(where: { $0.id == item.id }) { store.tasks[i].done.toggle() } } label: {
                CheckBox(done: item.done, theme: theme)
            }
            .buttonStyle(PressScale())
            .padding(.top, theme.font.firstLineXMid - 7.5)
            .accessibilityLabel(item.done ? "Mark as not done" : "Mark as done")
            TaskText(text: text, done: item.done, font: theme.font, ink: theme.ink, doneInk: theme.done, strike: theme.strike,
                     focusRequested: store.focusTarget == .task(item.id),
                     onReturn: { returnPressed(after: item.id) },
                     onPasteLines: { lines in pasted(lines, into: item.id) },
                     onDeleteWhenEmpty: { remove(item.id) },
                     onFocusChange: { editing = $0 },
                     onFocused: { store.focusTarget = nil })
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("Copy Task") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.text, forType: .string) }
            Button("Copy All Tasks") { store.copyAll() }
            Button("Paste as Tasks") { withAnimation(Motion.drawer) { store.pasteAsTasks() } }
            Divider()
            Button("Delete Task") { remove(item.id) }
        }
    }

    private var addRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if theme.roundBox { Circle().strokeBorder(theme.inkColor.opacity(0.3), style: StrokeStyle(lineWidth: 1.2, dash: [2.5, 2])) }
                else { RoundedRectangle(cornerRadius: 2).strokeBorder(theme.inkColor.opacity(0.3), style: StrokeStyle(lineWidth: 1.2, dash: [2.5, 2])) }
            }
            .frame(width: 15, height: 15)
            .padding(.top, theme.font.firstLineXMid - 7.5)
            TaskText(text: $draft, done: false, font: theme.font, ink: theme.ink, doneInk: theme.done, strike: theme.strike,
                     placeholder: store.tasks.isEmpty ? "Click to add tasks" : "Add a task", placeholderFont: theme.italic.withSize(theme.font.pointSize),
                     focusRequested: store.focusTarget == .add,
                     onReturn: commitDraft,
                     onPasteLines: { lines in commitDraft(); withAnimation(Motion.drawer) { store.insert(lines, at: store.tasks.count) } },
                     onFocusChange: { editing = $0 },
                     onFocused: { store.focusTarget = nil })
        }
        .padding(.vertical, 3)
    }

    private func commitDraft() {
        let v = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        draft = ""
        withAnimation(Motion.ui) { store.insert([v], at: store.tasks.count) }
        store.focusTarget = .add
    }

    /// Return starts a blank task right after this one, if that spot is on screen.
    private func returnPressed(after id: UUID) {
        guard let i = store.tasks.firstIndex(where: { $0.id == id }) else { return }
        guard store.state == .expanded || i + 1 < 2 else { NSApp.keyWindow?.makeFirstResponder(nil); return }
        let blank = TodoItem(text: "")
        withAnimation(Motion.ui) { store.tasks.insert(blank, at: i + 1) }
        store.focusTarget = .task(blank.id)
    }

    private func pasted(_ lines: [String], into id: UUID) {
        guard var i = store.tasks.firstIndex(where: { $0.id == id }) else { return }
        var rest = lines[...]
        if store.tasks[i].text.isEmpty, let first = rest.first { store.tasks[i].text = first; rest = rest.dropFirst() }
        i += 1
        withAnimation(Motion.drawer) { store.insert(Array(rest), at: i) }
    }

    private func remove(_ id: UUID) {
        guard let i = store.tasks.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(Motion.ui) { _ = store.tasks.remove(at: i) }
        if i > 0 { store.focusTarget = .task(store.tasks[i - 1].id) }
    }

    // MARK: Controls

    private var styleButton: some View {
        OutlineButton(theme: theme, tip: pickerOpen ? "Close" : "Change style", tipEdge: .leading) {
            withAnimation(Motion.ui) { pickerOpen.toggle() }
        } label: {
            MorphMenuIcon(open: pickerOpen, color: theme.inkColor)
        }
        .padding(.top, theme.overhang + (store.style == .torn ? 14 : 12)).padding(.leading, store.style == .torn ? 16 : 12)
        .opacity(controlsVisible ? 1 : 0)
        .accessibilityLabel(pickerOpen ? "Close style menu" : "Change style")
    }

    private var restartButton: some View {
        OutlineButton(theme: theme, tip: "Start fresh", tipEdge: .trailing) {
            withAnimation(Motion.ui) { store.restart() }
        } label: {
            Image(systemName: "arrow.counterclockwise").font(.system(size: 11, weight: .medium))
        }
        .padding(.top, theme.overhang + 12).padding(.trailing, store.style == .torn ? 58 : 12)
        .opacity(controlsVisible ? 1 : 0)
        .disabled(store.tasks.isEmpty)
        .accessibilityLabel("Start a fresh page")
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(NoteStyle.allCases) { s in
                Button {
                    withAnimation(Motion.ui) { pickerOpen = false }
                    withAnimation(Motion.morph) { store.style = s }
                } label: {
                    HStack(spacing: 10) {
                        Group {
                            switch s {
                            case .brass: BrassClip().frame(width: 26)
                            case .wax: WaxSeal().frame(width: 18, height: 18)
                            case .torn: StarSticker(size: 17, rotation: -10)
                            }
                        }
                        .frame(width: 28)
                        Text(s.name).font(Font(NSFont(name: "EBGaramond-Regular", size: 15) ?? .systemFont(ofSize: 13)))
                        Spacer(minLength: 8)
                        if s == store.style { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)) }
                    }
                    .foregroundStyle(Color(hex: 0x2a251e))
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PickerRowStyle())
            }
        }
        .padding(5)
        .frame(width: 176)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(hex: 0xfffdf7).opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.black.opacity(0.07)))
        .shadow(color: Color(hex: 0x46340f).opacity(0.16), radius: 12, y: 8)
        .padding(.top, theme.overhang + 46).padding(.leading, 10)
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
    }

    private var undoBar: some View {
        HStack(spacing: 12) {
            Text("Page cleared").foregroundStyle(Color(hex: 0xf6f1e6))
            Button("Undo") { withAnimation(Motion.ui) { store.undo() } }
                .buttonStyle(PressScale())
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color(hex: 0xefe6cf)))
                .foregroundStyle(Color(hex: 0x2c2822))
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 7)
        .background(Capsule().fill(Color(hex: 0x2c2822)))
        .padding(.top, 18)
        .opacity(store.undoable == nil ? 0 : 1)
        .offset(y: store.undoable == nil ? 6 : 0)
        .allowsHitTesting(store.undoable != nil)
    }
}

// MARK: - Pieces

/// Three lines that fold into an ×. Top and bottom rotate onto the centre; the middle one shrinks away.
struct MorphMenuIcon: View {
    var open: Bool
    var color: Color
    var body: some View {
        ZStack {
            Capsule().frame(width: 12, height: 1.5).rotationEffect(.degrees(open ? 45 : 0)).offset(y: open ? 0 : -4)
            Capsule().frame(width: 12, height: 1.5).scaleEffect(x: open ? 0.2 : 1).opacity(open ? 0 : 1)
            Capsule().frame(width: 12, height: 1.5).rotationEffect(.degrees(open ? -45 : 0)).offset(y: open ? 0 : 4)
        }
        .foregroundStyle(color)
        .frame(width: 14, height: 14)
        .animation(Motion.morph, value: open)
    }
}

/// Quiet round button: transparent fill, thin ink stroke, icon at half strength. A label appears after a short hover.
struct OutlineButton<Label: View>: View {
    var theme: Theme
    var tip: String
    var tipEdge: HorizontalEdge
    var action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var hover = false
    @State private var showTip = false

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(theme.inkColor.opacity(hover ? 0.8 : 0.5))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color(hex: 0xfffdf7).opacity(hover ? 0.65 : 0.3)))
                .overlay(Circle().strokeBorder(theme.inkColor.opacity(hover ? 0.42 : 0.26), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PressScale())
        .overlay(alignment: tipEdge == .leading ? .bottomLeading : .bottomTrailing) {
            Text(tip)
                .font(Font(NSFont(name: "EBGaramond-Italic", size: 13) ?? .systemFont(ofSize: 11)))
                .foregroundStyle(theme.inkColor.opacity(0.7))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0xfffdf7).opacity(0.85)))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.black.opacity(0.06)))
                .fixedSize()
                .offset(x: tipEdge == .leading ? -3 : 3, y: showTip ? -32 : -30)
                .opacity(showTip ? 1 : 0)
                .allowsHitTesting(false)
        }
        .onHover { h in
            withAnimation(.easeOut(duration: 0.16)) { hover = h }
            if h { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { if hover { withAnimation(Motion.ui) { showTip = true } } } }
            else { withAnimation(.easeOut(duration: 0.1)) { showTip = false } }
        }
    }
}

struct CheckBox: View {
    var done: Bool
    var theme: Theme
    var body: some View {
        ZStack {
            if theme.roundBox { Circle().strokeBorder(theme.inkColor.opacity(0.75), lineWidth: 1.2) }
            else { RoundedRectangle(cornerRadius: 2).strokeBorder(theme.inkColor.opacity(0.75), lineWidth: 1.2) }
            // Tick sits in the middle of the 15pt box
            Path { p in p.move(to: CGPoint(x: 3.9, y: 8.2)); p.addLine(to: CGPoint(x: 6.8, y: 11.1)); p.addLine(to: CGPoint(x: 12.1, y: 4.9)) }
                .trim(from: 0, to: done ? 1 : 0)
                .stroke(theme.tick, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .animation(Motion.tick, value: done)
        }
        .frame(width: 15, height: 15)
        .contentShape(Rectangle())
    }
}

/// Brass-clip look: deckled cotton card on a pinked mat, ticking stripe peeking out behind.
struct BrassPaper: View {
    var body: some View {
        ZStack {
            StripeCard().frame(width: 150, height: 120).rotationEffect(.degrees(-7))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).offset(x: -26, y: 30)
            Pinked().fill(Ink.mat).overlay(Image(nsImage: Grain.image).resizable(resizingMode: .tile).clipShape(Pinked()))
                .padding(-9).rotationEffect(.degrees(-1.6))
            Deckle(amp: 2.2, seed: 7).fill(Ink.paper)
                .overlay(Image(nsImage: Grain.mottle).resizable(resizingMode: .tile).blendMode(.softLight).opacity(0.1).clipShape(Deckle(amp: 2.2, seed: 7)))
                .overlay(Image(nsImage: Grain.image).resizable(resizingMode: .tile).clipShape(Deckle(amp: 2.2, seed: 7)))
                .overlay(Deckle(amp: 2.2, seed: 7).stroke(Ink.rim, lineWidth: 2.5))
        }
        .compositingGroup()
        .shadow(color: Color(hex: 0x46340f).opacity(0.18), radius: 0.8, y: 1)
        .shadow(color: Color(hex: 0x46340f).opacity(0.15), radius: 9, y: 12)
    }
}

struct StripeCard: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Ink.stripeBase))
            var x: CGFloat = 9
            while x < size.width { ctx.fill(Path(CGRect(x: x, y: 0, width: 8, height: size.height)), with: .color(Ink.stripe)); x += 17 }
        }
        .shadow(color: Color(hex: 0x323c50).opacity(0.15), radius: 1, y: 1)
    }
}

/// Paper rolls down from the fastener: a mask that grows from the top, content itself never squashes.
struct Reveal: ViewModifier, Animatable {
    var progress: CGFloat
    var animatableData: CGFloat { get { progress } set { progress = newValue } }
    func body(content: Content) -> some View {
        content
            .mask(alignment: .top) { Rectangle().padding(-80).scaleEffect(x: 1, y: max(progress, 0.001), anchor: .top) }
            .opacity(min(1, progress * 3))
    }
}

/// Style switch: brief blur so the two looks read as one transformation, not two objects swapping.
struct BlurFade: ViewModifier {
    var on: Bool
    func body(content: Content) -> some View { content.blur(radius: on ? 2 : 0).opacity(on ? 0 : 1) }
}

/// The old sheet lifts off toward the top-left while the fresh one stays put.
struct TearOff: ViewModifier {
    var on: Bool
    func body(content: Content) -> some View {
        content.rotationEffect(.degrees(on ? -5 : 0)).offset(x: on ? -18 : 0, y: on ? -40 : 0).opacity(on ? 0 : 1)
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.94 : 1).animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct MoreButtonStyle: ButtonStyle {
    var theme: Theme
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(hover ? theme.inkColor : theme.doneColor)
            .scaleEffect(configuration.isPressed ? 0.97 : 1, anchor: .leading)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}

struct PickerRowStyle: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x2a251e).opacity(configuration.isPressed ? 0.1 : hover ? 0.06 : 0)))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
    }
}
