# fiti Preferences + Launch-at-Login Design

Date: 2026-05-18
Status: Design — not yet implemented.

## Goal

Ship a Preferences window that hosts two settings:

1. **Activation hotkey** — rebindable via `KeyboardShortcuts.RecorderCocoa`, bound to `KeyboardShortcuts.Name.toggleActivation` (which already exists and already persists to UserDefaults).
2. **Launch at login** — `NSSwitch` that registers / unregisters fiti with `SMAppService.mainApp` so the hotkey is live across reboots without re-opening the app.

The window is opened from a new "Preferences..." item in the menubar status menu (Cmd+,). Closing the window dismisses it without quitting the app.

## Non-goals (out of scope for this spec)

- Migrating toolbar persistence (color, width, opacity) into the Preferences window. The toolbar's `UserDefaults` reads/writes stay in `ToolbarController`. Preferences is for app-level settings, not per-stroke knobs.
- A general settings storage abstraction. There is one new persisted bit (launch-at-login is read from `SMAppService` itself, the hotkey is persisted by KeyboardShortcuts under its own slug). No new UserDefaults keys.
- SwiftUI. The rest of the app is AppKit-first; introducing `NSHostingView` for two controls is not warranted.
- Tab bar inside Preferences. There are two rows; one pane is enough until there's a third or fourth feature.
- A "reset hotkey to default" button. `RecorderCocoa` exposes a built-in clear button already.

## Architecture

Hexagonal as elsewhere in the project.

### New port: `LaunchAtLogin`

Lives at `Sources/Core/Ports/LaunchAtLogin.swift`. Pure Swift, no AppKit, no ServiceManagement import.

```swift
@MainActor
public protocol LaunchAtLogin: AnyObject {
    /// Whether the toggle should appear at all. False on macOS versions where
    /// SMAppService.mainApp is unavailable, or when the adapter cannot find
    /// the bundle (e.g. unsigned debug builds with no Info.plist on disk).
    var isAvailable: Bool { get }

    /// Current registration state, freshly read from the underlying service.
    /// Distinct from `isAvailable`: an available adapter can still be in any
    /// of these states. `.requiresApproval` means "user toggled on but macOS
    /// is waiting on Login Items approval in System Settings."
    var status: LaunchAtLoginStatus { get }

    /// Register (true) or unregister (false). Throws if the underlying
    /// SMAppService call fails. Tests can throw a synthetic error to drive
    /// the failure path. The UI maps thrown errors to a one-line banner;
    /// the toggle springs back to its previous state.
    func setEnabled(_ enabled: Bool) throws
}

public enum LaunchAtLoginStatus: Equatable, Sendable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable
}
```

### New AppKit adapter: `SMAppServiceLaunchAtLogin`

`Sources/AppKit/SMAppServiceLaunchAtLogin.swift`. Wraps `SMAppService.mainApp` from the `ServiceManagement` framework (macOS 13+, fiti deploys 14+ so this is always available at compile time). Maps `SMAppService.Status` to `LaunchAtLoginStatus`:

| `SMAppService.Status` | `LaunchAtLoginStatus` |
| --- | --- |
| `.notRegistered`        | `.disabled` |
| `.enabled`              | `.enabled` |
| `.requiresApproval`     | `.requiresApproval` |
| `.notFound` (or future) | `.unavailable` |

`setEnabled(true)` calls `SMAppService.mainApp.register()`; `setEnabled(false)` calls `unregister()`. Both can throw; the caller surfaces the error.

`isAvailable` returns `true` unless the current status is `.unavailable`. This lets the Preferences row disable itself in environments where SMAppService can't see the bundle (very rare in practice; matters for "fiti running from /tmp during dev signing").

This adapter is not unit-testable — registering and unregistering with launchd is a real side effect that persists in the user's account. Manual smoke test only. The test target uses `RecordingLaunchAtLogin` (a test double) instead.

### New AppKit surfaces

- `Sources/AppKit/PreferencesWindow.swift` — `NSWindow` subclass, not a panel. Titled, closable (but not deallocated — `isReleasedWhenClosed = false`), `setFrameAutosaveName("fiti.preferences")`. Fixed content size (~360×140); not resizable. Standard close button only — no miniaturize, no zoom.
- `Sources/AppKit/PreferencesController.swift` — owns the window, builds the two-row stack content, wires `RecorderCocoa` and the launch-at-login switch. Subscribes to nothing globally; reads `LaunchAtLogin.status` on every `windowDidBecomeKey` (and once on init) so the switch reflects external changes (user toggled in System Settings → Login Items while the window was hidden).

### Menubar integration

Add one item to the status menu:

```
- Activate
- Deactivate
-
- Preferences...      (Cmd+,)
-
- Clear
- Undo
- Redo
-
- Quit fiti
```

Item is always enabled. Clicking it calls `PreferencesController.show()` which orders the window front, calls `makeKeyAndOrderFront`, and activates the app so the user sees the window above other apps. `NSApp.activate(ignoringOtherApps: true)` matches what `main.swift` already does at launch.

### Wiring in `Sources/App/main.swift`

```swift
let launchAtLogin: LaunchAtLogin = SMAppServiceLaunchAtLogin()
preferences = PreferencesController(launchAtLogin: launchAtLogin)
menubar = MenubarController(
    controller: controller,
    editor: editor,
    onOpenPreferences: { [weak self] in self?.preferences.show() }
)
```

`MenubarController`'s init grows one new closure parameter `onOpenPreferences: @MainActor () -> Void`. Closure-based injection (rather than passing the `PreferencesController` itself) keeps `MenubarController` testable without constructing a real preferences window. No other call sites change.

