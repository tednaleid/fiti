# fiti Menubar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the menubar feature designed in [`2026-05-16-fiti-menubar-design.md`](./2026-05-16-fiti-menubar-design.md): a persistent menu-bar status item with a two-state SF Symbol icon, a menu mirroring the existing keyboard shortcuts (Activate, Deactivate, Clear, Undo, Redo, Quit), and the small Core hooks that let it work.

**Architecture:** Pure adapter in `Sources/AppKit/MenubarController.swift` driven by two minor Core additions — `Editor.canUndo` / `Editor.canRedo` and `AppController.onModeChanged` (a single optional closure published from a `didSet` on `mode`). One line of wiring in `Sources/App/main.swift`. No new ports.

**Tech Stack:** Swift 6, AppKit (`NSStatusBar`, `NSStatusItem`, `NSMenu`, `NSMenuDelegate`), SF Symbols (`theatermask.and.paintbrush` / `theatermask.and.paintbrush.fill`), Swift Testing.

---

## File structure

**Modify:**
- `Sources/Core/Editor/Editor.swift` — add two computed properties
- `Sources/Core/Control/AppController.swift` — add an `onModeChanged` closure and a `didSet` observer on `mode`
- `Sources/App/main.swift` — wire the menubar in `applicationDidFinishLaunching`

**Create:**
- `Sources/AppKit/MenubarController.swift` — the adapter (single file)
- `Tests/CoreTests/EditorTests/EditorCanUndoCanRedoTests.swift`
- `Tests/CoreTests/AppControllerTests/OnModeChangedTests.swift`
- `Tests/AppKitTests/MenubarControllerTests.swift`

xcodegen auto-discovers new files under the `Sources/` and `Tests/` source globs in `project.yml`. No project.yml edits required.

---

## Task 1: Editor.canUndo / Editor.canRedo

**Files:**
- Modify: `Sources/Core/Editor/Editor.swift`
- Create: `Tests/CoreTests/EditorTests/EditorCanUndoCanRedoTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/EditorTests/EditorCanUndoCanRedoTests.swift`:

```swift
// ABOUTME: Tests for Editor.canUndo / canRedo — the menubar reads these to
// ABOUTME: decide whether to enable the Undo / Redo menu items.

import Testing

@Suite("Editor canUndo / canRedo")
@MainActor
struct EditorCanUndoCanRedoTests {
    private func makeEditor() -> Editor {
        Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
    }

    @Test("empty editor has no undo or redo")
    func empty() {
        let editor = makeEditor()
        #expect(editor.canUndo == false)
        #expect(editor.canRedo == false)
    }

    @Test("canUndo is true after a completed stroke")
    func afterStroke() {
        let editor = makeEditor()
        _ = editor.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        editor.endStroke()
        #expect(editor.canUndo == true)
        #expect(editor.canRedo == false)
    }

    @Test("canRedo is true after undo")
    func afterUndo() {
        let editor = makeEditor()
        _ = editor.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        editor.endStroke()
        _ = editor.undo()
        #expect(editor.canUndo == false)
        #expect(editor.canRedo == true)
    }
}
```

- [ ] **Step 2: Run tests, expect failure**

Run: `just test`
Expected: build failure — `canUndo` / `canRedo` do not exist on `Editor`.

- [ ] **Step 3: Add the computed properties**

In `Sources/Core/Editor/Editor.swift`, immediately after the `redoStack` declaration (currently around line 16):

```swift
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
```

- [ ] **Step 4: Run tests, expect pass**

