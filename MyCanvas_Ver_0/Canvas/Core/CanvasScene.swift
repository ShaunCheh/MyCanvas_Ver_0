import CoreGraphics
import Foundation

final class CanvasScene {
    private(set) var items: [CanvasImageItem]

    init(items: [CanvasImageItem] = []) {
        self.items = items
    }

    func setItems(_ items: [CanvasImageItem]) {
        self.items = items
    }

    func append(_ item: CanvasImageItem) {
        items.append(item)
    }

    func upsert(_ item: CanvasImageItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    func removeItem(withID id: CanvasImageItemID) {
        items.removeAll(where: { $0.id == id })
    }

    func visibleItems(in worldRect: CGRect) -> [CanvasImageItem] {
        orderedItems(from: items.filter { $0.worldFrame.intersects(worldRect) })
    }

    func orderedItems() -> [CanvasImageItem] {
        orderedItems(from: items)
    }

    private func orderedItems(from items: [CanvasImageItem]) -> [CanvasImageItem] {
        items.sorted { lhs, rhs in
            if lhs.zIndex == rhs.zIndex {
                return lhs.id.uuidString < rhs.id.uuidString
            }

            return lhs.zIndex < rhs.zIndex
        }
    }
}
