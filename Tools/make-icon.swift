// Draws the MacSweat app icon: a nervous little face breaking a sweat, on a soft matte squircle.
// Usage: make-icon <out.iconset> [preview-1024.png]
// Keep the eyes + drop geometry in sync with BrandGlyph in Sources/MacSweat.swift.
import AppKit
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func grad(_ c: [CGColor], _ s: [CGFloat]? = nil) -> CGGradient { CGGradient(colorsSpace: space, colors: c as CFArray, locations: s)! }

func dropPath(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ tip: CGFloat, tilt: CGFloat = 0) -> CGPath {
    let a = acos(r / tip), L = sqrt(tip * tip - r * r)
    let top = CGPoint(x: 0, y: tip)
    let right = CGPoint(x: r * sin(a), y: r * cos(a)), left = CGPoint(x: -r * sin(a), y: r * cos(a))
    let ux = -cos(a), uy = sin(a), nx = sin(a), ny = cos(a)
    let p = CGMutablePath()
    p.move(to: top)
    p.addCurve(to: right, control1: CGPoint(x: -0.3 * L * ux + 0.1 * L * nx, y: tip - 0.3 * L * uy + 0.1 * L * ny),
               control2: CGPoint(x: right.x + 0.38 * L * ux, y: right.y + 0.38 * L * uy))
    p.addArc(center: .zero, radius: r, startAngle: .pi / 2 - a, endAngle: .pi / 2 + a - 2 * .pi, clockwise: true)
    p.addCurve(to: top, control1: CGPoint(x: left.x - 0.38 * L * ux, y: left.y + 0.38 * L * uy),
               control2: CGPoint(x: 0.3 * L * ux - 0.1 * L * nx, y: tip - 0.3 * L * uy + 0.1 * L * ny))
    p.closeSubpath()
    var t = CGAffineTransform(translationX: cx, y: cy).rotated(by: tilt)
    return p.copy(using: &t)!
}

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = CGPath(roundedRect: body, cornerWidth: 190, cornerHeight: 190, transform: nil)
let cream = rgb(0xF4E4C8), accent = rgb(0xFF7A2F)

func matteBody(_ ctx: CGContext) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(0x000000, 0.35))
    ctx.addPath(squircle); ctx.setFillColor(rgb(0x1E1E20)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(squircle); ctx.clip()
    ctx.drawLinearGradient(grad([rgb(0x2C2C2F), rgb(0x1C1C1E), rgb(0x161618)], [0, 0.6, 1]), start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // soft inner light along the top edge, like a gently domed matte surface
    let outside = CGMutablePath(); outside.addRect(body.insetBy(dx: -100, dy: -100)); outside.addPath(squircle)
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0xFFFFFF, 0.10))
    ctx.addPath(outside); ctx.setFillColor(rgb(0x000000)); ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()
}

/// Paints a shape as a soft, slightly puffy matte element: shadow under, colour, gentle top light.
func puffy(_ ctx: CGContext, _ path: CGPath, _ color: CGColor, light: CGColor) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 34, color: rgb(0x000000, 0.5))
    ctx.addPath(path); ctx.setFillColor(color); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    let box = path.boundingBoxOfPath
    ctx.drawLinearGradient(grad([light, light, color], [0, 0.25, 1]), start: CGPoint(x: box.midX, y: box.maxY), end: CGPoint(x: box.midX, y: box.minY), options: [])
    let outside = CGMutablePath(); outside.addRect(box.insetBy(dx: -60, dy: -60)); outside.addPath(path)
    ctx.setShadow(offset: CGSize(width: 0, height: 9), blur: 16, color: rgb(0x5A3A14, 0.32))
    ctx.addPath(outside); ctx.setFillColor(rgb(0x000000)); ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()
}

// A — Spike: a CPU line that spikes, with a bead of sweat flying off the peak.
func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
}

/// The icon itself is a nervous little face: round eyes glancing at the bead of sweat on its forehead.
func face(_ ctx: CGContext) {
    matteBody(ctx)
    let ink = rgb(0x1B1B1D)
    for x in [336.0, 536.0] as [CGFloat] {
        puffy(ctx, CGPath(ellipseIn: CGRect(x: x - 78, y: 462 - 94, width: 156, height: 188), transform: nil), cream, light: rgb(0xFFF8EA))
        // pupils look up and to the right, at the bead
        ctx.addEllipse(in: CGRect(x: x + 24 - 40, y: 462 + 30 - 40, width: 80, height: 80))
        ctx.setFillColor(ink); ctx.fillPath()
        ctx.addEllipse(in: CGRect(x: x + 38, y: 462 + 44, width: 20, height: 20))
        ctx.setFillColor(rgb(0xFFF8EA)); ctx.fillPath()
    }
    // a small wobbly mouth
    let mouth = CGMutablePath()
    mouth.move(to: CGPoint(x: 362, y: 286))
    mouth.addCurve(to: CGPoint(x: 436, y: 286), control1: CGPoint(x: 380, y: 318), control2: CGPoint(x: 418, y: 318))
    mouth.addCurve(to: CGPoint(x: 510, y: 286), control1: CGPoint(x: 454, y: 254), control2: CGPoint(x: 492, y: 254))
    puffy(ctx, mouth.copy(strokingWithWidth: 30, lineCap: .round, lineJoin: .round, miterLimit: 1).normalized(), cream, light: rgb(0xFFF8EA))
    puffy(ctx, dropPath(712, 640, 58, 132, tilt: -0.12), accent, light: rgb(0xFFB27A))
}

func render(side: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    let ns = NSGraphicsContext(bitmapImageRep: rep)!; NSGraphicsContext.current = ns
    ns.cgContext.scaleBy(x: CGFloat(side) / 1024, y: CGFloat(side) / 1024)
    face(ns.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for (name, pixels) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                       ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try render(side: pixels).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(output)/icon_\(name).png"))
}
if CommandLine.arguments.count > 2 {
    try render(side: 1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
