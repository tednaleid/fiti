# Selection Manipulation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the selection tool fully manipulable — region-first pointer routing (fixes the multi-select drag bug), translate/uniform-resize/rigid-rotate via corner + rotate-node handles, a persistent oriented selection box, hover cursors, transient Space-held lifetime, and tool-gated Delete.

**Architecture:** All decisions live in pure `Sources/Core/` units tested without drawing — `OrientedBox` (geometry), `SelectionMath.region` (hit classification), `SelectionRegion` + `cursorFor` (cursor policy), `SelectionTransforms` (gesture math). `AppController` holds session state (`selectionBox`, `lastHoverPoint`) and routes pointers. AppKit is reduced to `NSCursor` lookup (`CursorRenderer`) and pixel drawing (`CanvasView`). Source of truth: `docs/specs/2026-05-21-fiti-selection-manipulation-design.md`.

**Tech Stack:** Swift 6, Swift Testing (`import Testing`, `@Test`, `@Suite`, `#expect`), AppKit (adapters only), no SwiftUI.

**Conventions for every task:** Two `// ABOUTME:` lines at the top of each new Swift file. `Sources/Core/` must not import AppKit/CoreGraphics/Network/SwiftUI. Run `just check` before each commit (the pre-commit hook runs it; never `--no-verify`). Every commit message uses a HEREDOC ending with `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` — commit steps below show the subject line only for brevity. Test files for `Sources/Core/Selection/X.swift` go under `Tests/CoreTests/SelectionTests/`.

---

## File map

| File | Responsibility | Task |
| --- | --- | --- |
| `Sources/Core/Model/Point.swift` | 2D point value (`x`, `y`) | create (1) |
| `Sources/Core/Selection/OrientedBox.swift` | oriented box value + `corners`/`rotateNode`/`toLocal` | create (1) |
| `Sources/Core/Selection/SelectionRegion.swift` | `Corner` + `SelectionRegion` enums; `cursorFor(...)` policy | create (2, 5) |
| `Sources/Core/Selection/SelectionMath.swift` | add `region(at:box:...)` | modify (2) |
| `Sources/Core/Selection/SelectionTransforms.swift` | translate / resize / rotate gesture math | create (3) |
| `Sources/Core/Model/CursorSpec.swift` | refactor struct → `brush`/`system` enum; add `SystemCursor` | modify (4) |
| `Sources/AppKit/CursorRenderer.swift` | `CursorSpec`/`SystemCursor` → `NSCursor` | modify (4, 10) |
| `Sources/Core/Control/AppController.swift` | `selectionBox`, `lastHoverPoint`, `pointerHover`, hover-aware `currentCursor`, transient lifetime | modify (6, 9) |
| `Sources/Core/Control/AppController+SelectionGesture.swift` | region-first `pointerDown`; resize/rotate gestures | modify (7, 8) |
| `Sources/Core/Control/AppController+Commands.swift` | tool-gated `run(.clear)` | modify (9) |
| `Sources/AppKit/CanvasView.swift` | `setSelectionBox(OrientedBox?)` + oriented chrome | modify (11) |
| `Sources/AppKit/NSEventInputSource.swift` | forward `mouseMoved` → hover | modify (11) |
| `Sources/App/main.swift` | publish/consume `OrientedBox`; wire hover; revert Esc | modify (9, 11) |

---

### Task 1: `Point` value + `OrientedBox`

**Files:**
- Create: `Sources/Core/Model/Point.swift`
- Create: `Sources/Core/Selection/OrientedBox.swift`
- Test: `Tests/CoreTests/SelectionTests/OrientedBoxTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/SelectionTests/OrientedBoxTests.swift`:

```swift
// ABOUTME: Tests for OrientedBox geometry — corners, rotate node, and the
// ABOUTME: world↔local round-trip at rotation 0 and non-zero.

import Testing

@Suite("OrientedBox")
struct OrientedBoxTests {
    private func approx(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) <= eps }

    @Test("corners at rotation 0 are center ± half-size, ordered TL/TR/BR/BL")
    func cornersUnrotated() {
        let box = OrientedBox(center: Point(x: 100, y: 100), size: Size(width: 40, height: 20), rotation: 0)
        let c = box.corners()
        #expect(approx(c[0].x, 80) && approx(c[0].y, 90))   // topLeft
        #expect(approx(c[1].x, 120) && approx(c[1].y, 90))  // topRight
        #expect(approx(c[2].x, 120) && approx(c[2].y, 110)) // bottomRight
        #expect(approx(c[3].x, 80) && approx(c[3].y, 110))  // bottomLeft
    }

    @Test("rotateNode at rotation 0 sits above the top-edge midpoint")
    func rotateNodeUnrotated() {
        let box = OrientedBox(center: Point(x: 100, y: 100), size: Size(width: 40, height: 20), rotation: 0)
        let n = box.rotateNode(offset: 20)
        #expect(approx(n.x, 100) && approx(n.y, 70))  // top edge y=90, minus 20
    }

    @Test("toLocal is the inverse of the world placement (round-trip)")
    func toLocalRoundTrip() {
        let box = OrientedBox(center: Point(x: 50, y: 50), size: Size(width: 30, height: 30), rotation: 30)
        // A world corner maps back to its local position (±halfW, ±halfH).
        let worldTL = box.corners()[0]
        let local = box.toLocal(worldTL)
        #expect(approx(local.x, -15) && approx(local.y, -15))
    }

    @Test("90° rotation sends the local top edge to the right side")
    func rotated90() {
        let box = OrientedBox(center: Point(x: 0, y: 0), size: Size(width: 20, height: 20), rotation: 90)
        // local topLeft (-10,-10) rotates +90 (y-down screen) → (10,-10).
        let c = box.corners()[0]
        #expect(approx(c.x, 10) && approx(c.y, -10))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: compile failure — `Point` and `OrientedBox` not found.

- [ ] **Step 3: Create `Point`**

Create `Sources/Core/Model/Point.swift`:

```swift
// ABOUTME: Plain 2D point in logical canvas coordinates. Distinct from
// ABOUTME: StrokePoint (which carries pressure); used by selection geometry.

import Foundation

public struct Point: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}
```

- [ ] **Step 4: Create `OrientedBox`**

Create `Sources/Core/Selection/OrientedBox.swift`:

```swift
// ABOUTME: A selection box that can be rotated — center, local size, and a
// ABOUTME: rotation in degrees. Pure geometry; the renderer and hit-testing
// ABOUTME: read its corners / rotate node / world↔local transform.

import Foundation

public struct OrientedBox: Equatable, Sendable {
    public var center: Point
    public var size: Size
    public var rotation: Double  // degrees

    public init(center: Point, size: Size, rotation: Double) {
        self.center = center
        self.size = size
        self.rotation = rotation
    }

    private var halfW: Double { size.width / 2 }
    private var halfH: Double { size.height / 2 }

    /// World-space corners, ordered topLeft, topRight, bottomRight, bottomLeft
    /// (in a y-down screen coordinate system: top = smaller y).
    public func corners() -> [Point] {
        [Point(x: -halfW, y: -halfH),
         Point(x:  halfW, y: -halfH),
         Point(x:  halfW, y:  halfH),
         Point(x: -halfW, y:  halfH)].map(worldFromLocal)
    }

    /// World-space center of the rotate node, `offset` above the top-edge midpoint.
    public func rotateNode(offset: Double) -> Point {
        worldFromLocal(Point(x: 0, y: -halfH - offset))
    }

    /// Maps a world point into the box's local (unrotated, center-origin) frame.
    public func toLocal(_ p: Point) -> Point {
        let dx = p.x - center.x
        let dy = p.y - center.y
        let a = -rotation * .pi / 180
        let c = cos(a), s = sin(a)
        return Point(x: dx * c - dy * s, y: dx * s + dy * c)
    }

    private func worldFromLocal(_ p: Point) -> Point {
        let a = rotation * .pi / 180
        let c = cos(a), s = sin(a)
        return Point(x: center.x + p.x * c - p.y * s,
                     y: center.y + p.x * s + p.y * c)
    }
}
```

- [ ] **Step 5: Run to verify pass**

Run: `just check`
Expected: 4 new tests pass; lint clean; build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Model/Point.swift Sources/Core/Selection/OrientedBox.swift \
        Tests/CoreTests/SelectionTests/OrientedBoxTests.swift
git commit  # subject: "Core: Point value + OrientedBox geometry for selection chrome"
```

