import CoreGraphics
import Foundation

struct CanvasContextResolverMetrics {
    let selectionHandleHitTargetSize: CGFloat
    let cropHandleHitTargetSize: CGFloat
    let cropOutlineHitTargetWidth: CGFloat
    let rotateHandleHitTargetSize: CGFloat
}

struct CanvasContextResolver {
    private let editOverlayHitTester = CanvasEditOverlayHitTester()

    func resolveContext(
        at viewportPoint: CGPoint,
        scene: CanvasScene,
        camera: CanvasCamera,
        renderSnapshot: CanvasRenderSnapshot,
        selectedItemID: CanvasItemID?,
        isInlineEditModeActive: Bool,
        isInlineCropModeActive: Bool,
        interactionMetrics: CanvasContextResolverMetrics
    ) -> CanvasContextMenuContext {
        let invocationWorldPoint = camera.viewportToWorld(viewportPoint)
        let editOverlayDescription = describeContextResolverOverlay(renderSnapshot.editOverlay)

        func finalize(
            branch: String,
            resolvedTarget: ResolvedTarget,
            sceneHitItemID: CanvasItemID? = nil
        ) -> CanvasContextMenuContext {
            let context = makeContext(
                viewportPoint: viewportPoint,
                worldPoint: invocationWorldPoint,
                resolvedTarget: resolvedTarget,
                selectedItemID: selectedItemID,
                isInlineEditModeActive: isInlineEditModeActive,
                isInlineCropModeActive: isInlineCropModeActive
            )
            print(
                "[Canvas Shared][ContextResolve] " +
                "branch=\(branch) " +
                "viewportPoint=\(describeContextResolverPoint(viewportPoint)) " +
                "worldPoint=\(describeContextResolverPoint(invocationWorldPoint)) " +
                "viewportBounds=\(describeContextResolverRect(renderSnapshot.viewportBounds)) " +
                "visibleWorldRect=\(describeContextResolverRect(renderSnapshot.visibleWorldRect)) " +
                "selectedItemID=\(describeContextResolverItemID(selectedItemID)) " +
                "sceneHitItemID=\(describeContextResolverItemID(sceneHitItemID)) " +
                "renderItems=\(renderSnapshot.items.count) " +
                "editOverlay=\(editOverlayDescription) " +
                context.debugSummary
            )
            return context
        }

        if let editOverlayHitTarget = editOverlayHitTester.resolve(
            at: viewportPoint,
            renderSnapshot: renderSnapshot,
            metrics: interactionMetrics
        ) {
            return finalize(
                branch: contextResolverBranch(for: editOverlayHitTarget),
                resolvedTarget: resolvedTarget(from: editOverlayHitTarget)
            )
        }

        if isInlineEditModeActive {
            return finalize(
                branch: "inlineEditBlank",
                resolvedTarget: ResolvedTarget(targetKind: .blank)
            )
        }

        guard let itemID = scene.topmostBoardItemID(containing: invocationWorldPoint) else {
            return finalize(
                branch: "blank",
                resolvedTarget: ResolvedTarget(targetKind: .blank)
            )
        }

        let targetKind: CanvasContextMenuTargetKind =
            itemID == selectedItemID ? .selectedItemBody : .unselectedItemBody

        return finalize(
            branch: "itemBody",
            resolvedTarget: ResolvedTarget(
                targetKind: targetKind,
                targetItemID: itemID,
                anchorRect: itemAnchorRect(
                    for: itemID,
                    renderSnapshot: renderSnapshot
                )
            ),
            sceneHitItemID: itemID
        )
    }

    private func contextResolverBranch(
        for hitTarget: CanvasEditOverlayHitTarget
    ) -> String {
        switch hitTarget.kind {
        case .rotateHandle, .selectionHandle, .cropHandle:
            return "editHandle"
        case .cropTranslationArea:
            return hitTarget.kind.debugName
        }
    }

    private func resolvedTarget(
        from hitTarget: CanvasEditOverlayHitTarget
    ) -> ResolvedTarget {
        let targetKind: CanvasContextMenuTargetKind
        switch hitTarget.kind {
        case .rotateHandle:
            targetKind = .rotateHandle
        case let .selectionHandle(role):
            targetKind = .selectionHandle(role: role)
        case let .cropHandle(role):
            targetKind = .cropHandle(role: role)
        case .cropTranslationArea:
            // Phase 3 expands the shared translation area, but the outward
            // context still reports .cropOutline until controller/menu paths
            // are fully migrated in later stages.
            targetKind = .cropOutline
        }

        return ResolvedTarget(
            targetKind: targetKind,
            editOverlayHitTargetKind: hitTarget.kind,
            targetItemID: hitTarget.itemID,
            anchorRect: hitTarget.anchorRect
        )
    }

    private func itemAnchorRect(
        for itemID: CanvasItemID,
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
        selectedItemID: CanvasItemID?,
        isInlineEditModeActive: Bool,
        isInlineCropModeActive: Bool
    ) -> CanvasContextMenuContext {
        CanvasContextMenuContext(
            invocationViewportPoint: viewportPoint,
            invocationWorldPoint: worldPoint,
            targetKind: resolvedTarget.targetKind,
            editOverlayHitTargetKind: resolvedTarget.editOverlayHitTargetKind,
            targetItemID: resolvedTarget.targetItemID,
            anchorRect: resolvedTarget.anchorRect,
            selectedItemID: selectedItemID,
            isInlineEditModeActive: isInlineEditModeActive,
            isInlineCropModeActive: isInlineCropModeActive
        )
    }

    private struct ResolvedTarget {
        let targetKind: CanvasContextMenuTargetKind
        var editOverlayHitTargetKind: CanvasEditOverlayHitTargetKind? = nil
        var targetItemID: CanvasItemID? = nil
        var anchorRect: CGRect? = nil
    }
}

private func describeContextResolverPoint(_ point: CGPoint) -> String {
    "{\(formatContextResolverValue(point.x)), \(formatContextResolverValue(point.y))}"
}

private func describeContextResolverRect(_ rect: CGRect) -> String {
    "{{\(formatContextResolverValue(rect.origin.x)), \(formatContextResolverValue(rect.origin.y))}, {\(formatContextResolverValue(rect.size.width)), \(formatContextResolverValue(rect.size.height))}}"
}

private func describeContextResolverItemID(_ itemID: CanvasItemID?) -> String {
    itemID?.uuidString ?? "nil"
}

private func describeContextResolverOverlay(_ overlay: CanvasEditRenderOverlay?) -> String {
    guard let overlay else {
        return "nil"
    }

    return "itemID=\(overlay.itemID.uuidString) kind=\(String(describing: overlay.kind)) activeScreenQuad=\(describeContextResolverRect(overlay.activeScreenQuad.boundingRect.standardized))"
}

private func formatContextResolverValue(_ value: CGFloat) -> String {
    String(format: "%.2f", Double(value))
}
