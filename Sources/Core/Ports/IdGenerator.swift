// ABOUTME: Stroke-id factory port. Production uses UUID-backed ids
// ABOUTME: (Sources/App); tests use SeededIdGenerator for determinism.

import Foundation

public protocol IdGenerator: AnyObject, Sendable {
    func newStrokeId() -> StrokeId
}
