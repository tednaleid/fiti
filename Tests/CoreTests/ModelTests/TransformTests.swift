// ABOUTME: Tests for Transform, Size, PointerType — the small model types.

import Foundation
import Testing

@Suite("Transform")
struct TransformTests {
    @Test("identity is x=0,y=0,scale=1,rotate=0")
    func identity() {
        let t = Transform.identity
        #expect(t.x == 0)
        #expect(t.y == 0)
        #expect(t.scale == 1)
        #expect(t.rotate == 0)
    }
}

@Suite("Size")
struct SizeTests {
    @Test("constructs with width and height")
    func construct() {
        let s = Size(width: 100, height: 200)
        #expect(s.width == 100)
        #expect(s.height == 200)
    }
}

@Suite("PointerType")
struct PointerTypeTests {
    @Test("encodes as lowercased string")
    func encoding() throws {
        let data = try JSONEncoder().encode(PointerType.mouse)
        #expect(String(data: data, encoding: .utf8) == "\"mouse\"")
    }
}
