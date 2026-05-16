// ABOUTME: Input port. NSEvent-based AppKit adapter conforms; HTTP injection
// ABOUTME: takes the same path by calling AppController directly.

import Foundation

public protocol InputSource: AnyObject {
    var onPointerDown: ((StrokePoint) -> Void)? { get set }
    var onPointerMoved: ((StrokePoint) -> Void)? { get set }
    var onPointerUp: (() -> Void)? { get set }
    var onActivate: (() -> Void)? { get set }
    var onDeactivate: (() -> Void)? { get set }
    var onClear: (() -> Void)? { get set }
}
