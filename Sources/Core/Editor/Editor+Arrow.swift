// ABOUTME: Transient in-progress arrow lifecycle on Editor: begin, update head,
// ABOUTME: commit into the doc, or cancel. Held out of FitiDoc until commit.

import Foundation

extension Editor {
    @discardableResult
    public func beginArrow(color: RGBA, width: Double, tail: Point) -> ItemId {
        let id = ids.newItemId()
        currentArrow = ArrowItem(id: id, color: color, width: width, transform: .identity,
                                 tail: tail, head: tail, createdAt: clock.now())
        emit(.local)
        return id
    }

    public func updateArrowHead(to head: Point) {
        guard var a = currentArrow else { return }
        a.head = head
        currentArrow = a
        emit(.local)
    }

    @discardableResult
    public func commitArrow() -> ItemId? {
        guard let a = currentArrow else { return nil }
        currentArrow = nil
        addItem(.arrow(a))  // appends to itemOrder, pushes deleteItem undo, and emits(.local)
        return a.id
    }

    public func cancelArrow() {
        guard currentArrow != nil else { return }
        currentArrow = nil
        emit(.local)
    }
}
