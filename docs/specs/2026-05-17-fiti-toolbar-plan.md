# fiti Toolbar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the floating-toolbar feature from [`2026-05-17-fiti-toolbar-design.md`](./2026-05-17-fiti-toolbar-design.md): vertical NSPanel with pen-tool placeholder, 8 quick-pick colors, custom color picker, width/opacity sliders, and a hide/show drawings button. Show on activation, hide on deactivation. Position + drawing parameters persist across launches. Every state the toolbar manipulates is also reachable via the dev HTTP API — the hexagonal contract says external (HTTP) and internal (UI) writers both read/write the same Core state.

**Architecture:** Pure adapter (`Sources/AppKit/ToolbarController.swift` + `Sources/AppKit/ToolbarPanel.swift`). Three Core additions: `AppController.drawingsVisible` (with `onDrawingsVisibilityChanged` callback via `didSet`), `didSet`-published callbacks on the existing `currentColor` and `currentWidth`, and a default-color change. One small `CanvasView` change (short-circuit when invisible). HTTP surface extends to expose / drive all three. Wiring in `Sources/App/main.swift`. Persistence via `NSWindow.setFrameAutosaveName` for position and `UserDefaults` (`fiti.*` keys) for color/width.

**Tech Stack:** Swift 6, AppKit (`NSPanel`, `NSStackView`, `NSButton`, `NSSlider`, `NSColorWell`), Swift Testing, `UserDefaults`, NWListener-backed dev HTTP.

---

## File structure

**Modify:**
- `Sources/Core/Control/AppController.swift` — add `drawingsVisible`, add `didSet` publication to `currentColor` / `currentWidth`, change default color
- `Sources/DevHTTP/DevHTTPSurface.swift` — extend the protocol with toolbar-state getters/setters
- `Sources/App/FitiDevHTTPSurface.swift` — implement the new surface members
- `Sources/DevHTTP/DevHTTPServer.swift` — add the new routes (`POST /color`, `POST /width`, `POST /drawings/show`, `POST /drawings/hide`); extend `GET /state` payload
- `Sources/AppKit/CanvasView.swift` — short-circuit `draw(_:)` when `drawingsVisible == false`
- `Sources/App/main.swift` — instantiate `ToolbarController`, compose `onModeChanged` and `onDrawingsVisibilityChanged` between menubar / toolbar / canvas
- `justfile` — add `inspect-set-color`, `inspect-set-width`, `inspect-show`, `inspect-hide` recipes

**Create:**
- `Sources/AppKit/ToolbarController.swift`
- `Sources/AppKit/ToolbarPanel.swift`
- `Tests/CoreTests/AppControllerTests/OnDrawingsVisibilityChangedTests.swift`
- `Tests/CoreTests/AppControllerTests/OnCurrentColorWidthChangedTests.swift`
- `Tests/DevHTTPTests/RouteTests/ToolbarRouteTests.swift` (new file under the existing RouteTests dir)
- `Tests/AppKitTests/ToolbarControllerTests.swift`
- `Tests/AppKitTests/CanvasViewVisibilityTests.swift`

xcodegen auto-picks-up new files. No `project.yml` edits needed.

---

## Task 1: AppController — drawingsVisible, color/width callbacks, default color

**Files:**
- Modify: `Sources/Core/Control/AppController.swift`
- Create: `Tests/CoreTests/AppControllerTests/OnDrawingsVisibilityChangedTests.swift`
- Create: `Tests/CoreTests/AppControllerTests/OnCurrentColorWidthChangedTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/AppControllerTests/OnDrawingsVisibilityChangedTests.swift`:

```swift
// ABOUTME: Tests for AppController.onDrawingsVisibilityChanged — fires when
// ABOUTME: drawingsVisible toggles, via a didSet observer. Mirror of onModeChanged.

import Testing

@Suite("AppController onDrawingsVisibilityChanged")
@MainActor
struct OnDrawingsVisibilityChangedTests {
    private func make() -> AppController {
        let window = RecordingWindow()
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        return AppController(editor: editor, window: window)
    }

    @Test("drawingsVisible defaults to true")
    func defaultIsVisible() {
        let c = make()
        #expect(c.drawingsVisible == true)
    }

    @Test("toggling drawingsVisible publishes the new value")
    func togglePublishes() {
        let c = make()
        var received: [Bool] = []
        c.onDrawingsVisibilityChanged = { received.append($0) }
        c.drawingsVisible = false
        c.drawingsVisible = true
        #expect(received == [false, true])
    }

    @Test("setting the same value does not publish")
    func noOpTransition() {
        let c = make()
        c.drawingsVisible = true
        var received: [Bool] = []
        c.onDrawingsVisibilityChanged = { received.append($0) }
        c.drawingsVisible = true
        #expect(received == [])
    }

    @Test("default color is the red from the toolbar palette at 0.8 opacity")
    func defaultColor() {
        let c = make()
        #expect(c.currentColor.r == 224.0 / 255.0)
        #expect(c.currentColor.g == 49.0 / 255.0)
        #expect(c.currentColor.b == 49.0 / 255.0)
        #expect(c.currentColor.a == 0.8)
    }
}
```

Create `Tests/CoreTests/AppControllerTests/OnCurrentColorWidthChangedTests.swift`:

