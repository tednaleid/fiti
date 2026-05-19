# fiti Keyboard Shortcuts (Active-App) Design

Date: 2026-05-18
Status: Design — not yet implemented.

## Goal

Make every action on the toolbar and the in-app menubar items reachable by a single keypress while fiti has key focus. Bindings are hard-coded, not user-rebindable (different from `Opt+F` activate and the planned `Opt+H` global hide/show — those are system-wide and route through `sindresorhus/KeyboardShortcuts` because they can collide with other apps). Tooltips on the toolbar and entries in the menubar surface the bindings so users discover them.

## Non-goals

- User rebinding. These bindings only fire while fiti is the key app; collisions with other apps are not possible.
- Global hotkeys. Activate stays `Opt+F`. The planned `Opt+H` global hide/show is a separate roadmap item.
- New tools. `e` (eraser), `p` (pen), `Space` (selection) are reserved binding slots but resolve to `nil` until the underlying tools land.
- Preferences-tab UI for bindings. The static table is the source of truth; tooltips and menu items provide discovery.
- A `KeyboardShortcuts.Name` for any of these. The library is reserved for system-wide bindings.

## Architecture

Three layers, mirroring the pattern already used for activation hotkeys and auto-fade ticking.

### Core: `KeyCommand` enum + registry

`Sources/Core/Control/KeyCommand.swift` (new):

```swift
public enum KeyCommand: Equatable, Sendable {
    case pickColor(Int)             // 0..7
    case bumpSize(Direction)
    case bumpOpacity(Direction)
    case toggleHide
    case toggleAutoFade
    case clear
    public enum Direction: Sendable { case up, down }
}

public struct KeyBinding: Hashable, Sendable {
    public let character: Character
    public let shift: Bool
}

public enum KeyCommandRegistry {
    public static let bindings: [KeyBinding: KeyCommand] = [
        KeyBinding("1", shift: false): .pickColor(0),
        KeyBinding("2", shift: false): .pickColor(1),
        KeyBinding("3", shift: false): .pickColor(2),
        KeyBinding("4", shift: false): .pickColor(3),
        KeyBinding("5", shift: false): .pickColor(4),
        KeyBinding("6", shift: false): .pickColor(5),
        KeyBinding("7", shift: false): .pickColor(6),
        KeyBinding("8", shift: false): .pickColor(7),
        KeyBinding("s", shift: false): .bumpSize(.up),
        KeyBinding("s", shift: true):  .bumpSize(.down),
        KeyBinding("o", shift: false): .bumpOpacity(.up),
        KeyBinding("o", shift: true):  .bumpOpacity(.down),
        KeyBinding("h", shift: false): .toggleHide,
        KeyBinding("f", shift: false): .toggleAutoFade,
        KeyBinding("c", shift: false): .clear
    ]
    public static func command(for binding: KeyBinding) -> KeyCommand? {
        bindings[binding]
    }
}
```

The registry character matches `charactersIgnoringModifiers` from the AppKit event — so `s` and `S` both report `"s"` but differ on the shift flag. Reserved slots (Space, `e`, `p`) are deliberately absent from the dictionary; the unit tests assert they resolve to `nil` so we can't accidentally drop a future tool's binding.

### Core: `QuickPickPalette`

Move `quickPickRGB` out of `ToolbarController` (where it currently lives as `private static let`) and into `Sources/Core/Model/QuickPickPalette.swift`:

