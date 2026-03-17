import CoreGraphics
import Foundation

struct CanvasRenderer {
    private static let rotateHandleScreenOffset: CGFloat = 28

    func makeSnapshot(
        scene: CanvasScene,
        boardState: CanvasBoardState? = nil,
        camera: CanvasCamera,
        interactionState: CanvasInteractionState = CanvasInteractionState(),
        inlineEditState: CanvasInlineEditState? = nil
    ) -> CanvasRenderSnapshot {
        let visibleWorldRect = camera.visibleWorldRect
        // Avoid turning an invalid zero-sized viewport into point-based culling.
        let visibleItems: [CanvasImageItem]
        if camera.viewportSize.width > 0, camera.viewportSize.height > 0 {
            visibleItems = scene.visibleItems(in: visibleWorldRect)
        } else {
            visibleItems = scene.orderedItems()
        }

        let renderItems = visibleItems.map { item in
            makeRenderItem(
                for: item,
                camera: camera,
                inlineEditState: inlineEditState
            )
        }

        let boardOverlay = boardState.map { boardState in
            CanvasBoardRenderOverlay(
                worldRect: boardState.worldRect,
                screenRect: camera.worldToViewport(boardState.worldRect)
            )
        }

        let editOverlay = makeEditOverlay(
            scene: scene,
            camera: camera,
            interactionState: interactionState,
            inlineEditState: inlineEditState
        )
        let selectionOverlay = makeSelectionOverlay(
            from: editOverlay
        )
        let cropOverlay = makeCropOverlay(
            from: editOverlay
        )
        let rotateOverlay = makeRotateOverlay(
            from: editOverlay
        )

        return CanvasRenderSnapshot(
            viewportBounds: camera.viewportBounds,
            visibleWorldRect: visibleWorldRect,
            boardOverlay: boardOverlay,
            items: renderItems,
            editOverlay: editOverlay,
            selectionOverlay: selectionOverlay,
            cropOverlay: cropOverlay,
            rotateOverlay: rotateOverlay
        )
    }

    private func makeEditOverlay(
        scene: CanvasScene,
        camera: CanvasCamera,
        interactionState: CanvasInteractionState,
        inlineEditState: CanvasInlineEditState?
    ) -> CanvasEditRenderOverlay? {
        if let cropEditOverlay = makeCropEditOverlay(
            scene: scene,
            camera: camera,
            inlineEditState: inlineEditState
        ) {
            return cropEditOverlay
        }

        if let rotateEditOverlay = makeRotateEditOverlay(
            scene: scene,
            camera: camera,
            inlineEditState: inlineEditState
        ) {
            return rotateEditOverlay
        }

        if let selectionEditOverlay = makeSelectionEditOverlay(
            scene: scene,
            camera: camera,
            interactionState: interactionState,
            inlineEditState: inlineEditState
        ) {
            return selectionEditOverlay
        }

        return nil
    }

    private func makeSelectionEditOverlay(
        scene: CanvasScene,
        camera: CanvasCamera,
        interactionState: CanvasInteractionState,
        inlineEditState: CanvasInlineEditState?
    ) -> CanvasEditRenderOverlay? {
        guard inlineEditState == nil else {
            return nil
        }

        guard
            let selectedItemID = interactionState.selectedItemID,
            let selectedItem = scene.item(withID: selectedItemID)
        else {
            return nil
        }

        let worldQuad = selectedItem.worldQuad
        let screenQuad = camera.worldToViewport(worldQuad)

        return CanvasEditRenderOverlay(
            itemID: selectedItemID,
            kind: .selection,
            activeWorldQuad: worldQuad,
            activeScreenQuad: screenQuad,
            cornerHandles: makeEditCornerHandles(for: screenQuad),
            payload: .selection
        )
    }

    private func makeCropEditOverlay(
        scene: CanvasScene,
        camera: CanvasCamera,
        inlineEditState: CanvasInlineEditState?
    ) -> CanvasEditRenderOverlay? {
        guard
            let inlineEditState,
            let cropSession = inlineEditState.cropSession,
            let item = scene.item(withID: inlineEditState.itemID)
        else {
            return nil
        }

        let previewItem = previewedItem(
            for: item,
            inlineEditState: inlineEditState
        )
        let fullImageWorldQuad = previewItem.fullImageWorldQuad
        let cropWorldQuad = previewItem.worldQuad(
            forNormalizedCropRect: cropSession.draftCropRectNormalized
        )
        let fullImageScreenQuad = camera.worldToViewport(fullImageWorldQuad)
        let cropScreenQuad = camera.worldToViewport(cropWorldQuad)

        return CanvasEditRenderOverlay(
            itemID: previewItem.id,
            kind: .crop,
            activeWorldQuad: cropWorldQuad,
            activeScreenQuad: cropScreenQuad,
            cornerHandles: makeEditCornerHandles(for: cropScreenQuad),
            payload: .crop(
                CanvasEditCropOverlayPayload(
                    fullImageWorldQuad: fullImageWorldQuad,
                    fullImageScreenQuad: fullImageScreenQuad,
                    cropRectNormalized: cropSession.draftCropRectNormalized,
                    cropWorldQuad: cropWorldQuad,
                    cropScreenQuad: cropScreenQuad
                )
            )
        )
    }

