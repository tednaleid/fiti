# fiti Selection Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Press-and-hold `Space` flips fiti to a selection tool. Click selects, Cmd-click toggles, drag-from-empty marquees. Four corner handles (uniform scale) plus a rotation handle. `Delete` with a selection erases only the selected strokes; with no selection it keeps the current "clear all" behavior. `Cmd+K` always clears all regardless.

**Architecture:** A new `Tool` enum on `AppController` runs parallel to `Mode`. Selection state (`selectedStrokeIds`, `inFlightTransforms`) lives on the controller. Hit-testing and marquee math are pure-Core functions in a new `SelectionMath` enum. `Editor` gains `transformStrokes(_:)` and `eraseStrokes(ids:)` as single undoable ops backed by a new `InverseOp.setTransforms` case plus the existing `restoreStrokes` primitive. `KeyMonitor` learns Space's press-and-hold semantics (keyUp monitor + `isARepeat` filter). `NSEventInputSource` extracts modifier flags into a Core `PointerModifiers` value. `CanvasView` gains setters for the selection box, handles, and marquee outline, drawn on top of the existing stroke pass.

**Tech Stack:** Swift 6, AppKit, Swift Testing, no SwiftUI, no new SPM deps.

**Source of truth:** `docs/specs/2026-05-20-fiti-selection-tool-design.md`.

---

## File map

| File | Responsibility | Status |
| --- | --- | --- |
| `Sources/Core/Model/Tool.swift` | `Tool` enum (`.pen`, `.selection`) | create (Task 1) |
| `Sources/Core/Model/PointerModifiers.swift` | `PointerModifiers` value (cmd / shift bools) | create (Task 1) |
| `Tests/CoreTests/ToolTests.swift` | enum exhaustiveness + equality | create (Task 1) |
| `Tests/CoreTests/PointerModifiersTests.swift` | factory + equality | create (Task 1) |
| `Sources/Core/Model/Rect.swift` | `Rect` value (x/y/width/height) | create (Task 2) |
| `Sources/Core/Selection/SelectionMath.swift` | hitTest, marqueeHit, selectionBounds | create (Task 2) |
| `Tests/CoreTests/RectTests.swift` | basic geometry tests | create (Task 2) |
| `Tests/CoreTests/SelectionMathTests.swift` | hit-test + marquee + bounds | create (Task 2) |
| `Sources/Core/Editor/InverseOp.swift` | gain `.setTransforms(entries:)` case + `TransformEntry` | modify (Task 3) |
| `Sources/Core/Editor/Editor.swift` | `transformStrokes(_:)`, `eraseStrokes(ids:)`, `applyInverse` setTransforms | modify (Task 3) |
| `Tests/CoreTests/EditorTransformStrokesTests.swift` | undoable transform op | create (Task 3) |
| `Tests/CoreTests/EditorEraseStrokesTests.swift` | undoable batch erase | create (Task 3) |
| `Sources/Core/Control/AppController.swift` | `currentTool`, `selectedStrokeIds`, `inFlightTransforms`, publishers; `run(.clear)` selection-aware; cursor returns nil under .selection | modify (Task 4) |
| `Tests/CoreTests/AppControllerTests/ToolStateTests.swift` | tool transitions + cursor | create (Task 4) |
| `Tests/CoreTests/AppControllerTests/SelectionStateTests.swift` | selectedStrokeIds + inFlightTransforms publishers | create (Task 4) |
| `Tests/CoreTests/AppControllerTests/RunCommandTests.swift` | additions for selection-aware clear | modify (Task 4) |
| `Sources/Core/Control/AppController.swift` | `pointerDown(_:modifiers:)` overload + selection state machine + gesture math | modify (Task 5) |
| `Tests/CoreTests/AppControllerTests/SelectionGestureTests.swift` | full gesture state machine | create (Task 5) |
| `Sources/AppKit/KeyMonitor.swift` | install `.keyUp` monitor; Space → currentTool = .selection on keyDown (no repeat), .pen on keyUp | modify (Task 6) |
| `Tests/AppKitTests/KeyMonitorTests.swift` | Space keyDown/keyUp; isARepeat filter | modify (Task 6) |
| `Sources/AppKit/NSEventInputSource.swift` | extract modifier flags; pass through new delegate protocol | modify (Task 7) |
| `Tests/AppKitTests/NSEventInputSourceTests.swift` | modifier translation if file exists; otherwise inline in CanvasInputView tests | modify or create (Task 7) |
| `Sources/Core/Rendering/RenderFrame.swift` | `from(editor:canvasSize:overrides:)` overload | modify (Task 8) |
| `Sources/AppKit/CanvasView.swift` | `setSelectionBounds`, `setSelectionHandles`, `setMarquee`; draw routine | modify (Task 8) |
| `Tests/AppKitTests/CanvasViewSelectionTests.swift` | renderer setters + pixel-sample for selection box | create (Task 8) |
| `Sources/App/main.swift` | wire `onSelectionChanged` and `onInFlightTransformsChanged`; thread modifiers | modify (Task 8) |

---

### Task 1: `Tool` enum + `PointerModifiers` value

Pure Core types. No behavior change.

**Files:**
- Create: `Sources/Core/Model/Tool.swift`
- Create: `Sources/Core/Model/PointerModifiers.swift`
- Create: `Tests/CoreTests/ToolTests.swift`
- Create: `Tests/CoreTests/PointerModifiersTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/ToolTests.swift`:

```swift
// ABOUTME: Tests for the Tool enum — covers the two cases shipped in v1
// ABOUTME: (.pen default, .selection) and their equality.

import Testing

@Suite("Tool")
struct ToolTests {
    @Test(".pen and .selection are distinct cases")
    func distinctCases() {
        #expect(Tool.pen != Tool.selection)
        #expect(Tool.pen == Tool.pen)
        #expect(Tool.selection == Tool.selection)
    }
}
```

Create `Tests/CoreTests/PointerModifiersTests.swift`:

```swift
// ABOUTME: Tests for the PointerModifiers value type — the Core abstraction
// ABOUTME: that lets AppKit modifier flags cross into Core without leaking NSEvent.

import Testing

@Suite("PointerModifiers")
struct PointerModifiersTests {
    @Test("default factory has no modifiers set")
    func defaultEmpty() {
        let m = PointerModifiers()
        #expect(m.command == false)
        #expect(m.shift == false)
    }

    @Test(".none equals default")
    func noneEqualsDefault() {
        #expect(PointerModifiers.none == PointerModifiers())
    }

    @Test("equality compares both flags")
    func equality() {
        #expect(PointerModifiers(command: true) != PointerModifiers())
        #expect(PointerModifiers(shift: true) != PointerModifiers())
        #expect(PointerModifiers(command: true, shift: true) == PointerModifiers(command: true, shift: true))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test`
Expected: compile errors — `Tool`, `PointerModifiers` not found.

- [ ] **Step 3: Create the types**

Create `Sources/Core/Model/Tool.swift`:

```swift
// ABOUTME: Active tool in the selection / drawing surface. Lives parallel to
// ABOUTME: AppController.Mode — orthogonal: any active mode can host any tool.

import Foundation

public enum Tool: Equatable, Hashable, Sendable {
    case pen
    case selection
}
```

Create `Sources/Core/Model/PointerModifiers.swift`:

```swift
// ABOUTME: Modifier-key state carried alongside a pointer event so Core sees
// ABOUTME: Cmd / Shift without importing AppKit. AppKit's NSEventInputSource
// ABOUTME: extracts event.modifierFlags into one of these on every dispatch.

import Foundation

public struct PointerModifiers: Equatable, Hashable, Sendable {
    public var command: Bool
    public var shift: Bool

    public init(command: Bool = false, shift: Bool = false) {
        self.command = command
        self.shift = shift
    }

    public static let none = PointerModifiers()
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `just check`
Expected: 4 new tests pass; lint clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Model/Tool.swift \
        Sources/Core/Model/PointerModifiers.swift \
        Tests/CoreTests/ToolTests.swift \
        Tests/CoreTests/PointerModifiersTests.swift
git commit -m "$(cat <<'EOF'
Core: Tool enum + PointerModifiers value for selection-tool foundation

Tool is the active interaction mode (.pen or .selection) on top of
AppController.Mode — orthogonal so future tools don't explode the Mode
enum. PointerModifiers carries Cmd / Shift bools so AppKit can pass
modifier state into Core without leaking NSEvent.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `Rect` + `SelectionMath` pure-function module

Pure-Core geometry. `Rect` is a small new value because Core doesn't have one yet; `SelectionMath` exposes hit-testing, marquee selection, and selection-bounds math.

**Files:**
- Create: `Sources/Core/Model/Rect.swift`
- Create: `Sources/Core/Selection/SelectionMath.swift`
- Create: `Tests/CoreTests/RectTests.swift`
- Create: `Tests/CoreTests/SelectionMathTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/RectTests.swift`:

```swift
// ABOUTME: Tests for the Core Rect value — origin + size, intersection,
// ABOUTME: contains-point. Doesn't import CoreGraphics.