## Data flow

### Opening Preferences

```
user clicks "Preferences..."  (or Cmd+, in the status menu)
    -> MenubarController.openPreferences()
       -> PreferencesController.show()
          -> reads launchAtLogin.status, syncs switch
          -> window.makeKeyAndOrderFront(nil)
          -> NSApp.activate(ignoringOtherApps: true)
```

### Rebinding the hotkey

```
user types a new combo into the Recorder
    -> KeyboardShortcuts persists to UserDefaults under "toggleActivation"
    -> the next KeyDown that matches fires the existing onActivation handler
       (already wired in main.swift via KeyboardShortcutsHotkeys)
```

No callbacks back into fiti's code. The library handles persistence, conflict resolution, and global event monitoring. The recorder is fire-and-forget UI.

### Toggling launch-at-login

```
user flips the switch ON
    -> PreferencesController.setLaunchAtLogin(true)
       -> launchAtLogin.setEnabled(true)
          (adapter calls SMAppService.mainApp.register())
       -> on throw: switch reverts, status field shows error message
       -> on success: re-read status; status field shows hint if .requiresApproval
```

A single `NSTextField` (secondary-style, 11-pt, multi-line) sits below the launch-at-login switch. It serves double duty:

- When `status == .requiresApproval`: "Approve fiti in System Settings → General → Login Items."
- When `setEnabled` throws: the localized error message from the thrown `Error`.
- Otherwise: hidden (`isHidden = true`).

The text field is always present in the layout (window height does not change); it just toggles visibility. Order of precedence when both conditions apply: the error message wins until the user toggles again, then the field falls back to the status-based message.

## UI layout

ASCII mockup — actual implementation uses NSStackView, vertical, 12-pt spacing, 20-pt window margin.

```
+--------------------------------------------------+
|  fiti Preferences                            [X] |
|                                                  |
|  Activation hotkey:  [  Opt+F            ]       |
|                                                  |
|  Launch at login:    ( )  (NSSwitch)             |
|                       Approve fiti in System     |
|                       Settings -> Login Items.   |
|                                                  |
+--------------------------------------------------+
```

Two rows. Labels right-aligned, controls left-aligned, single column. Hint text only present when `status == .requiresApproval`.

## Testing strategy

Following the test layout already established in `Tests/CoreTests/` and `Tests/AppKitTests/`.

### Core tests

`Tests/CoreTests/LaunchAtLoginTests.swift` — exercises `RecordingLaunchAtLogin`, the test double. Not the real adapter. Validates:

- Initial state is `.disabled` with `isAvailable == true`.
- `setEnabled(true)` updates `status` to `.enabled`.
- `setEnabled(false)` returns to `.disabled`.
- A configurable `errorToThrow` makes `setEnabled` throw — used by AppKit tests to drive the failure path.
- Setting `simulateApprovalRequired = true` makes `setEnabled(true)` land in `.requiresApproval` instead of `.enabled`.

The recording double lives at `Tests/CoreTests/Doubles/RecordingLaunchAtLogin.swift` so AppKit tests can use it too.

### AppKit tests

`Tests/AppKitTests/PreferencesControllerTests.swift`:

- Window content has a recorder bound to `.toggleActivation` (assert via `shortcutName == .toggleActivation`).
- Window content has an NSSwitch.
- Switch initial state reflects `launchAtLogin.status` (`enabled`/`requiresApproval` → on, else off).
- Toggling the switch calls `launchAtLogin.setEnabled(_:)` with the new state.
- When `setEnabled` throws, the switch springs back to its previous value.
- When status is `.requiresApproval`, the hint label is visible; when `.enabled`, hidden.
- `show()` orders the window front (assert via `window.isVisible == true`).

`Tests/AppKitTests/MenubarControllerTests.swift` (extend existing):

- "Preferences..." menu item exists with Cmd+, equivalent.
- Clicking it calls the injected open-preferences closure (a small recording double in the test that increments a counter, not the real `PreferencesController`).

No tests for the real `SMAppServiceLaunchAtLogin` adapter. Acceptance is manual:

1. `just run-bg`
2. Open Preferences from menubar
3. Toggle launch-at-login on. macOS opens Login Items. Verify fiti is listed and enabled.
4. Quit fiti. Log out, log in. Verify fiti is running (`pgrep -fl fiti`).
5. Re-open Preferences. Toggle off. Verify fiti is removed from Login Items.

## Acceptance criteria

- [ ] Status menu has "Preferences..." entry with Cmd+,.
- [ ] Clicking it opens an `NSWindow` with two rows: hotkey recorder and launch-at-login switch.
- [ ] Recording a new shortcut updates `KeyboardShortcuts.Name.toggleActivation` and the new combo triggers activation on the next press. Old combo no longer triggers.
- [ ] Clearing the shortcut (via recorder's clear button) leaves activation unbound until the user records a new one. Menubar "Activate" item still works (no global hotkey path used).
- [ ] Toggling launch-at-login on adds fiti to Login Items; toggling off removes it.
- [ ] If `setEnabled` throws, the switch reverts and the status text field shows the error. UI does not crash.
- [ ] `Sources/Core/` still has no AppKit/CoreGraphics/SwiftUI/ServiceManagement imports (verified by `just lint`).
- [ ] All test suites stay under the 5-second budget.

## Open questions / future

- Should the preferences window be reachable from a Dock icon menu when fiti gains a real icon? Probably yes once we have an icon. Out of scope here.
- Should the activation hotkey display a conflict warning if the user binds something that already has a system meaning? `KeyboardShortcuts` handles this internally — out of scope.
- A "Reset all" button. Not now. There are two settings; users can clear them individually.
