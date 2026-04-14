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

    func resolvePointerTarget(
        at viewportPoint: CGPoint,
        scene: CanvasScene,
        camera: CanvasCamera,
        renderSnapshot: CanvasRenderSnapshot,
        selectedItemIDs: [CanvasItemID],
        isInlineEditModeActive: Bool,
        isReadingModeActive: Bool,
        interactionMetrics: CanvasContextResolverMetrics
    ) -> CanvasPointerPressContext {
        let invocationWorldPoint = camera.viewportToWorld(viewportPoint)
        let resolution = resolveTarget(
            at: viewportPoint,
            invocationWorldPoint: invocationWorldPoint,
            scene: scene,
            renderSnapshot: renderSnapshot,
            selectedItemIDs: Set(selectedItemIDs),
            isInlineEditModeActive: isInlineEditModeActive,
            isReadingModeActive: isReadingModeActive,
            interactionMetrics: interactionMetrics
        )

        return makePointerPressContext(
            viewportPoint: viewportPoint,
            worldPoint: invocationWorldPoint,
            resolvedTarget: resolution.resolvedTarget
        )
    }

    func resolveContext(
        at viewportPoint: CGPoint,
        scene: CanvasScene,
        camera: CanvasCamera,
        renderSnapshot: CanvasRenderSnapshot,
        selectedItemIDs: [CanvasItemID],
        primarySelectedItemID: CanvasItemID?,
        isInlineEditModeActive: Bool,
        isInlineCropModeActive: Bool,
        isReadingModeActive: Bool,
        interactionMetrics: CanvasContextResolverMetrics
    ) -> CanvasContextMenuContext {
        let invocationWorldPoint = camera.viewportToWorld(viewportPoint)
        let editOverlayDescription = describeContextResolverOverlay(renderSnapshot.editOverlay)
        let resolution = resolveTarget(
            at: viewportPoint,
            invocationWorldPoint: invocationWorldPoint,
            scene: scene,
            renderSnapshot: renderSnapshot,
            selectedItemIDs: Set(selectedItemIDs),
            isInlineEditModeActive: isInlineEditModeActive,
            isReadingModeActive: isReadingModeActive,
            interactionMetrics: interactionMetrics
        )

        let context = makeContext(
            viewportPoint: viewportPoint,
            worldPoint: invocationWorldPoint,
            resolvedTarget: resolution.resolvedTarget,
            selectedItemIDs: selectedItemIDs,
            primarySelectedItemID: primarySelectedItemID,
            isInlineEditModeActive: isInlineEditModeActive,
            isInlineCropModeActive: isInlineCropModeActive
        )
        print(
            "[Canvas Shared][ContextResolve] " +
            "branch=\(resolution.branch) " +
            "viewportPoint=\(describeContextResolverPoint(viewportPoint)) " +
            "worldPoint=\(describeContextResolverPoint(invocationWorldPoint)) " +
            "viewportBounds=\(describeContextResolverRect(renderSnapshot.viewportBounds)) " +
            "visibleWorldRect=\(describeContextResolverRect(renderSnapshot.visibleWorldRect)) " +
            "selectedItemID=\(describeContextResolverItemID(primarySelectedItemID)) " +
            "sceneHitItemID=\(describeContextResolverItemID(resolution.sceneHitItemID)) " +
            "renderItems=\(renderSnapshot.items.count) " +
            "editOverlay=\(editOverlayDescription) " +
            context.debugSummary
        )
        return context
    }

    private func resolveTarget(
        at viewportPoint: CGPoint,
        invocationWorldPoint: CGPoint,
        scene: CanvasScene,
        renderSnapshot: CanvasRenderSnapshot,
        selectedItemIDs: Set<CanvasItemID>,
        isInlineEditModeActive: Bool,
        isReadingModeActive: Bool,
        interactionMetrics: CanvasContextResolverMetrics
    ) -> ResolutionResult {
        if isReadingModeActive {
            let sceneHitItemID = scene.topmostBoardItemID(
                containing: invocationWorldPoint
            )
            return ResolutionResult(
                branch: sceneHitItemID == nil
                    ? "readingModeBlank"
                    : "readingModeItemSuppressed",
                resolvedTarget: ResolvedTarget(pointerTargetKind: .blank),
                sceneHitItemID: sceneHitItemID
            )
        }

        if let editOverlayHitTarget = editOverlayHitTester.resolve(
            at: viewportPoint,
            renderSnapshot: renderSnapshot,
            metrics: interactionMetrics
        ) {
            return ResolutionResult(
                branch: contextResolverBranch(for: editOverlayHitTarget),
                resolvedTarget: resolvedTarget(from: editOverlayHitTarget)
            )
        }

        if isInlineEditModeActive {
            return ResolutionResult(
                branch: "inlineEditBlank",
                resolvedTarget: ResolvedTarget(pointerTargetKind: .blank)
            )
        }

        guard let itemID = scene.topmostBoardItemID(containing: invocationWorldPoint) else {
            return ResolutionResult(
                branch: "blank",
                resolvedTarget: ResolvedTarget(pointerTargetKind: .blank)
            )
        }

        let targetKind: CanvasPointerTargetKind =
            selectedItemIDs.contains(itemID)
            ? .selectedItemBody
            : .unselectedItemBody

        return ResolutionResult(
            branch: "itemBody",
            resolvedTarget: ResolvedTarget(
                pointerTargetKind: targetKind,
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
        case .rotateHandle,
             .groupRotateHandle,
             .selectionHandle,
             .groupSelectionHandle,
             .cropHandle:
            return "editHandle"
        case .cropTranslationArea:
            return hitTarget.kind.debugName
        }
    }

    private func resolvedTarget(
        from hitTarget: CanvasEditOverlayHitTarget
    ) -> ResolvedTarget {
        let pointerTargetKind: CanvasPointerTargetKind
        switch hitTarget.kind {
        case .rotateHandle:
            pointerTargetKind = .rotateHandle
        case .groupRotateHandle:
            pointerTargetKind = .groupRotateHandle
        case let .selectionHandle(role):
            pointerTargetKind = .selectionHandle(role: role)
        case let .groupSelectionHandle(role):
            pointerTargetKind = .groupSelectionHandle(role: role)
        case let .cropHandle(role):
            pointerTargetKind = .cropHandle(role: role)
        case .cropTranslationArea:
            pointerTargetKind = .cropTranslationArea
        }

        return ResolvedTarget(
            pointerTargetKind: pointerTargetKind,
            editOverlayHitTargetKind: hitTarget.kind,
            targetItemID: hitTarget.itemID,
            anchorRect: hitTarget.anchorRect
        )
    }

    private func itemAnchorRect(
        for itemID: CanvasItemID,
        renderSnapshot: CanvasRenderSnapshot
    ) -> CGRect? {
        if let overlayAnchorRect = overlayAnchorRect(
            for: itemID,
            renderSnapshot: renderSnapshot
        ) {
            return overlayAnchorRect
        }

        return renderSnapshot.items
            .first(where: { $0.id == itemID })?
            .screenQuad
            .boundingRect
            .standardized
    }

    private func overlayAnchorRect(
        for itemID: CanvasItemID,
        renderSnapshot: CanvasRenderSnapshot
    ) -> CGRect? {
        guard let editOverlay = renderSnapshot.editOverlay else {
            return nil
        }

        switch editOverlay.kind {
        case .crop:
            guard editOverlay.itemID == itemID else {
                return nil
            }
            return editOverlay.activeScreenQuad.boundingRect.standardized
        case .selection:
            guard case let .selection(payload) = editOverlay.payload else {
                return nil
            }
            switch payload.subject {
            case let .singleItem(selectedItemID):
                guard selectedItemID == itemID else {
                    return nil
                }
                return editOverlay.activeScreenQuad.boundingRect.standardized
            case .group:
                return nil
            }
        }
    }

    private func makeContext(
        viewportPoint: CGPoint,
        worldPoint: CGPoint,
        resolvedTarget: ResolvedTarget,
        selectedItemIDs: [CanvasItemID],
        primarySelectedItemID: CanvasItemID?,
        isInlineEditModeActive: Bool,
        isInlineCropModeActive: Bool
    ) -> CanvasContextMenuContext {
        CanvasContextMenuContext(
            invocationViewportPoint: viewportPoint,
            invocationWorldPoint: worldPoint,
            targetKind: contextMenuTargetKind(
                for: resolvedTarget.pointerTargetKind
            ),
            editOverlayHitTargetKind: resolvedTarget.editOverlayHitTargetKind,
            targetItemID: resolvedTarget.targetItemID,
            anchorRect: resolvedTarget.anchorRect,
            currentSelectedItemIDs: selectedItemIDs,
            currentPrimarySelectedItemID: primarySelectedItemID,
            isInlineEditModeActive: isInlineEditModeActive,
            isInlineCropModeActive: isInlineCropModeActive
        )
    }

    private func makePointerPressContext(
        viewportPoint: CGPoint,
        worldPoint: CGPoint,
        resolvedTarget: ResolvedTarget
    ) -> CanvasPointerPressContext {
        CanvasPointerPressContext(
            invocationViewportPoint: viewportPoint,
            invocationWorldPoint: worldPoint,
            targetKind: resolvedTarget.pointerTargetKind,
            targetItemID: resolvedTarget.targetItemID,
            anchorRect: resolvedTarget.anchorRect
        )
    }

    private func contextMenuTargetKind(
        for pointerTargetKind: CanvasPointerTargetKind
    ) -> CanvasContextMenuTargetKind {
        switch pointerTargetKind {
        case .rotateHandle:
            return .rotateHandle
        case .groupRotateHandle:
            return .groupRotateHandle
        case let .cropHandle(role):
            return .cropHandle(role: role)
        case .cropTranslationArea:
            return .cropOutline
        case let .selectionHandle(role):
            return .selectionHandle(role: role)
        case let .groupSelectionHandle(role):
            return .groupSelectionHandle(role: role)
        case .selectedItemBody:
            return .selectedItemBody
        case .unselectedItemBody:
            return .unselectedItemBody
        case .blank:
            return .blank
        }
    }

    private struct ResolvedTarget {
        let pointerTargetKind: CanvasPointerTargetKind
        var editOverlayHitTargetKind: CanvasEditOverlayHitTargetKind? = nil
        var targetItemID: CanvasItemID? = nil
        var anchorRect: CGRect? = nil
    }

    private struct ResolutionResult {
        let branch: String
        let resolvedTarget: ResolvedTarget
        var sceneHitItemID: CanvasItemID? = nil
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
