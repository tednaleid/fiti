# fiti Selection Tool Design

Date: 2026-05-20
Status: Design — not yet implemented.

## Goal

Add a selection tool that lets users pick previously-drawn strokes and manipulate them as a group: translate (drag), uniform scale (corner handles), rotate (handle above the box), and delete (the `Delete` key). Activation is press-and-hold `Space` so the modal switch feels ephemeral. The pen tool stays the default; selection is a transient detour.

## Non-goals

- Non-uniform (per-axis) scale. The existing `Transform` struct stores `scale: Double` (uniform), and perfect-freehand stroke widths look weird under non-uniform scaling. Four corner handles only.
- Per-stroke editing of style after creation (color, width, opacity). Selecting strokes does not unlock the toolbar's color/width sliders to retroactively restyle them. Separate future item.
- Cross-display selection. The canvas is single-display (`docs/specs/2026-05-16-fiti-roadmap.md` "Multi-display"); when the richer one-window-per-display version lands, selection will need to be revisited.
- A toolbar button for switching tools. Press-and-hold `Space` is the only entry point in v1; a toolbar button can land later with discoverability concerns.
- Selection serialization across app restart. Strokes themselves don't persist yet (see Persistence in the roadmap), so neither does a selection over them.

## Architecture

Three pieces.

### Core: `Tool` enum on `AppController`

New parallel state independent of `mode`:

```swift
public enum Tool: Equatable, Sendable {
    case pen
    case selection
}

public private(set) var currentTool: Tool = .pen {
    didSet {
        guard oldValue != currentTool else { return }
        onCurrentToolChanged?(currentTool)
        refreshCursor()
    }
}
public var onCurrentToolChanged: ((Tool) -> Void)?
```

`mode` keeps its three cases (`.inactive` / `.activeIdle` / `.activeDrawing`). Mode and tool are orthogonal: you can be in `.activeIdle` with either pen or selection; `.activeDrawing` only applies to pen. The pointer routing inside `AppController` reads `currentTool` to decide what `pointerDown` means.

### Core: `Selection` state on `AppController`

```swift
public private(set) var selectedStrokeIds: [StrokeId] = [] {
    didSet { if oldValue != selectedStrokeIds { onSelectionChanged?(selectedStrokeIds) } }
}
public var onSelectionChanged: (([StrokeId]) -> Void)?
```

Ordered list (not Set) so renderers can iterate deterministically. Selection lives on AppController, not Editor, because selection is presentation state. The Editor cares only about strokes and their transforms.

### Core: hit-testing + selection box geometry

New file `Sources/Core/Selection/SelectionMath.swift` (pure functions, no AppKit):

```swift
public enum SelectionMath {
    /// Returns the smallest StrokeId whose transformed polyline passes within
    /// `tolerance` points of `query`, or nil. "Smallest" = topmost in z-order
    /// (later strokes draw over earlier ones, so they should be hit first).
    public static func hitTest(point query: StrokePoint, strokes: [Stroke], tolerance: Double) -> StrokeId?

    /// Returns every StrokeId whose AABB (after transform) intersects `rect`.
    public static func marqueeHit(rect: Rect, strokes: [Stroke]) -> [StrokeId]

    /// AABB enclosing the union of every selected stroke's transformed points.
    public static func selectionBounds(strokeIds: [StrokeId], strokes: [String: Stroke]) -> Rect?
}
```

Hit-test uses distance-from-polyline within `stroke.width / 2 + tolerance`. Marquee uses bounding-box intersection (selects strokes that overlap the marquee, not strictly-contained ones). The renderer that draws the selection box also reads `selectionBounds`.

### Core: Editor batched ops

Two new Editor methods, both single undoable ops:

```swift
public func transformStrokes(_ updates: [(id: StrokeId, transform: Transform)]) -> Bool
public func eraseStrokes(ids: [StrokeId]) -> Bool
```

`transformStrokes` captures each stroke's old transform, applies the new one, and pushes a single inverse op restoring old transforms in bulk. `eraseStrokes` removes the strokes and pushes one `restoreStrokes` op (the same primitive `clear()` and the auto-fade expiration already use).

### AppKit: pointer routing in selection mode