Run: `just test`
Expected: 74 tests pass (71 prior + 3 new in CoreTests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Editor/Editor.swift Tests/CoreTests/EditorTests/EditorCanUndoCanRedoTests.swift
git commit -m "$(cat <<'EOF'
Editor: add canUndo / canRedo

Menubar enabled-state checks need these without forcing callers to
poke at undoStack.count. Trivial computed properties over the
existing stacks.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: AppController.onModeChanged

**Files:**
- Modify: `Sources/Core/Control/AppController.swift`
- Create: `Tests/CoreTests/AppControllerTests/OnModeChangedTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/AppControllerTests/OnModeChangedTests.swift`:

```swift
// ABOUTME: Tests for AppController.onModeChanged — fires whenever `mode`
// ABOUTME: transitions, via a didSet observer. Single subscriber for now.

import Testing

@Suite("AppController onModeChanged")
@MainActor
struct OnModeChangedTests {
    private func make() -> (AppController, RecordingWindow) {
        let window = RecordingWindow()
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(editor: editor, window: window)
        return (controller, window)
    }

    @Test("activate publishes .activeIdle")
    func activate() {
        let (c, _) = make()
        var received: [AppController.Mode] = []
        c.onModeChanged = { received.append($0) }
        c.activate()
        #expect(received == [.activeIdle])
    }

    @Test("deactivate publishes .inactive")
    func deactivate() {
        let (c, _) = make()
        c.activate()
        var received: [AppController.Mode] = []
        c.onModeChanged = { received.append($0) }
        c.deactivate()
        #expect(received == [.inactive])
    }

    @Test("pointerDown publishes .activeDrawing")
    func pointerDown() {
        let (c, _) = make()
        c.activate()
        var received: [AppController.Mode] = []
        c.onModeChanged = { received.append($0) }
        c.pointerDown(StrokePoint(x: 0, y: 0))
        #expect(received == [.activeDrawing])
    }

    @Test("pointerUp returns mode to .activeIdle")
    func pointerUp() {
        let (c, _) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        var received: [AppController.Mode] = []
        c.onModeChanged = { received.append($0) }
        c.pointerUp()
        #expect(received == [.activeIdle])
    }

    @Test("clear mid-stroke publishes .activeIdle")
    func clearMidStroke() {
        let (c, _) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        var received: [AppController.Mode] = []
        c.onModeChanged = { received.append($0) }
        c.clear()
        #expect(received == [.activeIdle])
    }

    @Test("no callback fires when mode does not actually change")
    func noOpTransitions() {
        let (c, _) = make()
        c.activate()
        var received: [AppController.Mode] = []
        c.onModeChanged = { received.append($0) }
        c.activate()  // already activeIdle; guard returns early
        c.deactivate()
        c.deactivate()  // already inactive
        #expect(received == [.inactive])
    }
}
```

- [ ] **Step 2: Run tests, expect failure**

Run: `just test`
Expected: build failure — `onModeChanged` does not exist.

- [ ] **Step 3: Wire `didSet` on `mode` and expose `onModeChanged`**

In `Sources/Core/Control/AppController.swift`, replace the existing `mode` declaration with:

```swift
    public var onModeChanged: ((Mode) -> Void)?

    public private(set) var mode: Mode = .inactive {
        didSet {
            if oldValue != mode { onModeChanged?(mode) }
        }
    }
```

No other call sites change — every existing `mode = .x` assignment in `activate()`, `deactivate()`, `pointerDown()`, `pointerUp()`, and `clear()` now publishes via `didSet`.

- [ ] **Step 4: Run tests, expect pass**

Run: `just test`
Expected: 80 tests pass (74 prior + 6 new).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Control/AppController.swift Tests/CoreTests/AppControllerTests/OnModeChangedTests.swift
git commit -m "$(cat <<'EOF'
AppController: publish mode transitions via didSet

Adds an `onModeChanged: ((Mode) -> Void)?` hook so the menubar can
update its icon without polling. Implemented as a didSet observer on
the `mode` property — single emission point, fires on every real
transition, no per-method scattered notifications.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: MenubarController scaffold (status item + icon + state subscription)

**Files:**
- Create: `Sources/AppKit/MenubarController.swift`
- Create: `Tests/AppKitTests/MenubarControllerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/AppKitTests/MenubarControllerTests.swift`:

```swift
// ABOUTME: Tests for MenubarController — verifies icon swaps with mode and
// ABOUTME: that the controller installs/removes its NSStatusItem cleanly.

import AppKit
import Testing

@Suite("MenubarController")
@MainActor
struct MenubarControllerTests {
    private func make() -> (MenubarController, AppController, RecordingWindow, Editor) {
        let window = RecordingWindow()
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(editor: editor, window: window)
        let menubar = MenubarController(controller: controller, editor: editor)
        return (menubar, controller, window, editor)
    }

    @Test("initial icon is the outlined symbol")
    func initialIcon() {
        let (menubar, _, _, _) = make()
        #expect(menubar.currentSymbolName == "theatermask.and.paintbrush")
    }

    @Test("icon swaps to the filled symbol when controller becomes active")
    func activateSwapsIcon() {
        let (menubar, controller, _, _) = make()
        controller.activate()
        #expect(menubar.currentSymbolName == "theatermask.and.paintbrush.fill")
    }

    @Test("icon returns to outlined when controller becomes inactive")
    func deactivateRestoresIcon() {
        let (menubar, controller, _, _) = make()
        controller.activate()
        controller.deactivate()
        #expect(menubar.currentSymbolName == "theatermask.and.paintbrush")
    }

    @Test("activeDrawing stays on the filled icon")
    func drawingKeepsFilled() {
        let (menubar, controller, _, _) = make()
        controller.activate()
        controller.pointerDown(StrokePoint(x: 0, y: 0))
        #expect(menubar.currentSymbolName == "theatermask.and.paintbrush.fill")
    }
}
```

- [ ] **Step 2: Run integration tests, expect failure**

Run: `just test-integration`
Expected: build failure — `MenubarController` does not exist.

- [ ] **Step 3: Create the controller**

Create `Sources/AppKit/MenubarController.swift`:

```swift
// ABOUTME: Menu-bar status item for fiti. Two-state SF Symbol icon,
// ABOUTME: menu wired to AppController actions, NSMenuDelegate for enabled state.

import AppKit

@MainActor
public final class MenubarController {
    private let controller: AppController
    private let editor: Editor
    private let statusItem: NSStatusItem
    internal private(set) var currentSymbolName: String = ""

    public init(controller: AppController, editor: Editor) {
        self.controller = controller
        self.editor = editor
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon(for: controller.mode)
        controller.onModeChanged = { [weak self] mode in self?.updateIcon(for: mode) }
    }

    deinit {
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
}
```

- [ ] **Step 4: Run integration tests, expect pass**

Run: `just test-integration`
Expected: 105 tests pass (92 prior + 9 from tasks 1-2 in CoreTests + 4 new MenubarController tests in AppKitTests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/MenubarController.swift Tests/AppKitTests/MenubarControllerTests.swift
git commit -m "$(cat <<'EOF'
Add MenubarController scaffold with two-state icon

NSStatusItem with theatermask.and.paintbrush (outlined when
inactive) / .fill (active). Subscribes to AppController.onModeChanged
to swap the icon as activation toggles. No menu yet — that lands in
the next commit.

deinit removes the status item so tests don't leak it into the
system menu bar across runs.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Menu construction + actions + enabled state

**Files:**
- Modify: `Sources/AppKit/MenubarController.swift`
- Modify: `Tests/AppKitTests/MenubarControllerTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/AppKitTests/MenubarControllerTests.swift`:

```swift
    @Test("menu has the expected items in order")
    func menuStructure() {
        let (menubar, _, _, _) = make()
        let titles = menubar.menu.items.map(\.title)
        #expect(titles == ["Activate", "Deactivate", "",
                           "Clear", "Undo", "Redo", "",
                           "Quit fiti"])
    }

    @Test("Activate item key equivalent is Cmd+Opt+Z")
    func activateShortcut() throws {
        let (menubar, _, _, _) = make()
        let item = try #require(menubar.menu.items.first { $0.title == "Activate" })
        #expect(item.keyEquivalent == "z")
        #expect(item.keyEquivalentModifierMask == [.command, .option])
    }

    @Test("Undo item key equivalent is Cmd+Z; Redo is Cmd+Shift+Z")
    func undoRedoShortcuts() throws {
        let (menubar, _, _, _) = make()
        let undo = try #require(menubar.menu.items.first { $0.title == "Undo" })
        let redo = try #require(menubar.menu.items.first { $0.title == "Redo" })
        #expect(undo.keyEquivalent == "z" && undo.keyEquivalentModifierMask == [.command])
        #expect(redo.keyEquivalent == "z" && redo.keyEquivalentModifierMask == [.command, .shift])
    }

    @Test("menuNeedsUpdate enables Activate when inactive, disables Deactivate")
    func enabledStateInactive() {
        let (menubar, _, _, _) = make()
        menubar.menuNeedsUpdate(menubar.menu)
        let activate = menubar.menu.items.first { $0.title == "Activate" }!
        let deactivate = menubar.menu.items.first { $0.title == "Deactivate" }!
        #expect(activate.isEnabled == true)
        #expect(deactivate.isEnabled == false)
    }

    @Test("menuNeedsUpdate enables Deactivate when active")
    func enabledStateActive() {
        let (menubar, controller, _, _) = make()
        controller.activate()
        menubar.menuNeedsUpdate(menubar.menu)
        let activate = menubar.menu.items.first { $0.title == "Activate" }!
        let deactivate = menubar.menu.items.first { $0.title == "Deactivate" }!
        #expect(activate.isEnabled == false)
        #expect(deactivate.isEnabled == true)
    }

    @Test("menuNeedsUpdate ties Undo / Redo to Editor.canUndo / canRedo")
    func enabledStateUndoRedo() {
        let (menubar, _, _, editor) = make()
        menubar.menuNeedsUpdate(menubar.menu)
        let undo = menubar.menu.items.first { $0.title == "Undo" }!
        let redo = menubar.menu.items.first { $0.title == "Redo" }!
        #expect(undo.isEnabled == false)
        #expect(redo.isEnabled == false)

        _ = editor.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        editor.endStroke()
        menubar.menuNeedsUpdate(menubar.menu)
        #expect(undo.isEnabled == true)
        #expect(redo.isEnabled == false)

        _ = editor.undo()
        menubar.menuNeedsUpdate(menubar.menu)
        #expect(undo.isEnabled == false)
        #expect(redo.isEnabled == true)
    }

    /// Invoke the menu item's action through the ObjC runtime, the way
    /// AppKit would when the user clicks it. Avoids NSMenu.performActionForItem
    /// so we don't depend on autoenablesItems / validation behaviour.
    private func fire(_ title: String, in menubar: MenubarController) throws {
        let item = try #require(menubar.menu.items.first { $0.title == title })
        let target = try #require(item.target as? NSObject)
        let action = try #require(item.action)
        _ = target.perform(action, with: nil)
    }

    @Test("Activate menu action calls controller.activate()")
    func activateAction() throws {
        let (menubar, controller, _, _) = make()
        try fire("Activate", in: menubar)
        #expect(controller.mode == .activeIdle)
    }

    @Test("Clear menu action calls controller.clear()")
    func clearAction() throws {
        let (menubar, _, _, editor) = make()
        _ = editor.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        editor.endStroke()
        try fire("Clear", in: menubar)
        #expect(editor.doc.strokeOrder.isEmpty)
    }

    @Test("Undo menu action calls editor.undo()")
    func undoAction() throws {
        let (menubar, _, _, editor) = make()
        _ = editor.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        editor.endStroke()
        try fire("Undo", in: menubar)
        #expect(editor.doc.strokeOrder.isEmpty)
        #expect(editor.canRedo == true)
    }
```

- [ ] **Step 2: Run tests, expect failure**

Run: `just test-integration`
Expected: build failure — `menu`, `menuNeedsUpdate`, etc. do not exist on `MenubarController`.

- [ ] **Step 3: Add menu, delegate, and selectors**

Replace `Sources/AppKit/MenubarController.swift` with the expanded version:

```swift
// ABOUTME: Menu-bar status item for fiti. Two-state SF Symbol icon,
// ABOUTME: menu wired to AppController actions, NSMenuDelegate for enabled state.

import AppKit

@MainActor
public final class MenubarController: NSObject {
    private let controller: AppController
    private let editor: Editor
    private let statusItem: NSStatusItem
    internal let menu: NSMenu
    internal private(set) var currentSymbolName: String = ""

    private let activateItem: NSMenuItem
    private let deactivateItem: NSMenuItem
    private let undoItem: NSMenuItem
    private let redoItem: NSMenuItem

    public init(controller: AppController, editor: Editor) {
        self.controller = controller
        self.editor = editor
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.menu = NSMenu()

        self.activateItem   = NSMenuItem(title: "Activate",   action: #selector(activate),   keyEquivalent: "z")
        self.deactivateItem = NSMenuItem(title: "Deactivate", action: #selector(deactivate), keyEquivalent: "\u{1b}")
        let clearItem       = NSMenuItem(title: "Clear",      action: #selector(clearAll),   keyEquivalent: "k")
        self.undoItem       = NSMenuItem(title: "Undo",       action: #selector(undo),       keyEquivalent: "z")
        self.redoItem       = NSMenuItem(title: "Redo",       action: #selector(redo),       keyEquivalent: "z")
        let quitItem        = NSMenuItem(title: "Quit fiti",  action: #selector(quit),       keyEquivalent: "q")

        super.init()

        activateItem.keyEquivalentModifierMask   = [.command, .option]
        deactivateItem.keyEquivalentModifierMask = []
        clearItem.keyEquivalentModifierMask      = [.command]
        undoItem.keyEquivalentModifierMask       = [.command]
        redoItem.keyEquivalentModifierMask       = [.command, .shift]
        quitItem.keyEquivalentModifierMask       = [.command]

        for item in [activateItem, deactivateItem, undoItem, redoItem, clearItem, quitItem] {
            item.target = self
        }

        menu.addItem(activateItem)
        menu.addItem(deactivateItem)
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

    deinit {
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

    @objc private func activate()   { controller.activate() }
    @objc private func deactivate() { controller.deactivate() }
    @objc private func clearAll()   { controller.clear() }
    @objc private func undo()       { _ = editor.undo() }
    @objc private func redo()       { _ = editor.redo() }
    @objc private func quit()       { NSApplication.shared.terminate(nil) }
}

extension MenubarController: NSMenuDelegate {
    public func menuNeedsUpdate(_ menu: NSMenu) {
        let active = controller.mode != .inactive
        activateItem.isEnabled   = !active
        deactivateItem.isEnabled = active
        undoItem.isEnabled       = editor.canUndo
        redoItem.isEnabled       = editor.canRedo
    }
}
```

Note: `MenubarController` now inherits from `NSObject` so `@objc` selectors and `NSMenuDelegate` conformance work. The `menu` is `internal` so tests in `Tests/AppKitTests/` can read it (the `fiti-integration` target compiles both directories into one module).

- [ ] **Step 4: Run integration tests, expect pass**

Run: `just test-integration`
Expected: 114 tests pass (105 prior + 9 new in AppKitTests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/MenubarController.swift Tests/AppKitTests/MenubarControllerTests.swift
git commit -m "$(cat <<'EOF'
MenubarController: menu items, selectors, enabled state

Builds the eight menu items (Activate, Deactivate, Clear, Undo, Redo,
Quit + two separators) with proper keyEquivalents. Actions route to
AppController / Editor / NSApplication.terminate. NSMenuDelegate
recomputes enabled state in menuNeedsUpdate so we don't burn cycles
on every Editor frame.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Wire into main.swift

**Files:**
- Modify: `Sources/App/main.swift`

- [ ] **Step 1: Add the wiring line**

In `Sources/App/main.swift`, add a new stored property on `FitiAppDelegate`:

```swift
    var menubar: MenubarController!
```

And inside `applicationDidFinishLaunching`, after the line `controller = AppController(editor: editor, window: window)`:

```swift
        menubar = MenubarController(controller: controller, editor: editor)
```

The order matters: `MenubarController.init` reads `controller.mode` to set the initial icon, so it must come after `controller` is constructed. It can come before or after the input source wiring; choose immediately after the controller for grouping.

- [ ] **Step 2: Run the full check**

Run: `just check`
Expected: `just test` reports 80 tests, `just test-integration` reports 114 tests, lint clean, build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/App/main.swift
git commit -m "$(cat <<'EOF'
main: wire MenubarController into the app delegate

One line: instantiate MenubarController immediately after
AppController so the menubar reads the initial mode correctly.
FitiAppDelegate holds the reference so the status item survives.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Manual smoke test

No code changes — this is the acceptance gate before declaring the feature done.

- [ ] **Step 1: Launch fresh**

Run: `just stop && just run-bg`
Expected:
- An outlined theater-mask-and-paintbrush icon appears in the menu bar.

- [ ] **Step 2: Click the icon**

Expected: a menu drops down with these items, in order:

```
Activate         ⌘⌥Z
Deactivate       esc
─────
Clear            ⌘K
Undo             ⌘Z
Redo             ⇧⌘Z
─────
Quit fiti        ⌘Q
```

`Activate` is enabled, `Deactivate` is disabled, `Undo` and `Redo` are disabled.

- [ ] **Step 3: Activate via the menu**

Click `Activate`.
Expected: the icon swaps to the filled variant. Cursor capture turns on (the screen is no longer click-through).

- [ ] **Step 4: Draw a stroke**

Click and drag with the mouse. Release.
Expected: a stroke appears on screen. The icon stays filled during the drag.

- [ ] **Step 5: Open the menu again**

Click the icon.
Expected: `Activate` is now disabled, `Deactivate` is enabled, `Undo` is enabled, `Redo` is disabled.

- [ ] **Step 6: Use the menu items**

Click `Undo`. Expected: the stroke disappears. `Redo` becomes enabled.
Click `Redo`. Expected: the stroke comes back.
Click `Clear`. Expected: the stroke disappears (and is undoable via Undo).

- [ ] **Step 7: Deactivate via menu**

Click `Deactivate`.
Expected: icon returns to outlined. Click-through resumes.

- [ ] **Step 8: Test keyboard shortcuts while focused**

Press `Cmd+Opt+Z` (anywhere).
Expected: fiti activates. Draw a stroke. Then with fiti focused, press `Cmd+Z`.
Expected: stroke disappears. `Cmd+Shift+Z` brings it back.

- [ ] **Step 9: Quit via menu**

Click the menu icon → `Quit fiti`.
Expected: fiti quits, icon disappears from the menu bar, `pgrep -lf Fiti` returns nothing.

---

## Self-review checklist

After all tasks complete:

- [ ] No placeholders, no TODOs, no "TBD" in any committed file
- [ ] All shortcuts in the menu match the design doc exactly
- [ ] `just check` passes end-to-end (test + test-integration + lint + build)
- [ ] The smoke checklist above passes top to bottom
- [ ] `MenubarController.menu` accessed from tests is `internal` (not `public`) — keep the API surface tight
- [ ] No new files imported `Combine` or `SwiftUI` (we don't use them anywhere yet)
- [ ] `Sources/Core/` did not grow any AppKit dependencies (lint will catch this; verify with `just lint`)
- [ ] No regression: the seven POC acceptance criteria still hold (draw with hotkey, clear with Cmd+K, deactivate with Esc, HTTP inspect-state/inspect-undo work as before)

If anything fails or feels off, stop and surface it before declaring done.
