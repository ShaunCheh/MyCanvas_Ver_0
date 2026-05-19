import CoreGraphics
import Foundation

struct CanvasRenderer {
    private struct WorkspaceGridSegments {
        let minor: [CanvasWorkspaceGridLineSegment]
        let major: [CanvasWorkspaceGridLineSegment]
    }

    private static let rotateHandleScreenOffset: CGFloat = 28
    private static let rotationInteractionTickStepDegrees: CGFloat = 10
    private static let minimumRotationInteractionRingRadius: CGFloat = 48
    private static let rotationInteractionTickLength: CGFloat = 8
    private static let rotationInteractionTextOffset: CGFloat = 18
    private static let workspaceMinorGridStepWorld: CGFloat = 64
    private static let workspaceMajorGridLineEvery: Int = 4
    private static let workspaceGridIndexEpsilonFactor: CGFloat = 0.0001
    private let presentationResolver = CanvasImagePresentationResolver()

    func makeSnapshot(
        scene: CanvasScene,
        boardState: CanvasBoardState? = nil,
        camera: CanvasCamera,
        interactionState: CanvasInteractionState = CanvasInteractionState(),
        inlineEditState: CanvasInlineEditState? = nil,
        rotationPreviewState: CanvasRotationPreviewState? = nil,
        rotationInteractionState: CanvasRotationInteractionState? = nil,
        alignmentInteractionState: CanvasAlignmentInteractionState? = nil
    ) -> CanvasRenderSnapshot {
        let visibleWorldRect = camera.visibleWorldRect
        // Avoid turning an invalid zero-sized viewport into point-based culling.
        let visibleItems: [CanvasBoardItem]
        if camera.viewportSize.width > 0, camera.viewportSize.height > 0 {
            visibleItems = scene.visibleBoardItems(in: visibleWorldRect)
        } else {
            visibleItems = scene.orderedBoardItems()
        }

        let renderItems = visibleItems.map { item in
            makeRenderItem(
                for: item,
                camera: camera,
                inlineEditState: inlineEditState,
                rotationPreviewState: rotationPreviewState
            )
        }

        let workspaceOverlay: CanvasWorkspaceRenderOverlay?
        if let boardState {
            let boardSurfaceWorldRect = boardState.worldRect.standardized
            let boardSurfaceScreenRect = camera
                .worldToViewport(boardSurfaceWorldRect)
                .standardized
            workspaceOverlay = makeWorkspaceOverlay(
                visibleWorldRect: visibleWorldRect,
                camera: camera,
                viewportBounds: camera.viewportBounds,
                boardSurfaceWorldRect: boardSurfaceWorldRect,
                boardSurfaceScreenRect: boardSurfaceScreenRect
            )
        } else {
            workspaceOverlay = nil
        }

        let editOverlay = makeEditOverlay(
            scene: scene,
            camera: camera,
            interactionState: interactionState,
            inlineEditState: inlineEditState,
            rotationPreviewState: rotationPreviewState
        )
        let selectionHighlights = makeSelectionHighlights(
            scene: scene,
            camera: camera,
            interactionState: interactionState,
            inlineEditState: inlineEditState,
            rotationPreviewState: rotationPreviewState
        )
        let interactionOverlay = makeInteractionOverlay(
            scene: scene,
            camera: camera,
            interactionState: interactionState,
            inlineEditState: inlineEditState,
            rotationPreviewState: rotationPreviewState,
            rotationInteractionState: rotationInteractionState,
            alignmentInteractionState: alignmentInteractionState
        )

        return CanvasRenderSnapshot(
            viewportBounds: camera.viewportBounds,
            visibleWorldRect: visibleWorldRect,
            workspaceOverlay: workspaceOverlay,
            items: renderItems,
            selectionHighlights: selectionHighlights,
            editOverlay: editOverlay,
            interactionOverlay: interactionOverlay
        )
    }

