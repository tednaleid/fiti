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
                handleRadius: Self.handleHitRadius,
                rotateNodeOffset: Self.rotateNodeOffset)
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
        guard let rect = SelectionMath.selectionBounds(strokeIds: selectedStrokeIds,
                                                       strokes: editor.doc.strokes) else {
            selectionBox = nil
            return
        }
        selectionBox = OrientedBox(center: Point(x: rect.x + rect.width / 2,
                                                 y: rect.y + rect.height / 2),
                                   size: Size(width: rect.width, height: rect.height),
                                   rotation: 0)
    }

    func selectionPointerDown(_ point: StrokePoint, modifiers: PointerModifiers) {
        lastSelectionPoint = point
        lastHoverPoint = Point(x: point.x, y: point.y)
        let p = Point(x: point.x, y: point.y)

        if modifiers.command {
            // Cmd = edit the selection set. Click toggles one stroke; drag marquees additively.
            let strokes = orderedStrokes()
            if let hit = SelectionMath.hitTest(point: point, strokes: strokes, tolerance: Self.handleHitRadius) {
                toggle(hit)
                selectionGesture = nil
            } else {
                selectionGesture = .marquee(startPoint: point, additive: true)
            }
            return
        }

        let region = SelectionMath.region(at: p, box: selectionBox,
                                          handleRadius: Self.handleHitRadius,
                                          rotateNodeOffset: Self.rotateNodeOffset)
        switch region {
        case .rotateHandle:
            beginRotate(at: point)            // Task 8
        case .corner(let corner):
            beginResize(corner: corner, at: point)  // Task 8
        case .body:
            beginTranslate(at: point)
        case .outside:
            let strokes = orderedStrokes()
            if let hit = SelectionMath.hitTest(point: point, strokes: strokes, tolerance: Self.handleHitRadius) {
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
            selectionMovedResizeOrRotate(point, gesture: gesture)  // Task 8
        }
    }

    func selectionPointerUp(modifiers: PointerModifiers) {
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
            let hits = SelectionMath.marqueeHit(rect: rect, strokes: orderedStrokes())
            if additive {
                for id in hits { toggle(id) }
            } else {
                selectedStrokeIds = hits
            }
        case .translate, .resize, .rotate:
            let updates = preview.map { (id: $0.key, transform: $0.value) }
            if !updates.isEmpty { _ = editor.transformStrokes(updates) }
            inFlightTransforms = [:]
            if case .rotate = g {
                // keep the oriented box at its rotated angle (don't snap back to upright)
                // selectionBox already holds the final rotated box from the last move
            } else {
                recomputeSelectionBox()
            }
        }
    }

    // MARK: Private helpers

    private func orderedStrokes() -> [Stroke] {
        editor.doc.strokeOrder.compactMap { editor.doc.strokes[$0] }
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
        for id in selectedStrokeIds { if let s = editor.doc.strokes[id] { out[id] = s.transform } }
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

    func selectionMovedResizeOrRotate(_ point: StrokePoint, gesture: SelectionGesture) {
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
                                 snap15: false))  // Shift-snap wired in Task 9 via modifiers
            selectionBox = box
            inFlightTransforms = transforms
        default:
            break
        }
    }
}
