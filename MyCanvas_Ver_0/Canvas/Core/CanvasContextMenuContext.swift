import CoreGraphics
import Foundation

enum CanvasContextMenuTargetKind {
    case rotateHandle
    case cropHandle(role: CanvasCropHandleRole)
    case cropOutline
    case selectionHandle(role: CanvasSelectionHandleRole)
    case selectedItemBody
    case unselectedItemBody
    case blank

    var isEditHandle: Bool {
        switch self {
        case .rotateHandle, .cropHandle, .selectionHandle:
            return true
        case .cropOutline, .selectedItemBody, .unselectedItemBody, .blank:
            return false
        }
    }
}

struct CanvasContextMenuContext {
    let invocationViewportPoint: CGPoint
    let invocationWorldPoint: CGPoint
    let targetKind: CanvasContextMenuTargetKind
    let targetItemID: CanvasImageItemID?
    let anchorRect: CGRect?
    let selectedItemID: CanvasImageItemID?
    let isInlineEditModeActive: Bool
    let isInlineCropModeActive: Bool

    var anchorPoint: CGPoint {
        guard let anchorRect else {
            return invocationViewportPoint
        }

        return CGPoint(
            x: anchorRect.midX,
            y: anchorRect.midY
        )
    }
}
