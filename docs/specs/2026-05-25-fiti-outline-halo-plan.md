# Outline / Halo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A global, non-destructive toggle that draws an auto-contrast halo around pen strokes, arrows, and text for legibility on any background.

**Architecture:** All policy (enabled, halo color, halo width) is a pure Core `resolveOutline`; AppKit draw functions call it and render one native stroke pass (text via a negative `NSAttributedString.strokeWidth`). The toggle is a Core `OutlineSettings` port with a UserDefaults adapter, mirroring the `FadeSettings` pattern. The halo rides inside each item's draw, so the existing opacity-flattening is untouched.

**Tech Stack:** Swift, Swift Testing, CoreGraphics + CoreText (AppKit only), XcodeGen + xcodebuild via `just`.

**Source of truth:** `docs/specs/2026-05-25-fiti-outline-halo-design.md`.

**Conventions (all tasks):**
- Red/green TDD: write the failing test, run it to see it fail, implement, run to see it pass, commit. `just check` (the pre-commit hook, `--strict` lint) must pass at every commit; never `--no-verify`.
- `just test` runs the Core-only `fiti-unit` target. `just test-integration` runs the AppKit target. `just check` is the full gate.
- Every new Swift file starts with two `// ABOUTME:` lines.
- `Sources/Core` must not import AppKit, CoreGraphics, CoreText, Network, or SwiftUI.
- Commit messages use a HEREDOC ending with `Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>`.
- Swift Testing (`import Testing`, `@Test`, `@Suite`, `#expect`), suite under 5s.
- SwiftLint `--strict`: function parameter count warns above 5, type-body ~250 lines, file ~400 lines. Targeted `// swiftlint:disable:next <rule>` is acceptable where noted.
- SourceKit "No such module 'Testing'" / "Cannot find type" editor diagnostics are cross-module indexing noise; trust `just`, not the editor.

---

## Task 1: OutlineSettings port (Core)

**Files:**
- Create: `Sources/Core/Ports/OutlineSettings.swift`
- Test: `Tests/CoreTests/PortTests/OutlineSettingsTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ABOUTME: Tests the in-memory DefaultOutlineSettings: defaults off, round-trips.

import Testing

@Suite("OutlineSettings")
@MainActor
struct OutlineSettingsTests {
    @Test("defaults to off")
    func defaultsOff() {
        #expect(DefaultOutlineSettings().outlineEnabled == false)
    }

    @Test("holds an injected value and round-trips a write")
    func roundTrips() {
        let s = DefaultOutlineSettings(outlineEnabled: true)
        #expect(s.outlineEnabled == true)
        s.outlineEnabled = false
        #expect(s.outlineEnabled == false)
    }
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `just test`
Expected: FAIL (`DefaultOutlineSettings` undefined).

- [ ] **Step 3: Create the port**

```swift
// ABOUTME: Port for the global outline/halo render-mode toggle. AppKit backs it with
// ABOUTME: UserDefaults; tests and default wiring use the in-memory DefaultOutlineSettings.

/// Whether marks render with a contrasting halo. Read live by the renderer; a
/// global, non-destructive render mode (the document model is unchanged).
@MainActor
public protocol OutlineSettings: AnyObject {
    var outlineEnabled: Bool { get set }
}

/// In-memory `OutlineSettings`. Production injects a persistent adapter; tests
/// inject this with an explicit value.
@MainActor
public final class DefaultOutlineSettings: OutlineSettings {
    public var outlineEnabled: Bool
    public init(outlineEnabled: Bool = false) {
        self.outlineEnabled = outlineEnabled
    }
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `just test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "$(cat <<'EOF'
Core: OutlineSettings port + in-memory default

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: UserDefaultsOutlineSettings adapter (AppKit)

**Files:**
- Create: `Sources/AppKit/UserDefaultsOutlineSettings.swift`
- Test: `Tests/AppKitTests/UserDefaultsOutlineSettingsTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ABOUTME: Tests the UserDefaults-backed OutlineSettings adapter: default off
// ABOUTME: when unset, and round-trip persistence.

import AppKit
import Testing

@Suite("UserDefaultsOutlineSettings")
@MainActor
struct UserDefaultsOutlineSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "fiti.tests.outline.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test("unset reads as off")
    func unsetIsOff() {
        #expect(UserDefaultsOutlineSettings(defaults: freshDefaults()).outlineEnabled == false)
    }

