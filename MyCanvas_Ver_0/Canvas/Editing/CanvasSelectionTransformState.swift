import CoreGraphics
import Foundation

struct CanvasBoardItemGeometry: Equatable {
    let itemID: CanvasItemID
    let center: CGPoint
    let size: CGSize
    let rotationRadians: CGFloat

    init(
        itemID: CanvasItemID,
        center: CGPoint,
        size: CGSize,
        rotationRadians: CGFloat
    ) {
        self.itemID = itemID
        self.center = center
        self.size = size
        self.rotationRadians = normalizedCanvasAngle(rotationRadians)
    }

    init(item: CanvasBoardItem) {
        self.init(
            itemID: item.id,
            center: item.center,
            size: item.size,
            rotationRadians: item.rotationRadians
        )
    }

    var worldBounds: CGRect {
        CanvasQuad(rect: CGRect(
            x: -size.width / 2,
            y: -size.height / 2,
            width: size.width,
            height: size.height
        )).map { localPoint in
            let rotatedPoint = canvasRotatePoint(
                localPoint,
                around: .zero,
                by: rotationRadians
            )
            return CGPoint(
                x: rotatedPoint.x + center.x,
                y: rotatedPoint.y + center.y
            )
        }.boundingRect.standardized
    }
}

struct CanvasSelectionTransformSnapshot: Equatable {
    let primaryItemID: CanvasItemID
    let memberGeometries: [CanvasBoardItemGeometry]
    let selectionBounds: CGRect

    init?(
        scene: CanvasScene,
        interactionState: CanvasInteractionState
    ) {
        let memberItems = interactionState.selectedItemIDs.compactMap { itemID in
            scene.boardItem(withID: itemID)
        }
        guard
            memberItems.isEmpty == false,
            let primaryItemID = interactionState.primarySelectedItemID
        else {
            return nil
        }

        self.init(
            primaryItemID: primaryItemID,
            memberGeometries: memberItems.map(CanvasBoardItemGeometry.init(item:)),
            selectionBounds: Self.selectionBounds(
                for: memberItems.map(CanvasBoardItemGeometry.init(item:))
            )
        )
    }

    init(
        primaryItemID: CanvasItemID,
        memberGeometries: [CanvasBoardItemGeometry],
        selectionBounds: CGRect? = nil
    ) {
        let normalized = normalizeCanvasSelectionState(
            selectedItemIDs: memberGeometries.map(\.itemID),
            primarySelectedItemID: primaryItemID
        )
        self.primaryItemID = normalized.primarySelectedItemID ?? primaryItemID
        self.memberGeometries = normalized.selectedItemIDs.compactMap { itemID in
            memberGeometries.first(where: { $0.itemID == itemID })
        }
        self.selectionBounds = (selectionBounds ?? Self.selectionBounds(
            for: self.memberGeometries
        )).standardized
    }

    var memberItemIDs: [CanvasItemID] {
        memberGeometries.map(\.itemID)
    }

    var selectionCenter: CGPoint {
        CGPoint(
            x: selectionBounds.midX,
            y: selectionBounds.midY
        )
    }

    func proposedBounds(
        forTranslation translation: CGPoint
    ) -> CGRect {
        selectionBounds.offsetBy(
            dx: translation.x,
            dy: translation.y
        ).standardized
    }

    func translatedMemberGeometries(
        by translation: CGPoint
    ) -> [CanvasBoardItemGeometry] {
        memberGeometries.map { geometry in
            CanvasBoardItemGeometry(
                itemID: geometry.itemID,
                center: CGPoint(
                    x: geometry.center.x + translation.x,
                    y: geometry.center.y + translation.y
                ),
                size: geometry.size,
                rotationRadians: geometry.rotationRadians
            )
        }
    }

    func resizedMemberGeometries(
        handleRole: CanvasSelectionHandleRole,
        draggedWorldCorner: CGPoint,
        minimumScale: CGFloat
    ) -> [CanvasBoardItemGeometry]? {
        guard
            let resizeDraft = resizeDraft(
                handleRole: handleRole,
                draggedWorldCorner: draggedWorldCorner,
                minimumScale: minimumScale
            )
        else {
            return nil
        }

        return memberGeometries.map { geometry in
            CanvasBoardItemGeometry(
                itemID: geometry.itemID,
                center: canvasScalePoint(
                    geometry.center,
                    around: resizeDraft.fixedCorner,
                    by: resizeDraft.scale
                ),
                size: CGSize(
                    width: geometry.size.width * resizeDraft.scale,
                    height: geometry.size.height * resizeDraft.scale
                ),
                rotationRadians: geometry.rotationRadians
            )
        }
    }

