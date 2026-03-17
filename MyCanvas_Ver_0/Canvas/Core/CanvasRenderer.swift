import CoreGraphics
import Foundation

struct CanvasRenderer {
    private static let rotateHandleScreenOffset: CGFloat = 28
    private let presentationResolver = CanvasImagePresentationResolver()

    func makeSnapshot(
        scene: CanvasScene,
        boardState: CanvasBoardState? = nil,
        camera: CanvasCamera,
        interactionState: CanvasInteractionState = CanvasInteractionState(),
        inlineEditState: CanvasInlineEditState? = nil,
        rotationPreviewState: CanvasRotationPreviewState? = nil
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
                inlineEditState: inlineEditState,
                rotationPreviewState: rotationPreviewState
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
            inlineEditState: inlineEditState,
            rotationPreviewState: rotationPreviewState
        )

        return CanvasRenderSnapshot(
            viewportBounds: camera.viewportBounds,
            visibleWorldRect: visibleWorldRect,
            boardOverlay: boardOverlay,
            items: renderItems,
            editOverlay: editOverlay
        )
    }

    private func makeEditOverlay(
        scene: CanvasScene,
        camera: CanvasCamera,
        interactionState: CanvasInteractionState,
        inlineEditState: CanvasInlineEditState?,
        rotationPreviewState: CanvasRotationPreviewState?
    ) -> CanvasEditRenderOverlay? {
        if let cropEditOverlay = makeCropEditOverlay(
            scene: scene,
            camera: camera,
            inlineEditState: inlineEditState
        ) {
            return cropEditOverlay
        }

        if let selectionEditOverlay = makeSelectionEditOverlay(
            scene: scene,
            camera: camera,
            interactionState: interactionState,
            inlineEditState: inlineEditState,
            rotationPreviewState: rotationPreviewState
        ) {
            return selectionEditOverlay
        }

        return nil
    }

    private func makeSelectionEditOverlay(
        scene: CanvasScene,
        camera: CanvasCamera,
        interactionState: CanvasInteractionState,
        inlineEditState: CanvasInlineEditState?,
        rotationPreviewState: CanvasRotationPreviewState?
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

        let presentation = presentationResolver.resolve(
            item: selectedItem,
            inlineEditState: inlineEditState,
            rotationPreviewState: rotationPreviewState
        )
        let worldQuad = presentation.visibleWorldQuad
        let screenQuad = camera.worldToViewport(worldQuad)
        let selectionPayload = CanvasEditSelectionOverlayPayload(
            rotateAffordance: makeRotateAffordance(
                for: presentation,
                camera: camera,
                screenQuad: screenQuad
            )
        )

        return CanvasEditRenderOverlay(
            itemID: presentation.itemID,
            kind: .selection,
            activeWorldQuad: worldQuad,
            activeScreenQuad: screenQuad,
            handles: makeCornerEditHandles(for: screenQuad),
            payload: .selection(selectionPayload)
        )
    }

    private func makeCropEditOverlay(
        scene: CanvasScene,
        camera: CanvasCamera,
        inlineEditState: CanvasInlineEditState?
    ) -> CanvasEditRenderOverlay? {
        guard
            let inlineEditState,
            let item = scene.item(withID: inlineEditState.itemID)
        else {
            return nil
        }

        let presentation = presentationResolver.resolve(
            item: item,
            inlineEditState: inlineEditState,
            rotationPreviewState: nil
        )
        let fullImageWorldQuad = presentation.fullImageWorldQuad
        let cropWorldQuad = presentation.visibleWorldQuad
        let fullImageScreenQuad = camera.worldToViewport(fullImageWorldQuad)
        let cropScreenQuad = camera.worldToViewport(cropWorldQuad)

        return CanvasEditRenderOverlay(
            itemID: presentation.itemID,
            kind: .crop,
            activeWorldQuad: cropWorldQuad,
            activeScreenQuad: cropScreenQuad,
            handles: makeCropEditHandles(for: cropScreenQuad),
            payload: .crop(
                CanvasEditCropOverlayPayload(
                    fullImageWorldQuad: fullImageWorldQuad,
                    fullImageScreenQuad: fullImageScreenQuad,
                    cropRectNormalized: presentation.effectiveCropRectNormalized,
                    cropWorldQuad: cropWorldQuad,
                    cropScreenQuad: cropScreenQuad
                )
            )
        )
    }

    private func makeRenderItem(
        for item: CanvasImageItem,
        camera: CanvasCamera,
        inlineEditState: CanvasInlineEditState?,
        rotationPreviewState: CanvasRotationPreviewState?
    ) -> CanvasRenderItem {
        let presentation = presentationResolver.resolve(
            item: item,
            inlineEditState: inlineEditState,
            rotationPreviewState: rotationPreviewState
        )
        let worldQuad = presentation.isCropPreviewActive
            ? presentation.fullImageWorldQuad
            : presentation.visibleWorldQuad
        let renderCenter = presentation.isCropPreviewActive
            ? presentation.fullImageCenter
            : presentation.visibleCenter
        let renderSize = presentation.isCropPreviewActive
            ? presentation.fullImageSize
            : presentation.visibleSize
        let contentsRect = presentation.isCropPreviewActive
            ? CanvasImageCropRect.fullImage.cgRect
            : presentation.effectiveCropRectNormalized.cgRect
        let screenQuad = camera.worldToViewport(worldQuad)
        return CanvasRenderItem(
            id: presentation.itemID,
            screenFrame: screenQuad.boundingRect.standardized,
            screenQuad: screenQuad,
            screenCenter: camera.worldToViewport(renderCenter),
            screenBoundsSize: CGSize(
                width: renderSize.width * camera.zoomScale,
                height: renderSize.height * camera.zoomScale
            ),
            contentsRect: contentsRect,
            rotationRadians: presentation.effectiveRotationRadians,
            cgImage: presentation.cgImage,
            zIndex: presentation.zIndex
        )
    }

    private func makeCornerEditHandles(
        for screenQuad: CanvasQuad
    ) -> [CanvasEditHandleGeometry] {
        makeEditHandles(
            for: screenQuad,
            roles: [
                .topLeading,
                .topTrailing,
                .bottomLeading,
                .bottomTrailing
            ]
        )
    }

    private func makeCropEditHandles(
        for screenQuad: CanvasQuad
    ) -> [CanvasEditHandleGeometry] {
        makeEditHandles(
            for: screenQuad,
            roles: CanvasCropHandleRole.allCases.map(\.editHandleRole)
        )
    }

    private func makeEditHandles(
        for screenQuad: CanvasQuad,
        roles: [CanvasEditHandleRole]
    ) -> [CanvasEditHandleGeometry] {
        let rotationRadians = editHandleRotation(for: screenQuad)
        return roles.map { role in
            CanvasEditHandleGeometry(
                role: role,
                screenCenter: editHandleCenter(for: role, in: screenQuad),
                screenRotationRadians: rotationRadians
            )
        }
    }

    private func editHandleCenter(
        for role: CanvasEditHandleRole,
        in screenQuad: CanvasQuad
    ) -> CGPoint {
        switch role {
        case .topLeading:
            return screenQuad.topLeading
        case .top:
            return screenQuad.topMidpoint
        case .topTrailing:
            return screenQuad.topTrailing
        case .trailing:
            return screenQuad.trailingMidpoint
        case .bottomTrailing:
            return screenQuad.bottomTrailing
        case .bottom:
            return screenQuad.bottomMidpoint
        case .bottomLeading:
            return screenQuad.bottomLeading
        case .leading:
            return screenQuad.leadingMidpoint
        case .rotate:
            assertionFailure("Rotate handle center is derived separately.")
            return screenQuad.topMidpoint
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

    private func makeRotateAffordance(
        for presentation: CanvasImagePresentation,
        camera: CanvasCamera,
        screenQuad: CanvasQuad
    ) -> CanvasEditRotateOverlayPayload {
        let screenCenter = camera.worldToViewport(presentation.visibleCenter)
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
        return CanvasEditRotateOverlayPayload(
            guideScreenStart: guideScreenStart,
            guideScreenEnd: guideScreenEnd,
            handle: CanvasEditHandleGeometry(
                role: .rotate,
                screenCenter: guideScreenEnd,
                screenRotationRadians: rotationRadians
            )
        )
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
