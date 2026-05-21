// ABOUTME: Selection gesture implementation for AppController — click-to-select,
// ABOUTME: Cmd-click toggle, marquee, and drag-translate routing.

import Foundation

extension AppController {
    func selectionPointerDown(_ point: StrokePoint, modifiers: PointerModifiers) {
        lastSelectionPoint = point
        let strokes = editor.doc.strokeOrder.compactMap { editor.doc.strokes[$0] }
        if let hitId = SelectionMath.hitTest(point: point, strokes: strokes, tolerance: 4) {
            if modifiers.command {
                if selectedStrokeIds.contains(hitId) {
                    selectedStrokeIds.removeAll { $0 == hitId }
                } else {
                    selectedStrokeIds.append(hitId)
                }
                selectionGesture = nil
            } else {
                if selectedStrokeIds != [hitId] { selectedStrokeIds = [hitId] }
                var originals: [StrokeId: Transform] = [:]
                for id in selectedStrokeIds {
                    if let s = editor.doc.strokes[id] { originals[id] = s.transform }
                }
                selectionGesture = .translate(startPoint: point, originalTransforms: originals)
            }
        } else {
            selectionGesture = .marquee(startPoint: point)
        }
    }

    func selectionPointerMoved(_ point: StrokePoint, modifiers: PointerModifiers) {
        lastSelectionPoint = point
        guard let gesture = selectionGesture else { return }
        switch gesture {
        case .marquee(let startPoint):
            let rect = Rect(
                x: min(startPoint.x, point.x),
                y: min(startPoint.y, point.y),
                width: abs(point.x - startPoint.x),
                height: abs(point.y - startPoint.y)
            )
            marqueeRect = rect
        case .translate(let startPoint, let originals):
            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y
            var preview: [StrokeId: Transform] = [:]
            for (id, original) in originals {
                preview[id] = Transform(x: original.x + dx, y: original.y + dy,
                                        scale: original.scale, rotate: original.rotate)
            }
            inFlightTransforms = preview
        }
    }

    func selectionPointerUp(modifiers: PointerModifiers) {
        let gesture = selectionGesture
        selectionGesture = nil
        let endPoint = lastSelectionPoint
        lastSelectionPoint = nil
        let preview = inFlightTransforms
        inFlightTransforms = [:]

        guard let g = gesture else { return }
        switch g {
        case .marquee(let startPoint):
            marqueeRect = nil
            let end = endPoint ?? startPoint
            let rect = Rect(
                x: min(startPoint.x, end.x),
                y: min(startPoint.y, end.y),
                width: abs(end.x - startPoint.x),
                height: abs(end.y - startPoint.y)
            )
            let strokes = editor.doc.strokeOrder.compactMap { editor.doc.strokes[$0] }
            selectedStrokeIds = SelectionMath.marqueeHit(rect: rect, strokes: strokes)
        case .translate:
            let updates = preview.map { (id: $0.key, transform: $0.value) }
            if !updates.isEmpty {
                _ = editor.transformStrokes(updates)
            }
        }
    }
}
