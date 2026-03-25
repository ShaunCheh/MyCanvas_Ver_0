import CoreGraphics
import Foundation

enum CanvasEditOverlayHitTargetKind {
    case rotateHandle
    case selectionHandle(role: CanvasSelectionHandleRole)
    case cropHandle(role: CanvasCropHandleRole)
    // Phase 2 freezes the future input vocabulary while keeping the old
    // edge-only crop movement behavior unchanged.
    case cropTranslationArea
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

        for edge in payload.cropScreenQuad.edges {
            if canvasDistance(
                from: viewportPoint,
                toSegmentStart: edge.start,
                segmentEnd: edge.end
            ) <= (metrics.cropOutlineHitTargetWidth / 2) {
                return CanvasEditOverlayHitTarget(
                    kind: .cropTranslationArea,
                    itemID: editOverlay.itemID,
                    anchorRect: payload.cropScreenQuad.boundingRect.standardized
                )
            }
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

        let rotateHitRect = rect(
            centeredAt: payload.rotateAffordance.handle.screenCenter,
            size: metrics.rotateHandleHitTargetSize
        )
        if rotateHitRect.contains(viewportPoint) {
            return CanvasEditOverlayHitTarget(
                kind: .rotateHandle,
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
                return CanvasEditOverlayHitTarget(
                    kind: .selectionHandle(role: role),
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
}
