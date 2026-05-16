// ABOUTME: The drawing document — keyed-map of strokes plus an ordered list.
// ABOUTME: Scratch-style: map for identity, list for z-order. CRDT-friendly.

import Foundation

public struct FitiDoc: Equatable, Codable, Sendable {
    public var strokes: [StrokeId: Stroke]
    public var strokeOrder: [StrokeId]

    public init(strokes: [StrokeId: Stroke] = [:], strokeOrder: [StrokeId] = []) {
        self.strokes = strokes
        self.strokeOrder = strokeOrder
    }

    public static let empty = FitiDoc()
}
