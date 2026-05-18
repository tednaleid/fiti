# fiti Disappearing Drawings (Auto-Fade) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an opt-in auto-fade mode: strokes ramp out over the last 2 s of a 10 s inactivity window and are removed in one undoable op; `Cmd+Z` restores them at full opacity and restarts the window.

**Architecture:** New `FadeTicker` port in `Sources/Core/Ports/` keeps Foundation pure. `AppController` owns the state machine (`autoFadeEnabled`, `lastInputAt`, `fadeOpacity`); `Editor` is untouched — fade expiration reuses the existing `clear()` path so undo restores via `restoreStrokes`. `CanvasView` gains a `globalOpacity` property updated by `main.swift` wiring `controller.onFadeOpacityChanged`. Toolbar gets one new toggle button persisted in `UserDefaults`.

**Tech Stack:** Swift 6, AppKit, Swift Testing, no SwiftUI, no new SPM deps.

**Source of truth:** `docs/specs/2026-05-18-fiti-disappearing-drawings-design.md`.

---

## File map

| File | Responsibility | Status |
| --- | --- | --- |
| `Sources/Core/Ports/FadeTicker.swift` | `FadeTicker` protocol | create (Task 1) |
| `Tests/CoreTests/Doubles/RecordingFadeTicker.swift` | Test double | create (Task 1) |
| `Tests/CoreTests/FadeTickerTests.swift` | 4 tests for the recording double | create (Task 1) |
| `Sources/AppKit/TimerFadeTicker.swift` | Real `Timer`-based adapter | create (Task 2) |
| `Sources/Core/Control/AppController.swift` | Add `autoFadeEnabled`, `fadeOpacity`, `lastInputAt`, ticker + clock params, handleTick | modify (Tasks 3-4) |
| `Tests/CoreTests/AppControllerTests/*.swift` | Update existing `make()` helpers; add fade tests | modify (Tasks 3-4) |
| `Tests/AppKitTests/MenubarControllerTests.swift` | Update `make()` helper for new ctor signature | modify (Task 3) |
| `Tests/AppKitTests/ToolbarControllerTests.swift` | Update fixtures; add toggle button tests | modify (Tasks 3, 6) |
| `Sources/App/main.swift` | Construct `TimerFadeTicker`; pass `clock` + `ticker` to `AppController`; wire `onFadeOpacityChanged` | modify (Tasks 3, 6) |
| `Sources/AppKit/CanvasView.swift` | `globalOpacity: Double` + `setGlobalOpacity(_:)` + alpha multiply on draw | modify (Task 5) |
| `Tests/AppKitTests/CanvasView*` | New rendering test for opacity multiply | modify (Task 5) |
| `Sources/AppKit/ToolbarController.swift` | New toggle button, persistence, sync with controller | modify (Task 6) |

---

### Task 1: `FadeTicker` port + recording double

Pure additions; no signature changes. Trivial test pass for the double to keep the TDD slice green.

**Files:**
- Create: `Sources/Core/Ports/FadeTicker.swift`
- Create: `Tests/CoreTests/Doubles/RecordingFadeTicker.swift`
- Create: `Tests/CoreTests/FadeTickerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/FadeTickerTests.swift`:

```swift
// ABOUTME: Tests for the RecordingFadeTicker double — covers start/stop bookkeeping
// ABOUTME: and the tick(at:) helper that drives AppController fade state in unit tests.

import Testing

@Suite("RecordingFadeTicker")
@MainActor
struct FadeTickerTests {
    @Test("initial state is stopped")
    func initialState() {
        let ticker = RecordingFadeTicker()
        #expect(ticker.isRunning == false)
    }

    @Test("start() flips isRunning to true")
    func startRuns() {
        let ticker = RecordingFadeTicker()
        ticker.start()
        #expect(ticker.isRunning == true)
    }

    @Test("stop() flips isRunning back to false")
    func stopStops() {
        let ticker = RecordingFadeTicker()
        ticker.start()
        ticker.stop()
        #expect(ticker.isRunning == false)
    }

    @Test("tick(at:) calls onTick when running")
    func tickFiresWhenRunning() {
        let ticker = RecordingFadeTicker()
        var received: Double?
        ticker.onTick = { received = $0 }
        ticker.start()
        ticker.tick(at: 42.5)
        #expect(received == 42.5)
    }

    @Test("tick(at:) is a no-op when stopped")
    func tickNoOpsWhenStopped() {
        let ticker = RecordingFadeTicker()
        var fireCount = 0
        ticker.onTick = { _ in fireCount += 1 }
        ticker.tick(at: 1)
        #expect(fireCount == 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test`
Expected: compile error — `RecordingFadeTicker`, `FadeTicker` not found.

- [ ] **Step 3: Create the port**

Create `Sources/Core/Ports/FadeTicker.swift`:

```swift
// ABOUTME: Port for a periodic tick that drives auto-fade. Real adapter wraps
// ABOUTME: Timer.scheduledTimer; tests use RecordingFadeTicker with tick(at:).

import Foundation

@MainActor
public protocol FadeTicker: AnyObject {
    /// Fired on each tick with the current clock time (seconds).
    var onTick: ((Double) -> Void)? { get set }

    /// Begin firing onTick on the adapter's chosen cadence. Idempotent.
    func start()

    /// Stop firing. Idempotent.
    func stop()
}
```