---

### Task 2: `SelectionRegion` + `SelectionMath.region`

**Files:**
- Create: `Sources/Core/Selection/SelectionRegion.swift`
- Modify: `Sources/Core/Selection/SelectionMath.swift`
- Test: `Tests/CoreTests/SelectionTests/SelectionRegionTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/SelectionTests/SelectionRegionTests.swift`:

```swift
// ABOUTME: Tests for SelectionMath.region — classifies a point against an
// ABOUTME: oriented box into rotateHandle / corner / body / outside.

import Testing

@Suite("SelectionMath.region")
struct SelectionRegionTests {
    private let box = OrientedBox(center: Point(x: 100, y: 100),
                                  size: Size(width: 40, height: 20), rotation: 0)

    @Test("nil box is always outside")
    func nilBox() {
        #expect(SelectionMath.region(at: Point(x: 100, y: 100), box: nil,
                                     handleRadius: 8, rotateNodeOffset: 20) == .outside)
    }

    @Test("point on the rotate node classifies as rotateHandle")
    func node() {
        let r = SelectionMath.region(at: Point(x: 100, y: 70), box: box,
                                     handleRadius: 8, rotateNodeOffset: 20)
        #expect(r == .rotateHandle)
    }

    @Test("points on each corner classify as that corner")
    func corners() {
        let hr = 8.0
        #expect(SelectionMath.region(at: Point(x: 80, y: 90), box: box, handleRadius: hr, rotateNodeOffset: 20) == .corner(.topLeft))
        #expect(SelectionMath.region(at: Point(x: 120, y: 90), box: box, handleRadius: hr, rotateNodeOffset: 20) == .corner(.topRight))
        #expect(SelectionMath.region(at: Point(x: 120, y: 110), box: box, handleRadius: hr, rotateNodeOffset: 20) == .corner(.bottomRight))
        #expect(SelectionMath.region(at: Point(x: 80, y: 110), box: box, handleRadius: hr, rotateNodeOffset: 20) == .corner(.bottomLeft))
    }

    @Test("interior is body, far away is outside")
    func bodyAndOutside() {
        #expect(SelectionMath.region(at: Point(x: 100, y: 100), box: box, handleRadius: 8, rotateNodeOffset: 20) == .body)
        #expect(SelectionMath.region(at: Point(x: 500, y: 500), box: box, handleRadius: 8, rotateNodeOffset: 20) == .outside)
    }

    @Test("on a rotated box, the rotated top-left corner still classifies as topLeft")
    func rotatedCorner() {
        let rbox = OrientedBox(center: Point(x: 0, y: 0), size: Size(width: 20, height: 20), rotation: 90)
        // local topLeft (-10,-10) at rotation 90 (y-down) → world (10,-10).
        let r = SelectionMath.region(at: Point(x: 10, y: -10), box: rbox, handleRadius: 8, rotateNodeOffset: 20)
        #expect(r == .corner(.topLeft))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: compile failure — `SelectionRegion`, `Corner`, `region` not found.

- [ ] **Step 3: Create the enums**

Create `Sources/Core/Selection/SelectionRegion.swift`:

```swift
// ABOUTME: Region of an oriented selection box that a point falls in, plus
// ABOUTME: the pure cursor policy. Drives both hit-routing and hover cursors.

import Foundation

public enum Corner: Equatable, Sendable {
    case topLeft, topRight, bottomRight, bottomLeft
}

public enum SelectionRegion: Equatable, Sendable {
    case rotateHandle
    case corner(Corner)
    case body
    case outside
}
```

(The `cursorFor` policy is added to this file in Task 5.)

- [ ] **Step 4: Add `region` to `SelectionMath`**

Append to `Sources/Core/Selection/SelectionMath.swift` (inside the existing `extension`-free enum, add a new `public static func`):

```swift
    /// Classifies a world point against an oriented selection box.
    /// Precedence: rotate node, then corners, then interior, else outside.
    public static func region(at point: Point, box: OrientedBox?,
                              handleRadius: Double, rotateNodeOffset: Double) -> SelectionRegion {
        guard let box else { return .outside }
        let local = box.toLocal(point)
        let halfW = box.size.width / 2
        let halfH = box.size.height / 2

        let node = Point(x: 0, y: -halfH - rotateNodeOffset)
        if hypot(local.x - node.x, local.y - node.y) <= handleRadius { return .rotateHandle }

        let corners: [(Corner, Point)] = [
            (.topLeft, Point(x: -halfW, y: -halfH)),
            (.topRight, Point(x: halfW, y: -halfH)),
            (.bottomRight, Point(x: halfW, y: halfH)),
            (.bottomLeft, Point(x: -halfW, y: halfH)),
        ]
        for (corner, c) in corners where hypot(local.x - c.x, local.y - c.y) <= handleRadius {
            return .corner(corner)
        }

        if abs(local.x) <= halfW && abs(local.y) <= halfH { return .body }
        return .outside
    }
```

- [ ] **Step 5: Run to verify pass**

Run: `just check`
Expected: 6 new tests pass; lint clean.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Selection/SelectionRegion.swift Sources/Core/Selection/SelectionMath.swift \
        Tests/CoreTests/SelectionTests/SelectionRegionTests.swift
git commit  # subject: "Core: SelectionRegion enum + SelectionMath.region classifier"
```

---

### Task 3: `SelectionTransforms` gesture math

**Files:**
- Create: `Sources/Core/Selection/SelectionTransforms.swift`
- Test: `Tests/CoreTests/SelectionTests/SelectionTransformsTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/SelectionTests/SelectionTransformsTests.swift`:

```swift
// ABOUTME: Tests for SelectionTransforms — translate / resize / rotate gesture
// ABOUTME: math returning (OrientedBox, per-stroke transforms) from one delta.

import Testing

@Suite("SelectionTransforms")
struct SelectionTransformsTests {
    private func approx(_ a: Double, _ b: Double, _ eps: Double = 1e-6) -> Bool { abs(a - b) <= eps }
    private let box = OrientedBox(center: Point(x: 100, y: 100), size: Size(width: 40, height: 20), rotation: 0)

    @Test("translate shifts the box center and every stroke transform by the delta")
    func translate() {
        let starts: [StrokeId: Transform] = ["a": .identity, "b": Transform(x: 5, y: 5, scale: 1, rotate: 0)]
        let (b, t) = SelectionTransforms.translate(startBox: box, startTransforms: starts, dx: 10, dy: -4)
        #expect(approx(b.center.x, 110) && approx(b.center.y, 96))
        #expect(approx(t["a"]!.x, 10) && approx(t["a"]!.y, -4))
        #expect(approx(t["b"]!.x, 15) && approx(t["b"]!.y, 1))
    }

    @Test("resize scales uniformly with the opposite corner pinned")
    func resize() {
        // Box corners: TL(80,90) BR(120,110). Drag BR with anchor=TL.
        let anchor = Point(x: 80, y: 90)
        let startCorner = Point(x: 120, y: 110)  // dist to anchor = sqrt(40²+20²)
        let pointer = Point(x: 160, y: 130)       // doubled vector from anchor → factor 2
        let starts: [StrokeId: Transform] = ["a": Transform(x: 100, y: 100, scale: 1, rotate: 0)]
        let (b, t) = SelectionTransforms.resize(startBox: box, startTransforms: starts,
                                                anchor: anchor, startCorner: startCorner,
                                                pointer: pointer, minFactor: 0.05)
        #expect(approx(b.size.width, 80) && approx(b.size.height, 40))   // doubled
        #expect(approx(t["a"]!.scale, 2))
        // translate scales around the anchor: 80 + 2*(100-80) = 120 ; 90 + 2*(100-90)=110
        #expect(approx(t["a"]!.x, 120) && approx(t["a"]!.y, 110))
    }

    @Test("resize clamps to the floor so it cannot collapse")
    func resizeClamp() {
        let anchor = Point(x: 80, y: 90)
        let startCorner = Point(x: 120, y: 110)
        let pointer = anchor  // factor → 0
        let (b, _) = SelectionTransforms.resize(startBox: box, startTransforms: ["a": .identity],
                                                anchor: anchor, startCorner: startCorner,
                                                pointer: pointer, minFactor: 0.05)
        #expect(b.size.width > 0)  // did not collapse
    }

    @Test("rotate spins the box and every stroke around the shared center")
    func rotate() {
        let center = Point(x: 0, y: 0)
        let starts: [StrokeId: Transform] = ["a": Transform(x: 10, y: 0, scale: 1, rotate: 0)]
        let rbox = OrientedBox(center: center, size: Size(width: 20, height: 20), rotation: 0)
        // startPointer at angle 0, pointer at angle +90° (y-down → (0,10)).
        let (b, t) = SelectionTransforms.rotate(startBox: rbox, startTransforms: starts,
                                                center: center, startPointer: Point(x: 10, y: 0),
                                                pointer: Point(x: 0, y: 10), snap15: false)
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
        let (b, _) = SelectionTransforms.rotate(startBox: rbox, startTransforms: ["a": .identity],
                                                center: center, startPointer: Point(x: 10, y: 0),
                                                pointer: Point(x: 10, y: 1.763), snap15: true)  // atan2(1.763,10)≈10°
        #expect(approx(b.rotation, 15, 1e-3))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: compile failure — `SelectionTransforms` not found.

- [ ] **Step 3: Create `SelectionTransforms`**

Create `Sources/Core/Selection/SelectionTransforms.swift`:

```swift
// ABOUTME: Pure gesture math for the selection tool — translate, uniform
// ABOUTME: resize (opposite-corner anchor), and rigid rotate around center.
// ABOUTME: Each returns the updated box and per-stroke transforms from one delta.

