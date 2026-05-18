# fiti Disappearing Drawings (Auto-Fade) Design

Date: 2026-05-18
Status: Design — not yet implemented.

## Goal

Opt-in mode in which strokes auto-remove themselves after a window of inactivity. Default window is 10 seconds; the last 2 seconds render as an opacity ramp so the user gets a visual warning before strokes disappear. Any pointer activity within the window keeps everything alive. When the window expires, every visible stroke is removed in a single undoable operation — `Cmd+Z` resurrects them all at full opacity and restarts the window.

## Non-goals

- User-configurable duration. v1 ships with a hardcoded 10s + 2s ramp. A Preferences slider is a follow-up if real use shows the defaults feel wrong.
- Per-stroke independent timers. The window is global — all currently-drawn strokes expire together.
- Keyboard shortcut for the toggle. That ships with the broader keyboard-driven tool use item (`f` for auto-fade is reserved).
- Persisting in-flight fade state across app restart. The toggle state persists; the timer always starts fresh.
- Replacing the existing `Editor.clear()` path. The fade-out reuses `clear()` for the actual stroke removal; no new editor method.

## Architecture

Timer and fade state live on `AppController`. `Editor` stays purely a document-mutation surface — it does not gain `tick()` or any time-based logic. Rendering picks up opacity changes via a separate publisher, not through `RenderFrame` (which stays focused on document snapshots).

### New port: `FadeTicker`

Lives at `Sources/Core/Ports/FadeTicker.swift`. Pure Swift, no AppKit.

```swift
@MainActor
public protocol FadeTicker: AnyObject {
    var onTick: ((Double) -> Void)? { get set }
    func start()
    func stop()
}
```

`onTick` callback receives the current time (Double seconds, same units as `Clock.now()`). Adapters fire at whatever cadence they choose (the AppKit adapter targets 30 Hz). `start()` is idempotent — starting an already-running ticker is a no-op. Same for `stop()`.

### AppKit adapter: `TimerFadeTicker`

`Sources/AppKit/TimerFadeTicker.swift`. Wraps `Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true)`. Holds an `unowned` reference to a `Clock` so it can pass `clock.now()` into `onTick`. Not unit-tested directly; the recording double is used in `AppController` tests.

### `AppController` fade state

New fields:

```swift
public private(set) var autoFadeEnabled: Bool = false {
    didSet {
        if oldValue != autoFadeEnabled { onAutoFadeEnabledChanged?(autoFadeEnabled) }
        autoFadeStateChanged()
    }
}
public var onAutoFadeEnabledChanged: ((Bool) -> Void)?

public private(set) var fadeOpacity: Double = 1.0 {
    didSet {
        if oldValue != fadeOpacity { onFadeOpacityChanged?(fadeOpacity) }
    }
}
public var onFadeOpacityChanged: ((Double) -> Void)?

private var lastInputAt: Double?
private let ticker: FadeTicker
private let clock: Clock
private static let fadeWindowSeconds: Double = 10.0
private static let fadeRampSeconds: Double = 2.0
```

`init` gains `ticker: FadeTicker` and `clock: Clock` parameters. Wires `ticker.onTick = { [weak self] now in self?.handleTick(now) }`.

`autoFadeStateChanged()` is a private helper that handles toggle ON/OFF side effects:

- ON: `lastInputAt = clock.now()`; `ticker.start()`. (If there are no strokes yet, the ticker still runs — `handleTick` no-ops when the doc is empty.)
- OFF: `ticker.stop()`; `fadeOpacity = 1.0`. Strokes are left in whatever state they were rendered at — the next render uses opacity 1.0.

### Renderer wiring

`CanvasView` gains a `globalOpacity: Double` property (default 1.0) and a `setGlobalOpacity(_:)` method that updates the property and triggers `needsDisplay = true`. `main.swift` wires the publisher: `controller.onFadeOpacityChanged = { [weak self] in self?.canvas.setGlobalOpacity($0) }`. When `CanvasView` draws strokes from a `RenderFrame`, it multiplies each stroke's alpha by `globalOpacity`. `RenderFrame` itself is untouched — opacity is presentation state, not document state. Same wiring pattern `CursorRenderer` already uses to receive `CursorSpec` updates.

### Editor mutation

When the fade window expires, AppController calls `editor.clear()`. Existing semantics already match what we need: every stroke is removed, a single `restoreStrokes(entries:)` inverse op is pushed onto the undo stack, and a subsequent `editor.undo()` brings them back at their original z-order. No new editor method.

### Persistence

`UserDefaults` key `fiti.autoFade` (Bool). Default `false`. `ToolbarController` reads it at init and writes it on every toggle. AppController itself is unaware of persistence — it just exposes the property.

## State machine

