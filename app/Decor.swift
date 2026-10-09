import SwiftUI
import AppKit
import CoreImage

/// Horizontal paper fibers (mockup `--fibers`): noise stretched along x, rendered once.
enum Fibers {
    static let image: NSImage = {
        let ctx = CIContext()
        let size = CGRect(x: 0, y: 0, width: 600, height: 600)
        let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
            .transformed(by: CGAffineTransform(scaleX: 22, y: 1)).cropped(to: size)
        let mono = noise.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.4, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.37, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0.32, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.16),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)])
        let cg = ctx.createCGImage(mono, from: size)!
        return NSImage(cgImage: cg, size: NSSize(width: 300, height: 300))
    }()
}

private func rotated(_ p: Path, _ deg: Double, _ cx: CGFloat, _ cy: CGFloat) -> Path {
    p.applying(CGAffineTransform(translationX: cx, y: cy).rotated(by: deg * .pi / 180).translatedBy(x: -cx, y: -cy))
}

/// Sage wax seal, drawn from the mockup's 100×100 SVG.
struct WaxSeal: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 100
            ctx.scaleBy(x: s, y: s)
            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
            var blob = Path()
            blob.move(to: P(50, 4))
            blob.addCurve(to: P(95, 34), control1: P(70, 2), control2: P(89, 14))
            blob.addCurve(to: P(82, 86), control1: P(100, 53), control2: P(95, 73))
            blob.addCurve(to: P(33, 94), control1: P(69, 97), control2: P(49, 100))
            blob.addCurve(to: P(4, 51), control1: P(15, 88), control2: P(4, 71))
            blob.addCurve(to: P(8, 27), control1: P(3, 40), control2: P(6, 31))
            blob.addCurve(to: P(5, 20), control1: P(5, 26), control2: P(3, 23))
            blob.addCurve(to: P(13, 20), control1: P(7, 17), control2: P(11, 18))
            blob.addCurve(to: P(50, 4), control1: P(19, 11), control2: P(32, 5))
            blob.closeSubpath()
            let grad = Gradient(stops: [.init(color: Color(hex: 0xa6b392), location: 0), .init(color: Color(hex: 0x7f8d6b), location: 0.45),
                                        .init(color: Color(hex: 0x617051), location: 0.85), .init(color: Color(hex: 0x4d5a40), location: 1)])
            ctx.fill(blob, with: .radialGradient(grad, center: P(3 + 0.36 * 97, 2 + 0.3 * 97), startRadius: 0, endRadius: 0.85 * 97))
            var hi = Path(); hi.move(to: P(50, 4)); hi.addCurve(to: P(95, 34), control1: P(70, 2), control2: P(89, 14))
            ctx.stroke(hi, with: .color(Color(hex: 0xc3cdb3).opacity(0.55)), lineWidth: 1.4)
            func oval(_ dx: CGFloat, _ dy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: 50 + dx - rx, y: 52 + dy - ry, width: 2 * rx, height: 2 * ry)) }
            ctx.fill(oval(0, 0, 28.5, 36.5), with: .color(Color(hex: 0x6a7856)))
            ctx.stroke(oval(-0.8, -0.8, 28.5, 36.5), with: .color(Color(hex: 0xa9b597).opacity(0.75)), lineWidth: 2)
            ctx.stroke(oval(0.8, 0.8, 28.5, 36.5), with: .color(Color(hex: 0x3e4a32).opacity(0.6)), lineWidth: 2)
            ctx.stroke(oval(0, 0, 23.5, 31.5), with: .color(Color(hex: 0x91a07e)),
                       style: StrokeStyle(lineWidth: 1.7, lineCap: .round, dash: [0.1, 3.3]))
            func sprig(_ hex: UInt32, _ op: Double, _ dx: CGFloat, _ dy: CGFloat) {
                var c = ctx; c.translateBy(x: dx, y: dy); c.opacity = op
                let col = GraphicsContext.Shading.color(Color(hex: hex))
                var stem = Path(); stem.move(to: P(50, 77))
                stem.addCurve(to: P(51, 46), control1: P(49.5, 66), control2: P(49, 57))
                stem.addCurve(to: P(56.5, 31), control1: P(52, 40), control2: P(54, 35))
                c.stroke(stem, with: col, style: StrokeStyle(lineWidth: 2.1, lineCap: .round))
                var shapes = Path()
                func leaf(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ deg: Double) {
                    shapes.addPath(rotated(Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry)), deg, cx, cy)) }
                func dot(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) { shapes.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)) }
                leaf(44, 62, 6.4, 2.9, -32); leaf(57, 56, 6.2, 2.7, 28); leaf(45.5, 47, 5.2, 2.4, -42); leaf(58.5, 42, 4.8, 2.2, 36)
                dot(43, 36, 2.4); dot(47, 32.5, 2.2); dot(40.5, 40, 2); dot(46, 38, 1.6)
                dot(60, 29, 2.2); dot(63.5, 32.5, 2); dot(57, 26, 1.8)
                c.fill(shapes, with: col); c.stroke(shapes, with: col, lineWidth: 1)
            }
            sprig(0xb4bfa3, 0.8, -0.8, -0.8)
            sprig(0x3d4832, 0.7, 0.9, 0.9)
            sprig(0x7b8968, 1, 0, 0)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Black paperclip (viewBox 27×90).
