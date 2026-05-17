// ABOUTME: Ported from perfect-freehand@1.2.3/simulatePressure.ts (MIT, Steve Ruiz).
// ABOUTME: Velocity-to-pressure synthesis for non-stylus input.

import Foundation

/// Simulate pressure based on the distance between points and stroke size.
/// Creates a natural-looking pressure effect based on drawing velocity.
///
/// - Parameters:
///   - prevPressure: The previous pressure value.
///   - distance: The distance from the previous point.
///   - size: The base stroke size.
/// - Returns: The simulated pressure value (0...1).
func simulatePressure(prevPressure: Double, distance: Double, size: Double) -> Double {
    // Speed of change - how fast should the pressure be changing?
    let sp = min(1, distance / size)
    // Rate of change - how much of a change is there?
    let rp = min(1, 1 - sp)
    // Accelerate the pressure
    return min(
        1,
        prevPressure + (rp - prevPressure) * (sp * PFConstants.RATE_OF_PRESSURE_CHANGE)
    )
}
