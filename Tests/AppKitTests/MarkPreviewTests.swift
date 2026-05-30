// ABOUTME: Tests MarkPreview — the mark snapshot view, used by the toolbar and
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

    /// Vertical span of the red ink in a rendered preview, in pixels of the backing cgImage.
    private struct RedSpan { let min: Int; let max: Int; let height: Int }

    /// `min`/`max` rows containing a red pixel. Returns nil when no red ink is present.
    private func redRows(_ image: NSImage) -> RedSpan? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = cg.width, h = cg.height
        let space = CGColorSpace(name: CGColorSpace.sRGB)!  // swiftlint:disable:this force_unwrapping
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!  // swiftlint:disable:this force_unwrapping
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minY = h, maxY = -1
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                if bytes[i] > 120 && bytes[i + 1] < 90 && bytes[i + 2] < 90 {
                    minY = min(minY, y); maxY = max(maxY, y); break
                }
            }
        }
        return maxY < 0 ? nil : RedSpan(min: minY, max: maxY, height: h)
    }

    @Test("the largest letter's apex reaches near the top edge without clipping")
    func largestLetterApexFillsBand() throws {
        // Size 100's cap-height "A" is centered in the band, so the apex sits a small
        // margin below the top edge. The old box-centered placement floated the line box
        // (with its empty descender gap) up and clipped the apex to the very top row;
        // cap-centering must leave a margin (min > 0) yet still reach near the top (min
        // within the top sliver), proving the full letter height shows.
        let img = try #require(MarkPreview.render(tool: .text,
                                                  color: RGBA(r: 1, g: 0, b: 0, a: 1),
                                                  width: 100, outlineOn: false))
        let rows = try #require(redRows(img))
        #expect(rows.min > 0)                            // apex not clipped at the top
        #expect(rows.min < Int(Double(rows.height) * 0.05))  // ...but reaches near the top
    }

    @Test("canvasSize tracks the width/height constants")
    func canvasSize() {
        #expect(MarkPreview.canvasSize.width == MarkPreview.canvasWidth)
        #expect(MarkPreview.canvasSize.height == MarkPreview.canvasHeight)
        #expect(MarkPreview.canvasSize.width == 60)
    }

    @Test("axis(forY:) maps the top half to size and the bottom half to opacity")
    func axisByHalf() {
        // Non-flipped view: y grows upward, so the visual top is the larger y.
        #expect(MarkPreview.axis(forY: 139, height: 140) == .size)     // top
        #expect(MarkPreview.axis(forY: 71, height: 140) == .size)      // just above midpoint
        #expect(MarkPreview.axis(forY: 70, height: 140) == .size)      // midpoint counts as top
        #expect(MarkPreview.axis(forY: 69, height: 140) == .opacity)   // just below midpoint
        #expect(MarkPreview.axis(forY: 1, height: 140) == .opacity)    // bottom
    }

    @Test("clicking the top half fires onHalfClick(.size), bottom half (.opacity)")
    func halfClickFires() {
        let mp = MarkPreview()
        mp.frame = NSRect(x: 0, y: 0, width: 60, height: 140)
        var picks: [PresetAxis] = []
        mp.onHalfClick = { picks.append($0) }
        mp.testOnly_click(atY: 130)  // top
        mp.testOnly_click(atY: 10)   // bottom
        #expect(picks == [.size, .opacity])
    }
}