    @Test("a set value round-trips and persists across adapters")
    func roundTrips() {
        let d = freshDefaults()
        let s = UserDefaultsOutlineSettings(defaults: d)
        s.outlineEnabled = true
        #expect(s.outlineEnabled == true)
        #expect(UserDefaultsOutlineSettings(defaults: d).outlineEnabled == true)
    }
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `just test-integration`
Expected: FAIL (type undefined).

- [ ] **Step 3: Create the adapter**

```swift
// ABOUTME: UserDefaults-backed OutlineSettings adapter. Persists the global
// ABOUTME: outline/halo toggle under "fiti.outlineEnabled", defaulting to off.

import Foundation

@MainActor
public final class UserDefaultsOutlineSettings: OutlineSettings {
    static let key = "fiti.outlineEnabled"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var outlineEnabled: Bool {
        get { defaults.bool(forKey: Self.key) }   // unset -> false
        set { defaults.set(newValue, forKey: Self.key) }
    }
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `just test-integration`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "$(cat <<'EOF'
AppKit: UserDefaults adapter for the outline toggle

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: OutlineTuning constants (Core)

**Files:**
- Create: `Sources/Core/Rendering/OutlineTuning.swift`

Constants only; no behavior, so no test (it just needs to compile).

- [ ] **Step 1: Create the file**

```swift
// ABOUTME: Hand-tuned constants for the outline/halo look (per-type halo weight,
// ABOUTME: luminance split). Not exposed in the UI; tweak here and rebuild.

public enum OutlineTuning {
    /// Halo line width as a fraction of stroke/arrow width (points).
    public static let strokeWidthFactor: Double = 0.5
    /// Halo weight for text as a fraction of font size; becomes the negative
    /// NSAttributedString strokeWidth percentage (textWidthFactor * 100).
    public static let textWidthFactor: Double = 0.06
    /// Below this Rec.601 luminance the halo is light (white), at/above it dark (black).
    public static let luminanceThreshold: Double = 0.5
}
```

- [ ] **Step 2: Confirm it compiles**

Run: `just test`
Expected: PASS (no new tests; build succeeds).

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "$(cat <<'EOF'
Core: OutlineTuning look constants

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: resolveOutline — the pure policy (Core)

**Files:**
- Create: `Sources/Core/Rendering/OutlineStyle.swift`
- Test: `Tests/CoreTests/RenderingTests/OutlineStyleTests.swift`

This is the feature's brain: enabled gate, auto-contrast color, halo width. Fully unit-tested in Core.

- [ ] **Step 1: Write the failing tests**

```swift
// ABOUTME: Tests resolveOutline: nil when disabled, white/black halo by luminance,
// ABOUTME: alpha preserved, width = sizeBasis * widthFactor, threshold boundary.

import Testing

@Suite("resolveOutline")
struct OutlineStyleTests {
    @Test("disabled returns nil")
    func disabledNil() {
        #expect(resolveOutline(enabled: false, color: RGBA(r: 0.5, g: 0.1, b: 0.1, a: 1),
                               sizeBasis: 40, widthFactor: 0.5) == nil)
    }

    @Test("dark color yields a white halo")
    func darkToWhite() {
        let o = resolveOutline(enabled: true, color: RGBA(r: 0.1, g: 0.1, b: 0.1, a: 1),
                               sizeBasis: 40, widthFactor: 0.5)
        #expect(o?.haloColor == RGBA(r: 1, g: 1, b: 1, a: 1))
    }

    @Test("light color yields a black halo")
    func lightToBlack() {
        let o = resolveOutline(enabled: true, color: RGBA(r: 0.95, g: 0.95, b: 0.95, a: 1),
                               sizeBasis: 40, widthFactor: 0.5)
        #expect(o?.haloColor == RGBA(r: 0, g: 0, b: 0, a: 1))
    }

    @Test("halo alpha equals the mark alpha")
    func alphaPreserved() {
        let o = resolveOutline(enabled: true, color: RGBA(r: 0.1, g: 0.1, b: 0.1, a: 0.5),
                               sizeBasis: 40, widthFactor: 0.5)
        #expect(o?.haloColor.a == 0.5)
    }

    @Test("halo width is sizeBasis * widthFactor")
    func widthMath() {
        let o = resolveOutline(enabled: true, color: RGBA(r: 0.1, g: 0.1, b: 0.1, a: 1),
                               sizeBasis: 40, widthFactor: 0.5)
        #expect(o?.haloWidth == 20)
    }

    @Test("luminance threshold splits white vs black in both directions")
    func thresholdBoundary() {
        // Rec.601 luminance of a pure gray g is g; threshold is 0.5.
        let justDark = resolveOutline(enabled: true, color: RGBA(r: 0.49, g: 0.49, b: 0.49, a: 1),
                                      sizeBasis: 1, widthFactor: 1)
        let justLight = resolveOutline(enabled: true, color: RGBA(r: 0.51, g: 0.51, b: 0.51, a: 1),
                                       sizeBasis: 1, widthFactor: 1)
        #expect(justDark?.haloColor == RGBA(r: 1, g: 1, b: 1, a: 1))
        #expect(justLight?.haloColor == RGBA(r: 0, g: 0, b: 0, a: 1))
    }
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `just test`
Expected: FAIL (`resolveOutline` / `ResolvedOutline` undefined).

- [ ] **Step 3: Implement**

```swift
// ABOUTME: Pure outline policy: resolves the contrast halo color (by luminance)
// ABOUTME: and halo width for a mark. No AppKit; the rendering layer consumes this.

public struct ResolvedOutline: Equatable {
    public let haloColor: RGBA
    public let haloWidth: Double   // points
    public init(haloColor: RGBA, haloWidth: Double) {
        self.haloColor = haloColor
        self.haloWidth = haloWidth
    }
}

/// Returns nil when disabled. Otherwise the halo color is the luminance-contrast
/// of `color` (white on dark, black on light) preserving alpha, and the halo
/// width is `sizeBasis * widthFactor` in points.
public func resolveOutline(enabled: Bool, color: RGBA, sizeBasis: Double,
                           widthFactor: Double) -> ResolvedOutline? {
    guard enabled else { return nil }
    let luminance = 0.299 * color.r + 0.587 * color.g + 0.114 * color.b
    let halo: RGBA = luminance < OutlineTuning.luminanceThreshold
        ? RGBA(r: 1, g: 1, b: 1, a: color.a)
        : RGBA(r: 0, g: 0, b: 0, a: color.a)
    return ResolvedOutline(haloColor: halo, haloWidth: sizeBasis * widthFactor)
}
```

- [ ] **Step 4: Run the tests to confirm they pass**

Run: `just test`
Expected: PASS (all six).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "$(cat <<'EOF'
Core: resolveOutline pure policy (contrast halo color + width)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Halo rendering in the draw functions (AppKit)

**Files:**
- Modify: `Sources/AppKit/StrokeDrawing.swift` (drawItem, drawStroke, drawText, drawTextString, + a shared halo helper)
- Modify: `Sources/AppKit/ArrowDrawing.swift` (drawArrow)
- Test: `Tests/AppKitTests/OutlineRenderingTests.swift`

