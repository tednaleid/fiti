# fiti Size / Opacity Visual Popover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `−size+` / `−opacity+` stepper rows in the toolbar with two SF-Symbol buttons that each open a horizontal popover of ten 60×140 preset cells rendered through the existing `SnapshotRenderer` pipeline.

**Architecture:** Pure Core gets a `PresetAxis` enum (presets + display string + selected-index match) and a `PopoverEdgePicker` (toolbar-position → side). AppKit gets a new `MarkPreview` view (extracted from `MarkControl`'s renderer), a `PresetButton` factory, and a `PresetPopover` borderless `NSPanel` with idempotent open/close and four dismissal paths. `MarkControl` shrinks to compose two `PresetButton`s + `MarkPreview`. `ToolbarController` owns one `PresetPopover` instance and handles toggle/swap on click.

**Tech Stack:** Swift 5.x, AppKit (`NSPanel`, `NSStackView`, `NSImageView`, `NSEvent` monitors), Swift Testing (`import Testing`, `@Test`, `#expect`, `@MainActor`). Build: `xcodegen` → `xcodebuild` via `just generate` / `just check`.

**Spec:** `docs/specs/2026-05-29-fiti-size-opacity-popover-design.md` (committed at `0dad936`). One deviation from the spec's signature: `PresetPopover.open(...)` takes a Core `PopoverEdge` enum instead of `NSRectEdge`, since `NSRectEdge` is an AppKit/CoreGraphics type and `Sources/Core/` cannot import either. The intent (which side of the anchor) is unchanged.

---

## File map

**Add (Core):**
- `Sources/Core/Model/PresetAxis.swift` — axis enum + display formatting + selected-index match.
- `Sources/Core/Model/PopoverEdge.swift` — `PopoverEdge` enum + `PopoverEdgePicker.pick(...)`.

**Add (AppKit):**
- `Sources/AppKit/MarkPreview.swift` — 60×140 live mark preview view. Static `render(...)` helper produces the same `NSImage` the popover cells use.
- `Sources/AppKit/PresetButton.swift` — `make(symbol:accessibility:tooltip:)` factory for 28×28 SF-Symbol buttons.
- `Sources/AppKit/PresetPopover.swift` — borderless `NSPanel` controller for the cells.

**Add (tests):**
- `Tests/CoreTests/PresetAxisTests.swift`
- `Tests/CoreTests/PopoverEdgePickerTests.swift`
- `Tests/AppKitTests/MarkPreviewTests.swift`
- `Tests/AppKitTests/PresetPopoverTests.swift`

**Modify:**
- `Sources/AppKit/MarkControl.swift` — drops stepper rows / labels / stepper actions; composes two `PresetButton`s + `MarkPreview`; exposes `onOpenPopover: ((PresetAxis, NSRect) -> Void)?`.
- `Sources/AppKit/ToolbarController.swift` — owns one `PresetPopover`; implements `markControl.onOpenPopover` with toggle / swap / tool-change-closes / active-highlight; deletes the `testOnly_tapSize*` / `testOnly_tapOpacity*` shims.
- `Tests/AppKitTests/MarkControlTests.swift` — rewritten.
- `Tests/AppKitTests/ToolbarControllerTests.swift` — stepper assertions removed; popover assertions added.

**Source globs auto-pick new files** (see `project.yml:43-78`). Run `just generate` whenever a source file is added before the next `just check`.

---

### Task 1: `PresetAxis` (pure Core enum)

**Files:**
- Create: `Sources/Core/Model/PresetAxis.swift`
- Test: `Tests/CoreTests/PresetAxisTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/CoreTests/PresetAxisTests.swift
// ABOUTME: Tests PresetAxis — the preset list, display formatting, and exact-match index.
// ABOUTME: Pure data + pure functions; no AppKit dependency.

import Testing

@Suite("PresetAxis")
struct PresetAxisTests {
    @Test("size axis exposes the ten ValuePresets.sizes values")
    func sizeValues() {
        #expect(PresetAxis.size.values == ValuePresets.sizes)
        #expect(PresetAxis.size.values.count == 10)
    }

    @Test("opacity axis exposes the ten ValuePresets.opacities values")
    func opacityValues() {
        #expect(PresetAxis.opacity.values == ValuePresets.opacities)
        #expect(PresetAxis.opacity.values.count == 10)
    }

    @Test("size displayString rounds to an integer (e.g. 14)")
    func sizeDisplayString() {
        #expect(PresetAxis.size.displayString(for: 14) == "14")
        #expect(PresetAxis.size.displayString(for: 6) == "6")
        #expect(PresetAxis.size.displayString(for: 100) == "100")
    }

    @Test("opacity displayString is a percent (e.g. 70%)")
    func opacityDisplayString() {
        #expect(PresetAxis.opacity.displayString(for: 0.7) == "70%")
        #expect(PresetAxis.opacity.displayString(for: 0.1) == "10%")
        #expect(PresetAxis.opacity.displayString(for: 1.0) == "100%")
    }

    @Test("selectedIndex returns the index for an exact preset match")
    func selectedIndexExact() {
        #expect(PresetAxis.size.selectedIndex(for: 2) == 0)
        #expect(PresetAxis.size.selectedIndex(for: 14) == 4)
        #expect(PresetAxis.size.selectedIndex(for: 100) == 9)
        #expect(PresetAxis.opacity.selectedIndex(for: 0.1) == 0)
        #expect(PresetAxis.opacity.selectedIndex(for: 0.7) == 6)
        #expect(PresetAxis.opacity.selectedIndex(for: 1.0) == 9)
    }

    @Test("selectedIndex returns nil for off-preset values")
    func selectedIndexOffPreset() {
        #expect(PresetAxis.size.selectedIndex(for: 7) == nil)
        #expect(PresetAxis.size.selectedIndex(for: 50) == nil)
        #expect(PresetAxis.opacity.selectedIndex(for: 0.75) == nil)
        #expect(PresetAxis.opacity.selectedIndex(for: 0.05) == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test-only PresetAxisTests`
Expected: FAIL — `PresetAxis` undefined.

- [ ] **Step 3: Implement `PresetAxis`**

```swift
// Sources/Core/Model/PresetAxis.swift
// ABOUTME: Pure picker-axis enum used by the size/opacity popover. Holds the preset
// ABOUTME: list, the display formatter (integer / percent), and exact-match indexing.

import Foundation

public enum PresetAxis: Equatable, Sendable {
    case size
    case opacity

    public var values: [Double] {
        switch self {
        case .size: return ValuePresets.sizes
        case .opacity: return ValuePresets.opacities
        }
    }

    public func displayString(for value: Double) -> String {
        switch self {
        case .size:
            return "\(Int(value.rounded()))"
        case .opacity:
            return "\(Int((value * 100).rounded()))%"
        }
    }

    public func selectedIndex(for value: Double) -> Int? {
        values.firstIndex { abs($0 - value) < 1e-6 }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `just generate && just test-only PresetAxisTests`
Expected: PASS for all six tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Model/PresetAxis.swift Tests/CoreTests/PresetAxisTests.swift
git commit -m "$(cat <<'EOF'
Core: PresetAxis enum for size/opacity picker presets

Pure axis abstraction the AppKit popover consumes: values list (via
ValuePresets), display string ("14" / "70%"), and selectedIndex for
exact-preset matching. No switch-axis blocks needed at the call site.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `PopoverEdge` + `PopoverEdgePicker` (pure Core)

**Files:**
- Create: `Sources/Core/Model/PopoverEdge.swift`
- Test: `Tests/CoreTests/PopoverEdgePickerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/CoreTests/PopoverEdgePickerTests.swift
// ABOUTME: Tests PopoverEdgePicker — chooses .maxX or .minX from toolbar/screen midpoints.
// ABOUTME: Pure helper so we can verify edge-mirroring without a real window.

import Testing

@Suite("PopoverEdgePicker")
struct PopoverEdgePickerTests {
    @Test("toolbar in the left half returns .maxX (popover extends right)")
    func leftHalfReturnsMaxX() {
        // Screen midX 720, toolbar midX 100 (left side).
        #expect(PopoverEdgePicker.pick(toolbarMidX: 100, screenMidX: 720) == .maxX)
    }

    @Test("toolbar in the right half returns .minX (popover extends left)")
    func rightHalfReturnsMinX() {
        // Screen midX 720, toolbar midX 1400 (right side).
        #expect(PopoverEdgePicker.pick(toolbarMidX: 1400, screenMidX: 720) == .minX)
    }

    @Test("toolbar exactly at screen midpoint returns .minX (boundary picks right-edge layout)")
    func boundaryReturnsMinX() {
        #expect(PopoverEdgePicker.pick(toolbarMidX: 720, screenMidX: 720) == .minX)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test-only PopoverEdgePickerTests`
Expected: FAIL — `PopoverEdgePicker` undefined.

- [ ] **Step 3: Implement**

```swift
// Sources/Core/Model/PopoverEdge.swift
// ABOUTME: Pure popover-edge enum and picker. Determines whether the size/opacity
// ABOUTME: popover extends right (.maxX) or left (.minX) of its anchor.

import Foundation

public enum PopoverEdge: Equatable, Sendable {
    /// Popover extends to the right of the anchor.
    case maxX
    /// Popover extends to the left of the anchor.
    case minX
}

public enum PopoverEdgePicker {
    /// Returns `.maxX` when the toolbar's horizontal center is strictly left of
    /// the screen's midpoint (popover extends right); `.minX` otherwise.
    public static func pick(toolbarMidX: Double, screenMidX: Double) -> PopoverEdge {
        toolbarMidX < screenMidX ? .maxX : .minX
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `just generate && just test-only PopoverEdgePickerTests`
Expected: PASS for all three tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Model/PopoverEdge.swift Tests/CoreTests/PopoverEdgePickerTests.swift
git commit -m "$(cat <<'EOF'
Core: PopoverEdge + PopoverEdgePicker for popover side selection

Pure helper that picks .maxX (popover extends right) or .minX (left)
from toolbar/screen horizontal midpoints. Lets the size/opacity popover
mirror sides based on the toolbar's screen position without needing a
real window in tests.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `MarkPreview` — extract the rendering view

**Files:**
- Create: `Sources/AppKit/MarkPreview.swift`
- Test: `Tests/AppKitTests/MarkPreviewTests.swift`

Note: This task creates `MarkPreview` as a standalone view with a static `render(...)` helper. `MarkControl` continues to render via its own internal code until Task 11 refactors it. The static helper exists from this task onward so the popover cells (Tasks 5–10) can reuse it.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AppKitTests/MarkPreviewTests.swift
// ABOUTME: Tests MarkPreview — 60x140 mark snapshot view, used by the toolbar and
// ABOUTME: re-used (via static render) by each PresetPopover cell.

import AppKit
import Testing

@Suite("MarkPreview")
@MainActor
struct MarkPreviewTests {
    @Test("renders a snapshot image for each drawing tool with outline on and off")
    func rendersForEachTool() {
        let mp = MarkPreview()
        mp.color = RGBA(r: 1, g: 0, b: 0, a: 1)
        mp.width = 30
        for tool in [Tool.pen, .arrow, .text] {
            for on in [false, true] {
                mp.currentTool = tool
                mp.outlineOn = on
                #expect(mp.testOnly_hasPreviewImage)
            }
        }
    }

    @Test("setting currentTool = .selection keeps the previously-set previewTool")
    func selectionKeepsPriorTool() {
        let mp = MarkPreview()
        mp.currentTool = .text
        #expect(mp.testOnly_previewTool == .text)
        mp.currentTool = .selection
        #expect(mp.testOnly_previewTool == .text)
        mp.currentTool = .arrow
        #expect(mp.testOnly_previewTool == .arrow)
    }

    @Test("static render returns a non-nil image for the standard preview inputs")
    func staticRenderProducesImage() {
        let img = MarkPreview.render(tool: .pen,
                                     color: RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1),
                                     width: 14,
                                     outlineOn: false)
        #expect(img != nil)
    }

    @Test("canvasSize is 60x140 logical points")
    func canvasSize() {
        #expect(MarkPreview.canvasSize.width == 60)
        #expect(MarkPreview.canvasSize.height == 140)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just generate && just test-only MarkPreviewTests`
Expected: FAIL — `MarkPreview` undefined.

- [ ] **Step 3: Implement `MarkPreview`**

```swift
// Sources/AppKit/MarkPreview.swift
// ABOUTME: 60x140 live mark preview rendered through SnapshotRenderer — the same image
// ABOUTME: shown in the toolbar and inside each PresetPopover cell. No interaction.

import AppKit

@MainActor
final class MarkPreview: NSView {
    static let canvasSize = Size(width: 60, height: 140)
    private static let markLength: Double = 66

    var color: RGBA = RGBA(r: 0, g: 0, b: 0, a: 1) { didSet { refresh() } }
    var width: Double = 6 { didSet { refresh() } }
    var outlineOn: Bool = false { didSet { refresh() } }
    /// The active tool. `.selection` is a meta tool; the preview keeps the
    /// drawing tool that was set before it.
    var currentTool: Tool = .pen {
        didSet { if currentTool != .selection { previewTool = currentTool; refresh() } }
    }
    private(set) var previewTool: Tool = .pen
    private let imageView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func build() {
        imageView.imageScaling = .scaleNone   // the renderer already produces real-sized pixels
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            widthAnchor.constraint(equalToConstant: CGFloat(Self.canvasSize.width)),
            heightAnchor.constraint(equalToConstant: CGFloat(Self.canvasSize.height))
        ])
    }

    private func refresh() {
        imageView.image = Self.render(tool: previewTool, color: color, width: width,
                                      outlineOn: outlineOn)
    }

    /// Build a `SnapshotRenderer` image for the given parameters at the standard preview
    /// canvas size. Internal so `PresetPopover` cells reuse the exact same pipeline.
    static func render(tool: Tool, color: RGBA, width: Double, outlineOn: Bool) -> NSImage? {
        let flags = OutlineFlags(text: tool == .text && outlineOn,
                                 arrow: tool == .arrow && outlineOn,
                                 pen: tool == .pen && outlineOn)
        let frame = RenderFrame(items: [previewItem(tool: tool, color: color, width: width)],
                                inProgress: nil, canvasSize: canvasSize)
        return SnapshotRenderer.image(from: frame, scale: 2, outline: flags)
    }

    private static func previewItem(tool: Tool, color: RGBA, width: Double) -> CanvasItem {
        let w = canvasSize.width, h = canvasSize.height
        let cx = w / 2, midY = h / 2, half = markLength / 2
        switch tool {
        case .arrow:
            return .arrow(ArrowItem(id: "preview", color: color, width: width, transform: .identity,
                                    tail: Point(x: cx, y: midY + half),
                                    head: Point(x: cx, y: midY - half),
                                    createdAt: 0))
        case .text:
            let fs = width * 4
            let font = NSFont(name: "Helvetica", size: CGFloat(fs)) ?? .systemFont(ofSize: CGFloat(fs))
            let glyph = ("A" as NSString).size(withAttributes: [.font: font])
            return .text(TextItem(id: "preview", string: "A", fontName: "Helvetica", fontSize: fs,
                                  color: color,
                                  transform: Transform(x: (w - Double(glyph.width)) / 2,
                                                       y: (h - Double(glyph.height)) / 2,
                                                       scale: 1, rotate: 0),
                                  bounds: Size(width: Double(glyph.width), height: Double(glyph.height)),
                                  createdAt: 0))
        case .pen, .selection:
            let pts = [(cx, midY - half), (cx - 6, midY - half * 0.25),
                       (cx + 5, midY + half * 0.35), (cx - 2, midY + half)]
                .map { StrokePoint(x: $0.0, y: $0.1) }
            return .stroke(Stroke(id: "preview", color: color, width: width, transform: .identity,
                                  points: pts, pointerType: .mouse, pressureEnabled: false,
                                  createdAt: 0))
        }
    }

    // MARK: Test hooks

    // swiftlint:disable identifier_name
    var testOnly_hasPreviewImage: Bool { imageView.image != nil }
    // swiftlint:enable identifier_name
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `just generate && just test-only MarkPreviewTests`
Expected: PASS for all four tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/MarkPreview.swift Tests/AppKitTests/MarkPreviewTests.swift
git commit -m "$(cat <<'EOF'
AppKit: MarkPreview view extracted from MarkControl renderer

Lifts the 60x140 mark-snapshot view into its own file so the upcoming
PresetPopover can reuse the same SnapshotRenderer call shape per cell.
Exposes a static render(tool:color:width:outlineOn:) helper that
returns the same NSImage the in-toolbar preview uses. MarkControl
continues to render via its own internal path until the refactor in
this series lands.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `PresetButton` factory

**Files:**
- Create: `Sources/AppKit/PresetButton.swift`

`PresetButton` is a tiny factory with no behavior beyond constructing a configured `FirstMouseButton`. It is exercised by the `MarkControl` tests in Task 11 (no separate test target needed in this task — the implementation is the test of its own correctness).

- [ ] **Step 1: Add file**

```swift
// Sources/AppKit/PresetButton.swift
// ABOUTME: 28x28 SF-Symbol button used as the size/opacity popover trigger in the toolbar.
// ABOUTME: Sibling to color and tool buttons; the same FirstMouseButton + regularSquare bezel.

import AppKit

enum PresetButton {
    /// Builds a 28x28 first-mouse SF-Symbol button. Caller wires `target` and `action`.
    static func make(symbol: String, accessibility: String, tooltip: String) -> NSButton {
        let button = FirstMouseButton(title: "", target: nil, action: nil)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibility)
        button.imagePosition = .imageOnly
        button.bezelStyle = .regularSquare
        button.toolTip = tooltip
        return button
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `just generate && just build`
Expected: clean Debug build, no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/AppKit/PresetButton.swift
git commit -m "$(cat <<'EOF'
AppKit: PresetButton factory for size/opacity popover triggers

Small NSButton factory: 28x28, SF-Symbol image, regularSquare bezel,
first-mouse so it fires on the non-activating toolbar panel. Two
instances will live in MarkControl (lineweight for size, drop for
opacity) replacing the +/- stepper rows.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: `PresetPopover` skeleton (open / isOpen / close idempotent)

**Files:**
- Create: `Sources/AppKit/PresetPopover.swift`
- Test: `Tests/AppKitTests/PresetPopoverTests.swift`

The skeleton creates the borderless panel, exposes `isOpen` and `currentAxis`, has a stub `open(...)` that just records the axis, and `close()` that orders out and clears state. Cells, dismissal monitors, and the pick closure all arrive in later tasks.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AppKitTests/PresetPopoverTests.swift
// ABOUTME: Tests PresetPopover — borderless panel that shows preset cells for the size
// ABOUTME: or opacity axis. Covers lifecycle, cell building, selection, and dismissal.

import AppKit
import Testing

@Suite("PresetPopover")
@MainActor
struct PresetPopoverTests {
    private func anchor() -> NSRect {
        // A point in screen space that is on a real screen — using NSScreen.main's frame
        // origin avoids screen-edge clamping concerns. Size matches MarkPreview.
        let origin = NSScreen.main?.frame.origin ?? .zero
        return NSRect(x: origin.x + 100, y: origin.y + 100, width: 60, height: 140)
    }

    @Test("isOpen is false before open")
    func notOpenInitially() {
        let pop = PresetPopover()
        #expect(pop.isOpen == false)
        #expect(pop.currentAxis == nil)
    }

    @Test("open(size, ...) sets isOpen and currentAxis = .size")
    func openSetsAxis() {
        let pop = PresetPopover()
        pop.open(axis: .size, currentValue: 6,
                 color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 6, tool: .pen, outlineOn: false,
                 anchor: anchor(), edge: .maxX, onPick: { _ in })
        #expect(pop.isOpen == true)
        #expect(pop.currentAxis == .size)
        pop.close()
    }

    @Test("close clears isOpen and currentAxis")
    func closeClears() {
        let pop = PresetPopover()
        pop.open(axis: .opacity, currentValue: 0.7,
                 color: RGBA(r: 0, g: 1, b: 0, a: 0.7), width: 14, tool: .pen, outlineOn: true,
                 anchor: anchor(), edge: .maxX, onPick: { _ in })
        pop.close()
        #expect(pop.isOpen == false)
        #expect(pop.currentAxis == nil)
    }

    @Test("close is idempotent — calling twice does not crash")
    func closeIdempotent() {
        let pop = PresetPopover()
        pop.close()
        pop.close()
        #expect(pop.isOpen == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just generate && just test-only PresetPopoverTests`
Expected: FAIL — `PresetPopover` undefined.

- [ ] **Step 3: Implement the skeleton**

```swift
// Sources/AppKit/PresetPopover.swift
// ABOUTME: Borderless panel showing 10 preset cells for the size or opacity axis.
// ABOUTME: Owns its dismissal monitors and lifecycle; idempotent open / close.

import AppKit

@MainActor
final class PresetPopover {
    private let panel: NSPanel

    private(set) var currentAxis: PresetAxis?
    var isOpen: Bool { currentAxis != nil }

    init() {
        let rect = NSRect(x: 0, y: 0, width: 100, height: 140)
        panel = NSPanel(contentRect: rect,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = true
        // Above the toolbar (.floating + 1) so the popover sits on top of it.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.hidesOnDeactivate = false

        let container = NSView(frame: rect)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.16, alpha: 0.96).cgColor
        container.layer?.cornerRadius = 8
        panel.contentView = container
    }

    /// Show the popover for `axis`, anchored to `anchor` (screen coords) on the chosen `edge`.
    /// `onPick(value)` fires when the user clicks a cell; the popover then closes.
    func open(axis: PresetAxis,
              currentValue: Double,
              color: RGBA,
              width: Double,
              tool: Tool,
              outlineOn: Bool,
              anchor: NSRect,
              edge: PopoverEdge,
              onPick: @escaping (Double) -> Void) {
        guard !isOpen else { return }
        currentAxis = axis
        // Position the panel flush with the anchor's top/bottom; horizontal placement
        // depends on the edge. Concrete cell building lands in Task 6.
        let panelWidth = panel.frame.width
        let gap: CGFloat = 6
        let originY = anchor.minY
        let originX: CGFloat
        switch edge {
        case .maxX: originX = anchor.maxX + gap
        case .minX: originX = anchor.minX - gap - panelWidth
        }
        panel.setFrame(NSRect(x: originX, y: originY, width: panelWidth, height: anchor.height),
                       display: true)
        panel.orderFront(nil)
    }

    func close() {
        guard isOpen else { return }
        currentAxis = nil
        panel.orderOut(nil)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `just generate && just test-only PresetPopoverTests`
Expected: PASS for all four tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/PresetPopover.swift Tests/AppKitTests/PresetPopoverTests.swift
git commit -m "$(cat <<'EOF'
AppKit: PresetPopover skeleton — borderless panel + open/close lifecycle

Idempotent open and close, currentAxis tracking, edge-aware
positioning flush with the anchor's top/bottom. No cells, no
dismissal monitors yet — those land in follow-up commits.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: `PresetPopover` builds 10 cells + highlights selected

**Files:**
- Modify: `Sources/AppKit/PresetPopover.swift`
- Modify: `Tests/AppKitTests/PresetPopoverTests.swift`

- [ ] **Step 1: Add the failing tests**

Append to `Tests/AppKitTests/PresetPopoverTests.swift` before the closing brace of `PresetPopoverTests`:

```swift
    @Test("open builds 10 cells for the size axis")
    func tenCellsForSize() {
        let pop = PresetPopover()
        pop.open(axis: .size, currentValue: 14,
                 color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 14, tool: .pen, outlineOn: false,
                 anchor: anchor(), edge: .maxX, onPick: { _ in })
        #expect(pop.testOnly_cellCount == 10)
        pop.close()
    }

    @Test("open builds 10 cells for the opacity axis")
    func tenCellsForOpacity() {
        let pop = PresetPopover()
        pop.open(axis: .opacity, currentValue: 0.7,
                 color: RGBA(r: 0, g: 0, b: 1, a: 0.7), width: 14, tool: .pen, outlineOn: false,
                 anchor: anchor(), edge: .maxX, onPick: { _ in })
        #expect(pop.testOnly_cellCount == 10)
        pop.close()
    }

    @Test("the cell at the matching preset index has the active background")
    func matchingCellHighlighted() {
        let pop = PresetPopover()
        // Size 14 → preset index 4 (ValuePresets.sizes is [2,4,6,9,14,...]).
        pop.open(axis: .size, currentValue: 14,
                 color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 14, tool: .pen, outlineOn: false,
                 anchor: anchor(), edge: .maxX, onPick: { _ in })
        #expect(pop.testOnly_selectedCellIndex == 4)
        pop.close()
    }

    @Test("off-preset currentValue leaves no cell highlighted")
    func offPresetNoHighlight() {
        let pop = PresetPopover()
        pop.open(axis: .size, currentValue: 7,  // not in ValuePresets.sizes
                 color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 7, tool: .pen, outlineOn: false,
                 anchor: anchor(), edge: .maxX, onPick: { _ in })
        #expect(pop.testOnly_selectedCellIndex == nil)
        pop.close()
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test-only PresetPopoverTests`
Expected: FAIL — `testOnly_cellCount` / `testOnly_selectedCellIndex` undefined.

- [ ] **Step 3: Add cell construction and the testOnly accessors**

Edit `Sources/AppKit/PresetPopover.swift`. Add stored state and replace `open(...)` plus the closing `}` at the end of the type to include the new cell-building code and test hooks.

Replace the entire file with:

```swift
// Sources/AppKit/PresetPopover.swift
// ABOUTME: Borderless panel showing 10 preset cells for the size or opacity axis.
// ABOUTME: Owns its dismissal monitors and lifecycle; idempotent open / close.

import AppKit

@MainActor
final class PresetPopover {
    private let panel: NSPanel
    private let stack: NSStackView
    private var cells: [NSButton] = []
    private var onPick: ((Double) -> Void)?

    private(set) var currentAxis: PresetAxis?
    var isOpen: Bool { currentAxis != nil }

    private let cellSpacing: CGFloat = 6
    private let edgePadding: CGFloat = 6

    init() {
        let rect = NSRect(x: 0, y: 0, width: 100, height: 140)
        panel = NSPanel(contentRect: rect,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.hidesOnDeactivate = false

        stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = cellSpacing
        stack.edgeInsets = NSEdgeInsets(top: edgePadding, left: edgePadding,
                                        bottom: edgePadding, right: edgePadding)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: rect)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.16, alpha: 0.96).cgColor
        container.layer?.cornerRadius = 8
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        panel.contentView = container
    }

    func open(axis: PresetAxis,
              currentValue: Double,
              color: RGBA,
              width: Double,
              tool: Tool,
              outlineOn: Bool,
              anchor: NSRect,
              edge: PopoverEdge,
              onPick: @escaping (Double) -> Void) {
        guard !isOpen else { return }
        currentAxis = axis
        self.onPick = onPick

        buildCells(axis: axis, currentValue: currentValue,
                   color: color, width: width, tool: tool, outlineOn: outlineOn)
        positionPanel(anchor: anchor, edge: edge)
        panel.orderFront(nil)
    }

    func close() {
        guard isOpen else { return }
        currentAxis = nil
        onPick = nil
        for cell in cells { cell.removeFromSuperview() }
        cells.removeAll()
        panel.orderOut(nil)
    }

    private func buildCells(axis: PresetAxis, currentValue: Double, color: RGBA, width: Double,
                            tool: Tool, outlineOn: Bool) {
        let selected = axis.selectedIndex(for: currentValue)
        let resolvedTool: Tool = (tool == .selection) ? .pen : tool
        for (index, preset) in axis.values.enumerated() {
            let cell = makeCell(index: index, axis: axis, preset: preset,
                                color: color, width: width, tool: resolvedTool, outlineOn: outlineOn)
            setActiveBackground(cell, active: index == selected)
            stack.addArrangedSubview(cell)
            cells.append(cell)
        }
    }

    private func makeCell(index: Int, axis: PresetAxis, preset: Double,
                          color: RGBA, width: Double, tool: Tool, outlineOn: Bool) -> NSButton {
        let cell = FirstMouseButton(title: "", target: nil, action: nil)
        cell.tag = index
        cell.bezelStyle = .regularSquare
        cell.isBordered = false
        cell.imagePosition = .imageOnly
        cell.wantsLayer = true
        cell.layer?.cornerRadius = 4

        let image: NSImage?
        switch axis {
        case .size:
            image = MarkPreview.render(tool: tool, color: color, width: preset, outlineOn: outlineOn)
        case .opacity:
            let withAlpha = RGBA(r: color.r, g: color.g, b: color.b, a: preset)
            image = MarkPreview.render(tool: tool, color: withAlpha, width: width, outlineOn: outlineOn)
        }
        cell.image = image

        cell.widthAnchor.constraint(equalToConstant: CGFloat(MarkPreview.canvasSize.width)).isActive = true
        cell.heightAnchor.constraint(equalToConstant: CGFloat(MarkPreview.canvasSize.height)).isActive = true
        return cell
    }

    private func setActiveBackground(_ button: NSButton, active: Bool) {
        button.layer?.backgroundColor = active
            ? NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
            : NSColor.clear.cgColor
    }

    private func positionPanel(anchor: NSRect, edge: PopoverEdge) {
        // Width: 10 cells + 9 inter-cell gaps + 2 edge paddings.
        let cellW = CGFloat(MarkPreview.canvasSize.width)
        let cellCount: CGFloat = 10
        let panelWidth = cellW * cellCount + cellSpacing * (cellCount - 1) + edgePadding * 2
        let originY = anchor.minY
        let originX: CGFloat
        switch edge {
        case .maxX: originX = anchor.maxX + cellSpacing
        case .minX: originX = anchor.minX - cellSpacing - panelWidth
        }
        panel.setFrame(NSRect(x: originX, y: originY, width: panelWidth, height: anchor.height),
                       display: true)
    }

    // MARK: Test hooks

    // swiftlint:disable identifier_name
    var testOnly_cellCount: Int { cells.count }
    var testOnly_selectedCellIndex: Int? {
        cells.firstIndex { ($0.layer?.backgroundColor?.alpha ?? 0) > 0 }
    }
    // swiftlint:enable identifier_name
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `just test-only PresetPopoverTests`
Expected: PASS for all eight tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/PresetPopover.swift Tests/AppKitTests/PresetPopoverTests.swift
git commit -m "$(cat <<'EOF'
AppKit: PresetPopover builds 10 cells per axis with selected-index highlight

Each cell is a FirstMouseButton with a MarkPreview.render image —
identical pipeline to the in-toolbar preview, with the preset
substituted on the axis (size cell varies width; opacity cell varies
alpha). The cell at axis.selectedIndex(currentValue) gets the accent
background; off-preset values leave nothing highlighted.

Selection tool falls back to .pen for cell rendering so cells still
show a recognisable mark.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Cell click → `onPick` + close

**Files:**
- Modify: `Sources/AppKit/PresetPopover.swift`
- Modify: `Tests/AppKitTests/PresetPopoverTests.swift`

- [ ] **Step 1: Add the failing tests**

Append to `Tests/AppKitTests/PresetPopoverTests.swift` before the closing brace of `PresetPopoverTests`:

```swift
    @Test("clicking cell N fires onPick with axis.values[N] and closes the popover")
    func cellClickPicksAndCloses() {
        let pop = PresetPopover()
        var picked: [Double] = []
        pop.open(axis: .size, currentValue: 14,
                 color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 14, tool: .pen, outlineOn: false,
                 anchor: anchor(), edge: .maxX, onPick: { picked.append($0) })
        pop.testOnly_clickCell(at: 6)  // ValuePresets.sizes[6] == 30
        #expect(picked == [30])
        #expect(pop.isOpen == false)
    }

    @Test("clicking an opacity cell fires onPick with the matching opacity preset")
    func opacityCellClick() {
        let pop = PresetPopover()
        var picked: [Double] = []
        pop.open(axis: .opacity, currentValue: 0.5,
                 color: RGBA(r: 1, g: 0, b: 0, a: 0.5), width: 14, tool: .pen, outlineOn: false,
                 anchor: anchor(), edge: .maxX, onPick: { picked.append($0) })
        pop.testOnly_clickCell(at: 9)  // 1.0
        #expect(picked.count == 1)
        #expect(abs(picked[0] - 1.0) < 1e-6)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test-only PresetPopoverTests`
Expected: FAIL — `testOnly_clickCell(at:)` undefined.

- [ ] **Step 3: Wire cells to a click action and add the test hook**

Edit `Sources/AppKit/PresetPopover.swift`. In `makeCell(...)`, after the line setting `cell.tag = index`, set the cell's target/action:

```swift
        cell.target = self
        cell.action = #selector(cellClicked(_:))
```

Add an `@objc` action method inside the class (above `setActiveBackground`):

```swift
    @objc private func cellClicked(_ sender: NSButton) {
        guard let axis = currentAxis else { return }
        let value = axis.values[sender.tag]
        let pick = onPick
        close()
        pick?(value)
    }
```

Add the test hook (just before the closing `}` of the type, inside the swiftlint-disabled block):

```swift
    func testOnly_clickCell(at index: Int) {
        cellClicked(cells[index])
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `just test-only PresetPopoverTests`
Expected: PASS for all ten tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/PresetPopover.swift Tests/AppKitTests/PresetPopoverTests.swift
git commit -m "$(cat <<'EOF'
AppKit: PresetPopover commits the picked preset and closes on cell click

Each cell's NSButton action fires onPick(axis.values[index]) and
closes the popover. The close runs before the pick callback fires so
the popover is already gone by the time the caller mutates state and
the live preview refreshes.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: ESC dismissal via local `keyDown` monitor

**Files:**
- Modify: `Sources/AppKit/PresetPopover.swift`
- Modify: `Tests/AppKitTests/PresetPopoverTests.swift`

- [ ] **Step 1: Add the failing tests**

Append to `Tests/AppKitTests/PresetPopoverTests.swift` before the closing brace of `PresetPopoverTests`:

```swift
    @Test("delivering an ESC keyDown to the local monitor closes the popover")
    func escClosesPopover() {
        let pop = PresetPopover()
        pop.open(axis: .size, currentValue: 14,
                 color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 14, tool: .pen, outlineOn: false,
                 anchor: anchor(), edge: .maxX, onPick: { _ in })
        let escEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                        timestamp: 0, windowNumber: 0, context: nil,
                                        characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
                                        isARepeat: false, keyCode: 0x35)!
        let consumed = pop.testOnly_handleKey(escEvent)
        #expect(consumed)
        #expect(pop.isOpen == false)
    }

    @Test("a non-ESC keyDown is not swallowed and does not close the popover")
    func nonEscIgnored() {
        let pop = PresetPopover()
        pop.open(axis: .size, currentValue: 14,
                 color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 14, tool: .pen, outlineOn: false,
                 anchor: anchor(), edge: .maxX, onPick: { _ in })
        let aEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                      timestamp: 0, windowNumber: 0, context: nil,
                                      characters: "a", charactersIgnoringModifiers: "a",
                                      isARepeat: false, keyCode: 0x00)!
        let consumed = pop.testOnly_handleKey(aEvent)
        #expect(consumed == false)
        #expect(pop.isOpen == true)
        pop.close()
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test-only PresetPopoverTests`
Expected: FAIL — `testOnly_handleKey` undefined.

- [ ] **Step 3: Install the local key monitor and the test hook**

Edit `Sources/AppKit/PresetPopover.swift`. Add a stored property near the top of the type:

```swift
    private var localKeyMonitor: Any?
    private let escKeyCode: UInt16 = 0x35
```

In `open(...)`, after `panel.orderFront(nil)`, install the monitor:

```swift
        installLocalKeyMonitor()
```

In `close()`, after `panel.orderOut(nil)`, remove the monitor:

```swift
        removeLocalKeyMonitor()
```

Add two private methods and the test hook:

```swift
    private func installLocalKeyMonitor() {
        if localKeyMonitor != nil { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleLocalKey(event) ? nil : event
        }
    }

    private func removeLocalKeyMonitor() {
        if let token = localKeyMonitor {
            NSEvent.removeMonitor(token)
            localKeyMonitor = nil
        }
    }

    /// Returns true if the event was consumed (ESC, popover closes); false otherwise.
    private func handleLocalKey(_ event: NSEvent) -> Bool {
        guard isOpen, event.keyCode == escKeyCode else { return false }
        close()
        return true
    }
```

Add the test hook in the swiftlint-disabled block:

```swift
    func testOnly_handleKey(_ event: NSEvent) -> Bool { handleLocalKey(event) }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `just test-only PresetPopoverTests`
Expected: PASS for all twelve tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/PresetPopover.swift Tests/AppKitTests/PresetPopoverTests.swift
git commit -m "$(cat <<'EOF'
AppKit: PresetPopover closes on ESC via local keyDown monitor

addLocalMonitorForEvents(.keyDown) so ESC closes the popover and is
swallowed (returning nil from the handler). Other keys pass through.
Monitor is installed in open() and torn down in close() — a single
removeLocalKeyMonitor path means no leak across open/close cycles.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: `didResignActive` closes the popover

**Files:**
- Modify: `Sources/AppKit/PresetPopover.swift`
- Modify: `Tests/AppKitTests/PresetPopoverTests.swift`

- [ ] **Step 1: Add the failing test**

Append to `Tests/AppKitTests/PresetPopoverTests.swift` before the closing brace of `PresetPopoverTests`:

```swift
    @Test("NSApplication.didResignActiveNotification closes the popover")
    func resignActiveClosesPopover() {
        let pop = PresetPopover()
        pop.open(axis: .opacity, currentValue: 0.7,
                 color: RGBA(r: 0, g: 0, b: 1, a: 0.7), width: 14, tool: .pen, outlineOn: false,
                 anchor: anchor(), edge: .maxX, onPick: { _ in })
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification,
                                        object: NSApp)
        #expect(pop.isOpen == false)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test-only PresetPopoverTests`
Expected: FAIL — popover still open after the notification.

- [ ] **Step 3: Add the deactivation observer**

Edit `Sources/AppKit/PresetPopover.swift`. Add a stored property next to `localKeyMonitor`:

```swift
    private var deactivationObserver: NSObjectProtocol?
```

In `open(...)`, after `installLocalKeyMonitor()`, install the observer:

```swift
        installDeactivationObserver()
```

In `close()`, after `removeLocalKeyMonitor()`, remove it:

```swift
        removeDeactivationObserver()
```

Add the two helper methods:

```swift
    private func installDeactivationObserver() {
        if deactivationObserver != nil { return }
        deactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    private func removeDeactivationObserver() {
        if let observer = deactivationObserver {
            NotificationCenter.default.removeObserver(observer)
            deactivationObserver = nil
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `just test-only PresetPopoverTests`
Expected: PASS for all thirteen tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/PresetPopover.swift Tests/AppKitTests/PresetPopoverTests.swift
git commit -m "$(cat <<'EOF'
AppKit: PresetPopover closes when NSApplication resigns active

Adds a didResignActiveNotification observer paired with the local key
monitor. Same install-in-open / remove-in-close pattern so the observer
never outlives the open lifecycle.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: Global mouse monitor + monitor-leak invariant

**Files:**
- Modify: `Sources/AppKit/PresetPopover.swift`
- Modify: `Tests/AppKitTests/PresetPopoverTests.swift`

The global mouse monitor catches clicks outside the app (the local monitor would already cover same-app clicks, but for the floating popover the relevant case is anywhere outside its own panel). We can't realistically inject a global event in tests, so we verify it is *installed* and *removed* via a counter on the wiring.

- [ ] **Step 1: Add the failing tests**

Append to `Tests/AppKitTests/PresetPopoverTests.swift` before the closing brace of `PresetPopoverTests`:

```swift
    @Test("opening installs three monitors/observers; closing removes them")
    func monitorsClean() {
        let pop = PresetPopover()
        #expect(pop.testOnly_monitorCount == 0)
        pop.open(axis: .size, currentValue: 14,
                 color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 14, tool: .pen, outlineOn: false,
                 anchor: anchor(), edge: .maxX, onPick: { _ in })
        #expect(pop.testOnly_monitorCount == 3)
        pop.close()
        #expect(pop.testOnly_monitorCount == 0)
    }

    @Test("open/close cycles do not accumulate monitors")
    func monitorsNoLeakAcrossCycles() {
        let pop = PresetPopover()
        for _ in 0..<5 {
            pop.open(axis: .size, currentValue: 14,
                     color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 14, tool: .pen, outlineOn: false,
                     anchor: anchor(), edge: .maxX, onPick: { _ in })
            pop.close()
        }
        #expect(pop.testOnly_monitorCount == 0)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test-only PresetPopoverTests`
Expected: FAIL — `testOnly_monitorCount` undefined; or count != 3.

- [ ] **Step 3: Add global mouse monitor and the counter**

Edit `Sources/AppKit/PresetPopover.swift`. Add a stored property:

```swift
    private var globalMouseMonitor: Any?
```

In `open(...)`, after `installDeactivationObserver()`:

```swift
        installGlobalMouseMonitor()
```

In `close()`, after `removeDeactivationObserver()`:

```swift
        removeGlobalMouseMonitor()
```

Add the helpers:

```swift
    private func installGlobalMouseMonitor() {
        if globalMouseMonitor != nil { return }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    private func removeGlobalMouseMonitor() {
        if let token = globalMouseMonitor {
            NSEvent.removeMonitor(token)
            globalMouseMonitor = nil
        }
    }
```

Add the test hook:

```swift
    var testOnly_monitorCount: Int {
        var count = 0
        if localKeyMonitor != nil { count += 1 }
        if globalMouseMonitor != nil { count += 1 }
        if deactivationObserver != nil { count += 1 }
        return count
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `just test-only PresetPopoverTests`
Expected: PASS for all fifteen tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/PresetPopover.swift Tests/AppKitTests/PresetPopoverTests.swift
git commit -m "$(cat <<'EOF'
AppKit: PresetPopover global mouse monitor + monitor-leak invariant

Global addGlobalMonitorForEvents(.leftMouseDown) so out-of-app clicks
dismiss the popover. testOnly_monitorCount sums the three monitors
(local key, global mouse, deactivation observer) so the test suite
catches any leak across open/close cycles — the exact failure mode
that bit the prior ValuePickerControl popover (see commit 7da5e6b).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: `MarkControl` refactor — drop steppers, compose `MarkPreview` + two `PresetButton`s

**Files:**
- Modify: `Sources/AppKit/MarkControl.swift`
- Rewrite: `Tests/AppKitTests/MarkControlTests.swift`

This task replaces the body of `MarkControl` with a thin composition: a size `PresetButton`, the `MarkPreview` view, and an opacity `PresetButton`, plus an `onOpenPopover` callback. All stepper logic and the four `testOnly_tap*` shims go away.

- [ ] **Step 1: Rewrite `MarkControlTests`**

Replace `Tests/AppKitTests/MarkControlTests.swift` entirely:

```swift
// ABOUTME: Tests MarkControl — the toolbar's size/opacity composite. Buttons trigger
// ABOUTME: the popover-open callback; MarkPreview holds the live mark snapshot.

import AppKit
import Testing

@Suite("MarkControl")
@MainActor
struct MarkControlTests {
    @Test("size button click invokes onOpenPopover with .size and the preview rect")
    func sizeButtonOpensPopover() {
        let mc = MarkControl()
        var calls: [(PresetAxis, NSRect)] = []
        mc.onOpenPopover = { axis, rect in calls.append((axis, rect)) }
        mc.testOnly_clickSizeButton()
        #expect(calls.count == 1)
        #expect(calls.first?.0 == .size)
        // The rect should match the preview's bounds when there's no window.
        #expect(calls.first?.1.width == CGFloat(MarkPreview.canvasSize.width))
        #expect(calls.first?.1.height == CGFloat(MarkPreview.canvasSize.height))
    }

    @Test("opacity button click invokes onOpenPopover with .opacity and the preview rect")
    func opacityButtonOpensPopover() {
        let mc = MarkControl()
        var calls: [(PresetAxis, NSRect)] = []
        mc.onOpenPopover = { axis, rect in calls.append((axis, rect)) }
        mc.testOnly_clickOpacityButton()
        #expect(calls.count == 1)
        #expect(calls.first?.0 == .opacity)
    }

    @Test("preview ignores the selection tool, keeping the prior drawing tool")
    func selectionKeepsPriorTool() {
        let mc = MarkControl()
        mc.currentTool = .text
        #expect(mc.testOnly_previewTool == .text)
        mc.currentTool = .selection
        #expect(mc.testOnly_previewTool == .text)
        mc.currentTool = .arrow
        #expect(mc.testOnly_previewTool == .arrow)
    }

    @Test("renders a preview image for each drawing tool and outline state")
    func rendersPreview() {
        let mc = MarkControl()
        mc.color = RGBA(r: 1, g: 0, b: 0, a: 1)
        mc.width = 30
        for tool in [Tool.pen, .arrow, .text] {
            for on in [false, true] {
                mc.currentTool = tool
                mc.outlineOn = on
                #expect(mc.testOnly_hasPreviewImage)
            }
        }
    }

    @Test("size button has the size tooltip and lineweight SF Symbol")
    func sizeButtonTooltip() {
        let mc = MarkControl()
        #expect(mc.testOnly_sizeButtonTooltip == "Size — s / S")
    }

    @Test("opacity button has the opacity tooltip and drop SF Symbol")
    func opacityButtonTooltip() {
        let mc = MarkControl()
        #expect(mc.testOnly_opacityButtonTooltip == "Opacity — o / O")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test-only MarkControlTests`
Expected: FAIL — `MarkControl` has no `onOpenPopover`, no `testOnly_clickSizeButton`, etc.

- [ ] **Step 3: Rewrite `MarkControl`**

Replace `Sources/AppKit/MarkControl.swift` entirely:

```swift
// ABOUTME: Toolbar size/opacity composite — two SF-Symbol PresetButtons sandwiching
// ABOUTME: a live MarkPreview. Click on a button opens the matching popover via callback.

import AppKit

@MainActor
final class MarkControl: NSView {
    /// Fired when the user clicks one of the trigger buttons. The rect is the
    /// MarkPreview's bounds converted to the receiver's window's screen coords
    /// (or the preview's bounds when there is no window — used in tests).
    var onOpenPopover: ((PresetAxis, NSRect) -> Void)?

    var color: RGBA = RGBA(r: 0, g: 0, b: 0, a: 1) { didSet { preview.color = color } }
    var width: Double = 6 { didSet { preview.width = width } }
    var outlineOn: Bool = false { didSet { preview.outlineOn = outlineOn } }
    var currentTool: Tool = .pen { didSet { preview.currentTool = currentTool } }

    private let preview = MarkPreview()
    private let sizeButton = PresetButton.make(symbol: "lineweight",
                                               accessibility: "Size",
                                               tooltip: "Size — s / S")
    private let opacityButton = PresetButton.make(symbol: "drop",
                                                  accessibility: "Opacity",
                                                  tooltip: "Opacity — o / O")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func build() {
        sizeButton.target = self
        sizeButton.action = #selector(sizeClicked)
        opacityButton.target = self
        opacityButton.action = #selector(opacityClicked)

        let stack = NSStackView(views: [sizeButton, preview, opacityButton])
        stack.orientation = .vertical
        stack.spacing = 3
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    @objc private func sizeClicked() {
        onOpenPopover?(.size, previewScreenRect())
    }

    @objc private func opacityClicked() {
        onOpenPopover?(.opacity, previewScreenRect())
    }

    private func previewScreenRect() -> NSRect {
        // When attached to a window, convert preview.bounds to screen coords for the
        // popover anchor. Otherwise (tests without a window), return the local bounds —
        // a caller that needs a real screen rect must add the view to a window.
        guard let window = preview.window else { return preview.bounds }
        let inWindow = preview.convert(preview.bounds, to: nil)
        return window.convertToScreen(inWindow)
    }

    // MARK: Trigger highlight (driven by ToolbarController as popover open/close cycles)

    func setSizeButtonActive(_ active: Bool) { setActiveBackground(sizeButton, active: active) }
    func setOpacityButtonActive(_ active: Bool) { setActiveBackground(opacityButton, active: active) }

    private func setActiveBackground(_ button: NSButton, active: Bool) {
        button.wantsLayer = true
        button.layer?.cornerRadius = 4
        button.layer?.backgroundColor = active
            ? NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
            : NSColor.clear.cgColor
    }

    // MARK: Test hooks

    // swiftlint:disable identifier_name
    func testOnly_clickSizeButton() { sizeClicked() }
    func testOnly_clickOpacityButton() { opacityClicked() }
    var testOnly_previewTool: Tool { preview.testOnly_previewTool }
    var testOnly_hasPreviewImage: Bool { preview.testOnly_hasPreviewImage }
    var testOnly_color: RGBA { color }
    var testOnly_sizeButtonTooltip: String? { sizeButton.toolTip }
    var testOnly_opacityButtonTooltip: String? { opacityButton.toolTip }
    var testOnly_sizeButtonActive: Bool { hasActive(sizeButton) }
    var testOnly_opacityButtonActive: Bool { hasActive(opacityButton) }
    // swiftlint:enable identifier_name

    private func hasActive(_ button: NSButton) -> Bool {
        guard let cg = button.layer?.backgroundColor else { return false }
        return cg.alpha > 0
    }
}
```

Expose `testOnly_previewTool` on `MarkPreview` since `MarkControl` reads it. Edit `Sources/AppKit/MarkPreview.swift`, replace the `// MARK: Test hooks` block at the bottom with:

```swift
    // MARK: Test hooks

    // swiftlint:disable identifier_name
    var testOnly_hasPreviewImage: Bool { imageView.image != nil }
    var testOnly_previewTool: Tool { previewTool }
    // swiftlint:enable identifier_name
```

- [ ] **Step 4: Run test to verify it passes**

Run: `just test-only MarkControlTests` and `just test-only MarkPreviewTests`
Expected: PASS for all six MarkControlTests and all four MarkPreviewTests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/MarkControl.swift Sources/AppKit/MarkPreview.swift Tests/AppKitTests/MarkControlTests.swift
git commit -m "$(cat <<'EOF'
AppKit: MarkControl composes PresetButton + MarkPreview, drops steppers

MarkControl is now a thin vertical stack: lineweight size button,
60x140 MarkPreview, drop opacity button. Click on either button fires
onOpenPopover(axis, anchorRect) so ToolbarController can drive the
PresetPopover. All stepper actions, edge-disabling, +/- buttons, and
the size/opacity labels are removed. setSizeButtonActive /
setOpacityButtonActive expose the active-highlight hook the toolbar
uses while the popover is open for that axis.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: `ToolbarController` opens, toggles, swaps the popover

**Files:**
- Modify: `Sources/AppKit/ToolbarController.swift`
- Modify: `Tests/AppKitTests/ToolbarControllerTests.swift`

This wires the `MarkControl`'s `onOpenPopover` callback through `ToolbarController`. It owns a single `PresetPopover` instance. Click handling implements toggle (re-click closes) and swap (other axis closes + reopens).

- [ ] **Step 1: Replace and add the failing tests**

Edit `Tests/AppKitTests/ToolbarControllerTests.swift`. First, remove the now-broken stepper tests and tooltip assertions for the labels:

- Delete `widthSlider` (line 72-77), `opacityPreservesRGB` (already covered by popover pick test), `widgetChangesPersist` if it uses `testOnly_setWidth`/`setOpacity`, `sizeStepUpdatesController`, `opacityStepUpdatesController`, `widthSliderTooltip`, `opacitySliderTooltip`, `widthLabelText`, `opacityLabelText` — anything that uses the removed `testOnly_setWidth`, `testOnly_setOpacity`, `testOnly_tapSizeUp`, `testOnly_tapOpacityUp`, `testOnly_widthLabelText`, `testOnly_opacityLabelText`, `testOnly_widthSliderTooltip`, `testOnly_opacitySliderTooltip`.

Add the following test (in the `ToolbarControllerTests` suite, in place of the deleted ones):

```swift
    @Test("clicking the size button opens the popover with axis .size")
    func sizeButtonOpensPopover() {
        let (toolbar, _, _) = make()
        toolbar.testOnly_clickSizeButton()
        #expect(toolbar.testOnly_popoverOpen)
        #expect(toolbar.testOnly_popoverAxis == .size)
    }

    @Test("clicking the opacity button opens the popover with axis .opacity")
    func opacityButtonOpensPopover() {
        let (toolbar, _, _) = make()
        toolbar.testOnly_clickOpacityButton()
        #expect(toolbar.testOnly_popoverOpen)
        #expect(toolbar.testOnly_popoverAxis == .opacity)
    }

    @Test("re-clicking the same trigger toggles the popover closed")
    func reclickSameTriggerCloses() {
        let (toolbar, _, _) = make()
        toolbar.testOnly_clickSizeButton()
        #expect(toolbar.testOnly_popoverOpen)
        toolbar.testOnly_clickSizeButton()
        #expect(toolbar.testOnly_popoverOpen == false)
    }

    @Test("clicking the other trigger swaps the popover axis")
    func clickOtherTriggerSwaps() {
        let (toolbar, _, _) = make()
        toolbar.testOnly_clickSizeButton()
        #expect(toolbar.testOnly_popoverAxis == .size)
        toolbar.testOnly_clickOpacityButton()
        #expect(toolbar.testOnly_popoverOpen)
        #expect(toolbar.testOnly_popoverAxis == .opacity)
    }

    @Test("picking a size cell writes through to controller.currentWidth")
    func sizePickWritesWidth() {
        let (toolbar, controller, _) = make()
        toolbar.testOnly_clickSizeButton()
        toolbar.testOnly_pickPopoverCell(at: 6)  // ValuePresets.sizes[6] == 30
        #expect(controller.currentWidth == 30)
        #expect(toolbar.testOnly_popoverOpen == false)
    }

    @Test("picking an opacity cell writes controller.currentColor.a, preserving rgb")
    func opacityPickWritesAlpha() {
        let (toolbar, controller, _) = make()
        controller.currentColor = RGBA(r: 0.2, g: 0.4, b: 0.6, a: 0.5)
        toolbar.testOnly_clickOpacityButton()
        toolbar.testOnly_pickPopoverCell(at: 9)  // 1.0
        #expect(abs(controller.currentColor.a - 1.0) < 1e-6)
        #expect(controller.currentColor.r == 0.2)
        #expect(controller.currentColor.g == 0.4)
        #expect(controller.currentColor.b == 0.6)
    }
```

The `ToolbarControllerTooltipTests` suite needs its `widthSliderTooltip`, `opacitySliderTooltip`, `widthLabelText`, and `opacityLabelText` tests replaced with:

```swift
    @Test("size button tooltip is 'Size — s / S'")
    func sizeButtonTooltip() {
        let (toolbar, _) = make()
        #expect(toolbar.testOnly_sizeButtonTooltip == "Size — s / S")
    }

    @Test("opacity button tooltip is 'Opacity — o / O'")
    func opacityButtonTooltip() {
        let (toolbar, _) = make()
        #expect(toolbar.testOnly_opacityButtonTooltip == "Opacity — o / O")
    }
```

The `widgetChangesPersist` test currently uses `testOnly_setWidth(9)` and `testOnly_setOpacity(0.6)`. Replace its body with:

```swift
        // Persistence is driven by AppController setters (not by widgets), so go
        // directly through the controller — equivalent to the keyboard/HTTP path.
        let toolbar = ToolbarController(controller: controller, defaults: suite)
        controller.currentWidth = 9
        let c = controller.currentColor
        controller.currentColor = RGBA(r: c.r, g: c.g, b: c.b, a: 0.6)
        #expect(suite.double(forKey: "fiti.width") == 9)
        #expect(suite.double(forKey: "fiti.color.a") == 0.6)
        _ = toolbar
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test-only ToolbarControllerTests`
Expected: FAIL — `testOnly_clickSizeButton`, `testOnly_popoverOpen`, etc. undefined.

- [ ] **Step 3: Wire the popover in `ToolbarController`**

Edit `Sources/AppKit/ToolbarController.swift`. Add stored properties next to the other widgets:

```swift
    private let popover = PresetPopover()
```

Replace the `markControl.onWidth` / `markControl.onOpacity` wiring (currently in `init`) with:

```swift
        markControl.onOpenPopover = { [weak self] axis, anchor in
            self?.handleOpenPopover(axis: axis, anchor: anchor)
        }
```

Delete the four lines that wired `markControl.onWidth` and `markControl.onOpacity`.

Add a new method on `ToolbarController`:

```swift
    private func handleOpenPopover(axis: PresetAxis, anchor: NSRect) {
        if popover.isOpen, popover.currentAxis == axis {
            popover.close()
            updateTriggerHighlights()
            return
        }
        if popover.isOpen { popover.close() }

        let edge = pickEdge()
        let currentValue: Double
        switch axis {
        case .size: currentValue = controller.currentWidth
        case .opacity: currentValue = controller.currentColor.a
        }
        // markControl.currentTool already reflects the last drawing tool, because
        // controller.onCurrentToolChanged skips updating it when tool == .selection.
        let tool: Tool = markControl.currentTool
        popover.open(axis: axis,
                     currentValue: currentValue,
                     color: controller.currentColor,
                     width: controller.currentWidth,
                     tool: tool,
                     outlineOn: outlineOn(for: tool),
                     anchor: anchor,
                     edge: edge,
                     onPick: { [weak self] value in
                         self?.commitPick(axis: axis, value: value)
                     })
        updateTriggerHighlights()
    }

    private func commitPick(axis: PresetAxis, value: Double) {
        switch axis {
        case .size:
            controller.currentWidth = value
        case .opacity:
            let c = controller.currentColor
            controller.currentColor = RGBA(r: c.r, g: c.g, b: c.b, a: value)
        }
        updateTriggerHighlights()
    }

    private func pickEdge() -> PopoverEdge {
        guard let screen = panel.screen else { return .maxX }
        return PopoverEdgePicker.pick(toolbarMidX: Double(panel.frame.midX),
                                      screenMidX: Double(screen.frame.midX))
    }

    private func updateTriggerHighlights() {
        markControl.setSizeButtonActive(popover.currentAxis == .size)
        markControl.setOpacityButtonActive(popover.currentAxis == .opacity)
    }
```

Update the test hooks section. Delete the following (their tests are deleted in Step 1 or replaced):
- `func testOnly_tapSizeUp()` and `func testOnly_tapOpacityUp()`
- `internal var testOnly_widthSliderTooltip`
- `internal var testOnly_opacitySliderTooltip`
- `internal var testOnly_widthLabelText`
- `internal var testOnly_opacityLabelText`
- `internal func testOnly_setWidth(_ value: Double)`
- `internal func testOnly_setOpacity(_ value: Double)`

Keep (they read state that still exists on the new `MarkControl`):
- `internal var testOnly_widthSliderValue: Double { markControl.width }` — used by `externalWidthWriteUpdatesWidget`
- `internal var testOnly_markColor: RGBA { markControl.color }` — unchanged
- `internal var testOnly_sizePickerTool: Tool { markControl.testOnly_previewTool }` — unchanged
- `internal var testOnly_sizePickerOutlineOn: Bool { markControl.outlineOn }` — unchanged

Add new hooks (in the same swiftlint-disabled block):

```swift
    func testOnly_clickSizeButton() { markControl.testOnly_clickSizeButton() }
    func testOnly_clickOpacityButton() { markControl.testOnly_clickOpacityButton() }
    func testOnly_pickPopoverCell(at index: Int) { popover.testOnly_clickCell(at: index) }
    var testOnly_popoverOpen: Bool { popover.isOpen }
    var testOnly_popoverAxis: PresetAxis? { popover.currentAxis }
    var testOnly_sizeButtonTooltip: String? { markControl.testOnly_sizeButtonTooltip }
    var testOnly_opacityButtonTooltip: String? { markControl.testOnly_opacityButtonTooltip }
    var testOnly_sizeButtonActive: Bool { markControl.testOnly_sizeButtonActive }
    var testOnly_opacityButtonActive: Bool { markControl.testOnly_opacityButtonActive }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `just test-only ToolbarControllerTests`
Expected: PASS for all tests including the six new popover tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/ToolbarController.swift Tests/AppKitTests/ToolbarControllerTests.swift
git commit -m "$(cat <<'EOF'
AppKit: ToolbarController drives PresetPopover open/toggle/swap

Owns one PresetPopover. MarkControl's onOpenPopover callback routes
into handleOpenPopover which implements: re-click closes, click other
trigger swaps. Cell pick writes through to controller.currentWidth or
currentColor.a (preserving rgb). Edge is picked via the pure
PopoverEdgePicker from the toolbar panel's midX vs its screen's midX.

The stepper-era test shims (testOnly_setWidth/setOpacity/tapSize*/
tapOpacity*) and label/tooltip getters are removed; their replacements
target the button tooltips and popover state.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: Tool change closes the popover

**Files:**
- Modify: `Sources/AppKit/ToolbarController.swift`
- Modify: `Tests/AppKitTests/ToolbarControllerTests.swift`

The spec calls this out as an edge case: cells capture the tool at open time, so a tool change while open would leave stale renders. The fix is to close on `controller.onCurrentToolChanged`.

- [ ] **Step 1: Add the failing test**

Add to the `ToolbarControllerTests` suite:

```swift
    @Test("changing currentTool while the popover is open closes it")
    func toolChangeClosesPopover() {
        let (toolbar, controller, _) = make()
        toolbar.testOnly_clickSizeButton()
        #expect(toolbar.testOnly_popoverOpen)
        controller.currentTool = .arrow
        #expect(toolbar.testOnly_popoverOpen == false)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test-only ToolbarControllerTests`
Expected: FAIL — popover stays open after the tool change.

- [ ] **Step 3: Hook the tool-change callback**

Edit `Sources/AppKit/ToolbarController.swift`. In `init`, find the existing block:

```swift
        controller.onCurrentToolChanged = { [weak self] tool in
            guard let self else { return }
            self.updateToolHighlights()
            if tool != .selection {
                self.markControl.currentTool = tool
                self.markControl.outlineOn = self.outlineOn(for: tool)
            }
        }
```

Add a `popover.close()` and a highlight refresh at the top of that closure:

```swift
        controller.onCurrentToolChanged = { [weak self] tool in
            guard let self else { return }
            if self.popover.isOpen {
                self.popover.close()
                self.updateTriggerHighlights()
            }
            self.updateToolHighlights()
            if tool != .selection {
                self.markControl.currentTool = tool
                self.markControl.outlineOn = self.outlineOn(for: tool)
            }
        }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `just test-only ToolbarControllerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/ToolbarController.swift Tests/AppKitTests/ToolbarControllerTests.swift
git commit -m "$(cat <<'EOF'
AppKit: tool change closes the size/opacity popover

PresetPopover cells capture the tool at open time, so a mid-pick tool
change would leave stale renders on screen. Closing on
onCurrentToolChanged sidesteps that — the user can reopen on the new
tool to see fresh cells.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 14: Active highlight on the trigger button while the popover is open

**Files:**
- Modify: `Tests/AppKitTests/ToolbarControllerTests.swift`

The wiring already exists (Task 12 added `updateTriggerHighlights()`). This task adds the test that locks the behavior in so a future refactor can't silently drop it.

- [ ] **Step 1: Add the test**

Add to the `ToolbarControllerActiveStateTests` suite:

```swift
    @Test("size button gains an active background while its popover is open")
    func sizeButtonActiveWhileOpen() {
        let (toolbar, _) = make()
        #expect(toolbar.testOnly_sizeButtonActive == false)
        toolbar.testOnly_clickSizeButton()
        #expect(toolbar.testOnly_sizeButtonActive == true)
        #expect(toolbar.testOnly_opacityButtonActive == false)
        toolbar.testOnly_clickSizeButton()  // close
        #expect(toolbar.testOnly_sizeButtonActive == false)
    }

    @Test("opacity button gains an active background while its popover is open")
    func opacityButtonActiveWhileOpen() {
        let (toolbar, _) = make()
        toolbar.testOnly_clickOpacityButton()
        #expect(toolbar.testOnly_opacityButtonActive == true)
        #expect(toolbar.testOnly_sizeButtonActive == false)
    }

    @Test("swap clears the previous trigger's active background and lights the new one")
    func swapMovesActiveHighlight() {
        let (toolbar, _) = make()
        toolbar.testOnly_clickSizeButton()
        toolbar.testOnly_clickOpacityButton()
        #expect(toolbar.testOnly_sizeButtonActive == false)
        #expect(toolbar.testOnly_opacityButtonActive == true)
    }
```

`ToolbarControllerActiveStateTests.make()` returns `(ToolbarController, AppController)` — note the two-tuple, not the three-tuple used in `ToolbarControllerTests`.

- [ ] **Step 2: Run test to verify it passes**

Run: `just test-only ToolbarControllerActiveStateTests`
Expected: PASS for all three new tests (existing tests continue to pass).

- [ ] **Step 3: Commit**

```bash
git add Tests/AppKitTests/ToolbarControllerTests.swift
git commit -m "$(cat <<'EOF'
AppKit: lock in size/opacity trigger highlight while popover is open

Active background on the trigger button matches the open popover's
axis, mirrors away when the popover closes, and swaps when the user
clicks the other trigger. Covered by three tests in the existing
ActiveStateTests suite.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 15: Final sanity — `just check`

**Files:** none (verification only).

- [ ] **Step 1: Run the full CI gate**

Run: `just check`

Expected: tests + lint + build all pass.

- [ ] **Step 2: Manual smoke check (optional but recommended)**

Run: `just run-bg`

Verify in the running app:
- Toolbar shows a `lineweight` icon button above the live preview and a `drop` icon button below it. No `−size+` or `−opacity+` rows.
- Click the size button: a horizontal popover of 10 stroke cells extends to the right of the toolbar (assuming the toolbar is on the left half of the screen). The cell matching the current preset has an accent ring.
- Click a cell: the popover closes and the in-toolbar preview updates to the new size.
- Press the size button again: popover opens. Press it again: popover closes.
- Open the size popover, then click the opacity button: size popover closes, opacity popover opens.
- Open a popover, press ESC: closes.
- Open a popover, change tool with the `p`/`t`/`a` keys: popover closes.
- Drag the toolbar to the right half of the screen; open a popover: extends to the left.

Run: `just stop`

- [ ] **Step 3: Commit only if any test or lint adjustments were needed**

If `just check` flagged anything (formatting, unused symbol warnings, etc.), fix inline and commit. If everything was clean, no commit is needed — the implementation is already on `main` in earlier task commits.

```bash
# Only if there were fix-ups
git add -A
git commit -m "$(cat <<'EOF'
AppKit: tidy size/opacity popover implementation post-CI

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-review notes

- **Spec coverage:** Tasks 1–2 cover the Core surface (`PresetAxis`, `PopoverEdgePicker`). Task 3 covers `MarkPreview` (architecture §AppKit). Task 4 covers `PresetButton`. Tasks 5–10 cover `PresetPopover` (skeleton → cells → click → ESC → didResignActive → global mouse / leak invariant). Task 11 covers `MarkControl` refactor + its rewritten tests. Task 12 covers `ToolbarController` open/toggle/swap and the size + opacity pick paths. Task 13 covers the tool-change-closes edge case. Task 14 covers the active-highlight requirement. Task 15 covers the CI gate. Every requirement in the spec's Goals / Decisions / Data flow / Edge cases / Testing sections maps to a task.
- **Out-of-scope items:** click-outside via the global mouse monitor cannot be reliably synthesized in tests; per the spec's Testing § "Out of scope," we rely on the monitor-leak invariant (Task 10) and the explicit `close()`/ESC/didResignActive tests to verify the close machinery.
- **Migration:** the four `testOnly_tap*` and `testOnly_set*` shims on `ToolbarController` are removed inside Task 12. The four `testOnly_tap*`/`testOnly_*Enabled` shims on `MarkControl` are removed inside Task 11. No `AppController` surface changes; no persistence migration.