    private func makeWorkspaceOverlay(
        visibleWorldRect: CGRect,
        camera: CanvasCamera,
        viewportBounds: CGRect,
        boardSurfaceWorldRect: CGRect,
        boardSurfaceScreenRect: CGRect
    ) -> CanvasWorkspaceRenderOverlay {
        let gridSegments = makeWorkspaceGridSegments(
            visibleWorldRect: visibleWorldRect,
            camera: camera,
            minorStepWorld: Self.workspaceMinorGridStepWorld,
            majorGridLineEvery: Self.workspaceMajorGridLineEvery
        )
        return CanvasWorkspaceRenderOverlay(
            viewportBounds: viewportBounds,
            boardSurfaceWorldRect: boardSurfaceWorldRect,
            boardSurfaceScreenRect: boardSurfaceScreenRect,
            minorGridStepWorld: Self.workspaceMinorGridStepWorld,
            majorGridLineEvery: Self.workspaceMajorGridLineEvery,
            minorGridSegments: gridSegments.minor,
            majorGridSegments: gridSegments.major
        )
    }

    private func makeWorkspaceGridSegments(
        visibleWorldRect: CGRect,
        camera: CanvasCamera,
        minorStepWorld: CGFloat,
        majorGridLineEvery: Int
    ) -> WorkspaceGridSegments {
        let standardizedVisibleWorldRect = visibleWorldRect.standardized
        let resolvedMinorStepWorld = max(minorStepWorld, 1)
        let resolvedMajorGridLineEvery = max(majorGridLineEvery, 1)
        guard
            standardizedVisibleWorldRect.width > 0,
            standardizedVisibleWorldRect.height > 0
        else {
            return WorkspaceGridSegments(minor: [], major: [])
        }

        // Keep the workspace grid anchored to world-space zero so board auto
        // expansion changes the white surface bounds without rephasing the grid.
        var minorSegments: [CanvasWorkspaceGridLineSegment] = []
        var majorSegments: [CanvasWorkspaceGridLineSegment] = []
        appendVerticalWorkspaceGridSegments(
            visibleWorldRect: standardizedVisibleWorldRect,
            camera: camera,
            minorStepWorld: resolvedMinorStepWorld,
            majorGridLineEvery: resolvedMajorGridLineEvery,
            minorSegments: &minorSegments,
            majorSegments: &majorSegments
        )
        appendHorizontalWorkspaceGridSegments(
            visibleWorldRect: standardizedVisibleWorldRect,
            camera: camera,
            minorStepWorld: resolvedMinorStepWorld,
            majorGridLineEvery: resolvedMajorGridLineEvery,
            minorSegments: &minorSegments,
            majorSegments: &majorSegments
        )
        return WorkspaceGridSegments(
            minor: minorSegments,
            major: majorSegments
        )
    }

    private func appendVerticalWorkspaceGridSegments(
        visibleWorldRect: CGRect,
        camera: CanvasCamera,
        minorStepWorld: CGFloat,
        majorGridLineEvery: Int,
        minorSegments: inout [CanvasWorkspaceGridLineSegment],
        majorSegments: inout [CanvasWorkspaceGridLineSegment]
    ) {
        guard let xIndexRange = workspaceGridIndexRange(
            minimumWorld: visibleWorldRect.minX,
            maximumWorld: visibleWorldRect.maxX,
            stepWorld: minorStepWorld
        ) else {
            return
        }

        for xIndex in xIndexRange {
            let x = CGFloat(xIndex) * minorStepWorld
            let segment = CanvasWorkspaceGridLineSegment(
                start: camera.worldToViewport(
                    CGPoint(x: x, y: visibleWorldRect.minY)
                ),
                end: camera.worldToViewport(
                    CGPoint(x: x, y: visibleWorldRect.maxY)
                )
            )
            if xIndex.isMultiple(of: majorGridLineEvery) {
                majorSegments.append(segment)
            } else {
                minorSegments.append(segment)
            }
        }
    }