import Testing

@Suite("Rect")
struct RectTests {
    @Test("rect stores x/y/width/height")
    func basicShape() {
        let r = Rect(x: 1, y: 2, width: 3, height: 4)
        #expect(r.x == 1)
        #expect(r.y == 2)
        #expect(r.width == 3)
        #expect(r.height == 4)
    }

    @Test("intersects returns true when rects overlap")
    func intersectsOverlap() {
        let a = Rect(x: 0, y: 0, width: 10, height: 10)
        let b = Rect(x: 5, y: 5, width: 10, height: 10)
        #expect(a.intersects(b))
        #expect(b.intersects(a))
    }

    @Test("intersects returns false when rects are disjoint")
    func intersectsDisjoint() {
        let a = Rect(x: 0, y: 0, width: 5, height: 5)
        let b = Rect(x: 10, y: 10, width: 5, height: 5)
        #expect(!a.intersects(b))
    }

    @Test("intersects returns true when one rect contains the other")
    func intersectsContained() {
        let outer = Rect(x: 0, y: 0, width: 100, height: 100)
        let inner = Rect(x: 10, y: 10, width: 5, height: 5)
        #expect(outer.intersects(inner))
        #expect(inner.intersects(outer))
    }
}
```

Create `Tests/CoreTests/SelectionMathTests.swift`:

```swift
// ABOUTME: Tests for SelectionMath pure functions — hit-test, marquee-hit,
// ABOUTME: and selectionBounds. No state, no AppKit.

import Testing

@Suite("SelectionMath")
struct SelectionMathTests {
    private func makeStroke(id: String, points: [StrokePoint], width: Double = 4,
                            transform: Transform = .identity) -> Stroke {
        Stroke(id: id, color: RGBA(r: 0, g: 0, b: 0, a: 1), width: width,
               transform: transform, points: points,
               pointerType: .mouse, pressureEnabled: false, createdAt: 0)
    }

    // MARK: hitTest

    @Test("hitTest returns the stroke when the query is on its polyline")
    func hitTestOnPoint() {
        let s = makeStroke(id: "a", points: [StrokePoint(x: 0, y: 0), StrokePoint(x: 100, y: 0)])
        let hit = SelectionMath.hitTest(point: StrokePoint(x: 50, y: 0), strokes: [s], tolerance: 1)
        #expect(hit == "a")
    }

    @Test("hitTest returns the stroke when the query is within width/2 + tolerance")
    func hitTestWithinHalfWidth() {
        let s = makeStroke(id: "a", points: [StrokePoint(x: 0, y: 0), StrokePoint(x: 100, y: 0)], width: 10)
        // half-width = 5, tolerance = 1 → within 6 of the line counts as a hit
        let hit = SelectionMath.hitTest(point: StrokePoint(x: 50, y: 4), strokes: [s], tolerance: 1)
        #expect(hit == "a")
    }

    @Test("hitTest returns nil when the query is too far from any stroke")
    func hitTestFar() {
        let s = makeStroke(id: "a", points: [StrokePoint(x: 0, y: 0), StrokePoint(x: 100, y: 0)], width: 10)
        let hit = SelectionMath.hitTest(point: StrokePoint(x: 50, y: 50), strokes: [s], tolerance: 1)
        #expect(hit == nil)
    }

    @Test("hitTest with overlapping strokes returns the topmost (last in array)")
    func hitTestTopmost() {
        let s1 = makeStroke(id: "bottom", points: [StrokePoint(x: 0, y: 0), StrokePoint(x: 100, y: 0)])
        let s2 = makeStroke(id: "top", points: [StrokePoint(x: 0, y: 0), StrokePoint(x: 100, y: 0)])
        let hit = SelectionMath.hitTest(point: StrokePoint(x: 50, y: 0), strokes: [s1, s2], tolerance: 1)
        #expect(hit == "top")
    }

    @Test("hitTest with empty stroke array returns nil")
    func hitTestEmpty() {
        let hit = SelectionMath.hitTest(point: StrokePoint(x: 0, y: 0), strokes: [], tolerance: 1)
        #expect(hit == nil)
    }

    // MARK: marqueeHit

    @Test("marqueeHit returns strokes whose AABB intersects the marquee")
    func marqueeIntersect() {
        let s1 = makeStroke(id: "in", points: [StrokePoint(x: 10, y: 10), StrokePoint(x: 20, y: 20)])
        let s2 = makeStroke(id: "out", points: [StrokePoint(x: 100, y: 100), StrokePoint(x: 110, y: 110)])
        let ids = SelectionMath.marqueeHit(rect: Rect(x: 0, y: 0, width: 30, height: 30),
                                           strokes: [s1, s2])
        #expect(ids == ["in"])
    }

    @Test("marqueeHit returns all intersecting strokes in z-order")
    func marqueeMultiple() {
        let s1 = makeStroke(id: "a", points: [StrokePoint(x: 5, y: 5), StrokePoint(x: 15, y: 15)])
        let s2 = makeStroke(id: "b", points: [StrokePoint(x: 20, y: 20), StrokePoint(x: 25, y: 25)])
        let ids = SelectionMath.marqueeHit(rect: Rect(x: 0, y: 0, width: 30, height: 30),
                                           strokes: [s1, s2])
        #expect(ids == ["a", "b"])
    }

    @Test("marqueeHit with no overlap returns empty")
    func marqueeEmpty() {
        let s = makeStroke(id: "a", points: [StrokePoint(x: 100, y: 100), StrokePoint(x: 110, y: 110)])
        let ids = SelectionMath.marqueeHit(rect: Rect(x: 0, y: 0, width: 30, height: 30),
                                           strokes: [s])
        #expect(ids.isEmpty)
    }

    // MARK: selectionBounds

    @Test("selectionBounds returns the AABB enclosing all selected strokes")
    func boundsUnion() {
        let s1 = makeStroke(id: "a", points: [StrokePoint(x: 0, y: 0), StrokePoint(x: 10, y: 10)])
        let s2 = makeStroke(id: "b", points: [StrokePoint(x: 20, y: 20), StrokePoint(x: 30, y: 40)])
        let bounds = SelectionMath.selectionBounds(strokeIds: ["a", "b"],
                                                   strokes: ["a": s1, "b": s2])
        #expect(bounds == Rect(x: 0, y: 0, width: 30, height: 40))
    }

    @Test("selectionBounds with empty id list returns nil")
    func boundsEmpty() {
        let bounds = SelectionMath.selectionBounds(strokeIds: [],
                                                   strokes: [String: Stroke]())
        #expect(bounds == nil)
    }

