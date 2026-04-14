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
        removeBoardItems(withIDs: [id]).isEmpty == false
    }

    @discardableResult
    func removeBoardItems(withIDs itemIDs: [CanvasItemID]) -> [CanvasBoardItem] {
        let itemIDSet = Set(itemIDs)
        guard itemIDSet.isEmpty == false else {
            return []
        }

        let orderedItems = orderedBoardItems()
        let removedItems = orderedItems.filter { itemIDSet.contains($0.id) }
        guard removedItems.isEmpty == false else {
            return []
        }

        items = normalizedZOrderItems(
            from: orderedItems.filter { itemIDSet.contains($0.id) == false }
        )
        return removedItems
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
    func updateVideoPoster(
        withID id: CanvasImageItemID,
        posterAsset: CanvasImageAsset,
        posterTimeSeconds: Double
    ) -> CanvasImageItem? {
        var updatedItem: CanvasImageItem?
        updateImageItem(withID: id) { item in
            guard let nextItem = item.updatingVideoPoster(
                posterAsset: posterAsset,
                posterTimeSeconds: posterTimeSeconds
            ) else {
                return
            }

            item = nextItem
            updatedItem = nextItem
        }
        return updatedItem
    }

    @discardableResult
    func updateTextItem(
        withID id: CanvasItemID,
        text: String
    ) -> CanvasTextItem? {
        updateBoardItem(withID: id) { item in
            guard case var .text(textItem) = item else {
                return nil
            }

            textItem.text = text
            item = .text(textItem)
            return textItem
        } ?? nil
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
        duplicateBoardItems(
            withIDs: [id],
            offsetInWorld: offsetInWorld
        ).first
    }

    @discardableResult
    func duplicateBoardItems(
        withIDs itemIDs: [CanvasItemID],
        offsetInWorld: CGPoint = .zero
    ) -> [CanvasBoardItem] {
        let itemIDSet = Set(itemIDs)
        guard itemIDSet.isEmpty == false else {
            return []
        }

        let orderedItems = orderedBoardItems()
        var duplicatedItems: [CanvasBoardItem] = []
        var rebuiltItems: [CanvasBoardItem] = []
        rebuiltItems.reserveCapacity(orderedItems.count * 2)
        duplicatedItems.reserveCapacity(itemIDSet.count)
        var pendingDuplicateRun: [CanvasBoardItem] = []

        func flushPendingDuplicateRun() {
            guard pendingDuplicateRun.isEmpty == false else {
                return
            }

            let duplicatedRun = pendingDuplicateRun.map { sourceItem in
                duplicatedItem(
                    from: sourceItem,
                    offsetInWorld: offsetInWorld
                )
            }
            rebuiltItems.append(contentsOf: duplicatedRun)
            duplicatedItems.append(contentsOf: duplicatedRun)
            pendingDuplicateRun.removeAll(keepingCapacity: true)
        }

        for item in orderedItems {
            rebuiltItems.append(item)
            if itemIDSet.contains(item.id) {
                pendingDuplicateRun.append(item)
            } else {
                flushPendingDuplicateRun()
            }
        }
        flushPendingDuplicateRun()

        guard duplicatedItems.isEmpty == false else {
            return []
        }

        items = normalizedZOrderItems(from: rebuiltItems)
        return duplicatedItems
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
        canBringBoardItemsForward(withIDs: [id])
    }

    func canBringBoardItemsForward(withIDs itemIDs: [CanvasItemID]) -> Bool {
        let itemIDSet = Set(itemIDs)
        guard itemIDSet.isEmpty == false else {
            return false
        }

        let orderedItems = orderedBoardItems()
        guard orderedItems.count > 1 else {
            return false
        }

        for index in stride(from: orderedItems.count - 2, through: 0, by: -1) {
            let currentItemID = orderedItems[index].id
            let nextItemID = orderedItems[index + 1].id
            guard itemIDSet.contains(currentItemID) else {
                continue
            }

            if itemIDSet.contains(nextItemID) == false {
                return true
            }
        }

        return false
    }

    func canSendItemBackward(withID id: CanvasImageItemID) -> Bool {
        canSendBoardItemsBackward(withIDs: [id])
    }

    func canSendBoardItemsBackward(withIDs itemIDs: [CanvasItemID]) -> Bool {
        let itemIDSet = Set(itemIDs)
        guard itemIDSet.isEmpty == false else {
            return false
        }

        let orderedItems = orderedBoardItems()
        guard orderedItems.count > 1 else {
            return false
        }

        for index in 1..<orderedItems.count {
            let currentItemID = orderedItems[index].id
            let previousItemID = orderedItems[index - 1].id
            guard itemIDSet.contains(currentItemID) else {
                continue
            }

            if itemIDSet.contains(previousItemID) == false {
                return true
            }
        }

        return false
    }

    func canBringItemToFront(withID id: CanvasImageItemID) -> Bool {
        canBringBoardItemsForward(withIDs: [id])
    }

    func canBringBoardItemsToFront(withIDs itemIDs: [CanvasItemID]) -> Bool {
        canBringBoardItemsForward(withIDs: itemIDs)
    }

    func canSendItemToBack(withID id: CanvasImageItemID) -> Bool {
        canSendBoardItemsBackward(withIDs: [id])
    }

    func canSendBoardItemsToBack(withIDs itemIDs: [CanvasItemID]) -> Bool {
        canSendBoardItemsBackward(withIDs: itemIDs)
    }

    @discardableResult
    func bringBoardItemForward(withID id: CanvasItemID) -> CanvasBoardItem? {
        guard bringBoardItemsForward(withIDs: [id]) else {
            return nil
        }

        return boardItem(withID: id)
    }

    @discardableResult
    func bringBoardItemsForward(withIDs itemIDs: [CanvasItemID]) -> Bool {
        let itemIDSet = Set(itemIDs)
        guard itemIDSet.isEmpty == false else {
            return false
        }

        var orderedItems = orderedBoardItems()
        guard orderedItems.count > 1 else {
            return false
        }

        var didChangeOrder = false
        for index in stride(from: orderedItems.count - 2, through: 0, by: -1) {
            let currentItemID = orderedItems[index].id
            let nextItemID = orderedItems[index + 1].id
            guard itemIDSet.contains(currentItemID) else {
                continue
            }

            guard itemIDSet.contains(nextItemID) == false else {
                continue
            }

            orderedItems.swapAt(index, index + 1)
            didChangeOrder = true
        }

        guard didChangeOrder else {
            return false
        }

        items = normalizedZOrderItems(from: orderedItems)
        return true
    }

    @discardableResult
    func bringItemForward(withID id: CanvasImageItemID) -> CanvasImageItem? {
        bringBoardItemForward(withID: id)?.imageItem
    }

    @discardableResult
    func sendBoardItemBackward(withID id: CanvasItemID) -> CanvasBoardItem? {
        guard sendBoardItemsBackward(withIDs: [id]) else {
            return nil
        }

        return boardItem(withID: id)
    }

    @discardableResult
    func sendBoardItemsBackward(withIDs itemIDs: [CanvasItemID]) -> Bool {
        let itemIDSet = Set(itemIDs)
        guard itemIDSet.isEmpty == false else {
            return false
        }

        var orderedItems = orderedBoardItems()
        guard orderedItems.count > 1 else {
            return false
        }

        var didChangeOrder = false
        for index in 1..<orderedItems.count {
            let currentItemID = orderedItems[index].id
            let previousItemID = orderedItems[index - 1].id
            guard itemIDSet.contains(currentItemID) else {
                continue
            }

            guard itemIDSet.contains(previousItemID) == false else {
                continue
            }

            orderedItems.swapAt(index - 1, index)
            didChangeOrder = true
        }

        guard didChangeOrder else {
            return false
        }

        items = normalizedZOrderItems(from: orderedItems)
        return true
    }

    @discardableResult
    func sendItemBackward(withID id: CanvasImageItemID) -> CanvasImageItem? {
        sendBoardItemBackward(withID: id)?.imageItem
    }

    @discardableResult
    func bringBoardItemToFront(withID id: CanvasItemID) -> CanvasBoardItem? {
        guard bringBoardItemsToFront(withIDs: [id]) else {
            return nil
        }

        return boardItem(withID: id)
    }

    @discardableResult
    func bringBoardItemsToFront(withIDs itemIDs: [CanvasItemID]) -> Bool {
        let itemIDSet = Set(itemIDs)
        guard itemIDSet.isEmpty == false else {
            return false
        }

        let orderedItems = orderedBoardItems()
        let selectedItems = orderedItems.filter { itemIDSet.contains($0.id) }
        guard selectedItems.isEmpty == false else {
            return false
        }

        let reorderedItems =
            orderedItems.filter { itemIDSet.contains($0.id) == false } +
            selectedItems
        guard reorderedItems.map(\.id) != orderedItems.map(\.id) else {
            return false
        }

        items = normalizedZOrderItems(from: reorderedItems)
        return true
    }

    @discardableResult
    func bringItemToFront(withID id: CanvasImageItemID) -> CanvasImageItem? {
        bringBoardItemToFront(withID: id)?.imageItem
    }

    @discardableResult
    func sendBoardItemToBack(withID id: CanvasItemID) -> CanvasBoardItem? {
        guard sendBoardItemsToBack(withIDs: [id]) else {
            return nil
        }

        return boardItem(withID: id)
    }

    @discardableResult
    func sendBoardItemsToBack(withIDs itemIDs: [CanvasItemID]) -> Bool {
        let itemIDSet = Set(itemIDs)
        guard itemIDSet.isEmpty == false else {
            return false
        }

        let orderedItems = orderedBoardItems()
        let selectedItems = orderedItems.filter { itemIDSet.contains($0.id) }
        guard selectedItems.isEmpty == false else {
            return false
        }

        let reorderedItems =
            selectedItems +
            orderedItems.filter { itemIDSet.contains($0.id) == false }
        guard reorderedItems.map(\.id) != orderedItems.map(\.id) else {
            return false
        }

        items = normalizedZOrderItems(from: reorderedItems)
        return true
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

    private func duplicatedItem(
        from sourceItem: CanvasBoardItem,
        offsetInWorld: CGPoint
    ) -> CanvasBoardItem {
        switch sourceItem {
        case let .image(item):
            return .image(item.duplicated(offsetInWorld: offsetInWorld))
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
