# Opacity Flattening v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Overlapping marks of the same color read as one flat region at the intended opacity, live while drawing and pixel-identical when committed, without the O(items x canvas) cost that made v1 unusable.

**Architecture:** A pure Core planner (`LayerPlan`) groups items into flattened layers keyed on `(hue, alpha)`. One AppKit routine (`GroupCompositor`) flattens a layer by drawing its items opaque inside a `beginTransparencyLayer` and compositing the layer at the group's alpha. The committed bake, the snapshot, and the live in-progress path all call that one routine, so what is drawn matches what commits. Live flattening lifts the in-progress stroke's group out of the static bake and caches the group's committed members as an opaque-union image once at pen-down, so each frame is one image blit plus one stroke fill.

**Tech Stack:** Swift, Swift Testing (`import Testing`, `@Test`, `@Suite`, `#expect`), CoreGraphics, hexagonal layering (pure `Sources/Core`, AppKit adapters in `Sources/AppKit`).

**Source of truth:** `docs/specs/2026-05-24-fiti-opacity-flattening-design.md`. Baseline numbers to beat: `docs/perf-baseline.md`.

**Reuse:** `LayerPlan`, `SelectionMath.worldAABB`, and the bake-signature fix exist on the `opacity-flattening-v1` branch. The authoritative code is in this plan; `git show opacity-flattening-v1:<path>` is a reference only. The v1 `LayerCompositor` (per-item buffers) is NOT reused; `GroupCompositor` replaces it.

---

## Conventions (apply to every task)

- Tests use Swift Testing, never XCTest. Every new Swift file starts with two `// ABOUTME:` lines.
- `Sources/Core` must not import AppKit, CoreGraphics, CoreText, Network, or SwiftUI (enforced by `just lint` grep + the build graph). Foundation is allowed.
- Commands go through `just`: `just test` runs the Core (`fiti-unit`) bundle; `just test-only 'Suite/test()'` runs one Core test; `just test-integration` runs the AppKit bundle; `just check` is the full gate and is what the pre-commit hook runs. Never `--no-verify`.
- Full suite stays under 5 seconds.
- Commit at the end of each task. HEREDOC message ending with the trailer:

  ```bash
  git commit -F - <<'EOF'
  <subject>

  <body>

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  ```

- SwiftLint limits: 5 params/function, ~250-line type body, ~400-line file, cyclomatic complexity 10, colon spacing.
- SourceKit "No such module 'Testing'" / "Cannot find type" warnings are known false positives; `just check` is authoritative.
- A blocked pre-commit `just check` means fix forward; do not bypass.

---

## File structure

- Modify `Sources/AppKit/CanvasView.swift` — broaden bake signature (Phase 0); bake via the routine (Phase 3); live cached-union lift (Phase 5). Keep the existing perf-probe hooks.
- Modify `Sources/Core/Selection/SelectionMath.swift` — make `worldAABB(of:)` public (Phase 1).
- Create `Sources/Core/Rendering/LayerPlan.swift` — `FlattenLayer` + `LayerPlan.compute`, keyed on `(hue, alpha)` (Phase 1).
- Create `Sources/AppKit/GroupCompositor.swift` — `compositeGroups(_:in:)` transparency-layer flatten (Phase 2).
- Modify `Sources/AppKit/SnapshotRenderer.swift` — flatten via the routine (Phase 4).
- Tests: `Tests/AppKitTests/CanvasViewBakeTests.swift` (Phase 0), `Tests/CoreTests/SelectionTests/SelectionMathAABBTests.swift` (Phase 1), `Tests/CoreTests/RenderingTests/LayerPlanTests.swift` (Phase 1), `Tests/AppKitTests/GroupCompositorTests.swift` (Phase 2), `Tests/AppKitTests/CanvasViewFlattenTests.swift` (Phase 3 + 5), `Tests/AppKitTests/SnapshotRendererTests.swift` (Phase 4).

---

## Phase 0: Broaden the bake signature (standalone bug fix)

`BakeSignatureEntry.contentTag` returns `0` for every stroke, so recoloring or resizing a committed stroke does not re-bake. Grouping will also depend on color and alpha, so the signature must capture them. Ships first, independently.

### Task 0: Stroke color/width invalidate the bake

**Files:**
- Modify: `Sources/AppKit/CanvasView.swift` (`contentTag(for:)`)
- Test: `Tests/AppKitTests/CanvasViewBakeTests.swift`

- [ ] **Step 1: Write the failing tests.** Add to the `CanvasViewBakeTests` suite:

```swift
@Test("recoloring a committed stroke invalidates the bake signature")
func strokeRecolorInvalidates() {
    let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    func frame(_ color: RGBA) -> RenderFrame {
        let s = Stroke(id: "a", color: color, width: 2, transform: .identity,
                       points: [StrokePoint(x: 0, y: 0), StrokePoint(x: 10, y: 10)],
                       pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        return RenderFrame(items: [.stroke(s)], inProgress: nil,
                           canvasSize: Size(width: 100, height: 100))
    }
    view.render(frame(RGBA(r: 1, g: 0, b: 0, a: 1)))
    let sig1 = view.bakeSignatureForTesting
    view.render(frame(RGBA(r: 0, g: 0, b: 1, a: 1)))
    #expect(sig1 != view.bakeSignatureForTesting)
}

@Test("resizing a committed stroke's width invalidates the bake signature")
func strokeWidthInvalidates() {
    let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    func frame(_ width: Double) -> RenderFrame {
        let s = Stroke(id: "a", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: width,
                       transform: .identity,
                       points: [StrokePoint(x: 0, y: 0), StrokePoint(x: 10, y: 10)],
                       pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        return RenderFrame(items: [.stroke(s)], inProgress: nil,
                           canvasSize: Size(width: 100, height: 100))
    }
    view.render(frame(2))
    let sig1 = view.bakeSignatureForTesting
    view.render(frame(8))
    #expect(sig1 != view.bakeSignatureForTesting)
}
```

