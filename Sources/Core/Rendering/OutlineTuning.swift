// ABOUTME: Hand-tuned constants for the outline/halo look (per-type halo weight,
// ABOUTME: luminance split). Not exposed in the UI; tweak here and rebuild.

public enum OutlineTuning {
    /// Pen halo line width as a fraction of stroke width (points).
    public static let strokeWidthFactor: Double = 0.4
    /// Arrow halo line width as a fraction of arrow width (points), heavier than the
    /// pen so the outline reads solid on arrows, floored so thin arrows aren't wispy.
    public static let arrowWidthFactor: Double = 0.62
    public static let arrowMinHaloWidth: Double = 6.0
    /// Text halo width (points) by font-size band: the border reads chunky at large
    /// sizes and stays readable at small ones, stepping rather than scaling smoothly.
    /// The first band whose `maxFontSize` is not exceeded wins; above the last band the
    /// largest width is used. On a 2x display the width is roughly its value in device
    /// pixels. fontSize = width slider * 4, so these bands span the full slider range.
    public static let textHaloSteps: [(maxFontSize: Double, width: Double)] = [
        (48, 5),
        (96, 8),
        (160, 12)
    ]
    /// Below this Rec.601 luminance the halo is light (white), at/above it dark (black).
    public static let luminanceThreshold: Double = 0.5
}
