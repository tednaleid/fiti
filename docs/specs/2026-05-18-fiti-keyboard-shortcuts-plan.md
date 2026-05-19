# fiti Keyboard Shortcuts (Active-App) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Single-key shortcuts (`1`–`8`, `s`/`S`, `o`/`O`, `h`, `f`, `c`) that fire only while fiti has key focus. Discoverability via toolbar tooltips and a "Drawing" submenu on the menubar. Bindings are hard-coded; no Preferences UI for them.

**Architecture:** A pure-Core `KeyCommand` enum + static `KeyCommandRegistry` binding table is the single source of truth. `AppController.run(_ command: KeyCommand)` is the single dispatch entry point used by both the keyboard monitor and the menu. The color palette moves from `ToolbarController` into a Core `QuickPickPalette` so toolbar, menu, and tooltips all share names + RGB. An `NSEvent.addLocalMonitorForEvents` adapter in AppKit (`KeyMonitor`) installs/uninstalls based on mode. The menu's `keyEquivalent`s are display-only — `KeyMonitor` does the real dispatch.

**Tech Stack:** Swift 6, AppKit, Swift Testing, no SwiftUI, no new SPM deps.

**Source of truth:** `docs/specs/2026-05-18-fiti-keyboard-shortcuts-design.md`.

---

## File map

| File | Responsibility | Status |
| --- | --- | --- |
| `Sources/Core/Control/KeyCommand.swift` | `KeyCommand` enum + `KeyBinding` + `KeyCommandRegistry` | create (Task 1) |
| `Tests/CoreTests/KeyCommandRegistryTests.swift` | Exhaustive registry lookup + reserved-slot tests | create (Task 1) |
| `Sources/Core/Model/QuickPickPalette.swift` | Named 8-color palette | create (Task 2) |
| `Tests/CoreTests/QuickPickPaletteTests.swift` | Palette shape + name/RGB invariants | create (Task 2) |
| `Sources/AppKit/ToolbarController.swift` | Drop local `quickPickRGB`; consume `QuickPickPalette` | modify (Task 2, again in Task 6) |
| `Tests/AppKitTests/ToolbarControllerTests.swift` | Existing color-click test should still pass against palette | modify (Task 2, again in Task 6) |
| `Sources/Core/Model/RGBA.swift` | `with(a:)` convenience | modify (Task 3) |
| `Sources/Core/Control/AppController.swift` | `run(_ command: KeyCommand)` | modify (Task 3) |
| `Tests/CoreTests/AppControllerTests/RunCommandTests.swift` | Exhaustive `run(_:)` per branch + clamps + mid-stroke | create (Task 3) |
| `Sources/AppKit/KeyMonitor.swift` | `NSEvent.addLocalMonitorForEvents` adapter; `handle(_:)` for tests | create (Task 4) |
| `Tests/AppKitTests/KeyMonitorTests.swift` | Synthesized `NSEvent.keyDown` → dispatch + pass-through | create (Task 4) |
| `Sources/App/main.swift` | Construct `KeyMonitor`; compose `onModeChanged` to call `keyMonitor.syncRegistration(for:)` | modify (Task 4) |
| `Sources/AppKit/MenubarController.swift` | "Drawing" submenu items dispatching `controller.run(_:)`; state checkmarks | modify (Task 5) |
| `Tests/AppKitTests/MenubarControllerTests.swift` | Submenu structure + key-equivalent + checkmark behavior | modify (Task 5) |
| `Sources/AppKit/ToolbarController.swift` | Tooltips on every widget; `"stroke size"` / `"stroke opacity"` labels | modify (Task 6) |
| `Tests/AppKitTests/ToolbarControllerTests.swift` | Tooltip assertions + label-text assertions | modify (Task 6) |

---

### Task 1: `KeyCommand` + `KeyBinding` + `KeyCommandRegistry`

Pure data and a static lookup table. Establishes the shared vocabulary the rest of the slices will consume.

**Files:**
- Create: `Sources/Core/Control/KeyCommand.swift`
- Create: `Tests/CoreTests/KeyCommandRegistryTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/KeyCommandRegistryTests.swift`:

```swift
// ABOUTME: Tests for KeyCommandRegistry — exhaustive lookup table for every
// ABOUTME: bound key plus reserved-slot assertions for future tools.

import Testing

@Suite("KeyCommandRegistry")
struct KeyCommandRegistryTests {
    private func lookup(_ ch: Character, shift: Bool = false) -> KeyCommand? {
        KeyCommandRegistry.command(for: KeyBinding(character: ch, shift: shift))
    }

    @Test("digits 1..8 resolve to pickColor 0..7")
    func digitsPickColor() {
        for i in 0..<8 {
            let ch = Character("\(i + 1)")
            #expect(lookup(ch) == .pickColor(i))
        }
    }

    @Test("'s' resolves to bumpSize(.up); shift+'s' resolves to bumpSize(.down)")
    func sizeBindings() {
        #expect(lookup("s") == .bumpSize(.up))
        #expect(lookup("s", shift: true) == .bumpSize(.down))
    }

    @Test("'o' resolves to bumpOpacity(.up); shift+'o' resolves to bumpOpacity(.down)")
    func opacityBindings() {
        #expect(lookup("o") == .bumpOpacity(.up))
        #expect(lookup("o", shift: true) == .bumpOpacity(.down))
    }

    @Test("'h' toggles hide; 'f' toggles auto-fade; 'c' clears")
    func toggleAndClearBindings() {
        #expect(lookup("h") == .toggleHide)
        #expect(lookup("f") == .toggleAutoFade)
        #expect(lookup("c") == .clear)
    }

    @Test("reserved slots (Space, 'e', 'p') resolve to nil")
    func reservedSlotsAreUnbound() {
        #expect(lookup(" ") == nil)
        #expect(lookup("e") == nil)
        #expect(lookup("p") == nil)
    }

    @Test("uppercase variants without shift are not silently mapped")
    func uppercaseRequiresShift() {
        // The registry uses lowercase + shift convention. Looking up a literal
        // uppercase character returns nil — callers should normalize via
        // charactersIgnoringModifiers first.
        #expect(lookup("S") == nil)
        #expect(lookup("O") == nil)
    }

    @Test("registry has exactly the documented number of bindings")
    func bindingCount() {
        // 8 colors + 4 size/opacity (s/S/o/O) + 3 toggles (h/f/c) = 15
        #expect(KeyCommandRegistry.bindings.count == 15)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test`
Expected: compile errors — `KeyCommand`, `KeyBinding`, `KeyCommandRegistry` not found.

- [ ] **Step 3: Create the Core module**

Create `Sources/Core/Control/KeyCommand.swift`:

