// ABOUTME: Pure outline policy: resolves the contrast halo color (by luminance)
// ABOUTME: and halo width for a mark. No AppKit; the rendering layer consumes this.

public struct ResolvedOutline: Equatable {
    public let haloColor: RGBA
    public let haloWidth: Double   // points
    public init(haloColor: RGBA, haloWidth: Double) {
        self.haloColor = haloColor
        self.haloWidth = haloWidth
    }
}

/// Returns nil when disabled. Otherwise the halo color is the luminance-contrast
/// of `color` (white on dark, black on light) preserving alpha, and the halo
/// width is `width` in points.
public func resolveOutline(enabled: Bool, color: RGBA, width: Double) -> ResolvedOutline? {
    guard enabled else { return nil }
    let luminance = 0.299 * color.r + 0.587 * color.g + 0.114 * color.b
    let halo: RGBA = luminance < OutlineTuning.luminanceThreshold
        ? RGBA(r: 1, g: 1, b: 1, a: color.a)
        : RGBA(r: 0, g: 0, b: 0, a: color.a)
    return ResolvedOutline(haloColor: halo, haloWidth: width)
}

/// Proportional-width convenience for strokes and arrows: `sizeBasis * widthFactor`
/// in points, floored at `minWidth` so a thin halo on a small mark stays readable.
public func resolveOutline(enabled: Bool, color: RGBA, sizeBasis: Double,
                           widthFactor: Double, minWidth: Double = 0) -> ResolvedOutline? {
    resolveOutline(enabled: enabled, color: color, width: max(sizeBasis * widthFactor, minWidth))
}

/// Stepped halo width (points) for text by font-size band: chunkier at large sizes,
/// with a readable floor at small ones. The first band whose `maxFontSize` is not
/// exceeded wins; above the last band the largest width is used. See
/// `OutlineTuning.textHaloSteps`. (fontSize = width slider * 4.)
public func textHaloWidth(forFontSize fontSize: Double) -> Double {
    for step in OutlineTuning.textHaloSteps where fontSize <= step.maxFontSize {
        return step.width
    }
    return OutlineTuning.textHaloSteps.last?.width ?? 6
}
