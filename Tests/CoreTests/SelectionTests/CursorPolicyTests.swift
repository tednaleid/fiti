// ABOUTME: Tests for cursorFor — region → SystemCursor, including corner
// ABOUTME: angle bucketing that tracks the box rotation.

import Testing

@Suite("cursorFor")
struct CursorPolicyTests {
    @Test("rotate handle, body, and outside map to fixed cursors")
    func fixedRegions() {
        #expect(cursorFor(region: .rotateHandle, boxRotation: 0, dragging: false) == .rotate)
        #expect(cursorFor(region: .body, boxRotation: 0, dragging: false) == .openHand)
        #expect(cursorFor(region: .body, boxRotation: 0, dragging: true) == .closedHand)
        #expect(cursorFor(region: .outside, boxRotation: 0, dragging: false) == .crosshair)
    }

    @Test("at rotation 0, topLeft/bottomRight bucket to 135°, topRight/bottomLeft to 45°")
    func cornerBucketsUnrotated() {
        #expect(cursorFor(region: .corner(.topLeft), boxRotation: 0, dragging: false) == .resize(angle: 135))
        #expect(cursorFor(region: .corner(.bottomRight), boxRotation: 0, dragging: false) == .resize(angle: 135))
        #expect(cursorFor(region: .corner(.topRight), boxRotation: 0, dragging: false) == .resize(angle: 45))
        #expect(cursorFor(region: .corner(.bottomLeft), boxRotation: 0, dragging: false) == .resize(angle: 45))
    }

    @Test("rotating the box 45° rebuckets the corner cursor (135 + 45 = 180 ≡ 0, horizontal)")
    func cornerBucketsRotated() {
        #expect(cursorFor(region: .corner(.topLeft), boxRotation: 45, dragging: false) == .resize(angle: 0))
    }
}