```swift
// ABOUTME: Pure-Core key dispatch vocabulary. KeyCommand is the verb;
// ABOUTME: KeyBinding is the (character, shift) tuple; KeyCommandRegistry maps
// ABOUTME: between them and is the single source of truth for active-app shortcuts.

import Foundation

public enum KeyCommand: Equatable, Sendable {
    case pickColor(Int)
    case bumpSize(Direction)
    case bumpOpacity(Direction)
    case toggleHide
    case toggleAutoFade
    case clear

    public enum Direction: Equatable, Sendable {
        case up
        case down
    }
}

public struct KeyBinding: Hashable, Sendable {
    public let character: Character
    public let shift: Bool

    public init(character: Character, shift: Bool = false) {
        self.character = character
        self.shift = shift
    }
}

public enum KeyCommandRegistry {
    public static let bindings: [KeyBinding: KeyCommand] = [
        KeyBinding(character: "1"): .pickColor(0),
        KeyBinding(character: "2"): .pickColor(1),
        KeyBinding(character: "3"): .pickColor(2),
        KeyBinding(character: "4"): .pickColor(3),
        KeyBinding(character: "5"): .pickColor(4),
        KeyBinding(character: "6"): .pickColor(5),
        KeyBinding(character: "7"): .pickColor(6),
        KeyBinding(character: "8"): .pickColor(7),
        KeyBinding(character: "s"):                .bumpSize(.up),
        KeyBinding(character: "s", shift: true):   .bumpSize(.down),
        KeyBinding(character: "o"):                .bumpOpacity(.up),
        KeyBinding(character: "o", shift: true):   .bumpOpacity(.down),
        KeyBinding(character: "h"): .toggleHide,
        KeyBinding(character: "f"): .toggleAutoFade,
        KeyBinding(character: "c"): .clear
    ]

    public static func command(for binding: KeyBinding) -> KeyCommand? {
        bindings[binding]
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `just test`
Expected: 7 new `KeyCommandRegistryTests` pass.

- [ ] **Step 5: Lint clean**

Run: `just lint`
Expected: 0 violations; `Sources/Core/` import-discipline check still passes (the new file imports only `Foundation`).

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Control/KeyCommand.swift \
        Tests/CoreTests/KeyCommandRegistryTests.swift
git commit -m "$(cat <<'EOF'
Core: KeyCommand enum + KeyBinding + KeyCommandRegistry

Pure-Core vocabulary for active-app keyboard shortcuts. The static
binding table is the single source of truth consumed by the AppKit
KeyMonitor (next) and the menubar "Drawing" submenu. Reserved keys
(Space, e, p) are deliberately absent so the unit tests catch any
accidental future binding.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Extract `QuickPickPalette` to Core

Move the 8-color quick-pick palette out of `ToolbarController` (where it currently lives as `private static let quickPickRGB: [(r, g, b)]`) and into a named, shared Core model so the menu and tooltips can name colors. ToolbarController consumes the new shape.

**Files:**
- Create: `Sources/Core/Model/QuickPickPalette.swift`
- Create: `Tests/CoreTests/QuickPickPaletteTests.swift`
- Modify: `Sources/AppKit/ToolbarController.swift`
- Modify: `Tests/AppKitTests/ToolbarControllerTests.swift` (only if existing test code referenced the old tuple shape — it didn't last time we checked; verify)

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/QuickPickPaletteTests.swift`:

```swift
// ABOUTME: Tests for QuickPickPalette — the 8 named quick-pick colors shared
// ABOUTME: between ToolbarController, the menubar Drawing submenu, and tooltips.

import Testing

@Suite("QuickPickPalette")
struct QuickPickPaletteTests {
    @Test("palette has exactly 8 entries")
    func paletteSize() {
        #expect(QuickPickPalette.colors.count == 8)
    }

    @Test("each color has a non-empty name")
    func allColorsNamed() {
        for color in QuickPickPalette.colors {
            #expect(!color.name.isEmpty)
        }
    }

    @Test("RGB values are in 0...1")
    func rgbRange() {
        for color in QuickPickPalette.colors {
            #expect(color.r >= 0 && color.r <= 1)
            #expect(color.g >= 0 && color.g <= 1)
            #expect(color.b >= 0 && color.b <= 1)
        }
    }

    @Test("first entry is Black at (0,0,0)")
    func firstIsBlack() {
        let first = QuickPickPalette.colors[0]
        #expect(first.name == "Black")
        #expect(first.r == 0)
        #expect(first.g == 0)
        #expect(first.b == 0)
    }

    @Test("third entry is Red matching the original toolbar palette")
    func redIsCorrect() {
        let red = QuickPickPalette.colors[2]
        #expect(red.name == "Red")
        #expect(abs(red.r - 224.0/255.0) < 0.0001)
        #expect(abs(red.g - 49.0/255.0) < 0.0001)
        #expect(abs(red.b - 49.0/255.0) < 0.0001)
    }

    @Test("eighth entry is Violet")
    func eighthIsViolet() {
        let v = QuickPickPalette.colors[7]
        #expect(v.name == "Violet")
        #expect(abs(v.r - 156.0/255.0) < 0.0001)
        #expect(abs(v.g - 54.0/255.0) < 0.0001)
        #expect(abs(v.b - 181.0/255.0) < 0.0001)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test`
Expected: compile error — `QuickPickPalette` not found.

- [ ] **Step 3: Create the palette in Core**

Create `Sources/Core/Model/QuickPickPalette.swift`:

```swift
// ABOUTME: Named 8-color quick-pick palette used by the toolbar's color row,
// ABOUTME: the menubar's Drawing submenu, and tooltip text. RGB only — alpha
// ABOUTME: comes from the user's current opacity at the moment a color is picked.

import Foundation

public struct QuickPickColor: Equatable, Sendable {
    public let name: String
    public let r: Double
    public let g: Double
    public let b: Double

    public init(name: String, r: Double, g: Double, b: Double) {
        self.name = name
        self.r = r
        self.g = g
        self.b = b
    }
}

public enum QuickPickPalette {
    public static let colors: [QuickPickColor] = [
        QuickPickColor(name: "Black",  r: 0,             g: 0,             b: 0),
        QuickPickColor(name: "Gray",   r: 134.0 / 255.0, g: 142.0 / 255.0, b: 150.0 / 255.0),
        QuickPickColor(name: "Red",    r: 224.0 / 255.0, g:  49.0 / 255.0, b:  49.0 / 255.0),
        QuickPickColor(name: "Orange", r: 247.0 / 255.0, g: 103.0 / 255.0, b:   7.0 / 255.0),
        QuickPickColor(name: "Amber",  r: 245.0 / 255.0, g: 159.0 / 255.0, b:   0),
        QuickPickColor(name: "Green",  r:  47.0 / 255.0, g: 158.0 / 255.0, b:  68.0 / 255.0),
        QuickPickColor(name: "Blue",   r:  25.0 / 255.0, g: 113.0 / 255.0, b: 194.0 / 255.0),
        QuickPickColor(name: "Violet", r: 156.0 / 255.0, g:  54.0 / 255.0, b: 181.0 / 255.0)
    ]
}
```