import Foundation

public enum SelectionTransforms {
    public static func translate(startBox: OrientedBox, startTransforms: [StrokeId: Transform],
                                 dx: Double, dy: Double) -> (OrientedBox, [StrokeId: Transform]) {
        var box = startBox
        box.center = Point(x: startBox.center.x + dx, y: startBox.center.y + dy)
        var out: [StrokeId: Transform] = [:]
        for (id, t) in startTransforms {
            out[id] = Transform(x: t.x + dx, y: t.y + dy, scale: t.scale, rotate: t.rotate)
        }
        return (box, out)
    }

    public static func resize(startBox: OrientedBox, startTransforms: [StrokeId: Transform],
                              anchor: Point, startCorner: Point, pointer: Point,
                              minFactor: Double) -> (OrientedBox, [StrokeId: Transform]) {
        let startDist = hypot(startCorner.x - anchor.x, startCorner.y - anchor.y)
        let nowDist = hypot(pointer.x - anchor.x, pointer.y - anchor.y)
        let s = startDist == 0 ? 1 : max(minFactor, nowDist / startDist)

        var box = startBox
        box.size = Size(width: startBox.size.width * s, height: startBox.size.height * s)
        box.center = Point(x: anchor.x + s * (startBox.center.x - anchor.x),
                           y: anchor.y + s * (startBox.center.y - anchor.y))

        var out: [StrokeId: Transform] = [:]
        for (id, t) in startTransforms {
            out[id] = Transform(x: anchor.x + s * (t.x - anchor.x),
                                y: anchor.y + s * (t.y - anchor.y),
                                scale: t.scale * s, rotate: t.rotate)
        }
        return (box, out)
    }

    public static func rotate(startBox: OrientedBox, startTransforms: [StrokeId: Transform],
                              center: Point, startPointer: Point, pointer: Point,
                              snap15: Bool) -> (OrientedBox, [StrokeId: Transform]) {
        let a0 = atan2(startPointer.y - center.y, startPointer.x - center.x)
        let a1 = atan2(pointer.y - center.y, pointer.x - center.x)
        var deg = (a1 - a0) * 180 / .pi
        if snap15 { deg = (deg / 15).rounded() * 15 }

        var box = startBox
        box.rotation = startBox.rotation + deg

        let rad = deg * .pi / 180
        let c = cos(rad), s = sin(rad)
        var out: [StrokeId: Transform] = [:]
        for (id, t) in startTransforms {
            let dx = t.x - center.x
            let dy = t.y - center.y
            out[id] = Transform(x: center.x + dx * c - dy * s,
                                y: center.y + dx * s + dy * c,
                                scale: t.scale, rotate: t.rotate + deg)
        }
        return (box, out)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `just check`
Expected: 5 new tests pass; lint clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Selection/SelectionTransforms.swift \
        Tests/CoreTests/SelectionTests/SelectionTransformsTests.swift
git commit  # subject: "Core: SelectionTransforms — translate/resize/rotate gesture math"
```

---

### Task 4: `CursorSpec` struct→enum refactor (atomic with call sites)

This task changes a public type and must update every construction site in one commit so the build stays green.

**Files:**
- Modify: `Sources/Core/Model/CursorSpec.swift`
- Modify: `Sources/Core/Control/AppController.swift:144-148` (`currentCursor`)
- Modify: `Sources/AppKit/CursorRenderer.swift`
- Modify: any test that constructs `CursorSpec(color:diameter:)` (find with grep in Step 1)
- Test: `Tests/CoreTests/AppControllerTests/` existing cursor tests (update to enum)

- [ ] **Step 1: Inventory call sites**

Run: `grep -rn "CursorSpec(" Sources/ Tests/`
Note every site. Expected: `AppController.currentCursor`, `CursorRenderer`, and any cursor-emission tests.

- [ ] **Step 2: Refactor `CursorSpec` to an enum**

Replace `Sources/Core/Model/CursorSpec.swift` body:

```swift
// ABOUTME: Semantic cursor the AppKit adapter renders into an NSCursor. Core
// ABOUTME: expresses intent (.brush for pen, .system for selection); the
// ABOUTME: adapter maps it to a platform cursor.

import Foundation

public enum SystemCursor: Equatable, Sendable {
    case arrow, openHand, closedHand
    case resize(angle: Double)   // screen-space angle in {0,45,90,135}; adapter picks the platform cursor
    case rotate
}

public enum CursorSpec: Equatable, Sendable {
    case brush(color: RGBA, diameter: Double)
    case system(SystemCursor)

    /// Outline color contrasting with a brush fill (BT.601 luminance on RGB).
    public static func outlineColor(for fill: RGBA) -> RGBA {
        let luminance = 0.299 * fill.r + 0.587 * fill.g + 0.114 * fill.b
        return luminance > 0.5
            ? RGBA(r: 0, g: 0, b: 0, a: 0.5)
            : RGBA(r: 1, g: 1, b: 1, a: 0.5)
    }
}
```

- [ ] **Step 3: Update `AppController.currentCursor`**

In `Sources/Core/Control/AppController.swift`, replace the `currentCursor` body (lines ~144-148):

```swift
    public var currentCursor: CursorSpec? {
        if mode == .inactive { return nil }
        if currentTool == .selection { return .system(.arrow) }
        return .brush(color: currentColor, diameter: currentWidth)
    }
```

(Task 6 makes the `.selection` branch hover-aware; for now it returns the plain arrow, matching prior behavior.)

- [ ] **Step 4: Update `CursorRenderer` to switch on the enum**

In `Sources/AppKit/CursorRenderer.swift`, replace `makeCursor(for:)` and add a `SystemCursor` mapping. The brush path is the existing circle code:

```swift
    private func makeCursor(for spec: CursorSpec) -> NSCursor {
        switch spec {
        case .brush(let color, let diameter):
            return makeBrushCursor(color: color, diameter: diameter)
        case .system(let system):
            return makeSystemCursor(system)
        }
    }

    private func makeSystemCursor(_ system: SystemCursor) -> NSCursor {
        switch system {
        case .arrow: return .arrow
        case .openHand: return .openHand
        case .closedHand: return .closedHand
        case .resize, .rotate: return .arrow   // full mapping lands in Task 10
        }
    }

    private func makeBrushCursor(color: RGBA, diameter: Double) -> NSCursor {
        let fillDiameter = max(1.0, CGFloat(diameter) / 2)
        let outlineWidth = self.outlineWidth
        let outerDiameter = fillDiameter + outlineWidth * 2
        let size = NSSize(width: outerDiameter, height: outerDiameter)
        let outline = CursorSpec.outlineColor(for: color)
        let outerRect = NSRect(x: 0, y: 0, width: outerDiameter, height: outerDiameter)
        let innerRect = NSRect(x: outlineWidth, y: outlineWidth, width: fillDiameter, height: fillDiameter)
        let image = NSImage(size: size, flipped: false) { _ in
            let ring = NSBezierPath()
            ring.append(NSBezierPath(ovalIn: outerRect))
            ring.append(NSBezierPath(ovalIn: innerRect))
            ring.windingRule = .evenOdd
            NSColor(srgbRed: outline.r, green: outline.g, blue: outline.b, alpha: outline.a).setFill()
            ring.fill()
            NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: color.a).setFill()
            NSBezierPath(ovalIn: innerRect).fill()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: outerDiameter / 2, y: outerDiameter / 2))
    }