    private func appendHorizontalWorkspaceGridSegments(
        visibleWorldRect: CGRect,
        camera: CanvasCamera,
        minorStepWorld: CGFloat,
        majorGridLineEvery: Int,
        minorSegments: inout [CanvasWorkspaceGridLineSegment],
        majorSegments: inout [CanvasWorkspaceGridLineSegment]
    ) {
        guard let yIndexRange = workspaceGridIndexRange(
            minimumWorld: visibleWorldRect.minY,
            maximumWorld: visibleWorldRect.maxY,
            stepWorld: minorStepWorld
        ) else {
            return
        }

        for yIndex in yIndexRange {
            let y = CGFloat(yIndex) * minorStepWorld
            let segment = CanvasWorkspaceGridLineSegment(
                start: camera.worldToViewport(
                    CGPoint(x: visibleWorldRect.minX, y: y)
                ),
                end: camera.worldToViewport(
                    CGPoint(x: visibleWorldRect.maxX, y: y)
                )
            )
            if yIndex.isMultiple(of: majorGridLineEvery) {
                majorSegments.append(segment)
            } else {
                minorSegments.append(segment)
            }
        }
    }

    private func workspaceGridIndexRange(
        minimumWorld: CGFloat,
        maximumWorld: CGFloat,
        stepWorld: CGFloat
    ) -> ClosedRange<Int>? {
        guard stepWorld > 0 else {
            return nil
        }

        let epsilon = stepWorld * Self.workspaceGridIndexEpsilonFactor
        let startIndex = Int(
            ceil((minimumWorld - epsilon) / stepWorld)
        )
        let endIndex = Int(
            floor((maximumWorld + epsilon) / stepWorld)
        )
        guard startIndex <= endIndex else {
            return nil
        }

        return startIndex...endIndex
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

        let selectedItems = selectedOverlayItems(
            scene: scene,
            interactionState: interactionState,
            rotationPreviewState: rotationPreviewState
        )
        guard
            let primarySelectedItemID = interactionState.primarySelectedItemID,
            selectedItems.isEmpty == false
        else {
            return nil
        }
        let resolvedPrimarySelectedItemID =
            selectedItems.contains(where: { $0.id == primarySelectedItemID })
            ? primarySelectedItemID
            : selectedItems.last?.id ?? primarySelectedItemID

        let subject: CanvasEditSelectionOverlaySubject
        let worldQuad: CanvasQuad
        let screenQuad: CanvasQuad
        let screenCenter: CGPoint
        let selectionHandles: [CanvasEditHandleGeometry]
        if selectedItems.count == 1,
           let effectiveItem = selectedItems.first
        {
            subject = .singleItem(itemID: effectiveItem.id)
            worldQuad = effectiveItem.worldQuad
            screenQuad = camera.worldToViewport(worldQuad)
            screenCenter = camera.worldToViewport(effectiveItem.center)
            selectionHandles = effectiveItem.kind == .text
                ? []
                : makeCornerEditHandles(for: screenQuad)
        } else {
            let groupWorldBounds = groupSelectionWorldBounds(for: selectedItems)
            subject = .group(
                primaryItemID: resolvedPrimarySelectedItemID,
                memberItemIDs: selectedItems.map(\.id)
            )
            worldQuad = CanvasQuad(rect: groupWorldBounds)
            screenQuad = camera.worldToViewport(worldQuad)
            screenCenter = camera.worldToViewport(
                CGPoint(x: groupWorldBounds.midX, y: groupWorldBounds.midY)
            )
            selectionHandles = makeCornerEditHandles(for: screenQuad)
        }
        let selectionPayload = CanvasEditSelectionOverlayPayload(
            subject: subject,
            rotateAffordance: makeRotateAffordance(
                screenCenter: screenCenter,
                screenQuad: screenQuad
            )
        )

        return CanvasEditRenderOverlay(
            itemID: subject.primaryItemID,
            kind: .selection,
            activeWorldQuad: worldQuad,
            activeScreenQuad: screenQuad,
            handles: selectionHandles,
            payload: .selection(selectionPayload)
        )
    }