struct Paperclip: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 27
            ctx.scaleBy(x: s, y: s)
            var d = Path()
            d.move(to: CGPoint(x: 9, y: 62)); d.addLine(to: CGPoint(x: 9, y: 14))
            d.addArc(center: CGPoint(x: 16.5, y: 14), radius: 7.5, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            d.addLine(to: CGPoint(x: 24, y: 72))
            d.addArc(center: CGPoint(x: 13.5, y: 72), radius: 10.5, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            d.addLine(to: CGPoint(x: 3, y: 24))
            let st = { (w: CGFloat) in StrokeStyle(lineWidth: w, lineCap: .round) }
            ctx.stroke(d.offsetBy(dx: 1.6, dy: 2.4), with: .color(.black.opacity(0.18)), style: st(2.6))
            ctx.stroke(d, with: .color(Color(hex: 0x2b2b2b)), style: st(2.3))
            ctx.stroke(d.offsetBy(dx: -0.5, dy: -0.4), with: .color(Color(hex: 0x9a9a9a).opacity(0.7)), style: st(0.7))
        }
        .aspectRatio(27 / 90, contentMode: .fit)
    }
}

/// Embroidered silver star: 10 shaded facets, diagonal stitch lines, thin outline.
struct StarSticker: View {
    var size: CGFloat
    var rotation: Double
    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 100
            ctx.scaleBy(x: s, y: s)
            var pts: [CGPoint] = []
            for i in 0..<5 {
                let ao = (-90 + 72 * Double(i)) * .pi / 180, ai = (-90 + 36 + 72 * Double(i)) * .pi / 180
                pts.append(CGPoint(x: 50 + 47 * cos(ao), y: 50 + 47 * sin(ao)))
                pts.append(CGPoint(x: 50 + 19.5 * cos(ai), y: 50 + 19.5 * sin(ai)))
            }
            var outline = Path(); outline.move(to: pts[0]); pts.dropFirst().forEach { outline.addLine(to: $0) }; outline.closeSubpath()
            var c = ctx; c.clip(to: outline)
            let light = -125.0 * .pi / 180
            for k in 0..<10 {
                let a = pts[k], b = pts[(k + 1) % 10]
                let mid = atan2(Double((a.y + b.y) / 2 - 50), Double((a.x + b.x) / 2 - 50))
                let g = min(255, max(0, (168 + cos(mid + (k % 2 == 0 ? 1 : -1) * 0.55 - light) * 58).rounded()))
                var f = Path(); f.move(to: CGPoint(x: 50, y: 50)); f.addLine(to: a); f.addLine(to: b); f.closeSubpath()
                c.fill(f, with: .color(Color(red: g / 255, green: min(255, g + 3) / 255, blue: min(255, g + 7) / 255)))
            }
            c.rotate(by: .degrees(58))
            var lines = Path()
            var x: CGFloat = -160; while x < 160 { lines.addRect(CGRect(x: x, y: -160, width: 1, height: 320)); x += 2.2 }
            c.fill(lines, with: .color(.white.opacity(0.35)))
            ctx.stroke(outline, with: .color(Color(hex: 0x7f858b)), style: StrokeStyle(lineWidth: 0.9, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.22), radius: 0.75, y: 2)
        .rotationEffect(.degrees(rotation))
    }
}

