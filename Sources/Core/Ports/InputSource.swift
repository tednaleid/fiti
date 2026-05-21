// ABOUTME: Input port. NSEvent-based AppKit adapter conforms; HTTP injection
// ABOUTME: takes the same path by calling AppController directly. The system-wide
// ABOUTME: activation hotkey lives behind HotkeyRegistry, not here.

import Foundation

public protocol InputSource: AnyObject {
    var onPointerDown: ((StrokePoint, PointerModifiers) -> Void)? { get set }
    var onPointerMoved: ((StrokePoint, PointerModifiers) -> Void)? { get set }
    var onPointerUp: ((PointerModifiers) -> Void)? { get set }
    var onDeactivate: (() -> Void)? { get set }
    var onClear: (() -> Void)? { get set }
}