Each draw function gains `outline: Bool = false` and calls the Core resolver. Stroke and arrow share a halo-stroke helper; text uses NSAttributedString attributes.

- [ ] **Step 1: Write the failing tests**

```swift
// ABOUTME: Pixel tests for the outline halo on strokes, arrows, and text: a contrast
// ABOUTME: halo appears around the mark with outline on, and is absent with it off.

import AppKit
import CoreGraphics
import Testing

@MainActor
@Suite("Outline halo rendering")
struct OutlineRenderingTests {
    private func makeContext(_ w: Int, _ h: Int) -> CGContext {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        return CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                         bytesPerRow: 0, space: cs,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
    // count near-white opaque pixels in a region (the contrast halo of a dark-red mark)
    private func whiteCount(_ ctx: CGContext, xs: StrideThrough<Int>, ys: StrideThrough<Int>) -> Int {
        let bpr = ctx.bytesPerRow
        let p = ctx.data!.bindMemory(to: UInt8.self, capacity: bpr * ctx.height)
        var n = 0
        for y in ys { for x in xs {
            let i = y * bpr + x * 4
            if p[i + 3] > 120 && p[i] > 180 && p[i + 1] > 180 && p[i + 2] > 180 { n += 1 }
        } }
        return n
    }
    private func darkRed() -> RGBA { RGBA(r: 0.5, g: 0.1, b: 0.1, a: 1) }

    @Test("stroke gets a white halo with outline on, none with it off")
    func strokeHalo() {
        func render(_ outline: Bool) -> CGContext {
            let s = Stroke(id: "a", color: darkRed(), width: 40, transform: .identity,
                           points: [StrokePoint(x: 20, y: 80), StrokePoint(x: 180, y: 80)],
                           pointerType: .mouse, pressureEnabled: false, createdAt: 0)
            let ctx = makeContext(200, 160)
            drawStroke(s, in: ctx, isInProgress: false, outline: outline)
            return ctx
        }
        // scan a column just outside the ~40px band (edges near y=60 and y=100)
        let on = whiteCount(render(true), xs: stride(from: 95, through: 105, by: 1),
                            ys: stride(from: 101, through: 116, by: 1))
        let off = whiteCount(render(false), xs: stride(from: 95, through: 105, by: 1),
                             ys: stride(from: 101, through: 116, by: 1))
        #expect(on > 5)
        #expect(off == 0)
    }

    @Test("arrow gets a white halo with outline on, none with it off")
    func arrowHalo() {
        func render(_ outline: Bool) -> CGContext {
            let a = ArrowItem(id: "a", color: darkRed(), width: 40, transform: .identity,
                              tail: Point(x: 100, y: 30), head: Point(x: 100, y: 150),
                              createdAt: 0)
            let ctx = makeContext(200, 200)
            drawArrow(a, in: ctx, isInProgress: false, outline: outline)
            return ctx
        }
        // scan a column just left of the vertical shaft
        let on = whiteCount(render(true), xs: stride(from: 70, through: 86, by: 1),
                            ys: stride(from: 60, through: 120, by: 1))
        let off = whiteCount(render(false), xs: stride(from: 70, through: 86, by: 1),
                             ys: stride(from: 60, through: 120, by: 1))
        #expect(on > 5)
        #expect(off == 0)
    }

    @Test("text gets white halo pixels on the glyphs with outline on, none with it off")
    func textHalo() {
        func render(_ outline: Bool) -> CGContext {
            let t = TextItem(id: "a", color: darkRed(), fontName: "Helvetica-Bold", fontSize: 60,
                             transform: .identity, string: "H",
                             bounds: Size(width: 60, height: 70), createdAt: 0)
            let ctx = makeContext(120, 100)
            drawText(t, in: ctx, outline: outline)
            return ctx
        }
        let on = whiteCount(render(true), xs: stride(from: 0, through: 119, by: 1),
                            ys: stride(from: 0, through: 99, by: 1))
        let off = whiteCount(render(false), xs: stride(from: 0, through: 119, by: 1),
                             ys: stride(from: 0, through: 99, by: 1))
        #expect(on > 5)
        #expect(off == 0)
    }
}
```

NOTE: Verify the `ArrowItem`, `TextItem`, `Point`, `Size`, `Stroke` initializer labels against the model files (`Sources/Core/Model/`) and existing tests (`Tests/AppKitTests/ArrowDrawingTests.swift`, `CanvasViewTextSessionTests.swift`); adjust the fixtures if a label/field differs. The pixel scan windows assume `OutlineTuning.strokeWidthFactor = 0.5`; if you tune that down, widen/shift the scan so the assertions still hit the halo (do not weaken the `> 5` / `== 0` thresholds).

- [ ] **Step 2: Run it to confirm it fails**

Run: `just test-integration`
Expected: FAIL (`outline:` argument does not exist).

- [ ] **Step 3: Add the shared halo helper + thread `outline` through StrokeDrawing.swift**

In `Sources/AppKit/StrokeDrawing.swift`, add an internal helper (module-internal so `ArrowDrawing.swift` can call it):

```swift
/// Stroke `path` with the resolved contrast halo behind the fill, if outline is on.
/// Shared by drawStroke and drawArrow (both use the stroke/arrow width factor).
func strokeHaloIfNeeded(_ path: CGPath, color: RGBA, sizeBasis: Double,
                        outline: Bool, in ctx: CGContext) {
    guard let halo = resolveOutline(enabled: outline, color: color, sizeBasis: sizeBasis,
                                    widthFactor: OutlineTuning.strokeWidthFactor) else { return }
    ctx.setStrokeColor(red: CGFloat(halo.haloColor.r), green: CGFloat(halo.haloColor.g),
                       blue: CGFloat(halo.haloColor.b), alpha: CGFloat(halo.haloColor.a))
    ctx.setLineWidth(CGFloat(halo.haloWidth))
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)
    ctx.addPath(path)
    ctx.strokePath()
}
```