    private func makeSelectionHighlights(
        scene: CanvasScene,
        camera: CanvasCamera,
        interactionState: CanvasInteractionState,
        inlineEditState: CanvasInlineEditState?,
        rotationPreviewState: CanvasRotationPreviewState?
    ) -> [CanvasSelectionHighlight] {
        guard inlineEditState == nil, interactionState.selectionCount > 1 else {
            return []
        }

        return selectedOverlayItems(
            scene: scene,
            interactionState: interactionState,
            rotationPreviewState: rotationPreviewState
        ).map { item in
            CanvasSelectionHighlight(
                itemID: item.id,
                screenQuad: camera.worldToViewport(item.worldQuad),
                isPrimary: item.id == interactionState.primarySelectedItemID
            )
        }
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

    private func makeInteractionOverlay(
        scene: CanvasScene,
        camera: CanvasCamera,
        interactionState: CanvasInteractionState,
        inlineEditState: CanvasInlineEditState?,
        rotationPreviewState: CanvasRotationPreviewState?,
        rotationInteractionState: CanvasRotationInteractionState?,
        alignmentInteractionState: CanvasAlignmentInteractionState?
    ) -> CanvasInteractionRenderOverlay? {
        if let rotationOverlay = makeRotationInteractionOverlay(
            scene: scene,
            camera: camera,
            interactionState: interactionState,
            inlineEditState: inlineEditState,
            rotationPreviewState: rotationPreviewState,
            rotationInteractionState: rotationInteractionState
        ) {
            return rotationOverlay
        }

        return makeAlignmentInteractionOverlay(
            scene: scene,
            camera: camera,
            interactionState: interactionState,
            inlineEditState: inlineEditState,
            alignmentInteractionState: alignmentInteractionState
        )
    }

    private func makeRotationInteractionOverlay(
        scene: CanvasScene,
        camera: CanvasCamera,
        interactionState: CanvasInteractionState,
        inlineEditState: CanvasInlineEditState?,
        rotationPreviewState: CanvasRotationPreviewState?,
        rotationInteractionState: CanvasRotationInteractionState?
    ) -> CanvasInteractionRenderOverlay? {
        guard inlineEditState == nil else {
            return nil
        }

        guard
            let rotationInteractionState,
            interactionStateMatchesTransientSelection(
                selectedItemIDs: interactionState.selectedItemIDs,
                transientItemIDs: rotationInteractionState.memberItemIDs
            )
        else {
            return nil
        }

        let effectiveItems = rotationInteractionState.memberItemIDs.compactMap { itemID in
            scene.boardItem(withID: itemID)
        }.map { item in
            effectiveBoardItem(
                from: item,
                rotationPreviewState: rotationPreviewState
            )
        }
        guard effectiveItems.isEmpty == false else {
            return nil
        }

        let screenQuad: CanvasQuad
        let screenCenter: CGPoint
        let currentRotationRadians: CGFloat
        let overlayItemID: CanvasItemID

        if effectiveItems.count == 1, let effectiveItem = effectiveItems.first {
            screenQuad = camera.worldToViewport(effectiveItem.worldQuad)
            screenCenter = camera.worldToViewport(effectiveItem.center)
            currentRotationRadians = normalizedCanvasAngle(
                effectiveItem.rotationRadians
            )
            overlayItemID = effectiveItem.id
        } else {
            let interactionBounds = groupSelectionWorldBounds(for: effectiveItems)
            screenQuad = camera.worldToViewport(
                CanvasQuad(rect: interactionBounds)
            )
            screenCenter = camera.worldToViewport(
                CGPoint(
                    x: interactionBounds.midX,
                    y: interactionBounds.midY
                )
            )
            currentRotationRadians = normalizedCanvasAngle(
                rotationPreviewState?.displayRotationRadians ?? 0
            )
            overlayItemID = rotationInteractionState.primaryItemID
        }

        let rotateAffordance = makeRotateAffordance(
            screenCenter: screenCenter,
            screenQuad: screenQuad
        )
        let displayDegrees0To360 = canvasDisplayDegrees0To360(
            forRotationRadians: currentRotationRadians
        )
        let zeroReference: CanvasInteractionAngleZeroReference = .up
        let ringRadius = max(
            Self.minimumRotationInteractionRingRadius,
            distance(
                from: screenCenter,
                to: rotateAffordance.handle.screenCenter
            )
        )
        let tickSegments = makeRotationInteractionTickSegments(
            centeredAt: screenCenter,
            ringRadius: ringRadius,
            zeroReference: zeroReference
        )
        let zeroReferenceSegment = canvasRadialSegment(
            centeredAt: screenCenter,
            startRadius: 0,
            endRadius: ringRadius,
            displayDegrees0To360: 0,
            zeroReference: zeroReference
        )
        let currentAngleSegment = canvasRadialSegment(
            centeredAt: screenCenter,
            startRadius: 0,
            endRadius: ringRadius,
            displayDegrees0To360: displayDegrees0To360,
            zeroReference: zeroReference
        )
        let textScreenAnchor = CGPoint(
            x: screenCenter.x,
            y: screenCenter.y - ringRadius - Self.rotationInteractionTextOffset
        )

        return CanvasInteractionRenderOverlay(
            itemID: overlayItemID,
            kind: .rotation,
            payload: .rotation(
                CanvasRotationInteractionOverlayPayload(
                    screenCenter: screenCenter,
                    currentRotationRadians: currentRotationRadians,
                    displayDegrees0To360: displayDegrees0To360,
                    zeroReference: zeroReference,
                    tickStepDegrees: Self.rotationInteractionTickStepDegrees,
                    ringRadius: ringRadius,
                    ringScreenRect: canvasCircleRect(
                        centeredAt: screenCenter,
                        radius: ringRadius
                    ),
                    tickSegments: tickSegments,
                    zeroReferenceSegment: zeroReferenceSegment,
                    currentAngleSegment: currentAngleSegment,
                    textScreenAnchor: textScreenAnchor,
                    isActive: true
                )
            )
        )
    }

    private func makeAlignmentInteractionOverlay(
        scene: CanvasScene,
        camera: CanvasCamera,
        interactionState: CanvasInteractionState,
        inlineEditState: CanvasInlineEditState?,
        alignmentInteractionState: CanvasAlignmentInteractionState?
    ) -> CanvasInteractionRenderOverlay? {
        guard inlineEditState == nil else {
            return nil
        }

        guard
            let alignmentInteractionState,
            alignmentInteractionState.isActive,
            interactionStateMatchesTransientSelection(
                selectedItemIDs: interactionState.selectedItemIDs,
                transientItemIDs: alignmentInteractionState.memberItemIDs
            ),
            alignmentInteractionState.memberItemIDs.allSatisfy({
                scene.boardItem(withID: $0) != nil
            })
        else {
            return nil
        }

        let guideSegments = alignmentInteractionState.guides.map { guide in
            CanvasInteractionLineSegment(
                start: camera.worldToViewport(guide.worldStart),
                end: camera.worldToViewport(guide.worldEnd)
            )
        }

        return CanvasInteractionRenderOverlay(
            itemID: alignmentInteractionState.itemID,
            kind: .alignment,
            payload: .alignment(
                CanvasAlignmentInteractionOverlayPayload(
                    guideSegments: guideSegments,
                    xMatch: alignmentInteractionState.xMatch,
                    yMatch: alignmentInteractionState.yMatch,
                    isActive: alignmentInteractionState.isActive
                )
            )
        )
    }

    private func effectiveBoardItem(
        from item: CanvasBoardItem,
        rotationPreviewState: CanvasRotationPreviewState?
    ) -> CanvasBoardItem {
        guard
            let rotationPreviewState,
            let previewGeometry = rotationPreviewState.geometry(for: item.id)
        else {
            return item
        }

        return item.applyingGeometry(previewGeometry) ?? item
    }

    private func selectedOverlayItems(
        scene: CanvasScene,
        interactionState: CanvasInteractionState,
        rotationPreviewState: CanvasRotationPreviewState?
    ) -> [CanvasBoardItem] {
        interactionState.selectedItemIDs.compactMap { itemID in
            scene.boardItem(withID: itemID)
        }.map { item in
            effectiveBoardItem(
                from: item,
                rotationPreviewState: rotationPreviewState
            )
        }
    }

    private func groupSelectionWorldBounds(
        for items: [CanvasBoardItem]
    ) -> CGRect {
        let bounds = items.reduce(into: CGRect.null) { partialResult, item in
            partialResult = partialResult.union(item.worldQuad.boundingRect.standardized)
        }
        return bounds.isNull ? .zero : bounds.standardized
    }

    private func interactionStateMatchesTransientSelection(
        selectedItemIDs: [CanvasItemID],
        transientItemIDs: [CanvasItemID]
    ) -> Bool {
        Set(selectedItemIDs) == Set(transientItemIDs)
    }

    private func makeRenderItem(
        for item: CanvasBoardItem,
        camera: CanvasCamera,
        inlineEditState: CanvasInlineEditState?,
        rotationPreviewState: CanvasRotationPreviewState?
    ) -> CanvasRenderItem {
        switch item {
        case let .image(imageItem):
            return makeImageRenderItem(
                for: imageItem,
                camera: camera,
                inlineEditState: inlineEditState,
                rotationPreviewState: rotationPreviewState
            )
        case let .text(textItem):
            return makeTextRenderItem(
                for: textItem,
                camera: camera,
                inlineEditState: inlineEditState,
                rotationPreviewState: rotationPreviewState
            )
        case let .markdown(markdownItem):
            return makeMarkdownRenderItem(
                for: markdownItem,
                camera: camera,
                rotationPreviewState: rotationPreviewState
            )
        case let .handDrawing(handDrawingItem):
            return makeHandDrawingRenderItem(
                for: handDrawingItem,
                camera: camera,
                rotationPreviewState: rotationPreviewState
            )
        }
    }

    private func makeImageRenderItem(
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
            rotationRadians: presentation.effectiveRotationRadians,
            zIndex: presentation.zIndex,
            payload: .image(
                CanvasImageRenderPayload(
                    displayContract: CanvasImageDisplayContract(
                        assetReference: presentation.assetReference,
                        posterCGImage: presentation.posterCGImage,
                        allowsAnimatedPlayback: presentation.allowsAnimatedPlayback
                    ),
                    contentsRect: presentation.isCropPreviewActive
                        ? CanvasImageCropRect.fullImage.cgRect
                        : presentation.effectiveCropRectNormalized.cgRect
                )
            )
        )
    }

