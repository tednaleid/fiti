# Arrow Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dedicated arrow tool (`a` / toolbar button) that draws a straight, single-headed arrow from tail to head, as a first-class `CanvasItem` that selects, transforms, restyles, and flattens like every other mark, with full WYSIWYG live drawing.

**Architecture:** A pure-Core `ArrowItem` value and `ArrowGeometry` outline function feed a single AppKit `drawArrow` fill that plugs into the existing `drawItem` dispatch, so the committed bake, snapshot, opacity flattening, and live-group engine pick arrows up with no new pixel paths. The in-progress arrow is a transient held in `Editor` (out of the doc until commit) and surfaced through a generalized `RenderFrame.inProgress: CanvasItem?`, so the pen's live-flatten machinery draws it unchanged.

**Tech Stack:** Swift, Swift Testing (`import Testing`, `@Test`, `#expect`), Xcode via XcodeGen, AppKit + CoreGraphics adapters, pure `Sources/Core`. All commands through `just`.

**Source of truth:** `docs/specs/2026-05-24-fiti-arrow-tool-design.md`.

---

## Conventions for every task

- Tests use Swift Testing, never XCTest. Red first: write the failing test, run it, watch it fail, then implement.
- Every new Swift file starts with two `// ABOUTME: ` lines.
- `Sources/Core` must not import AppKit, CoreGraphics, CoreText, Network, or SwiftUI. Geometry stays pure.
- `just test` runs the Core `fiti-unit` target. `just test-integration` runs the AppKit target. `just check` is the full gate (test + lint + build) and is what the pre-commit hook runs. Never `--no-verify`.
- Commit only the task's files. Use a HEREDOC commit message ending with:
  `Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>`
- SwiftLint: 5-parameter function limit, ~250-line type-body limit, ~400-line file limit, cyclomatic complexity 10, single-space after colon.
- Each commit must pass `just check` green. Two tasks (4 and 7) add an enum case and therefore must update every exhaustive `switch` over that enum in the same commit; that is expected and called out.

## File structure

Create:
- `Sources/Core/Model/ArrowItem.swift` — the value type.
- `Sources/Core/Rendering/ArrowGeometry.swift` — pure outline function.
- `Sources/Core/Control/AppController+ArrowTool.swift` — pointer routing for the tool.
- `Sources/AppKit/ArrowDrawing.swift` — the `CGPath` fill.
- `Tests/CoreTests/ArrowItemTests.swift`, `Tests/CoreTests/ArrowGeometryTests.swift`, `Tests/CoreTests/ArrowToolTests.swift`, `Tests/CoreTests/EditorArrowTests.swift`, `Tests/CoreTests/RenderFrameArrowTests.swift`.
- `Tests/AppKitTests/ArrowDrawingTests.swift`, `Tests/AppKitTests/ArrowFlattenTests.swift`.

Modify:
- `Sources/Core/Model/CanvasItem.swift`, `Sources/Core/Model/Tool.swift`, `Sources/Core/Control/KeyCommand.swift`, `Sources/Core/Control/AppController.swift`, `Sources/Core/Selection/SelectionMath.swift`, `Sources/Core/Ports/RenderFrame.swift`, `Sources/Core/Editor/Editor.swift`, `Sources/Core/Editor/RenderFrame+from.swift`.
- `Sources/AppKit/StrokeDrawing.swift`, `Sources/AppKit/CanvasView.swift`, `Sources/AppKit/GroupCompositor.swift`, `Sources/AppKit/ToolbarController.swift`, `Sources/AppKit/CursorRenderer.swift`.
- `docs/fiti-roadmap.md`, `docs/architecture.md`, `docs/perf-baseline.md`.

---

### Task 1: ArrowItem value type

**Files:**
- Create: `Sources/Core/Model/ArrowItem.swift`
- Test: `Tests/CoreTests/ArrowItemTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ABOUTME: ArrowItem value-type tests: construction, Codable round-trip, equality.
// ABOUTME: Pure Core, no AppKit.

import Testing
@testable import Core

@Suite struct ArrowItemTests {
    private func sample() -> ArrowItem {
        ArrowItem(id: ItemId(), color: RGBA(r: 1, g: 0, b: 0, a: 0.5), width: 8,
                  transform: .identity, tail: Point(x: 0, y: 0), head: Point(x: 100, y: 0),
                  createdAt: 12.0)
    }

    @Test func storesEndpointsAndStyle() {
        let a = sample()
        #expect(a.tail == Point(x: 0, y: 0))
        #expect(a.head == Point(x: 100, y: 0))
        #expect(a.width == 8)
        #expect(a.color.a == 0.5)
    }

    @Test func codableRoundTrips() throws {
        let a = sample()
        let data = try JSONEncoder().encode(a)
        let back = try JSONDecoder().decode(ArrowItem.self, from: data)
        #expect(back == a)
    }
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `just test`
Expected: FAIL, `cannot find 'ArrowItem' in scope`.

- [ ] **Step 3: Implement**

```swift
// ABOUTME: One drawn arrow: frozen tail/head endpoints, style, and transform.
// ABOUTME: A first-class CanvasItem case; head is rendered at `head`, the lift point.

import Foundation

