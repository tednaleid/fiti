// ABOUTME: Data records describing how to reverse a mutation.
// ABOUTME: Editor.applyInverse consumes one and produces the paired inverse.

import Foundation

public struct StrokeRestoreEntry: Equatable, Sendable {
    public let snapshot: Stroke
    public let atIndex: Int

    public init(snapshot: Stroke, atIndex: Int) {
        self.snapshot = snapshot
        self.atIndex = atIndex
    }
}

public struct TransformEntry: Equatable, Sendable {
    public let strokeId: StrokeId
    public let transform: Transform

    public init(strokeId: StrokeId, transform: Transform) {
        self.strokeId = strokeId
        self.transform = transform
    }
}

public enum InverseOp: Equatable, Sendable {
    case deleteStroke(StrokeId)
    case restoreStroke(snapshot: Stroke, atIndex: Int)
    case deleteStrokes([StrokeId])
    case restoreStrokes(entries: [StrokeRestoreEntry])
    case setTransforms(entries: [TransformEntry])
}
