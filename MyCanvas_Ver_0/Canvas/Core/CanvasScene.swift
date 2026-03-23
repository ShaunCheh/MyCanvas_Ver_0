import CoreGraphics
import Foundation

final class CanvasScene {
    private(set) var items: [CanvasBoardItem]

    init(items: [CanvasBoardItem] = []) {
        self.items = items
    }

    func setItems(_ items: [CanvasBoardItem]) {
        self.items = items
    }

    func append(_ item: CanvasBoardItem) {
        items.append(item)
    }

    func append(_ item: CanvasImageItem) {
        append(.image(item))
    }

    func append(_ item: CanvasTextItem) {
        append(.text(item))
    }

    func upsert(_ item: CanvasBoardItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    func upsert(_ item: CanvasImageItem) {
        upsert(.image(item))
    }

    func upsert(_ item: CanvasTextItem) {
        upsert(.text(item))
    }

    @discardableResult
    func removeItem(withID id: CanvasImageItemID) -> Bool {
        var orderedItems = orderedBoardItems()
        guard let index = orderedItems.firstIndex(where: { $0.id == id }) else {
            return false
        }

        orderedItems.remove(at: index)
        items = normalizedZOrderItems(from: orderedItems)
        return true
    }

    func boardItem(withID id: CanvasItemID) -> CanvasBoardItem? {
        items.first(where: { $0.id == id })
    }

    func item(withID id: CanvasImageItemID) -> CanvasImageItem? {
        boardItem(withID: id)?.imageItem
    }

    func textItem(withID id: CanvasItemID) -> CanvasTextItem? {
        boardItem(withID: id)?.textItem
    }

    func itemWorldQuad(withID id: CanvasImageItemID) -> CanvasQuad? {
        boardItem(withID: id)?.worldQuad
    }

    func itemWorldBounds(withID id: CanvasImageItemID) -> CGRect? {
        boardItem(withID: id)?.worldBounds
    }

    func topmostBoardItem(containing worldPoint: CGPoint) -> CanvasBoardItem? {
        orderedBoardItems().reversed().first(where: { $0.contains(worldPoint: worldPoint) })
    }

    func topmostItem(containing worldPoint: CGPoint) -> CanvasImageItem? {
        orderedItems().reversed().first(where: { $0.contains(worldPoint: worldPoint) })
    }

    func topmostBoardItemID(containing worldPoint: CGPoint) -> CanvasItemID? {
        topmostBoardItem(containing: worldPoint)?.id
    }

    func topmostItemID(containing worldPoint: CGPoint) -> CanvasImageItemID? {
        topmostItem(containing: worldPoint)?.id
    }

    func moveItem(withID id: CanvasImageItemID, by deltaInWorld: CGPoint) {
        guard deltaInWorld != .zero else {
            return
        }

        updateBoardItem(withID: id) { item in
            item.center.x += deltaInWorld.x
            item.center.y += deltaInWorld.y
        }
    }

    @discardableResult
    // Controllers own pointer math, but Scene remains the shared mutation entry
    // point for resizing so platform flows write geometry the same way.
    func resizeBoardItem(withID id: CanvasItemID, to worldFrame: CGRect) -> CanvasBoardItem? {
        let standardizedFrame = worldFrame.standardized
        guard standardizedFrame.width > 0, standardizedFrame.height > 0 else {
            return nil
        }

        return resizeBoardItem(
            withID: id,
            toCenter: CGPoint(
                x: standardizedFrame.midX,
                y: standardizedFrame.midY
            ),
            size: standardizedFrame.size
        )
    }

    @discardableResult
    func resizeItem(withID id: CanvasImageItemID, to worldFrame: CGRect) -> CanvasImageItem? {
        resizeBoardItem(withID: id, to: worldFrame)?.imageItem
    }

    @discardableResult
    func resizeBoardItem(
        withID id: CanvasItemID,
        toCenter center: CGPoint,
        size: CGSize
    ) -> CanvasBoardItem? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }

