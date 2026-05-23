// ABOUTME: Pure gesture math for the selection tool — translate, uniform
// ABOUTME: resize (opposite-corner anchor), and rigid rotate around center.
// ABOUTME: Each returns the updated box and per-stroke transforms from one delta.

import Foundation

/// Parameters for a resize drag: the pinned corner, the dragged corner at gesture
/// start, the current pointer position, and the minimum allowed scale factor.
public struct ResizeDrag {
    public let anchor: Point
    public let startCorner: Point
    public let pointer: Point
    public let minFactor: Double

    public init(anchor: Point, startCorner: Point, pointer: Point, minFactor: Double) {
        self.anchor = anchor
        self.startCorner = startCorner
        self.pointer = pointer
        self.minFactor = minFactor
    }
}

/// Parameters for a rotate drag: the rotation center, the pointer at gesture
/// start, the current pointer position, and whether to snap to 15° increments.
public struct RotateDrag {
    public let center: Point
    public let startPointer: Point
    public let pointer: Point
    public let snap15: Bool

    public init(center: Point, startPointer: Point, pointer: Point, snap15: Bool) {
        self.center = center
        self.startPointer = startPointer
        self.pointer = pointer
        self.snap15 = snap15
    }
}

public enum SelectionTransforms {
    public static func translate(startBox: OrientedBox, startTransforms: [ItemId: Transform],
                                 dx: Double, dy: Double) -> (OrientedBox, [ItemId: Transform]) {
        var box = startBox
        box.center = Point(x: startBox.center.x + dx, y: startBox.center.y + dy)
        var out: [ItemId: Transform] = [:]
        for (id, t) in startTransforms {
            out[id] = Transform(x: t.x + dx, y: t.y + dy, scale: t.scale, rotate: t.rotate)
        }
        return (box, out)
    }

    public static func resize(startBox: OrientedBox, startTransforms: [ItemId: Transform],
                              drag: ResizeDrag) -> (OrientedBox, [ItemId: Transform]) {
        let startDist = hypot(drag.startCorner.x - drag.anchor.x, drag.startCorner.y - drag.anchor.y)
        let nowDist = hypot(drag.pointer.x - drag.anchor.x, drag.pointer.y - drag.anchor.y)
        let s = startDist == 0 ? 1 : max(drag.minFactor, nowDist / startDist)

        var box = startBox
        box.size = Size(width: startBox.size.width * s, height: startBox.size.height * s)
        box.center = Point(x: drag.anchor.x + s * (startBox.center.x - drag.anchor.x),
                           y: drag.anchor.y + s * (startBox.center.y - drag.anchor.y))

        var out: [ItemId: Transform] = [:]
        for (id, t) in startTransforms {
            out[id] = Transform(x: drag.anchor.x + s * (t.x - drag.anchor.x),
                                y: drag.anchor.y + s * (t.y - drag.anchor.y),
                                scale: t.scale * s, rotate: t.rotate)
        }
        return (box, out)
    }

    public static func rotate(startBox: OrientedBox, startTransforms: [ItemId: Transform],
                              drag: RotateDrag) -> (OrientedBox, [ItemId: Transform]) {
        let a0 = atan2(drag.startPointer.y - drag.center.y, drag.startPointer.x - drag.center.x)
        let a1 = atan2(drag.pointer.y - drag.center.y, drag.pointer.x - drag.center.x)
        var deg = (a1 - a0) * 180 / .pi
        if drag.snap15 { deg = (deg / 15).rounded() * 15 }

        var box = startBox
        box.rotation = startBox.rotation + deg

        let rad = deg * .pi / 180
        let c = cos(rad), s = sin(rad)
        var out: [ItemId: Transform] = [:]
        for (id, t) in startTransforms {
            let dx = t.x - drag.center.x
            let dy = t.y - drag.center.y
            out[id] = Transform(x: drag.center.x + dx * c - dy * s,
                                y: drag.center.y + dx * s + dy * c,
                                scale: t.scale, rotate: t.rotate + deg)
        }
        return (box, out)
    }
}
