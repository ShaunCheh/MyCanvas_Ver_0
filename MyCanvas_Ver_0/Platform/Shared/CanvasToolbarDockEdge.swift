import Foundation

enum CanvasToolbarAxis: String, Sendable {
    case horizontal
    case vertical
}

enum CanvasToolbarDockEdge: String, CaseIterable, Sendable {
    case top
    case bottom
    case leading
    case trailing

    var preferredAxis: CanvasToolbarAxis {
        switch self {
        case .top, .bottom:
            return .horizontal
        case .leading, .trailing:
            return .vertical
        }
    }

    var prefersHorizontalButtonLayout: Bool {
        preferredAxis == .horizontal
    }
}