    func rotatedMemberGeometries(
        by rotationDeltaRadians: CGFloat
    ) -> [CanvasBoardItemGeometry] {
        memberGeometries.map { geometry in
            CanvasBoardItemGeometry(
                itemID: geometry.itemID,
                center: canvasRotatePoint(
                    geometry.center,
                    around: selectionCenter,
                    by: rotationDeltaRadians
                ),
                size: geometry.size,
                rotationRadians: geometry.rotationRadians + rotationDeltaRadians
            )
        }
    }

    static func selectionBounds(
        for geometries: [CanvasBoardItemGeometry]
    ) -> CGRect {
        let bounds = geometries.reduce(into: CGRect.null) { partialResult, geometry in
            partialResult = partialResult.union(
                geometry.worldBounds.standardized
            )
        }
        return bounds.isNull ? .zero : bounds.standardized
    }

    private func resizeDraft(
        handleRole: CanvasSelectionHandleRole,
        draggedWorldCorner: CGPoint,
        minimumScale: CGFloat
    ) -> CanvasSelectionResizeDraft? {
        guard
            selectionBounds.width > 0,
            selectionBounds.height > 0
        else {
            return nil
        }

        let fixedCorner = fixedOppositeCorner(
            for: handleRole,
            in: selectionBounds
        )
        let minimumWidth = selectionBounds.width * minimumScale
        let minimumHeight = selectionBounds.height * minimumScale
        let constrainedCorner = constrainedDraggedCorner(
            draggedWorldCorner,
            for: handleRole,
            oppositeCorner: fixedCorner,
            minimumWidth: minimumWidth,
            minimumHeight: minimumHeight
        )
        let widthScale = abs(constrainedCorner.x - fixedCorner.x) / selectionBounds.width
        let heightScale = abs(constrainedCorner.y - fixedCorner.y) / selectionBounds.height
        let scale = max(widthScale, heightScale, minimumScale)
        guard scale.isFinite else {
            return nil
        }

        return CanvasSelectionResizeDraft(
            fixedCorner: fixedCorner,
            scale: scale
        )
    }

    private func fixedOppositeCorner(
        for handleRole: CanvasSelectionHandleRole,
        in bounds: CGRect
    ) -> CGPoint {
        let standardizedBounds = bounds.standardized
        switch handleRole {
        case .topLeading:
            return CGPoint(
                x: standardizedBounds.maxX,
                y: standardizedBounds.maxY
            )
        case .topTrailing:
            return CGPoint(
                x: standardizedBounds.minX,
                y: standardizedBounds.maxY
            )
        case .bottomLeading:
            return CGPoint(
                x: standardizedBounds.maxX,
                y: standardizedBounds.minY
            )
        case .bottomTrailing:
            return CGPoint(
                x: standardizedBounds.minX,
                y: standardizedBounds.minY
            )
        }
    }

    private func constrainedDraggedCorner(
        _ draggedWorldCorner: CGPoint,
        for handleRole: CanvasSelectionHandleRole,
        oppositeCorner: CGPoint,
        minimumWidth: CGFloat,
        minimumHeight: CGFloat
    ) -> CGPoint {
        switch handleRole {
        case .topLeading:
            return CGPoint(
                x: min(draggedWorldCorner.x, oppositeCorner.x - minimumWidth),
                y: min(draggedWorldCorner.y, oppositeCorner.y - minimumHeight)
            )
        case .topTrailing:
            return CGPoint(
                x: max(draggedWorldCorner.x, oppositeCorner.x + minimumWidth),
                y: min(draggedWorldCorner.y, oppositeCorner.y - minimumHeight)
            )
        case .bottomLeading:
            return CGPoint(
                x: min(draggedWorldCorner.x, oppositeCorner.x - minimumWidth),
                y: max(draggedWorldCorner.y, oppositeCorner.y + minimumHeight)
            )
        case .bottomTrailing:
            return CGPoint(
                x: max(draggedWorldCorner.x, oppositeCorner.x + minimumWidth),
                y: max(draggedWorldCorner.y, oppositeCorner.y + minimumHeight)
            )
        }
    }
}

