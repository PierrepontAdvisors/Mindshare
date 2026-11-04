// Draws the brain-in-a-chip icon. Run: swift Scripts/make-icons.swift Assets
// Hand-drawn rather than built from SF Symbols, whose licence excludes app icons.
import AppKit

private typealias Lobe = (x: CGFloat, y: CGFloat, r: CGFloat)

private let detailedLobes: [Lobe] = [
    (0.36, 0.56, 0.42), (0.66, 0.22, 0.36), (0.62, -0.24, 0.38), (0.32, -0.58, 0.40), (0.28, 0, 0.50),
]

// Fewer, deeper bumps survive at small icon sizes, where fine lobes blur into a circle.
private let boldLobes: [Lobe] = [
    (0.42, 0.56, 0.46), (0.74, 0, 0.36), (0.42, -0.56, 0.46), (0.28, 0, 0.42),
]

/// Two hemispheres of overlapping circles with a centre split.
private func drawBrain(_ ctx: CGContext, at c: CGPoint, radius r: CGFloat, brainColor: CGColor, chipColor: CGColor, folds: Bool) {
    let lobes = folds ? detailedLobes : boldLobes
    ctx.setFillColor(brainColor)
    for side in [-1.0, 1.0] as [CGFloat] {
        for lobe in lobes {
            let radius = lobe.r * r
            ctx.fillEllipse(in: CGRect(x: c.x + side * lobe.x * r - radius, y: c.y + lobe.y * r - radius, width: radius * 2, height: radius * 2))
        }
    }

    ctx.setStrokeColor(chipColor)
    ctx.setLineCap(.round)
    ctx.setLineWidth(r * (folds ? 0.085 : 0.16))
    ctx.move(to: CGPoint(x: c.x, y: c.y + r * 0.98))
    ctx.addLine(to: CGPoint(x: c.x, y: c.y - r * 0.98))
    ctx.strokePath()
    guard folds else { return }
    // Folds branch from the centre line; free-floating arcs read as a face.
    for side in [-1.0, 1.0] as [CGFloat] {
        ctx.move(to: CGPoint(x: c.x, y: c.y + r * 0.36))
        ctx.addQuadCurve(to: CGPoint(x: c.x + side * r * 0.58, y: c.y + r * 0.56),
                         control: CGPoint(x: c.x + side * r * 0.34, y: c.y + r * 0.30))
        ctx.move(to: CGPoint(x: c.x, y: c.y - r * 0.08))
        ctx.addQuadCurve(to: CGPoint(x: c.x + side * r * 0.76, y: c.y + r * 0.04),
                         control: CGPoint(x: c.x + side * r * 0.40, y: c.y - r * 0.16))
        ctx.move(to: CGPoint(x: c.x, y: c.y - r * 0.50))
        ctx.addQuadCurve(to: CGPoint(x: c.x + side * r * 0.56, y: c.y - r * 0.50),
                         control: CGPoint(x: c.x + side * r * 0.30, y: c.y - r * 0.60))
        ctx.strokePath()
    }
}

/// A rounded square with three pins per side.
private func drawChip(_ ctx: CGContext, at c: CGPoint, side: CGFloat, corner: CGFloat, pinLength: CGFloat, pinWidth: CGFloat, color: CGColor) {
    ctx.setFillColor(color)
    let body = CGRect(x: c.x - side / 2, y: c.y - side / 2, width: side, height: side)
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil))
    ctx.fillPath()
    let spacing = side * 0.28
    for i in -1...1 {
        let offset = CGFloat(i) * spacing
        let reach = side / 2 + pinLength
        let pins = [
            CGRect(x: c.x + offset - pinWidth / 2, y: c.y + side / 2 - 1, width: pinWidth, height: pinLength + 1),
            CGRect(x: c.x + offset - pinWidth / 2, y: c.y - reach, width: pinWidth, height: pinLength + 1),
            CGRect(x: c.x - reach, y: c.y + offset - pinWidth / 2, width: pinLength + 1, height: pinWidth),
            CGRect(x: c.x + side / 2 - 1, y: c.y + offset - pinWidth / 2, width: pinLength + 1, height: pinWidth),
        ]
        for pin in pins {
            ctx.addPath(CGPath(roundedRect: pin, cornerWidth: pinWidth * 0.3, cornerHeight: pinWidth * 0.3, transform: nil))
            ctx.fillPath()
        }
    }
}

private func render(size: Int, to url: URL, draw: (CGContext, CGFloat) -> Void) throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
    draw(ctx, CGFloat(size))
    guard let image = ctx.makeImage(),
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try data.write(to: url)
}

private func drawAppIcon(_ ctx: CGContext, _ s: CGFloat) {
    let background = CGColor(srgbRed: 0.09, green: 0.10, blue: 0.12, alpha: 1)
    let chip = CGColor(srgbRed: 0.95, green: 0.96, blue: 0.97, alpha: 1)
    let inset = s * 0.098
    let tile = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: s * 0.18, cornerHeight: s * 0.18, transform: nil))
    ctx.setFillColor(background)
    ctx.fillPath()
    let center = CGPoint(x: s / 2, y: s / 2)
    drawChip(ctx, at: center, side: s * 0.50, corner: s * 0.07, pinLength: s * 0.065, pinWidth: s * 0.042, color: chip)
    drawBrain(ctx, at: center, radius: s * 0.178, brainColor: background, chipColor: chip, folds: s >= 128)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconset = output.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(size: size, to: iconset.appendingPathComponent("icon_\(size)x\(size).png"), draw: drawAppIcon)
    try render(size: size * 2, to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"), draw: drawAppIcon)
}