```

- [ ] **Step 5: Update cursor tests to the enum**

For each cursor-emission test found in Step 1, change assertions from `CursorSpec(color:..., diameter:...)` to `.brush(color:..., diameter:...)` and any selection-arrow expectation to `.system(.arrow)`. Example pattern:

```swift
#expect(controller.currentCursor == .brush(color: controller.currentColor, diameter: controller.currentWidth))
```

- [ ] **Step 6: Run to verify pass**

Run: `just check`
Expected: all existing + updated tests green; lint clean; build succeeds (AppKit included).

- [ ] **Step 7: Commit**

```bash
git add Sources/Core/Model/CursorSpec.swift Sources/Core/Control/AppController.swift \
        Sources/AppKit/CursorRenderer.swift Tests/
git commit  # subject: "Core+AppKit: CursorSpec becomes brush/system enum with SystemCursor"
```

---

### Task 5: `cursorFor` policy

**Files:**
- Modify: `Sources/Core/Selection/SelectionRegion.swift`
- Test: `Tests/CoreTests/SelectionTests/CursorPolicyTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/SelectionTests/CursorPolicyTests.swift`:

```swift
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
        #expect(cursorFor(region: .outside, boxRotation: 0, dragging: false) == .arrow)
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
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: compile failure — `cursorFor` not found.

- [ ] **Step 3: Add `cursorFor`**

Append to `Sources/Core/Selection/SelectionRegion.swift`:

```swift
/// Pure cursor policy: the cursor to show for a region, given the box rotation
/// and whether a drag is active. Corner cursors are bucketed by screen-space
/// angle (the corner's local diagonal plus the box rotation) into the four
/// orientations the platform provides.
public func cursorFor(region: SelectionRegion, boxRotation: Double, dragging: Bool) -> SystemCursor {
    switch region {
    case .rotateHandle:
        return .rotate
    case .body:
        return dragging ? .closedHand : .openHand
    case .outside:
        return .arrow
    case .corner(let corner):
        let base: Double = (corner == .topLeft || corner == .bottomRight) ? 135 : 45
        return .resize(angle: bucketAngle(base + boxRotation))
    }
}

/// Reduces an angle (degrees) mod 180 and snaps to the nearest of {0,45,90,135}.
private func bucketAngle(_ degrees: Double) -> Double {
    var a = degrees.truncatingRemainder(dividingBy: 180)
    if a < 0 { a += 180 }
    let buckets: [Double] = [0, 45, 90, 135]
    // 180 wraps to 0; pick nearest including the 180==0 wrap.
    var best = buckets[0]
    var bestDist = Double.infinity
    for b in buckets + [180] {
        let d = abs(a - b)
        if d < bestDist { bestDist = d; best = b == 180 ? 0 : b }
    }
    return best
}
```

- [ ] **Step 4: Run to verify pass**

Run: `just check`
Expected: 3 new tests pass; lint clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Selection/SelectionRegion.swift \
        Tests/CoreTests/SelectionTests/CursorPolicyTests.swift
git commit  # subject: "Core: cursorFor policy — region + box rotation → SystemCursor"
```

---

### Task 6: `AppController` selection box + hover cursor

**Files:**
- Modify: `Sources/Core/Control/AppController.swift`
- Test: `Tests/CoreTests/AppControllerTests/SelectionBoxHoverTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/AppControllerTests/SelectionBoxHoverTests.swift`:

```swift
// ABOUTME: Tests for AppController.selectionBox recompute on selection change
// ABOUTME: and pointerHover driving the region-appropriate cursor.

import Testing

@Suite("AppController selection box + hover")
@MainActor
struct SelectionBoxHoverTests {
    private func setup() -> (AppController, [StrokeId]) {
        let clock = VirtualClock()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let c = AppController(editor: editor, window: RecordingWindow(),
                              detector: RecordingStationaryDetector(), clock: clock,
                              ticker: RecordingFadeTicker())
        c.activate()
        c.pointerDown(StrokePoint(x: 10, y: 10)); c.pointerMoved(StrokePoint(x: 30, y: 20)); c.pointerUp()
        c.currentTool = .selection
        return (c, editor.doc.strokeOrder)
    }

    @Test("setting selectedStrokeIds computes a selection box at rotation 0")
    func boxRecompute() {
        let (c, ids) = setup()
        c.selectedStrokeIds = [ids[0]]
        #expect(c.selectionBox != nil)
        #expect(c.selectionBox?.rotation == 0)
    }

    @Test("clearing the selection clears the box")
    func boxClear() {
        let (c, ids) = setup()
        c.selectedStrokeIds = [ids[0]]
        c.selectedStrokeIds = []
        #expect(c.selectionBox == nil)
    }

    @Test("hovering the body emits an open-hand cursor")
    func hoverBody() {
        let (c, ids) = setup()
        c.selectedStrokeIds = [ids[0]]
        let box = c.selectionBox!
        c.pointerHover(StrokePoint(x: box.center.x, y: box.center.y), modifiers: .none)
        #expect(c.currentCursor == .system(.openHand))
    }