Confirm `bakeSignatureForTesting` is the real accessor name (it is, on main).

- [ ] **Step 2: Run to verify they fail.** `just test-integration`. Expected: FAIL (strokes share `contentTag` 0, so signatures match).

- [ ] **Step 3: Broaden `contentTag` for strokes.** Replace the `.stroke` case of `contentTag(for:)` in `Sources/AppKit/CanvasView.swift`:

```swift
        case .stroke(let s):
            var hasher = Hasher()
            hasher.combine(s.color.r)
            hasher.combine(s.color.g)
            hasher.combine(s.color.b)
            hasher.combine(s.color.a)
            hasher.combine(s.width)
            return hasher.finalize()
```

Leave the `.text` case as-is. Update the `BakeSignatureEntry.contentTag` comment to `// strokes: hash(color, width); text: hash(string, fontName, fontSize, color)`.

- [ ] **Step 4: Run to verify they pass.** `just test-integration`. Expected: PASS, including existing bake tests.

- [ ] **Step 5: Commit.**

```bash
git add Sources/AppKit/CanvasView.swift Tests/AppKitTests/CanvasViewBakeTests.swift
git commit -F - <<'EOF'
AppKit: include stroke color+width in the bake signature

contentTag was 0 for all strokes, so recoloring or resizing a committed
stroke left the bake stale. Hash color and width. Also a precursor to
opacity flattening, whose grouping depends on color and alpha.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Phase 1: Pure planner (Core)

### Task 1: Make `SelectionMath.worldAABB` public

**Files:**
- Modify: `Sources/Core/Selection/SelectionMath.swift`
- Test: `Tests/CoreTests/SelectionTests/SelectionMathAABBTests.swift`

- [ ] **Step 1: Write the failing test.** Create `Tests/CoreTests/SelectionTests/SelectionMathAABBTests.swift`:

```swift
// ABOUTME: Verifies SelectionMath.worldAABB is public and bounds strokes.
// ABOUTME: The opacity LayerPlan passes this as its AABB function.

import Testing

