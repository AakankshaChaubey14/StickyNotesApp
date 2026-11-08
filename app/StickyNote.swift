// Sticky Note: scrapbook edition.
// Three states: hidden (just the clip/seal/scrap), default (first 2 tasks), expanded (everything).
// Three looks, switched from the top-left button: brass clip, wax seal, torn paper & stars.
// Plain-text copy and paste work everywhere; pasting several lines adds several tasks.

import AppKit
import SwiftUI
import CoreText
import CoreImage
import Combine
import ServiceManagement

// MARK: - Model

struct TodoItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var done = false
    var runs: [NotepadDoc.Run]? = nil      // bold / italic words; optional so older files (and versions) still read
    var content: NotepadDoc { NotepadDoc(text: text, runs: runs ?? []) }
}

@MainActor
final class Store: ObservableObject {
    @Published var tasks: [TodoItem] = [] { didSet { if undoable != nil && !tasks.isEmpty { undoable = nil }; save() } }
    @Published var state: NoteState = .hidden
    @Published var style: NoteStyle = NoteStyle(rawValue: UserDefaults.standard.string(forKey: "style") ?? "") ?? .brass {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: "style") }
    }
    @Published var tab: NoteTab = NoteTab(rawValue: UserDefaults.standard.string(forKey: "tab") ?? "") ?? .todo {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: "tab") }
    }
    @Published var notepad = NotepadDoc() {
        didSet { if undoableNotes != nil && !notepad.text.isEmpty { undoableNotes = nil }; saveNotepad() }   // typing again keeps the clear
    }
    @Published var focusTarget: FocusTarget? = nil
    // The note's visible area in window coordinates, so clicks beside it reach the desktop.
    var tokenRect: CGRect = .zero
    var sheetRect: CGRect = .zero { didSet { if sheetRect != oldValue { layoutChanged?() } } }
    var layoutChanged: (() -> Void)?
    var hitRect: CGRect { state == .hidden ? tokenRect.insetBy(dx: -6, dy: -6) : sheetRect.insetBy(dx: -30, dy: -44) }
    @Published var page = UUID()            // changes on restart so the old sheet can animate away
    @Published var undoable: [TodoItem]? = nil
    @Published var undoableNotes: NotepadDoc? = nil

    /// Nothing saved yet, by this app or the old StickyNote: a brand-new user, who gets the intro.
    private(set) var isFirstRun = false

    private let url: URL
    private var notepadURL: URL { url.deletingLastPathComponent().appendingPathComponent("scrapbook-notepad.json") }
    private var undoTimer: Timer?

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StickyNote", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let custom = ProcessInfo.processInfo.environment["STICKYNOTE_DATA"] {
            let chosen = URL(fileURLWithPath: custom).resolvingSymlinksInPath()
            let old = dir.appendingPathComponent("todos.json").resolvingSymlinksInPath()
            url = chosen.path == old.path ? dir.appendingPathComponent("scrapbook-todos.json") : chosen
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } else {
            url = dir.appendingPathComponent("scrapbook-todos.json")
        }
        let fm = FileManager.default
        isFirstRun = ![url, notepadURL, dir.appendingPathComponent("todos.json")].contains { fm.fileExists(atPath: $0.path) }
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([TodoItem].self, from: data) {
            tasks = saved
        } else {
            tasks = Store.importFromOldApp(dir)   // read-only: the old app's file is never written
        }
        if let data = try? Data(contentsOf: notepadURL), let saved = try? JSONDecoder().decode(NotepadDoc.self, from: data) {
            notepad = saved
        }
        // Open tasks first, ticked ones after: older versions left ticked tasks where they were.
        let sorted = tasks.filter { !$0.done } + tasks.filter(\.done)
        if sorted != tasks { tasks = sorted; save() }   // observers don't run in init, so save by hand
        if isFirstRun { tasks = Intro.tasks; notepad = Intro.note; save(); saveNotepad() }
    }

    /// Open tasks come first, ticked ones after; this is where the ticked ones start.
    var firstDoneIndex: Int { tasks.firstIndex(where: \.done) ?? tasks.count }

    /// Ticking a task sinks it to the bottom; unticking brings it back up to the end of the open ones.
    func toggleDone(_ id: UUID) {
        var list = tasks
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        var t = list.remove(at: i)
        t.done.toggle()
        list.insert(t, at: t.done ? list.count : (list.firstIndex(where: \.done) ?? list.count))
        tasks = list
    }

    /// The previous StickyNote.app stored `[{id, text, done, ...}]` in todos.json.
    private static func importFromOldApp(_ dir: URL) -> [TodoItem] {
        struct Old: Decodable { var text: String; var done: Bool? }
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("todos.json")),
              let old = try? JSONDecoder().decode([Old].self, from: data) else { return [] }
        return old.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
                  .map { TodoItem(text: $0.text, done: $0.done ?? false) }
    }

    private func saveNotepad() {
        do { try JSONEncoder().encode(notepad).write(to: notepadURL, options: .atomic) }
        catch { NSLog("Sticky Note: could not save notes to %@: %@", notepadURL.path, error.localizedDescription) }
    }

    private func save() {
        do { try JSONEncoder().encode(tasks).write(to: url, options: .atomic) }
        catch { NSLog("Sticky Note: could not save tasks to %@: %@", url.path, error.localizedDescription) }
    }

    // Plain text from the clipboard, one task per line. Bullets / numbers / [ ] prefixes are dropped.
    static func lines(from text: String) -> [String] {
        text.components(separatedBy: .newlines).map { line in
            line.replacingOccurrences(of: #"^\s*(?:(?:[-*•]|\d+[.)])\s+)?(?:\[[ xX]\]\s+)?"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
    }

    @discardableResult
    func insert(_ texts: [String], at index: Int) -> [TodoItem] {
        let items = texts.map { TodoItem(text: $0) }
        tasks.insert(contentsOf: items, at: min(index, firstDoneIndex))   // new tasks stay above the ticked ones
        return items
    }

    /// A task with its formatting, kept above the ticked ones like any new task.
    func insert(_ item: TodoItem, at index: Int) {
        tasks.insert(item, at: min(index, firstDoneIndex))
    }

    /// Drag-reorder: `index` is the new position among the other tasks. Open tasks stay above ticked ones.
    func move(_ id: UUID, to index: Int) {
        var list = tasks
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        let t = list.remove(at: i)
        let open = list.filter { !$0.done }.count
        list.insert(t, at: t.done ? max(index, open) : min(index, open))
        if list != tasks { tasks = list }
    }

    func copyAll() {
        let text = tasks.map { $0.text }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func pasteAsTasks() {
        guard let s = NSPasteboard.general.string(forType: .string) else { return }
        insert(Store.lines(from: s), at: tasks.count)
    }

    func restart() {
        guard !tasks.isEmpty else { return }
        undoableNotes = nil                      // only the latest clear can be undone
        undoable = tasks
        if state == .expanded { state = .compact }
        page = UUID()
        tasks = []
        startUndoTimer()
    }

    /// Clears the notes page, with the same 5-second Undo as Start fresh.
    func clearNotes() {
        guard !notepad.text.isEmpty else { return }
        undoable = nil
        undoableNotes = notepad
        page = UUID()                            // the old page tears away, as with tasks
        notepad = NotepadDoc()
        startUndoTimer()
    }

    private func startUndoTimer() {
        undoTimer?.invalidate()
        undoTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            Task { @MainActor in withAnimation(.easeOut(duration: 0.18)) { self?.undoable = nil; self?.undoableNotes = nil } }
        }
    }

    func undo() {
        if let saved = undoableNotes { undoableNotes = nil; notepad = saved; return }
        guard let saved = undoable else { return }
        undoable = nil
        tasks = saved
    }
}

// MARK: - First run

/// What a brand-new user finds: tasks that teach by doing, and a welcome page in Notes.
/// It's ordinary content, so it can be ticked, deleted or cleared like anything else.
enum Intro {
    enum Style { case bold, italic }

    static let tasks: [TodoItem] = [
        doc("Tick this box to finish a task"),
        doc("Hover a task and click × to delete it"),
        doc("Select a word and press ", ("B", Style.bold), " or ", ("I", Style.italic)),
        doc("Click the clip at the top to fold me away"),
        doc("☰ changes the look: try all three"),
        doc("↺ clears the page when you're done"),
    ].map { TodoItem(text: $0.text, runs: $0.runs.isEmpty ? nil : $0.runs) }

    static let note = doc(("Welcome to your notes page", Style.bold),
                          "\nWrite anything here: ideas, lists, a letter to future you.",
                          "\nSelect words and press ", ("B", Style.bold), " for bold or ", ("I", Style.italic), " for italic (or ⌘B and ⌘I).",
                          "\nTap ", ("To-do", Style.italic), " at the top to get back to your list.",
                          "\nEverything stays on your Mac. Delete this whenever you're ready.")

    /// Joins plain strings and (text, style) pairs into text plus bold / italic runs.
    private static func doc(_ pieces: Any...) -> NotepadDoc {
        var d = NotepadDoc()
        for piece in pieces {
            let styled = piece as? (String, Style)
            let text = styled?.0 ?? (piece as? String ?? "")
            let at = (d.text as NSString).length
            d.text += text
            if let style = styled?.1 {
                d.runs.append(.init(location: at, length: (text as NSString).length, bold: style == .bold, italic: style == .italic))
            }
        }
        return d
    }
}

// MARK: - Look

enum Ink {
    static let text = Color(red: 0x2a/255, green: 0x25/255, blue: 0x1e/255)
    static let done = Color(red: 0x9b/255, green: 0x91/255, blue: 0x83/255)
    static let paper = Color(red: 0xf0/255, green: 0xea/255, blue: 0xdd/255)
    static let rim = Color(red: 0xf7/255, green: 0xf3/255, blue: 0xea/255)
    static let mat = Color(red: 0xe3/255, green: 0xdc/255, blue: 0xcb/255)
    static let stripe = Color(red: 0xb9/255, green: 0xc8/255, blue: 0xde/255)
    static let stripeBase = Color(red: 0xf5/255, green: 0xf4/255, blue: 0xef/255)
}

/// Procedural paper grain, rendered once at 2× so it stays crisp on Retina.
enum Grain {
    static let image: NSImage = {
        let ctx = CIContext()
        let size = CGRect(x: 0, y: 0, width: 512, height: 512)
        let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!.cropped(to: size)
        let mono = noise.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.32, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.27, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0.2, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.11),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)])
        let cg = ctx.createCGImage(mono, from: size)!
        return NSImage(cgImage: cg, size: NSSize(width: 256, height: 256))
    }()
    static let mottle: NSImage = {
        let ctx = CIContext()
        let size = CGRect(x: 0, y: 0, width: 512, height: 512)
        let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 6]).cropped(to: size)
            .applyingFilter("CIColorControls", parameters: ["inputSaturation": 0, "inputContrast": 3.2])
        let cg = ctx.createCGImage(noise, from: size)!
        return NSImage(cgImage: cg, size: NSSize(width: 256, height: 256))
    }()
}

