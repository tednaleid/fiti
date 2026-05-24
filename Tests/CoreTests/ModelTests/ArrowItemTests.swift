// ABOUTME: ArrowItem value-type tests: construction, Codable round-trip, equality.
// ABOUTME: Pure Core, no AppKit.

import Foundation
import Testing

@Suite struct ArrowItemTests {
    private func sample() -> ArrowItem {
        ArrowItem(id: "arrow-1", color: RGBA(r: 1, g: 0, b: 0, a: 0.5), width: 8,
                  transform: .identity, tail: Point(x: 0, y: 0), head: Point(x: 100, y: 0),
                  createdAt: 12.0)
    }

    @Test func storesEndpointsAndStyle() {
        let a = sample()
        #expect(a.tail == Point(x: 0, y: 0))
        #expect(a.head == Point(x: 100, y: 0))
        #expect(a.width == 8)
        #expect(a.color.a == 0.5)
    }

    @Test func codableRoundTrips() throws {
        let a = sample()
        let data = try JSONEncoder().encode(a)
        let back = try JSONDecoder().decode(ArrowItem.self, from: data)
        #expect(back == a)
    }
}