    private func makeRotateEditOverlay(
        scene: CanvasScene,
        camera: CanvasCamera,
        inlineEditState: CanvasInlineEditState?
    ) -> CanvasEditRenderOverlay? {
        guard
            let inlineEditState,
            inlineEditState.rotateSession != nil,
            let item = scene.item(withID: inlineEditState.itemID)
        else {
            return nil
        }

        let previewItem = previewedItem(
            for: item,
            inlineEditState: inlineEditState
        )
        let worldQuad = previewItem.worldQuad
        let screenQuad = camera.worldToViewport(worldQuad)
        let screenCenter = camera.worldToViewport(previewItem.center)
        let guideScreenStart = screenQuad.topMidpoint
        let outwardDirection = normalizedDirection(
            from: screenCenter,
            to: guideScreenStart
        )
        let guideScreenEnd = CGPoint(
            x: guideScreenStart.x + (outwardDirection.x * Self.rotateHandleScreenOffset),
            y: guideScreenStart.y + (outwardDirection.y * Self.rotateHandleScreenOffset)
        )
        let rotationRadians = editHandleRotation(for: screenQuad)
        return CanvasEditRenderOverlay(
            itemID: previewItem.id,
            kind: .rotate,
            activeWorldQuad: worldQuad,
            activeScreenQuad: screenQuad,
            cornerHandles: makeEditCornerHandles(for: screenQuad),
            payload: .rotate(
                CanvasEditRotateOverlayPayload(
                    guideScreenStart: guideScreenStart,
                    guideScreenEnd: guideScreenEnd,
                    handle: CanvasEditHandleGeometry(
                        role: .rotate,
                        screenCenter: guideScreenEnd,
                        screenRotationRadians: rotationRadians
                    )
                )
            )
        )
    }

    private func makeSelectionOverlay(
        from editOverlay: CanvasEditRenderOverlay?
    ) -> CanvasSelectionRenderOverlay? {
        guard
            let editOverlay,
            editOverlay.kind == .selection
        else {
            return nil
        }

        return CanvasSelectionRenderOverlay(
            itemID: editOverlay.itemID,
            worldFrame: editOverlay.activeWorldQuad.boundingRect.standardized,
            worldQuad: editOverlay.activeWorldQuad,
            screenFrame: editOverlay.activeScreenQuad.boundingRect.standardized,
            screenQuad: editOverlay.activeScreenQuad,
            handles: makeSelectionHandles(from: editOverlay.cornerHandles)
        )
    }

    private func makeRenderItem(
        for item: CanvasImageItem,
        camera: CanvasCamera,
        inlineEditState: CanvasInlineEditState?
    ) -> CanvasRenderItem {
        let previewItem = previewedItem(
            for: item,
            inlineEditState: inlineEditState
        )
        let isEditingCropItem =
            inlineEditState?.mode == .crop &&
            inlineEditState?.itemID == item.id
        let worldQuad = isEditingCropItem
            ? previewItem.fullImageWorldQuad
            : previewItem.worldQuad
        let renderCenter = isEditingCropItem
            ? previewItem.worldPoint(fromLocal: CGPoint(
                x: previewItem.fullImageLocalFrame.midX,
                y: previewItem.fullImageLocalFrame.midY
            ))
            : previewItem.center
        let renderSize = isEditingCropItem
            ? previewItem.fullImageLocalFrame.size
            : previewItem.size
        let contentsRect = isEditingCropItem
            ? CanvasImageCropRect.fullImage.cgRect
            : previewItem.imageContentsRect
        let screenQuad = camera.worldToViewport(worldQuad)
        return CanvasRenderItem(
            id: previewItem.id,
            screenFrame: screenQuad.boundingRect.standardized,
            screenQuad: screenQuad,
            screenCenter: camera.worldToViewport(renderCenter),
            screenBoundsSize: CGSize(
                width: renderSize.width * camera.zoomScale,
                height: renderSize.height * camera.zoomScale
            ),
            contentsRect: contentsRect,
            rotationRadians: previewItem.rotationRadians,
            cgImage: previewItem.cgImage,
            zIndex: previewItem.zIndex
        )
    }

    private func makeCropOverlay(
        from editOverlay: CanvasEditRenderOverlay?
    ) -> CanvasCropRenderOverlay? {
        guard
            let editOverlay,
            editOverlay.kind == .crop,
            case let .crop(payload) = editOverlay.payload
        else {
            return nil
        }

        return CanvasCropRenderOverlay(
            itemID: editOverlay.itemID,
            mode: .crop,
            fullImageWorldQuad: payload.fullImageWorldQuad,
            fullImageScreenQuad: payload.fullImageScreenQuad,
            cropRectNormalized: payload.cropRectNormalized,
            cropWorldQuad: payload.cropWorldQuad,
            cropScreenQuad: payload.cropScreenQuad,
            handles: makeCropHandles(from: editOverlay.cornerHandles)
        )
    }

