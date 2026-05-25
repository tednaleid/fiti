// ABOUTME: Smoke tests that CursorRenderer maps every SystemCursor to a
// ABOUTME: non-nil NSCursor (including the private-selector diagonal fallback).

import AppKit
import Testing

@Suite("CursorRenderer mapping")
@MainActor
struct CursorRendererTests {
    @Test("every SystemCursor resolves to a non-nil NSCursor")
    func allResolve() {
        let view = CanvasInputView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let renderer = CursorRenderer(view: view)
        let cursors: [SystemCursor] = [
            .arrow, .openHand, .closedHand, .rotate, .iBeam, .crosshair,
            .resize(angle: 0), .resize(angle: 45), .resize(angle: 90), .resize(angle: 135)
        ]
        for sc in cursors {
            #expect(renderer.nsCursor(for: sc) != nil)
        }
    }
}
