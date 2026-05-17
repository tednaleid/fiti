// ABOUTME: Render port — adapters realize this with CGContext / off-screen contexts / recording.

import Foundation

@MainActor
public protocol Renderer: AnyObject {
    func render(_ frame: RenderFrame)
}
