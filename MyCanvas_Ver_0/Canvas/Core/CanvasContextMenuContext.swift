import CoreGraphics
import Foundation

enum CanvasContextMenuTargetKind {
    case rotateHandle
    case groupRotateHandle
    case cropHandle(role: CanvasCropHandleRole)
    case cropOutline
    case selectionHandle(role: CanvasSelectionHandleRole)
    case groupSelectionHandle(role: CanvasSelectionHandleRole)
    case selectedItemBody
    case unselectedItemBody
    case blank

    var isEditHandle: Bool {
        switch self {
        case .rotateHandle,
             .groupRotateHandle,
             .cropHandle,
             .selectionHandle,
             .groupSelectionHandle:
            return true
        case .cropOutline, .selectedItemBody, .unselectedItemBody, .blank:
            return false
        }
    }

    var debugName: String {
        switch self {
        case .rotateHandle:
            return "rotateHandle"
        case .groupRotateHandle:
            return "groupRotateHandle"
        case let .cropHandle(role):
            return "cropHandle(\(String(describing: role)))"
        case .cropOutline:
            return "cropOutline"
        case let .selectionHandle(role):
            return "selectionHandle(\(String(describing: role)))"
        case let .groupSelectionHandle(role):
            return "groupSelectionHandle(\(String(describing: role)))"
        case .selectedItemBody:
            return "selectedItemBody"
        case .unselectedItemBody:
            return "unselectedItemBody"
        case .blank:
            return "blank"
        }
    }
}

struct CanvasContextMenuContext {
    let invocationViewportPoint: CGPoint
    let invocationWorldPoint: CGPoint
    let targetKind: CanvasContextMenuTargetKind
    let editOverlayHitTargetKind: CanvasEditOverlayHitTargetKind?
    let targetItemID: CanvasItemID?
    let anchorRect: CGRect?
    let currentSelectedItemIDs: [CanvasItemID]
    let currentPrimarySelectedItemID: CanvasItemID?
    let effectiveSelectedItemIDs: [CanvasItemID]
    let effectivePrimarySelectedItemID: CanvasItemID?
    let operatesOnCurrentSelection: Bool
    let isInlineEditModeActive: Bool
    let isInlineCropModeActive: Bool

    init(
        invocationViewportPoint: CGPoint,
        invocationWorldPoint: CGPoint,
        targetKind: CanvasContextMenuTargetKind,
        editOverlayHitTargetKind: CanvasEditOverlayHitTargetKind?,
        targetItemID: CanvasItemID?,
        anchorRect: CGRect?,
        currentSelectedItemIDs: [CanvasItemID] = [],
        currentPrimarySelectedItemID: CanvasItemID? = nil,
        effectiveSelectedItemIDs: [CanvasItemID]? = nil,
        effectivePrimarySelectedItemID: CanvasItemID? = nil,
        operatesOnCurrentSelection: Bool? = nil,
        isInlineEditModeActive: Bool,
        isInlineCropModeActive: Bool
    ) {
        self.invocationViewportPoint = invocationViewportPoint
        self.invocationWorldPoint = invocationWorldPoint
        self.targetKind = targetKind
        self.editOverlayHitTargetKind = editOverlayHitTargetKind
        self.targetItemID = targetItemID
        self.anchorRect = anchorRect
        let normalizedCurrentSelection = normalizeCanvasSelectionState(
            selectedItemIDs: currentSelectedItemIDs,
            primarySelectedItemID: currentPrimarySelectedItemID
        )
        self.currentSelectedItemIDs = normalizedCurrentSelection.selectedItemIDs
        self.currentPrimarySelectedItemID = normalizedCurrentSelection.primarySelectedItemID
        let resolvedOperatesOnCurrentSelection =
            operatesOnCurrentSelection
            ?? CanvasContextMenuContext.defaultOperatesOnCurrentSelection(
                for: targetKind
            )
        self.operatesOnCurrentSelection = resolvedOperatesOnCurrentSelection
        let normalizedEffectiveSelection: CanvasNormalizedSelectionState<CanvasItemID>
        if let effectiveSelectedItemIDs {
            normalizedEffectiveSelection = normalizeCanvasSelectionState(
                selectedItemIDs: effectiveSelectedItemIDs,
                primarySelectedItemID: effectivePrimarySelectedItemID
            )
        } else if resolvedOperatesOnCurrentSelection {
            let fallbackSelectedItemIDs =
                normalizedCurrentSelection.selectedItemIDs.isEmpty
                ? targetItemID.map { [$0] } ?? []
                : normalizedCurrentSelection.selectedItemIDs
            let fallbackPrimarySelectedItemID =
                normalizedCurrentSelection.primarySelectedItemID ?? targetItemID
            normalizedEffectiveSelection = normalizeCanvasSelectionState(
                selectedItemIDs: fallbackSelectedItemIDs,
                primarySelectedItemID: fallbackPrimarySelectedItemID
            )
        } else if let targetItemID {
            normalizedEffectiveSelection = normalizeCanvasSelectionState(
                selectedItemIDs: [targetItemID],
                primarySelectedItemID: targetItemID
            )
        } else {
            normalizedEffectiveSelection = normalizeCanvasSelectionState(
                selectedItemIDs: [],
                primarySelectedItemID: nil
            )
        }
        self.effectiveSelectedItemIDs =
            normalizedEffectiveSelection.selectedItemIDs
        self.effectivePrimarySelectedItemID =
            normalizedEffectiveSelection.primarySelectedItemID
        self.isInlineEditModeActive = isInlineEditModeActive
        self.isInlineCropModeActive = isInlineCropModeActive
    }

