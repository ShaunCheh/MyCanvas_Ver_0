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

    var debugName: String {
        switch self {
        case .rotateHandle:
            return "rotateHandle"
        case let .cropHandle(role):
            return "cropHandle(\(String(describing: role)))"
        case .cropOutline:
            return "cropOutline"
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
        switch targetKind {
        case .rotateHandle, .cropHandle, .selectionHandle:
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
            "invocationViewportPoint=\(contextMenuDescribe(invocationViewportPoint))",
            "invocationWorldPoint=\(contextMenuDescribe(invocationWorldPoint))",
            "anchorRect=\(anchorRect.map(contextMenuDescribe) ?? "nil")",
            "anchorPoint=\(contextMenuDescribe(anchorPoint))",
            "targetItemID=\(targetItemID?.uuidString ?? "nil")",
            "selectedItemID=\(selectedItemID?.uuidString ?? "nil")",
            "inlineEdit=\(isInlineEditModeActive)",
            "inlineCrop=\(isInlineCropModeActive)"
        ].joined(separator: " ")
    }
}

private func contextMenuDescribe(_ point: CGPoint) -> String {
    "{\(contextMenuFormat(point.x)), \(contextMenuFormat(point.y))}"
}

private func contextMenuDescribe(_ rect: CGRect) -> String {
    "{{\(contextMenuFormat(rect.origin.x)), \(contextMenuFormat(rect.origin.y))}, {\(contextMenuFormat(rect.size.width)), \(contextMenuFormat(rect.size.height))}}"
}

private func contextMenuFormat(_ value: CGFloat) -> String {
    String(format: "%.2f", Double(value))
}
