// ABOUTME: Render a RenderFrame to a CGImage / NSImage / PNG via off-screen CGContext.
// ABOUTME: Used by GET /snapshot.png and the toolbar mark preview — same drawing as CanvasView.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum SnapshotRenderer {
    /// Renders the frame to a CGImage (scale× the logical canvas). Shared core for
    /// the PNG and NSImage producers below; identical drawing to CanvasView.
    public static func cgImage(from frame: RenderFrame, scale: CGFloat = 2.0,
                               outline: OutlineFlags = .none) -> CGImage? {
        let width = Int(frame.canvasSize.width * Double(scale))
        let height = Int(frame.canvasSize.height * Double(scale))
        guard width > 0, height > 0 else { return nil }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: 0, y: CGFloat(frame.canvasSize.height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.clear(CGRect(x: 0, y: 0, width: Int(frame.canvasSize.width), height: Int(frame.canvasSize.height)))

        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let groups = LayerPlan.compute(items: frame.items, aabb: { SelectionMath.worldAABB(of: $0) })
        compositeGroups(groups, in: ctx, outline: outline)
        if let inProgress = frame.inProgress { drawItem(inProgress, in: ctx, isInProgress: true, outline: outline) }

        return ctx.makeImage()
    }

    public static func png(from frame: RenderFrame, scale: CGFloat = 2.0,
                           outline: OutlineFlags = .none) -> Data? {
        guard let cgImage = cgImage(from: frame, scale: scale, outline: outline) else { return nil }
        return pngData(from: cgImage)
    }

    /// An NSImage sized in logical points (the cgImage is scale× pixels), so it
    /// draws crisp at the display scale. Used by the toolbar mark preview.
    public static func image(from frame: RenderFrame, scale: CGFloat = 2.0,
                             outline: OutlineFlags = .none) -> NSImage? {
        guard let cg = cgImage(from: frame, scale: scale, outline: outline) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: frame.canvasSize.width,
                                                 height: frame.canvasSize.height))
    }

    private static func pngData(from image: CGImage) -> Data? {
        let buf = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(buf, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return buf as Data
    }
}
