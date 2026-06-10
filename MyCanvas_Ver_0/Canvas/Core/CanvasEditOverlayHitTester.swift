import CoreGraphics
import Foundation

enum CanvasEditOverlayHitTargetKind {
    case rotateHandle
    case groupRotateHandle
    case selectionHandle(role: CanvasSelectionHandleRole)
    case groupSelectionHandle(role: CanvasSelectionHandleRole)
    case arrowEndpointHandle(role: CanvasArrowEndpointRole)
    case selectionTranslationArea
    case cropHandle(role: CanvasCropHandleRole)
    // Crop translation now covers both the visible crop interior and the edge
    // hit slop so controllers can treat the whole movable area uniformly.
    case cropTranslationArea

    var debugName: String {
        switch self {
        case .rotateHandle:
            return "rotateHandle"
        case .groupRotateHandle:
            return "groupRotateHandle"
        case let .selectionHandle(role):
            return "selectionHandle(\(String(describing: role)))"
        case let .groupSelectionHandle(role):
            return "groupSelectionHandle(\(String(describing: role)))"
        case let .arrowEndpointHandle(role):
            return "arrowEndpointHandle(\(String(describing: role)))"
        case .selectionTranslationArea:
            return "selectionTranslationArea"
        case let .cropHandle(role):
            return "cropHandle(\(String(describing: role)))"
        case .cropTranslationArea:
            return "cropTranslationArea"
        }
    }
}

struct CanvasEditOverlayHitTarget {
    let kind: CanvasEditOverlayHitTargetKind
    let itemID: CanvasItemID
    let anchorRect: CGRect
}

struct CanvasEditOverlayHitTester {
    func resolve(
        at viewportPoint: CGPoint,
        renderSnapshot: CanvasRenderSnapshot,
        metrics: CanvasContextResolverMetrics
    ) -> CanvasEditOverlayHitTarget? {
        guard let editOverlay = renderSnapshot.editOverlay else {
            return nil
        }

        switch editOverlay.kind {
        case .crop:
            return resolveCropHitTarget(
                at: viewportPoint,
                editOverlay: editOverlay,
                metrics: metrics
            )
        case .selection:
            return resolveSelectionHitTarget(
                at: viewportPoint,
                editOverlay: editOverlay,
                renderSnapshot: renderSnapshot,
                metrics: metrics
            )
        }
    }

    private func resolveCropHitTarget(
        at viewportPoint: CGPoint,
        editOverlay: CanvasEditRenderOverlay,
        metrics: CanvasContextResolverMetrics
    ) -> CanvasEditOverlayHitTarget? {
        guard case let .crop(payload) = editOverlay.payload else {
            return nil
        }

        for handle in editOverlay.handles {
            guard let role = handle.role.cropHandleRole else {
                continue
            }

            let hitRect = rect(
                centeredAt: handle.screenCenter,
                size: metrics.cropHandleHitTargetSize
            )
            if hitRect.contains(viewportPoint) {
                return CanvasEditOverlayHitTarget(
                    kind: .cropHandle(role: role),
                    itemID: editOverlay.itemID,
                    anchorRect: hitRect
                )
            }
        }

        if isWithinCropTranslationArea(
            viewportPoint,
            cropScreenQuad: payload.cropScreenQuad,
            hitSlopWidth: metrics.cropOutlineHitTargetWidth
        ) {
            return CanvasEditOverlayHitTarget(
                kind: .cropTranslationArea,
                itemID: editOverlay.itemID,
                anchorRect: payload.cropScreenQuad.boundingRect.standardized
            )
        }

        return nil
    }