```swift
public struct QuickPickColor: Equatable, Sendable {
    public let name: String
    public let r: Double
    public let g: Double
    public let b: Double
}

public enum QuickPickPalette {
    public static let colors: [QuickPickColor] = [
        QuickPickColor(name: "Black",  r: 0,             g: 0,             b: 0),
        QuickPickColor(name: "Gray",   r: 134.0/255.0,   g: 142.0/255.0,   b: 150.0/255.0),
        QuickPickColor(name: "Red",    r: 224.0/255.0,   g:  49.0/255.0,   b:  49.0/255.0),
        QuickPickColor(name: "Orange", r: 247.0/255.0,   g: 103.0/255.0,   b:   7.0/255.0),
        QuickPickColor(name: "Amber",  r: 245.0/255.0,   g: 159.0/255.0,   b:   0),
        QuickPickColor(name: "Green",  r:  47.0/255.0,   g: 158.0/255.0,   b:  68.0/255.0),
        QuickPickColor(name: "Blue",   r:  25.0/255.0,   g: 113.0/255.0,   b: 194.0/255.0),
        QuickPickColor(name: "Violet", r: 156.0/255.0,   g:  54.0/255.0,   b: 181.0/255.0)
    ]
}
```

`ToolbarController` and `MenubarController` both read from `QuickPickPalette.colors`. Color labels live with their RGB values, so renaming "Violet" to "Purple" is a one-line change that propagates everywhere.

### Core: `AppController.run(_:)`

New single-entry-point method on `AppController`:

```swift
public func run(_ command: KeyCommand) {
    switch command {
    case .pickColor(let i):
        guard i >= 0, i < QuickPickPalette.colors.count else { return }
        let c = QuickPickPalette.colors[i]
        currentColor = RGBA(r: c.r, g: c.g, b: c.b, a: currentColor.a)
    case .bumpSize(.up):    currentWidth = min(40, currentWidth * 1.1)
    case .bumpSize(.down):  currentWidth = max(1,  currentWidth / 1.1)
    case .bumpOpacity(.up):    currentColor = currentColor.with(a: min(1, currentColor.a + 0.1))
    case .bumpOpacity(.down):  currentColor = currentColor.with(a: max(0, currentColor.a - 0.1))
    case .toggleHide:     drawingsVisible.toggle()
    case .toggleAutoFade: autoFadeEnabled.toggle()
    case .clear:          clear()
    }
}
```

`RGBA.with(a:)` is a small convenience added in this slice. The size and opacity math is intentionally simple: clamped to slider bounds, no rounding to whole numbers. The didSet on `currentColor` / `currentWidth` already publishes to ToolbarController, so widgets update automatically.

### AppKit adapter: `KeyMonitor`

`Sources/AppKit/KeyMonitor.swift` (new). Owns one `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` registration. Translates each event into a `KeyBinding`, looks it up in the registry, and dispatches.

```swift
@MainActor
public final class KeyMonitor {
    private let controller: AppController
    private var monitor: Any?

    public init(controller: AppController) {
        self.controller = controller
        controller.onModeChanged = { [weak self] mode in self?.syncRegistration(for: mode) }
        syncRegistration(for: controller.mode)
    }

    deinit { uninstall() }

    private func syncRegistration(for mode: AppController.Mode) {
        if mode == .inactive { uninstall() } else { install() }
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func uninstall() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    internal func handle(_ event: NSEvent) -> NSEvent? {
        // Public so unit tests can synthesize NSEvents and verify dispatch.
        guard let chars = event.charactersIgnoringModifiers, chars.count == 1,
              let ch = chars.first else { return event }
        let binding = KeyBinding(character: ch, shift: event.modifierFlags.contains(.shift))
        guard let command = KeyCommandRegistry.command(for: binding) else { return event }
        // Don't swallow if Cmd is held — Cmd+Z/Cmd+K/Cmd+, etc. route through the menubar.
        if event.modifierFlags.contains(.command) { return event }
        controller.run(command)
        return nil
    }
}
```

The `onModeChanged` subscription means we only intercept keys while fiti is active. When `mode == .inactive`, the local monitor is removed entirely so other apps see the keystroke unmodified. The Cmd-modifier guard exists because `Cmd+S`, `Cmd+H`, `Cmd+F` are reserved by macOS conventions even though we never bind to them — we explicitly stay out of their way.