- [ ] **Step 4: Create the recording double**

Create `Tests/CoreTests/Doubles/RecordingFadeTicker.swift`:

```swift
// ABOUTME: Synchronous FadeTicker for tests. tick(at:) simulates a real tick;
// ABOUTME: isRunning lets tests assert on start/stop bookkeeping.

import Foundation

@MainActor
public final class RecordingFadeTicker: FadeTicker {
    public var onTick: ((Double) -> Void)?
    public private(set) var isRunning = false
    public init() {}
    public func start() { isRunning = true }
    public func stop()  { isRunning = false }
    /// Test helper: simulate a tick at the given time. No-op if not started.
    public func tick(at time: Double) {
        guard isRunning else { return }
        onTick?(time)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `just test`
Expected: five new tests in `FadeTickerTests` pass; `fiti-unit` count grows by 5.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Ports/FadeTicker.swift \
        Tests/CoreTests/Doubles/RecordingFadeTicker.swift \
        Tests/CoreTests/FadeTickerTests.swift
git commit -m "$(cat <<'EOF'
Core: FadeTicker port + RecordingFadeTicker double

Port keeps the tick driver swappable so AppController's fade state
machine is testable with VirtualClock. Real Timer-based adapter
arrives next; AppController consumption lands after that.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `TimerFadeTicker` AppKit adapter

Real `Timer.scheduledTimer`-backed adapter. Not unit-tested — the wrap is too trivial to be worth a flaky timing test. Smoke is the manual acceptance in Task 6.

**Files:**
- Create: `Sources/AppKit/TimerFadeTicker.swift`

- [ ] **Step 1: Create the adapter**

Create `Sources/AppKit/TimerFadeTicker.swift`:

```swift
// ABOUTME: Real FadeTicker adapter. Fires at 30 Hz via Timer.scheduledTimer,
// ABOUTME: passing clock.now() into onTick. Smoke-tested through real app use.

import AppKit
import Foundation

@MainActor
public final class TimerFadeTicker: FadeTicker {
    public var onTick: ((Double) -> Void)?
    private let clock: Clock
    private var timer: Timer?

    public init(clock: Clock) {
        self.clock = clock
    }

    public func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            // Hop to MainActor — Timer's callback is not actor-isolated.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.onTick?(self.clock.now())
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    isolated deinit {
        timer?.invalidate()
    }
}
```

- [ ] **Step 2: Verify the build still passes**

Run: `just build`
Expected: build succeeds. No new tests yet.

- [ ] **Step 3: Confirm lint is clean**

Run: `just lint`
Expected: 0 violations; `Sources/Core/` import-discipline check still passes.

- [ ] **Step 4: Commit**

```bash
git add Sources/AppKit/TimerFadeTicker.swift
git commit -m "$(cat <<'EOF'
AppKit: TimerFadeTicker — 30 Hz Timer-backed FadeTicker adapter

Wraps Timer.scheduledTimer; reads clock.now() per tick. MainActor hop
inside the closure because Timer's callback is not actor-isolated.
Not unit-tested — covered by manual smoke later.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `AppController` gains `ticker` + `clock`; adds `autoFadeEnabled` / `fadeOpacity`; updates every call site (atomic)

The constructor signature change breaks every test that builds an `AppController` and every call in `main.swift`. Bundle into one commit. The fade *state machine* (handleTick, mid-stroke guard, expiration) is NOT in this task — Task 4 adds that. This task only adds:

- New `clock`, `ticker` stored properties.
- New `autoFadeEnabled` (publishes `onAutoFadeEnabledChanged`) — toggling starts/stops the ticker and resets `lastInputAt` / `fadeOpacity`.
- New `fadeOpacity` (publishes `onFadeOpacityChanged`) — default 1.0.
- Private `lastInputAt: Double?`.
- Constructor wiring of `ticker.onTick` to a stub `handleTick` that no-ops for now (Task 4 fills it in).

**Files:**
- Modify: `Sources/Core/Control/AppController.swift`
- Modify: every file under `Tests/CoreTests/AppControllerTests/` that calls `AppController(editor:, window:, detector:)`.
- Modify: `Tests/AppKitTests/MenubarControllerTests.swift`, `Tests/AppKitTests/ToolbarControllerTests.swift`, and any other `Tests/AppKitTests/` file that constructs `AppController`.
- Modify: `Tests/DevHTTPTests/` files that construct `AppController` (if any).
- Modify: `Sources/App/main.swift`.

- [ ] **Step 1: Inventory call sites**

Run: `grep -rn "AppController(editor:" Tests/ Sources/`
Expected: a list of every constructor call. Note them — each gets the new params added.

- [ ] **Step 2: Write the new fade-property tests**

Create `Tests/CoreTests/AppControllerTests/FadeStateTests.swift`:

