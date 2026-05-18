# fiti Preferences + Launch-at-Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a Preferences window with a rebindable activation-hotkey recorder and a launch-at-login toggle, opened from a new "Preferences..." menubar item (Cmd+,).

**Architecture:** Hexagonal — new `LaunchAtLogin` port in `Sources/Core/Ports/` keeps `ServiceManagement` out of Core. AppKit adapter `SMAppServiceLaunchAtLogin` wraps `SMAppService.mainApp`. New `PreferencesController` owns an `NSWindow` (not panel) hosting `KeyboardShortcuts.RecorderCocoa` + `NSSwitch`. `MenubarController` gains one closure parameter `onOpenPreferences` so it doesn't depend on the concrete `PreferencesController`.

**Tech Stack:** Swift 6, AppKit, Swift Testing, sindresorhus/KeyboardShortcuts, ServiceManagement (macOS 13+). No SwiftUI.

**Source of truth:** `docs/specs/2026-05-18-fiti-preferences-design.md`.

---

## File map

| File | Responsibility | Status |
| --- | --- | --- |
| `Sources/Core/Ports/LaunchAtLogin.swift` | `LaunchAtLogin` protocol + `LaunchAtLoginStatus` enum | create (Task 1) |
| `Tests/CoreTests/Doubles/RecordingLaunchAtLogin.swift` | Test double for the port | create (Task 1) |
| `Tests/CoreTests/LaunchAtLoginTests.swift` | Tests for the recording double | create (Task 1) |
| `Sources/AppKit/SMAppServiceLaunchAtLogin.swift` | Real adapter wrapping `SMAppService.mainApp` | create (Task 2) |
| `Sources/AppKit/PreferencesWindow.swift` | `NSWindow` subclass with title + autosave | create (Task 3) |
| `Sources/AppKit/PreferencesController.swift` | Owns the window, builds content, wires actions | create (Tasks 4-6) |
| `Tests/AppKitTests/PreferencesControllerTests.swift` | Tests for the controller | create (Tasks 4-6) |
| `Sources/AppKit/MenubarController.swift` | Add "Preferences..." menu item + `onOpenPreferences` arg | modify (Task 7) |
| `Tests/AppKitTests/MenubarControllerTests.swift` | Add Preferences-item tests | modify (Task 7) |
| `Sources/App/main.swift` | Construct adapter + controller + wire menubar | modify (Task 7) |

---

### Task 1: `LaunchAtLogin` port, status enum, and recording double

Establish the port and the test double in one TDD slice. The double is what every downstream test will use; the real adapter is not unit-tested.

**Files:**
- Create: `Sources/Core/Ports/LaunchAtLogin.swift`
- Create: `Tests/CoreTests/Doubles/RecordingLaunchAtLogin.swift`
- Create: `Tests/CoreTests/LaunchAtLoginTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CoreTests/LaunchAtLoginTests.swift`:

```swift
// ABOUTME: Tests for the RecordingLaunchAtLogin double — covers the initial
// ABOUTME: state, status transitions on setEnabled, throwing path, and approval simulation.

import Testing

@Suite("RecordingLaunchAtLogin")
@MainActor
struct LaunchAtLoginTests {
    @Test("initial state is disabled and available")
    func initialState() {
        let lal = RecordingLaunchAtLogin()
        #expect(lal.isAvailable == true)
        #expect(lal.status == .disabled)
    }

    @Test("setEnabled(true) moves status to enabled")
    func enableMovesToEnabled() throws {
        let lal = RecordingLaunchAtLogin()
        try lal.setEnabled(true)
        #expect(lal.status == .enabled)
    }

    @Test("setEnabled(false) moves status back to disabled")
    func disableMovesToDisabled() throws {
        let lal = RecordingLaunchAtLogin()
        try lal.setEnabled(true)
        try lal.setEnabled(false)
        #expect(lal.status == .disabled)
    }

    @Test("simulateApprovalRequired makes setEnabled(true) land in requiresApproval")
    func approvalRequired() throws {
        let lal = RecordingLaunchAtLogin()
        lal.simulateApprovalRequired = true
        try lal.setEnabled(true)
        #expect(lal.status == .requiresApproval)
    }

    @Test("errorToThrow makes setEnabled throw and leaves status unchanged")
    func errorPath() {
        let lal = RecordingLaunchAtLogin()
        lal.errorToThrow = RecordingLaunchAtLoginError.synthetic
        #expect(throws: RecordingLaunchAtLoginError.synthetic) {
            try lal.setEnabled(true)
        }
        #expect(lal.status == .disabled)
    }

    @Test("isAvailable can be overridden to false")
    func unavailable() {
        let lal = RecordingLaunchAtLogin()
        lal.isAvailable = false
        #expect(lal.isAvailable == false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test`
