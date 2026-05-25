// ABOUTME: SnapshotRenderer renders the outline halo when asked, so /snapshot.png
// ABOUTME: stays in parity with CanvasView's on-screen outline rendering.

import AppKit
import Testing

@MainActor
@Suite("SnapshotRenderer outline")
struct SnapshotRendererOutlineTests {
    @Test("outline snapshot differs from the plain snapshot")
    func differs() {
        let stroke = Stroke(id: "a", color: RGBA(r: 0.5, g: 0.1, b: 0.1, a: 1), width: 40,
                            transform: .identity,
                            points: [StrokePoint(x: 20, y: 50), StrokePoint(x: 180, y: 50)],
                            pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        let frame = RenderFrame(items: [.stroke(stroke)], inProgress: nil,
                                canvasSize: Size(width: 200, height: 100))
        let plain = SnapshotRenderer.png(from: frame, outline: .none)
        let haloed = SnapshotRenderer.png(from: frame,
                                          outline: OutlineFlags(text: false, arrow: false, pen: true))
        #expect(plain != nil && haloed != nil)
        #expect(plain != haloed)
    }
}