```swift
// ABOUTME: Tests for AppController fade properties — toggle on/off, ticker
// ABOUTME: start/stop bookkeeping, opacity reset behavior. Tick state machine
// ABOUTME: behavior lives in FadeTickTests.

import Testing

@Suite("AppController fade state")
@MainActor
struct FadeStateTests {
    // swiftlint:disable:next large_tuple
    private func make() -> (AppController, VirtualClock, RecordingFadeTicker, OpacityRecorder) {
        let clock = VirtualClock()
        let ticker = RecordingFadeTicker()
        let window = RecordingWindow()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(
            editor: editor,
            window: window,
            detector: RecordingStationaryDetector(),
            clock: clock,
            ticker: ticker
        )
        let rec = OpacityRecorder()
        controller.onFadeOpacityChanged = { rec.opacities.append($0) }
        return (controller, clock, ticker, rec)
    }

    private final class OpacityRecorder {
        var opacities: [Double] = []
    }

    @Test("initial state: autoFade off, opacity 1.0, ticker stopped")
    func initialState() {
        let (c, _, ticker, _) = make()
        #expect(c.autoFadeEnabled == false)
        #expect(c.fadeOpacity == 1.0)
        #expect(ticker.isRunning == false)
    }

    @Test("toggling autoFadeEnabled on starts the ticker")
    func toggleOnStartsTicker() {
        let (c, _, ticker, _) = make()
        c.autoFadeEnabled = true
        #expect(ticker.isRunning == true)
    }

    @Test("toggling autoFadeEnabled off stops the ticker and resets opacity to 1.0")
    func toggleOffStopsAndResets() {
        let (c, _, ticker, _) = make()
        c.autoFadeEnabled = true
        c.fadeOpacity = 0.5
        c.autoFadeEnabled = false
        #expect(ticker.isRunning == false)
        #expect(c.fadeOpacity == 1.0)
    }

    @Test("onAutoFadeEnabledChanged fires on each value change")
    func autoFadeChangePublisher() {
        let (c, _, _, _) = make()
        var values: [Bool] = []
        c.onAutoFadeEnabledChanged = { values.append($0) }
        c.autoFadeEnabled = true
        c.autoFadeEnabled = false
        #expect(values == [true, false])
    }

    @Test("idempotent autoFade set does not re-fire the publisher")
    func idempotentAutoFadeSet() {
        let (c, _, _, _) = make()
        var count = 0
        c.onAutoFadeEnabledChanged = { _ in count += 1 }
        c.autoFadeEnabled = true
        c.autoFadeEnabled = true
        #expect(count == 1)
    }

    @Test("onFadeOpacityChanged fires when opacity changes")
    func opacityPublisher() {
        let (c, _, _, rec) = make()
        c.fadeOpacity = 0.75
        #expect(rec.opacities.last == 0.75)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `just test`
Expected: compile errors. `AppController.init` doesn't accept `clock:` or `ticker:`; `autoFadeEnabled`, `fadeOpacity`, `onFadeOpacityChanged`, `onAutoFadeEnabledChanged` not found.

- [ ] **Step 4: Update `AppController.swift`**

Modify `Sources/Core/Control/AppController.swift`. Add the four new stored properties, the two publishers, and update the init. The handleTick body stays empty/no-op for this task — Task 4 fills it in. Final relevant additions:

```swift
public final class AppController {
    // ... existing properties ...

    private let clock: Clock
    private let ticker: FadeTicker

    public var onAutoFadeEnabledChanged: ((Bool) -> Void)?
    public var onFadeOpacityChanged: ((Double) -> Void)?

    public var autoFadeEnabled: Bool = false {
        didSet {
            guard oldValue != autoFadeEnabled else { return }
            onAutoFadeEnabledChanged?(autoFadeEnabled)
            autoFadeStateChanged()
        }
    }

    public var fadeOpacity: Double = 1.0 {
        didSet {
            if oldValue != fadeOpacity { onFadeOpacityChanged?(fadeOpacity) }
        }
    }

    private var lastInputAt: Double?

    public init(
        editor: Editor,
        window: WindowControl,
        detector: StationaryDetector,
        clock: Clock,
        ticker: FadeTicker
    ) {
        self.editor = editor
        self.window = window
        self.detector = detector
        self.clock = clock
        self.ticker = ticker
        detector.onStationary = { [weak self] in self?.handleStationary() }
        ticker.onTick = { [weak self] now in self?.handleTick(now) }
    }

    private func autoFadeStateChanged() {
        if autoFadeEnabled {
            lastInputAt = clock.now()
            ticker.start()
        } else {
            ticker.stop()
            fadeOpacity = 1.0
        }
    }

    private func handleTick(_ now: Double) {
        // Task 4 fills this in. For now: no-op so the ticker doesn't crash.
    }