/// Deckled edge: a rectangle whose sides wander by a couple of points, seeded so it never shimmers.
struct Deckle: Shape {
    var amp: CGFloat = 2.2
    var seed: UInt64 = 7
    func path(in r: CGRect) -> Path {
        var rng = SplitMix(seed)
        var p = Path()
        let step: CGFloat = 5
        func j() -> CGFloat { (CGFloat(rng.next() % 1000) / 1000 - 0.5) * 2 * amp }
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        var x = r.minX; while x < r.maxX { x = min(x + step, r.maxX); p.addLine(to: CGPoint(x: x, y: r.minY + j())) }
        var y = r.minY; while y < r.maxY { y = min(y + step, r.maxY); p.addLine(to: CGPoint(x: r.maxX + j(), y: y)) }
        x = r.maxX; while x > r.minX { x = max(x - step, r.minX); p.addLine(to: CGPoint(x: x, y: r.maxY + j())) }
        y = r.maxY; while y > r.minY { y = max(y - step, r.minY); p.addLine(to: CGPoint(x: r.minX + j(), y: y)) }
        p.closeSubpath()
        return p
    }
}

/// Pinking-shears edge for the mat behind the card.
struct Pinked: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); let t: CGFloat = 8, d: CGFloat = 4; var i = 0
        p.move(to: r.origin)
        var x = r.minX; while x < r.maxX { x += t; i += 1; p.addLine(to: CGPoint(x: min(x, r.maxX), y: r.minY + (i % 2 == 0 ? 0 : d))) }
        var y = r.minY; while y < r.maxY { y += t; i += 1; p.addLine(to: CGPoint(x: r.maxX - (i % 2 == 0 ? 0 : d), y: min(y, r.maxY))) }
        x = r.maxX; while x > r.minX { x -= t; i += 1; p.addLine(to: CGPoint(x: max(x, r.minX), y: r.maxY - (i % 2 == 0 ? 0 : d))) }
        y = r.maxY; while y > r.minY { y -= t; i += 1; p.addLine(to: CGPoint(x: r.minX + (i % 2 == 0 ? 0 : d), y: max(y, r.minY))) }
        p.closeSubpath(); return p
    }
}