The existing `pointerDown` / `pointerMoved` / `pointerUp` callbacks on `AppController` are pen-centric. They keep their existing signatures (so the activation-gate and HTTP code paths don't churn) and gain a sibling overload that carries modifier state:

```swift
public struct PointerModifiers: Equatable, Sendable {
    public var command: Bool
    public var shift: Bool
    public init(command: Bool = false, shift: Bool = false) { ... }
    public static let none = PointerModifiers()
}

public func pointerDown(_ point: StrokePoint, modifiers: PointerModifiers = .none) {
    lastInputAt = clock.now()
    guard mode != .inactive else { return }
    switch currentTool {
    case .pen: penPointerDown(point)
    case .selection: selectionPointerDown(point, modifiers: modifiers)
    }
}
```

`PointerModifiers` is a pure-Core value type so AppKit types don't leak. The AppKit adapter (`NSEventInputSource`) extracts `event.modifierFlags` and constructs the value before forwarding. Existing pen-only callers (HTTP, the legacy pen tests) keep calling the no-modifier overload via the default argument. Same pattern for `pointerMoved`/`pointerUp`.

### AppKit: KeyMonitor extension for Space

Press-and-hold `Space` is unlike the existing `KeyCommandRegistry` bindings (which fire once per keypress). KeyMonitor gains a separate branch:

```swift
internal func handle(_ event: NSEvent) -> NSEvent? {
    // ... existing keyDown logic ...
    if event.type == .keyDown && event.charactersIgnoringModifiers == " " && !event.isARepeat {
        controller.currentTool = .selection
        return nil
    }
    if event.type == .keyUp && event.charactersIgnoringModifiers == " " {
        controller.currentTool = .pen
        return nil
    }
    // ... existing registry lookup ...
}
```

KeyMonitor installs a monitor for both `.keyDown` and `.keyUp` events. `isARepeat` filters out keyboard autorepeats so holding Space doesn't constantly re-set the tool. On release, currentTool reverts to `.pen` but the selection is preserved (per user choice).

### AppKit: selection rendering

Selection box, handles, and marquee outline render in `Sources/AppKit/CanvasView.swift`. New stored state on the view: `selectionBounds: Rect?`, `marqueeRect: Rect?`, and a `selectionOverlayColor: NSColor` derived from `controlAccentColor` for theme adaptation. `setSelectionBounds(_:)` and `setMarquee(_:)` setters trigger redraw. The draw routine, after the existing stroke pass, draws:

1. Selection AABB outline (1pt accent, dashed if rotated would not be visible — solid for axis-aligned bounds).
2. Four corner squares (6×6pt, filled accent, 1pt outline).
3. Rotation handle: small circle anchored 20pt above the top-midpoint, connected by a 1pt line.
4. Marquee rectangle (1pt accent, dashed, with a 0.15-alpha accent fill).

## Interaction

### Tool entry / exit

| Trigger | Effect |
| --- | --- |
| `Space` keyDown (not repeat) while active | `currentTool = .selection`, cursor becomes arrow |
| `Space` keyUp | `currentTool = .pen`, cursor reverts to fiti circle. Selection persists. |
| `Esc` while selection mode active | `currentTool = .pen`, selection clears. (Esc with selection but mode is `.activeIdle`/pen also clears the selection.) |
| Drawing a new stroke (pen pointerDown) | Selection clears as a side-effect of the new stroke commit. |

`Esc` semantics extend the existing "Esc deactivates" only when no selection exists. When a selection exists, Esc clears the selection first; a second Esc deactivates fiti entirely.

### Selection pointer states (while `currentTool == .selection`)

State machine:

```
                             ┌──────────┐
                             │   idle   │
                             └────┬─────┘
                                  │ pointerDown
                                  ▼
              ┌───────────────────────────────────┐
              │ hit-test the click point          │
              └───┬────────────┬──────────────┬───┘
                  │            │              │
                  │ on stroke  │ on handle    │ on empty space
                  ▼            ▼              ▼
        ┌──────────────┐ ┌───────────┐ ┌─────────────┐
        │ select       │ │ resize /  │ │ start       │
        │ (replace)    │ │ rotate /  │ │ marquee     │
        │ + drag-trans │ │ translate │ │             │
        └──────────────┘ └───────────┘ └─────────────┘
                                  │                │
                  pointerMoved   ▼                ▼
              update transform / extend marquee  ...
                                  │                │
                  pointerUp      ▼                ▼
              commit Editor op   |        commit marqueeHit selection
                                  │                │
                                  └────────────────┘
```

Specifics:
- **Click on a stroke**, no modifier: replace selection with that stroke, then enter drag-translate (so single click + drag moves it).
- **Cmd-click on a stroke**: add/remove from selection. Does not enter drag mode (single Cmd-click is a discrete add/remove, not a drag).
- **Click on a corner handle**: enter resize. Drag scales the selection uniformly around the selection center. Anchor is the diagonally-opposite corner.
- **Click on the rotation handle**: enter rotate. Drag changes rotation around the selection center. Snap to 15° increments while `Shift` is held.
- **Click on the selection body** (inside box but not on a handle, not on a stroke): enter drag-translate.
- **Click on empty space** (no stroke and no handle): clear selection, start a marquee at the click point. Drag extends the marquee. On pointerUp, set selection = `marqueeHit(...)`.

### Transform composition

Resize, rotate, and translate all decompose into "delta from gesture start". When a resize/rotate gesture begins, snapshot each selected stroke's `Transform` into a local dictionary. On each `pointerMoved`, compute the delta from the original gesture point, apply that delta to each snapshot, and write the result via `editor.transformStrokes(...)`. This avoids float drift from cumulative deltas across many moves.

For uniform scale around point `C` with factor `s` and an original transform `(tx, ty, scale, rotate)`:
- new translate.x = C.x + s * (tx - C.x)
- new translate.y = C.y + s * (ty - C.y)
- new scale       = scale * s
- new rotate      = rotate

For rotation around point `C` by `θ` and original transform `(tx, ty, scale, rotate)`:
- new translate   = rotate (tx, ty) around C by θ
- new scale       = scale
- new rotate      = rotate + θ

For translation by `(dx, dy)`:
- new translate   = (tx + dx, ty + dy)
- everything else unchanged

Only one `transformStrokes` call commits to the undo stack per gesture (pointerUp). Intermediate updates render via an in-flight overlay on `AppController`:

```swift
public private(set) var inFlightTransforms: [StrokeId: Transform] = [:]
public var onInFlightTransformsChanged: (([StrokeId: Transform]) -> Void)?
```

Each `pointerMoved` during a transform gesture rebuilds `inFlightTransforms` from the snapshot-at-gesture-start and the delta. The renderer reads `RenderFrame.from(editor:overrides:)` which composes editor strokes with the controller's overrides. On `pointerUp`, `editor.transformStrokes(...)` is called once with the final transforms (capturing the original snapshot as the undo entry), and `inFlightTransforms` clears. This means the Editor never sees intermediate states, and only one undo entry exists per gesture.

### Delete

`KeyCommandRegistry` already maps `Delete` → `.clear`. Update `AppController.run(.clear)` to be selection-aware:

```swift
public func run(_ command: KeyCommand) {
    switch command {
    // ... other cases ...
    case .clear:
        if !selectedStrokeIds.isEmpty {
            _ = editor.eraseStrokes(ids: selectedStrokeIds)
            selectedStrokeIds = []
        } else {
            clear()
        }
    }
}
```

`Cmd+K` (menubar) keeps its current "always clear everything" semantics — its action goes through `AppController.clear()`, not `run(.clear)`. Two distinct verbs.

## UI surface

### Cursor

- `currentTool == .pen`: existing fiti circle cursor (unchanged).
- `currentTool == .selection`: system arrow cursor.
- During a transform gesture (resize/rotate/translate): keep the arrow (no special resize cursors in v1).

`CursorSpec` already drives this via `refreshCursor()`. Extend `currentCursor` to return `nil` when `currentTool == .selection` (which already causes the arrow to render).

### Selection box

Drawn AFTER the stroke pass so it's always visible on top:
- AABB outline: 1pt, `controlAccentColor`.
- Corner handles: 6×6pt squares, filled `controlAccentColor`, 1pt `windowBackgroundColor` outline so they show on any background.
- Rotation handle: 8pt diameter circle, filled accent, 1pt outline, 20pt above top-mid.
- Connection line: 1pt accent from top-midpoint to rotation handle.

### Marquee

- 1pt accent, dashed (4pt on, 4pt off).
- Interior fill: accent at 0.15 alpha.
- Disappears on pointerUp.

### Menubar

The Drawing submenu doesn't change. Selection isn't surfaced as a menu item in v1 — press-and-hold Space is the only entry. Future: maybe a "Selection mode" toggle item if the discoverability concern surfaces.

## Testing strategy

### Core (`Tests/CoreTests/`)

**`SelectionMathTests.swift`** — pure-function hit-test and marquee:
- Hit-test: a point exactly on a stroke polyline returns that stroke's id.
- Hit-test: a point off the polyline by less than `width/2 + tolerance` still hits.
- Hit-test: a point further than that returns nil.
- Hit-test: with two overlapping strokes, the later-created one (topmost) wins.
- Marquee: a rect overlapping a stroke's AABB returns that stroke's id.
- Marquee: a rect strictly inside the stroke's AABB without crossing returns that stroke's id (bounding-box intersection, not "marquee fully contains stroke").
- Marquee: a rect fully outside any stroke's AABB returns an empty list.
- `selectionBounds`: union AABB of multiple selected strokes.
- `selectionBounds`: empty list returns nil.

**`AppControllerToolTests.swift`** — tool state transitions:
- `currentTool` defaults to `.pen`.
- Setting `currentTool = .selection` fires `onCurrentToolChanged`.
- Setting the same value twice fires the publisher only once.
- `refreshCursor` produces nil cursor (arrow) when `currentTool == .selection` AND `mode != .inactive`.

**`AppControllerSelectionTests.swift`** — pointer routing:
- In `.activeIdle` with `currentTool = .selection`, a `pointerDown` on a stroke replaces selection.
- A second click on a different stroke replaces selection (single-click is replace, not toggle).
- Cmd-modifier `pointerDown` via the new `pointerDown(_:modifiers:)` overload adds/removes that stroke from the existing selection (does not trigger a drag-translate).
- A drag from empty space sets `marqueeRect`; pointerUp populates `selectedStrokeIds` from `marqueeHit`.
- A drag on a stroke (after a click-select) translates the stroke; the transform commits on pointerUp via `transformStrokes`.
- `pointerDown` while `currentTool == .pen` ignores selection logic and goes through pen path.

**`EditorTransformStrokesTests.swift`**:
- Applying transforms to two strokes via `transformStrokes` is one undoable op.
- `undo` restores both strokes' original transforms.
- `redo` re-applies both.

**`EditorEraseStrokesTests.swift`**:
- `eraseStrokes(ids:)` removes all listed strokes.
- One undo restores all of them at original z-order (uses `restoreStrokes`).

**`AppControllerRunCommandTests.swift`** additions:
- `run(.clear)` with non-empty `selectedStrokeIds` only erases those strokes; the rest remain.
- `run(.clear)` with empty selection clears everything (existing behavior).

### AppKit (`Tests/AppKitTests/`)

- `KeyMonitorTests`: Space keyDown sets `currentTool = .selection`; Space keyUp reverts to `.pen`. Repeat events (`isARepeat == true`) are ignored.
- `CanvasViewTests` (new file or addition): `setSelectionBounds(...)` draws the selection box at the given rect (sampled-pixel check at the expected outline coords).

### What's NOT unit-tested

- Pixel-perfect handle positions and selection-box rendering (visual smoke test).
- NSEvent local monitor's keyUp path with real keyboard input (covered manually).

## Acceptance criteria

- [ ] Press-and-hold `Space` while fiti is active flips currentTool to selection; cursor switches to arrow.
- [ ] Releasing `Space` reverts to pen; any active selection persists.
- [ ] Click on a stroke replaces selection with that stroke. Cmd-click toggles individual stroke membership.
- [ ] Drag from an empty area shows a marquee rectangle; on release, selection becomes every stroke whose AABB intersects the marquee.
- [ ] Selection box renders with 4 corner handles and one rotation handle above the top midpoint.
- [ ] Drag the body of the selection to translate; commits one undoable op on release.
- [ ] Drag a corner to scale uniformly around the selection center.
- [ ] Drag the rotation handle to rotate around the selection center. `Shift` snaps to 15° increments.
- [ ] Press `Delete` with a non-empty selection: only selected strokes erase, in one undoable op. Press `Delete` with empty selection: existing "clear all" behavior.
- [ ] `Cmd+K` always clears everything regardless of selection.
- [ ] `Esc` with a non-empty selection clears the selection (does not deactivate fiti). `Esc` with no selection deactivates fiti.
- [ ] Drawing a new stroke (pen mode) implicitly clears any prior selection.
- [ ] `Sources/Core/` has zero AppKit/CoreGraphics/Network/SwiftUI imports.
- [ ] Full test suite stays under 5 seconds (`just check`).

## Open questions / future

- Should the rotation handle's 15° snap angle be configurable, or should we add other snap angles (`Cmd`+drag for 1° increments, `Shift` for 15°, free otherwise)?
- Selection persistence across mode toggles (e.g., Opt+F deactivate / reactivate): clear or preserve? Probably preserve, since the selection is purely document state. Confirm during implementation.
- Toolbar button for tool switching: defer to a future "tools palette" item if discoverability of `Space` proves a problem.
- Eraser tool: shares hit-testing with selection. Landing eraser right after this would let us reuse `SelectionMath.hitTest`.
