import CoreGraphics
import Foundation

enum CanvasToolbarTransitionDirection: Hashable, Sendable {
    case toReading
    case toEditing
}

enum CanvasToolbarTransitionStage: Hashable, Sendable {
    case steadyVisible
    case collapsing(progress: CGFloat)
    case exiting(progress: CGFloat)
    case hidden
    case entering(progress: CGFloat)
    case expanding(progress: CGFloat)
}

struct CanvasToolbarTransitionConfiguration: Hashable, Sendable {
    var collapseDuration: TimeInterval
    var slideDuration: TimeInterval
    var minimumContentScale: CGFloat

    init(
        collapseDuration: TimeInterval = 0.18,
        slideDuration: TimeInterval = 0.14,
        minimumContentScale: CGFloat = 0.78
    ) {
        self.collapseDuration = max(collapseDuration, 0)
        self.slideDuration = max(slideDuration, 0)
        self.minimumContentScale = min(
            max(minimumContentScale, 0),
            1
        )
    }
}

struct CanvasToolbarTransitionSnapshot: Hashable, Sendable {
    var state: CanvasToolbarState
    var frame: CGRect
}

struct CanvasToolbarTransitionFrames: Hashable, Sendable {
    var visibleFrame: CGRect
    var collapsedFrame: CGRect
    var offscreenFrame: CGRect
}

struct CanvasToolbarTransitionContext: Hashable, Sendable {
    var direction: CanvasToolbarTransitionDirection
    var visibleSnapshot: CanvasToolbarTransitionSnapshot
    var settledState: CanvasToolbarState
    var frames: CanvasToolbarTransitionFrames
    var configuration: CanvasToolbarTransitionConfiguration
}

struct CanvasToolbarTransitionPresentation: Hashable, Sendable {
    var frame: CGRect
    var itemStates: [CanvasToolbarItemState]
    var showsBackground: Bool
    var contentAlpha: CGFloat
    var contentScale: CGFloat
    var keepsHostVisible: Bool
    var isInteractive: Bool
}

struct CanvasToolbarTransitionRuntime: Hashable, Sendable {
    var context: CanvasToolbarTransitionContext
    var stage: CanvasToolbarTransitionStage
    var currentPresentation: CanvasToolbarTransitionPresentation
    var pendingLayoutReconcile: Bool
}
