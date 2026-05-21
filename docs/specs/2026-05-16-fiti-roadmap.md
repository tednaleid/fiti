# fiti Roadmap

Date: 2026-05-16 (refreshed 2026-05-20)
Status: Backlog. Items here are not committed scope. Each item becomes a brainstorm → design spec → implementation plan when it's time to land.

## What this is

A running list of things that move fiti from "POC + hardened" to "an app I actually want to use." Items are roughly grouped by impact, not committed to an order. Anything that's a separate independent spec gets a checkbox so we can tick it off as work begins.

## Shipped

- [x] Menubar status item (active/idle SF Symbol icons; menu for activate/deactivate, preferences, clear, undo, redo, quit) — `Sources/AppKit/MenubarController.swift`.
- [x] Floating toolbar (color quick-picks, custom color, width slider, opacity slider, hide/show button) — `Sources/AppKit/ToolbarController.swift`.
- [x] Hide / show drawings (toolbar button + `AppController.drawingsVisible` state). Global hotkey is still missing — see open items below.
- [x] User-customizable activation hotkey via `sindresorhus/KeyboardShortcuts`. Default Opt+F. Preferences UI with `RecorderCocoa` ships in 0.2.0.
- [x] Launch-at-login toggle via `SMAppService.mainApp` — Preferences UI in 0.2.0.
- [x] Perfect-freehand Swift port (tapered, velocity-aware strokes). `simulatePressure: true` synthesises pressure from velocity for mouse input.
- [x] Retina-correct two-canvas bake (`window.backingScaleFactor` multiplier + CTM compensation).
- [x] Hold-to-straighten gesture (Notability-style draw-and-hold-to-snap, then rubber-band the endpoint).
- [x] Real code signing (Developer ID Application cert via `FITI_CODE_SIGN_IDENTITY`), notarization in CI, reproducible CI builds via GitHub secrets.
- [x] Dev HTTP surface gated behind `#if DEBUG` — Release binaries do not link Network or expose `localhost:9876`.
- [x] Disappearing drawings (auto-fade) — opt-in toolbar toggle (clock glyph). 10s solid + 2s linear fade, then `editor.clear()` in one undoable op. `Sources/Core/Control/AppController.swift` owns the state machine; `Sources/AppKit/TimerFadeTicker.swift` drives the 30Hz tick.
- [x] Active-app keyboard shortcuts — `1`-`8` (color), `s` / `Shift+S` (size), `o` / `Shift+O` (opacity), `h` (hide), `f` (auto-fade), `Delete` (clear). Pure-Core `KeyCommandRegistry` is the source of truth, dispatched by `Sources/AppKit/KeyMonitor.swift`. Discoverable via toolbar tooltips and the menubar "Drawing" submenu.
- [x] Canvas follows the toolbar to whichever monitor it lives on. `NSWindow.didChangeScreenNotification` observer on the toolbar panel relocates the full-screen canvas; drawings clear on monitor switch (one-`Cmd+Z` restores at original coordinates).

## Open: visibility & interaction

### Global hide/show hotkey
- [ ] Toolbar already has a hide/show button; need a system-wide hotkey so you can toggle visibility without going through the toolbar. Default: `Opt+H`. Wire through `KeyboardShortcuts.Name.toggleDrawingsVisible` so it gets the same rebind-in-Preferences treatment as the activation hotkey.
- [ ] `Opt+H` in most apps types the `˙` combining-diacritic. That character is rarely needed in normal typing; rebinding is the escape hatch for anyone who does need it.
- [ ] Fall-through when there's nothing to hide: if `editor.doc.strokes.isEmpty`, the hotkey should *not* intercept the keystroke — pass it through so apps still see `Opt+H` and the `˙` character types normally. Only swallow the event when there's actually something to toggle.
  - Implementation tension: `KeyboardShortcuts` is Carbon-backed (`RegisterEventHotKey`), which always intercepts at the OS level — there's no "decline" return code. Two options to get fall-through: (a) after receiving the event, re-synthesise and post the original keypress via `CGEventPost` when we want to "let it through" — gross but doesn't need extra entitlements; (b) bypass the library for this one binding and use a `CGEventTap` (needs Accessibility permission in System Settings → Privacy & Security). Option (a) is the lower-friction default; revisit if it has noticeable latency or feels janky.
- [ ] The hotkey works regardless of fiti's activation state — it's purely about whether marks are rendered. Activating fiti is still `Opt+F`.

### Keyboard slots reserved for future tools
- [ ] `e`: eraser tool (when Eraser as a UI tool ships).
- [ ] `p`: pen tool (default; only useful once a non-pen tool exists to switch back from).
- [ ] `Space`: selection tool (press-and-hold, see selection design). Tentative; final choice between `Space` and a dedicated letter gets decided in the selection-tool brainstorm.
- These slots are deliberately absent from `KeyCommandRegistry` today. The registry's tests assert they resolve to `nil` so a future binding can't be added silently.