    private func makeHandDrawingRenderItem(
        for item: CanvasHandDrawingItem,
        camera: CanvasCamera,
        rotationPreviewState: CanvasRotationPreviewState?
    ) -> CanvasRenderItem {
        let effectiveHandDrawingItem: CanvasHandDrawingItem
        switch effectiveBoardItem(
            from: .handDrawing(item),
            rotationPreviewState: rotationPreviewState
        ) {
        case let .handDrawing(resolvedHandDrawingItem):
            effectiveHandDrawingItem = resolvedHandDrawingItem
        case .image, .text, .markdown:
            assertionFailure("Expected hand drawing item after applying geometry.")
            effectiveHandDrawingItem = item
        }

        let screenQuad = camera.worldToViewport(effectiveHandDrawingItem.worldQuad)
        return CanvasRenderItem(
            id: effectiveHandDrawingItem.id,
            screenFrame: screenQuad.boundingRect.standardized,
            screenQuad: screenQuad,
            screenCenter: camera.worldToViewport(effectiveHandDrawingItem.center),
            screenBoundsSize: CGSize(
                width: effectiveHandDrawingItem.size.width * camera.zoomScale,
                height: effectiveHandDrawingItem.size.height * camera.zoomScale
            ),
            rotationRadians: effectiveHandDrawingItem.rotationRadians,
            zIndex: effectiveHandDrawingItem.zIndex,
            payload: .handDrawing(
                CanvasHandDrawingRenderPayload(
                    previewAssetReference: effectiveHandDrawingItem.previewAsset.reference,
                    previewCGImage: effectiveHandDrawingItem.previewAsset.posterCGImage,
                    paper: effectiveHandDrawingItem.paper,
                    isEmpty: effectiveHandDrawingItem.isEmpty
                )
            )
        )
    }