Replace `drawItem` and `drawStroke` with:

```swift
public func drawItem(_ item: CanvasItem, in ctx: CGContext, isInProgress: Bool, outline: Bool = false) {
    switch item {
    case .stroke(let s): drawStroke(s, in: ctx, isInProgress: isInProgress, outline: outline)
    case .text(let t): drawText(t, in: ctx, outline: outline)
    case .arrow(let a): drawArrow(a, in: ctx, isInProgress: isInProgress, outline: outline)
    }
}

public func drawStroke(_ stroke: Stroke, in ctx: CGContext, isInProgress: Bool, outline: Bool = false) {
    guard !stroke.points.isEmpty else { return }
    let opts = FitiStrokeOptions.make(width: stroke.width, last: !isInProgress || stroke.snappedToLine)
    let polygon = getStroke(points: stroke.points.perfectFreehandInputs, options: opts)
    guard polygon.count >= 3 else { return }

    withItemTransform(stroke.transform, in: ctx) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: polygon[0].x, y: polygon[0].y))
        for v in polygon.dropFirst() {
            path.addLine(to: CGPoint(x: v.x, y: v.y))
        }
        path.closeSubpath()
        strokeHaloIfNeeded(path, color: stroke.color, sizeBasis: stroke.width, outline: outline, in: ctx)
        ctx.setFillColor(red: CGFloat(stroke.color.r), green: CGFloat(stroke.color.g),
                         blue: CGFloat(stroke.color.b), alpha: CGFloat(stroke.color.a))
        ctx.addPath(path)
        ctx.fillPath()
    }
}
```

Replace `drawText` and `drawTextString`. `drawText` gains the param; `drawTextString` gains it too (this pushes it to 6 params — add the targeted disable shown):

```swift
public func drawText(_ text: TextItem, in ctx: CGContext, outline: Bool = false) {
    withItemTransform(text.transform, in: ctx) {
        drawTextString(text.string, fontName: text.fontName, fontSize: text.fontSize,
                       color: text.color, in: ctx, outline: outline)
    }
}

// swiftlint:disable:next function_parameter_count
func drawTextString(_ string: String, fontName: String, fontSize: Double,
                    color: RGBA, in ctx: CGContext, outline: Bool = false) {
    let font = NSFont(name: fontName, size: CGFloat(fontSize))
        ?? NSFont.systemFont(ofSize: CGFloat(fontSize))
    var attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(
            calibratedRed: CGFloat(color.r),
            green: CGFloat(color.g),
            blue: CGFloat(color.b),
            alpha: CGFloat(color.a)
        )
    ]
    if let halo = resolveOutline(enabled: outline, color: color, sizeBasis: fontSize,
                                 widthFactor: OutlineTuning.textWidthFactor) {
        attrs[.strokeColor] = NSColor(calibratedRed: CGFloat(halo.haloColor.r),
                                      green: CGFloat(halo.haloColor.g),
                                      blue: CGFloat(halo.haloColor.b),
                                      alpha: CGFloat(halo.haloColor.a))
        // NSAttributedString strokeWidth is a percentage of font size; negative = fill AND stroke.
        attrs[.strokeWidth] = -100.0 * halo.haloWidth / fontSize
    }
    // CanvasView is isFlipped and the bake context applies its own y-flip, so the
    // local drawing space has y increasing downward. CoreText ignores the context
    // flip and would render glyphs mirrored vertically, so apply the corrective
    // text matrix to draw glyphs upright.
    ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)

    let lh = lineHeight(for: font)
    let ascent = font.ascender
    let lines = string.components(separatedBy: "\n")
    for (index, line) in lines.enumerated() {
        let attrStr = NSAttributedString(string: line, attributes: attrs)
        let ctLine = CTLineCreateWithAttributedString(attrStr)
        let yOffset = CGFloat(index) * lh + ascent
        ctx.textPosition = CGPoint(x: 0, y: yOffset)
        CTLineDraw(ctLine, ctx)
    }
}
```

(Only the `attrs` becomes `var` and the `if let halo` block plus the `outline` params are new; the rest of `drawTextString` is unchanged.)

- [ ] **Step 4: Thread `outline` through ArrowDrawing.swift**

Replace `drawArrow` in `Sources/AppKit/ArrowDrawing.swift` with (note the local polygon is renamed `poly` to avoid shadowing the new `outline` parameter):

```swift
public func drawArrow(_ arrow: ArrowItem, in ctx: CGContext, isInProgress: Bool, outline: Bool = false) {
    let poly = ArrowGeometry.outline(tail: arrow.tail, head: arrow.head, width: arrow.width)
    guard poly.count >= 3 else { return }

    withItemTransform(arrow.transform, in: ctx) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: poly[0].x, y: poly[0].y))
        for p in poly.dropFirst() {
            path.addLine(to: CGPoint(x: p.x, y: p.y))
        }
        path.closeSubpath()
        strokeHaloIfNeeded(path, color: arrow.color, sizeBasis: arrow.width, outline: outline, in: ctx)
        ctx.setFillColor(red: CGFloat(arrow.color.r), green: CGFloat(arrow.color.g),
                         blue: CGFloat(arrow.color.b), alpha: CGFloat(arrow.color.a))
        ctx.setStrokeColor(red: CGFloat(arrow.color.r), green: CGFloat(arrow.color.g),
                           blue: CGFloat(arrow.color.b), alpha: CGFloat(arrow.color.a))
        let cornerRoundWidth = arrow.width * 0.17
        ctx.setLineWidth(cornerRoundWidth)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.addPath(path)
        ctx.drawPath(using: .fillStroke)
    }
}
```