    // ... existing methods ...
}
```

- [ ] **Step 5: Update every existing AppController call site to pass the new params**

For every test fixture, change patterns like:

```swift
let controller = AppController(editor: editor, window: window, detector: RecordingStationaryDetector())
```

to:

```swift
let controller = AppController(
    editor: editor,
    window: window,
    detector: RecordingStationaryDetector(),
    clock: VirtualClock(),
    ticker: RecordingFadeTicker()
)
```

If a test fixture already constructs a `VirtualClock` for an `Editor`, reuse the same clock here so all time references in the test agree. If a fixture uses a separate clock for the editor (e.g., a `SeededIdGenerator`), it's fine to construct a fresh `VirtualClock()` for AppController — the existing tests don't time-couple Editor and AppController.

Files known to construct `AppController(editor:, window:, detector:)` (verify with the grep from Step 1; this list is not exhaustive):
- `Tests/CoreTests/AppControllerTests/ActivationTests.swift`
- `Tests/CoreTests/AppControllerTests/CursorEmissionTests.swift`
- `Tests/AppKitTests/MenubarControllerTests.swift`
- `Tests/AppKitTests/ToolbarControllerTests.swift`

- [ ] **Step 6: Update `Sources/App/main.swift`**

In `FitiAppDelegate.applicationDidFinishLaunching`, replace:

```swift
editor = Editor(clock: SystemClock(), ids: UUIDStrokeIds())
// ...
controller = AppController(editor: editor, window: window, detector: TaskStationaryDetector())
```

with:

```swift
let clock = SystemClock()
editor = Editor(clock: clock, ids: UUIDStrokeIds())
// ...
let ticker = TimerFadeTicker(clock: clock)
controller = AppController(
    editor: editor,
    window: window,
    detector: TaskStationaryDetector(),
    clock: clock,
    ticker: ticker
)
```

Promote `let clock = SystemClock()` to a local in `applicationDidFinishLaunching` so editor + ticker + controller share one. Don't introduce a stored property on the delegate for it — no other code needs it.

- [ ] **Step 7: Run the full check**

Run: `just check`
Expected:
- All previously-passing tests still pass after the call-site updates.
- Six new `FadeStateTests` pass.
- `fiti-unit` count grows by 6; `fiti-integration` count grows by 6 (it includes `Tests/CoreTests`).
- Lint clean, build succeeds.

- [ ] **Step 8: Commit**

```bash
git add Sources/Core/Control/AppController.swift \
        Sources/App/main.swift \
        Tests/CoreTests/AppControllerTests/FadeStateTests.swift \
        Tests/CoreTests/AppControllerTests/ActivationTests.swift \
        Tests/CoreTests/AppControllerTests/CursorEmissionTests.swift \
        Tests/AppKitTests/MenubarControllerTests.swift \
        Tests/AppKitTests/ToolbarControllerTests.swift
# Plus any other test files the Step 1 grep surfaced.
git commit -m "$(cat <<'EOF'
Core + App: AppController gains FadeTicker + Clock, autoFade properties

Adds autoFadeEnabled (with publisher), fadeOpacity (with publisher),
lastInputAt, and ticker.onTick wiring. Toggle on starts the ticker
and arms the window; toggle off stops the ticker and resets opacity.
The handleTick body is stubbed — the actual state machine lands next.
Mechanical updates to every AppController call site for the new
clock/ticker params.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `handleTick` state machine + pointer-event reset triggers

Now fill in `handleTick` per the state-machine diagram in the design. Add `lastInputAt = clock.now()` to `pointerDown` / `pointerMoved` / `pointerUp`.

**Files:**
- Modify: `Sources/Core/Control/AppController.swift`
- Create: `Tests/CoreTests/AppControllerTests/FadeTickTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/AppControllerTests/FadeTickTests.swift`:

