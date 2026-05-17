// ABOUTME: Ported from perfect-freehand@1.2.3/constants.ts (MIT, Steve Ruiz).
// ABOUTME: Numeric constants used by the algorithm.

import Foundation

/// Constants used throughout the stroke generation algorithm.
enum PFConstants {
    /// Rate of change for simulated pressure.
    /// Controls how quickly pressure changes based on drawing velocity.
    /// Higher values make pressure more responsive to speed changes.
    static let RATE_OF_PRESSURE_CHANGE: Double = 0.275

    /// PI with a tiny offset to fix browser rendering artifacts.
    /// Some browsers render strokes incorrectly when using exact PI.
    static let FIXED_PI: Double = .pi + 0.0001

    /// Number of segments for rounded start caps.
    static let START_CAP_SEGMENTS: Int = 13

    /// Number of segments for rounded end caps.
    /// Higher than start caps for smoother appearance at stroke endings.
    static let END_CAP_SEGMENTS: Int = 29

    /// Number of segments for sharp corner caps.
    static let CORNER_CAP_SEGMENTS: Int = 13

    /// Pixels to skip at the end of a stroke to reduce noise.
    static let END_NOISE_THRESHOLD: Double = 3

    /// Minimum interpolation factor for streamline.
    /// Used when streamline is at maximum (1.0).
    static let MIN_STREAMLINE_T: Double = 0.15

    /// Range for interpolation factor calculation.
    /// Added to MIN_STREAMLINE_T based on (1 - streamline).
    static let STREAMLINE_T_RANGE: Double = 0.85

    /// Minimum stroke radius to prevent invisible strokes.
    static let MIN_RADIUS: Double = 0.01

    /// Default pressure for the first point of a stroke.
    /// Lower than subsequent points to prevent fat starts,
    /// since drawn lines almost always start slow.
    static let DEFAULT_FIRST_PRESSURE: Double = 0.25

    /// Default pressure for subsequent points when no pressure is provided.
    static let DEFAULT_PRESSURE: Double = 0.5

    /// Unit offset vector used as placeholder for initial vector
    /// and for creating a second point when only one point is provided.
    static let UNIT_OFFSET: [Double] = [1, 1]
}
