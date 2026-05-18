# fiti CanvasView Retina-Bake Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the bake CGContext in `Sources/AppKit/CanvasView.swift` render at backing-pixel resolution instead of point resolution, so committed strokes don't soften by 2× on retina displays.

**Architecture:** Single localized change to `CanvasView`. Add a `backingScale: CGFloat` tracked from `window?.backingScaleFactor` (default 1 when no window, e.g. in tests). Multiply the bake `CGContext`'s pixel width/height by `backingScale`, apply a CTM `scaleBy(x: scale, y: scale)` after the existing flip so drawing calls stay in point space, and re-bake when the scale changes (not just when the stroke signature changes). Introduce an internal `testOnly_overrideBackingScale: CGFloat?` so tests can simulate a 2× display without a real screen attached.

**Tech Stack:** Swift 6, AppKit (`NSView`, `CGContext`, `backingScaleFactor`), Swift Testing.

**Why now:** Today the softness is masked because uniform-width `CGPath` strokes have boring edges. The forthcoming perfect-freehand port produces polygon outlines with subtle curvature and tapered ends — those make the 2× upscale visible. Landing this first means perfect-freehand cuts over on a sharp canvas; landing it after would ship a brief "soft strokes" regression.

---

## File structure

**Modify:**
- `Sources/AppKit/CanvasView.swift` — add `backingScale` property, `testOnly_overrideBackingScale` hook; update `render(_:)` to capture scale; update bake-invalidation predicate; update `bakeCommitted(_:exclude:)` to size the context in backing pixels and CTM-scale before drawing.
- `Tests/AppKitTests/CanvasViewBakeTests.swift` — add three new `@Test` cases for retina behavior.

**Create:** none.

---

## Task 1: Retina-aware bake

**Files:**
- Modify: `Sources/AppKit/CanvasView.swift`
- Modify: `Tests/AppKitTests/CanvasViewBakeTests.swift`

- [ ] **Step 1: Read current CanvasView.swift to confirm structure**

Open `Sources/AppKit/CanvasView.swift`. Confirm:
- `lastFrame: RenderFrame?`, `committedImage: CGImage?`, `committedSignature: [StrokeId]` are stored properties near the top
- `render(_:)` (~line 31) checks `signature != committedSignature` and rebakes on mismatch
- `bakeCommitted(_:exclude:)` (~line 64) builds a `CGContext` with `width = Int(frame.canvasSize.width)`, `height = Int(frame.canvasSize.height)` and applies a flip CTM before drawing strokes

If anything in the file has drifted from the above, adjust the steps below to match. The intent is the only thing that must hold: capture scale, re-bake on scale-change, size context in backing pixels, apply CTM scale before drawing.

- [ ] **Step 2: Write the failing tests**

