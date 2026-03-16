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

    func item(withID id: CanvasImageItemID) -> CanvasImageItem? {
        items.first(where: { $0.id == id })
    }

    func itemWorldQuad(withID id: CanvasImageItemID) -> CanvasQuad? {
        item(withID: id)?.worldQuad
    }

    func itemWorldBounds(withID id: CanvasImageItemID) -> CGRect? {
        item(withID: id)?.worldBounds
    }

    func topmostItem(containing worldPoint: CGPoint) -> CanvasImageItem? {
        orderedItems().reversed().first(where: { $0.contains(worldPoint: worldPoint) })
    }

    func topmostItemID(containing worldPoint: CGPoint) -> CanvasImageItemID? {
        topmostItem(containing: worldPoint)?.id
    }

    func moveItem(withID id: CanvasImageItemID, by deltaInWorld: CGPoint) {
        guard deltaInWorld != .zero else {
            return
        }

        updateItem(withID: id) { item in
            item.center.x += deltaInWorld.x
            item.center.y += deltaInWorld.y
        }
    }

    @discardableResult
    // Controllers own pointer math, but Scene remains the shared mutation entry
    // point for resizing so platform flows write geometry the same way.
    func resizeItem(withID id: CanvasImageItemID, to worldFrame: CGRect) -> CanvasImageItem? {
        let standardizedFrame = worldFrame.standardized
        guard standardizedFrame.width > 0, standardizedFrame.height > 0 else {
            return nil
        }

        return updateItem(withID: id) { item in
            item.center = CGPoint(
                x: standardizedFrame.midX,
                y: standardizedFrame.midY
            )
            item.size = standardizedFrame.size
            return item
        }
    }

    func visibleItems(in worldRect: CGRect) -> [CanvasImageItem] {
        let standardizedWorldRect = worldRect.standardized
        return orderedItems(from: items.filter { item in
            item.worldBounds.intersects(standardizedWorldRect)
        })
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

    @discardableResult
    private func updateItem<T>(
        withID id: CanvasImageItemID,
        _ mutate: (inout CanvasImageItem) -> T
    ) -> T? {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        return mutate(&items[index])
    }
}