```
                   ticker.onTick(now)
                       ↓
              autoFadeEnabled == false?  →  no-op
                       ↓ no
              mode == .activeDrawing?    →  no-op  (mid-stroke guard)
                       ↓ no
              doc.strokes.isEmpty?       →  lastInputAt = nil
                                            fadeOpacity = 1.0
                                            no-op
                       ↓ no
              lastInputAt == nil?        →  lastInputAt = now    (re-arm after undo)
                                            fadeOpacity = 1.0
                                            no-op
                       ↓ no
              age = now - lastInputAt
                       ↓
              age < 8.0   → fadeOpacity = 1.0
              8.0 ≤ age < 10.0 → fadeOpacity = 1.0 - (age - 8.0) / 2.0
              age ≥ 10.0  → editor.clear()
                            lastInputAt = nil
                            fadeOpacity = 1.0
```

Fade is linear over the 2s ramp. Strokes go from solid (1.0) to invisible (0.0); at the moment they hit invisible, the `clear()` fires and they're removed from the doc entirely. The next paint draws nothing.

### Reset triggers (set `lastInputAt = clock.now()`)

- Every `pointerDown` / `pointerMoved` / `pointerUp` — keeps the timer fresh during normal drawing.
- `autoFadeEnabled` toggled ON (start the window from now).
- The "lastInputAt == nil but strokes non-empty" branch in `handleTick` (above). This is the re-arm path that fires on the first tick after `Cmd+Z` restores fade-expired strokes. No subscription to editor mutations is needed; the next tick (~33 ms later) handles it. Between the undo and that tick, `fadeOpacity` stays at its previous value (1.0 from the expiration cycle), so strokes render at full opacity immediately on the post-undo frame.

### Mid-stroke guard

`handleTick` no-ops when `mode == .activeDrawing`. This is belt-and-suspenders defense alongside the pointer-event resets: pointer events keep `lastInputAt` fresh during normal drawing, but if the user pauses mid-stroke for 10s without moving, the mode guard still prevents `clear()` from wiping the in-progress stroke. Without the guard, an unusual hold-still gesture could destroy an active line.

### Toggle OFF mid-fade

If the user disables auto-fade while strokes are in the 8s-10s opacity ramp:

1. `ticker.stop()`
2. `fadeOpacity = 1.0` (which publishes `onFadeOpacityChanged(1.0)`)
3. CanvasView's next render uses 1.0; strokes snap back to full opacity.

Per the roadmap: "freezes whatever's still visible at full opacity." Strokes that already fully expired (had been removed via `editor.clear()`) are not magically restored — they're on the undo stack, and `Cmd+Z` is the explicit recovery path.

### Undo after expiration

When the user presses `Cmd+Z` after the fade window cleared all strokes:

1. `editor.undo()` runs the `restoreStrokes` inverse op. Doc goes from `strokes.isEmpty == true` to populated.
2. AppController's `fadeOpacity` is already 1.0 from the expiration cycle, so the next paint draws the restored strokes at full opacity. No flicker.
3. On the next ticker fire (~33 ms after undo), `handleTick` sees `lastInputAt == nil && !doc.strokes.isEmpty` and re-arms: `lastInputAt = now`. The 10s window starts fresh from there.

AppController does NOT need to subscribe to editor mutations for this — the tick-based re-arm handles it without any cross-coupling. If the user manages to wait the entire 10s window between undo and the very next tick, the worst case is the timer effectively starts a frame late. The behavioral effect is negligible.

## UI surface

Toolbar gains one new button between the width/opacity sliders and the existing hide button:

- Glyph: SF Symbol `timer`. Filled when `autoFadeEnabled == true`, outline when `false`. (`timer` has both a filled and outline variant in macOS 14+.)
- Accessibility label: "Auto-fade drawings".
- Tag identifier so tests can grab it.
- Persisted in `UserDefaults` under `fiti.autoFade`.

No Preferences row, no slider, no keyboard shortcut in v1.

## Testing strategy

### AppController tests (Core)

Eight cases drive every branch of the state machine. All use `RecordingFadeTicker` (a synchronous test double with a public `tick(at: Double)` method).

