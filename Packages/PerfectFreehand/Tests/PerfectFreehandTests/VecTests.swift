// ABOUTME: Tests for Vec — first-principles coverage of every exported function
// ABOUTME: from perfect-freehand@1.2.3/vec.ts. Upstream has no vec.spec.ts.

import Testing
import Foundation
@testable import PerfectFreehand

@Suite("Vec")
struct VecTests {
    // MARK: - Float-tolerant comparison helpers

    private func expectClose(_ a: Double, _ b: Double, abs tolerance: Double = 1e-12) {
        #expect(Swift.abs(a - b) <= tolerance, "\(a) vs \(b)")
    }

    private func expectClose(_ a: [Double], _ b: [Double], abs tolerance: Double = 1e-12) {
        #expect(a.count == b.count)
        for (i, (x, y)) in zip(a, b).enumerated() {
            #expect(Swift.abs(x - y) <= tolerance, "index \(i): \(x) vs \(y)")
        }
    }

    // MARK: - neg

    @Test("neg negates components")
    func negBasic() {
        #expect(Vec.neg([1, 2]) == [-1, -2])
        #expect(Vec.neg([-3, 4]) == [3, -4])
    }

    @Test("neg of zero vector is zero")
    func negZero() {
        #expect(Vec.neg([0, 0]) == [0, 0])
    }

    // MARK: - add

    @Test("add sums two vectors")
    func addBasic() {
        #expect(Vec.add([1, 2], [3, 4]) == [4, 6])
        #expect(Vec.add([-1, 2], [1, -2]) == [0, 0])
    }

    @Test("add with zero is identity")
    func addZeroIdentity() {
        #expect(Vec.add([5, 7], [0, 0]) == [5, 7])
    }

    // MARK: - addInto

    @Test("addInto mutates output and returns it")
    func addIntoBasic() {
        var out: [Double] = [0, 0]
        let result = Vec.addInto(&out, [1, 2], [3, 4])
        #expect(out == [4, 6])
        #expect(result == [4, 6])
    }

    @Test("addInto overwrites pre-existing values")
    func addIntoOverwrites() {
        var out: [Double] = [99, -99]
        _ = Vec.addInto(&out, [1, 1], [2, 2])
        #expect(out == [3, 3])
    }

    // MARK: - sub

    @Test("sub subtracts components")
    func subBasic() {
        #expect(Vec.sub([5, 7], [2, 3]) == [3, 4])
    }

    @Test("sub of identical vectors is zero")
    func subIdentical() {
        #expect(Vec.sub([4, -1], [4, -1]) == [0, 0])
    }

    // MARK: - subInto

    @Test("subInto mutates output")
    func subIntoBasic() {
        var out: [Double] = [0, 0]
        _ = Vec.subInto(&out, [10, 5], [3, 2])
        #expect(out == [7, 3])
    }

    // MARK: - mul

    @Test("mul scales by scalar")
    func mulBasic() {
        #expect(Vec.mul([2, 3], 4) == [8, 12])
        #expect(Vec.mul([1, -1], -2) == [-2, 2])
    }

    @Test("mul by zero returns zero")
    func mulZero() {
        #expect(Vec.mul([7, 9], 0) == [0, 0])
    }

    // MARK: - mulInto

    @Test("mulInto mutates output")
    func mulIntoBasic() {
        var out: [Double] = [0, 0]
        _ = Vec.mulInto(&out, [2, 3], 5)
        #expect(out == [10, 15])
    }

    // MARK: - div

    @Test("div divides by scalar")
    func divBasic() {
        #expect(Vec.div([10, 20], 2) == [5, 10])
    }

    @Test("div by 1 is identity")
    func divIdentity() {
        #expect(Vec.div([3, 4], 1) == [3, 4])
    }

    // MARK: - per

    @Test("per rotates 90 degrees clockwise (TS convention)")
    func perBasic() {
        // TS: per(A) -> [A[1], -A[0]]
        #expect(Vec.per([1, 0]) == [0, -1])
        #expect(Vec.per([0, 1]) == [1, 0])
        #expect(Vec.per([3, 4]) == [4, -3])
    }

    @Test("per of zero is zero")
    func perZero() {
        #expect(Vec.per([0, 0]) == [0, 0])
    }

    // MARK: - perInto

    @Test("perInto mutates output")
    func perIntoBasic() {
        var out: [Double] = [0, 0]
        _ = Vec.perInto(&out, [3, 4])
        #expect(out == [4, -3])
    }

    @Test("perInto handles aliasing (out === A semantics not tested; just basic correctness)")
    func perIntoOverwrites() {
        var out: [Double] = [99, 99]
        _ = Vec.perInto(&out, [1, 2])
        #expect(out == [2, -1])
    }

    // MARK: - dpr (dot product)

    @Test("dpr computes dot product")
    func dprBasic() {
        #expect(Vec.dpr([1, 2], [3, 4]) == 11)
        #expect(Vec.dpr([1, 0], [0, 1]) == 0)
    }

    @Test("dpr of perpendicular vectors is zero")
    func dprPerpendicular() {
        #expect(Vec.dpr([1, 0], [0, 5]) == 0)
    }

    // MARK: - isEqual

    @Test("isEqual on equal vectors")
    func isEqualTrue() {
        #expect(Vec.isEqual([1.5, 2.5], [1.5, 2.5]))
        #expect(Vec.isEqual([0, 0], [0, 0]))
    }

    @Test("isEqual on different vectors")
    func isEqualFalse() {
        #expect(!Vec.isEqual([1, 2], [1, 3]))
        #expect(!Vec.isEqual([1, 2], [2, 2]))
    }