public struct ArrowItem: Equatable, Codable, Sendable {
    public let id: ItemId
    public var color: RGBA
    public var width: Double
    public var transform: Transform
    public var tail: Point        // local coords, frozen at commit
    public var head: Point        // local coords, frozen at commit
    public let createdAt: Double  // seconds since epoch

    public init(id: ItemId, color: RGBA, width: Double, transform: Transform,
                tail: Point, head: Point, createdAt: Double) {
        self.id = id
        self.color = color
        self.width = width
        self.transform = transform
        self.tail = tail
        self.head = head
        self.createdAt = createdAt
    }
}
```

(Confirm `ItemId` has a parameterless `init()` usable in tests; if not, mint one via the test's id generator pattern used elsewhere in `Tests/CoreTests`.)

- [ ] **Step 4: Run and watch it pass**

Run: `just test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Model/ArrowItem.swift Tests/CoreTests/ArrowItemTests.swift
git commit -m "$(cat <<'EOF'
Core: ArrowItem value type (endpoints, style, transform)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: ArrowGeometry outline (pure)

**Files:**
- Create: `Sources/Core/Rendering/ArrowGeometry.swift`
- Test: `Tests/CoreTests/ArrowGeometryTests.swift`

The outline is one closed 7-vertex polygon in local space: tapered shaft merged with a swept, filled head. Proportions are multiples of stroke width, tuned to the approved mockup (medium sweep, subtle taper).

- [ ] **Step 1: Write the failing test**

```swift
// ABOUTME: ArrowGeometry.outline tests: vertex layout, width scaling, taper, degeneracy.
// ABOUTME: Pure Core; verifies the merged shaft+head polygon for a known arrow.

import Testing
@testable import Core

@Suite struct ArrowGeometryTests {
    @Test func horizontalArrowVertices() {
        let pts = ArrowGeometry.outline(tail: Point(x: 0, y: 0), head: Point(x: 100, y: 0), width: 10)
        #expect(pts.count == 7)
        // tip is the head
        #expect(pts[3] == Point(x: 100, y: 0))
        // barb tips at base (x = len - headLen = 55), spanning +/- barb (26)
        #expect(abs(pts[2].x - 55) < 1e-9 && abs(pts[2].y - 26) < 1e-9)
        #expect(abs(pts[4].x - 55) < 1e-9 && abs(pts[4].y + 26) < 1e-9)
        // tail edge half-width 2.75
        #expect(abs(pts[0].y - 2.75) < 1e-9)
        #expect(abs(pts[6].y + 2.75) < 1e-9)
    }

    @Test func headScalesWithWidth() {
        let small = ArrowGeometry.outline(tail: Point(x: 0, y: 0), head: Point(x: 200, y: 0), width: 10)
        let big = ArrowGeometry.outline(tail: Point(x: 0, y: 0), head: Point(x: 200, y: 0), width: 20)
        // barb half-span doubles with width
        #expect(abs(big[2].y - small[2].y * 2) < 1e-9)
    }

    @Test func tailNarrowerThanBarbSpan() {
        let pts = ArrowGeometry.outline(tail: Point(x: 0, y: 0), head: Point(x: 100, y: 0), width: 10)
        #expect(abs(pts[0].y) < abs(pts[2].y))   // taper: tail half-width < barb span
    }

    @Test func degenerateIsEmpty() {
        #expect(ArrowGeometry.outline(tail: Point(x: 5, y: 5), head: Point(x: 5, y: 5), width: 10).isEmpty)
        #expect(ArrowGeometry.outline(tail: Point(x: 0, y: 0), head: Point(x: 10, y: 0), width: 0).isEmpty)
    }
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `just test`
Expected: FAIL, `cannot find 'ArrowGeometry' in scope`.

- [ ] **Step 3: Implement**

```swift
// ABOUTME: Pure geometry for the arrow tool: builds the merged shaft+head outline.
// ABOUTME: One closed polygon so the seam never double-darkens and hit-test is single.

import Foundation

public enum ArrowGeometry {
    // Proportions as multiples of stroke width, tuned to the approved mockup.
    static let headLengthFactor = 4.5   // head length along the shaft
    static let barbSpanFactor = 2.6     // barb half-span perpendicular to the shaft
    static let sweepFraction = 0.25     // notch depth as a fraction of head length
    static let tailHalfFactor = 0.275   // shaft half-width at the tail
    static let baseHalfFactor = 0.5     // shaft half-width where it meets the head

