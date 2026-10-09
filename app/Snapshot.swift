// Debug-only: renders the note in each state and style to PNGs (built with -D SNAPSHOT). Not part of the app build.
#if SNAPSHOT
import AppKit
import SwiftUI

/// App icon artwork (1024×1024): deckled card under the brass clip, one task ticked and struck through.
struct AppIconArt: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xe9ecdf), Color(hex: 0xcbd3bf)], startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.22), radius: 18, y: 12)
            ZStack(alignment: .top) {
                ZStack(alignment: .topLeading) {
                    Deckle(amp: 2.4, seed: 7).fill(Ink.paper)
                        .overlay(Image(nsImage: Grain.image).resizable(resizingMode: .tile).clipShape(Deckle(amp: 2.4, seed: 7)))
                        .overlay(Deckle(amp: 2.4, seed: 7).stroke(Ink.rim, lineWidth: 6))
                    VStack(alignment: .leading, spacing: 46) {
                        iconRow(done: true, width: 300)
                        iconRow(done: false, width: 230)
                        iconRow(done: false, width: 270, dashed: true)
                    }
                    .padding(.leading, 70).padding(.top, 150)
                }
                .frame(width: 560, height: 520)
                .shadow(color: Color(hex: 0x46340f).opacity(0.25), radius: 14, y: 16)
                BrassClip().frame(width: 260).offset(y: -66)
            }
            .rotationEffect(.degrees(-4))
            .offset(y: 40)
        }
        .frame(width: 1024, height: 1024)
    }
    private func iconRow(done: Bool, width: CGFloat, dashed: Bool = false) -> some View {
        HStack(spacing: 30) {
            RoundedRectangle(cornerRadius: 6).strokeBorder(Ink.text.opacity(dashed ? 0.3 : 0.8), style: StrokeStyle(lineWidth: 7, dash: dashed ? [12, 9] : []))
                .frame(width: 46, height: 46)
                .overlay { if done { Path { p in p.move(to: CGPoint(x: 11, y: 24)); p.addLine(to: CGPoint(x: 20, y: 33)); p.addLine(to: CGPoint(x: 36, y: 14)) }
                    .stroke(Ink.text, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)) } }
            Capsule().fill(done ? Ink.done.opacity(0.55) : (dashed ? Ink.done.opacity(0.35) : Ink.text.opacity(0.85))).frame(width: width, height: 18)
                .overlay { if done { Capsule().fill(Color(hex: 0x3a2f22)).frame(width: width + 16, height: 6) } }
        }
    }
}

@MainActor
enum Snapshot {
    /// Transparent sprites of the app's own art, for the website background.
    static func sprites(to dir: String) {
        func save<V: View>(_ v: V, _ name: String) {
            let r = ImageRenderer(content: v.padding(14)); r.scale = 2; r.isOpaque = false
            if let cg = r.cgImage { try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/" + name + ".png")) }
        }
        save(StarSticker(size: 90, rotation: 0), "star")
        save(BrassClip().frame(width: 140), "clip")
        save(WaxSeal().frame(width: 96, height: 96).shadow(color: Color(hex: 0x28321e).opacity(0.35), radius: 3, y: 4), "seal")
        save(Paperclip().frame(width: 30, height: 100), "paperclip")
    }

    static func icon(to path: String) {
        let r = ImageRenderer(content: AppIconArt()); r.scale = 1
        if let cg = r.cgImage { try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path)) }
    }

    /// Drop the token near the bottom of the screen, open the note, and check it was lifted fully on screen.
    static func fitTest(panel: NSPanel, store: Store) {
        let vis = (panel.screen ?? NSScreen.main!).visibleFrame
        let start = NSPoint(x: vis.maxX - 380, y: vis.minY - 900 + 140)   // token ~90pt above the bottom edge
        panel.setFrameOrigin(start)
        func bottom() -> CGFloat { panel.frame.maxY - store.sheetRect.maxY }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(Motion.drawer) { store.state = .compact }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                print("COMPACT-FITS", bottom() >= vis.minY + 11 ? "ok" : "FAIL", "bottom=\(bottom()) visMinY=\(vis.minY) moved=\(panel.frame.minY - start.y)")
                withAnimation(Motion.drawer) { store.state = .expanded }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let top = panel.frame.maxY - store.sheetRect.minY + 50
                    print("EXPANDED-FITS", bottom() >= vis.minY + 11 || top >= vis.maxY - 13 ? "ok" : "FAIL", "bottom=\(bottom()) top=\(top) visMaxY=\(vis.maxY)")
                    withAnimation(Motion.ui) { store.state = .hidden }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        print("RETURNED-HOME", abs(panel.frame.minY - start.y) < 1 && abs(panel.frame.minX - start.x) < 1 ? "ok" : "FAIL \(panel.frame.origin) vs \(start)")
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    static func run(store: Store) {
        let out = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] ?? NSTemporaryDirectory()
        let parsed = Store.lines(from: "- one\n• two\n[x] three\n\n4) four\n  five  \n- [ ] six")
        print("PASTE-PARSE", parsed == ["one", "two", "three", "four", "five", "six"] ? "ok" : "FAIL \(parsed)")
        for (k, t) in [3, 0].enumerated() where t < store.tasks.count { store.tasks[t].done = true; _ = k }
        var shots: [(String, NoteStyle, NoteState, Bool)] = []
        for s in NoteStyle.allCases { shots += [("\(s.rawValue)-1-hidden", s, .hidden, false), ("\(s.rawValue)-2-default", s, .compact, true), ("\(s.rawValue)-3-expanded", s, .expanded, true)] }
        var delay = 0.8
        for (name, style, state, hover) in shots {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                store.style = style; store.state = state
                let view = NoteView(store: store, forceHover: hover).frame(width: 380, height: 900, alignment: .top)
                    .background(LinearGradient(colors: [Color(hex: 0xeceee6), Color(hex: 0xdde2d4)], startPoint: .top, endPoint: .bottom))
                let host = NSHostingView(rootView: view)
                host.frame = NSRect(x: 0, y: 0, width: 380, height: 900)
                let w = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                w.contentView = host; w.setFrameOrigin(NSPoint(x: -4000, y: 0)); w.orderBack(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    host.layoutSubtreeIfNeeded()
                    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out + "/\(name).png"))
                    w.orderOut(nil)
                }
            }
            delay += 1.2
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1) {
            print("FONTS", ["CormorantGaramond-SemiBold", "EBGaramond-Regular", "EBGaramond-Italic", "CourierPrime-Regular", "CourierPrime-Italic"].map { "\($0)=\(NSFont(name: $0, size: 12) != nil)" }.joined(separator: " "))
            NSApp.terminate(nil)
        }
    }
}
#endif
