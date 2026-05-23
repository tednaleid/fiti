// ABOUTME: Pure-function hit-testing, marquee selection, and bounds math
// ABOUTME: for the selection tool. No state, no AppKit — CanvasItem geometry.

import Foundation

public enum SelectionMath {
    /// Returns the topmost (latest in array) StrokeId whose transformed polyline
    /// passes within `stroke.width / 2 + tolerance` of `query`, or nil.
    public static func hitTest(point query: StrokePoint, strokes: [Stroke], tolerance: Double) -> StrokeId? {
        for stroke in strokes.reversed() {
            let halfWidth = stroke.width / 2 + tolerance
            let pts = transformed(points: stroke.points, by: stroke.transform)
            if minDistanceFromPolyline(point: query, polyline: pts) <= halfWidth {
                return stroke.id
            }
        }
        return nil
    }

    /// Returns every StrokeId whose transformed AABB intersects `rect`,
    /// preserving the original array's order (z-order from bottom up).
    public static func marqueeHit(rect: Rect, strokes: [Stroke]) -> [StrokeId] {
        strokes.compactMap { stroke in
            guard let bounds = aabb(of: transformed(points: stroke.points, by: stroke.transform)) else { return nil }
            return rect.intersects(bounds) ? stroke.id : nil
        }
    }

    /// AABB enclosing the union of every selected stroke's transformed points.
    public static func selectionBounds(strokeIds: [StrokeId], strokes: [ItemId: CanvasItem]) -> Rect? {
        var union: Rect?
        for id in strokeIds {
            guard case .stroke(let s) = strokes[id] else { continue }
            guard let bounds = aabb(of: transformed(points: s.points, by: s.transform)) else { continue }
            if let current = union {
                union = unionRect(current, bounds)
            } else {
                union = bounds
            }
        }
        return union
    }

    // MARK: - Item-generic geometry

    /// Returns the topmost (latest in `order`) ItemId whose geometry contains `point`,
    /// or nil. Strokes use polyline distance; text uses point-in-oriented-box.
    public static func hitTestItem(at point: Point, items: [ItemId: CanvasItem],
                                   order: [ItemId], tolerance: Double) -> ItemId? {
        let query = StrokePoint(x: point.x, y: point.y, pressure: 0)
        for id in order.reversed() {
            guard let item = items[id] else { continue }
            switch item {
            case .stroke(let s):
                let halfWidth = s.width / 2 + tolerance
                let pts = transformed(points: s.points, by: s.transform)
                if minDistanceFromPolyline(point: query, polyline: pts) <= halfWidth { return id }
            case .text(let t):
                if pointInTextItem(point, text: t, tolerance: tolerance) { return id }
            }
        }
        return nil
    }

    /// Returns every ItemId in `order` whose world AABB intersects `rect`.
    public static func marqueeHitItems(rect: Rect, items: [ItemId: CanvasItem],
                                       order: [ItemId]) -> [ItemId] {
        order.compactMap { id in
            guard let item = items[id], let bounds = worldAABB(of: item) else { return nil }
            return rect.intersects(bounds) ? id : nil
        }
    }

    /// AABB enclosing the union of every selected item's world box.
    public static func selectionBoundsItems(ids: [ItemId], items: [ItemId: CanvasItem]) -> Rect? {
        var union: Rect?
        for id in ids {
            guard let item = items[id], let bounds = worldAABB(of: item) else { continue }
            if let current = union {
                union = unionRect(current, bounds)
            } else {
                union = bounds
            }
        }
        return union
    }

    /// Classifies a world point against an oriented selection box.
    /// Precedence: rotate node, then corners, then interior, else outside.
    public static func region(at point: Point, box: OrientedBox?, handleRadius: Double,
                              rotateNodeOffset: Double, rotateNodeRadius: Double) -> SelectionRegion {
        guard let box else { return .outside }
        let local = box.toLocal(point)
        let halfW = box.size.width / 2
        let halfH = box.size.height / 2

        let node = Point(x: 0, y: -halfH - rotateNodeOffset)
        if hypot(local.x - node.x, local.y - node.y) <= rotateNodeRadius { return .rotateHandle }

        let corners: [(Corner, Point)] = [
            (.topLeft, Point(x: -halfW, y: -halfH)),
            (.topRight, Point(x: halfW, y: -halfH)),
            (.bottomRight, Point(x: halfW, y: halfH)),
            (.bottomLeft, Point(x: -halfW, y: halfH))
        ]
        for (corner, c) in corners where hypot(local.x - c.x, local.y - c.y) <= handleRadius {
            return .corner(corner)
        }

        if abs(local.x) <= halfW && abs(local.y) <= halfH { return .body }
        return .outside
    }

    // MARK: - Internals

