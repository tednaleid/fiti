// ABOUTME: Pure size/opacity preset values plus next/previous stepping.
// ABOUTME: Backs the toolbar pickers and the keyboard size/opacity shortcuts.

import Foundation

public enum ValuePresets {
    /// Stroke/arrow width presets in points. The text tool derives font size as
    /// width * 4, so these map to font sizes 8...400 (the smallest is an 8pt font).
    public static let sizes: [Double] = [2, 4, 6, 9, 14, 20, 30, 45, 70, 100]
    /// Opacity presets, 10%...100%.
    public static let opacities: [Double] = [0.1, 0.2, 0.3, 0.4, 0.5,
                                            0.6, 0.7, 0.8, 0.9, 1.0]
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