### Selection tool
- [ ] Selection / pointer tool that lets the user pick previously drawn strokes and manipulate them.
  - Click on a stroke: select it (replaces previous selection).
  - `Cmd`-click: add/remove from selection.
  - Drag from empty area: rubber-band a marquee box; release selects all strokes whose bounding box intersects the marquee.
  - Once selected, the selection bounding box renders with eight resize handles (corners and midpoints) and a separate rotation handle anchored above the top edge.
  - Drag the body of the selection to translate. Drag a corner/edge handle to scale (Shift to lock aspect ratio). Drag the rotation handle to rotate around the selection center.
  - `Delete` with a selection removes only the selected strokes (one undoable op). With no selection, `Delete` keeps its current behavior of clearing everything.
  - `Esc` or click in empty space dismisses the selection.
- [ ] Activated by the keyboard shortcut item above (`Space` press-and-hold leaning likeliest, TBD in design). Returns to pen when released or another tool selected.
- [ ] Implementation surface:
  - New `AppController.Mode` case (`.activeSelecting`) or a parallel "current tool" state independent of mode. The latter scales better as more tools land.
  - `Editor` gains `transformStrokes(ids:translate:scale:rotate:)` as a single undoable op so one drag = one undo entry.
  - `Editor` gains `eraseStrokes(ids:)` (or extends the existing `eraseStroke`) as a batched single undoable op for the Delete-selected case.
  - Hit-testing helper in Core: point-in-polygon for perfect-freehand strokes, distance-from-path within `width/2 + tolerance` for any legacy uniform strokes.
  - Bounding-box / marquee math also in Core (testable without AppKit).
  - Selection rendering (handles, marquee outline) lives in `Sources/AppKit/CanvasView.swift` since it's a presentation concern.

## Open: stroke rendering & tools

### Perfect-freehand option sliders
- [ ] v1 ships with `smoothing/thinning/streamline = 0.5` and `simulatePressure: true` hardcoded. Promote one or more to toolbar sliders only if real use reveals the defaults feel wrong (too laggy, too jittery, taper too aggressive). Likely candidates if anything turns out wrong: a single "smoothness" slider scaling `smoothing + streamline` together, then `thinning` if the velocity-taper feels off.

### Shape tools
- [ ] Rect, ellipse, arrow. Each becomes a `Stroke` variant with `kind: .rect | .ellipse | .arrow`. The model needs a discriminator; render path picks geometry by `kind`. Hit-testing for the selection tool also has to grow per-kind logic.

### Eraser as a UI tool
- [ ] Pointer in eraser mode finds the topmost stroke under it (hit-test) and calls `eraseStroke(id)`. The data path already works via HTTP; the UI surface is what's missing. Shares the hit-test helper with the selection tool — land that first or in the same milestone.

## Open: distribution & polish

### App icon
- [ ] Fiti currently ships with the default macOS app placeholder icon. Even though `LSUIElement = true` keeps it out of the Dock, the icon still appears in Finder, the menubar status item (currently a system theatermask glyph), and the cask "About" panel. Reference: `../limn/scripts/generate-app-icon.py` renders an `Assets.xcassets/AppIcon.appiconset` from a single source PNG/SVG via `sips` at all 10 required sizes. Mnemonic: "fiti" is short for graffiti — a brush, spraycan, or marker silhouette would fit.

### Persistence
- [ ] Strokes don't survive app restart. For real daily-driver usage we probably want a session that persists, with a "clear" that's separate from "quit." Could be as simple as JSON-encoding `FitiDoc` to `~/Library/Application Support/fiti/session.json` on every change. Needs a versioned doc shape so future schema changes are migratable.
- [ ] Open question: persistence of toolbar position, hide-state, opacity — already in UserDefaults under `fiti.*` keys; doc persistence is a separate concern.

### Multi-display
- Shipped (0.3.0): the canvas window follows whichever monitor hosts the toolbar. One display at a time; strokes clear on a monitor switch.
- [ ] Richer version: one canvas per display, all sharing the same `Editor`. Strokes get a `displayId` or get coordinates resolved to a global space — open design question. Affects how the selection tool's marquee behaves across displays.

## Code-level cleanup (not features)

- [ ] `Sources/DevHTTP/DevHTTPServer.swift:12` — `@unchecked Sendable` is a Swift-6 concession. Proper fix: make `DevHTTPServer` an actor, or replace the `start()` busy-wait with a semaphore signaled from the NWListener state handler. Resolves the `boundPort` data race in the same step.

## Out of scope (deliberately not on this list)

These are punted, not forgotten, but I'm not planning to revisit them soon:

- Pen / touch / iPad input
- Automerge / CRDT sync (the doc shape is ready; nothing else is)
- Cloud sync, accounts, sharing
- iOS / iPadOS port
- A web companion

## Open questions worth answering before picking anything up

1. **What's the upgrade story when the document shape changes?** Persistence implies versioned doc; we should pick that scheme before writing the first version to disk.
2. **Do we want a "presentation mode" preset?** One hotkey that activates, hides all previous marks, and resets the color/width to defaults — useful for "start a fresh annotation pass." Becomes more interesting once keyboard shortcuts and disappearing drawings exist.
