import CoreGraphics
import Foundation

enum CanvasEditOverlayHitTargetKind {
    case rotateHandle
    case groupRotateHandle
    case selectionHandle(role: CanvasSelectionHandleRole)
    case groupSelectionHandle(role: CanvasSelectionHandleRole)
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
        metrics: CanvasContextResolverMetrics
    ) -> CanvasEditOverlayHitTarget? {
        guard case let .selection(payload) = editOverlay.payload else {
            return nil
        }
        let rotateHitTargetKind: CanvasEditOverlayHitTargetKind = payload.subject.isGroupSelection
            ? .groupRotateHandle
            : .rotateHandle

        let rotateHitRect = rect(
            centeredAt: payload.rotateAffordance.handle.screenCenter,
            size: metrics.rotateHandleHitTargetSize
        )
        if rotateHitRect.contains(viewportPoint) {
            return CanvasEditOverlayHitTarget(
                kind: rotateHitTargetKind,
                itemID: editOverlay.itemID,
                anchorRect: rotateHitRect
            )
        }

        for handle in editOverlay.handles {
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
        if cropScreenQuad.contains(viewportPoint) {
            return true
        }

        let halfHitSlopWidth = max(hitSlopWidth, 0) / 2
        guard halfHitSlopWidth > 0 else {
            return false
        }

        return cropScreenQuad.edges.contains { edge in
            canvasDistance(
                from: viewportPoint,
                toSegmentStart: edge.start,
                segmentEnd: edge.end
            ) <= halfHitSlopWidth
        }
    }
}
