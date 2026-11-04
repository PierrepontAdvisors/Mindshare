import AppKit
import MemoryCore

private let imageSize = NSSize(width: 18, height: 18)
private let pieDiameter: CGFloat = 14
private let warningPointSize: CGFloat = 14

/// A small pie while things are OK, and the panel's warning shapes when they aren't, so state never relies on colour alone.
/// Not a template image, because template images lose their colour. It draws on demand, so the pie's track
/// follows the menu bar's light or dark appearance.
func menuBarImage(_ status: MenuBarStatus) -> NSImage {
    let image = NSImage(size: imageSize, flipped: false) { bounds in
        switch status.state {
        case .normal: drawPie(in: bounds, level: status.level, color: .systemGreen)
        case .unknown: drawPie(in: bounds, level: status.level, color: .secondaryLabelColor)
        case .warning: drawSymbol("exclamationmark.triangle.fill", in: bounds, color: .systemOrange)
        case .critical: drawSymbol("xmark.octagon.fill", in: bounds, color: .systemRed)
        }
        return true
    }
    image.isTemplate = false
    return image
}

private func drawPie(in bounds: NSRect, level: Int, color: NSColor) {
    let center = NSPoint(x: bounds.midX, y: bounds.midY)
    let radius = pieDiameter / 2
    let circle = NSRect(x: center.x - radius, y: center.y - radius, width: pieDiameter, height: pieDiameter)
    NSColor.labelColor.withAlphaComponent(0.25).setFill()
    NSBezierPath(ovalIn: circle).fill()

    color.setFill()
    guard level < menuBarLevels else {
        NSBezierPath(ovalIn: circle).fill()
        return
    }
    let slice = NSBezierPath()
    slice.move(to: center)
    // Starts at 12 o'clock and fills clockwise, like the footer pie.
    let sweep = 360 * CGFloat(level) / CGFloat(menuBarLevels)
    slice.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - sweep, clockwise: true)
    slice.close()
    slice.fill()
}

private func drawSymbol(_ name: String, in bounds: NSRect, color: NSColor) {
    let configuration = NSImage.SymbolConfiguration(pointSize: warningPointSize, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white, color]))
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) else {
        NSLog("Mindshare: missing symbol %@", name)
        return
    }
    let origin = NSPoint(x: bounds.midX - symbol.size.width / 2, y: bounds.midY - symbol.size.height / 2)
    symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
}