    private func makeRotateOverlay(
        from editOverlay: CanvasEditRenderOverlay?
    ) -> CanvasRotateRenderOverlay? {
        guard
            let editOverlay,
            editOverlay.kind == .rotate,
            case let .rotate(payload) = editOverlay.payload
        else {
            return nil
        }

        return CanvasRotateRenderOverlay(
            itemID: editOverlay.itemID,
            mode: .rotate,
            worldQuad: editOverlay.activeWorldQuad,
            screenQuad: editOverlay.activeScreenQuad,
            screenCenter: editOverlay.activeScreenQuad.center,
            guideScreenStart: payload.guideScreenStart,
            guideScreenEnd: payload.guideScreenEnd,
            handle: CanvasRotateHandleGeometry(screenCenter: payload.handle.screenCenter)
        )
    }

    private func makeEditCornerHandles(
        for screenQuad: CanvasQuad
    ) -> [CanvasEditHandleGeometry] {
        let rotationRadians = editHandleRotation(for: screenQuad)
        return [
            CanvasEditHandleGeometry(
                role: .topLeading,
                screenCenter: screenQuad.topLeading,
                screenRotationRadians: rotationRadians
            ),
            CanvasEditHandleGeometry(
                role: .topTrailing,
                screenCenter: screenQuad.topTrailing,
                screenRotationRadians: rotationRadians
            ),
            CanvasEditHandleGeometry(
                role: .bottomLeading,
                screenCenter: screenQuad.bottomLeading,
                screenRotationRadians: rotationRadians
            ),
            CanvasEditHandleGeometry(
                role: .bottomTrailing,
                screenCenter: screenQuad.bottomTrailing,
                screenRotationRadians: rotationRadians
            )
        ]
    }

    private func makeSelectionHandles(
        from cornerHandles: [CanvasEditHandleGeometry]
    ) -> [CanvasSelectionHandleGeometry] {
        CanvasSelectionHandleRole.allCases.compactMap { role in
            guard
                let handle = cornerHandles.first(where: {
                    $0.role == editHandleRole(for: role)
                })
            else {
                return nil
            }

            return CanvasSelectionHandleGeometry(
                role: role,
                screenCenter: handle.screenCenter
            )
        }
    }

    private func makeCropHandles(
        from cornerHandles: [CanvasEditHandleGeometry]
    ) -> [CanvasCropHandleGeometry] {
        CanvasCropHandleRole.allCases.compactMap { role in
            guard
                let handle = cornerHandles.first(where: {
                    $0.role == editHandleRole(for: role)
                })
            else {
                return nil
            }

            return CanvasCropHandleGeometry(
                role: role,
                screenCenter: handle.screenCenter
            )
        }
    }

    private func editHandleRotation(
        for screenQuad: CanvasQuad
    ) -> CGFloat {
        normalizedCanvasAngle(
            atan2(
                screenQuad.topTrailing.y - screenQuad.topLeading.y,
                screenQuad.topTrailing.x - screenQuad.topLeading.x
            )
        )
    }

    private func editHandleRole(
        for role: CanvasSelectionHandleRole
    ) -> CanvasEditHandleRole {
        switch role {
        case .topLeading:
            return .topLeading
        case .topTrailing:
            return .topTrailing
        case .bottomLeading:
            return .bottomLeading
        case .bottomTrailing:
            return .bottomTrailing
        }
    }

    private func editHandleRole(
        for role: CanvasCropHandleRole
    ) -> CanvasEditHandleRole {
        switch role {
        case .topLeading:
            return .topLeading
        case .topTrailing:
            return .topTrailing
        case .bottomLeading:
            return .bottomLeading
        case .bottomTrailing:
            return .bottomTrailing
        }
    }

    private func cropHandleCenter(
        for role: CanvasCropHandleRole,
        in screenQuad: CanvasQuad
    ) -> CGPoint {
        switch role {
        case .topLeading:
            return screenQuad.topLeading
        case .topTrailing:
            return screenQuad.topTrailing
        case .bottomLeading:
            return screenQuad.bottomLeading
        case .bottomTrailing:
            return screenQuad.bottomTrailing
        }
    }

    private func previewedItem(
        for item: CanvasImageItem,
        inlineEditState: CanvasInlineEditState?
    ) -> CanvasImageItem {
        guard
            let inlineEditState,
            inlineEditState.itemID == item.id
        else {
            return item
        }

        var previewItem = item
        switch inlineEditState.session {
        case .crop:
            return previewItem
        case let .rotate(rotateSession):
            previewItem.rotationRadians = rotateSession.draftRotationRadians
            return previewItem
        }
    }

    private func normalizedDirection(
        from start: CGPoint,
        to end: CGPoint
    ) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0 else {
            return CGPoint(x: 0, y: -1)
        }

        return CGPoint(
            x: dx / length,
            y: dy / length
        )
    }
}
