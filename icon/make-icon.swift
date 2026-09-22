import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Draws the Mountie app icon (a network drive wearing a campaign hat) at any size.
// Usage: make-icon OUTPUT_DIR   -> writes an .iconset's PNGs; icon/build-icon.sh turns it into an .icns.

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                            CGFloat(hex & 0xFF) / 255, alpha])!
}

func gradient(_ stops: [(UInt32, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map { color($0.0) } as CFArray, locations: stops.map { $0.1 })!
}

/// Draws the icon into a size×size bitmap. Coordinates below are on a 1024 canvas, y measured from the top.
func render(size: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(size) / 1024
    ctx.scaleBy(x: s, y: s)

    func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: 1024 - y - h, width: w, height: h) }
    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: 1024 - y) }
    // Shadow offsets/blur are not scaled by the CTM, so scale them by hand. dy > 0 casts downward.
    func shadow(dy: CGFloat, blur: CGFloat, alpha: CGFloat, _ hex: UInt32 = 0x000000) {
        ctx.setShadow(offset: CGSize(width: 0, height: -dy * s), blur: blur * s, color: color(hex, alpha))
    }
    func fill(_ path: CGPath, _ g: CGGradient, from: CGPoint, to: CGPoint) {
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        ctx.drawLinearGradient(g, start: from, end: to, options: [])
        ctx.restoreGState()
    }

    // --- Body: red squircle (macOS grid: 824 pt body on a 1024 canvas) ---
    let body = CGPath(roundedRect: R(100, 100, 824, 824), cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    shadow(dy: 14, blur: 30, alpha: 0.35)
    ctx.setFillColor(color(0xB3202B))
    ctx.addPath(body); ctx.fillPath()
    ctx.restoreGState()
    fill(body, gradient([(0xF2585C, 0), (0xC72A34, 0.55), (0xA81C27, 1)]), from: P(0, 100), to: P(0, 924))
    // soft top light + hairline edge
    ctx.saveGState()
    ctx.addPath(body); ctx.clip()
    let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(glow, start: P(0, 100), end: P(0, 520), options: [])
    ctx.restoreGState()
    ctx.setStrokeColor(color(0xFFFFFF, 0.16)); ctx.setLineWidth(3)
    ctx.addPath(CGPath(roundedRect: R(101.5, 101.5, 821, 821), cornerWidth: 184.5, cornerHeight: 184.5, transform: nil)); ctx.strokePath()

    // --- The drive: a white slab ---
    let slab = CGPath(roundedRect: R(212, 505, 600, 268), cornerWidth: 46, cornerHeight: 46, transform: nil)
    ctx.saveGState()
    shadow(dy: 22, blur: 34, alpha: 0.38, 0x5A0A12)
    ctx.setFillColor(color(0xE9ECF2))
    ctx.addPath(slab); ctx.fillPath()
    ctx.restoreGState()
    fill(slab, gradient([(0xFFFFFF, 0), (0xE7EAF0, 1)]), from: P(0, 505), to: P(0, 773))
    ctx.setFillColor(color(0xC4CAD4))                                   // bottom edge
    ctx.saveGState(); ctx.addPath(slab); ctx.clip()
    ctx.fill(R(212, 753, 600, 20)); ctx.restoreGState()
    // vents
    ctx.setFillColor(color(0xD3D8E1))
    for i in 0..<3 {
        ctx.addPath(CGPath(roundedRect: R(268, 590 + CGFloat(i) * 42, 250, 16), cornerWidth: 8, cornerHeight: 8, transform: nil)); ctx.fillPath()
    }
    // status light (mounted = green)
    ctx.saveGState()
    shadow(dy: 0, blur: 26, alpha: 0.9, 0x2FD27A)
    ctx.setFillColor(color(0x2FD27A))
    ctx.fillEllipse(in: R(706, 620, 52, 52))
    ctx.restoreGState()
    ctx.setFillColor(color(0x8FF0BE, 0.9))
    ctx.fillEllipse(in: R(720, 632, 16, 12))

    // --- The hat: a flat-brimmed campaign hat sitting on the drive ---
    let crown = CGMutablePath()
    crown.move(to: P(338, 470))
    crown.addLine(to: P(366, 330))
    crown.addQuadCurve(to: P(430, 284), control: P(372, 284))
    crown.addLine(to: P(594, 284))
    crown.addQuadCurve(to: P(658, 330), control: P(652, 284))
    crown.addLine(to: P(686, 470))
    crown.addQuadCurve(to: P(338, 470), control: P(512, 512))   // rounded base, tucked into the brim
    crown.closeSubpath()

    let brim = CGPath(ellipseIn: R(148, 424, 728, 96), transform: nil)
    // brim
    ctx.saveGState()
    shadow(dy: 16, blur: 22, alpha: 0.45, 0x3A0509)
    ctx.setFillColor(color(0xB98B52))
    ctx.addPath(brim); ctx.fillPath()
    ctx.restoreGState()
    fill(brim, gradient([(0xEAC898, 0), (0xC9A06A, 0.6), (0xA9793F, 1)]), from: P(0, 424), to: P(0, 520))
    ctx.setStrokeColor(color(0xFFFFFF, 0.28)); ctx.setLineWidth(4)      // brim lip
    ctx.addPath(CGPath(ellipseIn: R(156, 432, 712, 80), transform: nil)); ctx.strokePath()
    // crown
    fill(crown, gradient([(0xD9B27B, 0), (0xEBC994, 0.45), (0xC29A63, 1)]), from: P(338, 0), to: P(686, 0))
    // band
    ctx.saveGState()
    ctx.addPath(crown); ctx.clip()
    let band = gradient([(0x8A5B33, 0), (0x5F3B1E, 1)])
    ctx.addRect(R(320, 404, 384, 110)); ctx.clip()
    ctx.drawLinearGradient(band, start: P(0, 404), end: P(0, 480), options: [.drawsAfterEndLocation])
    ctx.restoreGState()
    // front crease + pinch shading on the crown
    ctx.saveGState()
    ctx.addPath(crown); ctx.clip()
    ctx.setStrokeColor(color(0x8F6535, 0.32)); ctx.setLineWidth(14); ctx.setLineCap(.round)
    ctx.move(to: P(512, 292)); ctx.addQuadCurve(to: P(512, 400), control: P(506, 350)); ctx.strokePath()
    let sheen = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.12), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: P(340, 0), end: P(440, 0), options: [])
    ctx.restoreGState()
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("couldn't write \(url.path)") }
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
// (points, scale) pairs macOS wants in an .iconset
for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "icon_\(pt)x\(pt)" + (scale == 2 ? "@2x" : "") + ".png"
    writePNG(render(size: pt * scale), to: out.appendingPathComponent(name))
}
print("wrote iconset PNGs to \(out.path)")
