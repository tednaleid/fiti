// ABOUTME: Hand-tuned constants for the outline/halo look (per-type halo weight,
// ABOUTME: luminance split). Not exposed in the UI; tweak here and rebuild.

public enum OutlineTuning {
    /// Halo line width as a fraction of stroke/arrow width (points).
    public static let strokeWidthFactor: Double = 0.5
    /// Halo weight for text as a fraction of font size; becomes the negative
    /// NSAttributedString strokeWidth percentage (textWidthFactor * 100).
    public static let textWidthFactor: Double = 0.06
    /// Below this Rec.601 luminance the halo is light (white), at/above it dark (black).
    public static let luminanceThreshold: Double = 0.5
}