    @Test("selectionBounds with unknown id is skipped")
    func boundsUnknownId() {
        let s = makeStroke(id: "a", points: [StrokePoint(x: 5, y: 5), StrokePoint(x: 15, y: 15)])
        let bounds = SelectionMath.selectionBounds(strokeIds: ["a", "missing"],
                                                   strokes: ["a": s])
        #expect(bounds == Rect(x: 5, y: 5, width: 10, height: 10))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test`
Expected: compile errors — `Rect`, `SelectionMath` not found.

- [ ] **Step 3: Create `Rect`**

Create `Sources/Core/Model/Rect.swift`:

```swift
// ABOUTME: Pure-Core axis-aligned bounding rectangle. Used by SelectionMath
// ABOUTME: and the AppKit renderer for selection box / marquee geometry.

import Foundation

public struct Rect: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    public func intersects(_ other: Rect) -> Bool {
        x < other.maxX && other.x < maxX && y < other.maxY && other.y < maxY
    }

    public func contains(_ p: StrokePoint) -> Bool {
        p.x >= x && p.x <= maxX && p.y >= y && p.y <= maxY
    }
}
```

- [ ] **Step 4: Create `SelectionMath`**

Create `Sources/Core/Selection/SelectionMath.swift`:

```swift
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
            let bounds = aabb(of: transformed(points: stroke.points, by: stroke.transform))
            return rect.intersects(bounds) ? stroke.id : nil
        }
    }

    /// AABB enclosing the union of every selected stroke's transformed points.
    public static func selectionBounds(strokeIds: [StrokeId], strokes: [String: Stroke]) -> Rect? {
        var union: Rect?
        for id in strokeIds {
            guard let s = strokes[id] else { continue }
            let bounds = aabb(of: transformed(points: s.points, by: s.transform))
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
            return StrokePoint(x: rx + t.x, y: ry + t.y)
        }
    }

    private static func aabb(of points: [StrokePoint]) -> Rect {
        guard let first = points.first else { return Rect(x: 0, y: 0, width: 0, height: 0) }
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
```

- [ ] **Step 5: Run the full check**

Run: `just check`
Expected: 12 new tests (4 Rect + 8 SelectionMath) pass; existing tests still green; lint clean.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Model/Rect.swift \
        Sources/Core/Selection/SelectionMath.swift \
        Tests/CoreTests/RectTests.swift \
        Tests/CoreTests/SelectionMathTests.swift
git commit -m "$(cat <<'EOF'
Core: Rect + SelectionMath — hit-testing and marquee math for selection

Rect is a pure-Core AABB value with intersect + contains. SelectionMath
exposes three pure functions: hitTest (topmost-stroke distance from
polyline), marqueeHit (AABB intersection), and selectionBounds (union
AABB over selected strokes). All apply the stroke's Transform before
computing geometry so rotated/scaled strokes hit-test correctly.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Editor batched ops + new `InverseOp.setTransforms`

Two new Editor methods, both single undoable ops, plus the new InverseOp case that captures old transforms.

**Files:**
- Modify: `Sources/Core/Editor/InverseOp.swift`
- Modify: `Sources/Core/Editor/Editor.swift`
- Create: `Tests/CoreTests/EditorTransformStrokesTests.swift`
- Create: `Tests/CoreTests/EditorEraseStrokesTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/EditorTransformStrokesTests.swift`:

```swift
// ABOUTME: Tests for Editor.transformStrokes — batched transform op that
// ABOUTME: captures pre-call transforms as a single undo entry.

import Testing

@Suite("Editor.transformStrokes")
@MainActor
struct EditorTransformStrokesTests {
    private func makeEditorWith(strokes count: Int) -> (Editor, [StrokeId]) {
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        var ids: [StrokeId] = []
        for _ in 0..<count {
            let id = editor.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 2, pointerType: .mouse)
            editor.appendPoint(StrokePoint(x: 0, y: 0))
            editor.endStroke()
            ids.append(id)
        }
        return (editor, ids)
    }

    @Test("applies a transform to each listed stroke")
    func appliesTransforms() {
        let (editor, ids) = makeEditorWith(strokes: 2)
        let t1 = Transform(x: 10, y: 0, scale: 1, rotate: 0)
        let t2 = Transform(x: 0, y: 20, scale: 2, rotate: 0)
        let ok = editor.transformStrokes([(ids[0], t1), (ids[1], t2)])
        #expect(ok == true)
        #expect(editor.doc.strokes[ids[0]]?.transform == t1)
        #expect(editor.doc.strokes[ids[1]]?.transform == t2)
    }

    @Test("transformStrokes is one undo entry — single undo restores all")
    func singleUndoEntry() {
        let (editor, ids) = makeEditorWith(strokes: 2)
        let t1 = Transform(x: 10, y: 0, scale: 1, rotate: 0)
        let t2 = Transform(x: 0, y: 20, scale: 2, rotate: 0)
        editor.transformStrokes([(ids[0], t1), (ids[1], t2)])
        #expect(editor.undo() == true)
        #expect(editor.doc.strokes[ids[0]]?.transform == .identity)
        #expect(editor.doc.strokes[ids[1]]?.transform == .identity)
    }

    @Test("redo re-applies all transforms")
    func redoReapplies() {
        let (editor, ids) = makeEditorWith(strokes: 2)
        let t1 = Transform(x: 10, y: 0, scale: 1, rotate: 0)
        editor.transformStrokes([(ids[0], t1), (ids[1], .identity)])
        editor.undo()
        #expect(editor.redo() == true)
        #expect(editor.doc.strokes[ids[0]]?.transform == t1)
    }

    @Test("transformStrokes with unknown id is skipped, known id still applied")
    func unknownIdSkipped() {
        let (editor, ids) = makeEditorWith(strokes: 1)
        let t = Transform(x: 5, y: 5, scale: 1, rotate: 0)
        let ok = editor.transformStrokes([(ids[0], t), ("missing", t)])
        #expect(ok == true)  // at least one applied
        #expect(editor.doc.strokes[ids[0]]?.transform == t)
    }

    @Test("transformStrokes with no known ids returns false and does not push undo")
    func allUnknownReturnsFalse() {
        let (editor, _) = makeEditorWith(strokes: 1)
        let before = editor.canUndo
        let ok = editor.transformStrokes([("missing", .identity)])
        #expect(ok == false)
        #expect(editor.canUndo == before)
    }
}
```

Create `Tests/CoreTests/EditorEraseStrokesTests.swift`:

```swift
// ABOUTME: Tests for Editor.eraseStrokes — batched erase op that uses the
// ABOUTME: existing restoreStrokes inverse primitive so one undo brings
// ABOUTME: everything back at original z-order.

import Testing

@Suite("Editor.eraseStrokes")
@MainActor
struct EditorEraseStrokesTests {
    private func makeEditorWith(strokes count: Int) -> (Editor, [StrokeId]) {
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        var ids: [StrokeId] = []
        for _ in 0..<count {
            let id = editor.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 2, pointerType: .mouse)
            editor.appendPoint(StrokePoint(x: 0, y: 0))
            editor.endStroke()
            ids.append(id)
        }
        return (editor, ids)
    }

    @Test("eraseStrokes removes all listed strokes")
    func erasesAll() {
        let (editor, ids) = makeEditorWith(strokes: 3)
        let ok = editor.eraseStrokes(ids: [ids[0], ids[2]])
        #expect(ok == true)
        #expect(editor.doc.strokes[ids[0]] == nil)
        #expect(editor.doc.strokes[ids[1]] != nil)
        #expect(editor.doc.strokes[ids[2]] == nil)
    }

    @Test("eraseStrokes is one undoable op")
    func singleUndo() {
        let (editor, ids) = makeEditorWith(strokes: 3)
        editor.eraseStrokes(ids: [ids[0], ids[2]])
        editor.undo()
        #expect(editor.doc.strokes.count == 3)
        #expect(editor.doc.strokeOrder == ids)
    }

    @Test("eraseStrokes with empty list returns false and no-ops")
    func emptyListNoOp() {
        let (editor, _) = makeEditorWith(strokes: 2)
        let before = editor.canUndo
        let ok = editor.eraseStrokes(ids: [])
        #expect(ok == false)
        #expect(editor.canUndo == before)
        #expect(editor.doc.strokes.count == 2)
    }

    @Test("eraseStrokes with unknown ids does nothing and returns false")
    func unknownIdsReturnsFalse() {
        let (editor, _) = makeEditorWith(strokes: 1)
        let ok = editor.eraseStrokes(ids: ["missing"])
        #expect(ok == false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test`
Expected: compile errors — `Editor.transformStrokes`, `Editor.eraseStrokes` not found.

- [ ] **Step 3: Extend `InverseOp`**

Modify `Sources/Core/Editor/InverseOp.swift`. Add a `TransformEntry` struct + a new case:

```swift
public struct TransformEntry: Equatable, Sendable {
    public let strokeId: StrokeId
    public let transform: Transform

    public init(strokeId: StrokeId, transform: Transform) {
        self.strokeId = strokeId
        self.transform = transform
    }
}

public enum InverseOp: Equatable, Sendable {
    case deleteStroke(StrokeId)
    case restoreStroke(snapshot: Stroke, atIndex: Int)
    case deleteStrokes([StrokeId])
    case restoreStrokes(entries: [StrokeRestoreEntry])
    case setTransforms(entries: [TransformEntry])
}
```

- [ ] **Step 4: Implement Editor methods + applyInverse case**

Modify `Sources/Core/Editor/Editor.swift`. Add the two methods alongside the existing `eraseStroke` / `clear`:

```swift
@discardableResult
public func eraseStrokes(ids: [StrokeId]) -> Bool {
    let presentIds = ids.filter { doc.strokes[$0] != nil }
    guard !presentIds.isEmpty else { return false }
    let entries: [StrokeRestoreEntry] = presentIds.compactMap { id in
        guard let s = doc.strokes[id] else { return nil }
        let idx = doc.strokeOrder.firstIndex(of: id) ?? doc.strokeOrder.count
        return StrokeRestoreEntry(snapshot: s, atIndex: idx)
    }
    for id in presentIds {
        doc.strokes.removeValue(forKey: id)
        doc.strokeOrder.removeAll { $0 == id }
    }
    pushUndo(.restoreStrokes(entries: entries))
    emit(.local)
    return true
}

@discardableResult
public func transformStrokes(_ updates: [(id: StrokeId, transform: Transform)]) -> Bool {
    let known = updates.filter { doc.strokes[$0.id] != nil }
    guard !known.isEmpty else { return false }
    let oldEntries: [TransformEntry] = known.map { update in
        TransformEntry(strokeId: update.id, transform: doc.strokes[update.id]!.transform)
    }
    for update in known {
        if var stroke = doc.strokes[update.id] {
            stroke.transform = update.transform
            doc.strokes[update.id] = stroke
        }
    }
    pushUndo(.setTransforms(entries: oldEntries))
    emit(.local)
    return true
}
```

Add the matching `applyInverse` case in the existing switch:

```swift
case .setTransforms(let entries):
    var currentEntries: [TransformEntry] = []
    for entry in entries {
        guard var stroke = doc.strokes[entry.strokeId] else { continue }
        currentEntries.append(TransformEntry(strokeId: entry.strokeId, transform: stroke.transform))
        stroke.transform = entry.transform
        doc.strokes[entry.strokeId] = stroke
    }
    return .setTransforms(entries: currentEntries)
```

- [ ] **Step 5: Run the full check**

Run: `just check`
Expected: 9 new tests pass; lint clean.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Editor/InverseOp.swift \
        Sources/Core/Editor/Editor.swift \
        Tests/CoreTests/EditorTransformStrokesTests.swift \
        Tests/CoreTests/EditorEraseStrokesTests.swift
git commit -m "$(cat <<'EOF'
Core: Editor.transformStrokes + Editor.eraseStrokes — batched undoable ops

transformStrokes captures pre-call transforms as a single setTransforms
inverse op (new InverseOp case), so a multi-stroke drag commits one
undo entry. eraseStrokes reuses the existing restoreStrokes primitive
so a multi-stroke delete one-undos cleanly. Both are no-ops on empty
or all-unknown input.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `AppController` selection state + selection-aware `run(.clear)`

Add the new properties and publishers; make the cursor return `nil` (system arrow) under `.selection`; make `run(.clear)` selection-aware.

**Files:**
- Modify: `Sources/Core/Control/AppController.swift`
- Create: `Tests/CoreTests/AppControllerTests/ToolStateTests.swift`
- Create: `Tests/CoreTests/AppControllerTests/SelectionStateTests.swift`
- Modify: `Tests/CoreTests/AppControllerTests/RunCommandTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/AppControllerTests/ToolStateTests.swift`:

```swift
// ABOUTME: Tests for AppController.currentTool — defaults, publisher, and
// ABOUTME: cursor behavior (selection tool returns the system arrow).

import Testing

@Suite("AppController.currentTool")
@MainActor
struct ToolStateTests {
    private func make() -> AppController {
        let clock = VirtualClock()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        return AppController(
            editor: editor,
            window: RecordingWindow(),
            detector: RecordingStationaryDetector(),
            clock: clock,
            ticker: RecordingFadeTicker()
        )
    }

    @Test("currentTool defaults to .pen")
    func defaultsToPen() {
        let c = make()
        #expect(c.currentTool == .pen)
    }

    @Test("onCurrentToolChanged publisher fires on transition")
    func publisherFires() {
        let c = make()
        var values: [Tool] = []
        c.onCurrentToolChanged = { values.append($0) }
        c.currentTool = .selection
        c.currentTool = .pen
        #expect(values == [.selection, .pen])
    }

    @Test("setting currentTool to its current value does not fire publisher")
    func idempotent() {
        let c = make()
        var count = 0
        c.onCurrentToolChanged = { _ in count += 1 }
        c.currentTool = .pen
        #expect(count == 0)
    }

    @Test("cursor is nil (system arrow) while currentTool is .selection in an active mode")
    func cursorUnderSelection() {
        let c = make()
        c.activate()  // mode -> .activeIdle
        #expect(c.currentCursor != nil)  // pen cursor
        c.currentTool = .selection
        #expect(c.currentCursor == nil)  // system arrow
        c.currentTool = .pen
        #expect(c.currentCursor != nil)
    }
}
```

Create `Tests/CoreTests/AppControllerTests/SelectionStateTests.swift`:

```swift
// ABOUTME: Tests for AppController.selectedStrokeIds and inFlightTransforms
// ABOUTME: — pure state + publishers. Gesture-driven population is in
// ABOUTME: SelectionGestureTests once the state machine lands.

import Testing

@Suite("AppController selection state")
@MainActor
struct SelectionStateTests {
    private func make() -> AppController {
        let clock = VirtualClock()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        return AppController(
            editor: editor,
            window: RecordingWindow(),
            detector: RecordingStationaryDetector(),
            clock: clock,
            ticker: RecordingFadeTicker()
        )
    }

    @Test("selectedStrokeIds defaults to empty")
    func selectedDefaultsEmpty() {
        let c = make()
        #expect(c.selectedStrokeIds == [])
    }

    @Test("onSelectionChanged fires on change")
    func selectionPublisher() {
        let c = make()
        var values: [[StrokeId]] = []
        c.onSelectionChanged = { values.append($0) }
        c.selectedStrokeIds = ["a", "b"]
        c.selectedStrokeIds = []
        #expect(values == [["a", "b"], []])
    }

    @Test("idempotent assignment does not fire publisher")
    func selectionIdempotent() {
        let c = make()
        var count = 0
        c.onSelectionChanged = { _ in count += 1 }
        c.selectedStrokeIds = []
        #expect(count == 0)
    }

    @Test("inFlightTransforms defaults to empty")
    func inFlightDefaultsEmpty() {
        let c = make()
        #expect(c.inFlightTransforms.isEmpty)
    }

    @Test("onInFlightTransformsChanged fires on change")
    func inFlightPublisher() {
        let c = make()
        var fireCount = 0
        c.onInFlightTransformsChanged = { _ in fireCount += 1 }
        c.inFlightTransforms = ["a": Transform(x: 1, y: 0, scale: 1, rotate: 0)]
        #expect(fireCount == 1)
        c.inFlightTransforms = [:]
        #expect(fireCount == 2)
    }
}
```

Modify `Tests/CoreTests/AppControllerTests/RunCommandTests.swift` — append a new suite or add to the existing one (use whichever matches the existing file's structure):

```swift
@Test("run(.clear) with non-empty selectedStrokeIds erases only those strokes")
func clearWithSelectionErasesSelected() {
    let (c, editor, _) = make()  // make() helper from existing tests
    c.activate()
    c.pointerDown(StrokePoint(x: 0, y: 0))
    c.pointerUp()
    c.pointerDown(StrokePoint(x: 10, y: 10))
    c.pointerUp()
    let allIds = editor.doc.strokeOrder
    #expect(allIds.count == 2)
    c.selectedStrokeIds = [allIds[0]]
    c.run(.clear)
    #expect(editor.doc.strokes[allIds[0]] == nil)
    #expect(editor.doc.strokes[allIds[1]] != nil)
    #expect(c.selectedStrokeIds == [])  // selection cleared after delete
}

@Test("run(.clear) with empty selection clears everything (existing behavior)")
func clearWithoutSelectionClearsAll() {
    let (c, editor, _) = make()
    c.activate()
    c.pointerDown(StrokePoint(x: 0, y: 0))
    c.pointerUp()
    #expect(editor.doc.strokeOrder.count == 1)
    c.run(.clear)
    #expect(editor.doc.strokeOrder.isEmpty)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test`
Expected: compile errors — `currentTool`, `selectedStrokeIds`, `inFlightTransforms`, `onCurrentToolChanged`, etc. not found.

- [ ] **Step 3: Add state + publishers to `AppController`**

Modify `Sources/Core/Control/AppController.swift`. Add near the existing publishers:

```swift
public private(set) var currentTool: Tool = .pen {
    didSet {
        guard oldValue != currentTool else { return }
        onCurrentToolChanged?(currentTool)
        refreshCursor()
    }
}
public var onCurrentToolChanged: ((Tool) -> Void)?

public var selectedStrokeIds: [StrokeId] = [] {
    didSet { if oldValue != selectedStrokeIds { onSelectionChanged?(selectedStrokeIds) } }
}
public var onSelectionChanged: (([StrokeId]) -> Void)?

public var inFlightTransforms: [StrokeId: Transform] = [:] {
    didSet { onInFlightTransformsChanged?(inFlightTransforms) }
}
public var onInFlightTransformsChanged: (([StrokeId: Transform]) -> Void)?
```

Note: `currentTool` is `public private(set)` so external code (KeyMonitor) writes through a method or directly via internal access. For now keep `private(set)` — Task 6 will adjust to `public` write or expose a `setTool(_:)` method.

Actually let's make it `public var currentTool` (settable from outside) since KeyMonitor will need to write it directly. Update the test accordingly:

Reconsider: making it `public var` means HTTP and other adapters could also flip the tool. That's fine — same model as `drawingsVisible`. Use `public var`.

Update the `currentCursor` computed property:

```swift
public var currentCursor: CursorSpec? {
    if mode == .inactive { return nil }
    if currentTool == .selection { return nil }  // system arrow
    return CursorSpec(color: currentColor, diameter: currentWidth)
}
```

Update `run(.clear)`:

```swift
case .clear:
    if !selectedStrokeIds.isEmpty {
        _ = editor.eraseStrokes(ids: selectedStrokeIds)
        selectedStrokeIds = []
    } else {
        clear()
    }
```

- [ ] **Step 4: Run the full check**

Run: `just check`
Expected: ~9 new tests pass; existing tests still green (including all prior `RunCommandTests`); lint clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Control/AppController.swift \
        Tests/CoreTests/AppControllerTests/ToolStateTests.swift \
        Tests/CoreTests/AppControllerTests/SelectionStateTests.swift \
        Tests/CoreTests/AppControllerTests/RunCommandTests.swift
git commit -m "$(cat <<'EOF'
Core: AppController selection state + selection-aware run(.clear)

Adds currentTool (.pen / .selection), selectedStrokeIds, and
inFlightTransforms with publishers. The Delete key (run(.clear)) now
erases only the selection when non-empty; Cmd+K is unaffected because
it goes through clear() directly. Cursor returns nil (system arrow)
under .selection so the AppKit side picks up the arrow automatically.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: `pointerDown(_:modifiers:)` overload + selection gesture state machine

The biggest task. Add the modifier-carrying overloads, route into a selection state machine, and implement the four gesture kinds (click-select, marquee, drag-translate, resize, rotate). All gesture math lives in this file.

**Files:**
- Modify: `Sources/Core/Control/AppController.swift`
- Create: `Tests/CoreTests/AppControllerTests/SelectionGestureTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/AppControllerTests/SelectionGestureTests.swift`. The file is long — include each sub-suite. Helpers at the top:

```swift
// ABOUTME: Tests for AppController's selection gesture state machine —
// ABOUTME: click-to-select, Cmd-click toggle, marquee, drag-translate,
// ABOUTME: corner-handle scale, and rotation-handle rotate.

import Testing

@Suite("AppController selection gestures")
@MainActor
struct SelectionGestureTests {
    private func setup() -> (AppController, Editor, [StrokeId]) {
        let clock = VirtualClock()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(
            editor: editor,
            window: RecordingWindow(),
            detector: RecordingStationaryDetector(),
            clock: clock,
            ticker: RecordingFadeTicker()
        )
        // Draw two strokes at known locations so hit-tests are deterministic.
        controller.activate()
        controller.pointerDown(StrokePoint(x: 10, y: 10))
        controller.pointerMoved(StrokePoint(x: 30, y: 10))
        controller.pointerUp()
        controller.pointerDown(StrokePoint(x: 100, y: 100))
        controller.pointerMoved(StrokePoint(x: 120, y: 100))
        controller.pointerUp()
        controller.currentTool = .selection
        return (controller, editor, editor.doc.strokeOrder)
    }

    // MARK: click-to-select

    @Test("click on a stroke replaces selection with that stroke")
    func clickReplacesSelection() {
        let (c, _, ids) = setup()
        c.pointerDown(StrokePoint(x: 20, y: 10))  // on first stroke
        c.pointerUp()
        #expect(c.selectedStrokeIds == [ids[0]])
    }

    @Test("clicking a second stroke replaces (not adds)")
    func clickReplacesEvenWithExisting() {
        let (c, _, ids) = setup()
        c.pointerDown(StrokePoint(x: 20, y: 10))
        c.pointerUp()
        c.pointerDown(StrokePoint(x: 110, y: 100))
        c.pointerUp()
        #expect(c.selectedStrokeIds == [ids[1]])
    }

    @Test("Cmd-click toggles a stroke into / out of selection")
    func cmdClickToggles() {
        let (c, _, ids) = setup()
        c.pointerDown(StrokePoint(x: 20, y: 10), modifiers: PointerModifiers(command: true))
        c.pointerUp()
        #expect(c.selectedStrokeIds == [ids[0]])
        c.pointerDown(StrokePoint(x: 110, y: 100), modifiers: PointerModifiers(command: true))
        c.pointerUp()
        #expect(Set(c.selectedStrokeIds) == Set(ids))
        c.pointerDown(StrokePoint(x: 20, y: 10), modifiers: PointerModifiers(command: true))
        c.pointerUp()
        #expect(c.selectedStrokeIds == [ids[1]])
    }

    // MARK: marquee

    @Test("drag from empty area marquees over intersecting strokes")
    func marqueeSelectsIntersecting() {
        let (c, _, ids) = setup()
        c.pointerDown(StrokePoint(x: 0, y: 0))  // empty point near (but not on) stroke 0
        c.pointerMoved(StrokePoint(x: 50, y: 50))
        c.pointerUp()
        #expect(c.selectedStrokeIds == [ids[0]])
    }

    @Test("a marquee that includes both strokes selects both")
    func marqueeBoth() {
        let (c, _, ids) = setup()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.pointerMoved(StrokePoint(x: 200, y: 200))
        c.pointerUp()
        #expect(Set(c.selectedStrokeIds) == Set(ids))
    }

    @Test("marquee starting in empty space clears prior selection on commit")
    func marqueeClearsPriorSelection() {
        let (c, _, ids) = setup()
        c.selectedStrokeIds = [ids[0], ids[1]]
        c.pointerDown(StrokePoint(x: 500, y: 500))  // empty, far from all strokes
        c.pointerMoved(StrokePoint(x: 550, y: 550))
        c.pointerUp()
        #expect(c.selectedStrokeIds == [])  // marquee hit nothing → empty selection
    }

    // MARK: drag-translate

    @Test("drag on a stroke translates it; one undoable op")
    func dragTranslate() {
        let (c, editor, ids) = setup()
        // First click-and-drag in one motion: pointerDown selects + starts translate
        c.pointerDown(StrokePoint(x: 20, y: 10))
        c.pointerMoved(StrokePoint(x: 25, y: 15))
        c.pointerMoved(StrokePoint(x: 30, y: 20))
        c.pointerUp()
        #expect(editor.doc.strokes[ids[0]]?.transform.x == 10)  // +20 - +10 = 10 from drag delta
        #expect(editor.doc.strokes[ids[0]]?.transform.y == 10)
        // Undo restores
        editor.undo()
        #expect(editor.doc.strokes[ids[0]]?.transform == .identity)
    }

    // MARK: pen mode bypasses selection

    @Test("pointerDown while currentTool == .pen draws a stroke")
    func penIgnoresSelection() {
        let (c, editor, _) = setup()
        c.currentTool = .pen
        let before = editor.doc.strokes.count
        c.pointerDown(StrokePoint(x: 300, y: 300))
        c.pointerUp()
        #expect(editor.doc.strokes.count == before + 1)
    }

    // MARK: drawing new stroke clears selection

    @Test("drawing a new stroke while having a selection clears the selection")
    func drawClearsSelection() {
        let (c, _, ids) = setup()
        c.selectedStrokeIds = [ids[0]]
        c.currentTool = .pen
        c.pointerDown(StrokePoint(x: 300, y: 300))
        c.pointerUp()
        #expect(c.selectedStrokeIds == [])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test`
Expected: compile errors — `pointerDown(_:modifiers:)` overload not found.

- [ ] **Step 3: Add modifier-carrying overloads + selection routing**

Modify `Sources/Core/Control/AppController.swift`. Three additions:

**3a. Internal gesture state:**

```swift
private enum SelectionGesture {
    case marquee(startPoint: StrokePoint)
    case translate(startPoint: StrokePoint, originalTransforms: [StrokeId: Transform])
    // case resize and case rotate come in a later iteration of this task; for
    // now the test suite only exercises click, marquee, and translate.
}

private var selectionGesture: SelectionGesture?
```

**3b. New pointer overloads:**

```swift
public func pointerDown(_ point: StrokePoint) {
    pointerDown(point, modifiers: .none)
}

public func pointerDown(_ point: StrokePoint, modifiers: PointerModifiers) {
    lastInputAt = clock.now()
    guard mode != .inactive else { return }
    switch currentTool {
    case .pen:
        if !selectedStrokeIds.isEmpty { selectedStrokeIds = [] }  // drawing clears prior selection
        penPointerDown(point)
    case .selection:
        selectionPointerDown(point, modifiers: modifiers)
    }
}

public func pointerMoved(_ point: StrokePoint) {
    pointerMoved(point, modifiers: .none)
}

public func pointerMoved(_ point: StrokePoint, modifiers: PointerModifiers) {
    lastInputAt = clock.now()
    guard mode != .inactive else { return }
    switch currentTool {
    case .pen:  penPointerMoved(point)
    case .selection: selectionPointerMoved(point, modifiers: modifiers)
    }
}

public func pointerUp() {
    pointerUp(modifiers: .none)
}

public func pointerUp(modifiers: PointerModifiers) {
    lastInputAt = clock.now()
    guard mode != .inactive else { return }
    switch currentTool {
    case .pen: penPointerUp()
    case .selection: selectionPointerUp(modifiers: modifiers)
    }
}
```

Rename the EXISTING bodies of `pointerDown`, `pointerMoved`, `pointerUp` to `penPointerDown`, `penPointerMoved`, `penPointerUp` (private). Their internals stay the same.

**3c. Selection routing implementation:**

```swift
private func selectionPointerDown(_ point: StrokePoint, modifiers: PointerModifiers) {
    let strokes = editor.doc.strokeOrder.compactMap { editor.doc.strokes[$0] }
    if let hitId = SelectionMath.hitTest(point: point, strokes: strokes, tolerance: 4) {
        if modifiers.command {
            // Toggle membership without entering a drag.
            if selectedStrokeIds.contains(hitId) {
                selectedStrokeIds.removeAll { $0 == hitId }
            } else {
                selectedStrokeIds.append(hitId)
            }
            selectionGesture = nil
        } else {
            // Replace selection and start a drag-translate.
            if selectedStrokeIds != [hitId] { selectedStrokeIds = [hitId] }
            let originals = Dictionary(uniqueKeysWithValues:
                selectedStrokeIds.compactMap { id -> (StrokeId, Transform)? in
                    guard let s = editor.doc.strokes[id] else { return nil }
                    return (id, s.transform)
                })
            selectionGesture = .translate(startPoint: point, originalTransforms: originals)
        }
    } else {
        // Empty space: start a marquee.
        selectionGesture = .marquee(startPoint: point)
    }
}

private func selectionPointerMoved(_ point: StrokePoint, modifiers: PointerModifiers) {
    guard let gesture = selectionGesture else { return }
    switch gesture {
    case .marquee:
        // The marquee rect is presented via `currentMarqueeRect` (a derived
        // property the renderer will read in Task 8). Updating gesture state
        // here is enough; the renderer subscribes to onSelectionChanged or
        // to a dedicated onMarqueeChanged publisher (added in Task 8).
        break  // rectangle computed in pointerUp from start + end
    case .translate(let startPoint, let originals):
        let dx = point.x - startPoint.x
        let dy = point.y - startPoint.y
        var preview: [StrokeId: Transform] = [:]
        for (id, original) in originals {
            preview[id] = Transform(x: original.x + dx, y: original.y + dy,
                                    scale: original.scale, rotate: original.rotate)
        }
        inFlightTransforms = preview
    }
}

private func selectionPointerUp(modifiers: PointerModifiers) {
    defer {
        selectionGesture = nil
        if !inFlightTransforms.isEmpty { inFlightTransforms = [:] }
    }
    guard let gesture = selectionGesture else { return }
    switch gesture {
    case .marquee(let startPoint):
        // (we don't have the endPoint stored — use the last lastInputAt
        // delivery. Simpler: cache endPoint here as a separate private var
        // updated in selectionPointerMoved. Implementer should add that.)
        // For the test code above, the marquee rect spans startPoint to the
        // last pointerMoved point. Store endPoint in a private var.
        // Pseudocode:
        let endPoint = lastSelectionPoint ?? startPoint
        let rect = Rect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
        let strokes = editor.doc.strokeOrder.compactMap { editor.doc.strokes[$0] }
        selectedStrokeIds = SelectionMath.marqueeHit(rect: rect, strokes: strokes)
    case .translate(_, let originals):
        // Commit the in-flight transforms via Editor.transformStrokes once.
        let updates = inFlightTransforms.map { (id: $0.key, transform: $0.value) }
        if !updates.isEmpty {
            _ = editor.transformStrokes(updates)
        }
        _ = originals  // silence warning; for explicit retain
    }
}
```

Add a private `lastSelectionPoint: StrokePoint?` updated at the top of `selectionPointerMoved` so the marquee end is known on pointerUp. Reset to nil in pointerUp's defer block.

(Resize-handle and rotation-handle gestures are out of this slice. The test suite for those is in Step 4 below as a follow-up commit if you want them separated — for now this commit ships click/marquee/translate, and resize/rotate land in a separate small task. **See "Optional sub-task 5b" at the end of this section.**)

- [ ] **Step 4: Run the full check**

Run: `just check`
Expected: 8 new `SelectionGestureTests` pass; existing tests still green; lint clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Control/AppController.swift \
        Tests/CoreTests/AppControllerTests/SelectionGestureTests.swift
git commit -m "$(cat <<'EOF'
Core: pointerDown/Moved/Up modifier overloads + selection state machine

Adds modifier-carrying overloads of the pointer methods that route into
penPointer* (existing behavior) or selectionPointer* (new) based on
currentTool. Selection click replaces, Cmd-click toggles, drag from
empty space marquees, drag on a stroke translates via the in-flight
overlay. pointerUp commits the final transforms with one editor op.

Resize-corner and rotation-handle gestures land in a follow-up task
since the math is meatier.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

#### Sub-task 5b (optional): resize + rotate gestures

After Task 5 commit lands, add the remaining two gesture kinds. Hit-testing for handles happens at the AppController level using `SelectionMath.selectionBounds`:

```swift
case .resize(startPoint: StrokePoint, anchor: StrokePoint, originalTransforms: ..., originalBounds: Rect)
case .rotate(startPoint: StrokePoint, center: StrokePoint, originalTransforms: ...)
```

For corner-handle hit-test: the AppKit side reports the handle index via a separate `pointerDownOnHandle(index:point:)` API, OR we inline the handle test in `selectionPointerDown` by checking if `point` is within 6pt of any corner of `selectionBounds(for: selectedStrokeIds)`.

This sub-task adds tests for:
- `scaleAroundOppositeCorner` math (uniform scale anchored at opposite corner)
- `rotateAroundCenter` math (rotation around bounding-box center, with shift snapping to 15°)
- One commit per gesture kind.

This is deliberately deferred from the main Task 5 commit to keep that one digestible. If the implementer wants to roll it into Task 5, the test suite above just gets extended.

---

### Task 6: `KeyMonitor` Space press-and-hold

Install a `.keyUp` monitor alongside the existing `.keyDown`. Space keyDown (not autorepeat) → `controller.currentTool = .selection`. Space keyUp → `controller.currentTool = .pen`.

**Files:**
- Modify: `Sources/AppKit/KeyMonitor.swift`
- Modify: `Tests/AppKitTests/KeyMonitorTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/AppKitTests/KeyMonitorTests.swift`:

```swift
@Test("Space keyDown sets currentTool to .selection")
func spaceKeyDownEntersSelection() {
    let (monitor, controller, _) = make()
    #expect(controller.currentTool == .pen)
    _ = monitor.handle(keyEvent(" "))
    #expect(controller.currentTool == .selection)
}

@Test("Space keyUp reverts currentTool to .pen")
func spaceKeyUpExitsSelection() {
    let (monitor, controller, _) = make()
    _ = monitor.handle(keyEvent(" "))
    #expect(controller.currentTool == .selection)
    _ = monitor.handle(keyUpEvent(" "))
    #expect(controller.currentTool == .pen)
}

@Test("Space autorepeat (isARepeat=true) does not re-fire the tool transition")
func spaceRepeatIgnored() {
    let (monitor, controller, _) = make()
    var fireCount = 0
    controller.onCurrentToolChanged = { _ in fireCount += 1 }
    _ = monitor.handle(keyEvent(" "))  // initial keyDown
    _ = monitor.handle(keyEvent(" ", isARepeat: true))
    _ = monitor.handle(keyEvent(" ", isARepeat: true))
    #expect(fireCount == 1)
}
```

Update the `keyEvent` helper to accept `isARepeat` and create `keyUpEvent`:

```swift
private func keyEvent(_ chars: String, shift: Bool = false, command: Bool = false, isARepeat: Bool = false) -> NSEvent {
    var flags: NSEvent.ModifierFlags = []
    if shift { flags.insert(.shift) }
    if command { flags.insert(.command) }
    return NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: flags,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: chars,
        charactersIgnoringModifiers: chars,
        isARepeat: isARepeat,
        keyCode: 0
    )!
}

private func keyUpEvent(_ chars: String) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyUp,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: chars,
        charactersIgnoringModifiers: chars,
        isARepeat: false,
        keyCode: 0
    )!
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test`
Expected: assertion fails — KeyMonitor doesn't handle Space yet.

- [ ] **Step 3: Update `KeyMonitor`**

Modify `Sources/AppKit/KeyMonitor.swift`:

1. Change `addLocalMonitorForEvents(matching: .keyDown)` to `addLocalMonitorForEvents(matching: [.keyDown, .keyUp])`.

2. In `handle(_:)`, add Space-specific branches BEFORE the existing single-character-registry lookup:

```swift
internal func handle(_ event: NSEvent) -> NSEvent? {
    guard let chars = event.charactersIgnoringModifiers,
          chars.count == 1,
          let ch = chars.lowercased().first else {
        return event
    }
    // Space press-and-hold drives the selection tool.
    if ch == " " {
        if event.type == .keyDown {
            if event.isARepeat { return nil }  // swallow autorepeats
            controller.currentTool = .selection
            return nil
        }
        if event.type == .keyUp {
            controller.currentTool = .pen
            return nil
        }
    }
    // Only keyDown reaches the registry lookup below.
    guard event.type == .keyDown else { return event }
    if event.modifierFlags.contains(.command) { return event }
    let binding = KeyBinding(character: ch, shift: event.modifierFlags.contains(.shift))
    guard let command = KeyCommandRegistry.command(for: binding) else { return event }
    controller.run(command)
    return nil
}
```

- [ ] **Step 4: Run the full check**

Run: `just check`
Expected: 3 new tests pass; all prior `KeyMonitorTests` still green (the non-Space tests don't involve keyUp).

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/KeyMonitor.swift \
        Tests/AppKitTests/KeyMonitorTests.swift
git commit -m "$(cat <<'EOF'
AppKit: KeyMonitor handles Space press-and-hold for selection tool

Local monitor now watches both .keyDown and .keyUp. Space keyDown (not
isARepeat) flips controller.currentTool to .selection; keyUp reverts to
.pen. Autorepeats are swallowed so holding Space doesn't churn the
publisher. Existing KeyCommandRegistry dispatch is unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: AppKit modifier plumbing — `CanvasInputDelegate` + `NSEventInputSource`

Thread `NSEvent.modifierFlags` from `CanvasInputView` through the delegate to `NSEventInputSource`, which builds a `PointerModifiers` and calls `controller.pointerDown(_:modifiers:)` etc.

**Files:**
- Modify: `Sources/AppKit/NSEventInputSource.swift`
- Modify: `Sources/App/main.swift` (only the input wiring callbacks)

- [ ] **Step 1: Inventory existing callers of the delegate protocol**

```bash
grep -rn "CanvasInputDelegate\|canvasInput.*Down\|canvasInput.*Up\|canvasInput.*Dragged" \
  Sources/ Tests/
```

Existing implementers: `NSEventInputSource`. Existing callers: `CanvasInputView.mouseDown/Dragged/Up`. Tests: any AppKitTests that construct an `NSEventInputSource`.

- [ ] **Step 2: Update the protocol to carry modifiers**

Modify `Sources/AppKit/NSEventInputSource.swift`. Extend the delegate protocol with the modifier-carrying form, keeping the bare form as a default:

```swift
public protocol CanvasInputDelegate: AnyObject {
    func canvasInput(_ view: CanvasInputView, mouseDownAt point: CGPoint, modifiers: PointerModifiers)
    func canvasInput(_ view: CanvasInputView, mouseDraggedAt point: CGPoint, modifiers: PointerModifiers)
    func canvasInput(_ view: CanvasInputView, mouseUpAt point: CGPoint, modifiers: PointerModifiers)
}
```

(Delete the old method signatures or provide default-impl forwarders. Since `NSEventInputSource` is the only conformer, it's simpler to update its conformance directly.)

Update `CanvasInputView.mouseDown/Dragged/Up` to read modifiers from the event:

```swift
public override func mouseDown(with event: NSEvent) {
    let p = convert(event.locationInWindow, from: nil)
    let m = PointerModifiers(
        command: event.modifierFlags.contains(.command),
        shift: event.modifierFlags.contains(.shift)
    )
    delegate?.canvasInput(self, mouseDownAt: p, modifiers: m)
}
// Same for mouseDragged and mouseUp.
```

Update `NSEventInputSource`'s callbacks to surface `PointerModifiers` upstream:

```swift
public var onPointerDown: ((StrokePoint, PointerModifiers) -> Void)?
public var onPointerMoved: ((StrokePoint, PointerModifiers) -> Void)?
public var onPointerUp: ((PointerModifiers) -> Void)?
```

And the delegate conformance:

```swift
extension NSEventInputSource: CanvasInputDelegate {
    public func canvasInput(_ view: CanvasInputView, mouseDownAt point: CGPoint, modifiers: PointerModifiers) {
        onPointerDown?(StrokePoint(x: Double(point.x), y: Double(point.y)), modifiers)
    }
    public func canvasInput(_ view: CanvasInputView, mouseDraggedAt point: CGPoint, modifiers: PointerModifiers) {
        onPointerMoved?(StrokePoint(x: Double(point.x), y: Double(point.y)), modifiers)
    }
    public func canvasInput(_ view: CanvasInputView, mouseUpAt point: CGPoint, modifiers: PointerModifiers) {
        onPointerUp?(modifiers)
    }
}
```

- [ ] **Step 3: Update `main.swift` to thread modifiers**

Modify the input wiring in `applicationDidFinishLaunching`:

```swift
input.onPointerDown   = { [weak self] in self?.controller.pointerDown($0, modifiers: $1) }
input.onPointerMoved  = { [weak self] in self?.controller.pointerMoved($0, modifiers: $1) }
input.onPointerUp     = { [weak self] in self?.controller.pointerUp(modifiers: $0) }
```

- [ ] **Step 4: Run the full check**

Run: `just check`
Expected: all tests still green; build succeeds; lint clean. (No new test file in this task — the delegate-protocol change is exercised through Task 5's gesture tests, which already pass `PointerModifiers` into the AppController overloads. The plumbing is type-checked by the compiler.)

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/NSEventInputSource.swift Sources/App/main.swift
git commit -m "$(cat <<'EOF'
AppKit + App: thread PointerModifiers through CanvasInputView

CanvasInputDelegate methods now carry PointerModifiers extracted from
NSEvent.modifierFlags. NSEventInputSource surfaces them via its
onPointer* closures, and main.swift wires them into the new
controller.pointerDown/Moved/Up(_:modifiers:) overloads. Selection
gestures now see Cmd / Shift natively without leaking NSEvent.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: `RenderFrame.overrides` + `CanvasView` selection rendering + `main.swift` wiring

Final slice. `RenderFrame` learns to compose stroke transforms with controller overrides for in-flight gesture preview. `CanvasView` gains setters for the selection box, handles, and marquee. `main.swift` wires `onSelectionChanged` and `onInFlightTransformsChanged` to the canvas.

**Files:**
- Modify: `Sources/Core/Rendering/RenderFrame.swift`
- Modify: `Sources/AppKit/CanvasView.swift`
- Create: `Tests/AppKitTests/CanvasViewSelectionTests.swift`
- Modify: `Sources/App/main.swift`

- [ ] **Step 1: Extend `RenderFrame.from(editor:canvasSize:)` with overrides**

Modify `Sources/Core/Rendering/RenderFrame.swift`. Add an overload:

```swift
public static func from(editor: Editor, canvasSize: Size, overrides: [StrokeId: Transform]) -> RenderFrame {
    let strokes = editor.doc.strokeOrder.compactMap { id -> Stroke? in
        guard var s = editor.doc.strokes[id] else { return nil }
        if let override = overrides[id] { s.transform = override }
        return s
    }
    return RenderFrame(strokes: strokes,
                       inProgress: editor.currentStroke,
                       canvasSize: canvasSize)
}
```

The existing zero-overrides `from(editor:canvasSize:)` calls into this overload with `overrides: [:]`.

- [ ] **Step 2: Add selection setters to `CanvasView`**

Modify `Sources/AppKit/CanvasView.swift`. Three new properties + setters:

```swift
public private(set) var selectionBounds: Rect?
public private(set) var marqueeRect: Rect?

public func setSelectionBounds(_ rect: Rect?) {
    guard selectionBounds != rect else { return }
    selectionBounds = rect
    needsDisplay = true
}

public func setMarquee(_ rect: Rect?) {
    guard marqueeRect != rect else { return }
    marqueeRect = rect
    needsDisplay = true
}
```

Extend `draw(_:)` to render the selection box and marquee AFTER the stroke pass:

```swift
// After the existing stroke / globalOpacity drawing:
if let sel = selectionBounds {
    drawSelectionBox(sel, in: ctx)
}
if let marq = marqueeRect {
    drawMarquee(marq, in: ctx)
}
```

`drawSelectionBox` draws the AABB outline (1pt, `NSColor.controlAccentColor`), four 6×6pt corner handles, and a rotation handle (circle, 20pt above top mid). `drawMarquee` draws a dashed 1pt accent outline with a 0.15-alpha accent fill.

- [ ] **Step 3: Write `CanvasView` selection tests**

Create `Tests/AppKitTests/CanvasViewSelectionTests.swift`:

```swift
// ABOUTME: Tests for CanvasView's selection setters — selection bounds and
// ABOUTME: marquee rect storage and idempotent set behavior.

import AppKit
import Testing

@Suite("CanvasView selection")
@MainActor
struct CanvasViewSelectionTests {
    private func makeCanvas() -> CanvasView {
        CanvasView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
    }

    @Test("selectionBounds defaults to nil")
    func selectionDefaultsNil() {
        #expect(makeCanvas().selectionBounds == nil)
    }

    @Test("setSelectionBounds stores the value")
    func setStoresSelection() {
        let canvas = makeCanvas()
        let rect = Rect(x: 10, y: 10, width: 50, height: 50)
        canvas.setSelectionBounds(rect)
        #expect(canvas.selectionBounds == rect)
    }

    @Test("idempotent setSelectionBounds does not redraw")
    func idempotentSelectionSet() {
        let canvas = makeCanvas()
        let rect = Rect(x: 10, y: 10, width: 50, height: 50)
        canvas.setSelectionBounds(rect)
        canvas.needsDisplay = false
        canvas.setSelectionBounds(rect)
        #expect(canvas.needsDisplay == false)
    }

    @Test("setMarquee stores the value and marks dirty")
    func marqueeSet() {
        let canvas = makeCanvas()
        canvas.needsDisplay = false
        canvas.setMarquee(Rect(x: 0, y: 0, width: 30, height: 30))
        #expect(canvas.marqueeRect != nil)
        #expect(canvas.needsDisplay == true)
    }

    @Test("setMarquee(nil) clears the rectangle")
    func marqueeClears() {
        let canvas = makeCanvas()
        canvas.setMarquee(Rect(x: 0, y: 0, width: 30, height: 30))
        canvas.setMarquee(nil)
        #expect(canvas.marqueeRect == nil)
    }
}
```

- [ ] **Step 4: Wire `main.swift` (plus Esc selection-clear)**

Modify `Sources/App/main.swift`. Update the existing `input.onDeactivate` wiring so Esc clears any active selection before deactivating fiti (matches the spec: "Esc with a non-empty selection clears the selection; second Esc deactivates"):

```swift
input.onDeactivate = { [weak self] in
    guard let self else { return }
    if !self.controller.selectedStrokeIds.isEmpty {
        self.controller.selectedStrokeIds = []
    } else {
        self.controller.deactivate()
    }
}
```

(Add a small test for this in `Tests/AppKitTests/NSEventInputSourceTests.swift` if a relevant test file exists; otherwise rely on the manual smoke test below since it's a single-line wiring change.)

Then in `composeControllerCallbacks` (or wherever appropriate):

```swift
controller.onSelectionChanged = { [weak self] ids in
    guard let self else { return }
    let bounds = SelectionMath.selectionBounds(
        strokeIds: ids,
        strokes: self.editor.doc.strokes
    )
    self.canvas.setSelectionBounds(bounds)
}

controller.onInFlightTransformsChanged = { [weak self] overrides in
    guard let self else { return }
    let frame = RenderFrame.from(editor: self.editor,
                                 canvasSize: self.canvasSize,
                                 overrides: overrides)
    self.canvas.render(frame)
    // Refresh selection bounds because in-flight transforms move strokes.
    let bounds = SelectionMath.selectionBounds(
        strokeIds: self.controller.selectedStrokeIds,
        strokes: frame.strokes.reduce(into: [String: Stroke]()) { $0[$1.id] = $1 }
    )
    self.canvas.setSelectionBounds(bounds)
}
```

The marquee is wired via a separate publisher — for v1, the simplest approach is `controller.onSelectionGestureChanged: ((Rect?) -> Void)?` that fires when the marquee rect updates during a gesture. Add that publisher in Task 5's selectionPointerMoved (when the gesture is `.marquee`).

Per-task isolation note: if the marquee publisher feels like it belongs in Task 5, move it there; Task 8 only wires the AppKit subscriber side. Either way the slice should compile and pass.

- [ ] **Step 5: Run the full check + manual smoke**

Run: `just check`
Expected: 5 new `CanvasViewSelectionTests` pass; all existing tests still green; build + lint clean.

Manual smoke:
```bash
just run-bg
```

Then:
1. Activate fiti (Opt+F). Draw a few strokes.
2. Hold Space. Cursor switches to arrow.
3. Click on a stroke — selection box appears around it.
4. Cmd-click another stroke — both highlight.
5. Drag from empty space — marquee rectangle appears, releases as a multi-selection.
6. Drag a selected stroke — preview moves smoothly, releases at the new position.
7. Press Delete — only selected strokes erase. Cmd+Z restores them.
8. Press Esc — selection clears.
9. Draw a new stroke (release Space, then click-drag) — prior selection clears.

```bash
just stop
```

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Rendering/RenderFrame.swift \
        Sources/AppKit/CanvasView.swift \
        Tests/AppKitTests/CanvasViewSelectionTests.swift \
        Sources/App/main.swift
git commit -m "$(cat <<'EOF'
AppKit + App: render selection box + marquee; wire controller publishers

RenderFrame.from(editor:canvasSize:overrides:) composes stroke
transforms with controller overrides for smooth in-flight gesture
preview. CanvasView gains setSelectionBounds and setMarquee setters
with idempotent dirty-mark behavior. main.swift subscribes to
controller.onSelectionChanged and onInFlightTransformsChanged so the
canvas re-renders on every gesture frame.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Acceptance criteria (mirrors the spec)

- [ ] Press-and-hold `Space` flips currentTool to .selection; cursor becomes arrow.
- [ ] Releasing `Space` reverts to .pen; selection persists.
- [ ] Click on a stroke replaces selection. Cmd-click toggles a stroke into / out of selection.
- [ ] Drag from empty area marquees; release populates selection from `SelectionMath.marqueeHit`.
- [ ] Drag on a stroke translates the whole selection; commits one undoable op on pointerUp.
- [ ] Corner handles + rotation handle land in the sub-task (5b) and ship as separate commits.
- [ ] `Delete` with selection erases only those strokes (one undoable op). `Delete` with empty selection keeps the existing clear-all behavior.
- [ ] `Cmd+K` always clears everything regardless of selection.
- [ ] Drawing a new stroke (pen pointerDown) clears any prior selection.
- [ ] `Esc` with a non-empty selection clears the selection. `Esc` with no selection deactivates fiti.
- [ ] `Sources/Core/` has zero AppKit / CoreGraphics / Network / SwiftUI imports.
- [ ] Full test suite stays under 5 seconds (`just check`).