Expected: compile error — `RecordingLaunchAtLogin`, `LaunchAtLoginStatus`, `RecordingLaunchAtLoginError` not found.

- [ ] **Step 3: Create the port file**

Create `Sources/Core/Ports/LaunchAtLogin.swift`:

```swift
// ABOUTME: Launch-at-login port. AppKit adapter wraps SMAppService.mainApp; tests
// ABOUTME: use RecordingLaunchAtLogin. Status enum decouples Core from ServiceManagement.

import Foundation

@MainActor
public protocol LaunchAtLogin: AnyObject {
    /// Whether the toggle should appear at all. False on platforms or
    /// configurations where SMAppService cannot find the bundle.
    var isAvailable: Bool { get }

    /// Current registration state, freshly read from the underlying service.
    var status: LaunchAtLoginStatus { get }

    /// Register (true) or unregister (false). Throws if the underlying
    /// service call fails. Callers surface the error in the UI and revert.
    func setEnabled(_ enabled: Bool) throws
}

public enum LaunchAtLoginStatus: Equatable, Sendable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable
}
```

- [ ] **Step 4: Create the recording double**

Create `Tests/CoreTests/Doubles/RecordingLaunchAtLogin.swift`:

```swift
// ABOUTME: In-memory LaunchAtLogin double for tests. Configurable errorToThrow
// ABOUTME: and simulateApprovalRequired flags drive the controller's failure paths.

import Foundation

@MainActor
public final class RecordingLaunchAtLogin: LaunchAtLogin {
    public var isAvailable: Bool = true
    public private(set) var status: LaunchAtLoginStatus = .disabled
    public var errorToThrow: Error?
    public var simulateApprovalRequired = false

    public init() {}

    public func setEnabled(_ enabled: Bool) throws {
        if let errorToThrow { throw errorToThrow }
        if enabled {
            status = simulateApprovalRequired ? .requiresApproval : .enabled
        } else {
            status = .disabled
        }
    }
}

public enum RecordingLaunchAtLoginError: Error, Equatable {
    case synthetic
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `just test`
Expected: all six tests in `LaunchAtLoginTests` pass; total suite count grows by 6.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Ports/LaunchAtLogin.swift \
        Tests/CoreTests/Doubles/RecordingLaunchAtLogin.swift \
        Tests/CoreTests/LaunchAtLoginTests.swift
git commit -m "$(cat <<'EOF'
Core: LaunchAtLogin port + RecordingLaunchAtLogin double

Port keeps ServiceManagement out of Core. Recording double covers the
controllable surface every downstream UI test needs: status transitions,
throwing path, requiresApproval simulation, availability override.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `SMAppServiceLaunchAtLogin` AppKit adapter

Real adapter wrapping `SMAppService.mainApp`. Not unit-testable (registering / unregistering with launchd is a real persistent side effect). Build-only verification here; manual smoke test deferred to Task 7's acceptance.

**Files:**
- Create: `Sources/AppKit/SMAppServiceLaunchAtLogin.swift`

- [ ] **Step 1: Create the adapter**

Create `Sources/AppKit/SMAppServiceLaunchAtLogin.swift`:

```swift
// ABOUTME: Real LaunchAtLogin adapter wrapping SMAppService.mainApp. Side effects
// ABOUTME: persist in the user's launchd; not unit-tested. Manual smoke test only.

import Foundation
import ServiceManagement

@MainActor
public final class SMAppServiceLaunchAtLogin: LaunchAtLogin {
    public init() {}

    public var isAvailable: Bool {
        SMAppService.mainApp.status != .notFound
    }

    public var status: LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered: return .disabled
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
```

- [ ] **Step 2: Verify the build still passes**

Run: `just build`
Expected: build succeeds. No new tests yet — the adapter is wired up in Task 7.

- [ ] **Step 3: Confirm lint is clean**

Run: `just lint`
Expected: no warnings or errors. The `import ServiceManagement` is in `Sources/AppKit/`, not Core — the `Sources/Core/` import-discipline grep should still pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/AppKit/SMAppServiceLaunchAtLogin.swift
git commit -m "$(cat <<'EOF'
AppKit: SMAppServiceLaunchAtLogin adapter for the LaunchAtLogin port

Wraps SMAppService.mainApp. Not unit-tested — registering with launchd
is a real persistent side effect. Smoke test covered in the Preferences
acceptance checklist.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `PreferencesWindow` shell

Plain `NSWindow` subclass with title, fixed size, autosave frame. No content — that arrives in Task 4. Splitting this out keeps the next tasks focused on behaviour, not window plumbing.

**Files:**
- Create: `Sources/AppKit/PreferencesWindow.swift`
- Create: `Tests/AppKitTests/PreferencesControllerTests.swift` (skeleton, exercises just the window for now)

- [ ] **Step 1: Write the failing test**

Create `Tests/AppKitTests/PreferencesControllerTests.swift`:

```swift
// ABOUTME: Tests for PreferencesController and its window — verifies window
// ABOUTME: identity, hotkey recorder binding, launch-at-login switch behaviour.

import AppKit
import Testing

@Suite("PreferencesWindow")
@MainActor
struct PreferencesWindowTests {
    @Test("window has the expected title")
    func windowTitle() {
        let window = PreferencesWindow()
        #expect(window.title == "fiti Preferences")
    }