/// Rect with straight top/left/right, a small rounded top-right corner and a jagged torn bottom.
struct TornEdge: Shape {
    var seed: UInt64 = 11
    var drop: CGFloat = 0
    func path(in r: CGRect) -> Path {
        var rng = SplitMix(seed)
        func rnd() -> CGFloat { CGFloat(rng.next() >> 11) / CGFloat(1 << 53) }
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + w - 6, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + w, y: r.minY + 6), control: CGPoint(x: r.minX + w, y: r.minY))
        var y = h - 10 - drop
        var x = w
        while x >= 0 {
            y = min(h - drop, max(h - 18 - drop, y + (rnd() - 0.5) * 7))
            p.addLine(to: CGPoint(x: r.minX + x, y: r.minY + y))
            x -= 3 + rnd() * 4
        }
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + y))
        p.closeSubpath()
        return p
    }
}

/// Torn notebook scrap: white fiber rim under a kraft-grey sheet.
struct TornPaper: View {
    var body: some View {
        ZStack {
            TornEdge(seed: 11).fill(Color(hex: 0xfaf8f3))
            TornEdge(seed: 11, drop: 3).fill(Color(hex: 0xe9e3d8))
                .overlay(Image(nsImage: Fibers.image).resizable(resizingMode: .tile).clipShape(TornEdge(seed: 11, drop: 3)))
                .overlay(Image(nsImage: Grain.image).resizable(resizingMode: .tile).clipShape(TornEdge(seed: 11, drop: 3)))
                .overlay(LinearGradient(stops: [
                    .init(color: .clear, location: 0.44), .init(color: .white.opacity(0.22), location: 0.456),
                    .init(color: .black.opacity(0.035), location: 0.466), .init(color: .clear, location: 0.485)],
                    startPoint: UnitPoint(x: 0, y: 0.46), endPoint: UnitPoint(x: 1, y: 0.54))
                    .clipShape(TornEdge(seed: 11, drop: 3)))
        }
        .compositingGroup()
        .shadow(color: Color(hex: 0x28261e).opacity(0.16), radius: 0.5, y: 1)
        .shadow(color: Color(hex: 0x28261e).opacity(0.13), radius: 8, y: 10)
    }
}

/// Heavy deckled handmade sheet with embossed mottle and a pale rim.
struct WaxPaper: View {
    var body: some View {
        let edge = Deckle(amp: 3.2, seed: 12)
        ZStack {
            edge.fill(Color(hex: 0xf3eee4))
                .overlay(Image(nsImage: Grain.mottle).resizable(resizingMode: .tile).blendMode(.softLight).opacity(0.6).clipShape(edge))
                .overlay(Image(nsImage: Grain.image).resizable(resizingMode: .tile).clipShape(edge))
                .overlay(edge.stroke(Color(hex: 0xfaf7f0), lineWidth: 6).clipShape(edge))
        }
        .compositingGroup()
        .shadow(color: Color(hex: 0x3c3728).opacity(0.16), radius: 0.5, y: 1)
        .shadow(color: Color(hex: 0x3c3728).opacity(0.14), radius: 11, y: 14)
    }
}