    private func makeTextRenderItem(
        for item: CanvasTextItem,
        camera: CanvasCamera,
        inlineEditState: CanvasInlineEditState?,
        rotationPreviewState: CanvasRotationPreviewState?
    ) -> CanvasRenderItem {
        let effectiveTextItem: CanvasTextItem
        switch effectiveBoardItem(
            from: .text(item),
            rotationPreviewState: rotationPreviewState
        ) {
        case let .text(resolvedTextItem):
            effectiveTextItem = resolvedTextItem
        case .image, .markdown, .handDrawing:
            assertionFailure("Expected text item after applying text presentation.")
            effectiveTextItem = item
        }

        let resolvedText: String
        if inlineEditState?.mode == .text, inlineEditState?.itemID == effectiveTextItem.id {
            resolvedText = inlineEditState?.draftText ?? effectiveTextItem.text
        } else {
            resolvedText = effectiveTextItem.text
        }

        let screenQuad = camera.worldToViewport(effectiveTextItem.worldQuad)
        return CanvasRenderItem(
            id: effectiveTextItem.id,
            screenFrame: screenQuad.boundingRect.standardized,
            screenQuad: screenQuad,
            screenCenter: camera.worldToViewport(effectiveTextItem.center),
            screenBoundsSize: CGSize(
                width: effectiveTextItem.size.width * camera.zoomScale,
                height: effectiveTextItem.size.height * camera.zoomScale
            ),
            rotationRadians: effectiveTextItem.rotationRadians,
            zIndex: effectiveTextItem.zIndex,
            payload: .text(
                CanvasTextRenderPayload(
                    text: resolvedText,
                    style: effectiveTextItem.style,
                    zoomScale: camera.zoomScale
                )
            )
        )
    }