    private func resolveSelectionHitTarget(
        at viewportPoint: CGPoint,
        editOverlay: CanvasEditRenderOverlay,
        renderSnapshot: CanvasRenderSnapshot,
        metrics: CanvasContextResolverMetrics
    ) -> CanvasEditOverlayHitTarget? {
        guard case let .selection(payload) = editOverlay.payload else {
            return nil
        }
        if let rotateAffordance = payload.rotateAffordance {
            let rotateHitTargetKind: CanvasEditOverlayHitTargetKind = payload.subject.isGroupSelection
                ? .groupRotateHandle
                : .rotateHandle

            let rotateHitRect = rect(
                centeredAt: rotateAffordance.handle.screenCenter,
                size: metrics.rotateHandleHitTargetSize
            )
            if rotateHitRect.contains(viewportPoint) {
                return CanvasEditOverlayHitTarget(
                    kind: rotateHitTargetKind,
                    itemID: editOverlay.itemID,
                    anchorRect: rotateHitRect
                )
            }
        }

        for handle in editOverlay.handles {
            if let role = handle.role.arrowEndpointRole {
                let hitRect = rect(
                    centeredAt: handle.screenCenter,
                    size: metrics.selectionHandleHitTargetSize
                )
                if hitRect.contains(viewportPoint) {
                    return CanvasEditOverlayHitTarget(
                        kind: .arrowEndpointHandle(role: role),
                        itemID: editOverlay.itemID,
                        anchorRect: hitRect
                    )
                }
            }

            guard let role = handle.role.selectionHandleRole else {
                continue
            }

            let hitRect = rect(
                centeredAt: handle.screenCenter,
                size: metrics.selectionHandleHitTargetSize
            )
            if hitRect.contains(viewportPoint) {
                let handleHitTargetKind: CanvasEditOverlayHitTargetKind = payload.subject.isGroupSelection
                    ? .groupSelectionHandle(role: role)
                    : .selectionHandle(role: role)
                return CanvasEditOverlayHitTarget(
                    kind: handleHitTargetKind,
                    itemID: editOverlay.itemID,
                    anchorRect: hitRect
                )
            }
        }

        let selectedMemberScreenQuads = selectionMemberScreenQuads(
            for: payload.subject.memberItemIDs,
            renderSnapshot: renderSnapshot
        )
        if isWithinSelectionTranslationArea(
            viewportPoint,
            selectionScreenQuad: editOverlay.activeScreenQuad,
            selectionTranslationPath: payload.translationScreenPath,
            selectedMemberScreenQuads: selectedMemberScreenQuads,
            expectedMemberCount: payload.subject.memberItemIDs.count,
            outlineHitSlopWidth: metrics.selectionOutlineHitTargetWidth
        ) {
            return CanvasEditOverlayHitTarget(
                kind: .selectionTranslationArea,
                itemID: editOverlay.itemID,
                anchorRect: editOverlay.activeScreenQuad.boundingRect.standardized
            )
        }

        return nil
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

    private func isWithinCropTranslationArea(
        _ viewportPoint: CGPoint,
        cropScreenQuad: CanvasQuad,
        hitSlopWidth: CGFloat
    ) -> Bool {
        isWithinQuadTranslationArea(
            viewportPoint,
            screenQuad: cropScreenQuad,
            hitSlopWidth: hitSlopWidth
        )
    }

    private func selectionMemberScreenQuads(
        for memberItemIDs: [CanvasItemID],
        renderSnapshot: CanvasRenderSnapshot
    ) -> [CanvasQuad] {
        let screenQuadByItemID = Dictionary(
            uniqueKeysWithValues: renderSnapshot.items.map { item in
                (item.id, item.screenQuad)
            }
        )
        return memberItemIDs.compactMap { memberItemID in
            screenQuadByItemID[memberItemID]
        }
    }

    private func isWithinSelectionTranslationArea(
        _ viewportPoint: CGPoint,
        selectionScreenQuad: CanvasQuad,
        selectionTranslationPath: CGPath?,
        selectedMemberScreenQuads: [CanvasQuad],
        expectedMemberCount: Int,
        outlineHitSlopWidth: CGFloat
    ) -> Bool {
        if let selectionTranslationPath {
            if selectionTranslationPath.contains(viewportPoint) {
                return true
            }

            let strokedTranslationPath = selectionTranslationPath.copy(
                strokingWithWidth: outlineHitSlopWidth,
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 10,
                transform: .identity
            )
            if strokedTranslationPath.contains(viewportPoint) {
                return true
            }
        }

        if isWithinQuadOutlineHitArea(
            viewportPoint,
            screenQuad: selectionScreenQuad,
            hitSlopWidth: outlineHitSlopWidth
        ) {
            return true
        }

        return isWithinSelectionInteriorBlankArea(
            viewportPoint,
            selectionScreenQuad: selectionScreenQuad,
            selectedMemberScreenQuads: selectedMemberScreenQuads,
            expectedMemberCount: expectedMemberCount
        )
    }

    private func isWithinSelectionInteriorBlankArea(
        _ viewportPoint: CGPoint,
        selectionScreenQuad: CanvasQuad,
        selectedMemberScreenQuads: [CanvasQuad],
        expectedMemberCount: Int
    ) -> Bool {
        guard
            selectionScreenQuad.contains(viewportPoint),
            expectedMemberCount > 0,
            selectedMemberScreenQuads.count == expectedMemberCount
        else {
            return false
        }

        return selectedMemberScreenQuads.contains(where: { screenQuad in
            screenQuad.contains(viewportPoint)
        }) == false
    }

    private func isWithinQuadTranslationArea(
        _ viewportPoint: CGPoint,
        screenQuad: CanvasQuad,
        hitSlopWidth: CGFloat
    ) -> Bool {
        if screenQuad.contains(viewportPoint) {
            return true
        }

        return isWithinQuadOutlineHitArea(
            viewportPoint,
            screenQuad: screenQuad,
            hitSlopWidth: hitSlopWidth
        )
    }

    private func isWithinQuadOutlineHitArea(
        _ viewportPoint: CGPoint,
        screenQuad: CanvasQuad,
        hitSlopWidth: CGFloat
    ) -> Bool {
        let halfHitSlopWidth = max(hitSlopWidth, 0) / 2
        guard halfHitSlopWidth > 0 else {
            return false
        }

        return screenQuad.edges.contains { edge in
            canvasDistance(
                from: viewportPoint,
                toSegmentStart: edge.start,
                segmentEnd: edge.end
            ) <= halfHitSlopWidth
        }
    }
}
