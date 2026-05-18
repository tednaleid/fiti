# fiti Hold-to-Straighten Gesture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Notability-style hold-to-straighten gesture. While drawing, if the pointer goes stationary for ~800ms AND the freehand path so far is "substantially straight," replace the stroke with a line from start to current position and enter rubber-band mode where subsequent moves update only the endpoint until the user releases the mouse.

**Architecture:** Hexagonal split. New Core port `StationaryDetector` abstracts the timer (real AppKit adapter uses `Task.sleep`; test double exposes a `fire()` helper for deterministic tests). A pure straightness rubric `isSubstantiallyStraight(points:)` lives in Core. `Editor` gains two in-place mutators on the current stroke: `straightenCurrentStroke()` (replace points with `[first, last]`) and `moveCurrentStrokeEndpoint(to:)` (replace the last point). Neither pushes its own `InverseOp` — the whole stroke is one undo unit per the existing `startStroke` → `endStroke` model. `AppController` gains an `isRubberBanding` flag (only meaningful while `mode == .activeDrawing`), arms/disarms the detector on pointer events, and routes `pointerMoved` differently depending on the flag.

**Tech Stack:** Swift 6 (Core: pure, AppKit: `Task` for the timer), Swift Testing, existing `Editor` / `AppController` patterns.

