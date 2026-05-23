// ABOUTME: Tests for SelectionTransforms — translate / resize / rotate gesture
// ABOUTME: math returning (OrientedBox, per-stroke transforms) from one delta.

import Testing

@Suite("SelectionTransforms")
struct SelectionTransformsTests {
    private func approx(_ a: Double, _ b: Double, _ eps: Double = 1e-6) -> Bool { abs(a - b) <= eps }
    private let box = OrientedBox(center: Point(x: 100, y: 100), size: Size(width: 40, height: 20), rotation: 0)

    @Test("translate shifts the box center and every stroke transform by the delta")
    func translate() {
        let starts: [ItemId: Transform] = ["a": .identity, "b": Transform(x: 5, y: 5, scale: 1, rotate: 0)]
        let (b, t) = SelectionTransforms.translate(startBox: box, startTransforms: starts, dx: 10, dy: -4)
        #expect(approx(b.center.x, 110) && approx(b.center.y, 96))
        #expect(approx(t["a"]!.x, 10) && approx(t["a"]!.y, -4))
        #expect(approx(t["b"]!.x, 15) && approx(t["b"]!.y, 1))
    }

    @Test("resize scales uniformly with the opposite corner pinned")
    func resize() {
        // Box corners: TL(80,90) BR(120,110). Drag BR with anchor=TL.
        let drag = ResizeDrag(anchor: Point(x: 80, y: 90),
                              startCorner: Point(x: 120, y: 110),  // dist to anchor = sqrt(40²+20²)
                              pointer: Point(x: 160, y: 130),       // doubled vector from anchor → factor 2
                              minFactor: 0.05)
        let starts: [ItemId: Transform] = ["a": Transform(x: 100, y: 100, scale: 1, rotate: 0)]
        let (b, t) = SelectionTransforms.resize(startBox: box, startTransforms: starts, drag: drag)
        #expect(approx(b.size.width, 80) && approx(b.size.height, 40))   // doubled
        #expect(approx(t["a"]!.scale, 2))
        // translate scales around the anchor: 80 + 2*(100-80) = 120 ; 90 + 2*(100-90)=110
        #expect(approx(t["a"]!.x, 120) && approx(t["a"]!.y, 110))
    }

    @Test("resize clamps to the floor so it cannot collapse")
    func resizeClamp() {
        let anchor = Point(x: 80, y: 90)
        let drag = ResizeDrag(anchor: anchor, startCorner: Point(x: 120, y: 110),
                              pointer: anchor,  // factor → 0
                              minFactor: 0.05)
        let (b, _) = SelectionTransforms.resize(startBox: box, startTransforms: ["a": .identity],
                                                drag: drag)
        #expect(b.size.width > 0)  // did not collapse
    }

    @Test("rotate spins the box and every stroke around the shared center")
    func rotate() {
        let center = Point(x: 0, y: 0)
        let starts: [ItemId: Transform] = ["a": Transform(x: 10, y: 0, scale: 1, rotate: 0)]
        let rbox = OrientedBox(center: center, size: Size(width: 20, height: 20), rotation: 0)
        // startPointer at angle 0, pointer at angle +90° (y-down → (0,10)).
        let drag = RotateDrag(center: center, startPointer: Point(x: 10, y: 0),
                              pointer: Point(x: 0, y: 10), snap15: false)
        let (b, t) = SelectionTransforms.rotate(startBox: rbox, startTransforms: starts, drag: drag)
        #expect(approx(b.rotation, 90))
        #expect(approx(t["a"]!.rotate, 90))
        // stroke translate (10,0) rotated +90 about origin (y-down) → (0,10)
        #expect(approx(t["a"]!.x, 0) && approx(t["a"]!.y, 10))
    }

    @Test("rotate snaps to 15° increments when requested")
    func rotateSnap() {
        let center = Point(x: 0, y: 0)
        let rbox = OrientedBox(center: center, size: Size(width: 20, height: 20), rotation: 0)
        // ~10° delta snaps to 15? No — nearest is 15 only if >7.5; ~10° → 15.
        let drag = RotateDrag(center: center, startPointer: Point(x: 10, y: 0),
                              pointer: Point(x: 10, y: 1.763),  // atan2(1.763,10)≈10°
                              snap15: true)
        let (b, _) = SelectionTransforms.rotate(startBox: rbox, startTransforms: ["a": .identity],
                                                drag: drag)
        #expect(approx(b.rotation, 15, 1e-3))
    }
}
