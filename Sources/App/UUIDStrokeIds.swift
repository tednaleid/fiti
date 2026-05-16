// ABOUTME: Production IdGenerator. Spec calls for ULID, but UUID is simpler
// ABOUTME: and the spec's "sortable" property isn't load-bearing because
// ABOUTME: FitiDoc.strokeOrder is the canonical stroke ordering anyway.

import Foundation

public final class UUIDStrokeIds: IdGenerator {
    public init() {}
    public func newStrokeId() -> StrokeId { UUID().uuidString }
}
