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

    @discardableResult
    func removeItem(withID id: CanvasImageItemID) -> Bool {
        var orderedItems = orderedItems()
        guard let index = orderedItems.firstIndex(where: { $0.id == id }) else {
            return false
        }

        orderedItems.remove(at: index)
        items = normalizedZOrderItems(from: orderedItems)
        return true
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

        return resizeItem(
            withID: id,
            toCenter: CGPoint(
                x: standardizedFrame.midX,
                y: standardizedFrame.midY
            ),
            size: standardizedFrame.size
        )
    }

    @discardableResult
    func resizeItem(
        withID id: CanvasImageItemID,
        toCenter center: CGPoint,
        size: CGSize
    ) -> CanvasImageItem? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }

        return updateItem(withID: id) { item in
            item.center = center
            item.size = size
            return item
        }
    }

    @discardableResult
    // Rotated resize works in item-local axes so the committed center/size update
    // stays shared even when the visible quad is no longer axis-aligned in world space.
    func resizeItem(
        withID id: CanvasImageItemID,
        toLocalFrame localFrame: CGRect
    ) -> CanvasImageItem? {
        let standardizedLocalFrame = localFrame.standardized
        guard
            standardizedLocalFrame.width > 0,
            standardizedLocalFrame.height > 0
        else {
            return nil
        }

        return updateItem(withID: id) { item in
            item.center = item.worldPoint(
                fromLocal: CGPoint(
                    x: standardizedLocalFrame.midX,
                    y: standardizedLocalFrame.midY
                )
            )
            item.size = standardizedLocalFrame.size
            return item
        }
    }

    @discardableResult
    // Crop writes remain centralized in Scene so controller drag previews can
    // stay platform-specific while the committed document geometry stays shared.
    func cropItem(
        withID id: CanvasImageItemID,
        toNormalizedCropRect normalizedCropRect: CanvasImageCropRect
    ) -> CanvasImageItem? {
        updateItem(withID: id) { item in
            let updatedLocalFrame = item.localFrame(forNormalizedCropRect: normalizedCropRect).standardized
            guard
                updatedLocalFrame.width > 0,
                updatedLocalFrame.height > 0
            else {
                return item
            }

            let updatedCenter = item.worldPoint(
                fromLocal: CGPoint(
                    x: updatedLocalFrame.midX,
                    y: updatedLocalFrame.midY
                )
            )
            item.cropRectNormalized = normalizedCropRect
            item.center = updatedCenter
            item.size = updatedLocalFrame.size
            return item
        }
    }

    @discardableResult
    // Rotation writes stay centralized in Scene so controllers only manage draft
    // angles while the persisted presentation state changes in one shared place.
    func rotateItem(
        withID id: CanvasImageItemID,
        to rotationRadians: CGFloat
    ) -> CanvasImageItem? {
        updateItem(withID: id) { item in
            item.rotationRadians = normalizedCanvasAngle(rotationRadians)
            return item
        }
    }

    @discardableResult
    func duplicateItem(
        withID id: CanvasImageItemID,
        offsetInWorld: CGPoint = .zero
    ) -> CanvasImageItem? {
        var orderedItems = orderedItems()
        guard let index = orderedItems.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        let sourceItem = orderedItems[index]
        let duplicatedItem = CanvasImageItem(
            cgImage: sourceItem.cgImage,
            center: CGPoint(
                x: sourceItem.center.x + offsetInWorld.x,
                y: sourceItem.center.y + offsetInWorld.y
            ),
            size: sourceItem.size,
            zIndex: sourceItem.zIndex,
            cropRectNormalized: sourceItem.cropRectNormalized,
            rotationRadians: sourceItem.rotationRadians
        )
        orderedItems.insert(duplicatedItem, at: index + 1)
        items = normalizedZOrderItems(from: orderedItems)
        return item(withID: duplicatedItem.id)
    }

    func canBringItemForward(withID id: CanvasImageItemID) -> Bool {
        guard let index = orderedItems().firstIndex(where: { $0.id == id }) else {
            return false
        }

        return index < (items.count - 1)
    }

    func canSendItemBackward(withID id: CanvasImageItemID) -> Bool {
        guard let index = orderedItems().firstIndex(where: { $0.id == id }) else {
            return false
        }

        return index > 0
    }

    func canBringItemToFront(withID id: CanvasImageItemID) -> Bool {
        canBringItemForward(withID: id)
    }

    func canSendItemToBack(withID id: CanvasImageItemID) -> Bool {
        canSendItemBackward(withID: id)
    }

    @discardableResult
    func bringItemForward(withID id: CanvasImageItemID) -> CanvasImageItem? {
        guard let currentIndex = orderedItems().firstIndex(where: { $0.id == id }) else {
            return nil
        }

        return reorderItem(
            withID: id,
            toOrderedIndex: currentIndex + 1
        )
    }

    @discardableResult
    func sendItemBackward(withID id: CanvasImageItemID) -> CanvasImageItem? {
        guard let currentIndex = orderedItems().firstIndex(where: { $0.id == id }) else {
            return nil
        }

        return reorderItem(
            withID: id,
            toOrderedIndex: currentIndex - 1
        )
    }

    @discardableResult
    func bringItemToFront(withID id: CanvasImageItemID) -> CanvasImageItem? {
        reorderItem(
            withID: id,
            toOrderedIndex: max(items.count - 1, 0)
        )
    }

    @discardableResult
    func sendItemToBack(withID id: CanvasImageItemID) -> CanvasImageItem? {
        reorderItem(
            withID: id,
            toOrderedIndex: 0
        )
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

    private func normalizedZOrderItems(
        from orderedItems: [CanvasImageItem]
    ) -> [CanvasImageItem] {
        orderedItems.enumerated().map { index, item in
            var normalizedItem = item
            normalizedItem.zIndex = CGFloat(index)
            return normalizedItem
        }
    }

    @discardableResult
    private func reorderItem(
        withID id: CanvasImageItemID,
        toOrderedIndex destinationIndex: Int
    ) -> CanvasImageItem? {
        var orderedItems = orderedItems()
        guard let currentIndex = orderedItems.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        let clampedDestinationIndex = min(
            max(destinationIndex, 0),
            max(orderedItems.count - 1, 0)
        )
        guard currentIndex != clampedDestinationIndex else {
            return nil
        }

        let reorderedItem = orderedItems.remove(at: currentIndex)
        orderedItems.insert(reorderedItem, at: clampedDestinationIndex)
        items = normalizedZOrderItems(from: orderedItems)
        return item(withID: id)
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
