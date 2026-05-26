// ABOUTME: Activation state machine and selection gesture router. Bridges
// ABOUTME: raw pointer input to Editor calls; owns click-through toggling via WindowControl.

import Foundation

@MainActor
public final class AppController { // swiftlint:disable:this type_body_length
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

    var lastInputAt: Double?

    public let editor: Editor
    private let window: WindowControl
    let detector: StationaryDetector
    let clock: Clock
    let ticker: FadeTicker
    let fadeSettings: FadeSettings
    private let stationaryDeadZone: Double = 2.0
    let minArrowLengthFactor: Double = 2.0
    static let fadeRampSeconds: Double = 2.0
    /// Upper bound on stroke/arrow width in points, shared by the size-bump
    /// command, selection resize, and the toolbar slider.
    public static let maxStrokeWidth: Double = 100
    private var lastTimerResetPoint: StrokePoint?

    public private(set) var isRubberBanding: Bool = false

    // MARK: Selection gesture state

    enum SelectionGesture {
        case marquee(startPoint: StrokePoint, additive: Bool)
        case translate(startBox: OrientedBox, startTransforms: [ItemId: Transform], startPoint: StrokePoint)
        case resize(startBox: OrientedBox, startTransforms: [ItemId: Transform], anchor: Point, startCorner: Point)
        case rotate(startBox: OrientedBox, startTransforms: [ItemId: Transform], center: Point, startPoint: StrokePoint)
    }

    var selectionGesture: SelectionGesture?
    var lastSelectionPoint: StrokePoint?

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

    /// The toolbar's frame in canvas coordinates, fed by the AppKit adapter.
    /// When the hover point is inside it, the cursor is a plain arrow and
    /// pointer-downs there start no mark. `nil` when unknown or inactive.
    public var toolbarRegion: Rect? {
        didSet { if oldValue != toolbarRegion { refreshCursor() } }
    }

    // Tool + selection state.
    public var onCurrentToolChanged: ((Tool) -> Void)?

    var pendingSelectionClear = false

    public var currentTool: Tool = .pen {
        didSet {
            guard oldValue != currentTool else { return }
            if currentTool == .pen {
                if selectionGesture != nil {
                    pendingSelectionClear = true   // defer until the gesture's pointerUp
                } else {
                    clearSelectionState()
                }
            }
            onCurrentToolChanged?(currentTool)
            refreshCursor()
        }
    }

    public var onSelectionChanged: (([ItemId]) -> Void)?

    public var selectedItemIds: [ItemId] = [] {
        didSet {
            if oldValue != selectedItemIds {
                recomputeSelectionBox()
                onSelectionChanged?(selectedItemIds)
                refreshCursor()
            }
        }
    }

    public var onInFlightTransformsChanged: (([ItemId: Transform]) -> Void)?

    public var inFlightTransforms: [ItemId: Transform] = [:] {
        didSet { onInFlightTransformsChanged?(inFlightTransforms) }
    }

    public var onMarqueeChanged: ((Rect?) -> Void)?

    public var marqueeRect: Rect? {
        didSet {
            if oldValue != marqueeRect { onMarqueeChanged?(marqueeRect) }
        }
    }

    public var onSelectionBoxChanged: ((OrientedBox?) -> Void)?

    public var selectionBox: OrientedBox? {
        didSet { if oldValue != selectionBox { onSelectionBoxChanged?(selectionBox) } }
    }

    var lastHoverPoint: Point?

    // Cursor publisher. Adapters subscribe to keep the rendered NSCursor in sync
    // with mode + currentColor + currentWidth. `nil` means inactive (system
    // cursor returns). Initial state is nil; refreshCursor() only fires when
    // the derived value diverges, so activeIdle ↔ activeDrawing transitions
    // and writes-while-inactive don't generate spurious events. Subscribers
    // that join after initialization should read `currentCursor` to sync.
    public var onCursorChanged: ((CursorSpec?) -> Void)?
    var lastEmittedCursor: CursorSpec?

    let textMeasurer: TextMeasuring

    public var onTextSessionChanged: ((TextEditSession?) -> Void)?

    public var textSession: TextEditSession? {
        didSet {
            if oldValue != textSession { onTextSessionChanged?(textSession) }
        }
    }

    public var isEditingText: Bool { textSession != nil }

