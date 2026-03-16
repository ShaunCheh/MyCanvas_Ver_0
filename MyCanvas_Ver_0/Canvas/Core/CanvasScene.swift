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
