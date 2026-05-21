// ABOUTME: Activation state machine. Bridges raw pointer input to Editor
// ABOUTME: calls; owns click-through toggling via WindowControl.

import Foundation

@MainActor
public final class AppController {
    public enum Mode: Equatable, Sendable {
        case inactive
        case activeIdle
        case activeDrawing
    }

    public var onModeChanged: ((Mode) -> Void)?

    public private(set) var mode: Mode = .inactive {
        didSet {
            if oldValue != mode {
                onModeChanged?(mode)
                refreshCursor()
            }
        }
    }

    public var onDrawingsVisibilityChanged: ((Bool) -> Void)?
    public var onAutoFadeEnabledChanged: ((Bool) -> Void)?
    public var onFadeOpacityChanged: ((Double) -> Void)?

    public var drawingsVisible: Bool = true {
        didSet {
            if oldValue != drawingsVisible { onDrawingsVisibilityChanged?(drawingsVisible) }
        }
    }

    public var autoFadeEnabled: Bool = false {
        didSet {
            guard oldValue != autoFadeEnabled else { return }
            onAutoFadeEnabledChanged?(autoFadeEnabled)
            autoFadeStateChanged()
        }
    }

    public var fadeOpacity: Double = 1.0 {
        didSet {
            if oldValue != fadeOpacity { onFadeOpacityChanged?(fadeOpacity) }
        }
    }

    private var lastInputAt: Double?

    public let editor: Editor
    private let window: WindowControl
    private let detector: StationaryDetector
    private let clock: Clock
    private let ticker: FadeTicker
    private let stationaryDeadZone: Double = 2.0
    private static let fadeWindowSeconds: Double = 10.0
    private static let fadeRampSeconds: Double = 2.0
    private var lastTimerResetPoint: StrokePoint?

    public private(set) var isRubberBanding: Bool = false

    // Drawing parameters. Each has a didSet publisher so HTTP writes and
    // toolbar-widget writes both notify other adapters that need to react
    // (toolbar widgets, snapshot consumers, etc.).
    public var onCurrentColorChanged: ((RGBA) -> Void)?
    public var onCurrentWidthChanged: ((Double) -> Void)?

    // Default: red #e03131 from the toolbar's quick-pick palette, at 0.8
    // opacity so the slider is immediately discoverable. UserDefaults
    // overrides this when the toolbar reads persisted state at launch.
    public var currentColor: RGBA = RGBA(r: 224.0 / 255.0, g: 49.0 / 255.0, b: 49.0 / 255.0, a: 0.8) {
        didSet {
            if oldValue != currentColor {
                onCurrentColorChanged?(currentColor)
                refreshCursor()
            }
        }
    }
    public var currentWidth: Double = 6 {
        didSet {
            if oldValue != currentWidth {
                onCurrentWidthChanged?(currentWidth)
                refreshCursor()
            }
        }
    }

    // Tool + selection state.
    public var onCurrentToolChanged: ((Tool) -> Void)?

    public var currentTool: Tool = .pen {
        didSet {
            guard oldValue != currentTool else { return }
            onCurrentToolChanged?(currentTool)
            refreshCursor()
        }
    }

    public var onSelectionChanged: (([StrokeId]) -> Void)?

    public var selectedStrokeIds: [StrokeId] = [] {
        didSet {
            if oldValue != selectedStrokeIds {
                onSelectionChanged?(selectedStrokeIds)
            }
        }
    }

    public var onInFlightTransformsChanged: (([StrokeId: Transform]) -> Void)?

    public var inFlightTransforms: [StrokeId: Transform] = [:] {
        didSet { onInFlightTransformsChanged?(inFlightTransforms) }
    }

    // Cursor publisher. Adapters subscribe to keep the rendered NSCursor in sync
    // with mode + currentColor + currentWidth. `nil` means inactive (system
    // cursor returns). Initial state is nil; refreshCursor() only fires when
    // the derived value diverges, so activeIdle ↔ activeDrawing transitions
    // and writes-while-inactive don't generate spurious events. Subscribers
    // that join after initialization should read `currentCursor` to sync.
    public var onCursorChanged: ((CursorSpec?) -> Void)?
    private var lastEmittedCursor: CursorSpec?

    /// The cursor the AppKit adapter should render right now. Pure derived state.
    public var currentCursor: CursorSpec? {
        if mode == .inactive { return nil }
        if currentTool == .selection { return nil }
        return CursorSpec(color: currentColor, diameter: currentWidth)
    }