    public init(
        editor: Editor,
        window: WindowControl,
        detector: StationaryDetector,
        clock: Clock,
        ticker: FadeTicker,
        textMeasurer: TextMeasuring,
        fadeSettings: FadeSettings = DefaultFadeSettings()
    ) {
        self.editor = editor
        self.window = window
        self.detector = detector
        self.clock = clock
        self.ticker = ticker
        self.textMeasurer = textMeasurer
        self.fadeSettings = fadeSettings
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

    // MARK: Public pointer entry points

    /// Record user input: reset the fade timer and restore full opacity. Resetting
    /// opacity here (not just the timer) means a mark drawn mid-fade is immediately
    /// solid instead of inheriting the faded level until the pointer is released.
    private func noteInput() {
        lastInputAt = clock.now()
        fadeOpacity = 1.0
    }

    public func pointerDown(_ point: StrokePoint) {
        pointerDown(point, modifiers: .none)
    }

    public func pointerDown(_ point: StrokePoint, modifiers: PointerModifiers) {
        noteInput()
        guard mode != .inactive else { return }
        if let region = toolbarRegion, region.contains(point) { return }
        switch currentTool {
        case .pen:
            if !selectedItemIds.isEmpty { selectedItemIds = [] }
            penPointerDown(point)
        case .selection:
            selectionPointerDown(point, modifiers: modifiers)
        case .text:
            textPointerDown(point)
        case .arrow:
            if !selectedItemIds.isEmpty { selectedItemIds = [] }
            arrowPointerDown(point)
        }
    }

    public func pointerMoved(_ point: StrokePoint) {
        pointerMoved(point, modifiers: .none)
    }

    public func pointerMoved(_ point: StrokePoint, modifiers: PointerModifiers) {
        noteInput()
        guard mode != .inactive else { return }
        switch currentTool {
        case .pen: penPointerMoved(point)
        case .selection: selectionPointerMoved(point, modifiers: modifiers)
        case .text: break
        case .arrow: arrowPointerMoved(point)
        }
    }

    public func pointerUp() {
        pointerUp(modifiers: .none)
    }

    public func pointerUp(modifiers: PointerModifiers) {
        noteInput()
        guard mode != .inactive else { return }
        if pendingSelectionClear {
            selectionPointerUp(modifiers: modifiers)
            return
        }
        switch currentTool {
        case .pen: penPointerUp()
        case .selection: selectionPointerUp(modifiers: modifiers)
        case .text: break
        case .arrow: arrowPointerUp()
        }
    }

    // MARK: Pen gesture (private)

    private func penPointerDown(_ point: StrokePoint) {
        guard mode == .activeIdle else { return }
        revealDrawingsForNewMark()
        _ = editor.startStroke(color: currentColor, width: currentWidth, pointerType: .mouse)
        editor.appendPoint(point)
        mode = .activeDrawing
        lastTimerResetPoint = point
        detector.arm()
    }

    private func penPointerMoved(_ point: StrokePoint) {
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

    private func penPointerUp() {
        guard mode == .activeDrawing else { return }
        resetStrokeState()
        editor.endStroke()
        mode = .activeIdle
    }

    private func pastDeadZone(_ point: StrokePoint) -> Bool {
        guard let last = lastTimerResetPoint else { return true }
        let dx = point.x - last.x
        let dy = point.y - last.y
        return (dx * dx + dy * dy).squareRoot() > stationaryDeadZone
    }

    private func handleStationary() {
        guard mode == .activeDrawing, !isRubberBanding else { return }
        guard let id = editor.currentStrokeId,
              case .stroke(let stroke)? = editor.doc.items[id] else { return }
        guard isSubstantiallyStraight(points: stroke.points) else { return }
        editor.straightenCurrentStroke()
        isRubberBanding = true
    }

    public func clear() {
        // If a stroke is in progress, end it first so its points are committed
        // before they're cleared (matches the eraseItems / undo invariant that
        // a snapshot of the doc is consistent after every public method returns).
        if mode == .activeDrawing {
            resetStrokeState()
            editor.endStroke()
            mode = .activeIdle
        }
        editor.clear()
        if !selectedItemIds.isEmpty { selectedItemIds = [] }
    }

    private func resetStrokeState() {
        detector.disarm()
        isRubberBanding = false
        lastTimerResetPoint = nil
    }

    // Lets gesture handlers in sibling extension files drive the activeIdle <->
    // activeDrawing transition without widening `mode`'s private(set) setter.
    func setMode(_ newMode: Mode) {
        mode = newMode
    }

    /// Drawing or editing a mark means the user wants to see drawings, so a
    /// pen/arrow stroke or a text pointer-down (new or editing existing text)
    /// while hidden flips drawings back on. Selection and hover never call this,
    /// so `h` stays a deliberate peek-away toggle.
    func revealDrawingsForNewMark() {
        if !drawingsVisible { drawingsVisible = true }
    }

}