- [ ] **Step 5: Run the tests to confirm they pass**

Run: `just test-integration`
Expected: PASS (stroke/arrow/text halo). If a halo scan finds nothing, confirm the band geometry against the actual `getStroke`/`ArrowGeometry.outline` output and adjust the scan window (not the thresholds). Existing `StrokeDrawingTests`, `ArrowDrawingTests` must still pass (outline defaults off).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "$(cat <<'EOF'
AppKit: render an auto-contrast halo on strokes, arrows, and text

drawStroke/drawArrow stroke the silhouette in the resolved contrast color behind
the fill via a shared strokeHaloIfNeeded; drawText adds a negative
NSAttributedString strokeWidth. All gated by an outline flag, off by default.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: compositeGroups + SnapshotRenderer pass-through (AppKit)

**Files:**
- Modify: `Sources/AppKit/GroupCompositor.swift`
- Modify: `Sources/AppKit/SnapshotRenderer.swift`
- Test: `Tests/AppKitTests/SnapshotRendererOutlineTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ABOUTME: SnapshotRenderer renders the outline halo when asked, matching CanvasView.

import AppKit
import Testing

@MainActor
@Suite("SnapshotRenderer outline")
struct SnapshotRendererOutlineTests {
    @Test("outline snapshot differs from the plain snapshot")
    func differs() {
        let stroke = Stroke(id: "a", color: RGBA(r: 0.5, g: 0.1, b: 0.1, a: 1), width: 40,
                            transform: .identity,
                            points: [StrokePoint(x: 20, y: 50), StrokePoint(x: 180, y: 50)],
                            pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        let frame = RenderFrame(items: [.stroke(stroke)], inProgress: nil,
                                canvasSize: Size(width: 200, height: 100))
        let plain = SnapshotRenderer.png(from: frame, outline: false)
        let haloed = SnapshotRenderer.png(from: frame, outline: true)
        #expect(plain != nil && haloed != nil)
        #expect(plain != haloed)
    }
}
```

- [ ] **Step 2: Run to confirm it fails**

Run: `just test-integration`
Expected: FAIL (`outline:` argument does not exist).

- [ ] **Step 3: Add the parameter to compositeGroups**

In `Sources/AppKit/GroupCompositor.swift`, change the signature and the inner draw call:

```swift
func compositeGroups(_ groups: [FlattenLayer], in ctx: CGContext, outline: Bool = false) {
```
and inside the loop, change `drawItem(item.withAlpha(1), in: ctx, isInProgress: false)` to
`drawItem(item.withAlpha(1), in: ctx, isInProgress: false, outline: outline)`.

- [ ] **Step 4: Add the parameter to SnapshotRenderer**

In `Sources/AppKit/SnapshotRenderer.swift`, change the signature:

```swift
    public static func png(from frame: RenderFrame, scale: CGFloat = 2.0,
                           outline: Bool = false) -> Data? {
```
and change the two draw calls:
```swift
        let groups = LayerPlan.compute(items: frame.items, aabb: { SelectionMath.worldAABB(of: $0) })
        compositeGroups(groups, in: ctx, outline: outline)
        if let inProgress = frame.inProgress { drawItem(inProgress, in: ctx, isInProgress: true, outline: outline) }
```

- [ ] **Step 5: Run to confirm it passes**

Run: `just test-integration`
Expected: PASS. Existing `SnapshotRendererTests` and `GroupCompositorTests` still pass (defaults off).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "$(cat <<'EOF'
AppKit: thread outline through compositeGroups and SnapshotRenderer

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: CanvasView integration (toggle, invalidation, live halo)

**Files:**
- Modify: `Sources/AppKit/CanvasView.swift`
- Test: `Tests/AppKitTests/CanvasViewOutlineTests.swift`

When outline is on, the committed bake, the live in-progress mark, the lifted union, in-flight items, and live text all draw with the halo; flipping the toggle re-bakes.

- [ ] **Step 1: Write the failing tests**

```swift
// ABOUTME: CanvasView honors the OutlineSettings toggle: the committed bake gains a
// ABOUTME: contrast halo and re-bakes when the toggle flips.

import AppKit
import Testing

@MainActor
@Suite("CanvasView outline mode")
struct CanvasViewOutlineTests {
    private func fatStroke() -> Stroke {
        Stroke(id: "a", color: RGBA(r: 0.5, g: 0.1, b: 0.1, a: 1), width: 40,
               transform: .identity,
               points: [StrokePoint(x: 20, y: 80), StrokePoint(x: 180, y: 80)],
               pointerType: .mouse, pressureEnabled: false, createdAt: 0)
    }
    private func frame() -> RenderFrame {
        RenderFrame(items: [.stroke(fatStroke())], inProgress: nil,
                    canvasSize: Size(width: 200, height: 160))
    }
    private func whiteCountInBake(_ view: CanvasView) throws -> Int {
        let image = try #require(view.testOnly_committedImage)
        let ctx = try #require(CGContext(data: nil, width: image.width, height: image.height,
                                         bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bpr = ctx.bytesPerRow
        let data = try #require(ctx.data)
        let p = data.bindMemory(to: UInt8.self, capacity: bpr * image.height)
        var n = 0
        for y in 0..<image.height { for x in 0..<image.width {
            let i = y * bpr + x * 4
            if p[i + 3] > 120 && p[i] > 180 && p[i + 1] > 180 && p[i + 2] > 180 { n += 1 }
        } }
        return n
    }

    @Test("outline on adds white halo pixels to the bake")
    func haloInBake() throws {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 200, height: 160))
        view.outlineSettings = DefaultOutlineSettings(outlineEnabled: true)
        view.render(frame())
        #expect(try whiteCountInBake(view) > 20)
    }

    @Test("flipping the toggle re-bakes (halo appears, then is gone)")
    func toggleRebakes() throws {
        let settings = DefaultOutlineSettings(outlineEnabled: false)
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 200, height: 160))
        view.outlineSettings = settings
        view.render(frame())
        #expect(try whiteCountInBake(view) == 0)
        settings.outlineEnabled = true
        view.refresh()
        #expect(try whiteCountInBake(view) > 20)
    }
}
```