`onModeChanged` is currently used by `MenubarController` to update the menubar icon. We need to preserve that. The cleanest fix: change `AppController` to use a multicast pattern for `onModeChanged` — store an array of subscribers — or add a separate `addModeObserver(_:)` API. Given there's already a pattern of single-closure publishers throughout AppController (`onCurrentColorChanged`, `onDrawingsVisibilityChanged`, etc.), the smaller change is to introduce one helper:

```swift
// Sources/Core/Control/AppController.swift
public func addModeObserver(_ observer: @escaping (Mode) -> Void) {
    let prior = onModeChanged
    onModeChanged = { mode in prior?(mode); observer(mode) }
}
```

Both `MenubarController.init` and `KeyMonitor.init` use `addModeObserver` instead of overwriting `onModeChanged`. Existing callers that set `onModeChanged = ...` directly are migrated to `addModeObserver`.

### Menu

`MenubarController` gains a "Drawing" submenu inserted before the existing "Clear" item:

```
Activate                    ⌥F
Deactivate                  esc
───
Preferences...              ⌘,
───
Drawing                    ▶
   Black                    1
   Gray                     2
   Red                      3
   Orange                   4
   Amber                    5
   Green                    6
   Blue                     7
   Violet                   8
   ───
   Larger stroke            s
   Smaller stroke           S
   ───
   More opaque              o
   Less opaque              O
   ───
   Hide drawings            h    [checkmark when hidden]
   Auto-fade                f    [checkmark when on]
Clear                       ⌘K
Undo                        ⌘Z
Redo                        ⇧⌘Z
───
Quit fiti                   ⌘Q
```

Each submenu item:

- Has `keyEquivalent` set to the literal character (e.g. `"1"`, `"s"`) with `keyEquivalentModifierMask = []` for unshifted and `= [.shift]` for the shifted variants. This is for display only — status-menu key equivalents fire unreliably on `LSUIElement = true` apps. `KeyMonitor` is what actually dispatches.
- Has its `action` wired to a single `@objc func runCommand(_ sender: NSMenuItem)` on `MenubarController` that reads `sender.representedObject as? KeyCommand` and calls `controller.run(_:)`. Same dispatch path as the keyboard.
- For `Hide drawings` and `Auto-fade`, `menuNeedsUpdate` toggles `item.state = .on / .off` to reflect `drawingsVisible == false` and `autoFadeEnabled == true` respectively.

Top-level menu items (`Clear`, `Undo`, `Redo`, `Quit`) stay where they are with their existing `Cmd`-modifier shortcuts.

### Toolbar tooltips

Tooltip text is computed by a single helper that reads `QuickPickPalette` and the binding table. Each control's `.toolTip` is set during `buildContent` and refreshed in the same `update*Glyph` methods that already swap icons.

```swift
// Inside ToolbarController
private func tooltipForSwatch(_ i: Int) -> String {
    "\(QuickPickPalette.colors[i].name) — \(i + 1)"
}

private func updateHideButtonGlyph(visible: Bool) {
    // ... existing icon swap ...
    hideButton.toolTip = visible ? "Hide drawings — h" : "Show drawings — h"
}

private func updateAutoFadeGlyph(enabled: Bool) {
    // ... existing icon swap ...
    autoFadeButton.toolTip = enabled ? "Auto-fade on — f" : "Auto-fade off — f"
}
```

Static tooltips set once in `buildContent`:

- Color well: `"Custom color"`
- Width slider: `"Stroke size — s / S"`
- Opacity slider: `"Stroke opacity — o / O"`

Labels above the sliders change too: `label("w")` → `label("stroke size")`, `label("o")` → `label("stroke opacity")`.

## Mid-stroke behavior

`Editor.startStroke(color:width:pointerType:)` captures color and width *by value* at stroke start. Subsequent writes to `controller.currentColor` / `controller.currentWidth` (from a keyboard binding, the toolbar, or HTTP) update the controller's fields but do not retroactively alter the in-progress stroke. Verified at `Sources/Core/Editor/Editor.swift:33`.

