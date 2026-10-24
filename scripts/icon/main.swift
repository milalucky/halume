// Renders HaluMe's app icon set: the Halu ring in brand orange on a warm dark squircle.
// Usage: swift scripts/icon/main.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    // macOS icon grid: 824/1024 body with a soft shadow margin.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = CGPath(roundedRect: body, cornerWidth: body.width * 0.225, cornerHeight: body.width * 0.225, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(path)
    ctx.setFillColor(NSColor(red: 0.11, green: 0.10, blue: 0.10, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    // Warm glow from the top left, like the app's backdrop.
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [NSColor(red: 1, green: 0.58, blue: 0.24, alpha: 0.32).cgColor,
                                   NSColor(red: 1, green: 0.58, blue: 0.24, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: body.minX + body.width * 0.3, y: body.maxY), startRadius: 0,
                           endCenter: CGPoint(x: body.minX + body.width * 0.3, y: body.maxY), endRadius: body.width * 0.9, options: [])
    ctx.restoreGState()
    // The Halu mark: an open ring with a dot in its gap (same geometry as HaluMark).
    let size = body.width * 0.52
    let stroke = size * 0.15, dot = size * 0.21, radius = (size - stroke) / 2
    let center = CGPoint(x: body.midX, y: body.midY)
    let orange = NSColor(red: 1, green: 0.58, blue: 0.24, alpha: 1).cgColor
    ctx.setStrokeColor(orange)
    ctx.setLineWidth(stroke)
    ctx.setLineCap(.round)
    // Flipped y: angles mirror the SwiftUI version.
    ctx.addArc(center: center, radius: radius, startAngle: 0.264 * 2 * .pi, endAngle: 0.958 * 2 * .pi, clockwise: false)
    ctx.strokePath()
    let angle = 0.11 * 2 * CGFloat.pi, orbit = radius * 0.98
    let p = CGPoint(x: center.x + orbit * cos(angle), y: center.y + orbit * sin(angle))
    ctx.setFillColor(orange)
    ctx.fillEllipse(in: CGRect(x: p.x - dot / 2, y: p.y - dot / 2, width: dot, height: dot))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: out.appending(path: "icon_\(base)x\(base).png"))
    try render(base * 2).write(to: out.appending(path: "icon_\(base)x\(base)@2x.png"))
}
