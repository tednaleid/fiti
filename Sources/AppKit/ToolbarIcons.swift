// ABOUTME: Pure NSImage factories for the toolbar's swatches, glyphs, and color
// ABOUTME: wheel. Stateless, so they live apart from ToolbarController's wiring.

import AppKit

enum ToolbarIcons {
    /// A rounded-rect color swatch image for a quick-pick palette button.
    static func swatch(r: Double, g: Double, b: Double) -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 3, yRadius: 3).fill()
        img.unlockFocus()
        return img
    }

    /// Builds an SF Symbol image. When `withRedX` is true, palette rendering
    /// colors the secondary layer (the slash on `eye.slash` or the X badge on
    /// `clock.badge.xmark`) red while the base symbol keeps the label color.
    static func symbol(named name: String, withRedX: Bool, accessibilityDescription: String?) -> NSImage? {
        if withRedX {
            let config = NSImage.SymbolConfiguration(paletteColors: [.labelColor, .systemRed])
            return NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription)?
                .withSymbolConfiguration(config)
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription)
        image?.isTemplate = true
        return image
    }

    /// A 12-wedge rainbow wheel image for the custom-color button.
    static func colorWheel(diameter: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: diameter, height: diameter))
        img.lockFocus()
        let center = NSPoint(x: diameter / 2, y: diameter / 2)
        let wedges = 12
        for i in 0..<wedges {
            let path = NSBezierPath()
            path.move(to: center)
            path.appendArc(withCenter: center, radius: diameter / 2,
                           startAngle: CGFloat(i) / CGFloat(wedges) * 360,
                           endAngle: CGFloat(i + 1) / CGFloat(wedges) * 360)
            path.close()
            NSColor(hue: CGFloat(i) / CGFloat(wedges), saturation: 0.85, brightness: 0.95, alpha: 1).setFill()
            path.fill()
        }
        img.unlockFocus()
        return img
    }
}
