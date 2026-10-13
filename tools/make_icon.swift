import AppKit

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let scale = CGFloat(size) / 1024
    ctx.scaleBy(x: scale, y: scale)

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 184, yRadius: 184)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor.black.withAlphaComponent(0.32).cgColor)
    NSColor.black.setFill()
    squircle.fill()
    ctx.restoreGState()

    ctx.saveGState()
    squircle.addClip()
    let gradient = NSGradient(colors: [NSColor(srgbRed: 0.33, green: 0.31, blue: 0.95, alpha: 1),
                                       NSColor(srgbRed: 0.06, green: 0.74, blue: 0.72, alpha: 1)])!
    gradient.draw(from: CGPoint(x: body.minX, y: body.maxY), to: CGPoint(x: body.maxX, y: body.minY), options: [])

    let tileY: CGFloat = 282
    let tileH: CGFloat = 460
    let tiles: [(x: CGFloat, w: CGFloat, alpha: CGFloat)] = [(22, 300, 0.42), (362, 300, 1), (702, 300, 0.42)]
    for tile in tiles {
        let rect = CGRect(x: tile.x, y: tileY, width: tile.w, height: tileH)
        let path = NSBezierPath(roundedRect: rect, xRadius: 58, yRadius: 58)
        ctx.saveGState()
        if tile.alpha == 1 {
            ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: NSColor.black.withAlphaComponent(0.28).cgColor)
        }
        NSColor.white.withAlphaComponent(tile.alpha).setFill()
        path.fill()
        ctx.restoreGState()

        ctx.saveGState()
        path.addClip()
        NSColor(srgbRed: 0.33, green: 0.31, blue: 0.95, alpha: 0.16 * tile.alpha).setFill()
        CGRect(x: rect.minX, y: rect.maxY - 84, width: rect.width, height: 84).fill()
        ctx.restoreGState()
    }
    ctx.restoreGState()

    ctx.saveGState()
    squircle.addClip()
    let sheen = NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
    sheen.draw(in: CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let variants: [(String, Int)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                                 ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
for (name, px) in variants {
    try render(size: px).write(to: out.appendingPathComponent("icon_\(name).png"))
}