**Tunables (start here, adjust if v1 feels wrong):**
- Stationary timeout: 800ms
- Stationary dead-zone radius: 2.0 points (movement less than this doesn't reset the timer)
- Straightness threshold: `pathLength / euclidean(start, end) <= 1.20`
  - 1.0 = perfectly straight; a slight wobble is ~1.05; a box is ≥4. The 1.20 cutoff accepts hand-drawn straight-ish lines, rejects boxes/zigzags.

---

## File structure

**Create:**
- `Sources/Core/Ports/StationaryDetector.swift` — port (1 protocol)
- `Sources/Core/Editor/Straightness.swift` — pure `isSubstantiallyStraight(points:threshold:)` function
- `Sources/AppKit/TaskStationaryDetector.swift` — real adapter wrapping `Task.sleep`
- `Tests/CoreTests/Doubles/RecordingStationaryDetector.swift` — test double with `fire()`
- `Tests/CoreTests/Editor/StraightnessTests.swift` — rubric tests
- `Tests/CoreTests/Editor/EditorStraightenTests.swift` — `straightenCurrentStroke` + `moveCurrentStrokeEndpoint` tests
- `Tests/CoreTests/AppControllerTests/HoldToStraightenTests.swift` — state machine tests

**Modify:**
- `Sources/Core/Editor/Editor.swift` — add `straightenCurrentStroke()` and `moveCurrentStrokeEndpoint(to:)`
- `Sources/Core/Control/AppController.swift` — add `isRubberBanding`, wire `StationaryDetector`, branch in `pointerMoved`/`pointerUp`, handle stationary callback
- `Sources/App/main.swift` — instantiate `TaskStationaryDetector`, pass into `AppController` init
- `Tests/CoreTests/Doubles/` — any controller-test scaffolding that constructs `AppController` needs the new arg

---

## Task 1: StationaryDetector port + test double

**Files:**
- Create: `Sources/Core/Ports/StationaryDetector.swift`
- Create: `Tests/CoreTests/Doubles/RecordingStationaryDetector.swift`
- Create: `Tests/CoreTests/AppControllerTests/HoldToStraightenTests.swift` (just one initial sanity test for the double; full tests come in Task 5)

- [ ] **Step 1: Write the failing test**

Create `Tests/CoreTests/AppControllerTests/HoldToStraightenTests.swift`:

```swift
// ABOUTME: Tests for the hold-to-straighten gesture wiring on AppController.

import Testing

@Suite("hold-to-straighten")
@MainActor
struct HoldToStraightenTests {
    @Test("RecordingStationaryDetector arms, fires, and reports last-armed state")
    func detectorDouble() {
        let det = RecordingStationaryDetector()
        var fired = 0
        det.onStationary = { fired += 1 }
        #expect(det.isArmed == false)
        det.arm()
        #expect(det.isArmed)
        det.fire()
        #expect(fired == 1)
        #expect(det.isArmed == false)
        det.arm()
        det.disarm()
        #expect(det.isArmed == false)
        det.fire()
        #expect(fired == 1) // no fire when disarmed
    }
}
```

- [ ] **Step 2: Run test to verify it fails (compile error: RecordingStationaryDetector undefined)**

Run: `just test`
Expected: build failure — `Cannot find 'RecordingStationaryDetector' in scope`.

- [ ] **Step 3: Create the port**

Create `Sources/Core/Ports/StationaryDetector.swift`:

```swift
// ABOUTME: Port for "fire a callback after N ms of no arm() call." Real adapter
// ABOUTME: uses Task.sleep; test double exposes fire() so tests run instantly.

import Foundation

@MainActor
public protocol StationaryDetector: AnyObject {
    /// Callback invoked when the armed timer expires. Set once at composition time.
    var onStationary: (() -> Void)? { get set }
    /// (Re)start the timer. Any pending callback is cancelled.
    func arm()
    /// Cancel any pending callback.
    func disarm()
}
```

- [ ] **Step 4: Create the test double**

Create `Tests/CoreTests/Doubles/RecordingStationaryDetector.swift`:

```swift
// ABOUTME: Synchronous StationaryDetector for tests. fire() simulates the timer
// ABOUTME: expiring; isArmed lets tests assert on arm/disarm bookkeeping.

import Foundation

@MainActor
public final class RecordingStationaryDetector: StationaryDetector {
    public var onStationary: (() -> Void)?
    public private(set) var isArmed = false
    public init() {}
    public func arm() { isArmed = true }
    public func disarm() { isArmed = false }
    /// Test helper: simulate the timer expiring. No-op if not armed.
    public func fire() {
        guard isArmed else { return }
        isArmed = false
        onStationary?()
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `just test`
Expected: PASS — fiti-unit count up by 1.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Ports/StationaryDetector.swift \
        Tests/CoreTests/Doubles/RecordingStationaryDetector.swift \
        Tests/CoreTests/AppControllerTests/HoldToStraightenTests.swift
git commit -m "Core: StationaryDetector port + recording double"
```

---

## Task 2: Straightness rubric (pure function)

**Files:**
- Create: `Sources/Core/Editor/Straightness.swift`
- Create: `Tests/CoreTests/Editor/StraightnessTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/Editor/StraightnessTests.swift`:

```swift
// ABOUTME: Tests for isSubstantiallyStraight — the rubric that decides whether
// ABOUTME: a freehand path qualifies for the hold-to-straighten snap.

import Testing

@Suite("isSubstantiallyStraight")
struct StraightnessTests {
    @Test("two-point segment is straight")
    func twoPoints() {
        let pts = [StrokePoint(x: 0, y: 0), StrokePoint(x: 10, y: 0)]
        #expect(isSubstantiallyStraight(points: pts))
    }

    @Test("perfectly collinear points are straight")
    func collinear() {
        let pts = (0...10).map { StrokePoint(x: Double($0), y: Double($0) * 2) }
        #expect(isSubstantiallyStraight(points: pts))
    }

    @Test("slight wobble within threshold is straight")
    func slightWobble() {
        // a near-straight line from (0,0) to (100,0) with sub-point Y jitter
        let pts = (0...100).map { StrokePoint(x: Double($0), y: ($0 % 2 == 0) ? 0.5 : -0.5) }
        #expect(isSubstantiallyStraight(points: pts))
    }

    @Test("box is not straight")
    func box() {
        let pts = [
            StrokePoint(x: 0, y: 0),
            StrokePoint(x: 10, y: 0),
            StrokePoint(x: 10, y: 10),
            StrokePoint(x: 0, y: 10),
            StrokePoint(x: 0, y: 0.1)  // near-closed box
        ]
        #expect(isSubstantiallyStraight(points: pts) == false)
    }

    @Test("zigzag is not straight")
    func zigzag() {
        let pts = (0...20).map { i -> StrokePoint in
            StrokePoint(x: Double(i), y: (i % 2 == 0) ? 0 : 10)
        }
        #expect(isSubstantiallyStraight(points: pts) == false)
    }

    @Test("fewer than 2 points is not straight")
    func notEnoughPoints() {
        #expect(isSubstantiallyStraight(points: []) == false)
        #expect(isSubstantiallyStraight(points: [StrokePoint(x: 0, y: 0)]) == false)
    }

    @Test("first and last identical (closed loop) is not straight")
    func degenerateEuclidean() {
        let pts = [
            StrokePoint(x: 0, y: 0),
            StrokePoint(x: 5, y: 5),
            StrokePoint(x: 0, y: 0)
        ]
        #expect(isSubstantiallyStraight(points: pts) == false)
    }

    @Test("threshold is configurable")
    func customThreshold() {
        // a slightly-curved path with ratio ~1.10
        let pts = [
            StrokePoint(x: 0, y: 0),
            StrokePoint(x: 5, y: 1),
            StrokePoint(x: 10, y: 0)
        ]
        #expect(isSubstantiallyStraight(points: pts, threshold: 1.20))
        #expect(isSubstantiallyStraight(points: pts, threshold: 1.05) == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test`
Expected: `Cannot find 'isSubstantiallyStraight' in scope`.

- [ ] **Step 3: Implement the rubric**

Create `Sources/Core/Editor/Straightness.swift`:

```swift
// ABOUTME: Pure rubric for the hold-to-straighten gesture. Returns true when a
// ABOUTME: freehand path is straight enough that snapping to a line won't surprise
// ABOUTME: the user (rejects boxes, zigzags, arbitrary curves).

import Foundation

/// Returns true if `points` form a substantially-straight path. Uses the ratio
/// of accumulated path length to start→end Euclidean distance: 1.0 is perfect,
/// higher = more wandering. Default threshold of 1.20 accepts hand-drawn
/// straight-ish lines and rejects boxes/curves/zigzags.
public func isSubstantiallyStraight(points: [StrokePoint], threshold: Double = 1.20) -> Bool {
    guard points.count >= 2 else { return false }
    let dx = points.last!.x - points.first!.x
    let dy = points.last!.y - points.first!.y
    let euclidean = (dx * dx + dy * dy).squareRoot()
    guard euclidean > 0 else { return false }
    var pathLength = 0.0
    for i in 1..<points.count {
        let ddx = points[i].x - points[i - 1].x
        let ddy = points[i].y - points[i - 1].y
        pathLength += (ddx * ddx + ddy * ddy).squareRoot()
    }
    return pathLength / euclidean <= threshold
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `just test`
Expected: all 8 new straightness tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Editor/Straightness.swift Tests/CoreTests/Editor/StraightnessTests.swift
git commit -m "Core: isSubstantiallyStraight rubric for hold-to-straighten"
```

---

## Task 3: Editor mutators (straightenCurrentStroke + moveCurrentStrokeEndpoint)

**Files:**
- Modify: `Sources/Core/Editor/Editor.swift`
- Create: `Tests/CoreTests/Editor/EditorStraightenTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/Editor/EditorStraightenTests.swift`:

```swift
// ABOUTME: Tests for Editor.straightenCurrentStroke and moveCurrentStrokeEndpoint.

import Testing

@Suite("Editor straighten & move endpoint")
@MainActor
struct EditorStraightenTests {
    private func make() -> Editor {
        Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
    }

    @Test("straightenCurrentStroke replaces points with [first, last]")
    func straighten() {
        let e = make()
        let red = RGBA(r: 1, g: 0, b: 0, a: 1)
        let id = e.startStroke(color: red, width: 4, pointerType: .mouse)
        e.appendPoint(StrokePoint(x: 0, y: 0))
        e.appendPoint(StrokePoint(x: 3, y: 1))
        e.appendPoint(StrokePoint(x: 6, y: -1))
        e.appendPoint(StrokePoint(x: 10, y: 0))
        e.straightenCurrentStroke()
        let pts = e.doc.strokes[id]!.points
        #expect(pts.count == 2)
        #expect(pts.first == StrokePoint(x: 0, y: 0))
        #expect(pts.last == StrokePoint(x: 10, y: 0))
    }

    @Test("straightenCurrentStroke is a no-op when no stroke in progress")
    func straightenNoStroke() {
        let e = make()
        e.straightenCurrentStroke()  // does not crash
    }

    @Test("straightenCurrentStroke with fewer than 2 points is a no-op")
    func straightenTooFew() {
        let e = make()
        _ = e.startStroke(color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 4, pointerType: .mouse)
        e.appendPoint(StrokePoint(x: 0, y: 0))
        e.straightenCurrentStroke()
        #expect(e.doc.strokes[e.currentStrokeId!]!.points.count == 1)
    }

    @Test("moveCurrentStrokeEndpoint replaces the last point in place")
    func moveEndpoint() {
        let e = make()
        let id = e.startStroke(color: RGBA(r: 0, g: 1, b: 0, a: 1), width: 4, pointerType: .mouse)
        e.appendPoint(StrokePoint(x: 0, y: 0))
        e.appendPoint(StrokePoint(x: 10, y: 10))
        e.moveCurrentStrokeEndpoint(to: StrokePoint(x: 20, y: 5))
        let pts = e.doc.strokes[id]!.points
        #expect(pts.count == 2)
        #expect(pts.last == StrokePoint(x: 20, y: 5))
    }

    @Test("moveCurrentStrokeEndpoint is a no-op when no stroke in progress")
    func moveEndpointNoStroke() {
        let e = make()
        e.moveCurrentStrokeEndpoint(to: StrokePoint(x: 1, y: 1))  // does not crash
    }

    @Test("undo after straightenCurrentStroke + endStroke removes the whole stroke")
    func undoAfterStraighten() {
        let e = make()
        let id = e.startStroke(color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 4, pointerType: .mouse)
        e.appendPoint(StrokePoint(x: 0, y: 0))
        e.appendPoint(StrokePoint(x: 5, y: 1))
        e.appendPoint(StrokePoint(x: 10, y: 0))
        e.straightenCurrentStroke()
        e.moveCurrentStrokeEndpoint(to: StrokePoint(x: 15, y: 0))
        e.endStroke()
        #expect(e.doc.strokes[id] != nil)
        #expect(e.undo())
        #expect(e.doc.strokes[id] == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test`
Expected: `value of type 'Editor' has no member 'straightenCurrentStroke'` (and `moveCurrentStrokeEndpoint`).

- [ ] **Step 3: Implement the mutators**

Open `Sources/Core/Editor/Editor.swift`. Find `appendPoint(_:)` (~line 54). Add these methods immediately after it:

```swift
public func straightenCurrentStroke() {
    guard let id = currentStrokeId else { return }
    guard let stroke = doc.strokes[id], stroke.points.count >= 2 else { return }
    doc.strokes[id]!.points = [stroke.points.first!, stroke.points.last!]
    emit(.local)
}

public func moveCurrentStrokeEndpoint(to point: StrokePoint) {
    guard let id = currentStrokeId else { return }
    guard let stroke = doc.strokes[id], !stroke.points.isEmpty else { return }
    doc.strokes[id]!.points[doc.strokes[id]!.points.count - 1] = point
    emit(.local)
}
```

Neither pushes an `InverseOp`. The undo unit is the whole stroke (set up by `startStroke`'s existing inverse-op push). `endStroke` is the commit point that makes the undo target the full final stroke shape.

- [ ] **Step 4: Run tests to verify they pass**

Run: `just test`
Expected: 6 new tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Editor/Editor.swift Tests/CoreTests/Editor/EditorStraightenTests.swift
git commit -m "Editor: straightenCurrentStroke + moveCurrentStrokeEndpoint"
```

---

## Task 4: AppController state — isRubberBanding + detector wiring

**Files:**
- Modify: `Sources/Core/Control/AppController.swift`
- Modify: `Tests/CoreTests/AppControllerTests/HoldToStraightenTests.swift`
- Possibly modify: any test helper that constructs `AppController(editor:window:)` — they need a `detector:` arg now.

- [ ] **Step 1: Audit AppController constructor call sites**

Run:
```bash
grep -rn "AppController(editor:" Tests/ Sources/ | grep -v "Sources/Core/Control/AppController.swift"
```

Note every file. The constructor signature is about to gain a `detector: StationaryDetector` argument; each call site needs an instance — production passes the real `TaskStationaryDetector` (Task 6), tests pass `RecordingStationaryDetector()`.

- [ ] **Step 2: Write the failing tests**

Append to `Tests/CoreTests/AppControllerTests/HoldToStraightenTests.swift`:

```swift
    private func make() -> (AppController, RecordingStationaryDetector) {
        let window = RecordingWindow()
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        let detector = RecordingStationaryDetector()
        let controller = AppController(editor: editor, window: window, detector: detector)
        return (controller, detector)
    }

    @Test("pointerDown arms the detector")
    func pointerDownArms() {
        let (c, det) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        #expect(det.isArmed)
    }

    @Test("pointerMoved past the dead-zone re-arms the detector")
    func pointerMovedReArms() {
        let (c, det) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        det.disarm()  // clear initial arm
        c.pointerMoved(StrokePoint(x: 10, y: 0))  // well past dead-zone
        #expect(det.isArmed)
    }

    @Test("tiny jitter within the dead-zone does not re-arm")
    func jitterDoesNotReArm() {
        let (c, det) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        det.disarm()
        c.pointerMoved(StrokePoint(x: 0.5, y: 0.5))  // within 2.0 dead-zone
        #expect(det.isArmed == false)
    }

    @Test("pointerUp disarms")
    func pointerUpDisarms() {
        let (c, det) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        #expect(det.isArmed)
        c.pointerUp()
        #expect(det.isArmed == false)
    }

    @Test("stationary fire on a straight stroke enters rubber-band and snaps the stroke")
    func snapStraightStroke() {
        let (c, det) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.pointerMoved(StrokePoint(x: 5, y: 0.5))
        c.pointerMoved(StrokePoint(x: 10, y: -0.5))
        c.pointerMoved(StrokePoint(x: 15, y: 0))
        #expect(c.isRubberBanding == false)
        det.fire()
        #expect(c.isRubberBanding == true)
        let id = c.editor.currentStrokeId!
        let pts = c.editor.doc.strokes[id]!.points
        #expect(pts.count == 2)
        #expect(pts.first == StrokePoint(x: 0, y: 0))
        #expect(pts.last == StrokePoint(x: 15, y: 0))
    }

    @Test("stationary fire on a non-straight stroke does NOT snap")
    func dontSnapBox() {
        let (c, det) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.pointerMoved(StrokePoint(x: 10, y: 0))
        c.pointerMoved(StrokePoint(x: 10, y: 10))
        c.pointerMoved(StrokePoint(x: 0, y: 10))
        det.fire()
        #expect(c.isRubberBanding == false)
        let id = c.editor.currentStrokeId!
        #expect(c.editor.doc.strokes[id]!.points.count == 4)
    }

    @Test("during rubber-band, pointerMoved updates the endpoint instead of appending")
    func rubberBandMovesEndpoint() {
        let (c, det) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.pointerMoved(StrokePoint(x: 50, y: 0))
        det.fire()  // snap → rubber-band
        c.pointerMoved(StrokePoint(x: 100, y: 50))  // should update endpoint
        let id = c.editor.currentStrokeId!
        let pts = c.editor.doc.strokes[id]!.points
        #expect(pts.count == 2)
        #expect(pts.last == StrokePoint(x: 100, y: 50))
    }

    @Test("during rubber-band, the stationary detector stays disarmed")
    func rubberBandKeepsDetectorDisarmed() {
        let (c, det) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.pointerMoved(StrokePoint(x: 50, y: 0))
        det.fire()
        c.pointerMoved(StrokePoint(x: 75, y: 0))
        c.pointerMoved(StrokePoint(x: 100, y: 25))
        #expect(det.isArmed == false)
    }

    @Test("pointerUp from rubber-band commits the line and resets state")
    func rubberBandCommit() {
        let (c, det) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.pointerMoved(StrokePoint(x: 50, y: 0))
        det.fire()
        c.pointerMoved(StrokePoint(x: 100, y: 25))
        c.pointerUp()
        #expect(c.isRubberBanding == false)
        #expect(c.mode == .activeIdle)
        #expect(c.editor.currentStrokeId == nil)
    }
```

- [ ] **Step 3: Run test to verify it fails**

Run: `just test`
Expected: build errors — `AppController` has no `detector:` arg, no `isRubberBanding` property.

- [ ] **Step 4: Update AppController**

Open `Sources/Core/Control/AppController.swift`. Apply these changes:

(a) Add a stored property for the detector and the rubber-band flag, near the existing `window: WindowControl`:

```swift
private let detector: StationaryDetector
private let stationaryDeadZone: Double = 2.0
private var lastTimerResetPoint: StrokePoint?

public private(set) var isRubberBanding: Bool = false
```

(b) Update the initializer:

```swift
public init(editor: Editor, window: WindowControl, detector: StationaryDetector) {
    self.editor = editor
    self.window = window
    self.detector = detector
    detector.onStationary = { [weak self] in self?.handleStationary() }
}
```

(c) In `pointerDown`, arm the detector after appending the first point:

```swift
public func pointerDown(_ point: StrokePoint) {
    guard mode == .activeIdle else { return }
    _ = editor.startStroke(color: currentColor, width: currentWidth, pointerType: .mouse)
    editor.appendPoint(point)
    mode = .activeDrawing
    lastTimerResetPoint = point
    detector.arm()
}
```

(d) Rewrite `pointerMoved` to branch on `isRubberBanding`:

```swift
public func pointerMoved(_ point: StrokePoint) {
    guard mode == .activeDrawing else { return }
    if isRubberBanding {
        editor.moveCurrentStrokeEndpoint(to: point)
    } else {
        editor.appendPoint(point)
        if pastDeadZone(point) {
            lastTimerResetPoint = point
            detector.arm()
        }
    }
}

private func pastDeadZone(_ point: StrokePoint) -> Bool {
    guard let last = lastTimerResetPoint else { return true }
    let dx = point.x - last.x
    let dy = point.y - last.y
    return (dx * dx + dy * dy).squareRoot() > stationaryDeadZone
}
```

(e) Update `pointerUp` to disarm and reset rubber-band:

```swift
public func pointerUp() {
    guard mode == .activeDrawing else { return }
    detector.disarm()
    isRubberBanding = false
    lastTimerResetPoint = nil
    editor.endStroke()
    mode = .activeIdle
}
```

(f) Add the stationary handler:

```swift
private func handleStationary() {
    guard mode == .activeDrawing, !isRubberBanding else { return }
    guard let id = editor.currentStrokeId,
          let stroke = editor.doc.strokes[id] else { return }
    guard isSubstantiallyStraight(points: stroke.points) else { return }
    editor.straightenCurrentStroke()
    isRubberBanding = true
}
```

(g) Make sure `clear()` and `deactivate()` (which can interrupt a stroke) also reset `isRubberBanding` and disarm:

```swift
public func deactivate() {
    guard mode != .inactive else { return }
    if mode == .activeDrawing {
        detector.disarm()
        isRubberBanding = false
        lastTimerResetPoint = nil
        editor.endStroke()
    }
    mode = .inactive
    window.setClickThrough(true)
    window.releaseFocus()
}

public func clear() {
    if mode == .activeDrawing {
        detector.disarm()
        isRubberBanding = false
        lastTimerResetPoint = nil
        editor.endStroke()
        mode = .activeIdle
    }
    editor.clear()
}
```

- [ ] **Step 5: Fix every other AppController construction site**

For each site found in Step 1, append a `detector:` argument. In tests, pass `RecordingStationaryDetector()`. In `main.swift`, this is handled in Task 6 — for now you can pass a `RecordingStationaryDetector()` placeholder if main.swift compiles via the integration target (it shouldn't — only the App target compiles main.swift).

- [ ] **Step 6: Run tests to verify they pass**

Run: `just test && just test-integration`
Expected: all new HoldToStraightenTests PASS; the existing ActivationTests / cursor tests still PASS after the constructor update.

- [ ] **Step 7: Commit**

```bash
git add Sources/Core/Control/AppController.swift Tests/CoreTests/AppControllerTests/HoldToStraightenTests.swift Tests/CoreTests/
git commit -m "AppController: hold-to-straighten state machine (timer + rubber-band)"
```

---

## Task 5: TaskStationaryDetector adapter (AppKit)

**Files:**
- Create: `Sources/AppKit/TaskStationaryDetector.swift`

- [ ] **Step 1: Implement the adapter**

Create `Sources/AppKit/TaskStationaryDetector.swift`:

```swift
// ABOUTME: StationaryDetector adapter using a cancellable Task with sleep.
// ABOUTME: arm() restarts the sleep; disarm() cancels. onStationary fires on
// ABOUTME: timeout if and only if the most recent arm() wasn't superseded.

import Foundation

@MainActor
public final class TaskStationaryDetector: StationaryDetector {
    public var onStationary: (() -> Void)?
    private let timeout: Duration
    private var task: Task<Void, Never>?

    public init(timeout: Duration = .milliseconds(800)) {
        self.timeout = timeout
    }

    public func arm() {
        task?.cancel()
        task = Task { @MainActor [weak self, timeout] in
            try? await Task.sleep(for: timeout)
            guard let self, !Task.isCancelled else { return }
            self.onStationary?()
        }
    }

    public func disarm() {
        task?.cancel()
        task = nil
    }

    isolated deinit {
        task?.cancel()
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `just build`
Expected: BUILD SUCCEEDED. (No tests for the real adapter — it would require waiting on real time. The protocol contract is tested via the double.)

- [ ] **Step 3: Commit**

```bash
git add Sources/AppKit/TaskStationaryDetector.swift
git commit -m "AppKit: TaskStationaryDetector adapter (Task.sleep-based timer)"
```

---

## Task 6: main.swift wiring

**Files:**
- Modify: `Sources/App/main.swift`

- [ ] **Step 1: Instantiate the detector and pass it into AppController**

Open `Sources/App/main.swift`. Find the AppController construction (~line 42):

```swift
controller = AppController(editor: editor, window: window)
```

Change to:

```swift
controller = AppController(editor: editor, window: window, detector: TaskStationaryDetector())
```

Note: no stored property needed on the delegate — `AppController` holds the detector internally.

- [ ] **Step 2: Verify build + tests**

Run: `just check`
Expected: BUILD SUCCEEDED, all tests pass, lint clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/App/main.swift
git commit -m "main: wire TaskStationaryDetector into AppController"
```

---

## Task 7: Manual smoke test

- [ ] **Step 1: Stop and relaunch**

```bash
just stop && just run-bg
```

- [ ] **Step 2: Activate fiti (Opt+F)**

- [ ] **Step 3: Verify the gesture works**

Draw a slightly-wobbly line from left to right, then hold the mouse still at the endpoint without releasing. After ~0.8s, the stroke should snap to a straight line between start and current cursor position. While still holding, move the cursor — the line's endpoint follows the cursor. Release to commit.

- [ ] **Step 4: Verify boxes do NOT trigger snap**

Draw a square shape (or any closed loop). Hold at the endpoint. The stroke should NOT change. The freehand box stays drawn as-is.

- [ ] **Step 5: Verify Undo removes the whole stroke**

After a hold-to-straighten line commits, press `Cmd+Z`. The straight line should disappear in one undo step. (No intermediate undo state where the original freehand line returns.)

- [ ] **Step 6: Verify normal freehand still works**

Draw a curve and release without pausing. Normal freehand stroke commits as expected.

- [ ] **Step 7: Optional — exercise via dev HTTP**

If something feels off and a deterministic repro is wanted:
```bash
just inspect-pointer down 100 100
just inspect-pointer move 200 102
just inspect-pointer move 300 99
just inspect-pointer move 400 101
sleep 1   # real-time wait for the timer to fire
just inspect-state | jq '.isRubberBanding'   # should be true
just inspect-pointer move 500 200
just inspect-doc | jq '.strokes[].points'
just inspect-pointer up 500 200
```

---

## Risks and open questions

- **Visual snap is abrupt.** Without a preview line during the last ~200ms of the hold, the snap can feel surprising. v1 skips the preview to keep scope tight. If users complain, add a faint preview rendered by the canvas when `isRubberBanding` is about to become true (requires exposing the "armed and likely-to-snap" state).
- **Stroke rendering with 2 points + `simulatePressure=true`.** Perfect-freehand with 2 input points produces a thin oblong with rounded caps. Should look like a clean line. If it looks oddly thick/thin at the ends, consider passing `simulatePressure=false` for the snapped variant only (requires a stroke-level flag).
- **Rubber-band cursor.** The cursor still shows the circle preview from the existing `CursorRenderer`. That's correct — the same color/width applies. No change needed.
- **Hotkey conflicts.** None — this gesture uses no hotkeys, only the existing pointer event flow.