```swift
// ABOUTME: Tests for AppController fade state machine — handleTick branches
// ABOUTME: (solid / ramp / expiration / re-arm) and pointer-event reset triggers.

import Testing

@Suite("AppController fade tick state machine")
@MainActor
struct FadeTickTests {
    // swiftlint:disable:next large_tuple
    private func make() -> (AppController, VirtualClock, RecordingFadeTicker, Editor) {
        let clock = VirtualClock()
        let ticker = RecordingFadeTicker()
        let window = RecordingWindow()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(
            editor: editor,
            window: window,
            detector: RecordingStationaryDetector(),
            clock: clock,
            ticker: ticker
        )
        return (controller, clock, ticker, editor)
    }

    /// Activate, draw a one-point stroke, end it. Leaves lastInputAt = clock.now()
    /// from the pointerUp; mode = .activeIdle.
    private func drawOneStroke(_ controller: AppController) {
        controller.activate()
        controller.pointerDown(StrokePoint(x: 0, y: 0))
        controller.pointerUp()
    }

    @Test("tick when autoFade is off is a no-op")
    func tickOffNoOps() {
        let (c, clock, ticker, editor) = make()
        drawOneStroke(c)
        ticker.start()  // verify the autoFade guard catches even an externally-started ticker
        clock.advance(by: 1000)
        ticker.tick(at: clock.now())
        #expect(editor.doc.strokes.isEmpty == false)
        #expect(c.fadeOpacity == 1.0)
    }

    @Test("tick at age 7 keeps opacity 1.0")
    func tickInSolidPhase() {
        let (c, clock, ticker, _) = make()
        drawOneStroke(c)         // pointerUp at t=0; lastInputAt = 0
        c.autoFadeEnabled = true // re-arms lastInputAt to clock.now() = 0; ticker starts
        clock.advance(by: 7)
        ticker.tick(at: clock.now())
        #expect(c.fadeOpacity == 1.0)
    }

    @Test("tick at age 8.5 sets opacity to 0.75 (within ramp)")
    func tickInRamp() {
        let (c, clock, ticker, _) = make()
        drawOneStroke(c)
        c.autoFadeEnabled = true
        clock.advance(by: 8.5)
        ticker.tick(at: clock.now())
        #expect(abs(c.fadeOpacity - 0.75) < 0.0001)
    }

    @Test("tick at age 10 clears strokes and resets state")
    func tickExpires() {
        let (c, clock, ticker, editor) = make()
        drawOneStroke(c)
        c.autoFadeEnabled = true
        clock.advance(by: 10)
        ticker.tick(at: clock.now())
        #expect(editor.doc.strokes.isEmpty == true)
        #expect(c.fadeOpacity == 1.0)
    }

    @Test("tick on empty doc stays at opacity 1.0")
    func tickEmptyDoc() {
        let (c, clock, ticker, _) = make()
        c.autoFadeEnabled = true
        clock.advance(by: 100)
        ticker.tick(at: clock.now())
        #expect(c.fadeOpacity == 1.0)
    }

    @Test("tick re-arms when lastInputAt is nil but strokes exist (post-undo)")
    func tickReArmsAfterUndo() {
        let (c, clock, ticker, editor) = make()
        drawOneStroke(c)
        c.autoFadeEnabled = true
        clock.advance(by: 10)
        ticker.tick(at: clock.now())
        #expect(editor.doc.strokes.isEmpty == true)
        _ = editor.undo()
        clock.advance(by: 0.05)
        ticker.tick(at: clock.now())  // re-arms lastInputAt to now
        #expect(c.fadeOpacity == 1.0)
        clock.advance(by: 1.0)         // 1s past the re-arm — still solid phase
        ticker.tick(at: clock.now())
        #expect(c.fadeOpacity == 1.0)
    }

    @Test("mid-stroke (activeDrawing) tick does NOT expire")
    func midStrokeGuard() {
        let (c, clock, ticker, editor) = make()
        c.autoFadeEnabled = true
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))  // mode = .activeDrawing
        clock.advance(by: 15)
        ticker.tick(at: clock.now())
        #expect(editor.doc.strokes.isEmpty == false)
    }

    @Test("pointerDown sets lastInputAt — subsequent expiration honors it")
    func pointerDownResets() {
        let (c, clock, ticker, editor) = make()
        drawOneStroke(c)         // initial stroke ended at t=0
        c.autoFadeEnabled = true
        clock.advance(by: 5)
        c.activate()
        c.pointerDown(StrokePoint(x: 1, y: 1))  // lastInputAt = 5; mode now activeDrawing
        clock.advance(by: 7)                     // total elapsed 12 from t=0; mid-stroke guard active
        ticker.tick(at: clock.now())
        #expect(editor.doc.strokes.isEmpty == false)  // guard prevents expire
        #expect(c.mode == .activeDrawing)
    }

    @Test("pointerMoved keeps the timer fresh through a long stroke")
    func pointerMovedResets() {
        let (c, clock, ticker, editor) = make()
        c.autoFadeEnabled = true
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        clock.advance(by: 9)
        c.pointerMoved(StrokePoint(x: 1, y: 1))  // updates lastInputAt to 9
        c.pointerUp()                            // updates lastInputAt to 9; mode .activeIdle
        clock.advance(by: 5)                     // 5s past pointerUp — still solid (age 5)
        ticker.tick(at: clock.now())
        #expect(c.fadeOpacity == 1.0)
        #expect(editor.doc.strokes.isEmpty == false)
    }

    @Test("pointerUp sets lastInputAt and the window starts fresh from there")
    func pointerUpResets() {
        let (c, clock, ticker, editor) = make()
        c.autoFadeEnabled = true
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        clock.advance(by: 20)
        c.pointerUp()                            // lastInputAt = 20; mode .activeIdle
        clock.advance(by: 5)                     // 5s past pointerUp
        ticker.tick(at: clock.now())
        #expect(c.fadeOpacity == 1.0)            // age = 5s, still solid
        #expect(editor.doc.strokes.isEmpty == false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test`
Expected: most assertions fail because `handleTick` is still a no-op and `pointerDown`/`pointerMoved`/`pointerUp` don't yet set `lastInputAt`.

- [ ] **Step 3: Fill in `handleTick`**

Modify `Sources/Core/Control/AppController.swift`. Replace the stubbed `handleTick(_:)` with:

```swift
private static let fadeWindowSeconds: Double = 10.0
private static let fadeRampSeconds: Double = 2.0

private func handleTick(_ now: Double) {
    guard autoFadeEnabled else { return }
    guard mode != .activeDrawing else { return }

    if editor.doc.strokes.isEmpty {
        lastInputAt = nil
        fadeOpacity = 1.0
        return
    }

    if lastInputAt == nil {
        lastInputAt = now
        fadeOpacity = 1.0
        return
    }

    let age = now - lastInputAt!
    let rampStart = Self.fadeWindowSeconds - Self.fadeRampSeconds  // 8.0

    if age >= Self.fadeWindowSeconds {
        editor.clear()
        lastInputAt = nil
        fadeOpacity = 1.0
    } else if age >= rampStart {
        fadeOpacity = 1.0 - (age - rampStart) / Self.fadeRampSeconds
    } else {
        fadeOpacity = 1.0
    }
}
```

- [ ] **Step 4: Add pointer-event reset triggers**