    /// Merged arrow outline (local space) from `tail` to `head` at `width`.
    /// Seven vertices, counterclockwise; empty when degenerate.
    public static func outline(tail: Point, head: Point, width: Double) -> [Point] {
        let dx = head.x - tail.x, dy = head.y - tail.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 0, width > 0 else { return [] }
        let ux = dx / len, uy = dy / len     // unit axis, tail -> head
        let nx = -uy, ny = ux                // left normal

        let headLen = min(headLengthFactor * width, len)
        let barb = barbSpanFactor * width
        let notch = sweepFraction * headLen
        let tailH = tailHalfFactor * width
        let baseH = baseHalfFactor * width

        func along(_ p: Point, _ d: Double) -> Point { Point(x: p.x - ux * d, y: p.y - uy * d) }
        func offset(_ p: Point, _ d: Double) -> Point { Point(x: p.x + nx * d, y: p.y + ny * d) }

        let base = along(head, headLen)      // backmost of the head, on axis
        let notchPt = along(head, notch)     // inner back vertex, forward of base

        return [
            offset(tail, tailH),     // 0 tail left
            offset(notchPt, baseH),  // 1 shaft/head join left
            offset(base, barb),      // 2 left barb tip
            head,                    // 3 tip
            offset(base, -barb),     // 4 right barb tip
            offset(notchPt, -baseH), // 5 shaft/head join right
            offset(tail, -tailH)     // 6 tail right
        ]
    }
}
```

- [ ] **Step 4: Run and watch it pass**

Run: `just test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Rendering/ArrowGeometry.swift Tests/CoreTests/ArrowGeometryTests.swift
git commit -m "$(cat <<'EOF'
Core: ArrowGeometry merged shaft+head outline

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: ArrowDrawing fill (AppKit, standalone)

`drawArrow` takes an `ArrowItem` (it does not need the `CanvasItem` case yet), so it can be built and pixel-tested before the enum ripple in Task 4.

**Files:**
- Create: `Sources/AppKit/ArrowDrawing.swift`
- Test: `Tests/AppKitTests/ArrowDrawingTests.swift`

- [ ] **Step 1: Write the failing test**

Follow the offscreen-context pattern in `Tests/AppKitTests/CanvasViewBakeTests.swift` (create a `CGBitmapContext`, draw, sample pixels).

```swift
// ABOUTME: Pixel tests for drawArrow: the outline fills, and the shaft/head seam
// ABOUTME: shows no internal darkening because it is a single merged path.

import Testing
import CoreGraphics
@testable import AppKitModule   // use the actual AppKit target module name from project.yml
@testable import Core

@Suite struct ArrowDrawingTests {
    // Reuse the bitmap-context helper convention from CanvasViewBakeTests.
    @Test func fillsAndSeamNotDarker() {
        let ctx = makeBitmap(width: 140, height: 60)   // helper mirrored from CanvasViewBakeTests
        let arrow = ArrowItem(id: ItemId(), color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 10,
                              transform: .identity, tail: Point(x: 10, y: 30),
                              head: Point(x: 130, y: 30), createdAt: 0)
        drawArrow(arrow, in: ctx, isInProgress: false)
        // A point on the shaft is red.
        let shaft = pixel(ctx, x: 40, y: 30)
        #expect(shaft.r > 0.9 && shaft.a > 0.9)
        // The shaft/head seam (near the head base) is the same red, not doubled.
        let seam = pixel(ctx, x: 95, y: 30)
        #expect(abs(seam.r - shaft.r) < 0.02 && abs(seam.a - shaft.a) < 0.02)
    }
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `just test-integration`
Expected: FAIL, `cannot find 'drawArrow' in scope`.

- [ ] **Step 3: Implement**

```swift
// ABOUTME: Fills an ArrowItem's merged outline as one CGPath with rounded joins.
// ABOUTME: Shares the opaque/alpha behavior of drawStroke so it slots into drawItem.

import AppKit
import CoreGraphics
import Foundation

public func drawArrow(_ arrow: ArrowItem, in ctx: CGContext, isInProgress: Bool) {
    let outline = ArrowGeometry.outline(tail: arrow.tail, head: arrow.head, width: arrow.width)
    guard outline.count >= 3 else { return }

    withItemTransform(arrow.transform, in: ctx) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: outline[0].x, y: outline[0].y))
        for p in outline.dropFirst() {
            path.addLine(to: CGPoint(x: p.x, y: p.y))
        }
        path.closeSubpath()
        ctx.setFillColor(red: CGFloat(arrow.color.r), green: CGFloat(arrow.color.g),
                         blue: CGFloat(arrow.color.b), alpha: CGFloat(arrow.color.a))
        // Round the corners: stroke the same path in the same color with round joins.
        ctx.setStrokeColor(red: CGFloat(arrow.color.r), green: CGFloat(arrow.color.g),
                           blue: CGFloat(arrow.color.b), alpha: CGFloat(arrow.color.a))
        ctx.setLineWidth(CGFloat(arrow.width * ArrowGeometry.tailHalfFactor))
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.addPath(path)
        ctx.drawPath(using: .fillStroke)
    }
}
```

Note: `withItemTransform` is the shared CTM helper used by `drawStroke`/`drawText` in `StrokeDrawing.swift`. The fill-plus-same-color-stroke trick rounds the outer corners (matching the mockup) without changing the filled color. Keep the stroke width small.

- [ ] **Step 4: Run and watch it pass**

Run: `just test-integration`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/ArrowDrawing.swift Tests/AppKitTests/ArrowDrawingTests.swift
git commit -m "$(cat <<'EOF'
AppKit: drawArrow fills the merged outline with rounded joins

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Make ArrowItem a CanvasItem case (enum ripple)

Adding `.arrow` to `CanvasItem` breaks every exhaustive `switch` over it. This single commit adds the case plus all consumer branches, each calling units already built and tested in Tasks 2 and 3. It spans Core and AppKit so `just check` stays green.

**Files:**
- Modify: `Sources/Core/Model/CanvasItem.swift`
- Modify: `Sources/Core/Selection/SelectionMath.swift`
- Modify: `Sources/AppKit/StrokeDrawing.swift` (`drawItem`)
- Modify: `Sources/AppKit/CanvasView.swift` (`contentTag`)
- Modify: `Sources/AppKit/GroupCompositor.swift` (`inkPad`)
- Test: `Tests/CoreTests/ArrowItemTests.swift` (extend), new assertions in a `CanvasItemArrowTests` suite is also fine.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/CoreTests` (new file `CanvasItemArrowTests.swift`):