struct SplitMix { var s: UInt64; init(_ s: UInt64) { self.s = s }
    mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) } }

/// Gold bulldog clip, drawn from the same geometry as the mockup's SVG (viewBox 120×64).
struct BrassClip: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 120
            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            var lever = Path()
            lever.move(to: P(41, 3)); lever.addQuadCurve(to: P(79, 3), control: P(60, 0))
            lever.addLine(to: P(86, 37)); lever.addLine(to: P(34, 37)); lever.closeSubpath()
            lever.addEllipse(in: CGRect(x: 56.4 * s, y: 7.2 * s, width: 7.2 * s, height: 7.2 * s))
            ctx.fill(lever, with: .linearGradient(Gradient(stops: sheenStops), startPoint: P(0, 0), endPoint: P(120, 0)), style: FillStyle(eoFill: true))
            var mark = Path(); mark.move(to: P(51, 17)); mark.addLine(to: P(69, 17)); mark.addLine(to: P(60, 26)); mark.closeSubpath()
            ctx.stroke(mark, with: .color(Color(hex: 0x7a5b17).opacity(0.55)), lineWidth: 0.9 * s)
            let bar = Path(roundedRect: CGRect(x: 2 * s, y: 35 * s, width: 116 * s, height: 23 * s), cornerRadius: 2 * s)
            ctx.fill(bar, with: .linearGradient(Gradient(stops: sheenStops), startPoint: P(0, 0), endPoint: P(120, 0)))
            ctx.opacity = 0.62
            ctx.fill(bar, with: .linearGradient(Gradient(stops: rollStops), startPoint: P(0, 35), endPoint: P(0, 58)))
            ctx.opacity = 0.75
            ctx.fill(Path(CGRect(x: 3 * s, y: 37 * s, width: 114 * s, height: 1 * s)), with: .color(Color(hex: 0xfffbe6)))
            ctx.opacity = 0.45
            ctx.fill(Path(roundedRect: CGRect(x: 2 * s, y: 54 * s, width: 116 * s, height: 4 * s), cornerRadius: 1.5 * s), with: .color(Color(hex: 0x5f4512)))
        }
        .aspectRatio(120 / 64, contentMode: .fit)
        .shadow(color: Color(hex: 0x50380a).opacity(0.35), radius: 1.5, y: 3)
    }
    private var sheenStops: [Gradient.Stop] { [
        .init(color: Color(hex: 0x8a6a22), location: 0), .init(color: Color(hex: 0xd6b65a), location: 0.16),
        .init(color: Color(hex: 0xf7e9ad), location: 0.34), .init(color: Color(hex: 0xcaa047), location: 0.52),
        .init(color: Color(hex: 0xa47d2b), location: 0.74), .init(color: Color(hex: 0xecd486), location: 0.9),
        .init(color: Color(hex: 0x8a6a22), location: 1)] }
    private var rollStops: [Gradient.Stop] { [
        .init(color: Color(hex: 0xfff4c8), location: 0), .init(color: Color(hex: 0xe2c06a), location: 0.22),
        .init(color: Color(hex: 0xb08a31), location: 0.5), .init(color: Color(hex: 0xf0d68b), location: 0.72),
        .init(color: Color(hex: 0x7f601d), location: 1)] }
}

