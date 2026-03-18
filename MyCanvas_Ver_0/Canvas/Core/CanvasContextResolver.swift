import CoreGraphics
import Foundation

struct CanvasContextResolverMetrics {
    let selectionHandleHitTargetSize: CGFloat
    let cropHandleHitTargetSize: CGFloat
    let cropOutlineHitTargetWidth: CGFloat
    let rotateHandleHitTargetSize: CGFloat
}

struct CanvasContextResolver {
    func resolveContext(
        at viewportPoint: CGPoint,
        scene: CanvasScene,
        camera: CanvasCamera,
        renderSnapshot: CanvasRenderSnapshot,
        selectedItemID: CanvasImageItemID?,
        isInlineEditModeActive: Bool,
        isInlineCropModeActive: Bool,
        interactionMetrics: CanvasContextResolverMetrics
    ) -> CanvasContextMenuContext {
        let invocationWorldPoint = camera.viewportToWorld(viewportPoint)

        if let resolvedTarget = resolveEditHandleTarget(
            at: viewportPoint,
            renderSnapshot: renderSnapshot,
            interactionMetrics: interactionMetrics
        ) {
            return makeContext(
                viewportPoint: viewportPoint,
                worldPoint: invocationWorldPoint,
                resolvedTarget: resolvedTarget,
                selectedItemID: selectedItemID,
                isInlineEditModeActive: isInlineEditModeActive,
                isInlineCropModeActive: isInlineCropModeActive
            )
        }

        if let resolvedTarget = resolveCropOutlineTarget(
            at: viewportPoint,
            renderSnapshot: renderSnapshot,
            interactionMetrics: interactionMetrics
        ) {
            return makeContext(
                viewportPoint: viewportPoint,
                worldPoint: invocationWorldPoint,
                resolvedTarget: resolvedTarget,
                selectedItemID: selectedItemID,
                isInlineEditModeActive: isInlineEditModeActive,
                isInlineCropModeActive: isInlineCropModeActive
            )
        }

        if isInlineEditModeActive {
            return makeContext(
                viewportPoint: viewportPoint,
                worldPoint: invocationWorldPoint,
                resolvedTarget: ResolvedTarget(targetKind: .blank),
                selectedItemID: selectedItemID,
                isInlineEditModeActive: isInlineEditModeActive,
                isInlineCropModeActive: isInlineCropModeActive
            )
        }

        guard let itemID = scene.topmostItemID(containing: invocationWorldPoint) else {
            return makeContext(
                viewportPoint: viewportPoint,
                worldPoint: invocationWorldPoint,
                resolvedTarget: ResolvedTarget(targetKind: .blank),
                selectedItemID: selectedItemID,
                isInlineEditModeActive: isInlineEditModeActive,
                isInlineCropModeActive: isInlineCropModeActive
            )
        }

        let targetKind: CanvasContextMenuTargetKind =
            itemID == selectedItemID ? .selectedItemBody : .unselectedItemBody

        return makeContext(
            viewportPoint: viewportPoint,
            worldPoint: invocationWorldPoint,
            resolvedTarget: ResolvedTarget(
                targetKind: targetKind,
                targetItemID: itemID,
                anchorRect: itemAnchorRect(
                    for: itemID,
                    renderSnapshot: renderSnapshot
                )
            ),
            selectedItemID: selectedItemID,
            isInlineEditModeActive: isInlineEditModeActive,
            isInlineCropModeActive: isInlineCropModeActive
        )
    }