struct CanvasSelectionDragState: Equatable {
    let snapshot: CanvasSelectionTransformSnapshot
    let dragStartWorldLocation: CGPoint
    var alignmentLock: CanvasAlignmentLockState

    init(
        snapshot: CanvasSelectionTransformSnapshot,
        dragStartWorldLocation: CGPoint,
        alignmentLock: CanvasAlignmentLockState = .none
    ) {
        self.snapshot = snapshot
        self.dragStartWorldLocation = dragStartWorldLocation
        self.alignmentLock = alignmentLock
    }

    func proposedBounds(
        for currentWorldLocation: CGPoint
    ) -> CGRect {
        snapshot.proposedBounds(
            forTranslation: totalTranslation(
                for: currentWorldLocation
            )
        )
    }

    func totalTranslation(
        for currentWorldLocation: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: currentWorldLocation.x - dragStartWorldLocation.x,
            y: currentWorldLocation.y - dragStartWorldLocation.y
        )
    }

    func replacingAlignmentLock(
        _ alignmentLock: CanvasAlignmentLockState
    ) -> CanvasSelectionDragState {
        var updatedState = self
        updatedState.alignmentLock = alignmentLock
        return updatedState
    }
}

struct CanvasSelectionResizeState: Equatable {
    let snapshot: CanvasSelectionTransformSnapshot
    let handleRole: CanvasSelectionHandleRole
    let minimumScale: CGFloat

    func resizedMemberGeometries(
        for draggedWorldCorner: CGPoint
    ) -> [CanvasBoardItemGeometry]? {
        snapshot.resizedMemberGeometries(
            handleRole: handleRole,
            draggedWorldCorner: draggedWorldCorner,
            minimumScale: minimumScale
        )
    }
}

struct CanvasSelectionRotateState: Equatable {
    let snapshot: CanvasSelectionTransformSnapshot
    let rotationOffsetToPointerAngle: CGFloat

    func draftRotationRadians(
        for pointerWorldLocation: CGPoint
    ) -> CGFloat {
        let pointerAngle = canvasAngle(
            from: snapshot.selectionCenter,
            to: pointerWorldLocation
        )
        return normalizedCanvasAngle(
            pointerAngle + rotationOffsetToPointerAngle
        )
    }

    func rotatedMemberGeometries(
        for pointerWorldLocation: CGPoint
    ) -> [CanvasBoardItemGeometry] {
        snapshot.rotatedMemberGeometries(
            by: draftRotationRadians(for: pointerWorldLocation)
        )
    }
}

extension CanvasBoardItem {
    func applyingGeometry(
        _ geometry: CanvasBoardItemGeometry
    ) -> CanvasBoardItem? {
        guard
            id == geometry.itemID,
            geometry.size.width > 0,
            geometry.size.height > 0
        else {
            return nil
        }

        var updatedItem = self
        updatedItem.center = geometry.center
        updatedItem.size = geometry.size
        updatedItem.rotationRadians = geometry.rotationRadians
        return updatedItem
    }
}

private struct CanvasSelectionResizeDraft {
    let fixedCorner: CGPoint
    let scale: CGFloat
}

private func canvasRotatePoint(
    _ point: CGPoint,
    around pivot: CGPoint,
    by radians: CGFloat
) -> CGPoint {
    guard radians != 0 else {
        return point
    }

    let translatedPoint = CGPoint(
        x: point.x - pivot.x,
        y: point.y - pivot.y
    )
    let cosine = cos(radians)
    let sine = sin(radians)
    return CGPoint(
        x: (translatedPoint.x * cosine) - (translatedPoint.y * sine) + pivot.x,
        y: (translatedPoint.x * sine) + (translatedPoint.y * cosine) + pivot.y
    )
}

private func canvasScalePoint(
    _ point: CGPoint,
    around pivot: CGPoint,
    by scale: CGFloat
) -> CGPoint {
    CGPoint(
        x: pivot.x + ((point.x - pivot.x) * scale),
        y: pivot.y + ((point.y - pivot.y) * scale)
    )
}

private func canvasAngle(
    from start: CGPoint,
    to end: CGPoint
) -> CGFloat {
    atan2(end.y - start.y, end.x - start.x)
}