    private static func transformed(points: [StrokePoint], by t: Transform) -> [StrokePoint] {
        guard t != .identity else { return points }
        let cosθ = cos(t.rotate * .pi / 180.0)
        let sinθ = sin(t.rotate * .pi / 180.0)
        return points.map { p in
            let sx = p.x * t.scale
            let sy = p.y * t.scale
            let rx = sx * cosθ - sy * sinθ
            let ry = sx * sinθ + sy * cosθ
            return StrokePoint(x: rx + t.x, y: ry + t.y, pressure: p.pressure)
        }
    }

    private static func aabb(of points: [StrokePoint]) -> Rect? {
        guard let first = points.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            if p.x < minX { minX = p.x }
            if p.x > maxX { maxX = p.x }
            if p.y < minY { minY = p.y }
            if p.y > maxY { maxY = p.y }
        }
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func unionRect(_ a: Rect, _ b: Rect) -> Rect {
        let x = min(a.x, b.x)
        let y = min(a.y, b.y)
        let mx = max(a.maxX, b.maxX)
        let my = max(a.maxY, b.maxY)
        return Rect(x: x, y: y, width: mx - x, height: my - y)
    }

    private static func minDistanceFromPolyline(point q: StrokePoint, polyline: [StrokePoint]) -> Double {
        guard polyline.count >= 2 else {
            return polyline.first.map { distance(from: q, to: $0) } ?? .infinity
        }
        var best = Double.infinity
        for i in 0..<(polyline.count - 1) {
            let d = distanceFromSegment(point: q, a: polyline[i], b: polyline[i + 1])
            if d < best { best = d }
        }
        return best
    }

    private static func distanceFromSegment(point p: StrokePoint, a: StrokePoint, b: StrokePoint) -> Double {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let lengthSquared = abx * abx + aby * aby
        if lengthSquared == 0 { return distance(from: p, to: a) }
        let apx = p.x - a.x
        let apy = p.y - a.y
        var t = (apx * abx + apy * aby) / lengthSquared
        t = max(0, min(1, t))
        let projX = a.x + t * abx
        let projY = a.y + t * aby
        let dx = p.x - projX
        let dy = p.y - projY
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func distance(from p: StrokePoint, to q: StrokePoint) -> Double {
        let dx = p.x - q.x
        let dy = p.y - q.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// World-space AABB of an item's geometry.
    private static func worldAABB(of item: CanvasItem) -> Rect? {
        switch item {
        case .stroke(let s):
            return aabb(of: transformed(points: s.points, by: s.transform))
        case .text(let t):
            let corners = textWorldCorners(t)
            guard let first = corners.first else { return nil }
            var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
            for p in corners.dropFirst() {
                if p.x < minX { minX = p.x }
                if p.x > maxX { maxX = p.x }
                if p.y < minY { minY = p.y }
                if p.y > maxY { maxY = p.y }
            }
            return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }

    /// World-space corners of a text item's local bounds rect, pushed through its transform.
    /// Local rect spans (0,0)–(bounds.width, bounds.height); transform places origin.
    private static func textWorldCorners(_ t: TextItem) -> [Point] {
        let w = t.bounds.width, h = t.bounds.height
        let local: [Point] = [
            Point(x: 0, y: 0), Point(x: w, y: 0),
            Point(x: w, y: h), Point(x: 0, y: h)
        ]
        let cosθ = cos(t.transform.rotate * .pi / 180.0)
        let sinθ = sin(t.transform.rotate * .pi / 180.0)
        return local.map { p in
            let sx = p.x * t.transform.scale
            let sy = p.y * t.transform.scale
            let rx = sx * cosθ - sy * sinθ
            let ry = sx * sinθ + sy * cosθ
            return Point(x: rx + t.transform.x, y: ry + t.transform.y)
        }
    }

    /// Returns true if `point` lies within the text item's oriented box, expanded by `tolerance`.
    private static func pointInTextItem(_ point: Point, text: TextItem, tolerance: Double) -> Bool {
        let w = text.bounds.width * text.transform.scale
        let h = text.bounds.height * text.transform.scale
        guard w > 0, h > 0 else { return false }
        // Build an OrientedBox centered at the midpoint of the text rect in world space.
        let centerLocal = Point(x: text.bounds.width / 2, y: text.bounds.height / 2)
        let cosθ = cos(text.transform.rotate * .pi / 180.0)
        let sinθ = sin(text.transform.rotate * .pi / 180.0)
        let sx = centerLocal.x * text.transform.scale
        let sy = centerLocal.y * text.transform.scale
        let worldCenter = Point(
            x: sx * cosθ - sy * sinθ + text.transform.x,
            y: sx * sinθ + sy * cosθ + text.transform.y)
        let box = OrientedBox(center: worldCenter,
                              size: Size(width: w + tolerance * 2, height: h + tolerance * 2),
                              rotation: text.transform.rotate)
        let local = box.toLocal(point)
        return abs(local.x) <= (w + tolerance * 2) / 2 && abs(local.y) <= (h + tolerance * 2) / 2
    }
}