        return updateBoardItem(withID: id) { item in
            item.center = center
            item.size = size
            return item
        }
    }

    @discardableResult
    func resizeItem(
        withID id: CanvasImageItemID,
        toCenter center: CGPoint,
        size: CGSize
    ) -> CanvasImageItem? {
        resizeBoardItem(
            withID: id,
            toCenter: center,
            size: size
        )?.imageItem
    }

    @discardableResult
    // Rotated resize works in item-local axes so the committed center/size update
    // stays shared even when the visible quad is no longer axis-aligned in world space.
    func resizeBoardItem(
        withID id: CanvasItemID,
        toLocalFrame localFrame: CGRect
    ) -> CanvasBoardItem? {
        let standardizedLocalFrame = localFrame.standardized
        guard
            standardizedLocalFrame.width > 0,
            standardizedLocalFrame.height > 0
        else {
            return nil
        }

        return updateBoardItem(withID: id) { item in
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
    func resizeItem(
        withID id: CanvasImageItemID,
        toLocalFrame localFrame: CGRect
    ) -> CanvasImageItem? {
        resizeBoardItem(withID: id, toLocalFrame: localFrame)?.imageItem
    }

    @discardableResult
    // Crop writes remain centralized in Scene so controller drag previews can
    // stay platform-specific while the committed document geometry stays shared.
    func cropItem(
        withID id: CanvasImageItemID,
        toNormalizedCropRect normalizedCropRect: CanvasImageCropRect
    ) -> CanvasImageItem? {
        updateImageItem(withID: id) { item in
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
    func rotateBoardItem(
        withID id: CanvasItemID,
        to rotationRadians: CGFloat
    ) -> CanvasBoardItem? {
        updateBoardItem(withID: id) { item in
            item.rotationRadians = normalizedCanvasAngle(rotationRadians)
            return item
        }
    }

    @discardableResult
    func rotateItem(
        withID id: CanvasImageItemID,
        to rotationRadians: CGFloat
    ) -> CanvasImageItem? {
        rotateBoardItem(withID: id, to: rotationRadians)?.imageItem
    }

    @discardableResult
    func duplicateBoardItem(
        withID id: CanvasItemID,
        offsetInWorld: CGPoint = .zero
    ) -> CanvasBoardItem? {
        var orderedItems = orderedBoardItems()
        guard let index = orderedItems.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        let sourceItem = orderedItems[index]
        let duplicatedItem = duplicatedItem(
            from: sourceItem,
            offsetInWorld: offsetInWorld
        )
        orderedItems.insert(duplicatedItem, at: index + 1)
        items = normalizedZOrderItems(from: orderedItems)
        return boardItem(withID: duplicatedItem.id)
    }

    @discardableResult
    func duplicateItem(
        withID id: CanvasImageItemID,
        offsetInWorld: CGPoint = .zero
    ) -> CanvasImageItem? {
        duplicateBoardItem(
            withID: id,
            offsetInWorld: offsetInWorld
        )?.imageItem
    }

    func canBringItemForward(withID id: CanvasImageItemID) -> Bool {
        guard let index = orderedBoardItems().firstIndex(where: { $0.id == id }) else {
            return false
        }

        return index < (items.count - 1)
    }

    func canSendItemBackward(withID id: CanvasImageItemID) -> Bool {
        guard let index = orderedBoardItems().firstIndex(where: { $0.id == id }) else {
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
    func bringBoardItemForward(withID id: CanvasItemID) -> CanvasBoardItem? {
        guard let currentIndex = orderedBoardItems().firstIndex(where: { $0.id == id }) else {
            return nil
        }

        return reorderBoardItem(
            withID: id,
            toOrderedIndex: currentIndex + 1
        )
    }

    @discardableResult
    func bringItemForward(withID id: CanvasImageItemID) -> CanvasImageItem? {
        bringBoardItemForward(withID: id)?.imageItem
    }

    @discardableResult
    func sendBoardItemBackward(withID id: CanvasItemID) -> CanvasBoardItem? {
        guard let currentIndex = orderedBoardItems().firstIndex(where: { $0.id == id }) else {
            return nil
        }

        return reorderBoardItem(
            withID: id,
            toOrderedIndex: currentIndex - 1
        )
    }

    @discardableResult
    func sendItemBackward(withID id: CanvasImageItemID) -> CanvasImageItem? {
        sendBoardItemBackward(withID: id)?.imageItem
    }

    @discardableResult
    func bringBoardItemToFront(withID id: CanvasItemID) -> CanvasBoardItem? {
        reorderBoardItem(
            withID: id,
            toOrderedIndex: max(items.count - 1, 0)
        )
    }

    @discardableResult
    func bringItemToFront(withID id: CanvasImageItemID) -> CanvasImageItem? {
        bringBoardItemToFront(withID: id)?.imageItem
    }

    @discardableResult
    func sendBoardItemToBack(withID id: CanvasItemID) -> CanvasBoardItem? {
        reorderBoardItem(
            withID: id,
            toOrderedIndex: 0
        )
    }

    @discardableResult
    func sendItemToBack(withID id: CanvasImageItemID) -> CanvasImageItem? {
        sendBoardItemToBack(withID: id)?.imageItem
    }

    func visibleBoardItems(in worldRect: CGRect) -> [CanvasBoardItem] {
        let standardizedWorldRect = worldRect.standardized
        return orderedBoardItems(from: items.filter { item in
            item.worldBounds.intersects(standardizedWorldRect)
        })
    }

    func visibleItems(in worldRect: CGRect) -> [CanvasImageItem] {
        visibleBoardItems(in: worldRect).compactMap(\.imageItem)
    }

    func orderedBoardItems() -> [CanvasBoardItem] {
        orderedBoardItems(from: items)
    }

    func orderedItems() -> [CanvasImageItem] {
        orderedBoardItems().compactMap(\.imageItem)
    }

    private func orderedBoardItems(
        from items: [CanvasBoardItem]
    ) -> [CanvasBoardItem] {
        items.sorted { lhs, rhs in
            if lhs.zIndex == rhs.zIndex {
                return lhs.id.uuidString < rhs.id.uuidString
            }

            return lhs.zIndex < rhs.zIndex
        }
    }

    private func normalizedZOrderItems(
        from orderedItems: [CanvasBoardItem]
    ) -> [CanvasBoardItem] {
        orderedItems.enumerated().map { index, item in
            var normalizedItem = item
            normalizedItem.zIndex = CGFloat(index)
            return normalizedItem
        }
    }

    @discardableResult
    private func reorderBoardItem(
        withID id: CanvasItemID,
        toOrderedIndex destinationIndex: Int
    ) -> CanvasBoardItem? {
        var orderedItems = orderedBoardItems()
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
        return boardItem(withID: id)
    }

    private func duplicatedItem(
        from sourceItem: CanvasBoardItem,
        offsetInWorld: CGPoint
    ) -> CanvasBoardItem {
        switch sourceItem {
        case let .image(item):
            return .image(
                CanvasImageItem(
                    cgImage: item.cgImage,
                    center: CGPoint(
                        x: item.center.x + offsetInWorld.x,
                        y: item.center.y + offsetInWorld.y
                    ),
                    size: item.size,
                    zIndex: item.zIndex,
                    cropRectNormalized: item.cropRectNormalized,
                    rotationRadians: item.rotationRadians
                )
            )
        case let .text(item):
            return .text(
                CanvasTextItem(
                    text: item.text,
                    style: item.style,
                    center: CGPoint(
                        x: item.center.x + offsetInWorld.x,
                        y: item.center.y + offsetInWorld.y
                    ),
                    size: item.size,
                    zIndex: item.zIndex,
                    rotationRadians: item.rotationRadians
                )
            )
        }
    }

    @discardableResult
    private func updateBoardItem<T>(
        withID id: CanvasItemID,
        _ mutate: (inout CanvasBoardItem) -> T
    ) -> T? {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        return mutate(&items[index])
    }

    @discardableResult
    private func updateImageItem<T>(
        withID id: CanvasImageItemID,
        _ mutate: (inout CanvasImageItem) -> T
    ) -> T? {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        guard case var .image(item) = items[index] else {
            return nil
        }

        let result = mutate(&item)
        items[index] = .image(item)
        return result
    }
}