```swift
// ABOUTME: CanvasItem.arrow case: shared accessors, restyle, and SelectionMath
// ABOUTME: world AABB plus point-in-polygon hit-test for arrows.

import Testing
@testable import Core

@Suite struct CanvasItemArrowTests {
    private func arrowItem() -> ArrowItem {
        ArrowItem(id: ItemId(), color: RGBA(r: 0, g: 0, b: 1, a: 0.5), width: 10,
                  transform: .identity, tail: Point(x: 0, y: 0), head: Point(x: 100, y: 0),
                  createdAt: 1)
    }

    @Test func sharedAccessors() {
        let item = CanvasItem.arrow(arrowItem())
        #expect(item.color == RGBA(r: 0, g: 0, b: 1, a: 0.5))
        #expect(item.transform == .identity)
        let recolored = item.withColor(RGBA(r: 1, g: 0, b: 0, a: 1))
        #expect(recolored.color == RGBA(r: 1, g: 0, b: 0, a: 1))
    }

    @Test func worldAABBCoversHead() {
        let box = SelectionMath.worldAABB(of: .arrow(arrowItem()))
        #expect(box != nil)
        // barb half-span 26 -> vertical extent +/-26 around the axis at y=0
        #expect(abs(box!.y + 26) < 1e-6)
        #expect(abs(box!.height - 52) < 1e-6)
    }

    @Test func hitTestInsideAndOutside() {
        let id = ItemId()
        let items: [ItemId: CanvasItem] = [id: .arrow(arrowItem())]
        let hitShaft = SelectionMath.hitTestItem(at: Point(x: 30, y: 0), items: items,
                                                 order: [id], tolerance: 0)
        #expect(hitShaft == id)
        let miss = SelectionMath.hitTestItem(at: Point(x: 30, y: 40), items: items,
                                             order: [id], tolerance: 0)
        #expect(miss == nil)
    }
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `just test`
Expected: FAIL, `type 'CanvasItem' has no member 'arrow'`.

- [ ] **Step 3: Implement**

In `Sources/Core/Model/CanvasItem.swift`, add the case and extend every `switch`:

```swift
public enum CanvasItem: Equatable, Codable, Sendable {
    case stroke(Stroke)
    case text(TextItem)
    case arrow(ArrowItem)
    // id / createdAt / color / transform get+set / withColor: add a `case .arrow(let a)` /
    // `case .arrow(var a)` arm to each, mirroring the stroke arms.
}
```

In `Sources/Core/Selection/SelectionMath.swift`:
- `worldAABB(of:)`: add `case .arrow(let a): return arrowAABB(a)`.
- `hitTestItem`: add `case .arrow(let a): if pointInArrow(point, arrow: a) { return id }`.
- Add private helpers that transform the local outline through the item transform using the same convention as `textWorldCorners` (rotate `scale * local`, then translate by `x,y`):

```swift
private static func worldOutline(_ a: ArrowItem) -> [Point] {
    let local = ArrowGeometry.outline(tail: a.tail, head: a.head, width: a.width)
    let cosθ = cos(a.transform.rotate * .pi / 180.0)
    let sinθ = sin(a.transform.rotate * .pi / 180.0)
    return local.map { p in
        let sx = p.x * a.transform.scale, sy = p.y * a.transform.scale
        return Point(x: sx * cosθ - sy * sinθ + a.transform.x,
                     y: sx * sinθ + sy * cosθ + a.transform.y)
    }
}

private static func arrowAABB(_ a: ArrowItem) -> Rect? {
    let pts = worldOutline(a)
    guard let first = pts.first else { return nil }
    var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
    for p in pts.dropFirst() {
        minX = min(minX, p.x); maxX = max(maxX, p.x)
        minY = min(minY, p.y); maxY = max(maxY, p.y)
    }
    return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}

