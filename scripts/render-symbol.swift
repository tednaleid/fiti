#!/usr/bin/env swift
// ABOUTME: Renders an SF Symbol as a black glyph on a white square PNG, scaled
// ABOUTME: to fit. Usage: render-symbol.swift <symbol-name> [output.png] [size]

import AppKit

// --- arguments -------------------------------------------------------------
let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("""
    usage: render-symbol.swift <symbol-name> [output.png] [size] [inset]
      <symbol-name>  an SF Symbol name, e.g. theatermask.and.paintbrush
      [output.png]   output path (default: ./<symbol-name>.png)
      [size]         square edge in pixels (default: 1024)
      [inset]        fraction of the canvas left empty on each side,
                     0.0 = edge-to-edge (default: 0.10)

    """, stderr)
    exit(2)
}
let symbolName = args[1]
let outputPath = args.count >= 3 ? args[2] : "./\(symbolName).png"
let size = args.count >= 4 ? (Int(args[3]) ?? 1024) : 1024
// Fraction of the canvas left empty around the glyph on each side. A little
// breathing room reads better than an edge-to-edge symbol.
let insetFraction = args.count >= 5 ? (Double(args[4]) ?? 0.10) : 0.10

// --- resolve the symbol ----------------------------------------------------
let config = NSImage.SymbolConfiguration(pointSize: CGFloat(size), weight: .regular)
guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil),
      let symbol = base.withSymbolConfiguration(config) else {
    fputs("error: no SF Symbol named '\(symbolName)' on this system\n", stderr)
    exit(1)
}

// Recolor the (template) symbol to solid black, preserving its alpha shape.
func tintedBlack(_ image: NSImage) -> NSImage {
    let out = NSImage(size: image.size)
    out.lockFocus()
    let rect = NSRect(origin: .zero, size: image.size)
    image.draw(in: rect, from: rect, operation: .sourceOver, fraction: 1.0)
    NSColor.black.set()
    rect.fill(using: .sourceAtop)
    out.unlockFocus()
    return out
}
let glyph = tintedBlack(symbol)

// --- compose onto a white square -------------------------------------------
let px = size
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
    fputs("error: could not allocate \(px)x\(px) bitmap\n", stderr)
    exit(1)
}
rep.size = NSSize(width: px, height: px)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

NSColor.white.setFill()
NSRect(x: 0, y: 0, width: px, height: px).fill()

// Aspect-fit the glyph into the inset square, centered.
let available = CGFloat(px) * (1 - 2 * insetFraction)
let s = glyph.size
let scale = min(available / s.width, available / s.height)
let w = s.width * scale
let h = s.height * scale
let drawRect = NSRect(x: (CGFloat(px) - w) / 2, y: (CGFloat(px) - h) / 2, width: w, height: h)
glyph.draw(in: drawRect, from: NSRect(origin: .zero, size: s), operation: .sourceOver, fraction: 1.0)

NSGraphicsContext.restoreGraphicsState()

// --- write -----------------------------------------------------------------
guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("error: PNG encoding failed\n", stderr)
    exit(1)
}
let url = URL(fileURLWithPath: outputPath)
do {
    try png.write(to: url)
} catch {
    fputs("error: could not write \(outputPath): \(error.localizedDescription)\n", stderr)
    exit(1)
}
print("wrote \(px)x\(px) -> \(outputPath)")
