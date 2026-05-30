// ABOUTME: Pure size/opacity preset values plus next/previous stepping.
// ABOUTME: Backs the toolbar pickers and the keyboard size/opacity shortcuts.

import Foundation

public enum ValuePresets {
    /// Stroke/arrow width presets in points. The text tool derives font size from
    /// width via `textFontSize(forWidth:)` (the small presets are width * 4).
    public static let sizes: [Double] = [2, 4, 6, 9, 14, 20, 30, 45, 70, 100]
    /// Opacity presets, 10%...100%.
    public static let opacities: [Double] = [0.1, 0.2, 0.3, 0.4, 0.5,
                                            0.6, 0.7, 0.8, 0.9, 1.0]
}

/// Font size (points) for text drawn at stroke-width `width`. The small/mid widths
/// track `width * 4` so the first presets feel 1:1 with the slider; above the knee the
/// curve flattens so the largest preset tops out near 300pt instead of ballooning to
/// 400. The typed text and the toolbar preview share this, so the preview is honest.
public func textFontSize(forWidth width: Double) -> Double {
    let knee = 14.0, topWidth = 100.0, topFont = 300.0
    guard width > knee else { return width * 4 }
    let kneeFont = knee * 4
    let t = min((width - knee) / (topWidth - knee), 1)
    return kneeFont + t * (topFont - kneeFont)
}

/// First preset strictly greater than `value`; the largest preset when none is
/// greater (empty list -> `value`). Presets must be ascending.
public func nextPreset(after value: Double, in presets: [Double]) -> Double {
    presets.first(where: { $0 > value }) ?? presets.last ?? value
}

/// Last preset strictly less than `value`; the smallest preset when none is
/// less (empty list -> `value`). Presets must be ascending.
public func previousPreset(before value: Double, in presets: [Double]) -> Double {
    presets.last(where: { $0 < value }) ?? presets.first ?? value
}