@Suite("SelectionMath.worldAABB")
struct SelectionMathAABBTests {
    @Test("stroke world AABB encloses its transformed points")
    func strokeBounds() {
        let s = Stroke(id: "a", color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 2,
                       transform: .identity,
                       points: [StrokePoint(x: 0, y: 0), StrokePoint(x: 10, y: 4)],
                       pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        #expect(SelectionMath.worldAABB(of: .stroke(s)) == Rect(x: 0, y: 0, width: 10, height: 4))
    }
}
```

First read `SelectionMath.swift` and confirm `worldAABB(of:)` exists as `private static func worldAABB(of item: CanvasItem) -> Rect?` and that it computes tight min/max bounds with no width padding (so the expected `Rect(x:0,y:0,width:10,height:4)` holds). If it pads, set the expected value to what it actually produces and note it in the report.

- [ ] **Step 2: Run to verify it fails.** `just test-only 'SelectionMath.worldAABB/strokeBounds()'`. Expected: compile failure (inaccessible).

- [ ] **Step 3: Make it public.** Change `private static func worldAABB` to `public static func worldAABB`.

- [ ] **Step 4: Run to verify it passes.** `just test-only 'SelectionMath.worldAABB/strokeBounds()'`, then `just test`.

- [ ] **Step 5: Commit.**

```bash
git add Sources/Core/Selection/SelectionMath.swift Tests/CoreTests/SelectionTests/SelectionMathAABBTests.swift
git commit -F - <<'EOF'
Core: make SelectionMath.worldAABB public

The opacity LayerPlan needs a per-item AABB and SelectionMath already
computes one. Expose it; add a guard test.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

### Task 2: `LayerPlan.compute` keyed on (hue, alpha)

The planner takes committed items in z-order and an AABB function, returns flattened layers in composite order. The group key is `(r, g, b, a)` exactly. Same-key items merge; a different-key mark adds an ordering constraint only where its AABB overlaps.

**Files:**
- Create: `Sources/Core/Rendering/LayerPlan.swift`
- Test: `Tests/CoreTests/RenderingTests/LayerPlanTests.swift`

- [ ] **Step 1: Write the failing tests.** Create `Tests/CoreTests/RenderingTests/LayerPlanTests.swift`:

```swift
// ABOUTME: Tests the pure overlap-aware grouping keyed on (hue, alpha).
// ABOUTME: Boxes are injected so cases are exact and independent of geometry.

import Testing

@Suite("LayerPlan.compute")
struct LayerPlanTests {
    private let red = RGBA(r: 1, g: 0, b: 0, a: 0.5)
    private let blue = RGBA(r: 0, g: 0, b: 1, a: 0.5)

    private func mark(_ id: String, _ color: RGBA) -> CanvasItem {
        .stroke(Stroke(id: id, color: color, width: 1, transform: .identity,
                       points: [], pointerType: .mouse, pressureEnabled: false, createdAt: 0))
    }
    private func layerIds(_ items: [CanvasItem], _ boxes: [ItemId: Rect]) -> [[ItemId]] {
        LayerPlan.compute(items: items, aabb: { boxes[$0.id] }).map { $0.items.map(\.id) }
    }

    @Test("same key marks merge into one layer")
    func sameKeyMerge() {
        let items = [mark("r1", red), mark("r2", red)]
        let boxes: [ItemId: Rect] = ["r1": Rect(x: 0, y: 0, width: 10, height: 10),
                                     "r2": Rect(x: 5, y: 5, width: 10, height: 10)]
        #expect(layerIds(items, boxes) == [["r1", "r2"]])
    }

    @Test("same key split by a NON-overlapping other key still merges")
    func splitByNonOverlappingMerges() {
        let items = [mark("r1", red), mark("b", blue), mark("r3", red)]
        let boxes: [ItemId: Rect] = [
            "r1": Rect(x: 0, y: 0, width: 20, height: 20),
            "b":  Rect(x: 100, y: 0, width: 10, height: 20),
            "r3": Rect(x: 5, y: 5, width: 20, height: 20)
        ]
        let layers = layerIds(items, boxes)
        #expect(layers.first { $0.contains("r1") } == ["r1", "r3"])
        #expect(layers.contains(["b"]))
        #expect(layers.count == 2)
    }

    @Test("a different key overlapping both same-key marks forces a split")
    func genuineConflictSplits() {
        let items = [mark("r1", red), mark("b", blue), mark("r2", red)]
        let box = Rect(x: 0, y: 0, width: 30, height: 30)
        let boxes: [ItemId: Rect] = ["r1": box, "b": box, "r2": box]
        #expect(layerIds(items, boxes) == [["r1"], ["b"], ["r2"]])
    }

    @Test("same hue but different alpha are different keys: overlapping splits")
    func differentAlphaSameHueSplits() {
        let r70 = RGBA(r: 1, g: 0, b: 0, a: 0.7)
        let r30 = RGBA(r: 1, g: 0, b: 0, a: 0.3)
        let items = [mark("a", r70), mark("b", r30)]
        let box = Rect(x: 0, y: 0, width: 10, height: 10)
        #expect(layerIds(items, ["a": box, "b": box]) == [["a"], ["b"]])
    }

    @Test("same hue but different alpha, non-overlapping: each its own layer, order kept")
    func differentAlphaSameHueNonOverlapping() {
        let r70 = RGBA(r: 1, g: 0, b: 0, a: 0.7)
        let r30 = RGBA(r: 1, g: 0, b: 0, a: 0.3)
        let items = [mark("a", r70), mark("b", r30)]
        let boxes: [ItemId: Rect] = ["a": Rect(x: 0, y: 0, width: 10, height: 10),
                                     "b": Rect(x: 50, y: 0, width: 10, height: 10)]
        #expect(layerIds(items, boxes) == [["a"], ["b"]])
    }

    @Test("nil AABB never constrains and same-key can merge")
    func nilBoxNeverConstrains() {
        let items = [mark("r1", red), mark("b", blue), mark("r2", red)]
        #expect(layerIds(items, [:]) == [["r1", "r2"], ["b"]])
    }

    @Test("a single mark yields one layer of one item")
    func singleItem() {
        #expect(layerIds([mark("only", red)], ["only": Rect(x: 0, y: 0, width: 5, height: 5)]) == [["only"]])
    }
}
```

Before running, confirm `CanvasItem` exposes `.color` (RGBA) and `.id` (ItemId), `Rect` has `intersects(_:)`, and the `Stroke`/`RGBA`/`StrokePoint` initializers match. (All true on main.)

- [ ] **Step 2: Run to verify they fail.** `just test`. Expected: compile failure (`LayerPlan`/`FlattenLayer` undefined).

- [ ] **Step 3: Implement the planner.** Create `Sources/Core/Rendering/LayerPlan.swift`:

```swift
// ABOUTME: Pure overlap-aware grouping of canvas items into flattened layers,
// ABOUTME: keyed on (hue, alpha). Same-key marks merge unless a different key overlaps between them.

import Foundation

/// One flattened layer: marks of a single (hue, alpha) key, composited as a group.
/// Emitted bottom-to-top in final composite order.
public struct FlattenLayer: Equatable, Sendable {
    public let items: [CanvasItem]
    public init(items: [CanvasItem]) { self.items = items }
}

public enum LayerPlan {
    /// Group `items` (z-order, bottom first) into flattened layers in composite
    /// order. `aabb` returns an item's world-space bounds, or nil if it has none.
    public static func compute(items: [CanvasItem], aabb: (CanvasItem) -> Rect?) -> [FlattenLayer] {
        guard !items.isEmpty else { return [] }
        let boxes = items.map(aabb)
        let before = constraints(items: items, boxes: boxes)
        let order = clusteredOrder(items: items, before: before)
        return groupRuns(items: items, order: order)
    }

    /// before[j] = indices i < j that must composite before j (different key,
    /// overlapping). Edges only go low->high, so the graph is acyclic.
    private static func constraints(items: [CanvasItem], boxes: [Rect?]) -> [Set<Int>] {
        let n = items.count
        var before = Array(repeating: Set<Int>(), count: n)
        guard n > 1 else { return before }
        for j in 1..<n {
            for i in 0..<j {
                guard let bi = boxes[i], let bj = boxes[j] else { continue }
                if !sameKey(items[i].color, items[j].color), bi.intersects(bj) {
                    before[j].insert(i)
                }
            }
        }
        return before
    }

    /// Emit a constraint-respecting order that greedily clusters same-key items.
    private static func clusteredOrder(items: [CanvasItem], before: [Set<Int>]) -> [Int] {
        let n = items.count
        var emitted = Array(repeating: false, count: n)
        var order: [Int] = []
        order.reserveCapacity(n)
        var lastKey: RGBA?
        for _ in 0..<n {
            let chosen = nextIndex(items: items, before: before, emitted: emitted, lastKey: lastKey)
            emitted[chosen] = true
            order.append(chosen)
            lastKey = items[chosen].color
        }
        return order
    }

    /// Among items whose predecessors are all emitted, prefer one whose key
    /// matches `lastKey`, else the earliest eligible. The smallest un-emitted
    /// index is always eligible, so a value always exists.
    private static func nextIndex(items: [CanvasItem], before: [Set<Int>],
                                  emitted: [Bool], lastKey: RGBA?) -> Int {
        var fallback: Int?
        for k in 0..<items.count where !emitted[k] {
            guard before[k].allSatisfy({ emitted[$0] }) else { continue }
            if fallback == nil { fallback = k }
            if let lk = lastKey, sameKey(items[k].color, lk) { return k }
        }
        return fallback ?? 0
    }

    /// Group consecutive same-key items in `order` into layers.
    private static func groupRuns(items: [CanvasItem], order: [Int]) -> [FlattenLayer] {
        var layers: [FlattenLayer] = []
        var current: [CanvasItem] = []
        for idx in order {
            let item = items[idx]
            if let first = current.first, !sameKey(first.color, item.color) {
                layers.append(FlattenLayer(items: current))
                current = []
            }
            current.append(item)
        }
        if !current.isEmpty { layers.append(FlattenLayer(items: current)) }
        return layers
    }

    private static func sameKey(_ a: RGBA, _ b: RGBA) -> Bool {
        a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a
    }
}
```

- [ ] **Step 4: Run to verify they pass.** `just test`. Expected: all seven tests pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/Core/Rendering/LayerPlan.swift Tests/CoreTests/RenderingTests/LayerPlanTests.swift
git commit -F - <<'EOF'
Core: LayerPlan overlap-aware grouping keyed on (hue, alpha)

Pure planner: groups items into flattened layers keyed on full RGBA, with
ordering constraints only between overlapping different-key marks. Same-key
marks merge unless a different key genuinely overlaps between them.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Phase 2: The flatten routine (AppKit)

### Task 3: `GroupCompositor.compositeGroups`

Flatten a plan into a `CGContext`. Each group is drawn inside a `beginTransparencyLayer` with its items opaque (alpha forced to 1), and the layer is composited at the group's alpha. Cross-group z-order is the plan order (source-over).

**Files:**
- Create: `Sources/AppKit/GroupCompositor.swift`
- Test: `Tests/AppKitTests/GroupCompositorTests.swift`

- [ ] **Step 0: Confirm `withAlpha`.** Read `Sources/Core/Model/CanvasItem.swift` and confirm `CanvasItem` has `func withAlpha(_ a: Double) -> CanvasItem` that returns the item with its color alpha replaced (it was added with the selection-restyle feature; it is on main). If absent, add it (pure Core): for `.stroke`, return `.stroke` with `color.a = a`; for `.text`, the same. Confirm `drawItem(_ item: CanvasItem, in ctx: CGContext, isInProgress: Bool)` is the drawing entry point in `Sources/AppKit/StrokeDrawing.swift`.

- [ ] **Step 1: Write the failing tests.** Create `Tests/AppKitTests/GroupCompositorTests.swift`:

```swift
// ABOUTME: Pixel tests for GroupCompositor: same-color overlap is flat at the
// ABOUTME: group alpha, and cross-color groups preserve z-order.

import AppKit
import CoreGraphics
import Testing

@Suite("GroupCompositor")
@MainActor
struct GroupCompositorTests {
    private let size = 60

    private func context() -> CGContext {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        return ctx
    }
    private func hBar(_ id: String, y: Double, _ c: RGBA) -> CanvasItem {
        .stroke(Stroke(id: id, color: c, width: 16, transform: .identity,
                       points: [StrokePoint(x: 6, y: y), StrokePoint(x: 54, y: y)],
                       pointerType: .mouse, pressureEnabled: false, createdAt: 0))
    }
    private func vBar(_ id: String, x: Double, _ c: RGBA) -> CanvasItem {
        .stroke(Stroke(id: id, color: c, width: 16, transform: .identity,
                       points: [StrokePoint(x: x, y: 6), StrokePoint(x: x, y: 54)],
                       pointerType: .mouse, pressureEnabled: false, createdAt: 0))
    }
    private func alpha(_ ctx: CGContext, _ x: Int, _ y: Int) -> CGFloat {
        NSBitmapImageRep(cgImage: ctx.makeImage()!).colorAt(x: x, y: y)?.alphaComponent ?? 0
    }

    @Test("same-color 50% + is flat: intersection equals the arms")
    func sameColorPlusFlat() {
        let ctx = context()
        let red = RGBA(r: 1, g: 0, b: 0, a: 0.5)
        compositeGroups([FlattenLayer(items: [hBar("h", y: 30, red), vBar("v", x: 30, red)])], in: ctx)
        let arm = alpha(ctx, 12, 30)
        let center = alpha(ctx, 30, 30)
        #expect(arm > 0.3)
        #expect(abs(center - arm) < 0.12)
        #expect(center < 0.65)
    }

    @Test("different-color groups preserve z-order: later group on top")
    func crossColorOrder() {
        let ctx = context()
        compositeGroups([
            FlattenLayer(items: [hBar("r", y: 30, RGBA(r: 1, g: 0, b: 0, a: 1))]),
            FlattenLayer(items: [vBar("b", x: 30, RGBA(r: 0, g: 0, b: 1, a: 1))])
        ], in: ctx)
        let c = NSBitmapImageRep(cgImage: ctx.makeImage()!).colorAt(x: 30, y: 30)!
        #expect(c.blueComponent > 0.5 && c.redComponent < 0.3)
    }
}
```

If `width: 16` leaves a gap at the crossing (perfect-freehand thinning), widen the bars until the arms overlap at the center; keep the assertion intent.

- [ ] **Step 2: Run to verify they fail.** `just test-integration`. Expected: compile failure (`compositeGroups` undefined).

- [ ] **Step 3: Implement the routine.** Create `Sources/AppKit/GroupCompositor.swift`:

```swift
// ABOUTME: Paints a LayerPlan into a CGContext. Each group flattens in a
// ABOUTME: transparency layer, items drawn opaque, composited at the group's alpha.

import AppKit
import CoreGraphics

/// Composite `groups` (bottom-to-top) into `ctx`. Each group's items are drawn
/// opaque (alpha 1) inside a transparency layer, which is then composited at the
/// group's alpha. Same-color overlaps union flat; cross-group z-order is source-over.
func compositeGroups(_ groups: [FlattenLayer], in ctx: CGContext) {
    for group in groups {
        guard let groupAlpha = group.items.first?.color.a else { continue }
        ctx.saveGState()
        ctx.setAlpha(CGFloat(groupAlpha))         // applied to the whole layer on end
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        for item in group.items {
            drawItem(item.withAlpha(1), in: ctx, isInProgress: false)
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
}
```

(`RGBA` exposes `.a`; `CanvasItem.color` returns the item's RGBA; `withAlpha(1)` forces opaque.)

- [ ] **Step 4: Run to verify they pass.** `just test-integration`. Expected: both tests pass. If `crossColorOrder` fails (blue not on top), confirm `setAlpha` is before `beginTransparencyLayer` and `restoreGState` resets between groups.

- [ ] **Step 5: Commit.**

```bash
git add Sources/AppKit/GroupCompositor.swift Tests/AppKitTests/GroupCompositorTests.swift
git commit -F - <<'EOF'
AppKit: GroupCompositor flattens groups via transparency layers

Each (hue, alpha) group draws its items opaque inside a transparency layer
composited at the group alpha, so same-color overlaps read flat with no
per-pixel buffers. Cross-group z-order is source-over.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Phase 3: Bake committed items via the routine

### Task 4: Route the committed bake through LayerPlan + GroupCompositor

**Files:**
- Modify: `Sources/AppKit/CanvasView.swift` (`bakeCommitted`)
- Test: `Tests/AppKitTests/CanvasViewFlattenTests.swift`

- [ ] **Step 1: Write the failing test.** Create `Tests/AppKitTests/CanvasViewFlattenTests.swift`:

```swift
// ABOUTME: End-to-end flattening through the committed bake: a same-color +
// ABOUTME: drawn at 50% must be uniform, not darker at the intersection.

import AppKit
import Testing

@MainActor
@Suite("CanvasView flattening")
struct CanvasViewFlattenTests {
    func hBar(_ id: String, y: Double, _ c: RGBA) -> CanvasItem {
        .stroke(Stroke(id: id, color: c, width: 16, transform: .identity,
                       points: [StrokePoint(x: 10, y: y), StrokePoint(x: 90, y: y)],
                       pointerType: .mouse, pressureEnabled: false, createdAt: 0))
    }
    func vBar(_ id: String, x: Double, _ c: RGBA) -> CanvasItem {
        .stroke(Stroke(id: id, color: c, width: 16, transform: .identity,
                       points: [StrokePoint(x: x, y: 10), StrokePoint(x: x, y: 90)],
                       pointerType: .mouse, pressureEnabled: false, createdAt: 0))
    }

    @Test("a same-color 50% + is flat across the intersection in the committed bake")
    func committedPlusIsFlat() throws {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.testOnly_overrideBackingScale = 1
        let red = RGBA(r: 1, g: 0, b: 0, a: 0.5)
        view.render(RenderFrame(items: [hBar("h", y: 50, red), vBar("v", x: 50, red)],
                                inProgress: nil, canvasSize: Size(width: 100, height: 100)))
        let rep = NSBitmapImageRep(cgImage: try #require(view.testOnly_committedImage))
        let arm = try #require(rep.colorAt(x: 20, y: 50)).alphaComponent
        let center = try #require(rep.colorAt(x: 50, y: 50)).alphaComponent
        #expect(arm > 0.3)
        #expect(abs(center - arm) < 0.12)
        #expect(center < 0.65)
    }
}
```

Confirm `testOnly_overrideBackingScale` and `testOnly_committedImage` exist (they do, on main).

- [ ] **Step 2: Run to verify it fails.** `just test-integration`. Expected: FAIL (intersection ~0.75 under source-over).

- [ ] **Step 3: Route the bake through the plan.** In `bakeCommitted`, replace the per-item drawing loop (`for item in frame.items where item.id != exclude { drawItem(...) }`) with:

```swift
        let baked = frame.items.filter { $0.id != exclude }
        let groups = LayerPlan.compute(items: baked, aabb: SelectionMath.worldAABB)
        compositeGroups(groups, in: ctx)
        return ctx.makeImage()
```

Keep the context setup (size, flip, scale, line cap/join) and the `bakeCommitted(_:exclude:)` signature unchanged.

- [ ] **Step 4: Run to verify it passes.** `just test-integration`. Expected: PASS, including existing bake tests.

- [ ] **Step 5: Commit.**

```bash
git add Sources/AppKit/CanvasView.swift Tests/AppKitTests/CanvasViewFlattenTests.swift
git commit -F - <<'EOF'
AppKit: bake committed items through LayerPlan + GroupCompositor

bakeCommitted groups committed items by (hue, alpha) and flattens each group,
so overlapping same-color marks read flat instead of accumulating.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

- [ ] **Step 6: Perf checkpoint (controller-run).** `just run-bg`; `just inspect-perf-reset`; draw four strokes via `/pointer`; `just inspect-perf`. Expected: `render.bake` mean in single-digit ms (compare to the 2.6 ms baseline in `docs/perf-baseline.md`). `just stop`. If the bake exceeds ~10 ms, stop and investigate before Phase 5.

---

## Phase 4: Snapshot via the routine

### Task 5: `SnapshotRenderer` composes through LayerPlan + GroupCompositor

**Files:**
- Modify: `Sources/AppKit/SnapshotRenderer.swift`
- Test: `Tests/AppKitTests/SnapshotRendererTests.swift`

- [ ] **Step 1: Write the failing test.** Add to the existing `SnapshotRenderer` suite (read the file for its `pixel()` helper and `png(from:scale:)` signature; match how its tests sample). The test draws a same-color 50% `+`, renders `SnapshotRenderer.png(from:scale:1)`, and asserts the intersection alpha ~ the arm alpha and `< 0.65` (translate to the suite's pixel-sampling scale, as the existing tests do). Keep the in-progress draw line below the committed loop unchanged.

- [ ] **Step 2: Run to verify it fails.** `just test-integration`. Expected: FAIL (intersection ~0.75).

- [ ] **Step 3: Route through the plan.** Replace the committed-item loop (`for item in frame.items { drawItem(item, in: ctx, isInProgress: false) }`) with:

```swift
        let groups = LayerPlan.compute(items: frame.items, aabb: SelectionMath.worldAABB)
        compositeGroups(groups, in: ctx)
```

Keep the in-progress line (`if let inProgress = frame.inProgress { drawStroke(inProgress, in: ctx, isInProgress: true) }`) unchanged below it, and keep all context setup.

- [ ] **Step 4: Run to verify it passes.** `just test-integration`. Expected: PASS, including existing snapshot tests.

- [ ] **Step 5: Commit.**

```bash
git add Sources/AppKit/SnapshotRenderer.swift Tests/AppKitTests/SnapshotRendererTests.swift
git commit -F - <<'EOF'
AppKit: snapshot renderer composes via LayerPlan + GroupCompositor

GET /snapshot.png flattens through the same routine as the canvas bake, so
snapshots match the committed screen.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Phase 5: Live flattening with a cached opaque union

While drawing, the in-progress stroke flattens with its `(hue, alpha)` group, pixel-identical to what commits. Lift the group's committed members out of the static bake; cache them as an opaque-union image once when the lifted set changes; each frame composite `{cached union + the live stroke}` through one transparency layer at the group alpha.

### Task 6: Active-group lift + cached union

**Files:**
- Modify: `Sources/AppKit/CanvasView.swift` (`render`, `draw`, `bakeCommitted` -> `baked:`, new state + helpers)
- Test: `Tests/AppKitTests/CanvasViewFlattenTests.swift`

- [ ] **Step 1: Write the failing tests.** Add to `CanvasViewFlattenTests`:

```swift
@Test("in-progress stroke flattens live with a committed same-color mark")
func liveStrokeFlattensWithCommitted() throws {
    let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    view.testOnly_overrideBackingScale = 1
    let red = RGBA(r: 1, g: 0, b: 0, a: 0.5)
    let committed = Stroke(id: "h", color: red, width: 16, transform: .identity,
                           points: [StrokePoint(x: 10, y: 50), StrokePoint(x: 90, y: 50)],
                           pointerType: .mouse, pressureEnabled: false, createdAt: 0)
    let live = Stroke(id: "v", color: red, width: 16, transform: .identity,
                      points: [StrokePoint(x: 50, y: 10), StrokePoint(x: 50, y: 90)],
                      pointerType: .mouse, pressureEnabled: false, createdAt: 1)
    view.render(RenderFrame(items: [.stroke(committed)], inProgress: live,
                            canvasSize: Size(width: 100, height: 100)))
    let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: rep)
    let arm = try #require(rep.colorAt(x: 20, y: 50)).alphaComponent
    let center = try #require(rep.colorAt(x: 50, y: 50)).alphaComponent
    #expect(arm > 0.3)
    #expect(center < 0.65)
    #expect(abs(center - arm) < 0.15)
}

@Test("WYSIWYG: live crossing matches the same two marks committed")
func liveMatchesCommitted() throws {
    let red = RGBA(r: 1, g: 0, b: 0, a: 0.5)
    let h = Stroke(id: "h", color: red, width: 16, transform: .identity,
                   points: [StrokePoint(x: 10, y: 50), StrokePoint(x: 90, y: 50)],
                   pointerType: .mouse, pressureEnabled: false, createdAt: 0)
    let v = Stroke(id: "v", color: red, width: 16, transform: .identity,
                   points: [StrokePoint(x: 50, y: 10), StrokePoint(x: 50, y: 90)],
                   pointerType: .mouse, pressureEnabled: false, createdAt: 1)
    // live: h committed, v in progress
    let liveView = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    liveView.testOnly_overrideBackingScale = 1
    liveView.render(RenderFrame(items: [.stroke(h)], inProgress: v,
                                canvasSize: Size(width: 100, height: 100)))
    let liveRep = try #require(liveView.bitmapImageRepForCachingDisplay(in: liveView.bounds))
    liveView.cacheDisplay(in: liveView.bounds, to: liveRep)
    // committed: both h and v committed
    let comView = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    comView.testOnly_overrideBackingScale = 1
    comView.render(RenderFrame(items: [.stroke(h), .stroke(v)], inProgress: nil,
                               canvasSize: Size(width: 100, height: 100)))
    let comRep = try #require(comView.bitmapImageRepForCachingDisplay(in: comView.bounds))
    comView.cacheDisplay(in: comView.bounds, to: comRep)
    // The intersection pixel matches between live and committed.
    let liveCenter = try #require(liveRep.colorAt(x: 50, y: 50)).alphaComponent
    let comCenter = try #require(comRep.colorAt(x: 50, y: 50)).alphaComponent
    #expect(abs(liveCenter - comCenter) < 0.08)
}
```

- [ ] **Step 2: Run to verify they fail.** `just test-integration`. Expected: FAIL (in-progress draws source-over over the committed mark, so the live crossing reads ~0.75 and does not match the committed flat value).

- [ ] **Step 3: Implement the active-group lift.** In `Sources/AppKit/CanvasView.swift`:

Add state next to `committedImage`:

```swift
    private var activeGroupCommitted: [CanvasItem] = []
    private var activeGroupUnion: CGImage?
```

Rewrite `render(_:)` so it lifts the in-progress stroke's group, bakes the rest, and (when the baked/lifted set changes) rebuilds both the static bake and the cached opaque union. Keep the existing `#if DEBUG` perf-probe hooks:

```swift
    public func render(_ frame: RenderFrame) {
        let inProgressId = frame.inProgress?.id
        #if DEBUG
        let lifted = PerfLog.shared.measure("render.liftedGroup") {
            liftedGroup(for: frame, inProgressId: inProgressId)
        }
        #else
        let lifted = liftedGroup(for: frame, inProgressId: inProgressId)
        #endif
        let baked = frame.items.filter { $0.id != inProgressId && !lifted.contains($0.id) }
        let liftedMembers = frame.items.filter { lifted.contains($0.id) }

        let signature = baked
            .map { BakeSignatureEntry(id: $0.id, transform: $0.transform, contentTag: contentTag(for: $0)) }
        let resolvedScale = testOnly_overrideBackingScale ?? window?.backingScaleFactor ?? 1
        if signature != committedSignature || resolvedScale != backingScale {
            backingScale = resolvedScale
            #if DEBUG
            committedImage = PerfLog.shared.measure("render.bake") { bakeCommitted(frame, baked: baked) }
            #else
            committedImage = bakeCommitted(frame, baked: baked)
            #endif
            committedSignature = signature
            activeGroupCommitted = liftedMembers
            activeGroupUnion = liftedMembers.isEmpty ? nil : bakeOpaqueUnion(frame, members: liftedMembers)
        }
        lastFrame = frame
        needsDisplay = true
    }

    /// Committed item ids that share the in-progress stroke's (hue, alpha) group.
    private func liftedGroup(for frame: RenderFrame, inProgressId: ItemId?) -> Set<ItemId> {
        guard let live = frame.inProgress else { return [] }
        let committed = frame.items.filter { $0.id != inProgressId }
        let plan = LayerPlan.compute(items: committed + [.stroke(live)], aabb: SelectionMath.worldAABB)
        guard let group = plan.first(where: { $0.items.contains { $0.id == live.id } }) else { return [] }
        return Set(group.items.map(\.id)).subtracting([live.id])
    }
```

Change `bakeCommitted` to take `baked:` instead of `exclude:` (it already groups via the routine from Task 4):

```swift
    private func bakeCommitted(_ frame: RenderFrame, baked: [CanvasItem]) -> CGImage? {
        // ... unchanged context setup ...
        let groups = LayerPlan.compute(items: baked, aabb: SelectionMath.worldAABB)
        compositeGroups(groups, in: ctx)
        return ctx.makeImage()
    }
```

Add `bakeOpaqueUnion`, which renders the lifted members as an opaque-coverage union image, reusing the same context setup as `bakeCommitted` (factor a private `makeBakeContext(_ frame:) -> CGContext?` helper if it reduces duplication):

```swift
    /// The lifted group's committed members drawn opaque (alpha 1), source-over,
    /// into a canvas-sized image. The group alpha is applied later, in draw(_:),
    /// when this union is composited with the live stroke.
    private func bakeOpaqueUnion(_ frame: RenderFrame, members: [CanvasItem]) -> CGImage? {
        // ... same context setup as bakeCommitted (size, flip, scale, line cap/join) ...
        for member in members { drawItem(member.withAlpha(1), in: ctx, isInProgress: false) }
        return ctx.makeImage()
    }
```

In `draw(_:)`, replace the in-progress draw block. Current:

```swift
        if let live = frame.inProgress, !live.points.isEmpty {
            #if DEBUG
            PerfLog.shared.measure("draw.inProgress") { drawStroke(live, in: ctx, isInProgress: true) }
            #else
            drawStroke(live, in: ctx, isInProgress: true)
            #endif
        }
```

with a transparency-layer composite of `{cached union + live stroke}` at the group alpha (the rename `draw.inProgress` -> `draw.liveGroup` keeps the perf label meaningful):

```swift
        if let live = frame.inProgress, !live.points.isEmpty {
            #if DEBUG
            PerfLog.shared.measure("draw.liveGroup") { drawLiveGroup(live, frame: frame, in: ctx) }
            #else
            drawLiveGroup(live, frame: frame, in: ctx)
            #endif
        }
```

and add the helper (it mirrors the committed-image blit's flip handling for the union image):

```swift
    /// Composite the active group (cached committed union + the in-progress
    /// stroke) flattened at the group alpha, under globalOpacity. Matches the
    /// committed bake, so live drawing equals the committed result.
    private func drawLiveGroup(_ live: Stroke, frame: RenderFrame, in ctx: CGContext) {
        let groupAlpha = live.color.a
        ctx.saveGState()
        ctx.setAlpha(CGFloat(globalOpacity * groupAlpha))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        if let union = activeGroupUnion {
            let rect = CGRect(x: 0, y: 0, width: frame.canvasSize.width, height: frame.canvasSize.height)
            ctx.saveGState()
            ctx.translateBy(x: 0, y: rect.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(union, in: rect)
            ctx.restoreGState()
        }
        drawItem(CanvasItem.stroke(live).withAlpha(1), in: ctx, isInProgress: true)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
```

Notes:
- The `ctx.setAlpha(CGFloat(globalOpacity))` at the top of `draw(_:)` is overridden inside `drawLiveGroup` by `setAlpha(globalOpacity * groupAlpha)` within its own saved gstate, then restored. Leave the top-of-draw `setAlpha(globalOpacity)` and the committed-image blit as they are.
- The `frame.liveItems` selection-drag loop stays unchanged (source-over).
- When there is no in-progress stroke, `lifted` is empty, `activeGroupUnion` is nil, `drawLiveGroup` is not called, and rendering reduces to the static committed bake.

- [ ] **Step 4: Run to verify they pass.** `just test-integration`. Expected: PASS, including `liveStrokeFlattensWithCommitted`, `liveMatchesCommitted`, `committedPlusIsFlat`, and existing bake tests (the in-progress id is filtered from `baked`; selection-drag live items are unaffected). If `inProgressExcluded` fails because its two strokes share a key and the committed one is now lifted, give that test's committed and in-progress strokes distinct hues (as the v1 branch did) so it still asserts the in-progress id alone is excluded from the bake; commit that test file too.

- [ ] **Step 5: Run the full gate.** `just check`. Expected: PASS.

- [ ] **Step 6: Commit.**

```bash
git add Sources/AppKit/CanvasView.swift Tests/AppKitTests/CanvasViewFlattenTests.swift Tests/AppKitTests/CanvasViewBakeTests.swift
git commit -F - <<'EOF'
AppKit: live-flatten the in-progress stroke (cached opaque union)

Lift the in-progress stroke's (hue, alpha) group out of the static bake and
cache its committed members as an opaque-union image when the lifted set
changes. Each frame composite the union plus the live stroke through one
transparency layer at the group alpha, so the stroke flattens live and
matches the committed result. Per-frame cost is one blit plus one fill,
independent of mark count.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

- [ ] **Step 7: Perf checkpoint (controller-run, the gate that justifies v2).** `just run-bg`. Draw N committed marks of one color, then start another stroke of that color and measure: `just inspect-perf-reset` mid-drag is not possible, so instead (a) draw 4 strokes and read `draw.liveGroup` mean (expect sub-millisecond), then (b) clear, draw ~40 same-color strokes, draw one more and read `draw.liveGroup` again. Expected: `draw.liveGroup` mean stays sub-millisecond and does NOT grow between the 4-mark and 40-mark cases (flat in N), and `render.bake` stays single-digit ms. `just stop`. If `draw.liveGroup` grows with mark count, the cached union is not being used per frame; investigate before declaring Phase 5 done.

---

## Phase 6: Documentation

### Task 7: Mark shipped, update architecture, re-measure baseline doc

**Files:**
- Modify: `docs/fiti-roadmap.md`, `docs/architecture.md`, `docs/perf-baseline.md`

- [ ] **Step 1: Roadmap.** Move "Flatten overlapping same-opacity marks" to Shipped with a bullet describing the `(hue, alpha)` grouping, the transparency-layer flatten, the cached-union live path, "always on", and the accepted limits (mixed-opacity same-hue accumulates; cross-hue conflict; AABB conservatism). If the item is not present on `main`, add the Shipped bullet.

- [ ] **Step 2: architecture.md.** Add an "Opacity flattening" subsection under the rendering section describing `LayerPlan` (Core, pure, keyed on hue+alpha), `GroupCompositor` (transparency layer, draw opaque, composite at group alpha), the shared bake/snapshot/live path, and the cached opaque-union for live.

- [ ] **Step 3: perf-baseline.md.** Add a "v2 (transparency-layer flatten)" section with the measured `render.bake` and `draw.liveGroup` numbers from the Phase 3 and Phase 5 checkpoints, so the doc records that v2 met the single-digit-ms target (contrast with the v1 row).

- [ ] **Step 4: Commit.**

```bash
git add docs/fiti-roadmap.md docs/architecture.md docs/perf-baseline.md
git commit -F - <<'EOF'
docs: mark opacity flattening shipped (v2); record v2 perf

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Self-review notes (for the executor)

- **Spec coverage:** `(hue, alpha)` grouping (Task 2), transparency-layer flatten at group alpha (Task 3), shared routine across bake/snapshot/live (Tasks 4, 5, 6), WYSIWYG live==committed (Task 6 `liveMatchesCommitted`), cached opaque union for O(1)/frame (Task 6 + Phase 5 checkpoint), bake-signature fix (Task 0), always-on (no toggle), fade unchanged. Accepted limits hold by construction (alpha in the key; LayerPlan splits genuine cross-key conflicts).
- **WYSIWYG rationale:** `drawLiveGroup` composites `union(committed members) + live` opaque in one transparency layer at the group alpha; `bakeCommitted` (after commit) composites `union(all members incl. the new one)` opaque at the group alpha. Source-over is associative, so the union-of-an-image plus a stroke equals the union drawn directly; the two render the same. The `liveMatchesCommitted` test pins this.
- **Type consistency:** `FlattenLayer(items:)`, `LayerPlan.compute(items:aabb:)`, `compositeGroups(_:in:)`, `SelectionMath.worldAABB(of:)`, `bakeCommitted(_:baked:)`, `bakeOpaqueUnion(_:members:)`, `drawLiveGroup(_:frame:in:)`, `CanvasItem.withAlpha(_:)` are used identically across tasks.
- **Perf gates are explicit** (Phase 3 Step 6, Phase 5 Step 7) and are the reason v2 exists; they are controller-run because they need the GUI app + probe.
- **Watch:** if `GroupCompositor` cross-color test misbehaves, it is `setAlpha`/`beginTransparencyLayer` ordering. If `draw.liveGroup` grows with N, the cached union is being rebuilt per frame instead of only on signature change.
```