- [ ] **Step 2: Run to confirm it fails**

Run: `just test-integration`
Expected: FAIL (`outlineSettings`, `refresh()` undefined).

- [ ] **Step 3: Add the settings property + refresh + invalidation**

In `Sources/AppKit/CanvasView.swift`, add near `committedSignature` (after line ~22):

```swift
    /// Global outline/halo render toggle. Settable so production injects the
    /// UserDefaults adapter; defaults off so existing tests are unaffected.
    public var outlineSettings: OutlineSettings = DefaultOutlineSettings()
    private var bakedOutline = false
```

Add a `refresh()` method near `render(_:)`:

```swift
    /// Re-render the last frame. Call after the outline toggle changes so the
    /// bake rebuilds under the new mode.
    public func refresh() {
        if let frame = lastFrame { render(frame) }
    }
```

In `render(_:)`, read the flag once and add it to the rebuild condition + store it. Change the existing
`if signature != committedSignature || resolvedScale != backingScale || liftedChanged {`
to include `|| outlineSettings.outlineEnabled != bakedOutline`, and inside that block, after
`committedSignature = signature`, add `bakedOutline = outlineSettings.outlineEnabled`.

- [ ] **Step 4: Thread the flag into the draw paths**

In `bakeCommitted(_:baked:)`, change `compositeGroups(groups, in: ctx)` to
`compositeGroups(groups, in: ctx, outline: outlineSettings.outlineEnabled)`.

In `bakeOpaqueUnion(_:members:)`, change the loop's draw to
`drawItem(member.withAlpha(1), in: ctx, isInProgress: false, outline: outlineSettings.outlineEnabled)`.

In `drawLiveGroup(_:frame:in:)`, change `drawItem(live.withAlpha(1), in: ctx, isInProgress: true)` to
`drawItem(live.withAlpha(1), in: ctx, isInProgress: true, outline: outlineSettings.outlineEnabled)`.

In `drawLiveText(_:in:)`, change the `drawTextString(...)` call to pass
`outline: outlineSettings.outlineEnabled`.

In `draw(_:)`, the in-flight items loop `for live in frame.liveItems { drawItem(live, in: ctx, isInProgress: false) }`
becomes `drawItem(live, in: ctx, isInProgress: false, outline: outlineSettings.outlineEnabled)`.

- [ ] **Step 5: Run to confirm it passes**

Run: `just test-integration`
Expected: PASS. All existing `CanvasView*` tests still pass (outline defaults off). If `just lint --strict` flags `type_body_length` or `file_length` on CanvasView from the additions, the additions are tiny — recheck; if genuinely over, extract the new `refresh()`/property is not enough, report it (the file was within budget on main).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "$(cat <<'EOF'
AppKit: CanvasView honors the outline toggle (bake, live, lift, snapshot parity)

Reads OutlineSettings, threads the flag into the committed bake, the lifted union,
the live in-progress mark, in-flight items, and live text; re-bakes on toggle.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Preferences checkbox (AppKit)

**Files:**
- Modify: `Sources/AppKit/PreferencesController.swift`
- Modify: `Sources/AppKit/PreferencesWindow.swift`
- Modify: `Sources/App/main.swift` (temporary call-site update so the build passes; Task 9 finalizes the wiring)
- Test: `Tests/AppKitTests/PreferencesControllerTests.swift` (extend + update existing init callers)

The current `PreferencesController.init` is `(launchAtLogin:, fadeSettings:)`. Add `outlineSettings:` and `onOutlineChanged:` (4 params total — under the SwiftLint limit).

- [ ] **Step 1: Write the failing test**

Append a new suite to `Tests/AppKitTests/PreferencesControllerTests.swift` (use the existing `LaunchAtLogin` test double found in that file in place of `<LAL_DOUBLE>`):

```swift
@MainActor
@Suite("PreferencesController outline")
struct PreferencesControllerOutlineTests {
    @Test("checkbox initializes from the store")
    func initializesFromStore() {
        let oc = DefaultOutlineSettings(outlineEnabled: true)
        let c = PreferencesController(launchAtLogin: <LAL_DOUBLE>,
                                      fadeSettings: DefaultFadeSettings(),
                                      outlineSettings: oc,
                                      onOutlineChanged: {})
        #expect(c.testOnly_outlineCheckbox.state == .on)
    }

    @Test("toggling the checkbox writes the store and fires the closure")
    func writesStoreAndFires() {
        let oc = DefaultOutlineSettings(outlineEnabled: false)
        var fired = 0
        let c = PreferencesController(launchAtLogin: <LAL_DOUBLE>,
                                      fadeSettings: DefaultFadeSettings(),
                                      outlineSettings: oc,
                                      onOutlineChanged: { fired += 1 })
        c.testOnly_setOutline(true)
        #expect(oc.outlineEnabled == true)
        #expect(fired == 1)
    }
}
```

