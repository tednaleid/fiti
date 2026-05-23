// ABOUTME: Selection gesture implementation for AppController — click-to-select,
// ABOUTME: Cmd-click toggle, marquee, and drag-translate routing.

import Foundation

extension AppController {
    /// The cursor the AppKit adapter should render right now. Pure derived state.
    public var currentCursor: CursorSpec? {
        if mode == .inactive { return nil }
        if currentTool == .selection {
            let region = SelectionMath.region(
                at: lastHoverPoint ?? Point(x: .infinity, y: .infinity),
                box: selectionBox,
                handleRadius: SelectionMetrics.handleHitRadius,
                rotateNodeOffset: SelectionMetrics.rotateNodeOffset,
                rotateNodeRadius: SelectionMetrics.rotateNodeHitRadius)
            return .system(cursorFor(region: region, boxRotation: selectionBox?.rotation ?? 0,
                                     dragging: selectionGesture != nil))
        }
        return .brush(color: currentColor, diameter: currentWidth)
    }

    func refreshCursor() {
        let next = currentCursor
        guard lastEmittedCursor != next else { return }
        lastEmittedCursor = next
        onCursorChanged?(next)
    }

    public func pointerHover(_ point: StrokePoint, modifiers: PointerModifiers) {
        lastHoverPoint = Point(x: point.x, y: point.y)
        refreshCursor()
    }

    func recomputeSelectionBox() {
        guard let rect = SelectionMath.selectionBoundsItems(ids: selectedStrokeIds,
                                                            items: editor.doc.items) else {
            selectionBox = nil
            return
        }
        selectionBox = OrientedBox(center: Point(x: rect.x + rect.width / 2,
                                                 y: rect.y + rect.height / 2),
                                   size: Size(width: rect.width, height: rect.height),
                                   rotation: 0)
    }

    func selectionPointerDown(_ point: StrokePoint, modifiers: PointerModifiers) {
        // Starting a gesture flips the cursor (e.g. body open-hand → closed-hand);
        // refresh on every exit since no mouseMoved arrives mid-drag.
        defer { refreshCursor() }
        lastSelectionPoint = point
        lastHoverPoint = Point(x: point.x, y: point.y)
        let p = Point(x: point.x, y: point.y)

        if modifiers.command {
            // Cmd = edit the selection set. Click toggles one item; drag marquees additively.
            if let hit = SelectionMath.hitTestItem(at: p, items: editor.doc.items,
                                                   order: editor.doc.itemOrder,
                                                   tolerance: SelectionMetrics.handleHitRadius) {
                toggle(hit)
                selectionGesture = nil
            } else {
                selectionGesture = .marquee(startPoint: point, additive: true)
            }
            return
        }

        let region = SelectionMath.region(at: p, box: selectionBox,
                                          handleRadius: SelectionMetrics.handleHitRadius,
                                          rotateNodeOffset: SelectionMetrics.rotateNodeOffset,
                                          rotateNodeRadius: SelectionMetrics.rotateNodeHitRadius)
        switch region {
        case .rotateHandle:
            beginRotate(at: point)            // Task 8
        case .corner(let corner):
            beginResize(corner: corner, at: point)  // Task 8
        case .body:
            beginTranslate(at: point)
        case .outside:
            if let hit = SelectionMath.hitTestItem(at: p, items: editor.doc.items,
                                                   order: editor.doc.itemOrder,
                                                   tolerance: SelectionMetrics.handleHitRadius) {
                selectedStrokeIds = [hit]
                beginTranslate(at: point)
            } else {
                selectionGesture = .marquee(startPoint: point, additive: false)
            }
        }
    }

    func selectionPointerMoved(_ point: StrokePoint, modifiers: PointerModifiers) {
        lastSelectionPoint = point
        guard let gesture = selectionGesture else { return }
        switch gesture {
        case .marquee(let startPoint, _):
            marqueeRect = Rect(x: min(startPoint.x, point.x), y: min(startPoint.y, point.y),
                               width: abs(point.x - startPoint.x), height: abs(point.y - startPoint.y))
        case .translate(let startBox, let startTransforms, let startPoint):
            let (box, transforms) = SelectionTransforms.translate(
                startBox: startBox, startTransforms: startTransforms,
                dx: point.x - startPoint.x, dy: point.y - startPoint.y)
            selectionBox = box
            inFlightTransforms = transforms
        case .resize, .rotate:
            selectionMovedResizeOrRotate(point, gesture: gesture, modifiers: modifiers)
        }
    }

