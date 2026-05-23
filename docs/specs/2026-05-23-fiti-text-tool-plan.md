# Text Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a sticky Text tool to fiti (enter with `t`, multi-line, click-to-edit with a precise caret, rendered in the active color/size), with text as a first-class selectable/movable/rotatable canvas object sharing the existing undo and two-canvas rendering.

**Architecture:** Phase 1 generalizes the document from `Stroke` to a `CanvasItem` sum type (`stroke` | `text`) as a behavior-preserving refactor — every existing stroke test stays green, just renamed. Phase 2 layers the text tool, a pure `TextEditSession` edit buffer, and a `TextMeasuring` port (CoreText in the adapter, a monospace fake in tests) with text `bounds` frozen onto `TextItem` at commit. Phase 3 is docs + an icon-cache recipe.

**Tech Stack:** Swift 6, Swift Testing (`import Testing`, `@Test`, `@Suite`, `#expect`), AppKit + CoreText (adapters only), xcodegen + xcodebuild via `just`.

**Source of truth:** `docs/specs/2026-05-23-fiti-text-tool-design.md`.

**Conventions for every task:**
- Two `// ABOUTME:` lines at the top of each new Swift file.
- `Sources/Core/` must not import AppKit / CoreGraphics / CoreText / Network / SwiftUI. Ports live in `Sources/Core/Ports/`, adapters in `Sources/AppKit/`.
- Tests use Swift Testing, never XCTest. `@MainActor` types get `@MainActor` test suites.
- All commands go through `just`. Run `just check` before every commit (the pre-commit hook runs it; **never** `--no-verify`). After editing `project.yml`, run `just generate`.
- Commit only at a task's final step. Each commit message uses a HEREDOC ending with exactly:
  `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`
  (commit steps below show the subject only for brevity).
- SwiftLint: 5-parameter function limit, ~250-line type-body limit (move methods to an extension file as the existing code does), colon spacing (no alignment whitespace).
- SourceKit cross-target "No such module 'Testing'" / "Cannot find type" diagnostics are known false positives; `just check` is authoritative.

---

## File map

| File | Responsibility | Task |
| --- | --- | --- |
| `Sources/Core/Model/ItemId.swift` | `ItemId` typealias + deprecated `StrokeId` alias | create (1) |
| `Sources/Core/Model/TextItem.swift` | text value type (string/font/size/color/transform/bounds) | create (1) |
| `Sources/Core/Model/CanvasItem.swift` | `CanvasItem` sum type + shared accessors | create (1) |
| `Sources/Core/Model/FitiDoc.swift` | `items`/`itemOrder` (was strokes/strokeOrder) | modify (2) |
| `Sources/Core/Editor/InverseOp.swift` | `CanvasItem`-based ops + `ItemRestoreEntry` + `replaceItems` | modify (2) |
| `Sources/Core/Control/Editor.swift` | item-generic mutation surface + `addItem`/`replaceItem` | modify (2) |
| `Sources/Core/Selection/SelectionMath.swift` | item-generic hit-test / AABB / marquee | modify (3) |
| `Sources/Core/Ports/RenderFrame.swift` | `items`/`liveItems` + `editingItemId` | modify (4) |
| `Sources/Core/Editor/RenderFrame+from.swift` | build frame from items, exclude editing item | modify (4) |
| `Sources/AppKit/StrokeDrawing.swift` | `drawItem(_:in:isInProgress:)` switching stroke/text | modify (4) |
| `Sources/AppKit/CanvasView.swift` | item bake + content-tagged signature + live caret | modify (4, 12) |
| `Sources/AppKit/SnapshotRenderer.swift` | iterate items | modify (4) |
| `Sources/Core/Model/Tool.swift` | add `.text` | modify (5) |
| `Sources/Core/Control/KeyCommand.swift` | `.selectTool(Tool)` + `t`/`p` bindings | modify (5) |
| `Sources/Core/Ports/TextMeasuring.swift` | measuring port (measure + caretIndex) | create (6) |
| `Tests/CoreTests/Fakes/FakeTextMeasurer.swift` | monospace test double | create (6) |
| `Sources/Core/Control/TextEditSession.swift` | pure edit buffer + ops | create (7) |
| `Sources/Core/Control/AppController.swift` | tool `.text`, `textSession`, `isEditingText`, publishers | modify (8) |
| `Sources/Core/Control/AppController+TextTool.swift` | text pointer routing + commit | create (8) |
| `Sources/Core/Model/CursorSpec.swift` | `SystemCursor.iBeam` | modify (9) |
| `Sources/AppKit/CursorRenderer.swift` | `.iBeam` → `NSCursor.iBeam` | modify (9) |
| `Sources/AppKit/CoreTextMeasurer.swift` | CoreText impl of the port | create (10) |
| `Sources/AppKit/KeyMonitor.swift` | text-capture branch | modify (11) |
| `Sources/App/main.swift` | wire measurer, session render, editingItemId | modify (12) |
| `docs/architecture.md` | B4 rationale + geometry glossary | modify (13, 14) |
| `justfile` | `nuke-icon-cache` recipe | modify (15) |

---

# PHASE 1 — Generalize the document to `CanvasItem` (behavior-preserving)

After Phase 1 the whole codebase speaks `CanvasItem`; text data + rendering exist, but nothing can create a text item yet, so all existing behavior is unchanged.

---

### Task 1: `ItemId`, `TextItem`, `CanvasItem`

**Files:**
- Create: `Sources/Core/Model/ItemId.swift`
- Create: `Sources/Core/Model/TextItem.swift`
- Create: `Sources/Core/Model/CanvasItem.swift`
- Test: `Tests/CoreTests/ModelTests/CanvasItemTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/ModelTests/CanvasItemTests.swift`:

```swift
// ABOUTME: Tests for CanvasItem's shared accessors across the stroke and text
// ABOUTME: cases — id, transform get/set, createdAt, color.

import Testing

@Suite("CanvasItem")
struct CanvasItemTests {
    private func sampleStroke(id: ItemId = "s1") -> Stroke {
        Stroke(id: id, color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 6,
               transform: .identity, points: [StrokePoint(x: 0, y: 0)],
               pointerType: .mouse, pressureEnabled: false, createdAt: 10)
    }
    private func sampleText(id: ItemId = "t1") -> TextItem {
        TextItem(id: id, string: "hi", fontName: "Helvetica", fontSize: 24,
                 color: RGBA(r: 0, g: 0, b: 1, a: 0.8), transform: .identity,
                 bounds: Size(width: 24, height: 24), createdAt: 20)
    }

    @Test("id, createdAt, and color read through both cases")
    func sharedReads() {
        let s = CanvasItem.stroke(sampleStroke())
        let t = CanvasItem.text(sampleText())
        #expect(s.id == "s1")
        #expect(t.id == "t1")
        #expect(s.createdAt == 10)
        #expect(t.createdAt == 20)
        #expect(s.color == RGBA(r: 1, g: 0, b: 0, a: 1))
        #expect(t.color == RGBA(r: 0, g: 0, b: 1, a: 0.8))
    }

    @Test("transform set rewraps the same case")
    func transformSet() {
        var s = CanvasItem.stroke(sampleStroke())
        s.transform = Transform(x: 5, y: 6, scale: 2, rotate: 90)
        #expect(s.transform == Transform(x: 5, y: 6, scale: 2, rotate: 90))
        if case .stroke(let inner) = s { #expect(inner.transform.x == 5) } else { Issue.record("expected stroke") }

        var t = CanvasItem.text(sampleText())
        t.transform = Transform(x: 1, y: 2, scale: 1, rotate: 0)
        #expect(t.transform == Transform(x: 1, y: 2, scale: 1, rotate: 0))
        if case .text(let inner) = t { #expect(inner.transform.y == 2) } else { Issue.record("expected text") }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: compile failure — `ItemId`, `TextItem`, `CanvasItem` not found.

- [ ] **Step 3: Create `ItemId`**

Create `Sources/Core/Model/ItemId.swift`:

```swift
// ABOUTME: Stable identity for any canvas item (stroke, text, future shapes).
// ABOUTME: StrokeId is a deprecated alias kept during the CanvasItem migration.