1. **Initial state.** `autoFadeEnabled == false`, `fadeOpacity == 1.0`, ticker is stopped.
2. **Toggle on with no strokes.** Ticker starts; subsequent `tick(at: 100)` calls don't fire `editor.clear()`; `fadeOpacity` stays 1.0.
3. **Toggle on, draw, tick mid-window.** Draw a stroke ending at t=0 (sets `lastInputAt=0`); `tick(at: 7)` → `fadeOpacity == 1.0` (still in solid phase).
4. **Tick mid-ramp.** Same setup; `tick(at: 8.5)` → `fadeOpacity == 0.75` (within ε).
5. **Tick at expiration.** `tick(at: 10)` → `editor.clear()` was called once; `lastInputAt == nil`; `fadeOpacity == 1.0`.
6. **Mid-stroke guard.** `pointerDown` (mode → .activeDrawing) with no `pointerMoved` for 10s; `tick(at: 11)` → no `editor.clear()` call; in-progress stroke survives.
7. **Toggle off mid-ramp.** Setup: stroke at t=0, autoFade on, `tick(at: 8.5)` → opacity 0.75. Toggle off → `fadeOpacity` snaps to 1.0; ticker stopped; subsequent ticks have no effect.
8. **Undo after expiration.** Setup: stroke at t=0, `tick(at: 10)` fires `clear()`. Call `editor.undo()`. AppController's editor-subscription detects restored strokes; `lastInputAt` becomes the current clock; `fadeOpacity == 1.0`. Verify by ticking again at a small delta after the undo and confirming opacity stays 1.0.

### ToolbarController tests (AppKit)

- New button exists with the `timer` glyph (filled vs outline switches with state).
- Clicking the button flips `controller.autoFadeEnabled`.
- `UserDefaults` persistence: `defaults.bool(forKey: "fiti.autoFade")` reflects the latest toggle; `init` reads it back.
- External write to `autoFadeEnabled` (via HTTP) updates the button glyph through the subscription.

### CanvasView tests (AppKit)

One new test: after `controller.onFadeOpacityChanged(0.5)`, rendering produces a bitmap whose sampled stroke alpha is approximately half of what it was at opacity 1.0. Uses the same render-to-NSBitmapImageRep harness the existing `CanvasView*` tests already use.

### Recording double

`Tests/CoreTests/Doubles/RecordingFadeTicker.swift`:

```swift
@MainActor
public final class RecordingFadeTicker: FadeTicker {
    public var onTick: ((Double) -> Void)?
    public private(set) var isRunning = false
    public init() {}
    public func start() { isRunning = true }
    public func stop()  { isRunning = false }
    /// Test helper: fire onTick at the given clock time. No-op if not started.
    public func tick(at time: Double) {
        guard isRunning else { return }
        onTick?(time)
    }
}
```

### What's NOT tested

- `TimerFadeTicker` itself — wraps `Timer.scheduledTimer`, no logic worth covering.
- Real-time fade animation smoothness — visual, smoke-tested manually.

## Wiring notes

`AppController.init` gains `ticker: FadeTicker, clock: Clock` parameters. `main.swift` passes a `TimerFadeTicker` and a shared `SystemClock`; tests pass `RecordingFadeTicker` and `VirtualClock`. Because every existing test that constructs an `AppController` will see the new parameters, the constructor change ships atomically with the wiring (one commit) the same way the `StationaryDetector` parameter did for hold-to-straighten.

`ToolbarController` is the natural owner of the new toggle. Its existing `UserDefaults` pattern (`fiti.color.*`, `fiti.width`) extends to `fiti.autoFade`.

`main.swift` adds two new closures alongside the existing `controller.onCursorChanged` wire-up:

```swift
controller.onFadeOpacityChanged = { [weak self] opacity in self?.canvas.setGlobalOpacity(opacity) }
// (toolbar takes onAutoFadeEnabledChanged via its own init pattern, same as it handles the other toolbar state today)
```

## Acceptance criteria

- [ ] Auto-fade toggle button exists in the toolbar with `timer` SF Symbol (filled/outline reflects state).
- [ ] Toggling on starts the 10s window. Drawing within the window resets the timer (any number of times).
- [ ] Strokes stay full opacity for the first 8s, ramp linearly 1.0 → 0.0 over the next 2s, then disappear.
- [ ] On expiration, a single `Cmd+Z` brings every faded stroke back at full opacity and restarts the 10s window.
- [ ] Toggling off mid-fade snaps strokes back to full opacity. Already-expired strokes are not restored (use undo).
- [ ] Mid-stroke pause of any length does not trigger expiration of the in-progress stroke.
- [ ] Toggle state persists across app launches via `UserDefaults`.
- [ ] `Sources/Core/` has no AppKit/CoreGraphics/SwiftUI/Network imports (`just lint` enforces).
- [ ] All test suites stay under the 5-second budget (`just check`).

## Open questions / future

- Should the auto-fade toggle have a global hotkey of its own (Opt+H-style), or wait for the keyboard-driven tool use item? Leaning the latter — bundling all in-focus shortcuts in one pass.
- If the user has auto-fade on and disables fiti via Opt+F (click-through), should the timer keep running? Current design: yes (it's not gated on activation state). Reasonable; revisit if it confuses users.
- "Presentation mode" hotkey from the open questions in the roadmap becomes more interesting once this lands.