```swift
// ABOUTME: Tests for AppController.onCurrentColorChanged / onCurrentWidthChanged
// ABOUTME: — fire when the drawing parameters change so adapters (toolbar widgets,
// ABOUTME: HTTP clients) can react to writes from any source.

import Testing

@Suite("AppController color/width didSet publication")
@MainActor
struct OnCurrentColorWidthChangedTests {
    private func make() -> AppController {
        let window = RecordingWindow()
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        return AppController(editor: editor, window: window)
    }

    @Test("assigning a new currentColor publishes via onCurrentColorChanged")
    func colorPublishes() {
        let c = make()
        var received: [RGBA] = []
        c.onCurrentColorChanged = { received.append($0) }
        c.currentColor = RGBA(r: 0.5, g: 0.5, b: 0.5, a: 0.5)
        #expect(received == [RGBA(r: 0.5, g: 0.5, b: 0.5, a: 0.5)])
    }

    @Test("assigning the same currentColor does not publish")
    func colorNoOp() {
        let c = make()
        let original = c.currentColor
        var received: [RGBA] = []
        c.onCurrentColorChanged = { received.append($0) }
        c.currentColor = original
        #expect(received == [])
    }

    @Test("assigning a new currentWidth publishes via onCurrentWidthChanged")
    func widthPublishes() {
        let c = make()
        var received: [Double] = []
        c.onCurrentWidthChanged = { received.append($0) }
        c.currentWidth = 12
        #expect(received == [12])
    }

    @Test("assigning the same currentWidth does not publish")
    func widthNoOp() {
        let c = make()
        let original = c.currentWidth
        var received: [Double] = []
        c.onCurrentWidthChanged = { received.append($0) }
        c.currentWidth = original
        #expect(received == [])
    }
}
```

- [ ] **Step 2: Run tests, expect failure**

Run `just test`. Should fail: `drawingsVisible`, `onDrawingsVisibilityChanged`, `onCurrentColorChanged`, `onCurrentWidthChanged` don't exist, and the default color won't match.

- [ ] **Step 3: Update AppController**

In `Sources/Core/Control/AppController.swift`, replace the existing color/width lines:

```swift
    // Drawing parameters used while in POC. Hardcoded here; the toolbar that
    // mutates these lands in a later phase.
    public var currentColor: RGBA = RGBA(r: 0.20, g: 0.80, b: 0.94, a: 1.0)
    public var currentWidth: Double = 6
```

with:

```swift
    // Drawing parameters. Each has a didSet publisher so HTTP writes and
    // toolbar-widget writes both notify other adapters that need to react
    // (toolbar widgets, snapshot consumers, etc.).
    public var onCurrentColorChanged: ((RGBA) -> Void)?
    public var onCurrentWidthChanged: ((Double) -> Void)?

    // Default: red #e03131 from the toolbar's quick-pick palette, at 0.8
    // opacity so the slider is immediately discoverable. UserDefaults
    // overrides this when the toolbar reads persisted state at launch.
    public var currentColor: RGBA = RGBA(r: 224.0 / 255.0, g: 49.0 / 255.0, b: 49.0 / 255.0, a: 0.8) {
        didSet {
            if oldValue != currentColor { onCurrentColorChanged?(currentColor) }
        }
    }
    public var currentWidth: Double = 6 {
        didSet {
            if oldValue != currentWidth { onCurrentWidthChanged?(currentWidth) }
        }
    }
```

Then, immediately after the `mode` block (just before `public let editor: Editor`), add:

```swift
    public var onDrawingsVisibilityChanged: ((Bool) -> Void)?

    public var drawingsVisible: Bool = true {
        didSet {
            if oldValue != drawingsVisible { onDrawingsVisibilityChanged?(drawingsVisible) }
        }
    }
```

- [ ] **Step 4: Run tests, expect pass**

Run `just test`. Should report 88 tests pass (80 prior + 8 new across the two test files).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Control/AppController.swift Tests/CoreTests/AppControllerTests/OnDrawingsVisibilityChangedTests.swift Tests/CoreTests/AppControllerTests/OnCurrentColorWidthChangedTests.swift
git commit -m "$(cat <<'EOF'
AppController: drawingsVisible + didSet on color/width + default color

Three additions to support both the toolbar (UI) and the dev HTTP
API (external) being able to drive the same drawing parameters:

- drawingsVisible: Bool with an onDrawingsVisibilityChanged callback,
  mirror of the existing onModeChanged pattern.
- onCurrentColorChanged and onCurrentWidthChanged: didSet publishers
  on the existing currentColor / currentWidth properties so writes
  from any source notify subscribers.
- Default color changes from cyan to #e03131 at 0.8 opacity, matching
  the toolbar's quick-pick palette and surfacing the opacity slider.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Dev HTTP surface — toolbar state + routes

**Files:**
- Modify: `Sources/DevHTTP/DevHTTPSurface.swift`
- Modify: `Sources/App/FitiDevHTTPSurface.swift`
- Modify: `Sources/DevHTTP/DevHTTPServer.swift`
- Create: `Tests/DevHTTPTests/RouteTests/ToolbarRouteTests.swift`
- Modify: existing `/state` route test (likely in `Tests/DevHTTPTests/RouteTests/StateRouteTests.swift` or similar — check the file structure under `Tests/DevHTTPTests/RouteTests/`)

Before starting, run `ls Tests/DevHTTPTests/RouteTests/` to confirm exact file names of existing route tests; the `/state` test file there is the one to extend.

- [ ] **Step 1: Write the failing tests**

Create `Tests/DevHTTPTests/RouteTests/ToolbarRouteTests.swift`:

```swift
// ABOUTME: HTTP route tests for the toolbar surface — POST /color, /width,
// ABOUTME: /drawings/show, /drawings/hide. Mirror what the toolbar widgets do.

import Foundation
import Testing

@Suite("Toolbar routes")
@MainActor
struct ToolbarRouteTests {
    @Test("POST /color sets the surface's currentColor")
    func postColor() async throws {
        let surface = FakeSurface()
        let server = try await startServer(surface: surface)
        defer { server.stop() }
        let body = Data(#"{"r":0.1,"g":0.2,"b":0.3,"a":0.4}"#.utf8)
        let (_, response) = try await postJSON(path: "/color", body: body, port: server.boundPort ?? 0)
        #expect(response.statusCode == 200)
        #expect(surface.currentColor == RGBA(r: 0.1, g: 0.2, b: 0.3, a: 0.4))
    }

    @Test("POST /width sets the surface's currentWidth")
    func postWidth() async throws {
        let surface = FakeSurface()
        let server = try await startServer(surface: surface)
        defer { server.stop() }
        let body = Data(#"{"width":11}"#.utf8)
        let (_, response) = try await postJSON(path: "/width", body: body, port: server.boundPort ?? 0)
        #expect(response.statusCode == 200)
        #expect(surface.currentWidth == 11)
    }

    @Test("POST /drawings/hide sets drawingsVisible to false")
    func postHide() async throws {
        let surface = FakeSurface()
        let server = try await startServer(surface: surface)
        defer { server.stop() }
        let (_, response) = try await postJSON(path: "/drawings/hide", body: Data(), port: server.boundPort ?? 0)
        #expect(response.statusCode == 200)
        #expect(surface.drawingsVisible == false)
    }

    @Test("POST /drawings/show sets drawingsVisible to true")
    func postShow() async throws {
        let surface = FakeSurface()
        surface.drawingsVisible = false
        let server = try await startServer(surface: surface)
        defer { server.stop() }
        let (_, response) = try await postJSON(path: "/drawings/show", body: Data(), port: server.boundPort ?? 0)
        #expect(response.statusCode == 200)
        #expect(surface.drawingsVisible == true)
    }

    @Test("GET /state includes color, width, drawingsVisible")
    func stateIncludesToolbarFields() async throws {
        let surface = FakeSurface()
        surface.currentColor = RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1)
        surface.currentWidth = 7
        surface.drawingsVisible = false
        let server = try await startServer(surface: surface)
        defer { server.stop() }
        let (data, response) = try await get(path: "/state", port: server.boundPort ?? 0)
        #expect(response.statusCode == 200)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let color = try #require(json["color"] as? [String: Any])
        #expect(color["r"] as? Double == 0.5)
        #expect(json["width"] as? Double == 7)
        #expect(json["drawingsVisible"] as? Bool == false)
    }
}
```