In the same file, update the existing `pointerDown`, `pointerMoved`, and `pointerUp` to set `lastInputAt` at the **top** of each method (before any guards), so the timer ticks even if the event was a no-op for the drawing state machine. Concretely:

```swift
public func pointerDown(_ point: StrokePoint) {
    lastInputAt = clock.now()
    guard mode == .activeIdle else { return }
    // ... existing body unchanged ...
}

public func pointerMoved(_ point: StrokePoint) {
    lastInputAt = clock.now()
    guard mode == .activeDrawing else { return }
    // ... existing body unchanged ...
}

public func pointerUp() {
    lastInputAt = clock.now()
    guard mode == .activeDrawing else { return }
    // ... existing body unchanged ...
}
```

Adding the reset above the mode guard is intentional — even pointer events outside drawing state (e.g., a stray `pointerMoved` while inactive) should keep the timer fresh, since they indicate the user is still active.

- [ ] **Step 5: Run tests to verify they pass**

Run: `just check`
Expected: 10 new `FadeTickTests` pass; all previous tests still green; lint clean.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Control/AppController.swift \
        Tests/CoreTests/AppControllerTests/FadeTickTests.swift
git commit -m "$(cat <<'EOF'
Core: AppController fade tick state machine + pointer-event resets

handleTick implements the design's branch table: autoFade-off no-op,
mid-stroke guard, empty-doc reset, lastInputAt re-arm after undo,
8s solid + 2s linear ramp + expiration via editor.clear(). Pointer
events set lastInputAt at the top of their handlers so normal drawing
keeps the timer fresh continuously.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: `CanvasView.globalOpacity` + alpha multiply on draw

Add the rendering hook so the AppController's `onFadeOpacityChanged` publisher can dim strokes.

**Files:**
- Modify: `Sources/AppKit/CanvasView.swift`
- Create: `Tests/AppKitTests/CanvasViewGlobalOpacityTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/AppKitTests/CanvasViewGlobalOpacityTests.swift`. Pixel-sampling pattern mirrors `CanvasViewVisibilityTests.swift`.

```swift
// ABOUTME: Tests for CanvasView.globalOpacity — verifies the setter, dirty
// ABOUTME: marking, and that rendering with reduced opacity dims stroke alpha.

import AppKit
import Testing

@Suite("CanvasView globalOpacity")
@MainActor
struct CanvasViewGlobalOpacityTests {
    @Test("initial globalOpacity is 1.0")
    func initialOpacity() {
        let canvas = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        #expect(canvas.globalOpacity == 1.0)
    }

    @Test("setGlobalOpacity stores the new value")
    func setStoresValue() {
        let canvas = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        canvas.setGlobalOpacity(0.5)
        #expect(canvas.globalOpacity == 0.5)
    }

    @Test("setGlobalOpacity marks the view dirty")
    func setMarksDirty() {
        let canvas = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        canvas.needsDisplay = false
        canvas.setGlobalOpacity(0.5)
        #expect(canvas.needsDisplay == true)
    }

    @Test("idempotent setGlobalOpacity does not redraw")
    func idempotentSetSkipsRedraw() {
        let canvas = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        canvas.setGlobalOpacity(0.5)
        canvas.needsDisplay = false
        canvas.setGlobalOpacity(0.5)
        #expect(canvas.needsDisplay == false)
    }

    @Test("rendering at opacity 0.5 produces a half-alpha pixel")
    func renderAtHalfOpacity() throws {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        let stroke = Stroke(id: "a", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 4,
                            transform: .identity,
                            points: [StrokePoint(x: 10, y: 5), StrokePoint(x: 40, y: 5)],
                            pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        view.render(RenderFrame(strokes: [stroke], inProgress: nil,
                                canvasSize: Size(width: 50, height: 50)))
        view.setGlobalOpacity(0.5)
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let pixel = try #require(rep.colorAt(x: 25, y: 5))
        // Stroke is opaque red; at opacity 0.5 it should sample to alpha ~0.5.
        #expect(abs(pixel.alphaComponent - 0.5) < 0.1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test`
Expected: compile errors — `CanvasView.globalOpacity`, `setGlobalOpacity` not found.

- [ ] **Step 3: Add `globalOpacity` to `CanvasView`**

`CanvasView.draw(_:)` already follows a two-layer pattern: it blits a baked `CGImage` of committed strokes, then draws the in-progress stroke live on top. Apply the global alpha **once**, immediately after the existing `guard drawingsVisible else { return }` line at the top of `draw(_:)`. `CGContext.setAlpha` is a global state modifier, so both the bake blit (`ctx.draw(image, in: rect)`) and the live `drawStroke(live, ...)` inherit the factor without any per-stroke change.

Modify `Sources/AppKit/CanvasView.swift`:

1. Add the stored property and setter near the existing `drawingsVisible` property:

```swift
public private(set) var globalOpacity: Double = 1.0

public func setGlobalOpacity(_ opacity: Double) {
    guard globalOpacity != opacity else { return }
    globalOpacity = opacity
    needsDisplay = true
}
```

2. In `draw(_:)`, add **one line** after the existing `guard drawingsVisible else { return }` and before the bake-blit / live-draw block:

```swift
public override func draw(_ dirtyRect: NSRect) {
    // ... existing setup (getting ctx, etc.) ...
    guard drawingsVisible else { return }
    ctx.setAlpha(CGFloat(globalOpacity))   // <-- ADD THIS LINE
    // ... existing bake blit + live drawStroke ...
}
```

Single insertion, no other modifications to draw logic. The default `globalOpacity = 1.0` makes the new call a no-op for existing code paths.

- [ ] **Step 4: Run tests to verify they pass**

Run: `just check`
Expected: four new `CanvasViewGlobalOpacityTests` pass; existing `CanvasView*Tests` still green; lint clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/CanvasView.swift \
        Tests/AppKitTests/CanvasViewGlobalOpacityTests.swift
git commit -m "$(cat <<'EOF'
AppKit: CanvasView.globalOpacity for auto-fade rendering

setGlobalOpacity stores the value and marks the view dirty. Draw
multiplies stroke alpha by the global factor (applied once before
the stroke loop). The publisher hookup in main.swift lands with the
toolbar toggle next.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Toolbar auto-fade toggle button + `main.swift` opacity wiring (atomic)

The final slice. Toolbar gets a new toggle button with the `timer` SF Symbol; toggle persists via `UserDefaults` key `fiti.autoFade`; `main.swift` wires `controller.onFadeOpacityChanged → canvas.setGlobalOpacity`. Both end-to-end so the feature is fully observable on the toolbar at the end of this commit.

**Files:**
- Modify: `Sources/AppKit/ToolbarController.swift`
- Modify: `Tests/AppKitTests/ToolbarControllerTests.swift`
- Modify: `Sources/App/main.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/AppKitTests/ToolbarControllerTests.swift` (do not modify existing suites):

```swift
@Suite("ToolbarController auto-fade toggle")
@MainActor
struct ToolbarControllerAutoFadeTests {
    private func make(defaults: UserDefaults) -> (ToolbarController, AppController, VirtualClock) {
        let clock = VirtualClock()
        let window = RecordingWindow()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(
            editor: editor,
            window: window,
            detector: RecordingStationaryDetector(),
            clock: clock,
            ticker: RecordingFadeTicker()
        )
        let toolbar = ToolbarController(controller: controller, defaults: defaults)
        return (toolbar, controller, clock)
    }

    private func uniqueDefaults() -> UserDefaults {
        let suite = "fiti.tests.autoFade.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test("button glyph is outline timer when auto-fade is off")
    func glyphOff() {
        let (toolbar, _, _) = make(defaults: uniqueDefaults())
        #expect(toolbar.testOnly_autoFadeGlyphName == "timer")
    }

    @Test("button glyph swaps to filled timer when auto-fade is on")
    func glyphOn() {
        let (toolbar, controller, _) = make(defaults: uniqueDefaults())
        controller.autoFadeEnabled = true
        #expect(toolbar.testOnly_autoFadeGlyphName == "timer.fill")
    }

    @Test("clicking the button toggles controller.autoFadeEnabled")
    func clickToggles() {
        let (toolbar, controller, _) = make(defaults: uniqueDefaults())
        #expect(controller.autoFadeEnabled == false)
        toolbar.testOnly_clickAutoFade()
        #expect(controller.autoFadeEnabled == true)
        toolbar.testOnly_clickAutoFade()
        #expect(controller.autoFadeEnabled == false)
    }

    @Test("toggle writes to UserDefaults under fiti.autoFade")
    func togglePersists() {
        let defaults = uniqueDefaults()
        let (toolbar, _, _) = make(defaults: defaults)
        toolbar.testOnly_clickAutoFade()
        #expect(defaults.bool(forKey: "fiti.autoFade") == true)
        toolbar.testOnly_clickAutoFade()
        #expect(defaults.bool(forKey: "fiti.autoFade") == false)
    }

    @Test("init reads persisted state from UserDefaults")
    func initReadsPersisted() {
        let defaults = uniqueDefaults()
        defaults.set(true, forKey: "fiti.autoFade")
        let (_, controller, _) = make(defaults: defaults)
        #expect(controller.autoFadeEnabled == true)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test`
Expected: compile errors — `testOnly_autoFadeGlyphName`, `testOnly_clickAutoFade` not found.

- [ ] **Step 3: Add the button to `ToolbarController`**

Modify `Sources/AppKit/ToolbarController.swift`:

1. Add a stored `autoFadeButton: NSButton` property.
2. Construct it in `init` and append to the toolbar's stack (place it next to the existing `hideButton`).
3. Read persisted state in `loadPersistedState()` (or wherever existing UserDefaults reads happen) and assign to `controller.autoFadeEnabled`.
4. Subscribe to `controller.onAutoFadeEnabledChanged` to swap the glyph.
5. Wire `@objc func autoFadeClicked(_:)` to toggle `controller.autoFadeEnabled` and persist.
6. Add `testOnly_autoFadeGlyphName` (computed property, inside the existing `// swiftlint:disable identifier_name` block) and `testOnly_clickAutoFade()` (method, outside the block — same convention as `testOnly_toggleHide`).