Append to `Tests/AppKitTests/CanvasViewBakeTests.swift` (before the struct's closing brace):

```swift
    @Test("bake CGImage dimensions match canvas points × backingScale (default 1)")
    func bakeDimensionsDefaultScale() throws {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        let stroke = Stroke(id: "a", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 4,
                            transform: .identity,
                            points: [StrokePoint(x: 10, y: 25), StrokePoint(x: 40, y: 25)],
                            pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        view.render(RenderFrame(strokes: [stroke], inProgress: nil,
                                canvasSize: Size(width: 50, height: 50)))
        let image = try #require(view.testOnly_committedImage)
        #expect(image.width == 50)
        #expect(image.height == 50)
    }

    @Test("bake CGImage dimensions scale with backingScale = 2")
    func bakeDimensionsRetina() throws {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        view.testOnly_overrideBackingScale = 2
        let stroke = Stroke(id: "a", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 4,
                            transform: .identity,
                            points: [StrokePoint(x: 10, y: 25), StrokePoint(x: 40, y: 25)],
                            pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        view.render(RenderFrame(strokes: [stroke], inProgress: nil,
                                canvasSize: Size(width: 50, height: 50)))
        let image = try #require(view.testOnly_committedImage)
        #expect(image.width == 100)
        #expect(image.height == 100)
    }

    @Test("changing backingScale invalidates the bake and re-bakes at new resolution")
    func bakeRespondsToScaleChange() throws {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        let stroke = Stroke(id: "a", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 4,
                            transform: .identity,
                            points: [StrokePoint(x: 10, y: 25), StrokePoint(x: 40, y: 25)],
                            pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        let frame = RenderFrame(strokes: [stroke], inProgress: nil,
                                canvasSize: Size(width: 50, height: 50))

        view.testOnly_overrideBackingScale = 1
        view.render(frame)
        let firstImage = try #require(view.testOnly_committedImage)
        #expect(firstImage.width == 50)

        view.testOnly_overrideBackingScale = 2
        view.render(frame)
        let secondImage = try #require(view.testOnly_committedImage)
        #expect(secondImage.width == 100)
    }
```

These three tests require two new internal hooks on `CanvasView`:
- `testOnly_committedImage: CGImage?` — read-only accessor for the bake image (read the existing `committedImage` private storage)
- `testOnly_overrideBackingScale: CGFloat?` — settable override consulted in place of `window?.backingScaleFactor` when set

- [ ] **Step 3: Run integration tests, expect failure**

```
just test-integration
```

Expected: build error — `testOnly_committedImage` and `testOnly_overrideBackingScale` don't exist on `CanvasView`. Confirm before proceeding.

- [ ] **Step 4: Add the stored properties and test hooks to CanvasView**

In `Sources/AppKit/CanvasView.swift`, immediately after the existing `committedSignature` declaration (and before the `drawingsVisible` property), add:

```swift
    private var backingScale: CGFloat = 1

    /// Test-only override for `window?.backingScaleFactor`. When set, replaces
    /// the live window lookup in `render(_:)` so unit tests can simulate a
    /// retina display without needing a real screen attached.
    internal var testOnly_overrideBackingScale: CGFloat?

    internal var testOnly_committedImage: CGImage? { committedImage }
```

- [ ] **Step 5: Update render(_:) to track scale and trigger re-bake on scale change**

Replace the existing `render(_:)` method with:

```swift
    public func render(_ frame: RenderFrame) {
        let inProgressId = frame.inProgress?.id
        let signature = frame.strokes.map(\.id).filter { $0 != inProgressId }
        let resolvedScale = testOnly_overrideBackingScale ?? window?.backingScaleFactor ?? 1
        if signature != committedSignature || resolvedScale != backingScale {
            backingScale = resolvedScale
            committedImage = bakeCommitted(frame, exclude: inProgressId)
            committedSignature = signature
        }
        lastFrame = frame
        needsDisplay = true
    }
```

The two changes vs. today:
- Resolve the scale once at the top, honoring the test override.
- Bake when EITHER the signature OR the scale changed.

- [ ] **Step 6: Update bakeCommitted to size the context in backing pixels and CTM-scale**

Replace the existing `bakeCommitted(_:exclude:)` method with:

```swift
    private func bakeCommitted(_ frame: RenderFrame, exclude: StrokeId?) -> CGImage? {
        let pointWidth = Int(frame.canvasSize.width)
        let pointHeight = Int(frame.canvasSize.height)
        guard pointWidth > 0, pointHeight > 0 else { return nil }
        let pixelWidth = Int((CGFloat(pointWidth) * backingScale).rounded())
        let pixelHeight = Int((CGFloat(pointHeight) * backingScale).rounded())
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        // Order matters: flip first (in pixel space — the CGContext is sized in
        // pixels), then apply the scale CTM so drawStroke can keep using point
        // coordinates as if the context were point-sized.
        ctx.translateBy(x: 0, y: CGFloat(pixelHeight))
        ctx.scaleBy(x: 1, y: -1)
        ctx.scaleBy(x: backingScale, y: backingScale)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for stroke in frame.strokes where stroke.id != exclude {
            drawStroke(stroke, in: ctx)
        }
        return ctx.makeImage()
    }
```

Three changes vs. today:
- Compute `pixelWidth` / `pixelHeight` separately from the point dimensions.
- Pass pixel dimensions to `CGContext(data:width:height:...)`.
- Apply `scaleBy(x: backingScale, y: backingScale)` after the flip so drawing calls stay in point coordinates.

The blit site in `draw(_:)` does NOT change — `CGContext.draw(image:in:)` takes a rect in user space (points), and the higher-resolution bitmap will be sampled correctly by the GPU when mapped into that rect on a matching backing-pixel display.

- [ ] **Step 7: Run integration tests, expect pass**

```
just test-integration
```

Expected: 150 tests pass (147 prior + 3 new). The three pre-existing `CanvasViewBake` tests should also still pass at default scale = 1.

- [ ] **Step 8: Run lint**

```
just lint
```

Expected: 0 violations. The new `testOnly_*` identifiers may trigger `identifier_name` because of the underscore — if so, add a narrow `// swiftlint:disable identifier_name` block around just those declarations (the existing toolbar code uses the same idiom).

- [ ] **Step 9: Run full check**

```
just check
```

Expected: unit + integration + lint + build all green.

- [ ] **Step 10: Commit**

```bash
git add Sources/AppKit/CanvasView.swift Tests/AppKitTests/CanvasViewBakeTests.swift
git commit -m "$(cat <<'EOF'
CanvasView: bake at backing-pixel resolution

The bake CGContext was sized in points, so on retina displays the
committed-stroke cache was rendered at half resolution and softened
2× when blitted back at full point size. Uniform-width CGPath strokes
mostly hid the softness; perfect-freehand's polygon outlines (next on
the roadmap) would have made it obviously fuzzy compared to the live
in-progress stroke.

CanvasView now tracks window?.backingScaleFactor (default 1 when no
window, e.g. in tests), bakes at pixelWidth = points × scale, and
applies a CTM scaleBy so drawStroke keeps using point coordinates.
The bake is invalidated when the scale changes (window moved between
displays of different densities) in addition to stroke-signature
changes.

Internal testOnly_overrideBackingScale and testOnly_committedImage
hooks let unit tests simulate a 2× display without needing a real
screen attached.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Manual smoke

No code changes. Verify the visible effect on actual hardware.

- [ ] **Step 1: Rebuild and launch**

```
just stop && just run-bg
```

- [ ] **Step 2: Activate fiti**

`Opt+F` (or menubar → Activate).

- [ ] **Step 3: Draw three slow, curving strokes**

Slow strokes amplify any softness because there are many segments per stroke.

- [ ] **Step 4: Visually compare live vs. committed**

While drawing, the in-progress stroke renders straight into the view — pixel-sharp. The moment you release the mouse, the stroke commits and the bake takes over. Watch for the "snap from sharp to fuzzy" moment.

Expected after this fix: no visible snap. The released stroke looks identical to the live stroke.

If you still see a snap, something is off — flag it. With uniform-width strokes today the difference is subtle but real if you look closely; after this fix it should be invisible.

- [ ] **Step 5: Verify on an external non-retina monitor (if available)**

Drag the fiti window to an external 1× monitor and draw. Bake should adapt; nothing should look broken.

If you don't have a non-retina monitor handy, skip this step.

---

## Self-review checklist

After both tasks complete:

- [ ] `just check` passes end-to-end
- [ ] The three new bake tests are in `CanvasViewBakeTests.swift` and pass
- [ ] No regressions in the 4 pre-existing bake tests
- [ ] No regressions in the existing `CanvasViewVisibilityTests` (drawingsVisible behavior)
- [ ] `testOnly_*` identifiers are `internal` (not `public`)
- [ ] Manual smoke confirms no live-vs-committed visual snap
- [ ] The roadmap's "two-canvas split — bake uses points, not backing-store pixels" item can now be ticked off — do that in a separate small commit if desired, or fold into the next roadmap update
