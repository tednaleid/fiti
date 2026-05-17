# fiti Roadmap

Date: 2026-05-16
Status: Backlog. Items here are not committed scope. Each item becomes a brainstorm → design spec → implementation plan when it's time to land.

## What this is

A running list of things that move fiti from "POC + hardened" to "an app I actually want to use." Items are roughly grouped by impact, not committed to an order. Anything that's a separate independent spec gets a checkbox so we can tick it off as work begins.

## High-impact: visibility & interaction

### Menubar presence
- [ ] A menubar (status bar) item that shows fiti is running, with a menu to activate/deactivate, clear, quit, and toggle drawing visibility. Status icon should change between "active" (capturing input) and "idle" (click-through) so you can tell at a glance.
- [ ] Right now the only signal that fiti is running is the existence of strokes on screen or `pgrep`. There is no Dock icon (`LSUIElement = true`) and no menubar entry — the app is genuinely invisible until you draw.
- [ ] Needs a new AppKit adapter wrapping `NSStatusBar`; the port should be a `StatusItem` protocol in `Sources/Core/Ports/` so the menubar surface stays adapter-side.

### Toolbar
- [ ] A floating toolbar that appears when fiti is active (Cmd+Opt+Z), hides on Esc. Drag-positionable, remembers last position across launches.
- [ ] Reference: `../scratch/scratch/packages/web/src/ui/Toolbar.tsx`. Tools we want, distilled from there:
  - Tool picker: pen, eraser. (Shape tools come later.)
  - Color quick-picks (the eight from scratch are a fine starting point: black `#000000`, gray `#868e96`, red `#e03131`, orange `#f76707`, amber `#f59f00`, green `#2f9e44`, blue `#1971c2`, purple `#9c36b5`).
  - Custom color via native color picker, for anything not in the quick-pick row.
  - Width slider (1–20 with the rest of the proportional widths controlled by perfect-freehand's `size`).
  - Opacity / transparency slider — independent from color so red-50% is still legibly red.
  - Undo / redo / clear buttons.
  - Hide/show toggle (also bound to a hotkey — see next item).
- [ ] Open question: where to put the toolbar surface in the architecture. Probably a new `Sources/AppKit/Toolbar/` with its own `NSPanel`, and a `Toolbar` port in Core that the controller drives. The toolbar is *output* (Core tells it the current tool/color/width) and *input* (clicks become AppController calls). Two-way ports are awkward but not novel.

### Hide / show drawings
- [ ] Toolbar button + global hotkey to toggle stroke visibility without clearing. Strokes stay in the document; the renderer just stops drawing them. State should be a single boolean on `Editor` (or on `AppController`) so the existing snapshot listener can react.
- [ ] Useful pattern: present to an audience, hide the marks during the next live demo, show them again when you go back to the slide.
- [ ] Hotkey suggestion: `Cmd+Opt+H`. Same activate-style global monitor.

## High-quality: stroke rendering

### Perfect-freehand Swift port
- [ ] Real reason to do this: uniform-width `CGPath` strokes look amateurish; perfect-freehand gives you the tapered, velocity-aware curves that make annotations feel like ink instead of pixel art.
- [ ] Reference TS source: `node_modules/perfect-freehand` in scratch (MIT-licensed). The web app wraps it in `packages/web/src/canvas/strokePath.ts` with these options worth keeping:
  ```ts
  { smoothing: 0.5, thinning: 0.5, streamline: 0.5,
    simulatePressure: true,
    start: { taper: 0, cap: true },
    end:   { taper: 0, cap: true } }
  ```
- [ ] `simulatePressure: true` is the key for mouse input — synthesises pressure from velocity so even a non-stylus stroke tapers naturally. Stylus / trackpad real pressure overrides the sim. `Stroke.pressureEnabled` already exists in the model for this distinction.
- [ ] Implementation lives in `Sources/Core/` (it's pure math, no AppKit). The TS lib is ~600 lines of geometry; a direct port is feasible. Tests can compare outputs against checked-in TS-generated fixtures for byte-level confidence.
- [ ] The two-canvas split assumes uniform-width `addLine` paths. Perfect-freehand outputs a closed polygon to fill, not a path to stroke. The bake/blit pipeline still works — the `drawStroke` helper changes from "stroke a path" to "fill a polygon." Same call site, different internals.

## Distribution prereqs

### Real code signing
- [ ] Currently ad-hoc signed → `/tmp` rejection → `~/Applications/Fiti.app` workaround codified in justfile. None of that is acceptable for a shipped app.
- [ ] Path: enroll in Apple Developer Program (yearly fee), generate a Developer ID Application cert, configure xcodegen `signing` in `project.yml`, plumb the team identifier through `xcodebuild`. Result: stable cdhash across builds for users (per-developer team ID is the key macOS uses for accessibility grants when not ad-hoc), no more "toggle off and back on after each build."
- [ ] Once signed: notarization, then either drag-to-Applications DMG or Homebrew cask.

### Gate the dev HTTP surface behind a build config
- [ ] `DevHTTPServer` listens on `localhost:9876` whenever launched with `--dev`. That's fine in dev. For a shipped build, the `--dev` flag should be guarded by a build configuration (e.g. only compile `Sources/DevHTTP/` into Debug builds) so a release binary can't be driven by anything on `localhost`.
- [ ] Right now anyone with shell access to your Mac while fiti is running can `curl localhost:9876/pointer`. Acceptable for dev. Not acceptable for distribution.

## Lower priority

### Mark fading
- [ ] Strokes auto-fade after N seconds. Telestrator's signature feature; Ted has explicitly noted this is low-priority for fiti.
- [ ] Note for whenever it does land: it must be driven by `Editor.tick(now:)` calls (Clock port) so it remains testable with `FixedClock`. Do not drive from a UIKit/AppKit display link directly.

### Shape tools
- [ ] Rect, ellipse, arrow. Each becomes a `Stroke` variant with `kind: .rect | .ellipse | .arrow`. The model needs a discriminator; render path picks geometry by `kind`.

### Eraser as a UI tool
- [ ] Pointer in eraser mode finds the topmost stroke under it (hit-test) and calls `eraseStroke(id)`. The data path already works via HTTP; the UI is missing.
- [ ] Needs a hit-test helper. Hit-testing on perfect-freehand polygons is point-in-polygon; on `CGPath` strokes it's distance-from-path within `width/2 + tolerance`. Either way, lives in Core.

### Multi-display
- [ ] One window per display, all sharing the same `Editor`. Strokes get a `displayId` or get coordinates resolved to a global space — open design question.

### Persistence
- [ ] Strokes don't survive app restart. For "real" usage we probably want a session that persists, with a "clear" that's separate from "quit." Could be as simple as JSON-encoding `FitiDoc` to `~/Library/Application Support/fiti/session.json` on every change.

### Settings / preferences storage
- [ ] Color, width, opacity, toolbar position, hide-state — all need somewhere to live across launches. `UserDefaults` for prefs, separate from the document persistence above.

## Code-level cleanup (not features)

These are honest comments left in the code; not blockers, but worth a pass at some point.

- [ ] `Sources/DevHTTP/DevHTTPServer.swift:12` — `@unchecked Sendable` is a Swift-6 concession. Proper fix: make `DevHTTPServer` an actor, or replace the `start()` busy-wait with a semaphore signaled from the NWListener state handler. Resolves the `boundPort` data race in the same step.
- [ ] `docs/architecture.md` two-canvas split — bake uses points, not backing-store pixels. On retina the committed cache is half-res. Multiply by `window.backingScaleFactor` in the bake and use a CTM to compensate. Becomes visible when perfect-freehand lands and stroke edges have real detail to preserve.

## Out of scope (deliberately not on this list)

These are punted, not forgotten, but I'm not planning to revisit them soon:

- Pen / touch / iPad input
- Automerge / CRDT sync (the doc shape is ready; nothing else is)
- Cloud sync, accounts, sharing
- iOS / iPadOS port
- A web companion

## Open questions worth answering before picking anything up

1. **Where should the toolbar live in process?** Same window, separate panel, separate window-group? Affects how hide/show interacts with capture state.
2. **Should the global hide-toggle work even when fiti is not capturing input?** I think yes (it's separate from activation), but that means the global hotkey monitor needs a second binding.
3. **What's the upgrade story when the document shape changes?** Persistence implies versioned doc; we should pick that scheme before writing the first version to disk.
4. **Do we want a "presentation mode" preset?** One hotkey that activates, hides all previous marks, and resets the color/width to defaults — useful for "start a fresh annotation pass."