    var selectedItemID: CanvasItemID? {
        currentPrimarySelectedItemID
    }

    var selectedItemIDs: [CanvasItemID] {
        currentSelectedItemIDs
    }

    var primarySelectedItemID: CanvasItemID? {
        currentPrimarySelectedItemID
    }

    var selectionCount: Int {
        currentSelectedItemIDs.count
    }

    var effectiveSelectionCount: Int {
        effectiveSelectedItemIDs.count
    }

    var singleEffectiveItemID: CanvasItemID? {
        effectiveSelectionCount == 1 ? effectivePrimarySelectedItemID : nil
    }

    var anchorPoint: CGPoint {
        switch targetKind {
        case .rotateHandle,
             .groupRotateHandle,
             .cropHandle,
             .selectionHandle,
             .groupSelectionHandle:
            guard let anchorRect else {
                return invocationViewportPoint
            }

            return CGPoint(
                x: anchorRect.midX,
                y: anchorRect.midY
            )
        case .cropOutline, .selectedItemBody, .unselectedItemBody, .blank:
            // Body/outline menus should follow the actual invocation point instead
            // of the item's geometric center so the menu feels attached to the click.
            return invocationViewportPoint
        }
    }

    var debugSummary: String {
        [
            "target=\(targetKind.debugName)",
            "targetsCurrentSelection=\(operatesOnCurrentSelection)",
            "overlayTarget=\(editOverlayHitTargetKind?.debugName ?? "nil")",
            "invocationViewportPoint=\(contextMenuDescribe(invocationViewportPoint))",
            "invocationWorldPoint=\(contextMenuDescribe(invocationWorldPoint))",
            "anchorRect=\(anchorRect.map(contextMenuDescribe) ?? "nil")",
            "anchorPoint=\(contextMenuDescribe(anchorPoint))",
            "targetItemID=\(targetItemID?.uuidString ?? "nil")",
            "currentSelectedItemIDs=\(contextMenuDescribe(currentSelectedItemIDs))",
            "currentPrimarySelectedItemID=\(currentPrimarySelectedItemID?.uuidString ?? "nil")",
            "effectiveSelectedItemIDs=\(contextMenuDescribe(effectiveSelectedItemIDs))",
            "effectivePrimarySelectedItemID=\(effectivePrimarySelectedItemID?.uuidString ?? "nil")",
            "inlineEdit=\(isInlineEditModeActive)",
            "inlineCrop=\(isInlineCropModeActive)"
        ].joined(separator: " ")
    }

    private static func defaultOperatesOnCurrentSelection(
        for targetKind: CanvasContextMenuTargetKind
    ) -> Bool {
        switch targetKind {
        case .rotateHandle,
             .groupRotateHandle,
             .cropHandle,
             .cropOutline,
             .selectionHandle,
             .groupSelectionHandle,
             .selectedItemBody:
            return true
        case .unselectedItemBody, .blank:
            return false
        }
    }
}

private func contextMenuDescribe(_ point: CGPoint) -> String {
    "{\(contextMenuFormat(point.x)), \(contextMenuFormat(point.y))}"
}

private func contextMenuDescribe(_ rect: CGRect) -> String {
    "{{\(contextMenuFormat(rect.origin.x)), \(contextMenuFormat(rect.origin.y))}, {\(contextMenuFormat(rect.size.width)), \(contextMenuFormat(rect.size.height))}}"
}

private func contextMenuDescribe(_ itemIDs: [CanvasItemID]) -> String {
    "[\(itemIDs.map(\.uuidString).joined(separator: ","))]"
}

private func contextMenuFormat(_ value: CGFloat) -> String {
    String(format: "%.2f", Double(value))
}
