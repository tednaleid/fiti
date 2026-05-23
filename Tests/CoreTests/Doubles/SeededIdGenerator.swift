// ABOUTME: Counter-based IdGenerator for deterministic test ids.
// ABOUTME: Returns "{prefix}-1", "{prefix}-2", ...

import Foundation

public final class SeededIdGenerator: IdGenerator, @unchecked Sendable {
    private let prefix: String
    private var counter: Int = 0

    public init(prefix: String = "stroke") {
        self.prefix = prefix
    }

    public func newItemId() -> ItemId {
        counter += 1
        return "\(prefix)-\(counter)"
    }
}
