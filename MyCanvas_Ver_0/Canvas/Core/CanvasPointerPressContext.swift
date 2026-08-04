import CoreGraphics
import Foundation

enum CanvasPointerTargetKind {
    case rotateHandle
    case groupRotateHandle
    case cropHandle(role: CanvasCropHandleRole)
    case cropTranslationArea
    case selectionHandle(role: CanvasSelectionHandleRole)
    case groupSelectionHandle(role: CanvasSelectionHandleRole)
    case arrowEndpointHandle(role: CanvasArrowEndpointRole)
    case selectionTranslationArea
    case selectedItemBody
    case unselectedItemBody
    case groupFrameBody
    case groupFrameResizeHandle(role: CanvasSelectionHandleRole)
    case blank

    var debugName: String {
        switch self {
        case .rotateHandle:
            return "rotateHandle"
        case .groupRotateHandle:
            return "groupRotateHandle"
        case let .cropHandle(role):
            return "cropHandle(\(String(describing: role)))"
        case .cropTranslationArea:
            return "cropTranslationArea"
        case let .selectionHandle(role):
            return "selectionHandle(\(String(describing: role)))"
        case let .groupSelectionHandle(role):
            return "groupSelectionHandle(\(String(describing: role)))"
        case let .arrowEndpointHandle(role):
            return "arrowEndpointHandle(\(String(describing: role)))"
        case .selectionTranslationArea:
            return "selectionTranslationArea"
        case .selectedItemBody:
            return "selectedItemBody"
        case .unselectedItemBody:
            return "unselectedItemBody"
        case .groupFrameBody:
            return "groupFrameBody"
        case let .groupFrameResizeHandle(role):
            return "groupFrameResizeHandle(\(String(describing: role)))"
        case .blank:
            return "blank"
        }
    }
}

struct CanvasPointerPressContext {
    let invocationViewportPoint: CGPoint
    let invocationWorldPoint: CGPoint
    let targetKind: CanvasPointerTargetKind
    let targetItemID: CanvasItemID?
    let targetGroupID: CanvasItemGroupID?
    let targetHandleIdentity: CanvasEditHandleIdentity?
    let anchorRect: CGRect?
}