The glyph mapping is `timer.fill` when ON, `timer` when OFF (mirrors the existing hide button's `eye` / `eye.slash` pattern).

Concrete additions:

```swift
// Stored property near the other buttons:
private let autoFadeButton = NSButton(title: "", target: nil, action: nil)
internal private(set) var currentAutoFadeGlyphName: String = "timer"

// In buildContent(), after the hide button:
autoFadeButton.target = self
autoFadeButton.action = #selector(autoFadeClicked(_:))
autoFadeButton.bezelStyle = .regularSquare
autoFadeButton.imagePosition = .imageOnly
updateAutoFadeGlyph(enabled: controller.autoFadeEnabled)
stack.addArrangedSubview(autoFadeButton)

// In loadPersistedState():
let stored = defaults.bool(forKey: "fiti.autoFade")
if stored { controller.autoFadeEnabled = true }

// In init(), after the existing onDrawingsVisibilityChanged subscription:
controller.onAutoFadeEnabledChanged = { [weak self] enabled in
    self?.updateAutoFadeGlyph(enabled: enabled)
}

// New helpers:
private func updateAutoFadeGlyph(enabled: Bool) {
    let name = enabled ? "timer.fill" : "timer"
    currentAutoFadeGlyphName = name
    autoFadeButton.image = NSImage(systemSymbolName: name, accessibilityDescription: "Auto-fade drawings")
}

@objc private func autoFadeClicked(_ sender: NSButton) {
    controller.autoFadeEnabled.toggle()
    defaults.set(controller.autoFadeEnabled, forKey: "fiti.autoFade")
}

// Test hooks — method goes ABOVE the existing swiftlint:disable block,
// computed property goes INSIDE.
internal func testOnly_clickAutoFade() {
    autoFadeClicked(autoFadeButton)
}

// Inside the existing swiftlint:disable identifier_name block:
internal var testOnly_autoFadeGlyphName: String { currentAutoFadeGlyphName }
```

If `controller.onAutoFadeEnabledChanged` was already being used elsewhere (it isn't, but a future toolbar might compose multiple handlers), grab the existing handler first and compose. For now, direct assignment is fine.

- [ ] **Step 4: Update `Sources/App/main.swift`**

In `composeControllerCallbacks()` (or wherever the existing `onCursorChanged` and `onDrawingsVisibilityChanged` wires live), add the canvas opacity wire-up:

```swift
controller.onFadeOpacityChanged = { [weak self] opacity in
    self?.canvas.setGlobalOpacity(opacity)
}
```

Place it near the other `controller.on*Changed` assignments — order doesn't matter functionally.

- [ ] **Step 5: Run the full check**

Run: `just check`
Expected:
- Five new `ToolbarControllerAutoFadeTests` pass.
- All previous tests still green.
- `fiti-integration` count grows by 5.
- Lint clean, build succeeds.

- [ ] **Step 6: Manual smoke test**

```bash
just run-bg
```

Manually exercise:
1. Click the timer glyph in the toolbar (it should be outline-style). Verify it flips to filled.
2. Draw a stroke. Wait 8 seconds. The stroke should remain at full opacity for the first 8 s.
3. Watch the next 2 s — the stroke should fade smoothly to invisible.
4. At t ≈ 10 s, the stroke should disappear entirely.
5. Press `Cmd+Z` (via the menubar Edit menu or the keyboard). The stroke should reappear at full opacity. A fresh 10 s window starts.
6. Toggle auto-fade off mid-fade (during seconds 8–10). The stroke should snap back to full opacity and remain.
7. Quit the app via the menubar. Relaunch with `just run-bg`. The toolbar's auto-fade button should reflect whatever state it was in at quit (persistence check).

```bash
just stop
```

- [ ] **Step 7: Commit**

```bash
git add Sources/AppKit/ToolbarController.swift \
        Sources/App/main.swift \
        Tests/AppKitTests/ToolbarControllerTests.swift
git commit -m "$(cat <<'EOF'
AppKit + App: toolbar auto-fade toggle + main.swift opacity wiring

ToolbarController gains a timer-glyph toggle button next to the hide
button; click flips controller.autoFadeEnabled and persists under
fiti.autoFade in UserDefaults. main.swift wires
controller.onFadeOpacityChanged to canvas.setGlobalOpacity so the
state machine's published opacity dims rendered strokes end-to-end.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Acceptance criteria (mirrors the spec)

- [ ] Toolbar has a `timer`/`timer.fill` toggle button next to the hide button.
- [ ] Toggling ON starts the 10 s window; any pointer event resets the timer.
- [ ] Strokes stay full opacity for 8 s, then ramp linearly to 0 over the last 2 s.
- [ ] At t = 10 s a single `editor.clear()` removes all strokes; one `Cmd+Z` restores them and restarts the window.
- [ ] Toggling OFF mid-ramp snaps opacity back to 1.0; expired strokes stay gone until `Cmd+Z`.
- [ ] Mid-stroke pause of any length does NOT trigger expiration of the in-progress stroke (mid-stroke guard).
- [ ] Toggle state persists across launches under `UserDefaults` key `fiti.autoFade`.
- [ ] `Sources/Core/` keeps zero AppKit/CoreGraphics/SwiftUI/Network imports.
- [ ] All test suites finish in under 5 s (`just check`).
