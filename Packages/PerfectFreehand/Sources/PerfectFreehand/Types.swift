// ABOUTME: Ported from perfect-freehand@1.2.3/types.ts (MIT, Steve Ruiz).
// ABOUTME: Public types — StrokeOptions, TaperOptions, TaperValue, Point2D, StrokeInputPoint.

import Foundation

/// A 2D point in the algorithm's output polygon. Mirrors TS `Vec2 = [number, number]`.
public struct Point2D: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// Input-point protocol consumed by `getStroke`. Mirrors the TS shape
/// `{ x: number, y: number, pressure?: number }`.
public protocol StrokeInputPoint {
    var x: Double { get }
    var y: Double { get }
    var pressure: Double? { get }
}

/// Taper value for `start.taper` and `end.taper`. Mirrors TS's
/// `number | boolean | undefined`:
/// - `.none` ↔ TS `false` / `undefined` (no taper, distance = 0)
/// - `.auto` ↔ TS `true` (taper the full length: `max(size, totalLength)`)
/// - `.length(n)` ↔ TS `number` (use that exact taper distance)
public enum TaperValue: Sendable, Equatable {
    case none
    case auto
    case length(Double)
}

/// Per-end cap, taper, and easing options. Mirrors TS's `start` / `end` shape.
///
/// Defaults follow TS's destructuring in `getStrokeOutlinePoints.ts`:
/// when `start` / `end` are omitted entirely (TS `start = {}`), the inner
/// fields fall back to `cap = true`, no taper, and end-specific easings
/// (`t => t * (2 - t)` for start, `t => --t * t * t + 1` for end).
///
/// The Swift default `easing = nil` means "use the algorithm's built-in
/// per-end easing"; consumers pass a custom closure to override.
public struct TaperOptions: Sendable {
    public var taper: TaperValue
    public var cap: Bool
    public var easing: (@Sendable (Double) -> Double)?

    public init(
        taper: TaperValue = .none,
        cap: Bool = true,
        easing: (@Sendable (Double) -> Double)? = nil
    ) {
        self.taper = taper
        self.cap = cap
        self.easing = easing
    }
}

/// Options for `getStroke`. Mirrors TS's `StrokeOptions` interface.
///
/// Default values come from TS's `getStrokeOutlinePoints.ts` destructuring
/// (the authoritative source — the TS interface itself doesn't carry defaults):
/// `size = 16`, `thinning = 0.5`, `smoothing = 0.5`, `streamline = 0.5`,
/// `simulatePressure = true`, `easing = (t) => t` (linear), `last = false`.
///
/// `easing = nil` here means "use linear" — the algorithm layer treats nil
/// as the identity function, matching TS's `(t) => t` default.
public struct StrokeOptions: Sendable {
    public var size: Double
    public var thinning: Double
    public var smoothing: Double
    public var streamline: Double
    public var simulatePressure: Bool
    public var easing: (@Sendable (Double) -> Double)?
    public var start: TaperOptions
    public var end: TaperOptions
    public var last: Bool

    public init(
        size: Double = 16,
        thinning: Double = 0.5,
        smoothing: Double = 0.5,
        streamline: Double = 0.5,
        simulatePressure: Bool = true,
        easing: (@Sendable (Double) -> Double)? = nil,
        start: TaperOptions = TaperOptions(),
        end: TaperOptions = TaperOptions(),
        last: Bool = false
    ) {
        self.size = size
        self.thinning = thinning
        self.smoothing = smoothing
        self.streamline = streamline
        self.simulatePressure = simulatePressure
        self.easing = easing
        self.start = start
        self.end = end
        self.last = last
    }
}