- [ ] **Step 4: Migrate `ToolbarController` to consume the Core palette**

Modify `Sources/AppKit/ToolbarController.swift`:

1. Delete the `private static let quickPickRGB: [(r, g, b)]` block and the surrounding `swiftlint:disable large_tuple comma` / `swiftlint:enable` markers.
2. In `buildContent()`, change the color-row loop from iterating `Self.quickPickRGB` to iterating `QuickPickPalette.colors`. The inner body changes from:

   ```swift
   let rgb = Self.quickPickRGB[i]
   // ...
   btn.image = makeSwatchImage(r: rgb.r, g: rgb.g, b: rgb.b)
   ```

   to:

   ```swift
   let color = QuickPickPalette.colors[i]
   // ...
   btn.image = makeSwatchImage(r: color.r, g: color.g, b: color.b)
   ```

3. In `colorClicked(_:)`, change:

   ```swift
   let rgb = Self.quickPickRGB[sender.tag]
   let a = controller.currentColor.a
   controller.currentColor = RGBA(r: rgb.r, g: rgb.g, b: rgb.b, a: a)
   ```

   to:

   ```swift
   let c = QuickPickPalette.colors[sender.tag]
   let a = controller.currentColor.a
   controller.currentColor = RGBA(r: c.r, g: c.g, b: c.b, a: a)
   ```

4. Update the `rowStart` loop bound: change `stride(from: 0, to: Self.quickPickRGB.count, by: 2)` and the inner `Self.quickPickRGB.count` reference to `QuickPickPalette.colors.count`.

- [ ] **Step 5: Run the full check**

Run: `just check`
Expected:
- 6 new `QuickPickPaletteTests` pass.
- Existing `ToolbarControllerTests.quickPickPreservesAlpha` (which clicks index 1 and asserts Gray RGB) still passes.
- Lint clean — confirms the `swiftlint:disable large_tuple comma` block we removed is no longer needed.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Model/QuickPickPalette.swift \
        Tests/CoreTests/QuickPickPaletteTests.swift \
        Sources/AppKit/ToolbarController.swift
git commit -m "$(cat <<'EOF'
Core: QuickPickPalette — named 8-color quick-pick model

Moves the toolbar's private quickPickRGB tuple array into a shared
QuickPickColor struct in Core, with a name on each entry. Toolbar
consumes the new shape; menubar and tooltips will reuse it next.
The old swiftlint:disable for the large_tuple in ToolbarController
goes away with the tuple.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `RGBA.with(a:)` + `AppController.run(_:)`

Single Core method that the keyboard monitor and the menu will both call. Adds a small `RGBA.with(a:)` helper so opacity bumps don't have to spell out all four fields.

**Files:**
- Modify: `Sources/Core/Model/RGBA.swift`
- Modify: `Sources/Core/Control/AppController.swift`
- Create: `Tests/CoreTests/AppControllerTests/RunCommandTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/AppControllerTests/RunCommandTests.swift`:

```swift
// ABOUTME: Tests for AppController.run(_ command: KeyCommand) — exhaustive over
// ABOUTME: every KeyCommand case including clamps, mid-stroke behavior, and the
// ABOUTME: clear-finalizes-in-progress-stroke invariant.

import Testing

@Suite("AppController.run(_:)")
@MainActor
struct RunCommandTests {
    // swiftlint:disable:next large_tuple
    private func make() -> (AppController, Editor, VirtualClock) {
        let clock = VirtualClock()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(
            editor: editor,
            window: RecordingWindow(),
            detector: RecordingStationaryDetector(),
            clock: clock,
            ticker: RecordingFadeTicker()
        )
        return (controller, editor, clock)
    }

    @Test("pickColor sets RGB from the palette and preserves alpha")
    func pickColorPreservesAlpha() {
        let (c, _, _) = make()
        c.currentColor = RGBA(r: 0, g: 0, b: 0, a: 0.5)
        c.run(.pickColor(2))  // Red
        #expect(abs(c.currentColor.r - 224.0/255.0) < 0.0001)
        #expect(abs(c.currentColor.g - 49.0/255.0) < 0.0001)
        #expect(abs(c.currentColor.b - 49.0/255.0) < 0.0001)
        #expect(c.currentColor.a == 0.5)
    }

    @Test("pickColor with out-of-range index is a no-op")
    func pickColorOutOfRange() {
        let (c, _, _) = make()
        let before = c.currentColor
        c.run(.pickColor(99))
        c.run(.pickColor(-1))
        #expect(c.currentColor == before)
    }

    @Test("bumpSize(.up) multiplies width by 1.1")
    func bumpSizeUp() {
        let (c, _, _) = make()
        c.currentWidth = 10
        c.run(.bumpSize(.up))
        #expect(abs(c.currentWidth - 11.0) < 0.0001)
    }

    @Test("bumpSize(.down) divides width by 1.1")
    func bumpSizeDown() {
        let (c, _, _) = make()
        c.currentWidth = 11
        c.run(.bumpSize(.down))
        #expect(abs(c.currentWidth - 10.0) < 0.0001)
    }

    @Test("bumpSize(.up) clamps at 40")
    func bumpSizeUpClamp() {
        let (c, _, _) = make()
        c.currentWidth = 40
        c.run(.bumpSize(.up))
        #expect(c.currentWidth == 40)
    }

    @Test("bumpSize(.down) clamps at 1")
    func bumpSizeDownClamp() {
        let (c, _, _) = make()
        c.currentWidth = 1
        c.run(.bumpSize(.down))
        #expect(c.currentWidth == 1)
    }

    @Test("bumpOpacity(.up) adds 0.1 to alpha")
    func bumpOpacityUp() {
        let (c, _, _) = make()
        c.currentColor = RGBA(r: 0.2, g: 0.3, b: 0.4, a: 0.5)
        c.run(.bumpOpacity(.up))
        #expect(abs(c.currentColor.a - 0.6) < 0.0001)
        #expect(c.currentColor.r == 0.2)  // RGB unchanged
        #expect(c.currentColor.g == 0.3)
        #expect(c.currentColor.b == 0.4)
    }

    @Test("bumpOpacity(.down) subtracts 0.1 from alpha")
    func bumpOpacityDown() {
        let (c, _, _) = make()
        c.currentColor = RGBA(r: 0.2, g: 0.3, b: 0.4, a: 0.5)
        c.run(.bumpOpacity(.down))
        #expect(abs(c.currentColor.a - 0.4) < 0.0001)
    }

    @Test("bumpOpacity(.up) clamps at 1.0")
    func bumpOpacityUpClamp() {
        let (c, _, _) = make()
        c.currentColor = RGBA(r: 0, g: 0, b: 0, a: 1.0)
        c.run(.bumpOpacity(.up))
        #expect(c.currentColor.a == 1.0)
    }

    @Test("bumpOpacity(.down) clamps at 0.0")
    func bumpOpacityDownClamp() {
        let (c, _, _) = make()
        c.currentColor = RGBA(r: 0, g: 0, b: 0, a: 0.0)
        c.run(.bumpOpacity(.down))
        #expect(c.currentColor.a == 0.0)
    }

    @Test("toggleHide flips drawingsVisible")
    func toggleHideFlips() {
        let (c, _, _) = make()
        #expect(c.drawingsVisible == true)
        c.run(.toggleHide)
        #expect(c.drawingsVisible == false)
        c.run(.toggleHide)
        #expect(c.drawingsVisible == true)
    }

    @Test("toggleAutoFade flips autoFadeEnabled")
    func toggleAutoFadeFlips() {
        let (c, _, _) = make()
        #expect(c.autoFadeEnabled == false)
        c.run(.toggleAutoFade)
        #expect(c.autoFadeEnabled == true)
        c.run(.toggleAutoFade)
        #expect(c.autoFadeEnabled == false)
    }

    @Test("clear with in-progress stroke finalizes then empties the doc")
    func clearFinalizesInProgressStroke() {
        let (c, editor, _) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.pointerMoved(StrokePoint(x: 5, y: 5))
        // Mid-stroke clear:
        c.run(.clear)
        #expect(editor.doc.strokes.isEmpty == true)
        #expect(c.mode == .activeIdle)
        // One undo brings the just-finalized stroke back.
        _ = editor.undo()
        #expect(editor.doc.strokes.isEmpty == false)
    }

    @Test("pickColor mid-stroke leaves the in-progress stroke unchanged")
    func pickColorMidStrokeDoesNotRetro() {
        let (c, editor, _) = make()
        c.currentColor = RGBA(r: 1, g: 0, b: 0, a: 1)  // Red
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        guard let id = editor.currentStrokeId, let strokeBefore = editor.doc.strokes[id] else {
            Issue.record("expected an in-progress stroke")
            return
        }
        c.run(.pickColor(5))  // Green
        let strokeAfter = editor.doc.strokes[id]
        #expect(strokeAfter?.color == strokeBefore.color)  // unchanged
        #expect(c.currentColor != strokeBefore.color)      // controller moved
    }

    @Test("bumpSize mid-stroke leaves the in-progress stroke width unchanged")
    func bumpSizeMidStrokeDoesNotRetro() {
        let (c, editor, _) = make()
        c.currentWidth = 10
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        guard let id = editor.currentStrokeId, let strokeBefore = editor.doc.strokes[id] else {
            Issue.record("expected an in-progress stroke")
            return
        }
        c.run(.bumpSize(.up))
        let strokeAfter = editor.doc.strokes[id]
        #expect(strokeAfter?.width == strokeBefore.width)  // unchanged
        #expect(c.currentWidth > strokeBefore.width)        // controller moved
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test`
Expected: compile errors — `AppController.run` not found; `RGBA.with(a:)` may or may not be referenced depending on whether the test code uses it directly (this test file doesn't, so the error is only the run method).

- [ ] **Step 3: Add `RGBA.with(a:)`**

Modify `Sources/Core/Model/RGBA.swift`. Append below the existing init:

```swift
public extension RGBA {
    /// Returns a copy with `a` replaced. Used by AppController.run(.bumpOpacity:)
    /// to avoid spelling out all four fields.
    func with(a newAlpha: Double) -> RGBA {
        RGBA(r: r, g: g, b: b, a: newAlpha)
    }
}
```

- [ ] **Step 4: Add `AppController.run(_:)`**

Modify `Sources/Core/Control/AppController.swift`. Add to the end of the class body (before the closing brace), grouped with the other `public` methods:

```swift
public func run(_ command: KeyCommand) {
    switch command {
    case .pickColor(let i):
        guard i >= 0, i < QuickPickPalette.colors.count else { return }
        let c = QuickPickPalette.colors[i]
        currentColor = RGBA(r: c.r, g: c.g, b: c.b, a: currentColor.a)
    case .bumpSize(.up):
        currentWidth = min(40, currentWidth * 1.1)
    case .bumpSize(.down):
        currentWidth = max(1, currentWidth / 1.1)
    case .bumpOpacity(.up):
        currentColor = currentColor.with(a: min(1, currentColor.a + 0.1))
    case .bumpOpacity(.down):
        currentColor = currentColor.with(a: max(0, currentColor.a - 0.1))
    case .toggleHide:
        drawingsVisible.toggle()
    case .toggleAutoFade:
        autoFadeEnabled.toggle()
    case .clear:
        clear()
    }
}
```

- [ ] **Step 5: Run the full check**

Run: `just check`
Expected:
- 14 new `RunCommandTests` pass.
- All previously passing tests still green.
- Lint clean.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Model/RGBA.swift \
        Sources/Core/Control/AppController.swift \
        Tests/CoreTests/AppControllerTests/RunCommandTests.swift
git commit -m "$(cat <<'EOF'
Core: AppController.run(_ command: KeyCommand) single dispatch entry

Centralizes every keyboard shortcut's effect in one place: pickColor
preserves alpha, bumpSize is multiplicative (×1.1, clamped 1..40),
bumpOpacity is additive (±0.1, clamped 0..1), toggleHide/toggleAutoFade
flip booleans, clear finalizes any in-progress stroke before emptying
the doc. RGBA gains a small with(a:) helper to keep bumpOpacity tidy.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `KeyMonitor` + `main.swift` wiring

The AppKit adapter that turns NSEvent keyDowns into `controller.run(_:)` calls. Install/uninstall is gated on `mode != .inactive` so we never intercept keys when fiti is click-through.

**Files:**
- Create: `Sources/AppKit/KeyMonitor.swift`
- Create: `Tests/AppKitTests/KeyMonitorTests.swift`
- Modify: `Sources/App/main.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/AppKitTests/KeyMonitorTests.swift`:

```swift
// ABOUTME: Tests for KeyMonitor's pure NSEvent → dispatch path. Synthesizes
// ABOUTME: NSEvent.keyDown via NSEvent.keyEvent(with:...) and asserts that
// ABOUTME: handle() either dispatches and swallows or passes the event through.

import AppKit
import Testing

@Suite("KeyMonitor")
@MainActor
struct KeyMonitorTests {
    // swiftlint:disable:next large_tuple
    private func make() -> (KeyMonitor, AppController, Editor) {
        let clock = VirtualClock()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(
            editor: editor,
            window: RecordingWindow(),
            detector: RecordingStationaryDetector(),
            clock: clock,
            ticker: RecordingFadeTicker()
        )
        let monitor = KeyMonitor(controller: controller)
        return (monitor, controller, editor)
    }

    private func keyEvent(_ chars: String, shift: Bool = false, command: Bool = false) -> NSEvent {
        var flags: NSEvent.ModifierFlags = []
        if shift { flags.insert(.shift) }
        if command { flags.insert(.command) }
        return NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: chars,
            charactersIgnoringModifiers: chars,
            isARepeat: false,
            keyCode: 0
        )!
    }

    @Test("bound key dispatches and is swallowed")
    func boundKeyDispatched() {
        let (monitor, controller, _) = make()
        let before = controller.currentColor
        let result = monitor.handle(keyEvent("3"))  // Red
        #expect(result == nil, "bound key should be swallowed (nil return)")
        #expect(controller.currentColor != before)
    }

    @Test("shifted bound key dispatches the shifted variant")
    func shiftedKeyDispatched() {
        let (monitor, controller, _) = make()
        controller.currentWidth = 10
        _ = monitor.handle(keyEvent("s", shift: true))  // bumpSize(.down)
        #expect(controller.currentWidth < 10)
    }

    @Test("unbound key is passed through unchanged")
    func unboundKeyPassesThrough() {
        let (monitor, controller, _) = make()
        let before = controller.currentColor
        let event = keyEvent("x")
        let result = monitor.handle(event)
        #expect(result === event, "unbound key should return the original event")
        #expect(controller.currentColor == before)
    }

    @Test("Cmd-modified bound key passes through (menubar's job, not ours)")
    func commandModifierPassesThrough() {
        let (monitor, controller, _) = make()
        let before = controller.currentWidth
        let event = keyEvent("s", command: true)
        let result = monitor.handle(event)
        #expect(result === event)
        #expect(controller.currentWidth == before)
    }

    @Test("multi-character chars (dead-key composition) pass through")
    func multiCharPassesThrough() {
        let (monitor, controller, _) = make()
        let before = controller.currentColor
        let event = keyEvent("´e")  // accent composition
        let result = monitor.handle(event)
        #expect(result === event)
        #expect(controller.currentColor == before)
    }

    @Test("clear dispatches via run(.clear)")
    func clearDispatches() {
        let (monitor, controller, editor) = make()
        controller.activate()
        controller.pointerDown(StrokePoint(x: 0, y: 0))
        controller.pointerUp()
        #expect(editor.doc.strokes.isEmpty == false)
        _ = monitor.handle(keyEvent("c"))
        #expect(editor.doc.strokes.isEmpty == true)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test`
Expected: compile error — `KeyMonitor` not found.

- [ ] **Step 3: Create `KeyMonitor`**

Create `Sources/AppKit/KeyMonitor.swift`:

```swift
// ABOUTME: Active-app keyboard shortcut adapter. Installs an NSEvent local
// ABOUTME: monitor while mode != .inactive; translates each keyDown into a
// ABOUTME: KeyCommand via KeyCommandRegistry and dispatches AppController.run(_:).

import AppKit

@MainActor
public final class KeyMonitor {
    private let controller: AppController
    private var monitor: Any?

    public init(controller: AppController) {
        self.controller = controller
    }

    deinit { uninstallSync() }

    /// Called from main.swift's onModeChanged composition. Installs the local
    /// monitor while fiti is active so we never intercept keys when inactive.
    public func syncRegistration(for mode: AppController.Mode) {
        if mode == .inactive {
            uninstall()
        } else {
            install()
        }
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func uninstall() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    nonisolated private func uninstallSync() {
        // Called from deinit; NSEvent.removeMonitor is safe to call from any thread.
        if let m = monitor {
            NSEvent.removeMonitor(m)
        }
    }

    /// Pure translation, exposed for unit tests. Returns nil to swallow the
    /// event (bound key dispatched); returns the original event to pass it
    /// through (unbound, Cmd-modified, or multi-character composition).
    internal func handle(_ event: NSEvent) -> NSEvent? {
        guard let chars = event.charactersIgnoringModifiers,
              chars.count == 1,
              let ch = chars.first else {
            return event
        }
        // Cmd combos belong to the menubar (Cmd+Z, Cmd+K, Cmd+S, ...).
        if event.modifierFlags.contains(.command) { return event }
        let binding = KeyBinding(character: ch, shift: event.modifierFlags.contains(.shift))
        guard let command = KeyCommandRegistry.command(for: binding) else { return event }
        controller.run(command)
        return nil
    }
}
```

A note on the `deinit` shape: the existing `MenubarController` uses `isolated deinit` to call a MainActor-bound API. `NSEvent.removeMonitor(_:)` is documented as safe on any thread, so a `nonisolated` cleanup function is appropriate here — we don't need actor isolation in deinit.

- [ ] **Step 4: Wire `KeyMonitor` in `main.swift`**

Modify `Sources/App/main.swift`. The existing `composeControllerCallbacks()` method already chains handlers on `controller.onModeChanged`. Extend the chain to also call `keyMonitor.syncRegistration(for:)`.

1. Add a stored property near the other AppKit controllers (`menubarController`, `toolbar`, etc.):

   ```swift
   private var keyMonitor: KeyMonitor!
   ```

2. Construct it where the other controllers are constructed (after `controller` exists). The natural slot is alongside `toolbar` and `menubarController`:

   ```swift
   keyMonitor = KeyMonitor(controller: controller)
   ```

3. Update `composeControllerCallbacks()`:

   ```swift
   private func composeControllerCallbacks() {
       // Compose onModeChanged: menubar (icon) + toolbar (panel visibility)
       // + keyMonitor (install/uninstall local NSEvent monitor).
       let menubarModeHandler = controller.onModeChanged
       controller.onModeChanged = { [weak self] mode in
           menubarModeHandler?(mode)
           self?.toolbar.updateVisibility(for: mode)
           self?.keyMonitor.syncRegistration(for: mode)
       }
       // ... existing onDrawingsVisibilityChanged + onFadeOpacityChanged ...
   }
   ```

   Order in the composed closure does not matter functionally; group the new call next to the toolbar's visibility update to keep mode-driven side effects together.

4. After `composeControllerCallbacks()` runs the first time, the monitor is *not* installed because the initial `mode` is `.inactive`. The first activate (`Opt+F`) flips mode to `.activeIdle` and triggers the install.

- [ ] **Step 5: Run the full check**

Run: `just check`
Expected:
- 6 new `KeyMonitorTests` pass.
- All previously-passing tests still green.
- Build succeeds.
- Lint clean.

- [ ] **Step 6: Commit**

```bash
git add Sources/AppKit/KeyMonitor.swift \
        Sources/App/main.swift \
        Tests/AppKitTests/KeyMonitorTests.swift
git commit -m "$(cat <<'EOF'
AppKit + App: KeyMonitor — NSEvent local monitor for active-app shortcuts

Owns an NSEvent.addLocalMonitorForEvents(matching: .keyDown) handler
while AppController.mode != .inactive. Each event becomes a KeyBinding,
looked up in KeyCommandRegistry, and dispatched via controller.run(_:).
Cmd-modified keys pass through unchanged (menubar's job). Unit tests
exercise the pure handle(_:) translator via synthesized NSEvents.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: `MenubarController` "Drawing" submenu

Add a "Drawing" submenu before the existing "Clear" item. Submenu items have `keyEquivalent`s for display, dispatch via `controller.run(_:)` on click, and the hide/auto-fade items show `state` checkmarks reflecting current toggle state.

**Files:**
- Modify: `Sources/AppKit/MenubarController.swift`
- Modify: `Tests/AppKitTests/MenubarControllerTests.swift`

- [ ] **Step 1: Write the failing tests**

Append a new suite to `Tests/AppKitTests/MenubarControllerTests.swift` (do not modify existing suites). Pattern matches the existing `MenubarController` tests.

```swift
@Suite("MenubarController Drawing submenu")
@MainActor
struct MenubarControllerDrawingSubmenuTests {
    // swiftlint:disable:next large_tuple
    private func make() -> (MenubarController, AppController, Editor) {
        let clock = VirtualClock()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(
            editor: editor,
            window: RecordingWindow(),
            detector: RecordingStationaryDetector(),
            clock: clock,
            ticker: RecordingFadeTicker()
        )
        let mb = MenubarController(controller: controller, editor: editor, onOpenPreferences: {})
        return (mb, controller, editor)
    }

    private func drawingSubmenu(_ mb: MenubarController) -> NSMenu? {
        mb.menu.item(withTitle: "Drawing")?.submenu
    }

    @Test("Drawing submenu exists")
    func submenuExists() {
        let (mb, _, _) = make()
        #expect(drawingSubmenu(mb) != nil)
    }

    @Test("Drawing submenu has 8 color items with keyEquivalents 1..8")
    func colorItems() {
        let (mb, _, _) = make()
        let sub = drawingSubmenu(mb)!
        let colors = QuickPickPalette.colors
        for i in 0..<8 {
            let item = sub.item(withTitle: colors[i].name)
            #expect(item != nil, "expected menu item titled \(colors[i].name)")
            #expect(item?.keyEquivalent == "\(i + 1)")
            #expect(item?.keyEquivalentModifierMask == [])
        }
    }

    @Test("Larger stroke item has keyEquivalent 's' with no modifier")
    func largerStrokeKey() {
        let (mb, _, _) = make()
        let item = drawingSubmenu(mb)!.item(withTitle: "Larger stroke")
        #expect(item?.keyEquivalent == "s")
        #expect(item?.keyEquivalentModifierMask == [])
    }

    @Test("Smaller stroke item has keyEquivalent 's' with shift")
    func smallerStrokeKey() {
        let (mb, _, _) = make()
        let item = drawingSubmenu(mb)!.item(withTitle: "Smaller stroke")
        #expect(item?.keyEquivalent == "s")
        #expect(item?.keyEquivalentModifierMask == [.shift])
    }

    @Test("More opaque item has keyEquivalent 'o' with no modifier")
    func moreOpaqueKey() {
        let (mb, _, _) = make()
        let item = drawingSubmenu(mb)!.item(withTitle: "More opaque")
        #expect(item?.keyEquivalent == "o")
        #expect(item?.keyEquivalentModifierMask == [])
    }

    @Test("Less opaque item has keyEquivalent 'o' with shift")
    func lessOpaqueKey() {
        let (mb, _, _) = make()
        let item = drawingSubmenu(mb)!.item(withTitle: "Less opaque")
        #expect(item?.keyEquivalent == "o")
        #expect(item?.keyEquivalentModifierMask == [.shift])
    }

    @Test("Hide drawings item shows checkmark when drawingsVisible is false")
    func hideStateCheckmark() {
        let (mb, controller, _) = make()
        let item = drawingSubmenu(mb)!.item(withTitle: "Hide drawings")!
        // Initial: drawingsVisible == true → item.state == .off
        mb.menu.delegate?.menuNeedsUpdate?(mb.menu)
        #expect(item.state == .off)
        controller.drawingsVisible = false
        mb.menu.delegate?.menuNeedsUpdate?(mb.menu)
        #expect(item.state == .on)
    }

    @Test("Auto-fade item shows checkmark when autoFadeEnabled is true")
    func autoFadeStateCheckmark() {
        let (mb, controller, _) = make()
        let item = drawingSubmenu(mb)!.item(withTitle: "Auto-fade")!
        mb.menu.delegate?.menuNeedsUpdate?(mb.menu)
        #expect(item.state == .off)
        controller.autoFadeEnabled = true
        mb.menu.delegate?.menuNeedsUpdate?(mb.menu)
        #expect(item.state == .on)
    }

    @Test("clicking a color submenu item dispatches the matching pickColor")
    func clickColorDispatches() {
        let (mb, controller, _) = make()
        let red = drawingSubmenu(mb)!.item(withTitle: "Red")!
        // Synthesize a click by invoking the action selector directly.
        _ = red.target?.perform(red.action, with: red)
        #expect(abs(controller.currentColor.r - 224.0/255.0) < 0.0001)
    }

    @Test("clicking Larger stroke dispatches bumpSize(.up)")
    func clickLargerStrokeDispatches() {
        let (mb, controller, _) = make()
        controller.currentWidth = 10
        let item = drawingSubmenu(mb)!.item(withTitle: "Larger stroke")!
        _ = item.target?.perform(item.action, with: item)
        #expect(controller.currentWidth > 10)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test`
Expected: compile-OK but assertions fail — `Drawing` submenu doesn't exist yet.

- [ ] **Step 3: Build the submenu in `MenubarController`**

Modify `Sources/AppKit/MenubarController.swift`. Substantial additions:

1. Add a stored dictionary tracking submenu items keyed by `KeyCommand` so `menuNeedsUpdate` can update their `state`:

   ```swift
   private var drawingItems: [KeyCommand: NSMenuItem] = [:]
   ```

2. In `init`, build the submenu before the existing menu assembly. Insert it just before the existing `clearItem`:

   ```swift
   let drawingMenu = NSMenu(title: "Drawing")
   buildDrawingSubmenu(drawingMenu)
   let drawingItem = NSMenuItem(title: "Drawing", action: nil, keyEquivalent: "")
   drawingItem.submenu = drawingMenu
   // ... menu.addItem order: ... activate, deactivate, sep, preferences, sep, drawingItem, clearItem, undo, redo, sep, quit
   ```

3. Add the builder method:

   ```swift
   private func buildDrawingSubmenu(_ menu: NSMenu) {
       // Colors 1..8
       for (i, color) in QuickPickPalette.colors.enumerated() {
           let item = makeDrawingItem(
               title: color.name,
               key: "\(i + 1)",
               modifiers: [],
               command: .pickColor(i)
           )
           menu.addItem(item)
       }
       menu.addItem(.separator())
       menu.addItem(makeDrawingItem(title: "Larger stroke",  key: "s", modifiers: [],       command: .bumpSize(.up)))
       menu.addItem(makeDrawingItem(title: "Smaller stroke", key: "s", modifiers: [.shift], command: .bumpSize(.down)))
       menu.addItem(.separator())
       menu.addItem(makeDrawingItem(title: "More opaque",    key: "o", modifiers: [],       command: .bumpOpacity(.up)))
       menu.addItem(makeDrawingItem(title: "Less opaque",    key: "o", modifiers: [.shift], command: .bumpOpacity(.down)))
       menu.addItem(.separator())
       menu.addItem(makeDrawingItem(title: "Hide drawings",  key: "h", modifiers: [],       command: .toggleHide))
       menu.addItem(makeDrawingItem(title: "Auto-fade",      key: "f", modifiers: [],       command: .toggleAutoFade))
   }

   private func makeDrawingItem(title: String, key: String, modifiers: NSEvent.ModifierFlags,
                                command: KeyCommand) -> NSMenuItem {
       let item = NSMenuItem(title: title, action: #selector(runDrawingCommand(_:)), keyEquivalent: key)
       item.keyEquivalentModifierMask = modifiers
       item.target = self
       item.representedObject = CommandBox(command: command)
       drawingItems[command] = item
       return item
   }
   ```

   `CommandBox` is a small NSObject wrapper because `representedObject` is `Any?`. Place it at the bottom of the file:

   ```swift
   private final class CommandBox: NSObject {
       let command: KeyCommand
       init(command: KeyCommand) { self.command = command }
   }
   ```

4. Add the action method:

   ```swift
   @objc private func runDrawingCommand(_ sender: NSMenuItem) {
       guard let box = sender.representedObject as? CommandBox else { return }
       controller.run(box.command)
   }
   ```

5. Update `menuNeedsUpdate` to set checkmarks:

   ```swift
   public func menuNeedsUpdate(_ menu: NSMenu) {
       let active = controller.mode != .inactive
       activateItem.isEnabled = !active
       deactivateItem.isEnabled = active
       undoItem.isEnabled = editor.canUndo
       redoItem.isEnabled = editor.canRedo
       drawingItems[.toggleHide]?.state = controller.drawingsVisible ? .off : .on
       drawingItems[.toggleAutoFade]?.state = controller.autoFadeEnabled ? .on : .off
   }
   ```

- [ ] **Step 4: Run the full check**

Run: `just check`
Expected:
- 11 new `MenubarControllerDrawingSubmenuTests` pass.
- All existing menubar tests still pass.
- Lint clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/MenubarController.swift \
        Tests/AppKitTests/MenubarControllerTests.swift
git commit -m "$(cat <<'EOF'
AppKit: menubar gains a Drawing submenu mirroring active-app shortcuts

Each color, size, opacity, hide, and auto-fade binding has a menu item
under "Drawing" with its keyEquivalent displayed (1..8, s, S, o, O, h, f).
Click dispatches through controller.run(_:) — same path as KeyMonitor.
Hide and Auto-fade items toggle a checkmark via menuNeedsUpdate.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: `ToolbarController` tooltips + label text

Final slice. Every widget in the toolbar gets a tooltip naming the action and (where applicable) the shortcut. The two slider labels change from `"w"` / `"o"` to `"stroke size"` / `"stroke opacity"`.

**Files:**
- Modify: `Sources/AppKit/ToolbarController.swift`
- Modify: `Tests/AppKitTests/ToolbarControllerTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/AppKitTests/ToolbarControllerTests.swift` (add a new `@Suite`, do not modify existing suites). Also add a few inline assertions in `ToolbarControllerAutoFadeTests` for the auto-fade button tooltip, since it's state-dependent — but a separate suite for the rest keeps it scannable.

```swift
@Suite("ToolbarController tooltips and labels")
@MainActor
struct ToolbarControllerTooltipTests {
    // swiftlint:disable:next large_tuple
    private func make() -> (ToolbarController, AppController) {
        let clock = VirtualClock()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(
            editor: editor,
            window: RecordingWindow(),
            detector: RecordingStationaryDetector(),
            clock: clock,
            ticker: RecordingFadeTicker()
        )
        let toolbar = ToolbarController(controller: controller,
                                        defaults: UserDefaults(suiteName: UUID().uuidString)!)
        return (toolbar, controller)
    }

    @Test("color swatches have name + shortcut tooltips")
    func swatchTooltips() {
        let (toolbar, _) = make()
        for i in 0..<8 {
            let expected = "\(QuickPickPalette.colors[i].name) — \(i + 1)"
            #expect(toolbar.testOnly_swatchTooltip(at: i) == expected)
        }
    }

    @Test("color well has 'Custom color' tooltip")
    func colorWellTooltip() {
        let (toolbar, _) = make()
        #expect(toolbar.testOnly_colorWellTooltip == "Custom color")
    }

    @Test("width slider has 'Stroke size — s / S' tooltip")
    func widthSliderTooltip() {
        let (toolbar, _) = make()
        #expect(toolbar.testOnly_widthSliderTooltip == "Stroke size — s / S")
    }

    @Test("opacity slider has 'Stroke opacity — o / O' tooltip")
    func opacitySliderTooltip() {
        let (toolbar, _) = make()
        #expect(toolbar.testOnly_opacitySliderTooltip == "Stroke opacity — o / O")
    }

    @Test("hide button tooltip flips with drawingsVisible")
    func hideButtonTooltip() {
        let (toolbar, controller) = make()
        #expect(toolbar.testOnly_hideButtonTooltip == "Hide drawings — h")
        controller.drawingsVisible = false
        #expect(toolbar.testOnly_hideButtonTooltip == "Show drawings — h")
    }

    @Test("auto-fade button tooltip flips with autoFadeEnabled")
    func autoFadeButtonTooltip() {
        let (toolbar, controller) = make()
        #expect(toolbar.testOnly_autoFadeTooltip == "Auto-fade off — f")
        controller.autoFadeEnabled = true
        #expect(toolbar.testOnly_autoFadeTooltip == "Auto-fade on — f")
    }

    @Test("width label text is 'stroke size'")
    func widthLabelText() {
        let (toolbar, _) = make()
        #expect(toolbar.testOnly_widthLabelText == "stroke size")
    }

    @Test("opacity label text is 'stroke opacity'")
    func opacityLabelText() {
        let (toolbar, _) = make()
        #expect(toolbar.testOnly_opacityLabelText == "stroke opacity")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test`
Expected: compile errors — the new `testOnly_*` accessors don't exist yet.

- [ ] **Step 3: Modify `ToolbarController`**

Modify `Sources/AppKit/ToolbarController.swift`:

1. Store references to the two slider labels (currently created inline as anonymous `NSTextField`s). Add stored properties:

   ```swift
   private let widthLabel = NSTextField(labelWithString: "stroke size")
   private let opacityLabel = NSTextField(labelWithString: "stroke opacity")
   ```

   And update both labels' style (small font, centered) the same way the existing `label(_:)` helper does. The simplest move: keep using `label(_:)` for the construction-time text but capture the returned NSTextField:

   ```swift
   // In init, replace existing `private let widthLabel/opacityLabel = ...` if added,
   // and in buildContent() replace:
   //   stack.addArrangedSubview(label("w"))
   //   stack.addArrangedSubview(label("o"))
   // with the stored labels (constructed once in init, styled the same as label() does).
   ```

   Concretely, change `label(_ text: String)` to take an optional `into:` NSTextField parameter, or just inline the styling at construction. Pragmatic version:

   ```swift
   // Stored properties at the top of the class:
   private let widthLabel = NSTextField(labelWithString: "stroke size")
   private let opacityLabel = NSTextField(labelWithString: "stroke opacity")

   // In buildContent(), in the slider sections, replace:
   //   stack.addArrangedSubview(label("w"))
   // with:
   //   styleSliderLabel(widthLabel)
   //   stack.addArrangedSubview(widthLabel)
   // (same for opacityLabel)

   private func styleSliderLabel(_ field: NSTextField) {
       field.font = .systemFont(ofSize: 10)
       field.alignment = .center
   }
   ```

   The existing `label(_:)` helper can stay for any other use (or be deleted if no longer referenced).

2. Set tooltips on every widget. In `buildContent()`, after each widget is constructed:

   ```swift
   colorWell.toolTip = "Custom color"
   widthSlider.toolTip = "Stroke size — s / S"
   opacitySlider.toolTip = "Stroke opacity — o / O"
   ```

   In the swatch-row loop, after `btn.image = makeSwatchImage(...)`:

   ```swift
   btn.toolTip = "\(color.name) — \(i + 1)"
   ```

3. Update the state-dependent tooltip helpers. In `updateHideButtonGlyph(visible:)`, append:

   ```swift
   hideButton.toolTip = visible ? "Hide drawings — h" : "Show drawings — h"
   ```

   In `updateAutoFadeGlyph(enabled:)`, append:

   ```swift
   autoFadeButton.toolTip = enabled ? "Auto-fade on — f" : "Auto-fade off — f"
   ```

4. Add test-only accessors (inside the existing `// swiftlint:disable identifier_name` ... `// swiftlint:enable identifier_name` block):

   ```swift
   internal func testOnly_swatchTooltip(at index: Int) -> String? {
       guard index < quickPickButtons.count else { return nil }
       return quickPickButtons[index].toolTip
   }
   internal var testOnly_colorWellTooltip: String? { colorWell.toolTip }
   internal var testOnly_widthSliderTooltip: String? { widthSlider.toolTip }
   internal var testOnly_opacitySliderTooltip: String? { opacitySlider.toolTip }
   internal var testOnly_hideButtonTooltip: String? { hideButton.toolTip }
   internal var testOnly_autoFadeTooltip: String? { autoFadeButton.toolTip }
   internal var testOnly_widthLabelText: String { widthLabel.stringValue }
   internal var testOnly_opacityLabelText: String { opacityLabel.stringValue }
   ```

   The `testOnly_swatchTooltip(at:)` is a method, not a computed property — keep it outside the identifier_name disable block, alongside `testOnly_clickQuickPick`.

- [ ] **Step 4: Run the full check**

Run: `just check`
Expected:
- 8 new `ToolbarControllerTooltipTests` pass.
- All existing toolbar tests still pass.
- Lint clean.

- [ ] **Step 5: Manual smoke test**

```bash
just run-bg
```

Then:
1. Press `Opt+F` to activate.
2. Press `1` through `8` — current color cycles through the palette.
3. Press `s` repeatedly — stroke size grows. Watch the cursor diameter increase.
4. Press `Shift+S` — stroke size shrinks.
5. Press `o` / `Shift+O` — opacity changes (the cursor's ring alpha changes).
6. Press `h` — drawings hide. Press `h` again — drawings show.
7. Press `f` — toolbar clock glyph shows "on" state. Wait 10s with a stroke down to confirm auto-fade fires. Press `f` again — back to off.
8. Draw a stroke, then press `c` — strokes clear.
9. Hover over each toolbar control — tooltip text matches the spec.
10. Open the menubar → Drawing submenu — verify items render with key equivalents and checkmarks reflect current state.
11. Press `Opt+F` to deactivate. Press `1` — nothing happens (monitor is uninstalled). Type `s` in TextEdit — character types normally.

```bash
just stop
```

- [ ] **Step 6: Commit**

```bash
git add Sources/AppKit/ToolbarController.swift \
        Tests/AppKitTests/ToolbarControllerTests.swift
git commit -m "$(cat <<'EOF'
AppKit: toolbar gains tooltips on every widget + stroke-size/opacity labels

Each toolbar widget surfaces its shortcut binding via NSView.toolTip:
swatches read "Black — 1" etc., sliders read "Stroke size — s / S" and
"Stroke opacity — o / O", buttons read "Hide drawings — h" / "Auto-fade
on — f" with state-dependent text. The slider labels change from "w"/"o"
to "stroke size"/"stroke opacity" to match the keyboard binding naming.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Acceptance criteria (mirrors the spec)

- [ ] Pressing `1`–`8` while fiti is active picks the matching palette color, preserving alpha.
- [ ] Pressing `s` / `S` adjusts stroke size by ×1.1 / ÷1.1, clamped `[1, 40]`.
- [ ] Pressing `o` / `O` adjusts opacity by ±0.1, clamped `[0, 1]`.
- [ ] Pressing `h` toggles hide/show. Pressing `f` toggles auto-fade. Pressing `c` clears.
- [ ] Shortcuts only fire while `mode != .inactive`. Inactive, every key passes through.
- [ ] Cmd-modified keystrokes (`Cmd+Z`, `Cmd+K`, etc.) are not intercepted by `KeyMonitor`.
- [ ] Mid-stroke shortcut presses do not retroactively modify the in-progress stroke.
- [ ] "Drawing" submenu renders on the menubar status menu with key equivalents and checkmarks.
- [ ] Toolbar widgets show tooltips matching the spec on hover.
- [ ] Stroke size / opacity slider labels read "stroke size" / "stroke opacity".
- [ ] `Sources/Core/` has zero AppKit/CoreGraphics/Network/SwiftUI imports (`just lint` enforces).
- [ ] Full test suite finishes in under 5 seconds (`just check`).