    private func makeMarkdownRenderItem(
        for item: CanvasMarkdownItem,
        camera: CanvasCamera,
        rotationPreviewState: CanvasRotationPreviewState?
    ) -> CanvasRenderItem {
        let effectiveMarkdownItem: CanvasMarkdownItem
        switch effectiveBoardItem(
            from: .markdown(item),
            rotationPreviewState: rotationPreviewState
        ) {
        case let .markdown(resolvedMarkdownItem):
            effectiveMarkdownItem = resolvedMarkdownItem
        case .image, .text, .handDrawing:
            assertionFailure("Expected markdown item after applying geometry.")
            effectiveMarkdownItem = item
        }

        let screenQuad = camera.worldToViewport(effectiveMarkdownItem.worldQuad)
        return CanvasRenderItem(
            id: effectiveMarkdownItem.id,
            screenFrame: screenQuad.boundingRect.standardized,
            screenQuad: screenQuad,
            screenCenter: camera.worldToViewport(effectiveMarkdownItem.center),
            screenBoundsSize: CGSize(
                width: effectiveMarkdownItem.size.width * camera.zoomScale,
                height: effectiveMarkdownItem.size.height * camera.zoomScale
            ),
            rotationRadians: effectiveMarkdownItem.rotationRadians,
            zIndex: effectiveMarkdownItem.zIndex,
            payload: .markdown(
                CanvasMarkdownRenderPayload(
                    markdownSource: effectiveMarkdownItem.markdownSource,
                    style: effectiveMarkdownItem.style,
                    zoomScale: camera.zoomScale
                )
            )
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
        screenCenter: CGPoint,
        screenQuad: CanvasQuad
    ) -> CanvasEditRotateOverlayPayload {
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

    private func distance(
        from start: CGPoint,
        to end: CGPoint
    ) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    private func makeRotationInteractionTickSegments(
        centeredAt center: CGPoint,
        ringRadius: CGFloat,
        zeroReference: CanvasInteractionAngleZeroReference
    ) -> [CanvasInteractionLineSegment] {
        let tickStartRadius = max(
            ringRadius - Self.rotationInteractionTickLength,
            0
        )
        return stride(
            from: CGFloat(0),
            to: 360,
            by: Self.rotationInteractionTickStepDegrees
        ).map { degrees in
            canvasRadialSegment(
                centeredAt: center,
                startRadius: tickStartRadius,
                endRadius: ringRadius,
                displayDegrees0To360: degrees,
                zeroReference: zeroReference
            )
        }
    }
}
