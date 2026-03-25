import CoreGraphics
import Foundation

enum CanvasPointerTargetKind {
    case rotateHandle
    case cropHandle(role: CanvasCropHandleRole)
    case cropTranslationArea
    case selectionHandle(role: CanvasSelectionHandleRole)
    case selectedItemBody
    case unselectedItemBody
    case blank

    var debugName: String {
        switch self {
        case .rotateHandle:
            return "rotateHandle"
        case let .cropHandle(role):
            return "cropHandle(\(String(describing: role)))"
        case .cropTranslationArea:
            return "cropTranslationArea"
        case let .selectionHandle(role):
            return "selectionHandle(\(String(describing: role)))"
        case .selectedItemBody:
            return "selectedItemBody"
        case .unselectedItemBody:
            return "unselectedItemBody"
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
    let anchorRect: CGRect?
}
