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

        let selectionOverlay = makeSelectionOverlay(
            scene: scene,
            camera: camera,
            interactionState: interactionState,
            inlineEditState: inlineEditState
        )
        let cropOverlay = makeCropOverlay(
            scene: scene,
            camera: camera,
            inlineEditState: inlineEditState
        )
        let rotateOverlay = makeRotateOverlay(
            scene: scene,
            camera: camera,
            inlineEditState: inlineEditState
        )
        let editOverlay = makeEditOverlay(
            selectionOverlay: selectionOverlay,
            cropOverlay: cropOverlay,
            rotateOverlay: rotateOverlay
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
        selectionOverlay: CanvasSelectionRenderOverlay?,
        cropOverlay: CanvasCropRenderOverlay?,
        rotateOverlay: CanvasRotateRenderOverlay?
    ) -> CanvasEditRenderOverlay? {
        if let cropOverlay {
            return makeEditOverlay(from: cropOverlay)
        }

        if let rotateOverlay {
            return makeEditOverlay(from: rotateOverlay)
        }

        if let selectionOverlay {
            return makeEditOverlay(from: selectionOverlay)
        }

        return nil
    }

    private func makeEditOverlay(
        from selectionOverlay: CanvasSelectionRenderOverlay
    ) -> CanvasEditRenderOverlay {
        CanvasEditRenderOverlay(
            itemID: selectionOverlay.itemID,
            kind: .selection,
            activeWorldQuad: selectionOverlay.worldQuad,
            activeScreenQuad: selectionOverlay.screenQuad,
            cornerHandles: makeEditCornerHandles(
                from: selectionOverlay.handles,
                in: selectionOverlay.screenQuad
            ),
            payload: .selection
        )
    }

    private func makeEditOverlay(
        from rotateOverlay: CanvasRotateRenderOverlay
    ) -> CanvasEditRenderOverlay {
        let rotationRadians = editHandleRotation(for: rotateOverlay.screenQuad)
        return CanvasEditRenderOverlay(
            itemID: rotateOverlay.itemID,
            kind: .rotate,
            activeWorldQuad: rotateOverlay.worldQuad,
            activeScreenQuad: rotateOverlay.screenQuad,
            cornerHandles: makeEditCornerHandles(for: rotateOverlay.screenQuad),
            payload: .rotate(
                CanvasEditRotateOverlayPayload(
                    guideScreenStart: rotateOverlay.guideScreenStart,
                    guideScreenEnd: rotateOverlay.guideScreenEnd,
                    handle: CanvasEditHandleGeometry(
                        role: .rotate,
                        screenCenter: rotateOverlay.handle.screenCenter,
                        screenRotationRadians: rotationRadians
                    )
                )
            )
        )
    }

    private func makeEditOverlay(
        from cropOverlay: CanvasCropRenderOverlay
    ) -> CanvasEditRenderOverlay {
        CanvasEditRenderOverlay(
            itemID: cropOverlay.itemID,
            kind: .crop,
            activeWorldQuad: cropOverlay.cropWorldQuad,
            activeScreenQuad: cropOverlay.cropScreenQuad,
            cornerHandles: makeEditCornerHandles(
                from: cropOverlay.handles,
                in: cropOverlay.cropScreenQuad
            ),
            payload: .crop(
                CanvasEditCropOverlayPayload(
                    fullImageWorldQuad: cropOverlay.fullImageWorldQuad,
                    fullImageScreenQuad: cropOverlay.fullImageScreenQuad,
                    cropRectNormalized: cropOverlay.cropRectNormalized,
                    cropWorldQuad: cropOverlay.cropWorldQuad,
                    cropScreenQuad: cropOverlay.cropScreenQuad
                )
            )
        )
    }

    // Renderer is the single source of truth for selection geometry so drawing
    // and hit testing stay aligned without consulting platform layer state.
    private func makeSelectionOverlay(
        scene: CanvasScene,
        camera: CanvasCamera,
        interactionState: CanvasInteractionState,
        inlineEditState: CanvasInlineEditState?
    ) -> CanvasSelectionRenderOverlay? {
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
        let worldFrame = worldQuad.boundingRect.standardized
        let screenQuad = camera.worldToViewport(worldQuad)
        let screenFrame = screenQuad.boundingRect.standardized

        return CanvasSelectionRenderOverlay(
            itemID: selectedItemID,
            worldFrame: worldFrame,
            worldQuad: worldQuad,
            screenFrame: screenFrame,
            screenQuad: screenQuad,
            handles: makeSelectionHandles(for: screenQuad)
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
        scene: CanvasScene,
        camera: CanvasCamera,
        inlineEditState: CanvasInlineEditState?
    ) -> CanvasCropRenderOverlay? {
        guard
            let inlineEditState,
            inlineEditState.mode == .crop,
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
            forNormalizedCropRect: inlineEditState.draftCropRectNormalized
        )
        let fullImageScreenQuad = camera.worldToViewport(fullImageWorldQuad)
        let cropScreenQuad = camera.worldToViewport(cropWorldQuad)

        return CanvasCropRenderOverlay(
            itemID: previewItem.id,
            mode: inlineEditState.mode,
            fullImageWorldQuad: fullImageWorldQuad,
            fullImageScreenQuad: fullImageScreenQuad,
            cropRectNormalized: inlineEditState.draftCropRectNormalized,
            cropWorldQuad: cropWorldQuad,
            cropScreenQuad: cropScreenQuad,
            handles: makeCropHandles(for: cropScreenQuad)
        )
    }

    private func makeRotateOverlay(
        scene: CanvasScene,
        camera: CanvasCamera,
        inlineEditState: CanvasInlineEditState?
    ) -> CanvasRotateRenderOverlay? {
        guard
            let inlineEditState,
            inlineEditState.mode == .rotate,
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

        return CanvasRotateRenderOverlay(
            itemID: previewItem.id,
            mode: inlineEditState.mode,
            worldQuad: worldQuad,
            screenQuad: screenQuad,
            screenCenter: screenCenter,
            guideScreenStart: guideScreenStart,
            guideScreenEnd: guideScreenEnd,
            handle: CanvasRotateHandleGeometry(screenCenter: guideScreenEnd)
        )
    }

    private func makeSelectionHandles(for screenQuad: CanvasQuad) -> [CanvasSelectionHandleGeometry] {
        CanvasSelectionHandleRole.allCases.map { role in
            CanvasSelectionHandleGeometry(
                role: role,
                screenCenter: selectionHandleCenter(for: role, in: screenQuad)
            )
        }
    }

    private func makeCropHandles(for screenQuad: CanvasQuad) -> [CanvasCropHandleGeometry] {
        CanvasCropHandleRole.allCases.map { role in
            CanvasCropHandleGeometry(
                role: role,
                screenCenter: cropHandleCenter(for: role, in: screenQuad)
            )
        }
    }

    private func selectionHandleCenter(
        for role: CanvasSelectionHandleRole,
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

    private func makeEditCornerHandles(
        from handles: [CanvasSelectionHandleGeometry],
        in screenQuad: CanvasQuad
    ) -> [CanvasEditHandleGeometry] {
        let rotationRadians = editHandleRotation(for: screenQuad)
        return handles.map { handle in
            CanvasEditHandleGeometry(
                role: editHandleRole(for: handle.role),
                screenCenter: handle.screenCenter,
                screenRotationRadians: rotationRadians
            )
        }
    }

    private func makeEditCornerHandles(
        from handles: [CanvasCropHandleGeometry],
        in screenQuad: CanvasQuad
    ) -> [CanvasEditHandleGeometry] {
        let rotationRadians = editHandleRotation(for: screenQuad)
        return handles.map { handle in
            CanvasEditHandleGeometry(
                role: editHandleRole(for: handle.role),
                screenCenter: handle.screenCenter,
                screenRotationRadians: rotationRadians
            )
        }
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
        switch inlineEditState.mode {
        case .crop:
            return previewItem
        case .rotate:
            previewItem.rotationRadians = inlineEditState.draftRotationRadians
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