    private func resolveEditHandleTarget(
        at viewportPoint: CGPoint,
        renderSnapshot: CanvasRenderSnapshot,
        interactionMetrics: CanvasContextResolverMetrics
    ) -> ResolvedTarget? {
        guard let editOverlay = renderSnapshot.editOverlay else {
            return nil
        }

        switch editOverlay.kind {
        case .crop:
            for handle in editOverlay.handles {
                guard let role = handle.role.cropHandleRole else {
                    continue
                }

                let hitRect = rect(
                    centeredAt: handle.screenCenter,
                    size: interactionMetrics.cropHandleHitTargetSize
                )
                if hitRect.contains(viewportPoint) {
                    return ResolvedTarget(
                        targetKind: .cropHandle(role: role),
                        targetItemID: editOverlay.itemID,
                        anchorRect: hitRect
                    )
                }
            }
        case .selection:
            guard case let .selection(payload) = editOverlay.payload else {
                return nil
            }

            let rotateHitRect = rect(
                centeredAt: payload.rotateAffordance.handle.screenCenter,
                size: interactionMetrics.rotateHandleHitTargetSize
            )
            if rotateHitRect.contains(viewportPoint) {
                return ResolvedTarget(
                    targetKind: .rotateHandle,
                    targetItemID: editOverlay.itemID,
                    anchorRect: rotateHitRect
                )
            }

            for handle in editOverlay.handles {
                guard let role = handle.role.selectionHandleRole else {
                    continue
                }

                let hitRect = rect(
                    centeredAt: handle.screenCenter,
                    size: interactionMetrics.selectionHandleHitTargetSize
                )
                if hitRect.contains(viewportPoint) {
                    return ResolvedTarget(
                        targetKind: .selectionHandle(role: role),
                        targetItemID: editOverlay.itemID,
                        anchorRect: hitRect
                    )
                }
            }
        }

        return nil
    }

    private func resolveCropOutlineTarget(
        at viewportPoint: CGPoint,
        renderSnapshot: CanvasRenderSnapshot,
        interactionMetrics: CanvasContextResolverMetrics
    ) -> ResolvedTarget? {
        guard
            let editOverlay = renderSnapshot.editOverlay,
            case let .crop(payload) = editOverlay.payload
        else {
            return nil
        }

        for (start, end) in quadEdges(for: payload.cropScreenQuad) {
            if distance(
                from: viewportPoint,
                toSegmentStart: start,
                segmentEnd: end
            ) <= (interactionMetrics.cropOutlineHitTargetWidth / 2) {
                return ResolvedTarget(
                    targetKind: .cropOutline,
                    targetItemID: editOverlay.itemID,
                    anchorRect: payload.cropScreenQuad.boundingRect.standardized
                )
            }
        }

        return nil
    }

    private func itemAnchorRect(
        for itemID: CanvasImageItemID,
        renderSnapshot: CanvasRenderSnapshot
    ) -> CGRect? {
        if let editOverlay = renderSnapshot.editOverlay,
           editOverlay.itemID == itemID
        {
            return editOverlay.activeScreenQuad.boundingRect.standardized
        }

        return renderSnapshot.items
            .first(where: { $0.id == itemID })?
            .screenQuad
            .boundingRect
            .standardized
    }

    private func makeContext(
        viewportPoint: CGPoint,
        worldPoint: CGPoint,
        resolvedTarget: ResolvedTarget,
        selectedItemID: CanvasImageItemID?,
        isInlineEditModeActive: Bool,
        isInlineCropModeActive: Bool
    ) -> CanvasContextMenuContext {
        CanvasContextMenuContext(
            invocationViewportPoint: viewportPoint,
            invocationWorldPoint: worldPoint,
            targetKind: resolvedTarget.targetKind,
            targetItemID: resolvedTarget.targetItemID,
            anchorRect: resolvedTarget.anchorRect,
            selectedItemID: selectedItemID,
            isInlineEditModeActive: isInlineEditModeActive,
            isInlineCropModeActive: isInlineCropModeActive
        )
    }

    private func rect(
        centeredAt center: CGPoint,
        size: CGFloat
    ) -> CGRect {
        CGRect(
            x: center.x - size / 2,
            y: center.y - size / 2,
            width: size,
            height: size
        ).standardized
    }

    private func quadEdges(
        for quad: CanvasQuad
    ) -> [(start: CGPoint, end: CGPoint)] {
        [
            (quad.topLeading, quad.topTrailing),
            (quad.topTrailing, quad.bottomTrailing),
            (quad.bottomTrailing, quad.bottomLeading),
            (quad.bottomLeading, quad.topLeading)
        ]
    }

    private func distance(
        from point: CGPoint,
        toSegmentStart start: CGPoint,
        segmentEnd end: CGPoint
    ) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = (dx * dx) + (dy * dy)
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let projection = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        let clampedProjection = min(max(projection, 0), 1)
        let closestPoint = CGPoint(
            x: start.x + (clampedProjection * dx),
            y: start.y + (clampedProjection * dy)
        )
        return hypot(point.x - closestPoint.x, point.y - closestPoint.y)
    }

    private struct ResolvedTarget {
        let targetKind: CanvasContextMenuTargetKind
        var targetItemID: CanvasImageItemID? = nil
        var anchorRect: CGRect? = nil
    }
}