    @Test("window is not resizable")
    func notResizable() {
        let window = PreferencesWindow()
        #expect(window.styleMask.contains(.resizable) == false)
    }

    @Test("window is not released when closed")
    func notReleasedWhenClosed() {
        let window = PreferencesWindow()
        #expect(window.isReleasedWhenClosed == false)
    }

    @Test("window uses the fiti.preferences autosave name")
    func autosaveName() {
        let window = PreferencesWindow()
        #expect(window.frameAutosaveName == "fiti.preferences")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test`
Expected: compile error — `PreferencesWindow` not found.

- [ ] **Step 3: Create the window subclass**

Create `Sources/AppKit/PreferencesWindow.swift`:

```swift
// ABOUTME: NSWindow subclass for fiti Preferences. Titled, non-resizable, has
// ABOUTME: a close button only; window survives close (isReleasedWhenClosed = false).

import AppKit

public final class PreferencesWindow: NSWindow {
    public init() {
        let initialRect = NSRect(x: 0, y: 0, width: 360, height: 140)
        super.init(contentRect: initialRect,
                   styleMask: [.titled, .closable],
                   backing: .buffered,
                   defer: false)
        self.title = "fiti Preferences"
        self.isReleasedWhenClosed = false
        self.setFrameAutosaveName("fiti.preferences")
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `just test`
Expected: four new tests in `PreferencesWindowTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/PreferencesWindow.swift \
        Tests/AppKitTests/PreferencesControllerTests.swift
git commit -m "$(cat <<'EOF'
AppKit: PreferencesWindow shell — titled, fixed-size, autosaved frame

NSWindow subclass that hosts the upcoming Preferences UI. Survives
close so reopening from the menubar works without reconstructing
content.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `PreferencesController` with the activation-hotkey recorder

Add the controller, render only the recorder row, and verify it is bound to `KeyboardShortcuts.Name.toggleActivation`. The launch-at-login switch and status field arrive in Tasks 5–6.

The controller's `init` already takes `launchAtLogin: LaunchAtLogin` even though this task only uses it for `show()`'s status refresh in Task 5 — passing it now avoids a signature churn in the next task.

**Files:**
- Create: `Sources/AppKit/PreferencesController.swift`
- Modify: `Tests/AppKitTests/PreferencesControllerTests.swift`

- [ ] **Step 1: Add the failing tests**

Append to `Tests/AppKitTests/PreferencesControllerTests.swift`:

```swift
import KeyboardShortcuts

@Suite("PreferencesController hotkey recorder")
@MainActor
struct PreferencesControllerHotkeyTests {
    @Test("controller has a recorder bound to .toggleActivation")
    func recorderBinding() {
        let lal = RecordingLaunchAtLogin()
        let controller = PreferencesController(launchAtLogin: lal)
        #expect(controller.testOnly_recorder.shortcutName == .toggleActivation)
    }

    @Test("show() makes the window visible")
    func showOrdersFront() {
        let lal = RecordingLaunchAtLogin()
        let controller = PreferencesController(launchAtLogin: lal)
        controller.show()
        #expect(controller.testOnly_window.isVisible == true)
    }

    @Test("show() is idempotent — calling twice leaves window visible")
    func showIdempotent() {
        let lal = RecordingLaunchAtLogin()
        let controller = PreferencesController(launchAtLogin: lal)
        controller.show()
        controller.show()
        #expect(controller.testOnly_window.isVisible == true)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test`
Expected: compile error — `PreferencesController` not found.

- [ ] **Step 3: Create the controller with just the recorder**

Create `Sources/AppKit/PreferencesController.swift`:

```swift
// ABOUTME: Owns the Preferences NSWindow, builds the two-row layout, and wires
// ABOUTME: the activation-hotkey recorder + launch-at-login switch to their ports.

import AppKit
import KeyboardShortcuts

@MainActor
public final class PreferencesController: NSObject {
    private let launchAtLogin: LaunchAtLogin
    private let window: PreferencesWindow
    private let recorder: KeyboardShortcuts.RecorderCocoa

    public init(launchAtLogin: LaunchAtLogin) {
        self.launchAtLogin = launchAtLogin
        self.window = PreferencesWindow()
        self.recorder = KeyboardShortcuts.RecorderCocoa(for: .toggleActivation)
        super.init()
        buildContent()
    }

    public func show() {
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func buildContent() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(row(label: "Activation hotkey:", control: recorder))

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        window.contentView = container
    }

    private func row(label text: String, control: NSView) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        let label = NSTextField(labelWithString: text)
        row.addArrangedSubview(label)
        row.addArrangedSubview(control)
        return row
    }

    // MARK: - Test hooks
    // swiftlint:disable identifier_name
    internal var testOnly_recorder: KeyboardShortcuts.RecorderCocoa { recorder }
    internal var testOnly_window: PreferencesWindow { window }
    // swiftlint:enable identifier_name
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `just test`
Expected: three new tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/PreferencesController.swift \
        Tests/AppKitTests/PreferencesControllerTests.swift
git commit -m "$(cat <<'EOF'
AppKit: PreferencesController with activation-hotkey recorder

First slice of the Preferences UI: a single row hosting
KeyboardShortcuts.RecorderCocoa bound to .toggleActivation. show()
orders the window front and activates the app so it floats above the
caller. Launch-at-login switch arrives in the next slice.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Launch-at-login switch in `PreferencesController`

Add the `NSSwitch` row. Switch reads `launchAtLogin.status` on init; toggling calls `setEnabled`; if it throws, the switch springs back.

**Files:**
- Modify: `Sources/AppKit/PreferencesController.swift`
- Modify: `Tests/AppKitTests/PreferencesControllerTests.swift`

- [ ] **Step 1: Add the failing tests**

Append to `Tests/AppKitTests/PreferencesControllerTests.swift`:

```swift
@Suite("PreferencesController launch-at-login switch")
@MainActor
struct PreferencesControllerSwitchTests {
    @Test("switch starts off when launchAtLogin.status is disabled")
    func switchOffWhenDisabled() {
        let lal = RecordingLaunchAtLogin()
        let controller = PreferencesController(launchAtLogin: lal)
        #expect(controller.testOnly_switch.state == .off)
    }

    @Test("switch starts on when launchAtLogin.status is enabled")
    func switchOnWhenEnabled() throws {
        let lal = RecordingLaunchAtLogin()
        try lal.setEnabled(true)
        let controller = PreferencesController(launchAtLogin: lal)
        #expect(controller.testOnly_switch.state == .on)
    }

    @Test("switch starts on when launchAtLogin.status is requiresApproval")
    func switchOnWhenRequiresApproval() throws {
        let lal = RecordingLaunchAtLogin()
        lal.simulateApprovalRequired = true
        try lal.setEnabled(true)
        let controller = PreferencesController(launchAtLogin: lal)
        #expect(controller.testOnly_switch.state == .on)
    }

    @Test("flipping switch on calls setEnabled(true)")
    func flipOnCallsSetEnabled() {
        let lal = RecordingLaunchAtLogin()
        let controller = PreferencesController(launchAtLogin: lal)
        controller.testOnly_toggleSwitch(to: .on)
        #expect(lal.status == .enabled)
    }

    @Test("flipping switch off calls setEnabled(false)")
    func flipOffCallsSetEnabled() throws {
        let lal = RecordingLaunchAtLogin()
        try lal.setEnabled(true)
        let controller = PreferencesController(launchAtLogin: lal)
        controller.testOnly_toggleSwitch(to: .off)
        #expect(lal.status == .disabled)
    }

    @Test("switch reverts when setEnabled throws")
    func switchRevertsOnError() {
        let lal = RecordingLaunchAtLogin()
        lal.errorToThrow = RecordingLaunchAtLoginError.synthetic
        let controller = PreferencesController(launchAtLogin: lal)
        controller.testOnly_toggleSwitch(to: .on)
        #expect(controller.testOnly_switch.state == .off)
        #expect(lal.status == .disabled)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test`
Expected: compile error — `testOnly_switch`, `testOnly_toggleSwitch` not found.

- [ ] **Step 3: Add the switch to the controller**

Modify `Sources/AppKit/PreferencesController.swift`. Add a stored property and a row, and an action handler. Final file:

```swift
// ABOUTME: Owns the Preferences NSWindow, builds the two-row layout, and wires
// ABOUTME: the activation-hotkey recorder + launch-at-login switch to their ports.

import AppKit
import KeyboardShortcuts

@MainActor
public final class PreferencesController: NSObject {
    private let launchAtLogin: LaunchAtLogin
    private let window: PreferencesWindow
    private let recorder: KeyboardShortcuts.RecorderCocoa
    private let launchSwitch: NSSwitch

    public init(launchAtLogin: LaunchAtLogin) {
        self.launchAtLogin = launchAtLogin
        self.window = PreferencesWindow()
        self.recorder = KeyboardShortcuts.RecorderCocoa(for: .toggleActivation)
        self.launchSwitch = NSSwitch()
        super.init()
        buildContent()
        syncSwitchFromStatus()
    }

    public func show() {
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func buildContent() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(row(label: "Activation hotkey:", control: recorder))

        launchSwitch.target = self
        launchSwitch.action = #selector(launchSwitchToggled(_:))
        stack.addArrangedSubview(row(label: "Launch at login:", control: launchSwitch))

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        window.contentView = container
    }

    private func row(label text: String, control: NSView) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        let label = NSTextField(labelWithString: text)
        row.addArrangedSubview(label)
        row.addArrangedSubview(control)
        return row
    }

    private func syncSwitchFromStatus() {
        switch launchAtLogin.status {
        case .enabled, .requiresApproval:
            launchSwitch.state = .on
        case .disabled, .unavailable:
            launchSwitch.state = .off
        }
    }

    @objc private func launchSwitchToggled(_ sender: NSSwitch) {
        let wantsEnabled = sender.state == .on
        do {
            try launchAtLogin.setEnabled(wantsEnabled)
            syncSwitchFromStatus()
        } catch {
            // Spring back to the prior state on failure.
            sender.state = wantsEnabled ? .off : .on
        }
    }

    // MARK: - Test hooks
    // swiftlint:disable identifier_name
    internal var testOnly_recorder: KeyboardShortcuts.RecorderCocoa { recorder }
    internal var testOnly_window: PreferencesWindow { window }
    internal var testOnly_switch: NSSwitch { launchSwitch }
    internal func testOnly_toggleSwitch(to state: NSControl.StateValue) {
        launchSwitch.state = state
        launchSwitchToggled(launchSwitch)
    }
    // swiftlint:enable identifier_name
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `just test`
Expected: six new switch tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/PreferencesController.swift \
        Tests/AppKitTests/PreferencesControllerTests.swift
git commit -m "$(cat <<'EOF'
AppKit: PreferencesController launch-at-login switch + revert-on-error

Switch state derives from launchAtLogin.status (enabled/requiresApproval
both render as on). Toggling calls setEnabled; if it throws, switch
springs back to its prior state. Status field for the error message
itself arrives next.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Status text field for `requiresApproval` hint and error messages

Add the secondary-style `NSTextField` below the switch. It shows the System Settings hint when status is `.requiresApproval`, the localized error string when `setEnabled` throws, and is hidden otherwise.

**Files:**
- Modify: `Sources/AppKit/PreferencesController.swift`
- Modify: `Tests/AppKitTests/PreferencesControllerTests.swift`

- [ ] **Step 1: Add the failing tests**

Append to `Tests/AppKitTests/PreferencesControllerTests.swift`:

```swift
@Suite("PreferencesController status text")
@MainActor
struct PreferencesControllerStatusTextTests {
    @Test("status field is hidden when launch-at-login is disabled")
    func hiddenWhenDisabled() {
        let lal = RecordingLaunchAtLogin()
        let controller = PreferencesController(launchAtLogin: lal)
        #expect(controller.testOnly_statusField.isHidden == true)
    }

    @Test("status field is hidden when launch-at-login is enabled")
    func hiddenWhenEnabled() throws {
        let lal = RecordingLaunchAtLogin()
        try lal.setEnabled(true)
        let controller = PreferencesController(launchAtLogin: lal)
        #expect(controller.testOnly_statusField.isHidden == true)
    }

    @Test("status field shows the approval hint when requiresApproval")
    func hintWhenRequiresApproval() throws {
        let lal = RecordingLaunchAtLogin()
        lal.simulateApprovalRequired = true
        try lal.setEnabled(true)
        let controller = PreferencesController(launchAtLogin: lal)
        #expect(controller.testOnly_statusField.isHidden == false)
        #expect(controller.testOnly_statusField.stringValue.contains("Login Items"))
    }

    @Test("status field shows the error message when setEnabled throws")
    func errorMessage() {
        struct NamedError: LocalizedError {
            var errorDescription: String? { "Login Items registration failed" }
        }
        let lal = RecordingLaunchAtLogin()
        lal.errorToThrow = NamedError()
        let controller = PreferencesController(launchAtLogin: lal)
        controller.testOnly_toggleSwitch(to: .on)
        #expect(controller.testOnly_statusField.isHidden == false)
        #expect(controller.testOnly_statusField.stringValue == "Login Items registration failed")
    }

    @Test("status field clears when a subsequent toggle succeeds")
    func clearsOnSuccess() {
        let lal = RecordingLaunchAtLogin()
        lal.errorToThrow = RecordingLaunchAtLoginError.synthetic
        let controller = PreferencesController(launchAtLogin: lal)
        controller.testOnly_toggleSwitch(to: .on) // fails, field shows error
        lal.errorToThrow = nil
        controller.testOnly_toggleSwitch(to: .on) // succeeds
        #expect(controller.testOnly_statusField.isHidden == true)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test`
Expected: compile error — `testOnly_statusField` not found.

- [ ] **Step 3: Add the status field**

Modify `Sources/AppKit/PreferencesController.swift`. Add a stored property `statusField`, build it into the stack below the switch row, and update `syncSwitchFromStatus` + `launchSwitchToggled` to write to it. Final file:

```swift
// ABOUTME: Owns the Preferences NSWindow, builds the two-row layout, and wires
// ABOUTME: the activation-hotkey recorder + launch-at-login switch to their ports.

import AppKit
import KeyboardShortcuts

@MainActor
public final class PreferencesController: NSObject {
    private let launchAtLogin: LaunchAtLogin
    private let window: PreferencesWindow
    private let recorder: KeyboardShortcuts.RecorderCocoa
    private let launchSwitch: NSSwitch
    private let statusField: NSTextField

    private static let approvalHint = "Approve fiti in System Settings \u{2192} General \u{2192} Login Items."

    public init(launchAtLogin: LaunchAtLogin) {
        self.launchAtLogin = launchAtLogin
        self.window = PreferencesWindow()
        self.recorder = KeyboardShortcuts.RecorderCocoa(for: .toggleActivation)
        self.launchSwitch = NSSwitch()
        self.statusField = NSTextField(labelWithString: "")
        super.init()
        statusField.font = .systemFont(ofSize: 11)
        statusField.textColor = .secondaryLabelColor
        statusField.lineBreakMode = .byWordWrapping
        statusField.maximumNumberOfLines = 2
        statusField.isHidden = true
        buildContent()
        syncFromStatus()
    }

    public func show() {
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func buildContent() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(row(label: "Activation hotkey:", control: recorder))

        launchSwitch.target = self
        launchSwitch.action = #selector(launchSwitchToggled(_:))
        stack.addArrangedSubview(row(label: "Launch at login:", control: launchSwitch))

        stack.addArrangedSubview(statusField)

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        window.contentView = container
    }

    private func row(label text: String, control: NSView) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        let label = NSTextField(labelWithString: text)
        row.addArrangedSubview(label)
        row.addArrangedSubview(control)
        return row
    }

    private func syncFromStatus() {
        switch launchAtLogin.status {
        case .enabled:
            launchSwitch.state = .on
            setStatusText(nil)
        case .requiresApproval:
            launchSwitch.state = .on
            setStatusText(Self.approvalHint)
        case .disabled, .unavailable:
            launchSwitch.state = .off
            setStatusText(nil)
        }
    }

    private func setStatusText(_ text: String?) {
        if let text {
            statusField.stringValue = text
            statusField.isHidden = false
        } else {
            statusField.stringValue = ""
            statusField.isHidden = true
        }
    }

    @objc private func launchSwitchToggled(_ sender: NSSwitch) {
        let wantsEnabled = sender.state == .on
        do {
            try launchAtLogin.setEnabled(wantsEnabled)
            syncFromStatus()
        } catch {
            sender.state = wantsEnabled ? .off : .on
            let message = (error as? LocalizedError)?.errorDescription
                ?? "Failed to update launch-at-login: \(error.localizedDescription)"
            setStatusText(message)
        }
    }

    // MARK: - Test hooks
    // swiftlint:disable identifier_name
    internal var testOnly_recorder: KeyboardShortcuts.RecorderCocoa { recorder }
    internal var testOnly_window: PreferencesWindow { window }
    internal var testOnly_switch: NSSwitch { launchSwitch }
    internal var testOnly_statusField: NSTextField { statusField }
    internal func testOnly_toggleSwitch(to state: NSControl.StateValue) {
        launchSwitch.state = state
        launchSwitchToggled(launchSwitch)
    }
    // swiftlint:enable identifier_name
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `just test`
Expected: five new status-field tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/PreferencesController.swift \
        Tests/AppKitTests/PreferencesControllerTests.swift
git commit -m "$(cat <<'EOF'
AppKit: PreferencesController status text field for hint + errors

Single secondary-style NSTextField below the launch switch. Shows the
System Settings approval hint when status is requiresApproval, the
localized error message when setEnabled throws, hidden otherwise.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Menubar "Preferences..." item + `main.swift` wiring

Final atomic commit because `MenubarController`'s init signature changes (gains `onOpenPreferences`) and `main.swift` must update at the same time to keep the build green.

**Files:**
- Modify: `Sources/AppKit/MenubarController.swift`
- Modify: `Tests/AppKitTests/MenubarControllerTests.swift`
- Modify: `Sources/App/main.swift`

- [ ] **Step 1: Add the failing tests**

Modify `Tests/AppKitTests/MenubarControllerTests.swift`. Update the `make()` helper so callers can capture the open-preferences count, add tests for the new menu item, and update the existing `menuStructure` test to include the new "Preferences..." entry.

Replace the existing `make()` helper:

```swift
// swiftlint:disable:next large_tuple
private func make() -> (MenubarController, AppController, RecordingWindow, Editor, PreferencesCounter) {
    let counter = PreferencesCounter()
    let window = RecordingWindow()
    let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
    let controller = AppController(editor: editor, window: window, detector: RecordingStationaryDetector())
    let menubar = MenubarController(
        controller: controller,
        editor: editor,
        onOpenPreferences: { counter.count += 1 }
    )
    return (menubar, controller, window, editor, counter)
}

private final class PreferencesCounter {
    var count = 0
}
```

Update every existing call site in the file from `let (menubar, ...) = make()` patterns to ignore the fifth tuple element where unused. Then update the `menuStructure` test:

```swift
@Test("menu has the expected items in order")
func menuStructure() {
    let (menubar, _, _, _, _) = make()
    let titles = menubar.menu.items.map(\.title)
    #expect(titles == ["Activate", "Deactivate", "",
                       "Preferences...", "",
                       "Clear", "Undo", "Redo", "",
                       "Quit fiti"])
}
```

And add the new tests:

```swift
@Test("Preferences item has Cmd+, key equivalent")
func preferencesShortcut() throws {
    let (menubar, _, _, _, _) = make()
    let item = try #require(menubar.menu.items.first { $0.title == "Preferences..." })
    #expect(item.keyEquivalent == ",")
    #expect(item.keyEquivalentModifierMask == [.command])
}

@Test("Preferences menu action fires onOpenPreferences")
func preferencesAction() throws {
    let (menubar, _, _, _, counter) = make()
    try fire("Preferences...", in: menubar)
    #expect(counter.count == 1)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test`
Expected: compile error — `MenubarController.init` does not accept `onOpenPreferences`.

- [ ] **Step 3: Update `MenubarController`**

Modify `Sources/AppKit/MenubarController.swift`. Add an `onOpenPreferences` stored property, accept it in `init`, build a "Preferences..." menu item between the activate/deactivate group and the clear/undo group, wire its action. Final file:

```swift
// ABOUTME: Menu-bar status item for fiti. Two-state SF Symbol icon,
// ABOUTME: menu wired to AppController actions, NSMenuDelegate for enabled state.

import AppKit

@MainActor
public final class MenubarController: NSObject {
    private let controller: AppController
    private let editor: Editor
    private let onOpenPreferences: @MainActor () -> Void
    private let statusItem: NSStatusItem
    internal let menu: NSMenu
    internal private(set) var currentSymbolName: String = ""

    private let activateItem: NSMenuItem
    private let deactivateItem: NSMenuItem
    private let preferencesItem: NSMenuItem
    private let undoItem: NSMenuItem
    private let redoItem: NSMenuItem

    public init(
        controller: AppController,
        editor: Editor,
        onOpenPreferences: @escaping @MainActor () -> Void
    ) {
        self.controller = controller
        self.editor = editor
        self.onOpenPreferences = onOpenPreferences
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.menu = NSMenu()

        self.activateItem = NSMenuItem(title: "Activate", action: #selector(activate), keyEquivalent: "f")
        self.deactivateItem = NSMenuItem(title: "Deactivate", action: #selector(deactivate), keyEquivalent: "\u{1b}")
        self.preferencesItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        let clearItem = NSMenuItem(title: "Clear", action: #selector(clearAll), keyEquivalent: "k")
        self.undoItem = NSMenuItem(title: "Undo", action: #selector(undo), keyEquivalent: "z")
        self.redoItem = NSMenuItem(title: "Redo", action: #selector(redo), keyEquivalent: "z")
        let quitItem = NSMenuItem(title: "Quit fiti", action: #selector(quit), keyEquivalent: "q")

        super.init()

        activateItem.keyEquivalentModifierMask = [.option]
        deactivateItem.keyEquivalentModifierMask = []
        preferencesItem.keyEquivalentModifierMask = [.command]
        clearItem.keyEquivalentModifierMask = [.command]
        undoItem.keyEquivalentModifierMask = [.command]
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        quitItem.keyEquivalentModifierMask = [.command]

        for item in [activateItem, deactivateItem, preferencesItem, undoItem, redoItem, clearItem, quitItem] {
            item.target = self
        }

        menu.addItem(activateItem)
        menu.addItem(deactivateItem)
        menu.addItem(.separator())
        menu.addItem(preferencesItem)
        menu.addItem(.separator())
        menu.addItem(clearItem)
        menu.addItem(undoItem)
        menu.addItem(redoItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        menu.delegate = self
        statusItem.menu = menu

        updateIcon(for: controller.mode)
        controller.onModeChanged = { [weak self] mode in self?.updateIcon(for: mode) }
    }

    isolated deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func updateIcon(for mode: AppController.Mode) {
        let name = mode == .inactive ? "theatermask.and.paintbrush"
                                     : "theatermask.and.paintbrush.fill"
        currentSymbolName = name
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "fiti")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    @objc private func activate() { controller.activate() }
    @objc private func deactivate() { controller.deactivate() }
    @objc private func openPreferences() { onOpenPreferences() }
    @objc private func clearAll() { controller.clear() }
    @objc private func undo() { _ = editor.undo() }
    @objc private func redo() { _ = editor.redo() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}

extension MenubarController: NSMenuDelegate {
    public func menuNeedsUpdate(_ menu: NSMenu) {
        let active = controller.mode != .inactive
        activateItem.isEnabled = !active
        deactivateItem.isEnabled = active
        undoItem.isEnabled = editor.canUndo
        redoItem.isEnabled = editor.canRedo
    }
}
```

- [ ] **Step 4: Update `main.swift`**

Modify `Sources/App/main.swift`. Add a `preferences` stored property, construct the adapter + controller, pass the closure to the menubar. Replace the existing `menubar = MenubarController(...)` line and add the construction above it:

```swift
preferences = PreferencesController(launchAtLogin: SMAppServiceLaunchAtLogin())
menubar = MenubarController(
    controller: controller,
    editor: editor,
    onOpenPreferences: { [weak self] in self?.preferences.show() }
)
```

Add the stored property in `FitiAppDelegate`:

```swift
var preferences: PreferencesController!
```

- [ ] **Step 5: Run the full check**

Run: `just check`
Expected:
- `fiti-unit` test count grows by 6 (Task 1's `LaunchAtLoginTests`).
- `fiti-integration` test count grows by 6 + 4 + 3 + 6 + 5 + 2 = 26 (it includes `Tests/CoreTests` plus `Tests/AppKitTests`).
- All green; lint clean; build succeeds.

- [ ] **Step 6: Manual smoke test**

```bash
just run-bg
just inspect-state  # verify --dev port still listening
```

In the menubar:
1. Click the fiti status item. Verify "Preferences..." appears between Deactivate and Clear.
2. Click Preferences. Verify the window opens with the recorder and the launch-at-login switch.
3. Record a new hotkey (e.g., Opt+G). Verify it activates fiti on the next press, and Opt+F no longer does.
4. Re-record back to Opt+F (or clear and re-record).
5. Toggle launch-at-login on. macOS opens Login Items. Verify fiti appears there.
6. Toggle off. Verify fiti is removed.

```bash
just stop
```

- [ ] **Step 7: Commit**

```bash
git add Sources/AppKit/MenubarController.swift \
        Tests/AppKitTests/MenubarControllerTests.swift \
        Sources/App/main.swift
git commit -m "$(cat <<'EOF'
AppKit + App: menubar Preferences... item + main.swift wiring

MenubarController gains an onOpenPreferences closure parameter; the
new "Preferences..." item between Deactivate and Clear fires it on
Cmd+,. main.swift constructs SMAppServiceLaunchAtLogin +
PreferencesController and threads show() into the closure.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Acceptance criteria (mirrors the spec)

- [ ] Status menu has "Preferences..." entry with Cmd+,.
- [ ] Clicking it opens an `NSWindow` with two rows: hotkey recorder and launch-at-login switch.
- [ ] Recording a new shortcut updates `KeyboardShortcuts.Name.toggleActivation`; the new combo triggers activation; the old combo no longer does.
- [ ] Clearing the shortcut leaves activation unbound until the user records a new one. Menubar "Activate" item still works.
- [ ] Toggling launch-at-login on adds fiti to Login Items; toggling off removes it.
- [ ] If `setEnabled` throws, the switch reverts and the status text field shows the error. UI does not crash.
- [ ] `Sources/Core/` has no AppKit/CoreGraphics/SwiftUI/ServiceManagement imports (`just lint` enforces).
- [ ] All test suites stay under the 5-second budget (`just check`).