This gives us the behavior the roadmap calls out: pressing `5` (Amber) mid-stroke leaves the current line red and starts the next stroke amber. No special-casing needed in `KeyMonitor` or `AppController.run(_:)`.

`c` (clear) mid-stroke uses `AppController.clear()`, which already finalizes the in-progress stroke before clearing (`Sources/Core/Control/AppController.swift:196-206`). One `Cmd+Z` after that restores everything including the just-finished stroke.

`h` and `f` mid-stroke flip visibility and auto-fade respectively without affecting the active drawing path.

## Wiring

`main.swift` constructs a `KeyMonitor` after `MenubarController` and before `ToolbarController`. The monitor holds a strong reference inside `App` for lifetime management.

`AppController.init` is unchanged. Existing callers that wrote `controller.onModeChanged = { ... }` migrate to `controller.addModeObserver { ... }`. All callsites:

- `MenubarController.init` (line 69): one site to migrate.
- `KeyMonitor.init` (new): added in this slice.

The `addModeObserver` introduction is the same shape as the `addModeObserver` patterns used in similar Apple frameworks (`NotificationCenter.observe`, KVO blocks). It composes existing closures so we don't need to change the publisher's type from `((Mode) -> Void)?` to `[(Mode) -> Void]`.

## Testing

### Core (`Tests/CoreTests/`)

**`KeyCommandRegistryTests.swift`** — Exhaustive lookup table:

- `bindings["1", shift: false]` → `.pickColor(0)`, …, `bindings["8"]` → `.pickColor(7)`.
- `bindings["s", shift: false]` → `.bumpSize(.up)`, `bindings["s", shift: true]` → `.bumpSize(.down)`.
- `bindings["o", shift: false]` → `.bumpOpacity(.up)`, `bindings["o", shift: true]` → `.bumpOpacity(.down)`.
- `bindings["h"]` / `bindings["f"]` / `bindings["c"]` → correct commands.
- **Reserved slots** assert nil: `bindings[" ", shift: false]`, `bindings["e", shift: false]`, `bindings["p", shift: false]`.
- Sanity: no binding has `Cmd`-modifier baked in (Cmd combos route through the menubar).

**`AppControllerRunTests.swift`** — `run(_:)` behavior:

- `run(.pickColor(2))` sets `currentColor.r/g/b` to Red while preserving `currentColor.a`.
- `run(.pickColor(99))` is a no-op (out of range).
- `run(.bumpSize(.up))` at width 10 → 11.0. At width 40 (max) → 40 (clamp).
- `run(.bumpSize(.down))` at width 10 → ≈9.09. At width 1 (min) → 1 (clamp).
- `run(.bumpOpacity(.up))` at alpha 0.7 → 0.8. At alpha 1.0 → 1.0 (clamp).
- `run(.bumpOpacity(.down))` at alpha 0.7 → 0.6. At alpha 0.0 → 0.0 (clamp).
- `run(.toggleHide)` flips `drawingsVisible`.
- `run(.toggleAutoFade)` flips `autoFadeEnabled`.
- `run(.clear)` with an in-progress stroke: stroke is finalized, then doc is empty.
- **Mid-stroke color**: start a stroke at red, `run(.pickColor(4))` (amber), `endStroke()`. Assert the captured stroke's color is still red; `currentColor` is amber.

**Mode observer composition**: `addModeObserver` test — register two observers, assert both fire in registration order on mode change.

### AppKit (`Tests/AppKitTests/`)

**`KeyMonitorTests.swift`** — Test the pure translation via the internal `handle(_:)` method by synthesizing `NSEvent.keyDown` events. Helper:

```swift
private func keyEvent(_ chars: String, shift: Bool = false, command: Bool = false) -> NSEvent { ... }
```

Cases:
- `handle(keyEvent("3"))` → `nil` return (swallowed); `controller.currentColor` is Red.
- `handle(keyEvent("s"))` → controller.currentWidth increased.
- `handle(keyEvent("s", shift: true))` → controller.currentWidth decreased.
- `handle(keyEvent("x"))` → returns the event unchanged (no binding for `x`).
- `handle(keyEvent("s", command: true))` → returns the event unchanged (Cmd suppresses dispatch).
- Multi-character strings (e.g., dead keys producing `"´e"`) are passed through unchanged.

