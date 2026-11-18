// Draws the MacSweat app icon — a nervous laptop with a bead of sweat.
// Usage: make-icon <out.iconset> [preview-1024.png]
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let amber = color(0xFFB238), coral = color(0xFF5A36), ink = color(0x3B1E12)

/// A teardrop with its round part centred at (cx, cy), radius r, and its tip `tip` above the centre.
func dropPath(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ tip: CGFloat) -> NSBezierPath {
    let alpha = acos(r / tip)
    let top = NSPoint(x: cx, y: cy + tip)
    let right = NSPoint(x: cx + r * sin(alpha), y: cy + r * cos(alpha))
    let left = NSPoint(x: cx - r * sin(alpha), y: cy + r * cos(alpha))
    let path = NSBezierPath()
    path.move(to: top)
    path.curve(to: right, controlPoint1: NSPoint(x: cx + r * 0.18, y: cy + tip * 0.72),
               controlPoint2: NSPoint(x: right.x + r * 0.05, y: right.y + r * 0.35))
    path.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: r, startAngle: 90 - alpha * 180 / .pi,
                   endAngle: 90 + alpha * 180 / .pi - 360, clockwise: true)
    path.curve(to: top, controlPoint1: NSPoint(x: left.x - r * 0.05, y: left.y + r * 0.35),
               controlPoint2: NSPoint(x: cx - r * 0.18, y: cy + tip * 0.72))
    path.close()
    return path
}

func withShadow(_ hex: UInt32, _ alpha: CGFloat, blur: CGFloat, y: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(hex, alpha)
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: y)
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

func stroke(_ path: NSBezierPath, _ width: CGFloat, _ color: NSColor) {
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    color.setStroke()
    path.stroke()
}

/// Drawn on a 1024 × 1024 canvas following the macOS icon grid (824 pt body).
func drawIcon() {
    // Warm squircle background with a soft glow at the top.
    let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    withShadow(0x000000, 0.28, blur: 22, y: -10) { coral.setFill(); body.fill() }
    NSGradient(colors: [amber, color(0xFF8A3D), coral])!.draw(in: body, angle: -90)
    NSGraphicsContext.saveGraphicsState()
    body.addClip()
    NSGradient(colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)])!
        .draw(in: NSBezierPath(ovalIn: NSRect(x: 160, y: 640, width: 704, height: 420)), relativeCenterPosition: .zero)
    NSGraphicsContext.restoreGraphicsState()

    // Laptop.
    let lid = NSRect(x: 236, y: 360, width: 552, height: 366)
    withShadow(0x7A2A10, 0.25, blur: 18, y: -8) {
        color(0xFFFFFF).setFill()
        NSBezierPath(roundedRect: lid, xRadius: 48, yRadius: 48).fill()
        NSBezierPath(roundedRect: NSRect(x: 180, y: 304, width: 664, height: 52), xRadius: 26, yRadius: 26).fill()
    }
    let screen = lid.insetBy(dx: 30, dy: 30)
    color(0xFFF6EE).setFill()
    NSBezierPath(roundedRect: screen, xRadius: 22, yRadius: 22).fill()
    color(0xF1C9A8).setFill()
    NSBezierPath(roundedRect: NSRect(x: 452, y: 338, width: 120, height: 14), xRadius: 7, yRadius: 7).fill()

    // Nervous face: worried brows, wide eyes, wobbly mouth.
    let cx = screen.midX, cy = screen.midY
    ink.setFill()
    for side: CGFloat in [-1, 1] {
        let eyeX = cx + side * 100
        NSBezierPath(ovalIn: NSRect(x: eyeX - 30, y: cy + 4, width: 60, height: 72)).fill()
        let brow = NSBezierPath()
        brow.move(to: NSPoint(x: eyeX + side * 46, y: cy + 100))
        brow.line(to: NSPoint(x: eyeX - side * 30, y: cy + 124))
        stroke(brow, 22, ink)
    }
    let mouth = NSBezierPath()
    let y = cy - 74
    mouth.move(to: NSPoint(x: cx - 120, y: y))
    mouth.curve(to: NSPoint(x: cx - 40, y: y), controlPoint1: NSPoint(x: cx - 98, y: y + 36), controlPoint2: NSPoint(x: cx - 62, y: y + 36))
    mouth.curve(to: NSPoint(x: cx + 40, y: y), controlPoint1: NSPoint(x: cx - 18, y: y - 36), controlPoint2: NSPoint(x: cx + 18, y: y - 36))
    mouth.curve(to: NSPoint(x: cx + 120, y: y), controlPoint1: NSPoint(x: cx + 62, y: y + 36), controlPoint2: NSPoint(x: cx + 98, y: y + 36))
    stroke(mouth, 24, ink)

    // A bead of sweat rolling off the top corner of the lid.
    let drop = dropPath(lid.maxX - 18, lid.maxY - 30, 58, 128)
    withShadow(0x7A2A10, 0.35, blur: 14, y: -7) {
        NSGradient(colors: [color(0xA6E6FF), color(0x4FC3FF), color(0x1E9BF0)])!.draw(in: drop, angle: -90)
    }
    color(0xFFFFFF, 0.9).setFill()
    NSBezierPath(ovalIn: NSRect(x: lid.maxX - 18 - 34, y: lid.maxY - 30 - 6, width: 18, height: 30)).fill()
}

func render(side: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(side) / 1024)
    transform.concat()
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for (name, pixels) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                       ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try render(side: pixels).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "\(output)/icon_\(name).png"))
}
if CommandLine.arguments.count > 2 {
    try render(side: 1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