    private func refreshCursor() {
        let next = currentCursor
        guard lastEmittedCursor != next else { return }
        lastEmittedCursor = next
        onCursorChanged?(next)
    }

    public init(
        editor: Editor,
        window: WindowControl,
        detector: StationaryDetector,
        clock: Clock,
        ticker: FadeTicker
    ) {
        self.editor = editor
        self.window = window
        self.detector = detector
        self.clock = clock
        self.ticker = ticker
        detector.onStationary = { [weak self] in self?.handleStationary() }
        ticker.onTick = { [weak self] now in self?.handleTick(now) }
    }

    public func activate() {
        guard mode == .inactive else { return }
        mode = .activeIdle
        window.setClickThrough(false)
        window.focus()
    }

    public func deactivate() {
        guard mode != .inactive else { return }
        if mode == .activeDrawing {
            resetStrokeState()
            editor.endStroke()
        }
        mode = .inactive
        window.setClickThrough(true)
        window.releaseFocus()
    }

    public func toggle() {
        if mode == .inactive { activate() } else { deactivate() }
    }

    public func pointerDown(_ point: StrokePoint) {
        lastInputAt = clock.now()
        guard mode == .activeIdle else { return }
        _ = editor.startStroke(color: currentColor, width: currentWidth, pointerType: .mouse)
        editor.appendPoint(point)
        mode = .activeDrawing
        lastTimerResetPoint = point
        detector.arm()
    }

    public func pointerMoved(_ point: StrokePoint) {
        lastInputAt = clock.now()
        guard mode == .activeDrawing else { return }
        if isRubberBanding {
            editor.moveCurrentStrokeEndpoint(to: point)
        } else {
            editor.appendPoint(point)
            if pastDeadZone(point) {
                lastTimerResetPoint = point
                detector.arm()
            }
        }
    }

    private func pastDeadZone(_ point: StrokePoint) -> Bool {
        guard let last = lastTimerResetPoint else { return true }
        let dx = point.x - last.x
        let dy = point.y - last.y
        return (dx * dx + dy * dy).squareRoot() > stationaryDeadZone
    }

    public func pointerUp() {
        lastInputAt = clock.now()
        guard mode == .activeDrawing else { return }
        resetStrokeState()
        editor.endStroke()
        mode = .activeIdle
    }

    private func handleStationary() {
        guard mode == .activeDrawing, !isRubberBanding else { return }
        guard let id = editor.currentStrokeId,
              let stroke = editor.doc.strokes[id] else { return }
        guard isSubstantiallyStraight(points: stroke.points) else { return }
        editor.straightenCurrentStroke()
        isRubberBanding = true
    }

    public func clear() {
        // If a stroke is in progress, end it first so its points are committed
        // before they're cleared (matches the eraseStroke / undo invariant that
        // a snapshot of the doc is consistent after every public method returns).
        if mode == .activeDrawing {
            resetStrokeState()
            editor.endStroke()
            mode = .activeIdle
        }
        editor.clear()
    }

    private func resetStrokeState() {
        detector.disarm()
        isRubberBanding = false
        lastTimerResetPoint = nil
    }

    private func autoFadeStateChanged() {
        if autoFadeEnabled {
            lastInputAt = clock.now()
            ticker.start()
        } else {
            ticker.stop()
            fadeOpacity = 1.0
        }
    }

    private func handleTick(_ now: Double) {
        guard autoFadeEnabled else { return }
        guard mode != .activeDrawing else { return }

        if editor.doc.strokes.isEmpty {
            lastInputAt = nil
            fadeOpacity = 1.0
            return
        }

        if lastInputAt == nil {
            lastInputAt = now
            fadeOpacity = 1.0
            return
        }

        let age = now - lastInputAt!
        let rampStart = Self.fadeWindowSeconds - Self.fadeRampSeconds  // 8.0

        if age >= Self.fadeWindowSeconds {
            editor.clear()
            lastInputAt = nil
            fadeOpacity = 1.0
        } else if age >= rampStart {
            fadeOpacity = 1.0 - (age - rampStart) / Self.fadeRampSeconds
        } else {
            fadeOpacity = 1.0
        }
    }

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
            if !selectedStrokeIds.isEmpty {
                _ = editor.eraseStrokes(ids: selectedStrokeIds)
                selectedStrokeIds = []
            } else {
                clear()
            }
        }
    }
}