    // MARK: - len

    @Test("len computes 2D length")
    func lenBasic() {
        #expect(Vec.len([3, 4]) == 5)
        expectClose(Vec.len([1, 1]), sqrt(2.0))
    }

    @Test("len of zero is zero")
    func lenZero() {
        #expect(Vec.len([0, 0]) == 0)
    }

    // MARK: - len2

    @Test("len2 computes squared length")
    func len2Basic() {
        #expect(Vec.len2([3, 4]) == 25)
        #expect(Vec.len2([1, 1]) == 2)
    }

    @Test("len2 of zero is zero")
    func len2Zero() {
        #expect(Vec.len2([0, 0]) == 0)
    }

    // MARK: - dist2

    @Test("dist2 computes squared distance")
    func dist2Basic() {
        #expect(Vec.dist2([0, 0], [3, 4]) == 25)
        #expect(Vec.dist2([1, 1], [4, 5]) == 25)
    }

    @Test("dist2 of identical points is zero")
    func dist2Identical() {
        #expect(Vec.dist2([2, 3], [2, 3]) == 0)
    }

    // MARK: - uni

    @Test("uni returns unit vector")
    func uniBasic() {
        expectClose(Vec.uni([3, 4]), [0.6, 0.8])
        expectClose(Vec.uni([1, 0]), [1, 0])
        expectClose(Vec.uni([0, 5]), [0, 1])
    }

    @Test("uni preserves direction")
    func uniDirection() {
        let u = Vec.uni([2, 2])
        expectClose(u, [sqrt(2.0) / 2, sqrt(2.0) / 2])
    }

    // MARK: - dist

    @Test("dist computes 2D distance")
    func distBasic() {
        #expect(Vec.dist([0, 0], [3, 4]) == 5)
        #expect(Vec.dist([1, 1], [4, 5]) == 5)
    }

    @Test("dist of identical points is zero")
    func distIdentical() {
        #expect(Vec.dist([7, 9], [7, 9]) == 0)
    }

    // MARK: - med

    @Test("med computes midpoint")
    func medBasic() {
        #expect(Vec.med([0, 0], [10, 20]) == [5, 10])
        #expect(Vec.med([-2, 4], [2, -4]) == [0, 0])
    }

    @Test("med of identical points returns same point")
    func medIdentical() {
        #expect(Vec.med([3, 5], [3, 5]) == [3, 5])
    }

    // MARK: - rotAround

    @Test("rotAround by zero is identity")
    func rotAroundZero() {
        let result = Vec.rotAround([5, 0], [0, 0], 0)
        expectClose(result, [5, 0])
    }

    @Test("rotAround by pi/2 about origin")
    func rotAroundQuarter() {
        // Rotating [1, 0] by pi/2 around origin -> [0, 1]
        let result = Vec.rotAround([1, 0], [0, 0], .pi / 2)
        expectClose(result, [0, 1], abs: 1e-12)
    }

    @Test("rotAround by pi about origin")
    func rotAroundHalf() {
        let result = Vec.rotAround([3, 4], [0, 0], .pi)
        expectClose(result, [-3, -4], abs: 1e-12)
    }

    @Test("rotAround a point about itself is identity")
    func rotAroundSelf() {
        let result = Vec.rotAround([2, 3], [2, 3], 1.234)
        expectClose(result, [2, 3])
    }

    @Test("rotAround about non-origin center")
    func rotAroundNonOrigin() {
        // Point [2, 1] rotated pi/2 about center [1, 1] -> [1, 2]
        let result = Vec.rotAround([2, 1], [1, 1], .pi / 2)
        expectClose(result, [1, 2], abs: 1e-12)
    }

    // MARK: - rotAroundInto

    @Test("rotAroundInto mutates output")
    func rotAroundIntoBasic() {
        var out: [Double] = [0, 0]
        _ = Vec.rotAroundInto(&out, [1, 0], [0, 0], .pi / 2)
        expectClose(out, [0, 1], abs: 1e-12)
    }

    // MARK: - lrp

    @Test("lrp at t=0 returns A")
    func lrpStart() {
        #expect(Vec.lrp([2, 4], [10, 20], 0) == [2, 4])
    }

    @Test("lrp at t=1 returns B")
    func lrpEnd() {
        #expect(Vec.lrp([2, 4], [10, 20], 1) == [10, 20])
    }

    @Test("lrp at t=0.5 returns midpoint")
    func lrpMid() {
        expectClose(Vec.lrp([0, 0], [10, 20], 0.5), [5, 10])
    }

    @Test("lrp extrapolates beyond t=1")
    func lrpExtrapolate() {
        expectClose(Vec.lrp([0, 0], [10, 20], 2), [20, 40])
    }

    // MARK: - lrpInto

    @Test("lrpInto mutates output")
    func lrpIntoBasic() {
        var out: [Double] = [0, 0]
        _ = Vec.lrpInto(&out, [0, 0], [10, 20], 0.5)
        expectClose(out, [5, 10])
    }

    // MARK: - prj

    @Test("prj projects along direction")
    func prjBasic() {
        // prj(A, B, c) = A + B*c
        #expect(Vec.prj([1, 2], [3, 4], 2) == [7, 10])
    }

    @Test("prj by zero is identity")
    func prjZero() {
        #expect(Vec.prj([5, 6], [9, 9], 0) == [5, 6])
    }

    // MARK: - prjInto

    @Test("prjInto mutates output")
    func prjIntoBasic() {
        var out: [Double] = [0, 0]
        _ = Vec.prjInto(&out, [1, 2], [3, 4], 2)
        #expect(out == [7, 10])
    }
}
