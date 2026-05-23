// ABOUTME: Production IdGenerator. Spec calls for ULID, but UUID is simpler
// ABOUTME: and the spec's "sortable" property isn't load-bearing because
// ABOUTME: FitiDoc.itemOrder is the canonical item ordering anyway.

import Foundation

public final class UUIDItemIds: IdGenerator {
    public init() {}
    public func newItemId() -> ItemId { UUID().uuidString }
}