extension Color {
    init(hex: UInt32) { self.init(red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255) }
}

// MARK: - Window + app

final class StickyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: StickyPanel!
    var status: NSStatusItem!
    let store = Store()

    func applicationDidFinishLaunching(_ note: Notification) {
        registerFonts()
        installMenus()

        let host = NSHostingView(rootView: NoteView(store: store).frame(width: 380, height: 900, alignment: .top))
        host.sizingOptions = []
        let size = NSSize(width: 380, height: 900)
        panel = StickyPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        panel.setFrameOrigin(savedOrigin(size))
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.autoMoving else { return }
                if let t = self.glideTarget, abs(t.x - self.panel.frame.minX) < 1, abs(t.y - self.panel.frame.minY) < 1 { return }  // our own glide landing
                self.home = nil                      // the user dragged it: that's the new spot
                let o = self.panel.frame.origin
                UserDefaults.standard.set(Double(o.x), forKey: "panelX"); UserDefaults.standard.set(Double(o.y), forKey: "panelY")
            }
        }
        store.layoutChanged = { [weak self] in DispatchQueue.main.async { self?.fitOnScreen() } }
        // sheetRect is window-local, so it doesn't change when the hidden token is dragged:
        // check the fit on every open, not just when the note's layout changes.
        stateWatch = store.$state.dropFirst().sink { [weak self] state in   // skip the launch value: leave the token where it was saved
            DispatchQueue.main.async { if state == .hidden { self?.returnHome() } else { self?.fitOnScreen() } }
        }
        panel.orderFrontRegardless()
        if store.isFirstRun {                     // a brand-new user: show the intro rather than a lone clip in the corner
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                MainActor.assumeIsolated { withAnimation(Motion.drawer) { self?.store.state = .compact } }
            }
        }
        // Transparent space around the note shouldn't swallow clicks meant for the desktop.
        let track: (NSEvent?) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                let p = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
                let flipped = CGPoint(x: p.x, y: panel.frame.height - p.y)
                panel.ignoresMouseEvents = !self.store.hitRect.contains(flipped)
            }
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { track($0) }
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { track($0); return $0 }
        panel.acceptsMouseMovedEvents = true
        #if SNAPSHOT
        if let d = ProcessInfo.processInfo.environment["SPRITES_OUT"] { Snapshot.sprites(to: d); NSApp.terminate(nil) } else
        if let icon = ProcessInfo.processInfo.environment["ICON_OUT"] { Snapshot.icon(to: icon); NSApp.terminate(nil) } else
        if ProcessInfo.processInfo.environment["FIT_TEST"] != nil { Snapshot.fitTest(panel: panel, store: store) } else { Snapshot.run(store: store) }
        #endif
    }

    // MARK: Keep the open note on screen

    private var home: NSPoint?          // where the hidden token sat before the note was nudged
    private var autoMoving = false
    private var glideTarget: NSPoint?
    private var glideGen = 0
    private var stateWatch: AnyCancellable?

    /// If the open note would spill past the edge of the screen, glide it just far enough to fit.
    private func fitOnScreen() {
        guard store.state != .hidden, store.sheetRect != .zero, let screen = panel.screen ?? NSScreen.main else { return }
        // Measure from where an in-flight glide will land, so repeated layout passes don't stack moves
        let base = autoMoving ? (glideTarget ?? panel.frame.origin) : panel.frame.origin
        let vis = screen.visibleFrame, f = NSRect(origin: base, size: panel.frame.size), r = store.sheetRect, margin: CGFloat = 12
        // sheetRect is top-left based inside the window; the fastener pokes ~50pt above it
        let top = f.maxY - r.minY + 50, bottom = f.maxY - r.maxY
        let left = f.minX + r.minX - 24, right = f.minX + r.maxX + 24
        var dy: CGFloat = 0, dx: CGFloat = 0
        if bottom + dy < vis.minY + margin { dy = vis.minY + margin - bottom }
        if top + dy > vis.maxY - margin { dy = vis.maxY - margin - top }        // the top always stays visible
        if right > vis.maxX - margin { dx = vis.maxX - margin - right }
        if left + dx < vis.minX + margin { dx = vis.minX + margin - left }
        guard abs(dx) > 0.5 || abs(dy) > 0.5 else { return }
        if home == nil { home = f.origin }
        glide(to: NSPoint(x: f.minX + dx, y: f.minY + dy))
    }

    /// Folding back to the token tucks it against the nearest screen edge, measured from where
    /// the user left it if the open note was nudged to fit.
    private func returnHome() {
        let target = snappedToEdge(home ?? panel.frame.origin)
        home = nil
        UserDefaults.standard.set(Double(target.x), forKey: "panelX"); UserDefaults.standard.set(Double(target.y), forKey: "panelY")
        guard abs(target.x - panel.frame.minX) > 0.5 || abs(target.y - panel.frame.minY) > 0.5 else { return }
        glide(to: target, duration: 0.2)
    }

    /// The window origin that puts the hidden token flush against whichever screen edge it's closest to.
    private func snappedToEdge(_ origin: NSPoint) -> NSPoint {
        let r = store.tokenRect, margin: CGFloat = 12
        guard r != .zero else { return origin }
        // tokenRect is top-left based inside the window; convert to screen coordinates
        let t = NSRect(x: origin.x + r.minX, y: origin.y + panel.frame.height - r.maxY, width: r.width, height: r.height)
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: t.midX, y: t.midY)) } ?? panel.screen ?? NSScreen.main
        guard let vis = screen?.visibleFrame else { return origin }
        let gaps = [t.minX - vis.minX, vis.maxX - t.maxX, vis.maxY - t.maxY, t.minY - vis.minY]   // left, right, top, bottom
        var dx: CGFloat = 0, dy: CGFloat = 0
        switch gaps.indices.min(by: { gaps[$0] < gaps[$1] }) {
        case 0: dx = vis.minX + margin - t.minX
        case 1: dx = vis.maxX - margin - t.maxX
        case 2: dy = vis.maxY - margin - t.maxY
        default: dy = vis.minY + margin - t.minY
        }
        // keep the token fully on screen along the other axis too
        let x = t.minX + dx, y = t.minY + dy
        dx += max(0, vis.minX + margin - x) - max(0, x + t.width - (vis.maxX - margin))
        dy += max(0, vis.minY + margin - y) - max(0, y + t.height - (vis.maxY - margin))
        return NSPoint(x: origin.x + dx, y: origin.y + dy)
    }

    private func glide(to origin: NSPoint, duration: TimeInterval = 0.3) {
        autoMoving = true
        glideTarget = origin
        glideGen += 1
        let gen = glideGen
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : duration
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
            panel.animator().setFrame(NSRect(origin: origin, size: panel.frame.size), display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { if self?.glideGen == gen { self?.autoMoving = false } }
        }
    }

    private func savedOrigin(_ size: NSSize) -> NSPoint {
        let d = UserDefaults.standard
        if d.object(forKey: "panelX") != nil { return NSPoint(x: d.double(forKey: "panelX"), y: d.double(forKey: "panelY")) }
        let v = NSScreen.screens.first?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)   // the menu-bar display
        return NSPoint(x: v.maxX - size.width + 10, y: v.maxY - size.height - 8)   // top-right, the note drops down from its clip
    }

    private func registerFonts() {
        for name in ["CormorantGaramond", "CormorantGaramond-Italic", "EBGaramond", "EBGaramond-Italic", "CourierPrime-Regular", "CourierPrime-Italic"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    /// Accessory apps get no menu bar, so ⌘C / ⌘V / ⌘X / ⌘A / ⌘Z need an Edit menu to route through.
    private func installMenus() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appMenu.addItem(withTitle: "Quit Sticky Note", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z"); redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let plain = edit.addItem(withTitle: "Paste and Match Style", action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "v")
        plain.keyEquivalentModifierMask = [.command, .option, .shift]
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Sticky Note")
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Note", action: #selector(showNote), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Hide Note", action: #selector(hideNote), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Copy All Tasks", action: #selector(copyAll), keyEquivalent: "").target = self
        loginItem = menu.addItem(withTitle: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        dockItem = menu.addItem(withTitle: "Show in Dock", action: #selector(toggleDock), keyEquivalent: "")
        dockItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Sticky Note", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        status.menu = menu
        // Turn on Open at Login once, the first time the app runs; after that it's the user's choice.
        #if SNAPSHOT
        if ProcessInfo.processInfo.environment["UNREGISTER_LOGIN"] != nil { try? SMAppService.mainApp.unregister(); print("LOGIN", SMAppService.mainApp.status.rawValue); NSApp.terminate(nil) }
        #else
        if !UserDefaults.standard.bool(forKey: "loginSetupDone") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "loginSetupDone")
        }
        #endif
        refreshLoginItem()
        applyDockSetting()
    }

    @objc func showNote() { panel.orderFrontRegardless(); withAnimation(Motion.drawer) { store.state = .compact } }
    @objc func hideNote() { withAnimation(Motion.ui) { store.state = .hidden } }
    @objc func copyAll() { store.copyAll() }

    private var loginItem: NSMenuItem!
    @objc func toggleLogin() {
        let svc = SMAppService.mainApp
        if svc.status == .enabled { try? svc.unregister() } else { try? svc.register() }
        refreshLoginItem()
    }
    private func refreshLoginItem() { loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off }

    // MARK: Dock: on by default, since a crowded menu bar can hide the paperclip; it gives a Dock icon with Quit in its menu

    private var dockItem: NSMenuItem!

    @objc func toggleDock() {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "showInDock"), forKey: "showInDock")
        applyDockSetting()
    }

    private func applyDockSetting() {
        let on = UserDefaults.standard.bool(forKey: "showInDock")
        NSApp.setActivationPolicy(on ? .regular : .accessory)
        dockItem.state = on ? .on : .off
        panel?.orderFrontRegardless()            // switching Dock modes can hide the app's windows; keep the note up
    }

    /// Clicking the Dock icon (or a Dock shortcut to the app) opens the note.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showNote()
        return false
    }
}

@main
struct Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        UserDefaults.standard.register(defaults: ["showInDock": true])
        // Decide before launch, so turning the Dock off doesn't flash an icon at startup
        app.setActivationPolicy(UserDefaults.standard.bool(forKey: "showInDock") ? .regular : .accessory)
        app.run()
    }
}