private static func pointInArrow(_ point: Point, arrow a: ArrowItem) -> Bool {
    let poly = worldOutline(a)
    guard poly.count >= 3 else { return false }
    var inside = false
    var j = poly.count - 1
    for i in 0..<poly.count {
        let pi = poly[i], pj = poly[j]
        if (pi.y > point.y) != (pj.y > point.y) {
            let x = (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x
            if point.x < x { inside.toggle() }
        }
        j = i
    }
    return inside
}
```

In `Sources/AppKit/StrokeDrawing.swift`, `drawItem`:

```swift
public func drawItem(_ item: CanvasItem, in ctx: CGContext, isInProgress: Bool) {
    switch item {
    case .stroke(let s): drawStroke(s, in: ctx, isInProgress: isInProgress)
    case .text(let t): drawText(t, in: ctx)
    case .arrow(let a): drawArrow(a, in: ctx, isInProgress: isInProgress)
    }
}
```

In `Sources/AppKit/CanvasView.swift`, `contentTag(for:)` add:

```swift
case .arrow(let a):
    var hasher = Hasher()
    hasher.combine(a.color.r); hasher.combine(a.color.g)
    hasher.combine(a.color.b); hasher.combine(a.color.a)
    hasher.combine(a.width)
    hasher.combine(a.tail.x); hasher.combine(a.tail.y)
    hasher.combine(a.head.x); hasher.combine(a.head.y)
    return hasher.finalize()
```

In `Sources/AppKit/GroupCompositor.swift`, `inkPad(_:)` add:

```swift
case .arrow(let a):
    return a.width * linearScale(a.transform) + 1
```

- [ ] **Step 4: Run and watch it pass**

Run: `just check`
Expected: PASS (Core tests, AppKit build, lint all green).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Model/CanvasItem.swift Sources/Core/Selection/SelectionMath.swift \
        Sources/AppKit/StrokeDrawing.swift Sources/AppKit/CanvasView.swift \
        Sources/AppKit/GroupCompositor.swift Tests/CoreTests/CanvasItemArrowTests.swift
git commit -m "$(cat <<'EOF'
Core+AppKit: CanvasItem.arrow case wired through bounds, hit-test, draw

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Editor transient arrow

The in-progress arrow lives in `Editor` as a transient (not in the doc, so undo is clean), reachable from `RenderFrame.from`. It commits atomically on `commitArrow`.

**Files:**
- Modify: `Sources/Core/Editor/Editor.swift`
- Test: `Tests/CoreTests/EditorArrowTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ABOUTME: Editor transient arrow lifecycle: begin/update/commit/cancel.
// ABOUTME: Commit adds exactly one undoable item; cancel leaves the doc untouched.

import Testing
@testable import Core

@Suite struct EditorArrowTests {
    @MainActor private func editor() -> Editor {
        Editor(clock: FixedClock(now: 0), ids: SequentialIds())   // use the test doubles in Tests/CoreTests
    }

    @MainActor @Test func beginUpdateCommit() {
        let e = editor()
        _ = e.beginArrow(color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 8, tail: Point(x: 0, y: 0))
        #expect(e.currentArrow != nil)
        e.updateArrowHead(to: Point(x: 50, y: 0))
        #expect(e.currentArrow?.head == Point(x: 50, y: 0))
        let id = e.commitArrow()
        #expect(id != nil)
        #expect(e.currentArrow == nil)
        #expect(e.doc.itemOrder.count == 1)
        #expect(e.canUndo)
        _ = e.undo()
        #expect(e.doc.itemOrder.isEmpty)
    }

    @MainActor @Test func cancelDiscards() {
        let e = editor()
        _ = e.beginArrow(color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 8, tail: Point(x: 0, y: 0))
        e.updateArrowHead(to: Point(x: 50, y: 0))
        e.cancelArrow()
        #expect(e.currentArrow == nil)
        #expect(e.doc.itemOrder.isEmpty)
        #expect(!e.canUndo)
    }
}
```

(Use the existing `Tests/CoreTests` clock/id doubles; match their actual names.)

- [ ] **Step 2: Run and watch it fail**

Run: `just test`
Expected: FAIL, `value of type 'Editor' has no member 'beginArrow'`.

- [ ] **Step 3: Implement** in `Sources/Core/Editor/Editor.swift`

```swift
public private(set) var currentArrow: ArrowItem?

@discardableResult
public func beginArrow(color: RGBA, width: Double, tail: Point) -> ItemId {
    let id = ids.newItemId()
    currentArrow = ArrowItem(id: id, color: color, width: width, transform: .identity,
                             tail: tail, head: tail, createdAt: clock.now())
    emit(.local)
    return id
}

public func updateArrowHead(to head: Point) {
    guard var a = currentArrow else { return }
    a.head = head
    currentArrow = a
    emit(.local)
}

@discardableResult
public func commitArrow() -> ItemId? {
    guard let a = currentArrow else { return nil }
    currentArrow = nil
    addItem(.arrow(a))   // pushes its own undo entry and emits
    return a.id
}

public func cancelArrow() {
    guard currentArrow != nil else { return }
    currentArrow = nil
    emit(.local)
}
```

(Confirm `addItem` pushes an undo entry and emits; if `addItem` does not emit on its own, the existing tests for it will show the pattern.)

- [ ] **Step 4: Run and watch it pass**

Run: `just test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Editor/Editor.swift Tests/CoreTests/EditorArrowTests.swift
git commit -m "$(cat <<'EOF'
Core: Editor transient arrow (begin/update/commit/cancel)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Generalize the in-progress render slot to CanvasItem

`RenderFrame.inProgress` is typed `Stroke?`; widen it to `CanvasItem?` so the same live-flatten path draws an in-progress arrow. The pen path is unchanged (it supplies `.stroke(...)`). This commit spans Core and AppKit.

**Files:**
- Modify: `Sources/Core/Ports/RenderFrame.swift`
- Modify: `Sources/Core/Editor/RenderFrame+from.swift`
- Modify: `Sources/AppKit/CanvasView.swift` (`renderSplit`, `draw` guard, `drawLiveGroup`)
- Test: `Tests/CoreTests/RenderFrameArrowTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ABOUTME: RenderFrame.from surfaces the in-progress item: a pen stroke as .stroke,
// ABOUTME: an Editor transient arrow as .arrow.

import Testing
@testable import Core

@Suite struct RenderFrameArrowTests {
    @MainActor @Test func surfacesInProgressArrow() {
        let e = Editor(clock: FixedClock(now: 0), ids: SequentialIds())
        _ = e.beginArrow(color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 8, tail: Point(x: 0, y: 0))
        e.updateArrowHead(to: Point(x: 40, y: 0))
        let frame = RenderFrame.from(editor: e, canvasSize: Size(width: 100, height: 100))
        guard case .arrow(let a)? = frame.inProgress else {
            Issue.record("expected an in-progress arrow"); return
        }
        #expect(a.head == Point(x: 40, y: 0))
        #expect(frame.items.isEmpty)   // transient, not in the committed set
    }
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `just test`
Expected: FAIL (type mismatch: `inProgress` is `Stroke?`, or the arrow is not surfaced).

- [ ] **Step 3: Implement**

In `Sources/Core/Ports/RenderFrame.swift`, change the field and initializer:

```swift
public var inProgress: CanvasItem?   // pen stroke or arrow being actively drawn, drawn live
// update init signature: inProgress: CanvasItem?
```

In `Sources/Core/Editor/RenderFrame+from.swift`, build it from whichever transient is active:

```swift
let inProgress: CanvasItem? = {
    if let id = editor.currentStrokeId, case .stroke(let s)? = editor.doc.items[id] {
        return .stroke(s)
    }
    if let a = editor.currentArrow { return .arrow(a) }
    return nil
}()
```

In `Sources/AppKit/CanvasView.swift`:
- `renderSplit`: `LayerPlan.compute(items: committed + [.stroke(live)], ...)` becomes `committed + [live]` (live is now a `CanvasItem`). `live.id` already works.
- `draw(_:)` guard at the live-group call: replace `if let live = frame.inProgress, !live.points.isEmpty` with a generic drawable check:

```swift
if let live = frame.inProgress, isLiveDrawable(live) {
    drawLiveGroup(live, frame: frame, in: ctx)   // still wrapped in the PerfLog.measure in DEBUG
}
```

Add the helper:

```swift
private func isLiveDrawable(_ item: CanvasItem) -> Bool {
    switch item {
    case .stroke(let s): return !s.points.isEmpty
    case .arrow(let a): return a.tail != a.head
    case .text: return false
    }
}
```

- `drawLiveGroup(_ live: Stroke, ...)` becomes `drawLiveGroup(_ live: CanvasItem, ...)`, and the opaque draw `drawItem(CanvasItem.stroke(live).withAlpha(1), ...)` becomes `drawItem(live.withAlpha(1), ...)`.

- [ ] **Step 4: Run and watch it pass**

Run: `just check`
Expected: PASS. Existing pen and flatten tests still green (pen behavior unchanged).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Ports/RenderFrame.swift Sources/Core/Editor/RenderFrame+from.swift \
        Sources/AppKit/CanvasView.swift Tests/CoreTests/RenderFrameArrowTests.swift
git commit -m "$(cat <<'EOF'
Core+AppKit: in-progress render slot generalized to CanvasItem

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Arrow tool selection and gesture (Tool enum ripple)

Add `Tool.arrow`, bind `a`, route the three pointer phases to a new arrow handler, and update the `Tool` switches in the AppKit adapters so `just check` stays green.

**Files:**
- Modify: `Sources/Core/Model/Tool.swift`
- Modify: `Sources/Core/Control/KeyCommand.swift`
- Modify: `Sources/Core/Control/AppController.swift` (route `.arrow` in `pointerDown/Moved/Up`; add a `minArrowLength` constant)
- Create: `Sources/Core/Control/AppController+ArrowTool.swift`
- Modify: `Sources/AppKit/ToolbarController.swift`, `Sources/AppKit/CursorRenderer.swift` (handle `.arrow` in any exhaustive `Tool` switch; the toolbar button glyph is Task 8, here just keep switches exhaustive)
- Test: `Tests/CoreTests/ArrowToolTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ABOUTME: Arrow tool: key binding resolves to selectTool(.arrow), and the pointer
// ABOUTME: gesture commits exactly one arrow (discarding a sub-minimum-length drag).

import Testing
@testable import Core

@Suite struct ArrowToolTests {
    @Test func keyBindingResolves() {
        #expect(KeyCommandRegistry.command(for: KeyBinding(character: "a")) == .selectTool(.arrow))
    }

    @MainActor @Test func dragCommitsOneArrow() {
        let app = makeActiveAppController()   // mirror the harness used by pen/text tool tests
        app.currentTool = .arrow
        app.pointerDown(StrokePoint(x: 0, y: 0, pressure: 0))
        app.pointerMoved(StrokePoint(x: 120, y: 0, pressure: 0))
        app.pointerUp()
        let items = app.editor.doc.itemOrder.compactMap { app.editor.doc.items[$0] }
        #expect(items.count == 1)
        if case .arrow(let a) = items[0] {
            #expect(a.tail == Point(x: 0, y: 0))
            #expect(a.head == Point(x: 120, y: 0))
        } else {
            Issue.record("expected an arrow item")
        }
    }

    @MainActor @Test func subMinimumDragDiscards() {
        let app = makeActiveAppController()
        app.currentTool = .arrow
        app.pointerDown(StrokePoint(x: 0, y: 0, pressure: 0))
        app.pointerMoved(StrokePoint(x: 1, y: 0, pressure: 0))
        app.pointerUp()
        #expect(app.editor.doc.itemOrder.isEmpty)
    }
}
```

(Match `makeActiveAppController` to the existing tool-test harness in `Tests/CoreTests`.)

- [ ] **Step 2: Run and watch it fail**

Run: `just test`
Expected: FAIL, `type 'Tool' has no member 'arrow'`.

- [ ] **Step 3: Implement**

`Sources/Core/Model/Tool.swift`: add `case arrow`.

`Sources/Core/Control/KeyCommand.swift`: add `KeyBinding(character: "a"): .selectTool(.arrow)` to `bindings`.

`Sources/Core/Control/AppController.swift`: add `.arrow` arms to the three pointer switches:

```swift
// pointerDown switch
case .arrow:
    if !selectedItemIds.isEmpty { selectedItemIds = [] }
    arrowPointerDown(point)
// pointerMoved switch
case .arrow: arrowPointerMoved(point)
// pointerUp switch
case .arrow: arrowPointerUp()
```

Add a constant near the other gesture constants: `let minArrowLengthFactor = 2.0` (minimum length is `currentWidth * minArrowLengthFactor`).

Create `Sources/Core/Control/AppController+ArrowTool.swift`:

```swift
// ABOUTME: Arrow-tool pointer routing. Straight from the first move: tail at down,
// ABOUTME: head rubber-bands to the cursor, commit on up if past the minimum length.

import Foundation

extension AppController {
    func arrowPointerDown(_ point: StrokePoint) {
        guard mode == .activeIdle else { return }
        _ = editor.beginArrow(color: currentColor, width: currentWidth,
                              tail: Point(x: point.x, y: point.y))
        mode = .activeDrawing
    }

    func arrowPointerMoved(_ point: StrokePoint) {
        guard mode == .activeDrawing else { return }
        editor.updateArrowHead(to: Point(x: point.x, y: point.y))
    }

    func arrowPointerUp() {
        guard mode == .activeDrawing else { return }
        defer { mode = .activeIdle }
        guard let a = editor.currentArrow else { return }
        let dx = a.head.x - a.tail.x, dy = a.head.y - a.tail.y
        if (dx * dx + dy * dy).squareRoot() >= currentWidth * minArrowLengthFactor {
            _ = editor.commitArrow()
        } else {
            editor.cancelArrow()
        }
    }
}
```

`Sources/AppKit/ToolbarController.swift` and `Sources/AppKit/CursorRenderer.swift`: add a `.arrow` arm to any exhaustive `switch tool` so the build compiles. For the cursor, reuse the pen/crosshair cursor for now; the dedicated glyph and the toolbar button visual land in Task 8.

- [ ] **Step 4: Run and watch it pass**

Run: `just check`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Model/Tool.swift Sources/Core/Control/KeyCommand.swift \
        Sources/Core/Control/AppController.swift Sources/Core/Control/AppController+ArrowTool.swift \
        Sources/AppKit/ToolbarController.swift Sources/AppKit/CursorRenderer.swift \
        Tests/CoreTests/ArrowToolTests.swift
git commit -m "$(cat <<'EOF'
Core: arrow tool (a key + pointer gesture, straight from the start)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Toolbar button and tool cursor

Give the arrow tool a toolbar button beside pen and text, the active-tool indication the others have, and a tool cursor.

**Files:**
- Modify: `Sources/AppKit/ToolbarController.swift` (button, following the pen/text button pattern)
- Modify: `Sources/AppKit/CursorRenderer.swift` (arrow-tool cursor)
- Test: extend the existing toolbar/cursor test if one exists in `Tests/AppKitTests`; otherwise this is verified by `just check` plus a manual inspect pass.

- [ ] **Step 1: Write the failing test (if a toolbar/cursor test target exists)**

If `Tests/AppKitTests` already asserts the toolbar exposes pen/text buttons or that `CursorRenderer` maps each `Tool`, add the `.arrow` assertion there first and watch it fail. If no such test exists, skip to Step 3 and rely on `just check` plus the manual verification in Step 4 (do not invent a brittle snapshot test).

- [ ] **Step 2: Run and watch it fail** (only if Step 1 added a test)

Run: `just test-integration`

- [ ] **Step 3: Implement**

- Add an arrow button to `ToolbarController` mirroring the pen and text buttons: same sizing, same selected-state styling, target/action sets `currentTool = .arrow`. Use an SF Symbol such as `arrow.up.right` or `line.diagonal.arrow` for the glyph (menu/toolbar SF Symbol use is allowed).
- In `CursorRenderer`, return a crosshair-style cursor for `.arrow` (reuse the pen cursor if that is what pen uses).
- Confirm the active-tool highlight updates when `a` selects the tool (the toolbar already observes tool changes for pen/text; extend that wiring to include the arrow button).

- [ ] **Step 4: Verify**

Run: `just check`
Then a manual pass: `just run-bg`, `just inspect-activate`, then exercise the tool and confirm the button highlights and the cursor is correct:

```
just inspect-pointer down 200 200
just inspect-pointer move 500 260
just inspect-pointer up 500 260
just inspect-screenshot
```

Confirm the screenshot shows one arrow with the head at the lift point. `just stop` when done.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/ToolbarController.swift Sources/AppKit/CursorRenderer.swift
git commit -m "$(cat <<'EOF'
AppKit: arrow toolbar button and tool cursor

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Arrow flattening and WYSIWYG pixel tests

Verify arrows participate in `(hue, alpha)` flattening and that the live in-progress arrow is pixel-identical to the committed result. The production paths already route arrows through `GroupCompositor` (Task 4) and the live-group engine (Task 6); this task locks the behavior with tests, matching the structure of the existing opacity-flattening tests.

**Files:**
- Test: `Tests/AppKitTests/ArrowFlattenTests.swift`
- Modify (only if a test reveals a gap): `Sources/AppKit/GroupCompositor.swift` or `Sources/AppKit/CanvasView.swift`

- [ ] **Step 1: Write the tests**

Follow `Tests/AppKitTests/CanvasViewBakeTests.swift` (offscreen bake, pixel sampling). Cover:

```swift
// ABOUTME: Arrows flatten like strokes: same-color overlaps read flat, cross-color
// ABOUTME: preserves z-order, and the live in-progress arrow matches the committed bake.

// 1. Two overlapping same-color 50% arrows: the overlap equals a single arm (flat, not darker).
// 2. A same-color arrow crossing a same-color stroke: overlap is flat.
// 3. A different-color mark drawn over the arrow shows on top (z-order preserved).
// 4. WYSIWYG: render a committed same-color mark plus an in-progress crossing arrow via the
//    live path, and the same two items both committed via the bake; the intersection pixel
//    matches between the two renders (reuse the dual-render helper from the opacity tests).
```

- [ ] **Step 2: Run**

Run: `just test-integration`
Expected: ideally PASS straight away (the plumbing exists). If the WYSIWYG case fails, diagnose against the opacity-flattening design's live path before changing production code; fix the smallest gap (for example an arrow-specific clip pad in `GroupCompositor`).

- [ ] **Step 3: Commit**

```bash
git add Tests/AppKitTests/ArrowFlattenTests.swift
# add any production file only if a real gap was fixed
git commit -m "$(cat <<'EOF'
AppKit: arrow flattening + WYSIWYG live pixel tests

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: Documentation

**Files:**
- Modify: `docs/fiti-roadmap.md` (move the arrow tool from the open Shape-tools section to Shipped, summarizing what landed)
- Modify: `docs/architecture.md` (a short Arrow tool note: `ArrowItem`, pure `ArrowGeometry`, shared `drawArrow`, flattening + WYSIWYG via the existing engine)
- Modify: `docs/perf-baseline.md` (one line: the live in-progress arrow uses the same per-frame path as the pen and is no more expensive; a cheaper fill)

- [ ] **Step 1: Edit the docs**

No emojis, em dashes, or hyperbole. Keep the roadmap Shipped entry in the same style as the existing Shipped items (what shipped, key files). Note the inherited known limitations from the opacity-flattening design (cross-hue conflict, AABB conservatism) apply to arrows too.

- [ ] **Step 2: Verify**

Run: `just check`
Expected: PASS (lint includes doc-adjacent checks only for source; docs just need to not break the build).

- [ ] **Step 3: Commit**

```bash
git add docs/fiti-roadmap.md docs/architecture.md docs/perf-baseline.md
git commit -m "$(cat <<'EOF'
docs: arrow tool shipped (roadmap, architecture, perf note)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Self-review notes

- **Spec coverage:** straight-from-start interaction (Tasks 5, 7), single head at the lift point (Task 1 model, Task 2 geometry), rounded swept head + subtle taper (Task 2 constants, Task 3 rounding), head scales with width (Task 2 factors), first-class `CanvasItem` for free selection/transform/restyle/undo (Task 4), opacity flattening + full WYSIWYG live (Tasks 4, 6, 9), `a` key + toolbar button + cursor (Tasks 7, 8), non-goals (double head, angle snap, detection, hold-to-straighten) are simply not implemented. Covered.
- **Enum ripples are explicit:** `CanvasItem.arrow` (Task 4) and `Tool.arrow` (Task 7) each update every exhaustive switch in one commit so `just check` stays green.
- **Type consistency:** `ArrowGeometry.outline(tail:head:width:)`, `drawArrow(_:in:isInProgress:)`, `Editor.beginArrow/updateArrowHead/commitArrow/cancelArrow`, `RenderFrame.inProgress: CanvasItem?`, and the `AppController.arrowPointerDown/Moved/Up` names are used consistently across tasks.
- **Open verification points for the implementer:** the AppKit test target module name, the `Tests/CoreTests` clock/id/app-controller test doubles, whether `Editor.addItem` emits on its own, and whether a toolbar/cursor test target exists. Each is flagged at its task. None changes the design.