import Foundation

public typealias ItemId = String

@available(*, deprecated, renamed: "ItemId")
public typealias StrokeId = ItemId
```

- [ ] **Step 4: Create `TextItem`**

Create `Sources/Core/Model/TextItem.swift`:

```swift
// ABOUTME: A placed text mark — string + font + frozen layout bounds. Bounds are
// ABOUTME: measured by the AppKit/CoreText adapter at commit (see architecture.md, B4).

import Foundation

public struct TextItem: Equatable, Codable, Sendable {
    public let id: ItemId
    public var string: String          // may contain "\n"
    public var fontName: String
    public var fontSize: Double
    public var color: RGBA
    public var transform: Transform
    public var bounds: Size            // local-space layout size, frozen at commit
    public let createdAt: Double

    public init(id: ItemId, string: String, fontName: String, fontSize: Double,
                color: RGBA, transform: Transform, bounds: Size, createdAt: Double) {
        self.id = id
        self.string = string
        self.fontName = fontName
        self.fontSize = fontSize
        self.color = color
        self.transform = transform
        self.bounds = bounds
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 5: Create `CanvasItem`**

Create `Sources/Core/Model/CanvasItem.swift`:

```swift
// ABOUTME: Sum type over everything the document can hold. Shared identity and
// ABOUTME: transform live here so selection/undo/render stay item-generic.

import Foundation

public enum CanvasItem: Equatable, Codable, Sendable {
    case stroke(Stroke)
    case text(TextItem)

    public var id: ItemId {
        switch self {
        case .stroke(let s): return s.id
        case .text(let t): return t.id
        }
    }

    public var createdAt: Double {
        switch self {
        case .stroke(let s): return s.createdAt
        case .text(let t): return t.createdAt
        }
    }

    public var color: RGBA {
        switch self {
        case .stroke(let s): return s.color
        case .text(let t): return t.color
        }
    }

    public var transform: Transform {
        get {
            switch self {
            case .stroke(let s): return s.transform
            case .text(let t): return t.transform
            }
        }
        set {
            switch self {
            case .stroke(var s): s.transform = newValue; self = .stroke(s)
            case .text(var t): t.transform = newValue; self = .text(t)
            }
        }
    }
}
```

- [ ] **Step 6: Run to verify pass**

Run: `just test`
Expected: PASS (the new suite plus all existing suites).

- [ ] **Step 7: Commit**

```bash
git add Sources/Core/Model/ItemId.swift Sources/Core/Model/TextItem.swift \
  Sources/Core/Model/CanvasItem.swift Tests/CoreTests/ModelTests/CanvasItemTests.swift
git commit   # Core: CanvasItem sum type (stroke|text) + TextItem + ItemId
```

---

### Task 2: Generalize `FitiDoc`, `InverseOp`, and `Editor` to `CanvasItem`

This is the atomic behavior-preserving rename. `FitiDoc` stores `CanvasItem`s; `Editor` and `InverseOp` snapshot `CanvasItem`s; the pen path wraps its `Stroke` as `.stroke(...)`. Every existing call site and test updates in this one commit so `just check` stays green.

**Files:**
- Modify: `Sources/Core/Model/FitiDoc.swift`
- Modify: `Sources/Core/Editor/InverseOp.swift`
- Modify: `Sources/Core/Control/Editor.swift`
- Modify (call sites): `Sources/Core/Control/AppController.swift`, `Sources/Core/Control/AppController+SelectionGesture.swift`, `Sources/Core/Control/AppController+Commands.swift`, `Sources/Core/Control/AppController+AutoFade.swift`, `Sources/Core/Editor/RenderFrame+from.swift`, `Sources/Core/Selection/SelectionMath.swift`, plus any `Sources/DevHTTP/` reader of `doc.strokes`.
- Tests: update existing Editor/AppController/DevHTTP tests that read `doc.strokes`/`strokeOrder`.

- [ ] **Step 1: Write/adjust the failing test**

Add to `Tests/CoreTests/EditorTests/` a new file `EditorItemOpsTests.swift` capturing the new ops (this drives the new API):

```swift
// ABOUTME: Tests for the item-generic Editor surface — addItem, replaceItem,
// ABOUTME: and replaceItems undo round-trips, alongside the existing stroke path.

import Testing

@MainActor
@Suite("Editor item ops")
struct EditorItemOpsTests {
    private func makeEditor() -> Editor {
        Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "i"))
    }
    private func text(_ id: ItemId, _ s: String) -> CanvasItem {
        .text(TextItem(id: id, string: s, fontName: "Helvetica", fontSize: 24,
                       color: RGBA(r: 0, g: 0, b: 0, a: 1), transform: .identity,
                       bounds: Size(width: 24, height: 24), createdAt: 0))
    }

    @Test("addItem inserts and undo deletes")
    func addUndo() {
        let e = makeEditor()
        e.addItem(text("t1", "hi"))
        #expect(e.doc.itemOrder == ["t1"])
        e.undo()
        #expect(e.doc.items["t1"] == nil)
        #expect(e.doc.itemOrder.isEmpty)
    }

    @Test("replaceItem swaps content in place; undo restores prior value")
    func replaceUndo() {
        let e = makeEditor()
        e.addItem(text("t1", "hi"))
        e.replaceItem(text("t1", "hello"))
        if case .text(let t)? = e.doc.items["t1"] { #expect(t.string == "hello") } else { Issue.record("missing") }
        e.undo()
        if case .text(let t)? = e.doc.items["t1"] { #expect(t.string == "hi") } else { Issue.record("missing") }
        #expect(e.doc.itemOrder == ["t1"])  // order preserved
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: compile failure — `doc.itemOrder`, `addItem`, `replaceItem` not found.

- [ ] **Step 3: Generalize `FitiDoc`**

Replace the body of `Sources/Core/Model/FitiDoc.swift`:

```swift
// ABOUTME: The drawing document — keyed map of items plus an ordered id list.
// ABOUTME: Map for identity, list for z-order. CRDT-friendly.

import Foundation

public struct FitiDoc: Equatable, Codable, Sendable {
    public var items: [ItemId: CanvasItem]
    public var itemOrder: [ItemId]

    public init(items: [ItemId: CanvasItem] = [:], itemOrder: [ItemId] = []) {
        self.items = items
        self.itemOrder = itemOrder
    }

    public static let empty = FitiDoc()
}
```

- [ ] **Step 4: Generalize `InverseOp`**

Replace `Sources/Core/Editor/InverseOp.swift` with `CanvasItem` snapshots, an `ItemRestoreEntry`, an `ItemId`-keyed `TransformEntry`, and the new `replaceItems` case:

```swift
// ABOUTME: Data records describing how to reverse a mutation.
// ABOUTME: Editor.applyInverse consumes one and produces the paired inverse.

import Foundation

public struct ItemRestoreEntry: Equatable, Sendable {
    public let snapshot: CanvasItem
    public let atIndex: Int
    public init(snapshot: CanvasItem, atIndex: Int) {
        self.snapshot = snapshot
        self.atIndex = atIndex
    }
}

public struct TransformEntry: Equatable, Sendable {
    public let itemId: ItemId
    public let transform: Transform
    public init(itemId: ItemId, transform: Transform) {
        self.itemId = itemId
        self.transform = transform
    }
}

public enum InverseOp: Equatable, Sendable {
    case deleteItem(ItemId)
    case restoreItem(snapshot: CanvasItem, atIndex: Int)
    case deleteItems([ItemId])
    case restoreItems(entries: [ItemRestoreEntry])
    case setTransforms(entries: [TransformEntry])
    case replaceItems(entries: [CanvasItem])   // restore prior full values
}
```

- [ ] **Step 5: Generalize `Editor`**

Rewrite `Sources/Core/Control/Editor.swift` so the document holds `CanvasItem`s. Key changes:
- `doc.strokes`/`strokeOrder` → `doc.items`/`itemOrder` throughout.
- `startStroke` builds a `Stroke`, stores it as `.stroke(stroke)`; `appendPoint`/`straightenCurrentStroke`/`moveCurrentStrokeEndpoint` unwrap the current item's `.stroke` case, mutate, rewrap.
- Rename `eraseStroke`→ keep `eraseItems(ids:)` (drop the singular if unused) and `transformStrokes`→`transformItems`. `clear()` snapshots `CanvasItem`s.
- Add `addItem(_ item: CanvasItem)` (undo `.deleteItem`) and `replaceItem(_ item: CanvasItem)` (capture prior value, `.replaceItems(entries: [prior])`).
- `applyInverse` handles all six cases.

Pen-path mutation helper (illustrative — current stroke unwrap):

```swift
public func appendPoint(_ point: StrokePoint) {
    guard let id = currentStrokeId, case .stroke(var s)? = doc.items[id] else { return }
    s.points.append(point)
    doc.items[id] = .stroke(s)
    emit(.local)
}
```

`addItem` / `replaceItem`:

```swift
public func addItem(_ item: CanvasItem) {
    doc.items[item.id] = item
    doc.itemOrder.append(item.id)
    pushUndo(.deleteItem(item.id))
    emit(.local)
}

@discardableResult
public func replaceItem(_ item: CanvasItem) -> Bool {
    guard let prior = doc.items[item.id] else { return false }
    doc.items[item.id] = item
    pushUndo(.replaceItems(entries: [prior]))
    emit(.local)
    return true
}
```

`applyInverse` gains:

```swift
case .replaceItems(let entries):
    var current: [CanvasItem] = []
    for item in entries {
        if let now = doc.items[item.id] { current.append(now) }
        doc.items[item.id] = item
    }
    return .replaceItems(entries: current)
```

`transformItems` mutates `doc.items[id]?.transform = newTransform` (the `CanvasItem.transform` setter handles rewrapping), and pushes `.setTransforms` built from `TransformEntry(itemId:transform:)`.

- [ ] **Step 6: Update all Core call sites**

Mechanical sweep (no behavior change):
- `AppController.swift`: `selectedStrokeIds` keeps its name (it is still item ids; do not rename in this task) but its reads of `editor.doc.strokes`→`editor.doc.items`. Pen `pointerDown` clearing logic unchanged.
- `AppController+SelectionGesture.swift`: `orderedStrokes()` → iterate `editor.doc.itemOrder`/`items`; `editor.transformStrokes` → `editor.transformItems`; `editor.eraseStrokes` stays as `eraseItems`. `snapshotTransforms()` reads `doc.items[id]?.transform`.
- `AppController+Commands.swift` (`runClear`): `editor.eraseStrokes(ids:)` → `editor.eraseItems(ids:)`.
- `AppController+AutoFade.swift`: any `doc.strokes`/`strokeOrder` → `items`/`itemOrder`.
- `RenderFrame+from.swift` and `SelectionMath.swift`: updated in Tasks 3–4; for now make them compile against `items` (minimal edits — full generalization in those tasks).
- `Sources/DevHTTP/`: any route reading `doc.strokes`/`strokeOrder` → `items`/`itemOrder` (and unwrap `.stroke` where it needs stroke-specific fields).

- [ ] **Step 7: Update existing tests**

Sweep test files: `editor.doc.strokes` → `editor.doc.items`, `strokeOrder` → `itemOrder`. Where a test reads stroke-specific fields (`.points`, `.width`, `.snappedToLine`), unwrap: `guard case .stroke(let s)? = editor.doc.items[id] else { ... }`. Transform reads can use `editor.doc.items[id]?.transform` directly (the accessor).

- [ ] **Step 8: Run to verify pass**

Run: `just check`
Expected: PASS — all suites green, lint clean, build succeeds. Behavior identical to before.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit   # Core: generalize FitiDoc/Editor/InverseOp from Stroke to CanvasItem
```

---

### Task 3: Generalize `SelectionMath` to `CanvasItem`

Hit-test, AABB, marquee, and selection bounds operate over `CanvasItem`. A stroke's box is the AABB of its transformed points (today's logic); a text's box is its local `bounds` rect with corners pushed through its `transform`.

**Files:**
- Modify: `Sources/Core/Selection/SelectionMath.swift`
- Modify (call sites): `Sources/Core/Control/AppController+SelectionGesture.swift`
- Test: `Tests/CoreTests/SelectionTests/SelectionMathItemsTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/SelectionTests/SelectionMathItemsTests.swift`:

```swift
// ABOUTME: SelectionMath over a mixed stroke+text document — hit-test, marquee,
// ABOUTME: and selection bounds use each item's box (points vs frozen text bounds).

import Testing

@Suite("SelectionMath over items")
struct SelectionMathItemsTests {
    private func textItem(_ id: ItemId, at p: Point, size: Size) -> CanvasItem {
        .text(TextItem(id: id, string: "x", fontName: "Helvetica", fontSize: 24,
                       color: RGBA(r: 0, g: 0, b: 0, a: 1),
                       transform: Transform(x: p.x, y: p.y, scale: 1, rotate: 0),
                       bounds: size, createdAt: 0))
    }

    @Test("hit-test lands inside a text item's box")
    func hitText() {
        let item = textItem("t1", at: Point(x: 100, y: 100), size: Size(width: 60, height: 24))
        let order = ["t1"]
        let items: [ItemId: CanvasItem] = ["t1": item]
        #expect(SelectionMath.hitTestItem(at: Point(x: 110, y: 108), items: items, order: order, tolerance: 2) == "t1")
        #expect(SelectionMath.hitTestItem(at: Point(x: 500, y: 500), items: items, order: order, tolerance: 2) == nil)
    }

    @Test("marquee selects an intersecting text item")
    func marqueeText() {
        let item = textItem("t1", at: Point(x: 100, y: 100), size: Size(width: 60, height: 24))
        let hits = SelectionMath.marqueeHitItems(
            rect: Rect(x: 90, y: 90, width: 40, height: 40),
            items: ["t1": item], order: ["t1"])
        #expect(hits == ["t1"])
    }
}
```

(The exact text-box anchor convention — origin at `transform` translate, box spanning `(0,0)`–`(w,h)` — is fixed here by the asserted coordinates; implement to match.)

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: compile failure — `hitTestItem`/`marqueeHitItems` not found.

- [ ] **Step 3: Implement item-generic geometry**

In `SelectionMath.swift`, add a private `localBoxCorners(of item: CanvasItem) -> [Point]` returning the four transformed corners: for `.stroke`, derive from transformed points' AABB corners; for `.text`, the rect `(0,0)`–`(bounds.w, bounds.h)` corners pushed through `transform`. Add:
- `worldAABB(of item: CanvasItem) -> Rect?` (AABB of the corners).
- `hitTestItem(at: Point, items:, order:, tolerance:) -> ItemId?` — iterate `order` reversed; `.stroke` uses the existing polyline distance; `.text` uses point-in-oriented-box (reuse the `OrientedBox` containment already used for the selection box).
- `marqueeHitItems(rect:, items:, order:) -> [ItemId]` — intersect `rect` with each `worldAABB`.
- `selectionBoundsItems(ids:, items:) -> Rect?` — union of `worldAABB`.

Keep the existing stroke-only functions or rename their callers; the new `*Item(s)` functions are what `AppController` uses.

- [ ] **Step 4: Update `AppController+SelectionGesture.swift`**

Point selection hit-tests and bounds at the new `*Item(s)` functions over `editor.doc.items`/`itemOrder`. `recomputeSelectionBox` uses `selectionBoundsItems`.

- [ ] **Step 5: Run to verify pass**

Run: `just check`
Expected: PASS — new suite green, existing selection behavior unchanged.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit   # Core: SelectionMath hit-test/marquee/bounds over CanvasItem
```

---

### Task 4: Generalize `RenderFrame` + `drawItem` + content-tagged bake

`RenderFrame` carries `items`/`liveItems` and an `editingItemId` to exclude from the bake. `drawStroke` becomes `drawItem` switching on the case; the text branch draws with CoreText (adapter). The bake signature gains a content tag so a text edit re-bakes.

**Files:**
- Modify: `Sources/Core/Ports/RenderFrame.swift`
- Modify: `Sources/Core/Editor/RenderFrame+from.swift`
- Modify: `Sources/AppKit/StrokeDrawing.swift` (add `drawItem`)
- Modify: `Sources/AppKit/CanvasView.swift`
- Modify: `Sources/AppKit/SnapshotRenderer.swift`
- Test: `Tests/CoreTests/EditorTests/RenderFrameFromTests.swift` (Core); `Tests/AppKitTests/CanvasViewBakeTests.swift` (signature)

- [ ] **Step 1: Write the failing Core test**

Create `Tests/CoreTests/EditorTests/RenderFrameFromTests.swift`:

```swift
// ABOUTME: RenderFrame.from assembles committed vs live items and excludes the
// ABOUTME: item currently being edited from the committed set.

import Testing

@MainActor
@Suite("RenderFrame.from items")
struct RenderFrameFromTests {
    @Test("editingItemId is excluded from committed items")
    func excludesEditing() {
        let e = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "i"))
        e.addItem(.text(TextItem(id: "t1", string: "hi", fontName: "Helvetica", fontSize: 24,
                                 color: RGBA(r: 0, g: 0, b: 0, a: 1), transform: .identity,
                                 bounds: Size(width: 24, height: 24), createdAt: 0)))
        let frame = RenderFrame.from(editor: e, canvasSize: Size(width: 100, height: 100),
                                     overrides: [:], editingItemId: "t1")
        #expect(frame.items.contains { $0.id == "t1" } == false)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: compile failure — `RenderFrame.from(..., editingItemId:)` and `frame.items` not found.

- [ ] **Step 3: Generalize `RenderFrame`**

```swift
// ABOUTME: Immutable snapshot the renderer draws. Committed items are baked;
// ABOUTME: live items (in-flight transforms) and the in-progress pen draw live.

public struct RenderFrame: Equatable, Sendable {
    public var items: [CanvasItem]          // committed, baked
    public var liveItems: [CanvasItem]      // in-flight transform overrides, drawn live
    public var inProgress: Stroke?          // pen stroke being drawn
    public var canvasSize: Size

    public init(items: [CanvasItem], liveItems: [CanvasItem] = [],
                inProgress: Stroke?, canvasSize: Size) {
        self.items = items
        self.liveItems = liveItems
        self.inProgress = inProgress
        self.canvasSize = canvasSize
    }
}
```

- [ ] **Step 4: Update `RenderFrame.from`**

```swift
public extension RenderFrame {
    @MainActor
    static func from(editor: Editor, canvasSize: Size) -> RenderFrame {
        from(editor: editor, canvasSize: canvasSize, overrides: [:], editingItemId: nil)
    }

    @MainActor
    static func from(editor: Editor, canvasSize: Size,
                     overrides: [ItemId: Transform], editingItemId: ItemId?) -> RenderFrame {
        var committed: [CanvasItem] = []
        var live: [CanvasItem] = []
        for id in editor.doc.itemOrder {
            guard id != editingItemId, var item = editor.doc.items[id] else { continue }
            if let override = overrides[id] {
                item.transform = override
                live.append(item)
            } else {
                committed.append(item)
            }
        }
        let inProgress = editor.currentStrokeId.flatMap { id -> Stroke? in
            if case .stroke(let s)? = editor.doc.items[id] { return s }
            return nil
        }
        return RenderFrame(items: committed, liveItems: live,
                           inProgress: inProgress, canvasSize: canvasSize)
    }
}
```

(Keep a two-arg `overrides`-only overload if existing callers need it, or update them in Step 6.)

- [ ] **Step 5: Add `drawItem` (adapter)**

In `Sources/AppKit/StrokeDrawing.swift`, keep `drawStroke` and add:

```swift
public func drawItem(_ item: CanvasItem, in ctx: CGContext, isInProgress: Bool) {
    switch item {
    case .stroke(let s): drawStroke(s, in: ctx, isInProgress: isInProgress)
    case .text(let t): drawText(t, in: ctx)
    }
}
```

Add `drawText(_:in:)` using CoreText: build an `NSAttributedString` (font `NSFont(name: t.fontName, size: t.fontSize)`, foreground from `t.color`), apply `t.transform` via the same `saveGState` → translate/rotate/scale CTM → `restoreGState` pattern `drawStroke` uses, and draw each `\n`-split line stacked by line height. Bounds/caret math is not needed here (the committed item already carries `bounds`).

- [ ] **Step 6: Update `CanvasView` and `SnapshotRenderer`**

- `CanvasView`: iterate `frame.items` for the bake and `frame.liveItems` for live drawing, calling `drawItem`. Extend `BakeSignatureEntry` to include a content tag:

```swift
struct BakeSignatureEntry: Equatable {
    let id: ItemId
    let transform: Transform
    let contentTag: Int   // strokes: stable; text: hash(string, fontName, fontSize, color)
}
```

Compute `contentTag` per case (a stroke's may be `0`; a text's an `Hasher` over string/fontName/fontSize/color). Build the signature from `frame.items`.
- `SnapshotRenderer`: iterate `frame.items` calling `drawItem`; `frame.inProgress` unchanged.

- [ ] **Step 7: Write the bake-signature test**

Create `Tests/AppKitTests/CanvasViewBakeTests.swift` asserting two frames whose only difference is a text item's `string` produce different bake signatures (use the existing `bakeSignatureForTesting` accessor). Provide a helper building a one-text-item `RenderFrame`.

- [ ] **Step 8: Run to verify pass**

Run: `just check`
Expected: PASS — Core + AppKit + integration green.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit   # Render: RenderFrame over items + drawItem + content-tagged bake
```

---

# PHASE 2 — The Text tool

---

### Task 5: `Tool.text` + `t`/`p` keybindings

**Files:**
- Modify: `Sources/Core/Model/Tool.swift`
- Modify: `Sources/Core/Control/KeyCommand.swift`
- Modify: `Sources/Core/Control/AppController+Commands.swift`
- Test: `Tests/CoreTests/AppControllerTests/ToolSwitchTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ABOUTME: t and p key commands switch the active tool.

import Testing

@MainActor
@Suite("Tool switch commands")
struct ToolSwitchTests {
    private func controller() -> AppController {
        let c = AppController(editor: Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "i")),
                              window: RecordingWindow(), detector: RecordingStationaryDetector(),
                              clock: VirtualClock(), ticker: RecordingFadeTicker())
        c.activate(); return c
    }

    @Test("t selects text, p selects pen")
    func toolKeys() {
        let c = controller()
        c.run(.selectTool(.text))
        #expect(c.currentTool == .text)
        c.run(.selectTool(.pen))
        #expect(c.currentTool == .pen)
    }

    @Test("t and p are registered bindings")
    func bindings() {
        #expect(KeyCommandRegistry.command(for: KeyBinding(character: "t")) == .selectTool(.text))
        #expect(KeyCommandRegistry.command(for: KeyBinding(character: "p")) == .selectTool(.pen))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: FAIL — `.text` tool case and `.selectTool` command not found.

- [ ] **Step 3: Add the `.text` tool**

In `Sources/Core/Model/Tool.swift`: add `case text` to the enum.

- [ ] **Step 4: Add the command + bindings**

In `KeyCommand.swift`: add `case selectTool(Tool)`; add to `KeyCommandRegistry.bindings`:
```swift
KeyBinding(character: "t"): .selectTool(.text),
KeyBinding(character: "p"): .selectTool(.pen),
```

- [ ] **Step 5: Handle it in `run`**

In `AppController+Commands.swift`, add to the switch:
```swift
case .selectTool(let tool):
    currentTool = tool
```

- [ ] **Step 6: Run to verify pass**

Run: `just check`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit   # Core: Tool.text + t/p tool-switch key commands
```

---

### Task 6: `TextMeasuring` port + `FakeTextMeasurer`

**Files:**
- Create: `Sources/Core/Ports/TextMeasuring.swift`
- Create: `Tests/CoreTests/Fakes/FakeTextMeasurer.swift`
- Test: `Tests/CoreTests/Fakes/FakeTextMeasurerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ABOUTME: Verifies the deterministic monospace fake used to test text geometry.

import Testing

@Suite("FakeTextMeasurer")
struct FakeTextMeasurerTests {
    @Test("single line: width = chars * fontSize/2, height = fontSize")
    func singleLine() {
        let m = FakeTextMeasurer()
        #expect(m.measure(string: "hello world", fontName: "Helvetica", fontSize: 24)
                == Size(width: 132, height: 24))
    }

    @Test("newline adds 1.5x font height; width is widest line")
    func multiLine() {
        let m = FakeTextMeasurer()
        let s = m.measure(string: "ab\ncdef", fontName: "Helvetica", fontSize: 20)
        #expect(s.width == 40)   // "cdef" = 4 * 10
        #expect(s.height == 50)  // 20 + 1*20*1.5
    }

    @Test("caretIndex maps a click to a column on the right line")
    func caret() {
        let m = FakeTextMeasurer()
        // "abc" @24 -> charWidth 12; x=30 -> round(30/12)=index 2 (clamped to len)
        #expect(m.caretIndex(at: Point(x: 30, y: 5), string: "abc", fontName: "Helvetica", fontSize: 24) == 2)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: compile failure — `TextMeasuring`/`FakeTextMeasurer` not found.

- [ ] **Step 3: Create the port**

`Sources/Core/Ports/TextMeasuring.swift`:

```swift
// ABOUTME: Port for measuring text geometry. The AppKit adapter implements it
// ABOUTME: with CoreText; tests use a deterministic monospace fake.

import Foundation

public protocol TextMeasuring: Sendable {
    func measure(string: String, fontName: String, fontSize: Double) -> Size
    func caretIndex(at localPoint: Point, string: String,
                    fontName: String, fontSize: Double) -> Int
}
```

- [ ] **Step 4: Create the fake**

`Tests/CoreTests/Fakes/FakeTextMeasurer.swift` implementing the documented formula: `charWidth = fontSize/2`; lines split on `"\n"`; `width = max(line.count) * charWidth`; `height = fontSize + newlineCount * fontSize * 1.5`; `caretIndex` picks a line via `floor(localY / (fontSize*1.5))` clamped, then `min(round(localX / charWidth), line.count)` plus the offset of prior lines.

- [ ] **Step 5: Run to verify pass**

Run: `just test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Ports/TextMeasuring.swift Tests/CoreTests/Fakes/FakeTextMeasurer.swift \
  Tests/CoreTests/Fakes/FakeTextMeasurerTests.swift
git commit   # Core: TextMeasuring port + monospace test fake
```

---

### Task 7: `TextEditSession` pure edit buffer

**Files:**
- Create: `Sources/Core/Control/TextEditSession.swift`
- Test: `Tests/CoreTests/TextTests/TextEditSessionTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// ABOUTME: Pure edit-buffer behavior — insert, delete, newline, caret motion
// ABOUTME: including up/down across hard-break lines, with clamping.

import Testing

@Suite("TextEditSession")
struct TextEditSessionTests {
    private func session(_ s: String, caret: Int) -> TextEditSession {
        TextEditSession(itemId: nil, string: s, caret: caret, transform: .identity,
                        color: RGBA(r: 0, g: 0, b: 0, a: 1), fontName: "Helvetica", fontSize: 24)
    }

    @Test("insert places text at the caret and advances it")
    func insert() {
        var s = session("ac", caret: 1)
        s.insert("b")
        #expect(s.string == "abc"); #expect(s.caret == 2)
    }

    @Test("deleteBackward removes the char before the caret")
    func deleteBackward() {
        var s = session("abc", caret: 2)
        s.deleteBackward()
        #expect(s.string == "ac"); #expect(s.caret == 1)
    }

    @Test("deleteBackward at index 0 is a no-op")
    func deleteAtStart() {
        var s = session("abc", caret: 0)
        s.deleteBackward()
        #expect(s.string == "abc"); #expect(s.caret == 0)
    }

    @Test("insertNewline inserts \\n")
    func newline() {
        var s = session("ab", caret: 1)
        s.insertNewline()
        #expect(s.string == "a\nb"); #expect(s.caret == 2)
    }

    @Test("moveCaret down keeps the column across lines")
    func caretDown() {
        var s = session("abcd\nef", caret: 3)   // line 0, col 3
        s.moveCaret(.down)                       // line 1 has only 2 chars -> clamp to col 2
        #expect(s.caret == 7)                    // index of end of "ef"
    }

    @Test("moveCaret left/right clamps at ends")
    func caretEnds() {
        var s = session("ab", caret: 0)
        s.moveCaret(.left); #expect(s.caret == 0)
        s.moveCaret(.right); s.moveCaret(.right); s.moveCaret(.right); #expect(s.caret == 2)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: compile failure — `TextEditSession` not found.

- [ ] **Step 3: Implement `TextEditSession`**

Create `Sources/Core/Control/TextEditSession.swift` with the struct from the design and pure methods `insert(_:)`, `deleteBackward()`, `insertNewline()`, `moveCaret(_ dir: CaretMove)` where `CaretMove` is `{ left, right, up, down, lineStart, lineEnd }`. Implement line/column via `string` split on `"\n"`; up/down preserve the current column clamped to the target line length and recompute the absolute index.

- [ ] **Step 4: Run to verify pass**

Run: `just test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Control/TextEditSession.swift Tests/CoreTests/TextTests/TextEditSessionTests.swift
git commit   # Core: TextEditSession pure edit buffer
```

---

### Task 8: AppController text routing + commit

Adds the session state, the measuring port, `isEditingText`, pointer routing (click-blank = new, click-text = edit at reverse-mapped caret), commit/discard/erase, and the layered Esc entry point.

**Files:**
- Modify: `Sources/Core/Control/AppController.swift` (port, `textSession` + `onTextSessionChanged`, `isEditingText`, `escapePressed`, route `.text` in pointer entry points)
- Create: `Sources/Core/Control/AppController+TextTool.swift` (the routing/commit logic — keeps the type body under the line limit)
- Test: `Tests/CoreTests/AppControllerTests/TextToolTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// ABOUTME: AppController text-tool routing with a FakeTextMeasurer — create,
// ABOUTME: edit-at-caret, commit/keep, Esc layering, empty/erase, size/color.

import Testing

@MainActor
@Suite("Text tool routing")
struct TextToolTests {
    private func make() -> AppController {
        let c = AppController(editor: Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "i")),
                              window: RecordingWindow(), detector: RecordingStationaryDetector(),
                              clock: VirtualClock(), ticker: RecordingFadeTicker(),
                              textMeasurer: FakeTextMeasurer())
        c.activate(); c.currentTool = .text; return c
    }

    @Test("click on blank starts a new empty session at the click")
    func clickBlankStarts() {
        let c = make()
        c.pointerDown(StrokePoint(x: 40, y: 50))
        #expect(c.isEditingText)
        #expect(c.textSession?.itemId == nil)
        #expect(c.textSession?.transform.x == 40)
    }

    @Test("typing then Return commits a text item and stays in text mode")
    func commitKeepsMode() {
        let c = make()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.insertText("hi")
        c.commitText()
        #expect(c.currentTool == .text)
        #expect(c.isEditingText == false)
        #expect(c.editor.doc.itemOrder.count == 1)
        if case .text(let t)? = c.editor.doc.items[c.editor.doc.itemOrder[0]] {
            #expect(t.string == "hi")
            #expect(t.bounds == Size(width: 24, height: 24))   // fake: 2 chars * 12
            #expect(t.fontSize == c.currentWidth * 4)
            #expect(t.color == c.currentColor)
        } else { Issue.record("expected text item") }
    }

    @Test("empty new text on commit is discarded")
    func emptyDiscarded() {
        let c = make()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.commitText()
        #expect(c.editor.doc.itemOrder.isEmpty)
    }

    @Test("clicking an existing text edits it at the reverse-mapped caret")
    func clickEdits() {
        let c = make()
        c.pointerDown(StrokePoint(x: 0, y: 0)); c.insertText("abc"); c.commitText()
        let id = c.editor.doc.itemOrder[0]
        // text origin at (0,0); click near x=30 -> fake caretIndex 2
        c.pointerDown(StrokePoint(x: 30, y: 5))
        #expect(c.textSession?.itemId == id)
        #expect(c.textSession?.caret == 2)
    }

    @Test("Esc while typing commits and drops to pen")
    func escWhileTyping() {
        let c = make()
        c.pointerDown(StrokePoint(x: 0, y: 0)); c.insertText("hi")
        c.escapePressed()
        #expect(c.currentTool == .pen)
        #expect(c.isEditingText == false)
        #expect(c.editor.doc.itemOrder.count == 1)
    }

    @Test("Esc when idle deactivates fiti")
    func escIdleDeactivates() {
        let c = make()
        c.escapePressed()
        #expect(c.mode == .inactive)
    }

    @Test("editing an existing text to empty erases it on commit")
    func emptiedErases() {
        let c = make()
        c.pointerDown(StrokePoint(x: 0, y: 0)); c.insertText("hi"); c.commitText()
        let id = c.editor.doc.itemOrder[0]
        c.pointerDown(StrokePoint(x: 0, y: 0))   // re-edit (caret 0)
        c.textSession?.string = ""               // simulate deleting all
        c.commitText()
        #expect(c.editor.doc.items[id] == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: compile failure — `textMeasurer:` init param, `isEditingText`, `textSession`, `insertText`, `commitText`, `escapePressed` not found.

- [ ] **Step 3: Add session state + port to `AppController`**

In `AppController.swift`:
- Add a stored `private let textMeasurer: TextMeasuring` and a new designated-init parameter `textMeasurer: TextMeasuring` (default-construct a measurer is not possible in Core; require it). Update existing initializers/tests to pass one — Core tests pass `FakeTextMeasurer()`; `main.swift` passes `CoreTextMeasurer()` (Task 10/12).
- Add `public var textSession: TextEditSession?` with an `onTextSessionChanged` publisher (didSet, fire on change), and `public var isEditingText: Bool { textSession != nil }`.
- Route `.text` in `pointerDown(_:modifiers:)`: `case .text: textPointerDown(point)`.
- Add `public func escapePressed()`: if `isEditingText` { `commitText(); currentTool = .pen` } else { `deactivate()` }.

Constructor fan-out: give `AppController.init` the new last parameter `textMeasurer:`. Update all existing test constructors and `main.swift` in this task's call-site sweep (tests get `FakeTextMeasurer()`; defer `main.swift`'s `CoreTextMeasurer` to Task 10, using a temporary `FakeTextMeasurer` import is not allowed in App — instead land `CoreTextMeasurer` first if needed, or pass a tiny inline measurer). To keep this task green without the CoreText adapter yet, add a minimal `CoreTextMeasurer` stub here returning zero sizes is **not** acceptable (it must be real). Therefore: **reorder** — do Task 10 (`CoreTextMeasurer`) before this task's `main.swift` change, or have `main.swift` keep compiling by constructing the controller with `CoreTextMeasurer()` introduced in Task 10. Simplest: this task wires `main.swift` to `CoreTextMeasurer()` and depends on Task 10 being done first. **Execution note: do Task 10 before Task 8's `main.swift` edit** (the rest of Task 8 is Core + tests and is independent).

- [ ] **Step 4: Implement routing in `AppController+TextTool.swift`**

```swift
// ABOUTME: Text-tool pointer routing and commit. Click blank starts a new text;
// ABOUTME: click on existing text edits it at the reverse-mapped caret.

import Foundation

extension AppController {
    func textPointerDown(_ point: StrokePoint) {
        if isEditingText { commitText() }
        let p = Point(x: point.x, y: point.y)
        if let hitId = SelectionMath.hitTestItem(at: p, items: editor.doc.items,
                                                 order: editor.doc.itemOrder,
                                                 tolerance: SelectionMetrics.handleHitRadius),
           case .text(let t)? = editor.doc.items[hitId] {
            beginEditing(t, at: p)
        } else {
            beginNewText(at: p)
        }
        refreshCursor()
    }

    private func beginNewText(at p: Point) {
        textSession = TextEditSession(
            itemId: nil, string: "", caret: 0,
            transform: Transform(x: p.x, y: p.y, scale: 1, rotate: 0),
            color: currentColor, fontName: "Helvetica", fontSize: currentWidth * 4)
    }

    private func beginEditing(_ t: TextItem, at p: Point) {
        // Map the world click into the item's local space (translate only for v1).
        let local = Point(x: p.x - t.transform.x, y: p.y - t.transform.y)
        let caret = textMeasurer.caretIndex(at: local, string: t.string,
                                            fontName: t.fontName, fontSize: t.fontSize)
        textSession = TextEditSession(itemId: t.id, string: t.string, caret: caret,
                                      transform: t.transform, color: t.color,
                                      fontName: t.fontName, fontSize: t.fontSize)
    }

    public func insertText(_ s: String) { textSession?.insert(s); fireSession() }
    public func deleteBackward() { textSession?.deleteBackward(); fireSession() }
    public func insertNewline() { textSession?.insertNewline(); fireSession() }
    public func moveCaret(_ d: TextEditSession.CaretMove) { textSession?.moveCaret(d); fireSession() }

    private func fireSession() { onTextSessionChanged?(textSession) }

    public func commitText() {
        guard let s = textSession else { return }
        textSession = nil
        let trimmed = s.string
        let measured = textMeasurer.measure(string: trimmed, fontName: s.fontName, fontSize: s.fontSize)
        if let id = s.itemId {
            if trimmed.isEmpty { _ = editor.eraseItems(ids: [id]) }
            else {
                let item = TextItem(id: id, string: trimmed, fontName: s.fontName, fontSize: s.fontSize,
                                    color: s.color, transform: s.transform, bounds: measured,
                                    createdAt: clock.now())
                _ = editor.replaceItem(.text(item))
            }
        } else if !trimmed.isEmpty {
            let id = editor.newItemId()   // see note below
            let item = TextItem(id: id, string: trimmed, fontName: s.fontName, fontSize: s.fontSize,
                                color: s.color, transform: s.transform, bounds: measured,
                                createdAt: clock.now())
            editor.addItem(.text(item))
        }
        onTextSessionChanged?(nil)
        refreshCursor()
    }
}
```

`editor.newItemId()`: expose the `IdGenerator` through a small `Editor` method (`public func newItemId() -> ItemId { ids.newStrokeId() }`) so text items get ids from the same generator. Add it in this task.

Also: `onTextSessionChanged` must fire while editing so the adapter redraws — `insertText`/`deleteBackward`/etc. call `fireSession()`.

- [ ] **Step 5: Run to verify pass**

Run: `just check`
Expected: PASS (with Task 10 done first per the execution note).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit   # Core: text-tool routing, session state, commit/erase, layered Esc
```

---

### Task 9: `SystemCursor.iBeam`

**Files:**
- Modify: `Sources/Core/Model/CursorSpec.swift`
- Modify: `Sources/AppKit/CursorRenderer.swift`
- Modify: `Sources/Core/Control/AppController+SelectionGesture.swift` (`currentCursor` returns `.iBeam` in text mode)
- Test: `Tests/CoreTests/AppControllerTests/CursorEmissionTests.swift` (add a text-mode case); `Tests/AppKitTests/CursorRendererTests.swift` (add `.iBeam`)

- [ ] **Step 1: Write the failing tests**

Add to the cursor-emission suite:
```swift
@Test("text mode shows the I-beam cursor")
@MainActor func textModeIBeam() {
    let c = /* controller, activated */
    c.currentTool = .text
    #expect(c.currentCursor == .system(.iBeam))
}
```
Add `.iBeam` to the `CursorRendererTests` "all resolve" array.

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: FAIL — `SystemCursor.iBeam` not found.

- [ ] **Step 3: Add the case + mapping**

- `CursorSpec.swift`: add `case iBeam` to `SystemCursor`.
- `CursorRenderer.nsCursor(for:)`: add `case .iBeam: return .iBeam`.
- `currentCursor` (in `AppController+SelectionGesture.swift`): when `currentTool == .text`, return `.system(.iBeam)` (before the selection/pen branches).

- [ ] **Step 4: Run to verify pass**

Run: `just check`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit   # Cursor: SystemCursor.iBeam for text mode
```

---

### Task 10: `CoreTextMeasurer` adapter

**Do this before Task 8's `main.swift` wiring** (see Task 8 Step 3 note).

**Files:**
- Create: `Sources/AppKit/CoreTextMeasurer.swift`
- Test: `Tests/AppKitTests/CoreTextMeasurerTests.swift`

- [ ] **Step 1: Write the failing smoke test**

```swift
// ABOUTME: Smoke test for the CoreText-backed measurer — plausible sizes and a
// ABOUTME: caret index within range. Not glyph-exact.

import Testing
import AppKit

@Suite("CoreTextMeasurer")
struct CoreTextMeasurerTests {
    @Test("measure returns positive size; longer string is wider")
    func measure() {
        let m = CoreTextMeasurer()
        let a = m.measure(string: "i", fontName: "Helvetica", fontSize: 24)
        let b = m.measure(string: "wwww", fontName: "Helvetica", fontSize: 24)
        #expect(a.width > 0 && a.height > 0)
        #expect(b.width > a.width)
    }

    @Test("caretIndex is within [0, count]")
    func caret() {
        let m = CoreTextMeasurer()
        let i = m.caretIndex(at: Point(x: 1000, y: 0), string: "abc", fontName: "Helvetica", fontSize: 24)
        #expect(i >= 0 && i <= 3)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `just test-integration`
Expected: compile failure — `CoreTextMeasurer` not found.

- [ ] **Step 3: Implement**

Create `Sources/AppKit/CoreTextMeasurer.swift` conforming to `TextMeasuring`. Use `NSAttributedString` + `CTFramesetterCreateWithAttributedString` / `boundingRect(with:options:)` per `\n`-line for `measure`; for `caretIndex`, build `CTLine`s per line, pick the line by `localPoint.y / lineHeight`, and use `CTLineGetStringIndexForPosition` for the column, summing prior lines' lengths (+1 per newline).

- [ ] **Step 4: Run to verify pass**

Run: `just check`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/CoreTextMeasurer.swift Tests/AppKitTests/CoreTextMeasurerTests.swift
git commit   # AppKit: CoreTextMeasurer (CoreText impl of TextMeasuring)
```

---

### Task 11: `KeyMonitor` text-capture branch

**Files:**
- Modify: `Sources/AppKit/KeyMonitor.swift`
- Test: `Tests/CoreTests/...` is not possible (KeyMonitor is AppKit). Test in `Tests/AppKitTests/KeyMonitorTextTests.swift` using synthesized `NSEvent`s, following the existing `KeyMonitor.handle` test pattern.

- [ ] **Step 1: Write the failing tests**

Synthesize `keyDown` events (matching the shape NSEvent delivers) and assert routing while a session is active:
- a printable char (`"a"`) → `controller.isEditingText` path inserts and the event is swallowed (`handle` returns nil);
- `Return` → commits (session ends);
- `Shift+Return` → inserts newline (session string gains `\n`);
- `Esc` → session ends and `currentTool == .pen`;
- while editing, `"s"` does **not** change `currentWidth` (shortcut suspended).

Use a real `AppController` with a `FakeTextMeasurer` so `isEditingText` is observable.

- [ ] **Step 2: Run to verify failure**

Run: `just test-integration`
Expected: FAIL — events not routed to text input.

- [ ] **Step 3: Implement the capture branch**

At the top of `KeyMonitor.handle(_:)`, before the Space/registry logic:
```swift
if controller.isEditingText, event.type == .keyDown {
    return handleTextKey(event)   // swallows (nil) for handled keys
}
```
`handleTextKey` maps: `Esc` (keyCode 53) → `controller.escapePressed()`; `Return` (keyCode 36) with shift → `controller.insertNewline()` else `controller.commitText()`; Backspace (keyCode 51) → `controller.deleteBackward()`; arrows (123–126) → `controller.moveCaret(...)`; `Cmd`-combos → return the event (pass to menubar); otherwise `controller.insertText(event.characters ?? "")` and return nil. Also guard the existing Space branch so it only switches to selection when `controller.currentTool == .pen`, and the Space keyUp only resets to `.pen` when `controller.currentTool == .selection`.

- [ ] **Step 4: Run to verify pass**

Run: `just check`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit   # AppKit: KeyMonitor routes keystrokes to the text session while editing
```

---

### Task 12: `main.swift` wiring + live text/caret rendering

**Files:**
- Modify: `Sources/App/main.swift`
- Modify: `Sources/AppKit/CanvasView.swift` (draw the live session text + caret)
- Test: `Tests/AppKitTests/CanvasViewTextSessionTests.swift` (smoke: setting a session draws without crashing; clearing it removes the caret)

- [ ] **Step 1: Write the failing smoke test**

Drive `CanvasView` with a text-session snapshot (a small `setTextSession(_:)` API mirroring `setSelectionBox`) and assert it stores/clears and triggers `needsDisplay`-style state, plus a render pass does not crash. Keep assertions at the storage level (headless views don't reliably retain `needsDisplay`), as the existing `CanvasViewSelectionTests` do.

- [ ] **Step 2: Run to verify failure**

Run: `just test-integration`
Expected: FAIL — `setTextSession` not found.

- [ ] **Step 3: Implement live rendering + wiring**

- `CanvasView`: add `setTextSession(_ session: TextSessionSnapshot?)` storing the live string/caret/transform/color/fontSize; in `draw`, after chrome, draw the live text (reusing `drawText`) and a caret rectangle at the caret index (compute caret x via a `CoreTextMeasurer` instance the view holds, or via a passed measurer). Define a small `TextSessionSnapshot` value the App layer maps from `TextEditSession`.
- `main.swift`:
  - Construct `let measurer = CoreTextMeasurer()` and pass it to `AppController(..., textMeasurer: measurer)`.
  - `controller.onTextSessionChanged = { session in self.canvas.setTextSession(session.map(TextSessionSnapshot.init)); self.canvas.render(RenderFrame.from(editor: ..., overrides: ..., editingItemId: session?.itemId)) }`.
  - Update the existing editor-change render call to pass `editingItemId: controller.textSession?.itemId`.

- [ ] **Step 4: Run to verify pass**

Run: `just check`
Expected: PASS.

- [ ] **Step 5: Manual verification**

Run: `just run`, press `t`, click, type "hello", press Return; click the text, edit it; press `p` to go to pen; in selection mode (Space) move/rotate the text. Confirm via `just inspect-doc` that a text item exists with the expected string.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit   # App: wire CoreTextMeasurer + live text/caret rendering for the text tool
```

---

# PHASE 3 — Documentation and ops

---

### Task 13: Document the B4 bounds decision in `architecture.md`

**Files:**
- Modify: `docs/architecture.md`
- Modify: `Sources/Core/Model/TextItem.swift` (pointer comment)

- [ ] **Step 1: Add the architecture note**

Add a "Text geometry (B4)" subsection to `docs/architecture.md` explaining: the `TextMeasuring` port, that bounds are measured once at commit and frozen onto `TextItem`, why a derived field lives in the (CRDT-bound) document, and the re-derive escape hatch via the port. (No test.)

- [ ] **Step 2: Add the code pointer**

Above `TextItem.bounds`, add a one-line comment: `// Frozen at commit by TextMeasuring (B4); see docs/architecture.md "Text geometry".`

- [ ] **Step 3: Verify + commit**

Run: `just check` (docs change still builds).
```bash
git add docs/architecture.md Sources/Core/Model/TextItem.swift
git commit   # docs: B4 text-bounds rationale in architecture.md + code pointer
```

---

### Task 14: Geometry glossary in `architecture.md`

**Files:**
- Modify: `docs/architecture.md`

- [ ] **Step 1: Add a glossary section**

Add "Geometry glossary" defining: **AABB** (axis-aligned bounding box — the upright rectangle enclosing a shape, used for marquee tests and initial selection bounds), **bounding box** (generic enclosing rectangle), and **oriented box** (`OrientedBox` — the tilted rectangle hugging a rotated item, used for selection chrome and hit-testing). Include the upright-vs-tilted distinction.

- [ ] **Step 2: Verify + commit**

Run: `just check`.
```bash
git add docs/architecture.md
git commit   # docs: geometry glossary (AABB / bounding box / oriented box)
```

---

### Task 15: `nuke-icon-cache` justfile recipe

**Files:**
- Modify: `justfile`

- [ ] **Step 1: Add the recipe**

In the `assets / icons` section of the `justfile`, add (mirroring montty/limn):

```just
# Nuke the macOS icon cache. Run after changing the app icon if Finder/Dock still
# shows the old one. Pass --force to actually delete (requires sudo).
[group('assets')]
nuke-icon-cache force="":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Commands to clear macOS icon caches:"
    echo "  sudo rm -rf /Library/Caches/com.apple.iconservices.store"
    echo "  killall Dock Finder"
    if [ "{{force}}" = "--force" ]; then
        echo "Clearing caches (requires sudo)..."
        sudo rm -rf /Library/Caches/com.apple.iconservices.store
        sudo find /private/var/folders/ \( -name com.apple.dock.iconcache -or -name com.apple.iconservices \) -exec rm -rf {} \; 2>/dev/null || true
        killall Dock; killall Finder
        echo "Done. Dock and Finder restarted."
    else
        echo "Dry run. To execute: just nuke-icon-cache --force"
    fi
```

- [ ] **Step 2: Verify + commit**

Run: `just --list` (recipe appears under `assets`); `just check`.
```bash
git add justfile
git commit   # just: nuke-icon-cache recipe for refreshing the app icon
```

---

## Execution notes

- **Task ordering wrinkle:** Task 8 wires `main.swift` to `CoreTextMeasurer`, which Task 10 creates. Do **Task 10 before Task 8's `main.swift`/init fan-out** (Task 8's Core logic + tests are otherwise independent). The subagent runner should sequence: 5, 6, 7, 10, 8, 9, 11, 12, then 13–15. Phase 1 (1–4) is strictly first.
- Every task ends green: the failing test is committed together with the code that makes it pass; the "verify failure" step is a local `just test` run, never a commit.
- The `AppController.init` gains a `textMeasurer:` parameter in Task 8; that single signature change must update every constructor call site (tests + `main.swift`) in the same commit.