We do not test the `NSEvent.addLocalMonitorForEvents` registration itself — it's a thin wrapper, and the install/uninstall flips are covered by mode-state tests if needed.

**`MenubarControllerTests.swift` additions**:

- "Drawing" submenu exists at the expected index.
- Submenu has 8 color items + 4 size/opacity items + 2 toggle items (split by separators).
- Each color item's `keyEquivalent` matches its 1-indexed position.
- `Larger stroke` has `keyEquivalent == "s"`, `keyEquivalentModifierMask == []`.
- `Smaller stroke` has `keyEquivalent == "s"`, `keyEquivalentModifierMask == [.shift]`.
- After `controller.drawingsVisible = false`, calling `menuNeedsUpdate` makes the `Hide drawings` item show `.on` state.
- Clicking a submenu item (testOnly hook) dispatches `controller.run(_:)`.

**`ToolbarControllerTests.swift` additions**:

- After init, each swatch's `toolTip` matches `"<name> — <index+1>"` for the corresponding palette entry.
- Width slider tooltip is `"Stroke size — s / S"`.
- Opacity slider tooltip is `"Stroke opacity — o / O"`.
- Hide button tooltip flips between `"Hide drawings — h"` and `"Show drawings — h"` when `drawingsVisible` flips.
- Auto-fade button tooltip flips between `"Auto-fade on — f"` and `"Auto-fade off — f"` when `autoFadeEnabled` flips.
- Width-slider label text is `"stroke size"`.
- Opacity-slider label text is `"stroke opacity"`.

### What's NOT tested

- The macOS keyboard dispatch path itself (NSEvent.addLocalMonitorForEvents) — covered by manual smoke test.
- Visual rendering of tooltip popups — AppKit-internal.

## Persistence

Nothing new. Bindings are hard-coded; no `UserDefaults` keys are added.

## Acceptance criteria

- [ ] Pressing `1`–`8` while fiti is active selects the matching palette color, preserving the current alpha.
- [ ] Pressing `s` / `S` adjusts stroke size up / down by ~10% (multiplicative), clamped to `[1, 40]`.
- [ ] Pressing `o` / `O` adjusts opacity up / down by 0.1 (additive), clamped to `[0, 1]`.
- [ ] Pressing `h` toggles hide/show. Pressing `f` toggles auto-fade. Pressing `c` clears.
- [ ] Bindings only fire while fiti is active (`mode != .inactive`). Inactive, all keys pass through.
- [ ] Cmd-modifier keystrokes (`Cmd+Z`, `Cmd+K`, `Cmd+S`, etc.) are not intercepted by `KeyMonitor`.
- [ ] Drawing-shortcut menu items render in the menubar status menu as a "Drawing" submenu with the right key equivalents and state checkmarks.
- [ ] Toolbar widgets display tooltips matching the spec on hover.
- [ ] Stroke size / opacity slider labels read "stroke size" / "stroke opacity".
- [ ] Mid-stroke shortcut presses do not retroactively modify the in-progress stroke.
- [ ] `Sources/Core/` has no AppKit/CoreGraphics/Network/SwiftUI imports (`just lint` enforces).
- [ ] Full test suite stays under 5 seconds (`just check`).

## Open questions / future

- Should `Larger stroke` / `Smaller stroke` also accept Up/Down arrow keys when the toolbar has focus? Probably not — there's no concept of "toolbar focus" today, and Up/Down on the canvas should remain free for a future nudge-selected-strokes action.
- A "Help" item in the status menu listing all bindings could replace per-control tooltips eventually; for now tooltips + submenu are enough.
- If a future setting lets users disable the auto-fade toggle entirely, the `f` binding should become a no-op for them. Defer until that setting exists.
