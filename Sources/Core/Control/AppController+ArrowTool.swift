// ABOUTME: Arrow-tool pointer routing. Straight from the first move: tail at down,
// ABOUTME: head rubber-bands to the cursor, commit on up if past the minimum length.

import Foundation

extension AppController {
    func arrowPointerDown(_ point: StrokePoint) {
        guard mode == .activeIdle else { return }
        _ = editor.beginArrow(color: currentColor, width: currentWidth,
                              tail: Point(x: point.x, y: point.y))
        setMode(.activeDrawing)
    }

    func arrowPointerMoved(_ point: StrokePoint) {
        guard mode == .activeDrawing else { return }
        editor.updateArrowHead(to: Point(x: point.x, y: point.y))
    }

    func arrowPointerUp() {
        guard mode == .activeDrawing else { return }
        defer { setMode(.activeIdle) }
        guard let a = editor.currentArrow else { return }
        let dx = a.head.x - a.tail.x, dy = a.head.y - a.tail.y
        if (dx * dx + dy * dy).squareRoot() >= currentWidth * minArrowLengthFactor {
            _ = editor.commitArrow()
        } else {
            editor.cancelArrow()
        }
    }
}