    func selectionPointerUp(modifiers: PointerModifiers) {
        // Ending the gesture flips the cursor back (e.g. closed-hand → open-hand).
        defer { refreshCursor() }
        let gesture = selectionGesture
        selectionGesture = nil
        let endPoint = lastSelectionPoint
        lastSelectionPoint = nil
        let preview = inFlightTransforms

        guard let g = gesture else { inFlightTransforms = [:]; return }
        switch g {
        case .marquee(let startPoint, let additive):
            marqueeRect = nil
            inFlightTransforms = [:]
            let end = endPoint ?? startPoint
            let rect = Rect(x: min(startPoint.x, end.x), y: min(startPoint.y, end.y),
                            width: abs(end.x - startPoint.x), height: abs(end.y - startPoint.y))
            let hits = SelectionMath.marqueeHitItems(rect: rect, items: editor.doc.items,
                                                      order: editor.doc.itemOrder)
            if additive {
                for id in hits { toggle(id) }
            } else {
                selectedStrokeIds = hits
            }
        case .translate, .resize, .rotate:
            let updates = preview.map { (id: $0.key, transform: $0.value) }
            if !updates.isEmpty { _ = editor.transformItems(updates) }
            inFlightTransforms = [:]
            // Rotate preserves the box's angle (selectionBox already holds the
            // final rotated box); translate/resize recompute an upright box.
            if case .rotate = g {} else { recomputeSelectionBox() }
        }
        if pendingSelectionClear {
            pendingSelectionClear = false
            clearSelectionState()
        }
    }

    // MARK: Private helpers

    func clearSelectionState() {
        selectedStrokeIds = []
        selectionBox = nil
        inFlightTransforms = [:]
        marqueeRect = nil
        selectionGesture = nil
    }

    private func toggle(_ id: StrokeId) {
        if selectedStrokeIds.contains(id) {
            selectedStrokeIds.removeAll { $0 == id }
        } else {
            selectedStrokeIds.append(id)
        }
    }

    private func beginTranslate(at point: StrokePoint) {
        guard let box = selectionBox else { return }
        selectionGesture = .translate(startBox: box, startTransforms: snapshotTransforms(), startPoint: point)
    }

    func snapshotTransforms() -> [StrokeId: Transform] {
        var out: [StrokeId: Transform] = [:]
        for id in selectedStrokeIds { if let t = editor.doc.items[id]?.transform { out[id] = t } }
        return out
    }

    // MARK: Resize + rotate gesture begin + move

    func beginResize(corner: Corner, at point: StrokePoint) {
        guard let box = selectionBox else { return }
        let cs = box.corners()  // TL, TR, BR, BL
        let oppositeIndex: Int
        switch corner {
        case .topLeft: oppositeIndex = 2
        case .topRight: oppositeIndex = 3
        case .bottomRight: oppositeIndex = 0
        case .bottomLeft: oppositeIndex = 1
        }
        let cornerIndex: Int
        switch corner {
        case .topLeft: cornerIndex = 0
        case .topRight: cornerIndex = 1
        case .bottomRight: cornerIndex = 2
        case .bottomLeft: cornerIndex = 3
        }
        selectionGesture = .resize(startBox: box, startTransforms: snapshotTransforms(),
                                   anchor: cs[oppositeIndex], startCorner: cs[cornerIndex])
    }

    func beginRotate(at point: StrokePoint) {
        guard let box = selectionBox else { return }
        selectionGesture = .rotate(startBox: box, startTransforms: snapshotTransforms(),
                                   center: box.center, startPoint: point)
    }

    func selectionMovedResizeOrRotate(_ point: StrokePoint, gesture: SelectionGesture,
                                      modifiers: PointerModifiers) {
        let p = Point(x: point.x, y: point.y)
        switch gesture {
        case .resize(let startBox, let startTransforms, let anchor, let startCorner):
            let (box, transforms) = SelectionTransforms.resize(
                startBox: startBox, startTransforms: startTransforms,
                drag: ResizeDrag(anchor: anchor, startCorner: startCorner, pointer: p, minFactor: 0.05))
            selectionBox = box
            inFlightTransforms = transforms
        case .rotate(let startBox, let startTransforms, let center, let startPoint):
            let (box, transforms) = SelectionTransforms.rotate(
                startBox: startBox, startTransforms: startTransforms,
                drag: RotateDrag(center: center,
                                 startPointer: Point(x: startPoint.x, y: startPoint.y),
                                 pointer: p,
                                 snap15: modifiers.shift))
            selectionBox = box
            inFlightTransforms = transforms
        default:
            break
        }
    }
}
