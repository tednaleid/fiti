// ABOUTME: Where a stroke's input came from. Drives perfect-freehand's
// ABOUTME: simulatePressure decision when we port that algorithm later.

import Foundation

public enum PointerType: String, Equatable, Codable, Sendable {
    case mouse, pen, touch
}
