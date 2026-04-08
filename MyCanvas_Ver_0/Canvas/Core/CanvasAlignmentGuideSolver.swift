import CoreGraphics
import Foundation

enum CanvasAlignmentCoordinateAxis: CaseIterable {
    case x
    case y
}

enum CanvasAlignmentGuideOrientation: CaseIterable {
    case horizontal
    case vertical
}

enum CanvasAlignmentAnchor: CaseIterable {
    case left
    case centerX
    case right
    case top
    case centerY
    case bottom

    var axis: CanvasAlignmentCoordinateAxis {
        switch self {
        case .left, .centerX, .right:
            return .x
        case .top, .centerY, .bottom:
            return .y
        }
    }

    var guideOrientation: CanvasAlignmentGuideOrientation {
        switch axis {
        case .x:
            return .vertical
        case .y:
            return .horizontal
        }
    }

    func coordinate(in rect: CGRect) -> CGFloat {
        let standardizedRect = rect.standardized
        switch self {
        case .left:
            return standardizedRect.minX
        case .centerX:
            return standardizedRect.midX
        case .right:
            return standardizedRect.maxX
        case .top:
            return standardizedRect.minY
        case .centerY:
            return standardizedRect.midY
        case .bottom:
            return standardizedRect.maxY
        }
    }
}

enum CanvasAlignmentReferenceSource: Equatable {
    case board
    case item(CanvasItemID)
}

struct CanvasAlignmentGuide: Equatable {
    let orientation: CanvasAlignmentGuideOrientation
    let worldStart: CGPoint
    let worldEnd: CGPoint
    let movingAnchor: CanvasAlignmentAnchor
    let referenceAnchor: CanvasAlignmentAnchor
    let referenceSource: CanvasAlignmentReferenceSource
}

struct CanvasAlignmentMatch: Equatable {
    let movingAnchor: CanvasAlignmentAnchor
    let referenceAnchor: CanvasAlignmentAnchor
    let referenceSource: CanvasAlignmentReferenceSource
    let referenceCoordinate: CGFloat
    let distanceInWorld: CGFloat
}

struct CanvasAlignmentSolverConfiguration: Equatable {
    let snapThresholdInViewport: CGFloat
    let searchPaddingInViewport: CGFloat

    static let `default` = CanvasAlignmentSolverConfiguration(
        snapThresholdInViewport: 8,
        searchPaddingInViewport: 160
    )
}

struct CanvasAlignmentSolveRequest {
    let movingItemID: CanvasItemID
    let proposedCenter: CGPoint
    let scene: CanvasScene
    let boardState: CanvasBoardState?
    let camera: CanvasCamera
}

struct CanvasAlignmentSolveResult {
    let resolvedCenter: CGPoint
    let interactionState: CanvasAlignmentInteractionState?

    static func passthrough(
        proposedCenter: CGPoint
    ) -> CanvasAlignmentSolveResult {
        CanvasAlignmentSolveResult(
            resolvedCenter: proposedCenter,
            interactionState: nil
        )
    }
}

// Alignment solving stays axis-aligned in v1: all snap candidates come from
// board/item world frames plus centers, not rotated quads or transformed edges.
struct CanvasAlignmentGuideSolver {
    var configuration: CanvasAlignmentSolverConfiguration = .default

    func solve(
        _ request: CanvasAlignmentSolveRequest
    ) -> CanvasAlignmentSolveResult {
        CanvasAlignmentSolveResult.passthrough(
            proposedCenter: request.proposedCenter
        )
    }
}

extension CanvasCamera {
    func worldDistance(
        forViewportDistance viewportDistance: CGFloat
    ) -> CGFloat {
        guard zoomScale > 0 else {
            return viewportDistance
        }

        return viewportDistance / zoomScale
    }

    func expandedVisibleWorldRect(
        paddingInViewport viewportPadding: CGFloat
    ) -> CGRect {
        let paddingInWorld = worldDistance(
            forViewportDistance: max(viewportPadding, 0)
        )
        return visibleWorldRect.insetBy(
            dx: -paddingInWorld,
            dy: -paddingInWorld
        )
    }
}