    @Test("hovering outside the box emits the arrow")
    func hoverOutside() {
        let (c, ids) = setup()
        c.selectedStrokeIds = [ids[0]]
        c.pointerHover(StrokePoint(x: 1000, y: 1000), modifiers: .none)
        #expect(c.currentCursor == .system(.arrow))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: compile failure — `selectionBox`, `pointerHover` not found.

- [ ] **Step 3: Add selection-box state, hover, and hover-aware cursor**

In `Sources/Core/Control/AppController.swift`:

(a) Add near the other selection publishers (after `marqueeRect`):

```swift
    public var onSelectionBoxChanged: ((OrientedBox?) -> Void)?

    public var selectionBox: OrientedBox? {
        didSet { if oldValue != selectionBox { onSelectionBoxChanged?(selectionBox) } }
    }

    var lastHoverPoint: Point?

    /// Hit-test tuning shared by region classification and chrome rendering.
    static let handleHitRadius: Double = 8
    static let rotateNodeOffset: Double = 20
```

(b) Recompute the box whenever the selection set changes. Extend the existing `selectedStrokeIds.didSet`:

```swift
    public var selectedStrokeIds: [StrokeId] = [] {
        didSet {
            if oldValue != selectedStrokeIds {
                recomputeSelectionBox()
                onSelectionChanged?(selectedStrokeIds)
                refreshCursor()
            }
        }
    }

    func recomputeSelectionBox() {
        guard let rect = SelectionMath.selectionBounds(strokeIds: selectedStrokeIds, strokes: editor.doc.strokes) else {
            selectionBox = nil
            return
        }
        selectionBox = OrientedBox(center: Point(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2),
                                   size: Size(width: rect.width, height: rect.height), rotation: 0)
    }
```

(c) Add `pointerHover`:

```swift
    public func pointerHover(_ point: StrokePoint, modifiers: PointerModifiers) {
        lastHoverPoint = Point(x: point.x, y: point.y)
        refreshCursor()
    }
```

(d) Make `currentCursor` hover-aware in selection mode (replace the Task 4 `.selection` branch):

```swift
    public var currentCursor: CursorSpec? {
        if mode == .inactive { return nil }
        if currentTool == .selection {
            let region = SelectionMath.region(at: lastHoverPoint ?? Point(x: .infinity, y: .infinity),
                                              box: selectionBox,
                                              handleRadius: Self.handleHitRadius,
                                              rotateNodeOffset: Self.rotateNodeOffset)
            return .system(cursorFor(region: region, boxRotation: selectionBox?.rotation ?? 0,
                                     dragging: selectionGesture != nil))
        }
        return .brush(color: currentColor, diameter: currentWidth)
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `just check`
Expected: 4 new tests pass; existing cursor tests still green; lint clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Control/AppController.swift \
        Tests/CoreTests/AppControllerTests/SelectionBoxHoverTests.swift
git commit  # subject: "Core: AppController selection box + pointerHover-driven cursor"
```

---

### Task 7: Region-first `pointerDown` + Cmd selection-set editing

Rewrites `selectionPointerDown` to classify against the box first (fixing the multi-drag bug), routes translate through `SelectionTransforms`, and makes Cmd toggle membership for clicks and marquees.

**Files:**
- Modify: `Sources/Core/Control/AppController.swift` (extend the `SelectionGesture` enum)
- Modify: `Sources/Core/Control/AppController+SelectionGesture.swift`
- Test: `Tests/CoreTests/AppControllerTests/SelectionGestureTests.swift` (extend)

- [ ] **Step 1: Write the failing tests**

Append to `Tests/CoreTests/AppControllerTests/SelectionGestureTests.swift` (reuse its existing `setup()` which draws two strokes and switches to `.selection`):

```swift
    @Test("clicking a member of a multi-selection keeps the whole selection and translates it")
    func clickMemberKeepsMultiSelection() {
        let (c, editor, ids) = setup()
        c.selectedStrokeIds = ids                      // both selected
        c.pointerDown(StrokePoint(x: 20, y: 10))       // on stroke 0, which is inside the box
        c.pointerMoved(StrokePoint(x: 30, y: 10))      // drag +10 x
        c.pointerUp()
        #expect(Set(c.selectedStrokeIds) == Set(ids))  // still both
        #expect(editor.doc.strokes[ids[0]]?.transform.x == 10)
        #expect(editor.doc.strokes[ids[1]]?.transform.x == 10)  // moved together
    }

    @Test("clicking empty interior of the selection box translates the group")
    func clickEmptyInteriorTranslates() {
        let (c, editor, ids) = setup()
        c.selectedStrokeIds = ids
        let box = c.selectionBox!
        c.pointerDown(StrokePoint(x: box.center.x, y: box.center.y))  // empty interior
        c.pointerMoved(StrokePoint(x: box.center.x + 5, y: box.center.y))
        c.pointerUp()
        #expect(Set(c.selectedStrokeIds) == Set(ids))
        #expect(editor.doc.strokes[ids[0]]?.transform.x == 5)
    }

    @Test("Space+Cmd marquee toggles each intersected stroke")
    func cmdMarqueeToggles() {
        let (c, _, ids) = setup()
        c.selectedStrokeIds = [ids[0]]                 // stroke 0 already selected
        // Marquee over BOTH strokes with Cmd: stroke 0 removed, stroke 1 added.
        c.pointerDown(StrokePoint(x: 0, y: 0), modifiers: PointerModifiers(command: true))
        c.pointerMoved(StrokePoint(x: 200, y: 200), modifiers: PointerModifiers(command: true))
        c.pointerUp(modifiers: PointerModifiers(command: true))
        #expect(c.selectedStrokeIds == [ids[1]])
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: failures — clicking a member currently replaces the selection; Cmd-marquee currently replaces.

- [ ] **Step 3: Extend the `SelectionGesture` enum**

In `Sources/Core/Control/AppController.swift`, replace the enum (currently `.marquee`/`.translate`) with:

```swift
    enum SelectionGesture {
        case marquee(startPoint: StrokePoint, additive: Bool)
        case translate(startBox: OrientedBox, startTransforms: [StrokeId: Transform], startPoint: StrokePoint)
        case resize(startBox: OrientedBox, startTransforms: [StrokeId: Transform], anchor: Point, startCorner: Point)
        case rotate(startBox: OrientedBox, startTransforms: [StrokeId: Transform], center: Point, startPoint: StrokePoint)
    }
```

(`.resize`/`.rotate` are populated in Task 8; defining them now keeps the enum stable.)

- [ ] **Step 4: Rewrite `selectionPointerDown` (region-first + Cmd)**

In `Sources/Core/Control/AppController+SelectionGesture.swift`, replace `selectionPointerDown`:

```swift
    func selectionPointerDown(_ point: StrokePoint, modifiers: PointerModifiers) {
        lastSelectionPoint = point
        lastHoverPoint = Point(x: point.x, y: point.y)
        let p = Point(x: point.x, y: point.y)

        if modifiers.command {
            // Cmd = edit the selection set. Click toggles one stroke; drag marquees additively.
            let strokes = orderedStrokes()
            if let hit = SelectionMath.hitTest(point: point, strokes: strokes, tolerance: Self.handleHitRadius) {
                toggle(hit)
                selectionGesture = nil
            } else {
                selectionGesture = .marquee(startPoint: point, additive: true)
            }
            return
        }

        let region = SelectionMath.region(at: p, box: selectionBox,
                                          handleRadius: Self.handleHitRadius,
                                          rotateNodeOffset: Self.rotateNodeOffset)
        switch region {
        case .rotateHandle:
            beginRotate(at: point)            // Task 8
        case .corner(let corner):
            beginResize(corner: corner, at: point)  // Task 8
        case .body:
            beginTranslate(at: point)
        case .outside:
            let strokes = orderedStrokes()
            if let hit = SelectionMath.hitTest(point: point, strokes: strokes, tolerance: Self.handleHitRadius) {
                selectedStrokeIds = [hit]
                beginTranslate(at: point)
            } else {
                selectionGesture = .marquee(startPoint: point, additive: false)
            }
        }
    }

    private func orderedStrokes() -> [Stroke] {
        editor.doc.strokeOrder.compactMap { editor.doc.strokes[$0] }
    }

    private func toggle(_ id: StrokeId) {
        if selectedStrokeIds.contains(id) {
            selectedStrokeIds.removeAll { $0 == id }
        } else {
            selectedStrokeIds.append(id)
        }
    }

    private func beginTranslate(at point: StrokePoint) {
        guard let box = selectionBox else { return }
        selectionGesture = .translate(startBox: box, startTransforms: snapshotTransforms(), startPoint: point)
    }

    func snapshotTransforms() -> [StrokeId: Transform] {
        var out: [StrokeId: Transform] = [:]
        for id in selectedStrokeIds { if let s = editor.doc.strokes[id] { out[id] = s.transform } }
        return out
    }
```

- [ ] **Step 5: Update `selectionPointerMoved` / `selectionPointerUp` for the new enum**

Replace the `.translate` and `.marquee` handling in `selectionPointerMoved`:

```swift
    func selectionPointerMoved(_ point: StrokePoint, modifiers: PointerModifiers) {
        lastSelectionPoint = point
        guard let gesture = selectionGesture else { return }
        switch gesture {
        case .marquee(let startPoint, _):
            marqueeRect = Rect(x: min(startPoint.x, point.x), y: min(startPoint.y, point.y),
                               width: abs(point.x - startPoint.x), height: abs(point.y - startPoint.y))
        case .translate(let startBox, let startTransforms, let startPoint):
            let (box, transforms) = SelectionTransforms.translate(
                startBox: startBox, startTransforms: startTransforms,
                dx: point.x - startPoint.x, dy: point.y - startPoint.y)
            selectionBox = box
            inFlightTransforms = transforms
        case .resize, .rotate:
            selectionMovedResizeOrRotate(point, gesture: gesture)  // Task 8
        }
    }
```

Replace `selectionPointerUp`:

```swift
    func selectionPointerUp(modifiers: PointerModifiers) {
        let gesture = selectionGesture
        selectionGesture = nil
        let endPoint = lastSelectionPoint
        lastSelectionPoint = nil
        let preview = inFlightTransforms

        guard let g = gesture else { inFlightTransforms = [:]; return }
        switch g {
        case .marquee(let startPoint, let additive):
            marqueeRect = nil
            inFlightTransforms = [:]
            let end = endPoint ?? startPoint
            let rect = Rect(x: min(startPoint.x, end.x), y: min(startPoint.y, end.y),
                            width: abs(end.x - startPoint.x), height: abs(end.y - startPoint.y))
            let hits = SelectionMath.marqueeHit(rect: rect, strokes: orderedStrokes())
            if additive {
                for id in hits { toggle(id) }
            } else {
                selectedStrokeIds = hits
            }
        case .translate, .resize, .rotate:
            let updates = preview.map { (id: $0.key, transform: $0.value) }
            if !updates.isEmpty { _ = editor.transformStrokes(updates) }
            inFlightTransforms = [:]
            recomputeSelectionBox()  // re-baseline the box from committed transforms (keeps rotation if rotate committed via Task 8)
        }
    }
```

> Note for Task 8: rotate commits a rotated box; `recomputeSelectionBox()` resets rotation to 0 from the AABB. Task 8 overrides this for rotate by preserving the gesture's final `selectionBox` instead of recomputing. Leave the translate/resize path recomputing (rotation stays 0).

- [ ] **Step 6: Run to verify pass**

Run: `just check`
Expected: the 3 new tests pass; existing `SelectionGestureTests` (click-replace, marquee, dragTranslate, etc.) still pass. If `beginResize`/`beginRotate`/`selectionMovedResizeOrRotate` aren't defined yet, add temporary stubs that do nothing so the build is green:

```swift
    func beginResize(corner: Corner, at point: StrokePoint) { /* Task 8 */ }
    func beginRotate(at point: StrokePoint) { /* Task 8 */ }
    func selectionMovedResizeOrRotate(_ point: StrokePoint, gesture: SelectionGesture) { /* Task 8 */ }
```

- [ ] **Step 7: Commit**

```bash
git add Sources/Core/Control/AppController.swift \
        Sources/Core/Control/AppController+SelectionGesture.swift \
        Tests/CoreTests/AppControllerTests/SelectionGestureTests.swift
git commit  # subject: "Core: region-first selection pointerDown + Space+Cmd set editing"
```

---

### Task 8: Resize + rotate gestures

**Files:**
- Modify: `Sources/Core/Control/AppController+SelectionGesture.swift`
- Test: `Tests/CoreTests/AppControllerTests/SelectionGestureTests.swift` (extend)

- [ ] **Step 1: Write the failing tests**

Append to `Tests/CoreTests/AppControllerTests/SelectionGestureTests.swift`:

```swift
    @Test("dragging a corner scales the selection and commits one undoable op")
    func cornerResize() {
        let (c, editor, ids) = setup()
        c.selectedStrokeIds = [ids[0]]
        let box = c.selectionBox!
        let br = box.corners()[2]   // bottomRight
        let tl = box.corners()[0]   // anchor
        c.pointerDown(StrokePoint(x: br.x, y: br.y))
        // double the distance from the anchor along the diagonal
        c.pointerMoved(StrokePoint(x: tl.x + (br.x - tl.x) * 2, y: tl.y + (br.y - tl.y) * 2))
        c.pointerUp()
        #expect(editor.doc.strokes[ids[0]]!.transform.scale == 2)
        editor.undo()
        #expect(editor.doc.strokes[ids[0]]!.transform.scale == 1)
    }

    @Test("dragging the rotate node rotates the group as a rigid unit, one undoable op")
    func rotateGesture() {
        let (c, editor, ids) = setup()
        c.selectedStrokeIds = ids
        let box = c.selectionBox!
        let node = box.rotateNode(offset: AppController.rotateNodeOffset)
        c.pointerDown(StrokePoint(x: node.x, y: node.y))
        // move the pointer 90° around the center
        let center = box.center
        c.pointerMoved(StrokePoint(x: center.x, y: center.y + 50))
        c.pointerUp()
        // both strokes gained the same rotation delta (rigid)
        let r0 = editor.doc.strokes[ids[0]]!.transform.rotate
        let r1 = editor.doc.strokes[ids[1]]!.transform.rotate
        #expect(abs(r0 - r1) < 1e-6)
        #expect(abs(r0) > 1)   // actually rotated
        editor.undo()
        #expect(abs(editor.doc.strokes[ids[0]]!.transform.rotate) < 1e-6)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: failures — resize/rotate stubs do nothing, so transforms don't change.

- [ ] **Step 3: Implement resize/rotate gesture begin + move**

In `Sources/Core/Control/AppController+SelectionGesture.swift`, replace the Task-7 stubs:

```swift
    func beginResize(corner: Corner, at point: StrokePoint) {
        guard let box = selectionBox else { return }
        let cs = box.corners()  // TL, TR, BR, BL
        let oppositeIndex: Int
        switch corner {
        case .topLeft: oppositeIndex = 2
        case .topRight: oppositeIndex = 3
        case .bottomRight: oppositeIndex = 0
        case .bottomLeft: oppositeIndex = 1
        }
        let cornerIndex: Int
        switch corner {
        case .topLeft: cornerIndex = 0
        case .topRight: cornerIndex = 1
        case .bottomRight: cornerIndex = 2
        case .bottomLeft: cornerIndex = 3
        }
        selectionGesture = .resize(startBox: box, startTransforms: snapshotTransforms(),
                                   anchor: cs[oppositeIndex], startCorner: cs[cornerIndex])
    }

    func beginRotate(at point: StrokePoint) {
        guard let box = selectionBox else { return }
        selectionGesture = .rotate(startBox: box, startTransforms: snapshotTransforms(),
                                   center: box.center, startPoint: point)
    }

    func selectionMovedResizeOrRotate(_ point: StrokePoint, gesture: SelectionGesture) {
        let p = Point(x: point.x, y: point.y)
        switch gesture {
        case .resize(let startBox, let startTransforms, let anchor, let startCorner):
            let (box, transforms) = SelectionTransforms.resize(
                startBox: startBox, startTransforms: startTransforms,
                anchor: anchor, startCorner: startCorner, pointer: p, minFactor: 0.05)
            selectionBox = box
            inFlightTransforms = transforms
        case .rotate(let startBox, let startTransforms, let center, let startPoint):
            let (box, transforms) = SelectionTransforms.rotate(
                startBox: startBox, startTransforms: startTransforms,
                center: center, startPointer: Point(x: startPoint.x, y: startPoint.y),
                pointer: p, snap15: false)  // Shift-snap wired in Task 9 via modifiers
            selectionBox = box
            inFlightTransforms = transforms
        default:
            break
        }
    }
```

- [ ] **Step 4: Preserve the rotated box on rotate commit**

In `selectionPointerUp`, the `.translate, .resize, .rotate` branch currently calls `recomputeSelectionBox()` (resets rotation to 0). For rotate, keep the gesture's final box. Replace that branch:

```swift
        case .translate, .resize, .rotate:
            let updates = preview.map { (id: $0.key, transform: $0.value) }
            if !updates.isEmpty { _ = editor.transformStrokes(updates) }
            inFlightTransforms = [:]
            if case .rotate = g {
                // keep the oriented box at its rotated angle (don't snap back to upright)
                // selectionBox already holds the final rotated box from the last move
            } else {
                recomputeSelectionBox()
            }
```

- [ ] **Step 5: Run to verify pass**

Run: `just check`
Expected: the 2 new tests pass; all prior selection tests still green; lint clean.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Control/AppController+SelectionGesture.swift \
        Tests/CoreTests/AppControllerTests/SelectionGestureTests.swift
git commit  # subject: "Core: corner resize + rotate-node gestures via SelectionTransforms"
```

---

### Task 9: Transient lifetime, Shift-snap, tool-gated Delete, Esc revert

**Files:**
- Modify: `Sources/Core/Control/AppController.swift` (`currentTool` didSet)
- Modify: `Sources/Core/Control/AppController+SelectionGesture.swift` (Shift-snap in rotate)
- Modify: `Sources/Core/Control/AppController+Commands.swift` (`run(.clear)`)
- Modify: `Sources/App/main.swift` (Esc → plain deactivate)
- Test: `Tests/CoreTests/AppControllerTests/SelectionLifetimeTests.swift`; extend `RunCommandTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/AppControllerTests/SelectionLifetimeTests.swift`:

```swift
// ABOUTME: Tests for transient selection lifetime (clear on Space release with
// ABOUTME: mid-gesture deferral) and tool-gated Delete.

import Testing

@Suite("Selection lifetime")
@MainActor
struct SelectionLifetimeTests {
    private func setup() -> (AppController, Editor, [StrokeId]) {
        let clock = VirtualClock()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let c = AppController(editor: editor, window: RecordingWindow(),
                              detector: RecordingStationaryDetector(), clock: clock,
                              ticker: RecordingFadeTicker())
        c.activate()
        c.pointerDown(StrokePoint(x: 10, y: 10)); c.pointerMoved(StrokePoint(x: 30, y: 20)); c.pointerUp()
        c.currentTool = .selection
        return (c, editor, editor.doc.strokeOrder)
    }

    @Test("releasing Space (tool → pen) clears the selection")
    func releaseClears() {
        let (c, _, ids) = setup()
        c.selectedStrokeIds = [ids[0]]
        c.currentTool = .pen
        #expect(c.selectedStrokeIds == [])
        #expect(c.selectionBox == nil)
    }

    @Test("releasing Space mid-gesture defers the clear until pointerUp")
    func deferredClear() {
        let (c, editor, ids) = setup()
        c.selectedStrokeIds = ids
        c.pointerDown(StrokePoint(x: 20, y: 10))     // grab the group (inside box)
        c.pointerMoved(StrokePoint(x: 25, y: 10))
        c.currentTool = .pen                          // Space released mid-drag
        #expect(c.selectedStrokeIds == ids)           // NOT cleared yet
        c.pointerUp()                                 // gesture ends → deferred clear applies
        #expect(c.selectedStrokeIds == [])
        #expect(editor.doc.strokes[ids[0]]?.transform.x == 5)  // the drag still committed
    }

    @Test("Delete in selection mode with no selection is a no-op")
    func deleteNoSelectionNoOp() {
        let (c, editor, _) = setup()
        let before = editor.doc.strokes.count
        c.run(.clear)
        #expect(editor.doc.strokes.count == before)   // nothing cleared
    }

    @Test("Delete in pen mode clears everything")
    func deletePenClearsAll() {
        let (c, editor, _) = setup()
        c.currentTool = .pen
        c.run(.clear)
        #expect(editor.doc.strokes.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: failures — tool change doesn't clear; `run(.clear)` isn't tool-gated.

- [ ] **Step 3: Transient lifetime in `currentTool.didSet`**

In `Sources/Core/Control/AppController.swift`, update `currentTool` (and add a deferral flag):

```swift
    private var pendingSelectionClear = false

    public var currentTool: Tool = .pen {
        didSet {
            guard oldValue != currentTool else { return }
            if currentTool == .pen {
                if selectionGesture != nil {
                    pendingSelectionClear = true   // defer until the gesture's pointerUp
                } else {
                    clearSelectionState()
                }
            }
            onCurrentToolChanged?(currentTool)
            refreshCursor()
        }
    }

    func clearSelectionState() {
        selectedStrokeIds = []
        selectionBox = nil
        inFlightTransforms = [:]
        marqueeRect = nil
        selectionGesture = nil
    }
```

- [ ] **Step 4: Apply the deferred clear on pointerUp**

In `Sources/Core/Control/AppController+SelectionGesture.swift`, at the very end of `selectionPointerUp` (after the switch), add:

```swift
        if pendingSelectionClear {
            pendingSelectionClear = false
            clearSelectionState()
        }
```

(`pendingSelectionClear` is declared `private` in Step 3 — change it to internal access by removing `private` so the extension can see it, or add a small internal setter. Simplest: declare it `var pendingSelectionClear = false` without `private`.)

- [ ] **Step 5: Tool-gated `run(.clear)`**

In `Sources/Core/Control/AppController+Commands.swift`, replace the `.clear` case:

```swift
        case .clear:
            if currentTool == .selection {
                if !selectedStrokeIds.isEmpty {
                    _ = editor.eraseStrokes(ids: selectedStrokeIds)
                    selectedStrokeIds = []
                }
                // no selection in selection mode → no-op (a "miss")
            } else {
                clear()
            }
```

- [ ] **Step 6: Shift-snap in rotate**

In `Sources/Core/Control/AppController+SelectionGesture.swift`, thread the modifier into the rotate move. Change `selectionMovedResizeOrRotate` to take modifiers and pass `snap15: modifiers.shift`:

Update the call in `selectionPointerMoved` from `selectionMovedResizeOrRotate(point, gesture: gesture)` to `selectionMovedResizeOrRotate(point, gesture: gesture, modifiers: modifiers)`, and the signature to `func selectionMovedResizeOrRotate(_ point: StrokePoint, gesture: SelectionGesture, modifiers: PointerModifiers)`, using `snap15: modifiers.shift` in the rotate branch.

- [ ] **Step 7: Esc reverts to plain deactivate**

In `Sources/App/main.swift`, find the `input.onDeactivate` wiring (added in the original Task 8) and replace it with the plain form:

```swift
        input.onDeactivate = { [weak self] in self?.controller.deactivate() }
```

- [ ] **Step 8: Run to verify pass**

Run: `just check`
Expected: the 4 new lifetime tests pass; the prior `RunCommandTests` selection-clear tests still pass (selection-mode delete still erases selection); lint clean; build succeeds.

- [ ] **Step 9: Commit**

```bash
git add Sources/Core/Control/AppController.swift \
        Sources/Core/Control/AppController+SelectionGesture.swift \
        Sources/Core/Control/AppController+Commands.swift \
        Sources/App/main.swift \
        Tests/CoreTests/AppControllerTests/SelectionLifetimeTests.swift
git commit  # subject: "Core: transient selection lifetime, Shift-snap, tool-gated Delete; revert Esc"
```

---

### Task 10: `CursorRenderer` full `SystemCursor` mapping

**Files:**
- Modify: `Sources/AppKit/CursorRenderer.swift`
- Test: `Tests/AppKitTests/CursorRendererTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/AppKitTests/CursorRendererTests.swift`:

```swift
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
            .arrow, .openHand, .closedHand, .rotate,
            .resize(angle: 0), .resize(angle: 45), .resize(angle: 90), .resize(angle: 135),
        ]
        for sc in cursors {
            #expect(renderer.nsCursor(for: sc) != nil)
        }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: compile failure — `nsCursor(for:)` not exposed.

- [ ] **Step 3: Implement the mapping**

In `Sources/AppKit/CursorRenderer.swift`, replace `makeSystemCursor` with a testable `nsCursor(for:)` plus the diagonal/rotate implementations:

```swift
    func nsCursor(for system: SystemCursor) -> NSCursor {
        switch system {
        case .arrow: return .arrow
        case .openHand: return .openHand
        case .closedHand: return .closedHand
        case .rotate: return Self.rotateCursor
        case .resize(let angle): return Self.resizeCursor(angle: angle)
        }
    }

    private static func resizeCursor(angle: Double) -> NSCursor {
        switch Int(angle.rounded()) {
        case 0: return .resizeLeftRight
        case 90: return .resizeUpDown
        case 45: return privateCursor("_windowResizeNorthEastSouthWestCursor") ?? .arrow
        case 135: return privateCursor("_windowResizeNorthWestSouthEastCursor") ?? .arrow
        default: return .arrow
        }
    }

    /// Calls an undocumented NSCursor class selector by name; nil if unavailable.
    private static func privateCursor(_ name: String) -> NSCursor? {
        let sel = NSSelectorFromString(name)
        guard NSCursor.responds(to: sel) else { return nil }
        return NSCursor.perform(sel)?.takeUnretainedValue() as? NSCursor
    }

    /// A rotate cursor drawn programmatically (two curved arrows). No bundled asset.
    private static let rotateCursor: NSCursor = {
        let d: CGFloat = 20
        let image = NSImage(size: NSSize(width: d, height: d), flipped: false) { _ in
            let path = NSBezierPath()
            path.appendArc(withCenter: NSPoint(x: d / 2, y: d / 2), radius: d / 2 - 3,
                           startAngle: 40, endAngle: 320)
            path.lineWidth = 2
            NSColor.black.setStroke()
            // soft white halo for contrast
            let halo = path.copy() as! NSBezierPath
            halo.lineWidth = 4
            NSColor(white: 1, alpha: 0.8).setStroke(); halo.stroke()
            path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: d / 2, y: d / 2))
    }()
```

And change `makeCursor(for:)`'s `.system` branch to `return nsCursor(for: system)`.

- [ ] **Step 4: Run to verify pass**

Run: `just check`
Expected: the smoke test passes; lint clean; build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/CursorRenderer.swift Tests/AppKitTests/CursorRendererTests.swift
git commit  # subject: "AppKit: CursorRenderer maps SystemCursor (native diagonals + rotate image)"
```

---

### Task 11: `CanvasView` oriented chrome + hover forwarding + wiring

**Files:**
- Modify: `Sources/AppKit/CanvasView.swift` (`setSelectionBox`, oriented draw)
- Modify: `Sources/AppKit/NSEventInputSource.swift` (`mouseMoved` → hover)
- Modify: `Sources/App/main.swift` (subscribe `onSelectionBoxChanged`; wire hover; drop `setSelectionBounds`)
- Test: `Tests/AppKitTests/CanvasViewSelectionTests.swift` (update)

- [ ] **Step 1: Write/Update the failing test**

In `Tests/AppKitTests/CanvasViewSelectionTests.swift`, replace `setSelectionBounds` usage with `setSelectionBox` and add a rotated-box smoke check:

```swift
    @Test("setSelectionBox stores the box and marks dirty")
    func setBoxStores() {
        let canvas = CanvasView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        canvas.needsDisplay = false
        let box = OrientedBox(center: Point(x: 100, y: 100), size: Size(width: 40, height: 20), rotation: 30)
        canvas.setSelectionBox(box)
        #expect(canvas.selectionBox == box)
        #expect(canvas.needsDisplay == true)
    }

    @Test("setSelectionBox(nil) clears the chrome")
    func clearBox() {
        let canvas = CanvasView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        canvas.setSelectionBox(OrientedBox(center: Point(x: 10, y: 10), size: Size(width: 5, height: 5), rotation: 0))
        canvas.setSelectionBox(nil)
        #expect(canvas.selectionBox == nil)
    }
```

(Remove or update any existing test referencing `setSelectionBounds`.)

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: compile failure — `setSelectionBox` / `selectionBox: OrientedBox?` not found.

- [ ] **Step 3: Replace the axis-aligned chrome with an oriented box**

In `Sources/AppKit/CanvasView.swift`, replace `selectionBounds: Rect?` + `setSelectionBounds` with:

```swift
    public private(set) var selectionBox: OrientedBox?

    public func setSelectionBox(_ box: OrientedBox?) {
        guard selectionBox != box else { return }
        selectionBox = box
        needsDisplay = true
    }
```

Replace the `drawSelectionBox(_ rect:Rect, in:)` call/impl. In `draw(_:)`, change the `if let sel = selectionBounds` block to `if let box = selectionBox { drawSelectionBox(box, in: ctx) }`, and replace the function:

```swift
    private func drawSelectionBox(_ box: OrientedBox, in ctx: CGContext) {
        let corners = box.corners().map { CGPoint(x: $0.x, y: $0.y) }
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [5, 4])
        ctx.beginPath()
        ctx.move(to: corners[0])
        for c in corners.dropFirst() { ctx.addLine(to: c) }
        ctx.closePath()
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])

        // corner handles (6×6pt, filled accent, white outline)
        let h: CGFloat = 6
        for c in corners {
            let r = CGRect(x: c.x - h / 2, y: c.y - h / 2, width: h, height: h)
            ctx.setFillColor(NSColor.controlAccentColor.cgColor)
            ctx.fill(r)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(r)
        }

        // rotate node + connecting line from the top-edge midpoint
        let node = box.rotateNode(offset: 20)
        let topMid = CGPoint(x: (corners[0].x + corners[1].x) / 2, y: (corners[0].y + corners[1].y) / 2)
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(1)
        ctx.beginPath(); ctx.move(to: topMid); ctx.addLine(to: CGPoint(x: node.x, y: node.y)); ctx.strokePath()
        let nodeRect = CGRect(x: node.x - 6, y: node.y - 6, width: 12, height: 12)
        ctx.setFillColor(NSColor.black.cgColor); ctx.fillEllipse(in: nodeRect)
        ctx.strokeEllipse(in: nodeRect)
        ctx.restoreGState()
    }
```

(Leave `drawMarquee` and `marqueeRect` unchanged — the marquee stays axis-aligned.)

- [ ] **Step 4: Forward `mouseMoved` as hover**

In `Sources/AppKit/NSEventInputSource.swift`:

(a) Add a hover callback and a delegate method. Add to the `onPointer*` group:

```swift
    public var onPointerHover: ((StrokePoint, PointerModifiers) -> Void)?
```

(b) Extend the `CanvasInputDelegate` protocol with `func canvasInput(_ view: CanvasInputView, mouseMovedAt point: CGPoint, modifiers: PointerModifiers)` and implement it in the `NSEventInputSource: CanvasInputDelegate` extension:

```swift
    public func canvasInput(_ view: CanvasInputView, mouseMovedAt point: CGPoint, modifiers: PointerModifiers) {
        onPointerHover?(StrokePoint(x: Double(point.x), y: Double(point.y)), modifiers)
    }
```

(c) In `CanvasInputView.mouseMoved(with:)` (already overridden ~line 168), call the delegate with the converted point + modifiers (mirror `mouseDragged`):

```swift
    public override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let m = PointerModifiers(command: event.modifierFlags.contains(.command),
                                 shift: event.modifierFlags.contains(.shift))
        delegate?.canvasInput(self, mouseMovedAt: p, modifiers: m)
    }
```

(Preserve any existing cursor-related work already in `mouseMoved`.)

- [ ] **Step 5: Wire `main.swift`**

In `Sources/App/main.swift`:

(a) Replace the `onSelectionChanged`/`onInFlightTransformsChanged` blocks that call `setSelectionBounds` so they no longer compute a `Rect`; instead subscribe to the box publisher and forward in-flight renders:

```swift
        controller.onSelectionBoxChanged = { [weak self] box in
            self?.canvas.setSelectionBox(box)
        }

        controller.onInFlightTransformsChanged = { [weak self] overrides in
            guard let self else { return }
            self.canvas.render(RenderFrame.from(editor: self.editor, canvasSize: self.canvasSize, overrides: overrides))
        }

        controller.onMarqueeChanged = { [weak self] rect in
            self?.canvas.setMarquee(rect)
        }
```

(Delete the old `onSelectionChanged` selection-bounds computation; the box now comes from `onSelectionBoxChanged`. Keep `onSelectionChanged` only if something else needs it — otherwise remove the assignment.)

(b) Wire hover:

```swift
        input.onPointerHover = { [weak self] in self?.controller.pointerHover($0, modifiers: $1) }
```

- [ ] **Step 6: Run to verify pass + manual smoke**

Run: `just check`
Expected: updated CanvasView tests pass; all Core tests green; lint clean; build succeeds.

Manual smoke (`just run-bg`, then exercise, then `just stop`):
1. Activate fiti, draw a few strokes. Hold Space.
2. Marquee 2+ strokes; click any member or the empty box interior → the whole group drags.
3. Hover the body → hand; a corner → diagonal resize cursor; the node → rotate cursor.
4. Drag a corner → uniform scale; drag the node → rigid rotation (Shift snaps to 15°); the box stays oriented.
5. Space+Cmd+click toggles one stroke; Space+Cmd+marquee toggles each intersected.
6. Delete with a selection erases just those; Delete with no selection (Space held) does nothing; release Space, Delete clears all.
7. Release Space → selection clears.

- [ ] **Step 7: Commit**

```bash
git add Sources/AppKit/CanvasView.swift Sources/AppKit/NSEventInputSource.swift \
        Sources/App/main.swift Tests/AppKitTests/CanvasViewSelectionTests.swift
git commit  # subject: "AppKit+App: oriented selection chrome, hover forwarding, box wiring"
```

---

## Self-review notes

- **Spec coverage:** region-first routing (T7), Space+Cmd toggle click+marquee (T7), corners-only resize (T8), rigid rotate + 15° snap (T8/T9), persistent oriented box (T8 keeps rotation; T6 recompute at 0 on set change), hover cursors via pure `cursorFor` (T5/T6) + adapter mapping (T10), transient lifetime with mid-gesture deferral (T9), tool-gated Delete (T9), Esc revert (T9), oriented chrome (T11). All acceptance criteria map to a task.
- **Atomic signature change:** `CursorSpec` struct→enum is isolated to T4 with all call sites + tests updated in one commit.
- **Test boundary:** T1–T9 are pure-Core, tested without drawing; T10–T11 are AppKit smoke. `Sources/Core/` gains no forbidden imports.
- **Type consistency:** `Point`, `OrientedBox`, `SelectionRegion`, `Corner`, `SystemCursor`, `cursorFor`, `SelectionTransforms.{translate,resize,rotate}`, `selectionBox`, `pointerHover`, `clearSelectionState`, `pendingSelectionClear`, `recomputeSelectionBox`, `snapshotTransforms` are defined once and reused with consistent signatures.
