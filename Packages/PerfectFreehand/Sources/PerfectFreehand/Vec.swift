// ABOUTME: Ported from perfect-freehand@1.2.3/vec.ts (MIT, Steve Ruiz).
// ABOUTME: 2D vector math — internal helpers used by the algorithm.

import Foundation

enum Vec {
    /// Negate a vector.
    static func neg(_ A: [Double]) -> [Double] {
        return [-A[0], -A[1]]
    }

    /// Add vectors.
    static func add(_ A: [Double], _ B: [Double]) -> [Double] {
        return [A[0] + B[0], A[1] + B[1]]
    }

    /// Add vectors into an existing output vector (allocation-free).
    @discardableResult
    static func addInto(_ out: inout [Double], _ A: [Double], _ B: [Double]) -> [Double] {
        out[0] = A[0] + B[0]
        out[1] = A[1] + B[1]
        return out
    }

    /// Subtract vectors.
    static func sub(_ A: [Double], _ B: [Double]) -> [Double] {
        return [A[0] - B[0], A[1] - B[1]]
    }

    /// Subtract vectors into an existing output vector (allocation-free).
    @discardableResult
    static func subInto(_ out: inout [Double], _ A: [Double], _ B: [Double]) -> [Double] {
        out[0] = A[0] - B[0]
        out[1] = A[1] - B[1]
        return out
    }

    /// Vector multiplication by scalar.
    static func mul(_ A: [Double], _ n: Double) -> [Double] {
        return [A[0] * n, A[1] * n]
    }

    /// Vector multiplication by scalar into an existing output vector (allocation-free).
    @discardableResult
    static func mulInto(_ out: inout [Double], _ A: [Double], _ n: Double) -> [Double] {
        out[0] = A[0] * n
        out[1] = A[1] * n
        return out
    }

    /// Vector division by scalar.
    static func div(_ A: [Double], _ n: Double) -> [Double] {
        return [A[0] / n, A[1] / n]
    }

    /// Perpendicular rotation of a vector A.
    static func per(_ A: [Double]) -> [Double] {
        return [A[1], -A[0]]
    }

    /// Perpendicular rotation into an existing output vector (allocation-free).
    @discardableResult
    static func perInto(_ out: inout [Double], _ A: [Double]) -> [Double] {
        let temp = A[0]
        out[0] = A[1]
        out[1] = -temp
        return out
    }

    /// Dot product.
    static func dpr(_ A: [Double], _ B: [Double]) -> Double {
        return A[0] * B[0] + A[1] * B[1]
    }

    /// Get whether two vectors are equal.
    static func isEqual(_ A: [Double], _ B: [Double]) -> Bool {
        return A[0] == B[0] && A[1] == B[1]
    }

    /// Length of the vector.
    static func len(_ A: [Double]) -> Double {
        return hypot(A[0], A[1])
    }

    /// Length of the vector squared.
    static func len2(_ A: [Double]) -> Double {
        return A[0] * A[0] + A[1] * A[1]
    }

    /// Distance from A to B squared (inlined for performance).
    static func dist2(_ A: [Double], _ B: [Double]) -> Double {
        let dx = A[0] - B[0]
        let dy = A[1] - B[1]
        return dx * dx + dy * dy
    }

    /// Get normalized / unit vector.
    static func uni(_ A: [Double]) -> [Double] {
        return div(A, len(A))
    }

    /// Distance from A to B.
    static func dist(_ A: [Double], _ B: [Double]) -> Double {
        return hypot(A[1] - B[1], A[0] - B[0])
    }

    /// Mean between two vectors or mid vector between two vectors.
    static func med(_ A: [Double], _ B: [Double]) -> [Double] {
        return mul(add(A, B), 0.5)
    }

    /// Rotate a vector around another vector by r (radians).
    static func rotAround(_ A: [Double], _ C: [Double], _ r: Double) -> [Double] {
        let s = sin(r)
        let c = cos(r)

        let px = A[0] - C[0]
        let py = A[1] - C[1]

        let nx = px * c - py * s
        let ny = px * s + py * c

        return [nx + C[0], ny + C[1]]
    }

    /// Rotate a vector around another vector by r (radians) into an existing output vector (allocation-free).
    @discardableResult
    static func rotAroundInto(_ out: inout [Double], _ A: [Double], _ C: [Double], _ r: Double) -> [Double] {
        let s = sin(r)
        let c = cos(r)

        let px = A[0] - C[0]
        let py = A[1] - C[1]

        let nx = px * c - py * s
        let ny = px * s + py * c

        out[0] = nx + C[0]
        out[1] = ny + C[1]
        return out
    }

    /// Interpolate vector A to B with a scalar t.
    static func lrp(_ A: [Double], _ B: [Double], _ t: Double) -> [Double] {
        return add(A, mul(sub(B, A), t))
    }

    /// Interpolate vector A to B with a scalar t into an existing output vector (allocation-free).
    @discardableResult
    static func lrpInto(_ out: inout [Double], _ A: [Double], _ B: [Double], _ t: Double) -> [Double] {
        let dx = B[0] - A[0]
        let dy = B[1] - A[1]
        out[0] = A[0] + dx * t
        out[1] = A[1] + dy * t
        return out
    }

    /// Project a point A in the direction B by a scalar c.
    static func prj(_ A: [Double], _ B: [Double], _ c: Double) -> [Double] {
        return add(A, mul(B, c))
    }

    /// Project a point A in the direction B by a scalar c into an existing output vector (allocation-free).
    @discardableResult
    static func prjInto(_ out: inout [Double], _ A: [Double], _ B: [Double], _ c: Double) -> [Double] {
        out[0] = A[0] + B[0] * c
        out[1] = A[1] + B[1] * c
        return out
    }
}
