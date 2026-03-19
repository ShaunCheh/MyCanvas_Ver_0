import Foundation

enum CanvasToolbarDockEdge: CaseIterable {
    case top
    case bottom
    case leading
    case trailing

    var prefersHorizontalButtonLayout: Bool {
        switch self {
        case .top, .bottom:
            return true
        case .leading, .trailing:
            return false
        }
    }
}