You'll need `FakeSurface`, `startServer`, `postJSON`, `get` helpers. These already exist somewhere under `Tests/DevHTTPTests/` — find them with `grep -rn "FakeSurface\|startServer\|postJSON" Tests/DevHTTPTests/` and reuse. If `FakeSurface` doesn't already have `currentColor` / `currentWidth` / `drawingsVisible` storage, add them there too (it's a test double; add mutable vars).

Also extend the existing `/state` route test (in `Tests/DevHTTPTests/RouteTests/`) to include assertions for the three new fields, mirroring the test above.

- [ ] **Step 2: Run tests, expect failure**

Run `just test`. Should fail to build: `currentColor` etc. don't exist on `DevHTTPSurface`.

- [ ] **Step 3: Extend `DevHTTPSurface`**

In `Sources/DevHTTP/DevHTTPSurface.swift`, add inside the protocol body (after the existing properties):

```swift
    var currentColor: RGBA { get }
    var currentWidth: Double { get }
    var drawingsVisible: Bool { get }
    func setColor(_ color: RGBA)
    func setWidth(_ width: Double)
    func setDrawingsVisible(_ visible: Bool)
```

- [ ] **Step 4: Implement on `FitiDevHTTPSurface`**

In `Sources/App/FitiDevHTTPSurface.swift`, add:

```swift
    public var currentColor: RGBA { controller.currentColor }
    public var currentWidth: Double { controller.currentWidth }
    public var drawingsVisible: Bool { controller.drawingsVisible }

    public func setColor(_ color: RGBA) { controller.currentColor = color }
    public func setWidth(_ width: Double) { controller.currentWidth = width }
    public func setDrawingsVisible(_ visible: Bool) { controller.drawingsVisible = visible }
```

- [ ] **Step 5: Add routes**

In `Sources/DevHTTP/DevHTTPServer.swift`, find `installRoutes()`. After the existing route registrations, add:

```swift
        router.add("POST", "/color") { [weak self] req, _ in
            guard let self else { return .notFound() }
            return self.handleSetColor(req)
        }

        router.add("POST", "/width") { [weak self] req, _ in
            guard let self else { return .notFound() }
            return self.handleSetWidth(req)
        }

        router.add("POST", "/drawings/show") { [weak self] _, _ in
            self?.surface.setDrawingsVisible(true)
            return .ok()
        }

        router.add("POST", "/drawings/hide") { [weak self] _, _ in
            self?.surface.setDrawingsVisible(false)
            return .ok()
        }
```

And add the corresponding handlers (modeled after the existing `handlePointer`):

```swift
    @MainActor
    private func handleSetColor(_ req: HTTPRequest) -> HTTPResponse {
        guard let json = try? JSONSerialization.jsonObject(with: req.body) as? [String: Any],
              let r = (json["r"] as? Double) ?? (json["r"] as? Int).map(Double.init),
              let g = (json["g"] as? Double) ?? (json["g"] as? Int).map(Double.init),
              let b = (json["b"] as? Double) ?? (json["b"] as? Int).map(Double.init),
              let a = (json["a"] as? Double) ?? (json["a"] as? Int).map(Double.init) else {
            return .badRequest("expected {r, g, b, a} body, each in 0..1")
        }
        surface.setColor(RGBA(r: r, g: g, b: b, a: a))
        return .ok()
    }

    @MainActor
    private func handleSetWidth(_ req: HTTPRequest) -> HTTPResponse {
        guard let json = try? JSONSerialization.jsonObject(with: req.body) as? [String: Any],
              let w = (json["width"] as? Double) ?? (json["width"] as? Int).map(Double.init) else {
            return .badRequest("expected {width: Double} body")
        }
        surface.setWidth(w)
        return .ok()
    }
```

Extend the existing `/state` handler payload (in the same file, search for `router.add("GET", "/state")`) to include:

```swift
                "color": ["r": self.surface.currentColor.r,
                          "g": self.surface.currentColor.g,
                          "b": self.surface.currentColor.b,
                          "a": self.surface.currentColor.a],
                "width": self.surface.currentWidth,
                "drawingsVisible": self.surface.drawingsVisible,
```

- [ ] **Step 6: Add justfile recipes**

In `justfile`, in the `[group('inspect')]` section, add:

```just
[group('inspect')]
inspect-set-color r g b a:
    @curl -sf -X POST localhost:{{dev_port}}/color \
        -H 'Content-Type: application/json' \
        -d '{"r":{{r}},"g":{{g}},"b":{{b}},"a":{{a}}}'

[group('inspect')]
inspect-set-width w:
    @curl -sf -X POST localhost:{{dev_port}}/width \
        -H 'Content-Type: application/json' \
        -d '{"width":{{w}}}'

[group('inspect')]
inspect-show:
    @curl -sf -X POST localhost:{{dev_port}}/drawings/show

[group('inspect')]
inspect-hide:
    @curl -sf -X POST localhost:{{dev_port}}/drawings/hide
```

- [ ] **Step 7: Run tests, expect pass**

Run `just test`. Should report 93 tests pass (88 prior + 5 new in DevHTTPTests).

- [ ] **Step 8: Commit**

```bash
git add Sources/DevHTTP/DevHTTPSurface.swift Sources/App/FitiDevHTTPSurface.swift Sources/DevHTTP/DevHTTPServer.swift Tests/DevHTTPTests/RouteTests/ToolbarRouteTests.swift justfile Tests/DevHTTPTests/RouteTests/
git commit -m "$(cat <<'EOF'
Dev HTTP: expose color / width / drawingsVisible

DevHTTPSurface gains three getters + three setters; FitiDevHTTPSurface
passes through to AppController. New routes POST /color, /width,
/drawings/show, /drawings/hide. GET /state payload extends with the
three new fields.

just inspect-set-color / inspect-set-width / inspect-show /
inspect-hide recipes mirror the routes. The hexagonal contract holds:
HTTP and the (forthcoming) toolbar widgets read/write the same Core
state via the same callback hooks.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: CanvasView — short-circuit when drawingsVisible is false

**Files:**
- Modify: `Sources/AppKit/CanvasView.swift`
- Create: `Tests/AppKitTests/CanvasViewVisibilityTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/AppKitTests/CanvasViewVisibilityTests.swift`:

```swift
// ABOUTME: Tests for CanvasView.drawingsVisible — short-circuits draw(_:) when
// ABOUTME: false so hide/show on the toolbar produces a transparent overlay
// ABOUTME: without disturbing the underlying document.

import AppKit
import Testing

@Suite("CanvasView drawingsVisible")
@MainActor
struct CanvasViewVisibilityTests {
    @Test("strokes render normally when drawingsVisible is true")
    func renderWhenVisible() throws {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        let stroke = Stroke(id: "a", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 4,
                            transform: .identity,
                            points: [StrokePoint(x: 10, y: 5), StrokePoint(x: 40, y: 5)],
                            pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        view.render(RenderFrame(strokes: [stroke], inProgress: nil,
                                canvasSize: Size(width: 50, height: 50)))
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let top = try #require(rep.colorAt(x: 25, y: 5))
        #expect(top.redComponent > 0.5)
    }

    @Test("draw produces a transparent overlay when drawingsVisible is false")
    func hiddenWhenInvisible() throws {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        let stroke = Stroke(id: "a", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 4,
                            transform: .identity,
                            points: [StrokePoint(x: 10, y: 5), StrokePoint(x: 40, y: 5)],
                            pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        view.render(RenderFrame(strokes: [stroke], inProgress: nil,
                                canvasSize: Size(width: 50, height: 50)))
        view.drawingsVisible = false
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let pixel = try #require(rep.colorAt(x: 25, y: 5))
        #expect(pixel.alphaComponent < 0.01, "pixel should be transparent when hidden")
    }
}
```

- [ ] **Step 2: Run integration tests, expect failure**

Run `just test-integration`. Should fail: `drawingsVisible` does not exist on `CanvasView`.

- [ ] **Step 3: Update CanvasView**

In `Sources/AppKit/CanvasView.swift`, immediately after the `committedSignature` declaration, add:

```swift
    public var drawingsVisible: Bool = true {
        didSet {
            if oldValue != drawingsVisible { needsDisplay = true }
        }
    }
```

At the top of `draw(_:)`, after the existing context/frame guards, add:

```swift
        guard drawingsVisible else { return }
```

- [ ] **Step 4: Run integration tests, expect pass**

Run `just test-integration`. Verify the new tests pass; total count grows by 2 plus the carryover from CoreTests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/CanvasView.swift Tests/AppKitTests/CanvasViewVisibilityTests.swift
git commit -m "$(cat <<'EOF'
CanvasView: short-circuit draw when drawingsVisible is false

A single guard at the top of draw(_:) skips both the committed bake
blit and the in-progress overlay when the user has hidden marks.
Strokes stay in the document untouched.

didSet on drawingsVisible flips needsDisplay so the panel redraws
immediately on toggle.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: ToolbarController scaffold — panel + visibility hook

**Files:**
- Create: `Sources/AppKit/ToolbarController.swift`
- Create: `Sources/AppKit/ToolbarPanel.swift`
- Create: `Tests/AppKitTests/ToolbarControllerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/AppKitTests/ToolbarControllerTests.swift`:

```swift
// ABOUTME: Tests for ToolbarController — verifies the floating panel shows on
// ABOUTME: activation, hides on deactivation, and (later) widgets write through
// ABOUTME: to AppController state.

import AppKit
import Testing

@Suite("ToolbarController")
@MainActor
struct ToolbarControllerTests {
    // swiftlint:disable:next large_tuple
    private func make() -> (ToolbarController, AppController, Editor) {
        let window = RecordingWindow()
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(editor: editor, window: window)
        let toolbar = ToolbarController(controller: controller,
                                        defaults: UserDefaults(suiteName: UUID().uuidString)!)
        return (toolbar, controller, editor)
    }

    @Test("panel is hidden on init")
    func hiddenOnInit() {
        let (toolbar, _, _) = make()
        #expect(toolbar.panel.isVisible == false)
    }

    @Test("updateVisibility shows the panel when mode is not .inactive")
    func showsWhenActive() {
        let (toolbar, _, _) = make()
        toolbar.updateVisibility(for: .activeIdle)
        #expect(toolbar.panel.isVisible == true)
    }

    @Test("updateVisibility hides the panel when mode is .inactive")
    func hidesWhenInactive() {
        let (toolbar, _, _) = make()
        toolbar.updateVisibility(for: .activeIdle)
        toolbar.updateVisibility(for: .inactive)
        #expect(toolbar.panel.isVisible == false)
    }
}
```

The `updateVisibility(for:)` method is public so `main.swift` can call it after composing `onModeChanged` with the menubar's existing handler. The controller does NOT assign `controller.onModeChanged` in init — that's main.swift's job, to avoid clobbering the menubar's handler.

- [ ] **Step 2: Run tests, expect failure**

Run `just test-integration`. Should fail: `ToolbarController` does not exist.

- [ ] **Step 3: Create `ToolbarPanel.swift`**

```swift
// ABOUTME: NSPanel subclass for the fiti toolbar — nonactivating so clicks
// ABOUTME: don't steal focus from the underlying app being presented to.

import AppKit

public final class ToolbarPanel: NSPanel {
    public init() {
        let initialRect = NSRect(x: 24, y: 24, width: 60, height: 320)
        super.init(contentRect: initialRect,
                   styleMask: [.titled, .nonactivatingPanel, .utilityWindow],
                   backing: .buffered,
                   defer: false)
        self.level = .floating
        self.hidesOnDeactivate = false
        self.isFloatingPanel = true
        self.title = "fiti"
        self.setFrameAutosaveName("fiti.toolbar")
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
    }
}
```

- [ ] **Step 4: Create `ToolbarController.swift`** (scaffold only — widgets in Task 5)

```swift
// ABOUTME: Floating toolbar that appears when fiti activates. Owns color /
// ABOUTME: width / opacity / hide controls; writes through to AppController.

import AppKit

@MainActor
public final class ToolbarController: NSObject {
    private let controller: AppController
    private let defaults: UserDefaults
    internal let panel: ToolbarPanel

    public init(controller: AppController, defaults: UserDefaults = .standard) {
        self.controller = controller
        self.defaults = defaults
        self.panel = ToolbarPanel()
        super.init()
        updateVisibility(for: controller.mode)
    }

    public func updateVisibility(for mode: AppController.Mode) {
        if mode == .inactive {
            panel.orderOut(nil)
        } else {
            panel.orderFront(nil)
        }
    }
}
```

- [ ] **Step 5: Run integration tests, expect pass**

Run `just test-integration`. New tests should pass; total grows by 3.

- [ ] **Step 6: Commit**

```bash
git add Sources/AppKit/ToolbarController.swift Sources/AppKit/ToolbarPanel.swift Tests/AppKitTests/ToolbarControllerTests.swift
git commit -m "$(cat <<'EOF'
Add ToolbarController scaffold with show/hide hook

Nonactivating NSPanel that floats above other windows. No widgets
yet — just the panel, its frame autosave name, and an
updateVisibility(for:) hook that main.swift will compose with the
menubar's onModeChanged handler in a later commit.

Public updateVisibility hook keeps onModeChanged as a single-
subscriber callback (matching today's contract) while letting both
menubar and toolbar react. main.swift composes the handlers.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: ToolbarController widgets + persistence + external-write sync

**Files:**
- Modify: `Sources/AppKit/ToolbarController.swift`
- Modify: `Tests/AppKitTests/ToolbarControllerTests.swift`

The bulk of the work. Build the vertical stack of widgets, wire actions to `controller` setters, load/save `UserDefaults`, subscribe to `onCurrentColorChanged` / `onCurrentWidthChanged` / `onDrawingsVisibilityChanged` so HTTP-driven writes update the widgets too.

- [ ] **Step 1: Append failing tests for widgets + external sync**

Append to `Tests/AppKitTests/ToolbarControllerTests.swift` (before the struct's closing brace):

```swift
    @Test("clicking a quick-pick color sets controller.currentColor RGB but preserves alpha")
    func quickPickPreservesAlpha() throws {
        let (toolbar, controller, _) = make()
        controller.currentColor = RGBA(r: 0, g: 0, b: 0, a: 0.5)
        try toolbar.testOnly_clickQuickPick(at: 1)
        #expect(controller.currentColor.r == 134.0 / 255.0)
        #expect(controller.currentColor.g == 142.0 / 255.0)
        #expect(controller.currentColor.b == 150.0 / 255.0)
        #expect(controller.currentColor.a == 0.5, "alpha should be preserved")
    }

    @Test("opacity slider writes controller.currentColor.a but preserves rgb")
    func opacityPreservesRGB() {
        let (toolbar, controller, _) = make()
        controller.currentColor = RGBA(r: 0.2, g: 0.4, b: 0.6, a: 1.0)
        toolbar.testOnly_setOpacity(0.3)
        #expect(controller.currentColor.a == 0.3)
        #expect(controller.currentColor.r == 0.2)
        #expect(controller.currentColor.g == 0.4)
        #expect(controller.currentColor.b == 0.6)
    }

    @Test("width slider writes controller.currentWidth")
    func widthSlider() {
        let (toolbar, controller, _) = make()
        toolbar.testOnly_setWidth(12)
        #expect(controller.currentWidth == 12)
    }

    @Test("hide button toggles controller.drawingsVisible")
    func hideButton() {
        let (toolbar, controller, _) = make()
        #expect(controller.drawingsVisible == true)
        toolbar.testOnly_toggleHide()
        #expect(controller.drawingsVisible == false)
        toolbar.testOnly_toggleHide()
        #expect(controller.drawingsVisible == true)
    }

    @Test("persisted color/width override defaults at init")
    func persistedOverrides() {
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        suite.set(0.1, forKey: "fiti.color.r")
        suite.set(0.2, forKey: "fiti.color.g")
        suite.set(0.3, forKey: "fiti.color.b")
        suite.set(0.4, forKey: "fiti.color.a")
        suite.set(11.0, forKey: "fiti.width")
        let window = RecordingWindow()
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(editor: editor, window: window)
        _ = ToolbarController(controller: controller, defaults: suite)
        #expect(controller.currentColor == RGBA(r: 0.1, g: 0.2, b: 0.3, a: 0.4))
        #expect(controller.currentWidth == 11)
    }

    @Test("widget changes write through to UserDefaults")
    func widgetChangesPersist() {
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        let window = RecordingWindow()
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(editor: editor, window: window)
        let toolbar = ToolbarController(controller: controller, defaults: suite)
        toolbar.testOnly_setWidth(9)
        toolbar.testOnly_setOpacity(0.6)
        #expect(suite.double(forKey: "fiti.width") == 9)
        #expect(suite.double(forKey: "fiti.color.a") == 0.6)
    }

    @Test("external write to currentColor updates the color well")
    func externalColorWriteUpdatesWidget() {
        let (toolbar, controller, _) = make()
        controller.currentColor = RGBA(r: 0.0, g: 1.0, b: 0.0, a: 1.0)
        let c = toolbar.testOnly_colorWellColor
        #expect(abs(c.redComponent - 0.0) < 0.01)
        #expect(abs(c.greenComponent - 1.0) < 0.01)
        #expect(abs(c.blueComponent - 0.0) < 0.01)
    }

    @Test("external write to currentWidth updates the width slider")
    func externalWidthWriteUpdatesWidget() {
        let (toolbar, controller, _) = make()
        controller.currentWidth = 17
        #expect(toolbar.testOnly_widthSliderValue == 17)
    }

    @Test("external write to drawingsVisible updates the hide button glyph")
    func externalHideWriteUpdatesGlyph() {
        let (toolbar, controller, _) = make()
        controller.drawingsVisible = false
        #expect(toolbar.testOnly_hideButtonGlyphName == "eye.slash")
        controller.drawingsVisible = true
        #expect(toolbar.testOnly_hideButtonGlyphName == "eye")
    }
```

- [ ] **Step 2: Run tests, expect failure**

Run `just test-integration`. Should fail to build.

- [ ] **Step 3: Expand ToolbarController**

REPLACE the entire contents of `Sources/AppKit/ToolbarController.swift` with:

```swift
// ABOUTME: Floating toolbar that appears when fiti activates. Owns color /
// ABOUTME: width / opacity / hide controls; writes through to AppController.

import AppKit

@MainActor
public final class ToolbarController: NSObject {
    private let controller: AppController
    private let defaults: UserDefaults
    internal let panel: ToolbarPanel

    private let colorWell: NSColorWell
    private let widthSlider: NSSlider
    private let opacitySlider: NSSlider
    private let hideButton: NSButton
    private var quickPickButtons: [NSButton] = []

    /// 8 quick-pick colors from `../scratch/scratch/packages/web/src/ui/Toolbar.tsx`.
    /// RGB only — alpha is taken from the user's current opacity at click time.
    private static let quickPickRGB: [(r: Double, g: Double, b: Double)] = [
        (0.0, 0.0, 0.0),
        (134.0 / 255.0, 142.0 / 255.0, 150.0 / 255.0),
        (224.0 / 255.0,  49.0 / 255.0,  49.0 / 255.0),
        (247.0 / 255.0, 103.0 / 255.0,   7.0 / 255.0),
        (245.0 / 255.0, 159.0 / 255.0,   0.0),
        ( 47.0 / 255.0, 158.0 / 255.0,  68.0 / 255.0),
        ( 25.0 / 255.0, 113.0 / 255.0, 194.0 / 255.0),
        (156.0 / 255.0,  54.0 / 255.0, 181.0 / 255.0)
    ]

    public init(controller: AppController, defaults: UserDefaults = .standard) {
        self.controller = controller
        self.defaults = defaults
        self.panel = ToolbarPanel()
        self.colorWell = NSColorWell()
        self.widthSlider = NSSlider(value: controller.currentWidth, minValue: 1, maxValue: 20, target: nil, action: nil)
        self.opacitySlider = NSSlider(value: controller.currentColor.a, minValue: 0, maxValue: 1, target: nil, action: nil)
        self.hideButton = NSButton(title: "", target: nil, action: nil)
        super.init()

        loadPersistedState()
        buildContent()
        updateVisibility(for: controller.mode)

        // React to external writes (HTTP, other adapters) — keep widgets in sync.
        controller.onCurrentColorChanged = { [weak self] color in
            self?.syncColorWidgets(with: color)
        }
        controller.onCurrentWidthChanged = { [weak self] width in
            self?.widthSlider.doubleValue = width
        }
        controller.onDrawingsVisibilityChanged = { [weak self] visible in
            self?.updateHideButtonGlyph(visible: visible)
        }
    }

    public func updateVisibility(for mode: AppController.Mode) {
        if mode == .inactive {
            panel.orderOut(nil)
        } else {
            panel.orderFront(nil)
        }
    }

    private func syncColorWidgets(with color: RGBA) {
        colorWell.color = NSColor(red: CGFloat(color.r), green: CGFloat(color.g),
                                  blue: CGFloat(color.b), alpha: CGFloat(color.a))
        opacitySlider.doubleValue = color.a
    }

    private func buildContent() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let pen = NSButton(title: "", target: nil, action: nil)
        pen.image = NSImage(systemSymbolName: "pencil.tip", accessibilityDescription: "Pen")
        pen.imagePosition = .imageOnly
        pen.bezelStyle = .regularSquare
        pen.state = .on
        pen.isEnabled = false
        stack.addArrangedSubview(pen)

        for rowStart in stride(from: 0, to: Self.quickPickRGB.count, by: 2) {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 4
            for offset in 0..<2 where rowStart + offset < Self.quickPickRGB.count {
                let i = rowStart + offset
                let rgb = Self.quickPickRGB[i]
                let btn = NSButton(title: "", target: self, action: #selector(colorClicked(_:)))
                btn.tag = i
                btn.bezelStyle = .regularSquare
                btn.image = makeSwatchImage(r: rgb.r, g: rgb.g, b: rgb.b)
                btn.imagePosition = .imageOnly
                quickPickButtons.append(btn)
                row.addArrangedSubview(btn)
            }
            stack.addArrangedSubview(row)
        }

        colorWell.target = self
        colorWell.action = #selector(customColorChanged(_:))
        colorWell.color = NSColor(red: CGFloat(controller.currentColor.r),
                                  green: CGFloat(controller.currentColor.g),
                                  blue: CGFloat(controller.currentColor.b),
                                  alpha: CGFloat(controller.currentColor.a))
        stack.addArrangedSubview(colorWell)

        widthSlider.target = self
        widthSlider.action = #selector(widthChanged(_:))
        widthSlider.doubleValue = controller.currentWidth
        stack.addArrangedSubview(label("w"))
        stack.addArrangedSubview(widthSlider)

        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged(_:))
        opacitySlider.doubleValue = controller.currentColor.a
        stack.addArrangedSubview(label("o"))
        stack.addArrangedSubview(opacitySlider)

        hideButton.target = self
        hideButton.action = #selector(toggleHide(_:))
        hideButton.bezelStyle = .regularSquare
        hideButton.imagePosition = .imageOnly
        updateHideButtonGlyph(visible: controller.drawingsVisible)
        stack.addArrangedSubview(hideButton)

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        panel.contentView = container
    }

    private func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 10)
        l.alignment = .center
        return l
    }

    private func makeSwatchImage(r: Double, g: Double, b: Double) -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 3, yRadius: 3).fill()
        img.unlockFocus()
        return img
    }

    internal private(set) var currentHideGlyphName: String = "eye"

    private func updateHideButtonGlyph(visible: Bool) {
        let name = visible ? "eye" : "eye.slash"
        currentHideGlyphName = name
        hideButton.image = NSImage(systemSymbolName: name, accessibilityDescription: visible ? "Hide" : "Show")
    }

    // MARK: - Actions

    @objc private func colorClicked(_ sender: NSButton) {
        let rgb = Self.quickPickRGB[sender.tag]
        let a = controller.currentColor.a
        controller.currentColor = RGBA(r: rgb.r, g: rgb.g, b: rgb.b, a: a)
        persistColor()
    }

    @objc private func customColorChanged(_ sender: NSColorWell) {
        let c = sender.color
        let a = controller.currentColor.a
        controller.currentColor = RGBA(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent), a: a)
        persistColor()
    }

    @objc private func widthChanged(_ sender: NSSlider) {
        controller.currentWidth = sender.doubleValue
        defaults.set(controller.currentWidth, forKey: "fiti.width")
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        let c = controller.currentColor
        controller.currentColor = RGBA(r: c.r, g: c.g, b: c.b, a: sender.doubleValue)
        persistColor()
    }

    @objc private func toggleHide(_ sender: NSButton) {
        controller.drawingsVisible.toggle()
    }

    // MARK: - Persistence

    private func loadPersistedState() {
        if let r = defaults.object(forKey: "fiti.color.r") as? Double,
           let g = defaults.object(forKey: "fiti.color.g") as? Double,
           let b = defaults.object(forKey: "fiti.color.b") as? Double,
           let a = defaults.object(forKey: "fiti.color.a") as? Double {
            controller.currentColor = RGBA(r: r, g: g, b: b, a: a)
        }
        if let w = defaults.object(forKey: "fiti.width") as? Double {
            controller.currentWidth = w
        }
    }

    private func persistColor() {
        let c = controller.currentColor
        defaults.set(c.r, forKey: "fiti.color.r")
        defaults.set(c.g, forKey: "fiti.color.g")
        defaults.set(c.b, forKey: "fiti.color.b")
        defaults.set(c.a, forKey: "fiti.color.a")
    }

    // MARK: - Test hooks

    internal func testOnly_clickQuickPick(at index: Int) throws {
        guard index < quickPickButtons.count else { throw TestOnlyError.outOfRange }
        colorClicked(quickPickButtons[index])
    }

    internal func testOnly_setWidth(_ value: Double) {
        widthSlider.doubleValue = value
        widthChanged(widthSlider)
    }

    internal func testOnly_setOpacity(_ value: Double) {
        opacitySlider.doubleValue = value
        opacityChanged(opacitySlider)
    }

    internal func testOnly_toggleHide() {
        toggleHide(hideButton)
    }

    internal var testOnly_colorWellColor: NSColor { colorWell.color }
    internal var testOnly_widthSliderValue: Double { widthSlider.doubleValue }
    internal var testOnly_hideButtonGlyphName: String { currentHideGlyphName }
}

internal enum TestOnlyError: Error { case outOfRange }
```

- [ ] **Step 4: Run integration tests, expect pass**

Run `just test-integration`. Total grows by 9.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/ToolbarController.swift Tests/AppKitTests/ToolbarControllerTests.swift
git commit -m "$(cat <<'EOF'
ToolbarController: widgets, persistence, external-write sync

Eight quick-pick color swatches in a 2×4 grid, NSColorWell, width and
opacity sliders, hide/show button with eye / eye.slash glyph swap.
Pen tool is a disabled visual placeholder.

Quick-pick clicks preserve current alpha; opacity slider preserves
r/g/b. Widget changes write through UserDefaults (fiti.* keys), and
the controller reads persisted values at init.

The toolbar also subscribes to controller.onCurrentColorChanged /
onCurrentWidthChanged / onDrawingsVisibilityChanged, so HTTP-driven
changes (POST /color, /width, /drawings/show|hide, set via
`just inspect-*`) update the widgets too. The hexagonal contract
holds at the test boundary.

testOnly_* hooks let the tests simulate widget actions and inspect
widget state without synthesising NSEvents.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Wire into main.swift + compose handlers across adapters

**Files:**
- Modify: `Sources/App/main.swift`

`AppController` has three single-subscriber callbacks (`onModeChanged`, `onCurrentColorChanged` etc., `onCurrentWidthChanged`, `onDrawingsVisibilityChanged`). Today's menubar wires `onModeChanged`. Toolbar's init wires `onCurrentColorChanged` / `onCurrentWidthChanged` / `onDrawingsVisibilityChanged`. We need:

- `onModeChanged` to drive BOTH the menubar (icon swap) and the toolbar (panel show/hide)
- `onDrawingsVisibilityChanged` to drive BOTH the toolbar (eye glyph) and the canvas (suppress drawing)

Compose in main.swift.

- [ ] **Step 1: Add stored property + instantiation + composition**

In `Sources/App/main.swift`, on `FitiAppDelegate`, immediately after `var menubar: MenubarController!`:

```swift
    var toolbar: ToolbarController!
```

Inside `applicationDidFinishLaunching`, immediately after the existing line:

```swift
        menubar = MenubarController(controller: controller, editor: editor)
```

add:

```swift
        toolbar = ToolbarController(controller: controller)

        // Compose onModeChanged: menubar (icon) + toolbar (panel visibility).
        let menubarModeHandler = controller.onModeChanged
        controller.onModeChanged = { [weak self] mode in
            menubarModeHandler?(mode)
            self?.toolbar.updateVisibility(for: mode)
        }

        // Compose onDrawingsVisibilityChanged: toolbar (eye glyph) + canvas
        // (suppress drawing). The toolbar set this in its init; we wrap.
        let toolbarVisibilityHandler = controller.onDrawingsVisibilityChanged
        controller.onDrawingsVisibilityChanged = { [weak self] visible in
            toolbarVisibilityHandler?(visible)
            self?.canvas.drawingsVisible = visible
        }
```

- [ ] **Step 2: Run the full check**

Run `just check`. Both unit and integration suites pass, lint clean, build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/App/main.swift
git commit -m "$(cat <<'EOF'
main: wire ToolbarController and compose multi-adapter callbacks

Instantiate the toolbar after the menubar, then compose
controller.onModeChanged so both menubar (icon swap) and toolbar
(panel show/hide) fire. Same composition for
onDrawingsVisibilityChanged: toolbar (eye glyph) + CanvasView
(suppress drawing).

AppController's single-subscriber callback contract is preserved;
main.swift is the only place that knows about multiple adapters,
which is the right division of responsibility.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Manual smoke test

No code changes. Run through both the UI flow AND the HTTP-driven flow to verify hexagonal cohesion.

- [ ] **Step 1: Fresh launch**

```
just stop && just install && just run-bg
```

Expected: menubar icon outlined; no toolbar visible.

- [ ] **Step 2: Activate via menubar**

Click menubar → Activate.

Expected: menubar icon fills, toolbar panel appears at bottom-left. Color well shows red, width slider at 6, opacity slider at 80%, eye glyph.

- [ ] **Step 3: Draw with default**

Click and drag. Expected: red, translucent, width-6 stroke.

- [ ] **Step 4: Pick a different color, then change opacity**

Click blue swatch → drag opacity to ~30%. Expected: next stroke is blue at ~30%. Previously-drawn red stays at 80%.

- [ ] **Step 5: Inspect via HTTP**

`just inspect-state | jq '.color, .width, .drawingsVisible'`

Expected: shows the current blue (r/g/b ≈ 0.10/0.44/0.76), a ≈ 0.3, width 6, drawingsVisible true.

- [ ] **Step 6: Drive from HTTP, observe widgets update**

`just inspect-set-color 0 1 0 0.5` (green at 50%)

Expected: the color well in the toolbar switches to green; opacity slider moves to 50%. Drawing a stroke produces green at 50%.

- [ ] **Step 7: Width via HTTP**

`just inspect-set-width 15`

Expected: width slider moves to 15. Next stroke is thicker.

- [ ] **Step 8: Hide via HTTP**

`just inspect-hide`

Expected: all visible strokes disappear; eye glyph in toolbar swaps to eye.slash. Drawing during this state still adds strokes to the doc (verify with `just inspect-doc | jq '.strokeOrder | length'`).

- [ ] **Step 9: Show via toolbar button**

Click the eye.slash button in the toolbar.

Expected: strokes reappear; glyph swaps back to eye.

- [ ] **Step 10: Deactivate + reactivate**

Press Esc → toolbar hides, menubar icon outlines. Press Cmd+Opt+Z → toolbar reappears at same position, widget values preserved.

- [ ] **Step 11: Quit and relaunch**

Click menubar → Quit fiti. Then `just run-bg`. Activate.

Expected: toolbar at same position. Color/width/opacity restored from UserDefaults. Strokes from prior session NOT restored (no doc persistence yet).

- [ ] **Step 12: Move the toolbar**

Drag toolbar's title bar. Quit. Relaunch. Activate.

Expected: toolbar at new position.

---

## Self-review checklist

After all tasks complete:

- [ ] `just check` passes end-to-end
- [ ] All 12 smoke steps pass
- [ ] HTTP routes exercised both via `just inspect-*` recipes and from the toolbar widgets; widgets update on HTTP writes and HTTP `/state` reflects widget writes
- [ ] `Sources/Core/` still has no AppKit imports (`just lint` enforces)
- [ ] The previous menubar smoke checklist still passes
- [ ] No new files have `// TODO` or `// FIXME` markers
- [ ] `internal` (not `public`) on `testOnly_*` helpers
- [ ] `UserDefaults.standard` is the default in production wiring; tests use `UserDefaults(suiteName:)` instances
- [ ] No regressions in `just test` count (only additions)