Also update EVERY existing `PreferencesController(launchAtLogin:..., fadeSettings:...)` call in the file to add `outlineSettings: DefaultOutlineSettings(), onOutlineChanged: {}`.

- [ ] **Step 2: Run to confirm it fails**

Run: `just test-integration`
Expected: FAIL (init params + test hooks missing).

- [ ] **Step 3: Implement**

In `Sources/AppKit/PreferencesController.swift`, add stored properties near the other `private let` deps:

```swift
    private let outlineSettings: OutlineSettings
    private let onOutlineChanged: () -> Void
    private let outlineCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
```

Change the initializer to:

```swift
    public init(launchAtLogin: LaunchAtLogin, fadeSettings: FadeSettings,
                outlineSettings: OutlineSettings,
                onOutlineChanged: @escaping () -> Void) {
        self.launchAtLogin = launchAtLogin
        self.fadeSettings = fadeSettings
        self.outlineSettings = outlineSettings
        self.onOutlineChanged = onOutlineChanged
        // ... rest of the existing init body unchanged ...
```

In `buildContent()`, after the fade row (`stack.addArrangedSubview(row(label: "Seconds before fade:", ...))`), add:

```swift
        outlineCheckbox.state = outlineSettings.outlineEnabled ? .on : .off
        outlineCheckbox.target = self
        outlineCheckbox.action = #selector(outlineToggled(_:))
        stack.addArrangedSubview(row(label: "Outline:", control: outlineCheckbox))
```

Add the action and test hooks:

```swift
    @objc private func outlineToggled(_ sender: NSButton) {
        outlineSettings.outlineEnabled = (sender.state == .on)
        onOutlineChanged()
    }
```
and in the test-hooks section (place `testOnly_outlineCheckbox` inside the `swiftlint:disable identifier_name` block alongside the other property hooks):
```swift
    internal func testOnly_setOutline(_ on: Bool) {
        outlineCheckbox.state = on ? .on : .off
        outlineToggled(outlineCheckbox)
    }
```
```swift
    internal var testOnly_outlineCheckbox: NSButton { outlineCheckbox }
```

