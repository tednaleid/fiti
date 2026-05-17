// ABOUTME: Adapts fiti's StrokePoint to PerfectFreehand's StrokeInputPoint
// ABOUTME: protocol via a thin wrapper. Pressure is nil — simulatePressure
// ABOUTME: synthesizes velocity-derived pressure at the algorithm layer.

import PerfectFreehand

/// Adapter that bridges fiti's `StrokePoint` (with a non-optional `Double`
/// pressure field defaulting to 0.5 for mouse input) to perfect-freehand's
/// `StrokeInputPoint` protocol (which expects an optional `Double?`).
///
/// `pressure` is nil here on purpose: `simulatePressure: true` in
/// `FitiStrokeOptions` synthesizes a velocity-derived pressure at the
/// algorithm layer, which produces better-looking tapers than the model's
/// uniform 0.5. If/when real stylus pressure flows in, this adapter can
/// forward `point.pressure` instead.
public struct PerfectFreehandInput: StrokeInputPoint {
    public let x: Double
    public let y: Double
    public let pressure: Double? = nil

    public init(_ point: StrokePoint) {
        self.x = point.x
        self.y = point.y
    }
}

public extension Array where Element == StrokePoint {
    /// Map fiti's stroke points into perfect-freehand's input shape.
    var perfectFreehandInputs: [PerfectFreehandInput] {
        map(PerfectFreehandInput.init)
    }
}
