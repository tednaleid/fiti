// ABOUTME: Pure-function hit-testing, marquee selection, and bounds math
// ABOUTME: for the selection tool. No state, no AppKit — Stroke geometry only.

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
    public static func selectionBounds(strokeIds: [StrokeId], strokes: [String: Stroke]) -> Rect? {
        var union: Rect?
        for id in strokeIds {
            guard let s = strokes[id] else { continue }
            guard let bounds = aabb(of: transformed(points: s.points, by: s.transform)) else { continue }
            if let current = union {
                union = unionRect(current, bounds)
            } else {
                union = bounds
            }
        }
        return union
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
}