In `Sources/AppKit/PreferencesWindow.swift`, increase the initial content height by ~32 to fit the new row (find the height/rect constant; match the existing value's units).

In `Sources/App/main.swift`, the single `PreferencesController(launchAtLogin:fadeSettings:)` call site will not compile. Update it temporarily so the build passes:
```swift
        preferences = PreferencesController(launchAtLogin: SMAppServiceLaunchAtLogin(),
                                            fadeSettings: fadeSettings,
                                            outlineSettings: UserDefaultsOutlineSettings(),
                                            onOutlineChanged: {})  // TODO(Task 9): shared instance + canvas.refresh()
```

- [ ] **Step 4: Run to confirm it passes**

Run: `just test-integration`
Expected: PASS (new suite + the updated existing suites). `just check` builds Sources/App.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "$(cat <<'EOF'
AppKit: Preferences checkbox for the outline toggle

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Wire it together in main.swift

**Files:**
- Modify: `Sources/App/main.swift`
- Modify: `Sources/App/FitiDevHTTPSurface.swift`

One shared `UserDefaultsOutlineSettings` drives the canvas, Preferences, and dev surface; toggles call `canvas.refresh()`. No new unit test (composition; the AppKit smoke test covers construction).

- [ ] **Step 1: Instantiate and inject in `applicationDidFinishLaunching`**

After `canvas` is created, add:
```swift
        let outlineSettings = UserDefaultsOutlineSettings()
        canvas.outlineSettings = outlineSettings
```
Add a delegate stored property among the others so `maybeStartDevServer()` can share it:
```swift
    var outlineSettings: UserDefaultsOutlineSettings!
```
and assign `self.outlineSettings = outlineSettings`.

Replace the temporary `PreferencesController(...)` from Task 8 with the shared instance + refresh closure:
```swift
        preferences = PreferencesController(launchAtLogin: SMAppServiceLaunchAtLogin(),
                                            fadeSettings: fadeSettings,
                                            outlineSettings: outlineSettings,
                                            onOutlineChanged: { [weak self] in self?.canvas.refresh() })
```

- [ ] **Step 2: Wire the dev surface**

In `Sources/App/FitiDevHTTPSurface.swift`, add the shared settings + refresh closure and the dev-surface members (these become protocol requirements in Task 10):
```swift
    private let outlineSettings: OutlineSettings
    private let onOutlineChanged: () -> Void

    public init(controller: AppController, canvasSize: @escaping () -> Size,
                outlineSettings: OutlineSettings,
                onOutlineChanged: @escaping () -> Void) {
        self.controller = controller
        self.canvasSizeProvider = canvasSize
        self.outlineSettings = outlineSettings
        self.onOutlineChanged = onOutlineChanged
    }

    public var outlineEnabled: Bool { outlineSettings.outlineEnabled }
    public func setOutline(_ enabled: Bool) {
        outlineSettings.outlineEnabled = enabled
        onOutlineChanged()
    }
```
Update `snapshotPNG()` to render with the toggle:
```swift
    public func snapshotPNG() -> Data? {
        let frame = RenderFrame.from(editor: controller.editor, canvasSize: canvasSize)
        return SnapshotRenderer.png(from: frame, outline: outlineSettings.outlineEnabled)
    }
```

In `maybeStartDevServer()` in `main.swift`, update the `FitiDevHTTPSurface(...)` construction:
```swift
        let surface = FitiDevHTTPSurface(controller: controller,
                                         canvasSize: { [weak self] in self?.canvasSize ?? Size(width: 0, height: 0) },
                                         outlineSettings: self.outlineSettings,
                                         onOutlineChanged: { [weak self] in self?.canvas.refresh() })
```

- [ ] **Step 3: Build**

Run: `just check`
Expected: PASS (build + tests + lint).

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "$(cat <<'EOF'
App: wire the outline toggle (canvas, preferences, dev surface)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Dev HTTP route + /state field + justfile recipe

**Files:**
- Modify: `Sources/DevHTTP/DevHTTPSurface.swift` (protocol)
- Modify: `Sources/DevHTTP/DevHTTPServer.swift` (state field + route registration)
- Create: `Sources/DevHTTP/DevHTTPServer+Outline.swift` (route handler, mirroring `DevHTTPServer+Text.swift`)
- Modify: a `FakeSurface` double + a route test under `Tests/DevHTTPTests/`
- Modify: `justfile`

- [ ] **Step 1: Write the failing test**

In the DevHTTP route-test file (match the existing real-server/URLSession idiom used by `Tests/DevHTTPTests/RouteTests/ToolbarRouteTests.swift`), add:

```swift
    @Test("POST /outline toggles the surface and /state reports it")
    func outlineRoute() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0)
        try server.start()
        defer { server.stop() }
        var req = URLRequest(url: URL(string: "http://localhost:\(server.boundPort!)/outline")!)
        req.httpMethod = "POST"
        req.httpBody = Data(#"{"enabled": true}"#.utf8)
        let (_, resp) = try await URLSession.shared.data(for: req)
        #expect((resp as? HTTPURLResponse)?.statusCode == 200)
        #expect(surface.outlineEnabled == true)

        let (sData, _) = try await URLSession.shared.data(
            from: URL(string: "http://localhost:\(server.boundPort!)/state")!)
        let json = try JSONSerialization.jsonObject(with: sData) as? [String: Any]
        #expect(json?["outlineEnabled"] as? Bool == true)
    }
```
Match the exact `DevHTTPServer.start()/stop()/boundPort` API and the test file's helpers as they actually exist; add `outlineEnabled`/`setOutline` to `FakeSurface` (a stored bool + a setter that writes it).

- [ ] **Step 2: Run to confirm it fails**

Run: `just test-integration`
Expected: FAIL (route/protocol members missing).

- [ ] **Step 3: Implement**

In `Sources/DevHTTP/DevHTTPSurface.swift`, add to the protocol (inside `#if DEBUG`):
```swift
    var outlineEnabled: Bool { get }
    func setOutline(_ enabled: Bool)
```

Create `Sources/DevHTTP/DevHTTPServer+Outline.swift` (mirror `DevHTTPServer+Text.swift`):
```swift
// ABOUTME: Dev HTTP route for the global outline toggle: POST /outline {enabled: Bool}.
// ABOUTME: Lives in its own extension to keep DevHTTPServer under the type-body limit.

#if DEBUG
import Foundation

extension DevHTTPServer {
    func installOutlineRoute() {
        router.add("POST", "/outline") { [weak self] req, _ in
            guard let self else { return .notFound() }
            guard let json = try? JSONSerialization.jsonObject(with: req.body) as? [String: Any],
                  let enabled = json["enabled"] as? Bool else {
                return .badRequest("expected {enabled: Bool} body")
            }
            self.surface.setOutline(enabled)
            return .ok()
        }
    }
}
#endif
```
In `Sources/DevHTTP/DevHTTPServer.swift`, call `installOutlineRoute()` from wherever the other `install*Route(s)()` are called (e.g. `installRoutes()`), and add to the `handleState()` payload dictionary:
```swift
            "outlineEnabled": surface.outlineEnabled,
```
Confirm `router` and `surface` have the access level the extension needs (the `+Text` extension is the precedent; match it).

Add `outlineEnabled`/`setOutline` to the `FakeSurface` double.

In `justfile`, add two recipes near the other `inspect-*` recipes (mirror the `inspect-show`/`inspect-hide` style with `{{dev_port}}`):
```make
[group('inspect')]
inspect-outline-on:
    @curl -sf -X POST localhost:{{dev_port}}/outline \
        -H 'Content-Type: application/json' \
        -d '{"enabled":true}'

[group('inspect')]
inspect-outline-off:
    @curl -sf -X POST localhost:{{dev_port}}/outline \
        -H 'Content-Type: application/json' \
        -d '{"enabled":false}'
```

- [ ] **Step 4: Run to confirm it passes**

Run: `just test-integration` then `just --list`
Expected: tests PASS; `inspect-outline-on`/`-off` appear and the justfile parses.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "$(cat <<'EOF'
DevHTTP: POST /outline toggle + outlineEnabled in /state

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Self-review checklist (run after implementing)

- Spec coverage: toggle port (1,2), tuning (3), pure resolver (4), halo rendering on all three mark types (5), bake/snapshot pass-through (6), CanvasView bake+live+invalidation (7), Preferences (8), wiring (9), dev route + /state + justfile (10). Flattening untouched (no bypass task — by design). All covered.
- Type/name consistency: `outlineEnabled`, `OutlineSettings` / `DefaultOutlineSettings` / `UserDefaultsOutlineSettings`, `resolveOutline` / `ResolvedOutline`, `strokeHaloIfNeeded`, `refresh()`, `outlineSettings`, `setOutline`, `onOutlineChanged` used identically across tasks.
- No placeholders: every code step shows complete code; the only `<LAL_DOUBLE>` marker (Task 8) is an explicit instruction to use the existing test double by its real name.
- `just check` green at every commit; never `--no-verify`.
- Tuning constants (`strokeWidthFactor`, `textWidthFactor`, `luminanceThreshold`) are expected to be hand-tuned after the first end-to-end render; the pixel-scan windows in Tasks 5 and 7 assume `strokeWidthFactor = 0.5` and may need their scan ranges (not thresholds) widened if it changes.
