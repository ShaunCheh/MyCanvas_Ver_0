import CoreGraphics
import Foundation

enum CanvasToolbarTransitionGeometry {
    static func collapsedFrame(from visibleFrame: CGRect) -> CGRect {
        let origin = finiteOrigin(from: visibleFrame.origin)
        let edge = collapsedSquareEdge(from: visibleFrame)
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: edge,
            height: edge
        ).standardized
    }

    static func offscreenFrame(
        from collapsedFrame: CGRect,
        safeBounds: CGRect
    ) -> CGRect {
        let baseFrame = sanitizedRectOrFallback(
            collapsedFrame,
            fallbackOrigin: finiteOrigin(from: collapsedFrame.origin),
            fallbackSize: CGSize(
                width: collapsedSquareEdge(from: collapsedFrame),
                height: collapsedSquareEdge(from: collapsedFrame)
            )
        )
        let safeBoundsMaxX = CanvasChromeLayoutGeometry
            .sanitizedRect(safeBounds)?
            .maxX ?? baseFrame.maxX
        return CGRect(
            x: max(baseFrame.minX, safeBoundsMaxX),
            y: baseFrame.minY,
            width: baseFrame.width,
            height: baseFrame.height
        ).standardized
    }

    static func presentation(
        for stage: CanvasToolbarTransitionStage,
        context: CanvasToolbarTransitionContext
    ) -> CanvasToolbarTransitionPresentation {
        let visibleState = context.visibleSnapshot.state
        let frames = normalizedFrames(from: context)
        let minimumScale = context.configuration.minimumContentScale

        switch stage {
        case .steadyVisible:
            return CanvasToolbarTransitionPresentation(
                frame: frames.visibleFrame,
                itemStates: visibleState.items,
                showsBackground: visibleState.showsBackground,
                contentAlpha: 1,
                contentScale: 1,
                keepsHostVisible: true,
                isInteractive: true
            )

        case let .collapsing(progress):
            let t = clamped(progress)
            return CanvasToolbarTransitionPresentation(
                frame: interpolatedRect(
                    from: frames.visibleFrame,
                    to: frames.collapsedFrame,
                    progress: t
                ),
                itemStates: visibleState.items,
                showsBackground: visibleState.showsBackground,
                contentAlpha: interpolatedValue(
                    from: 1,
                    to: 0,
                    progress: t
                ),
                contentScale: interpolatedValue(
                    from: 1,
                    to: minimumScale,
                    progress: t
                ),
                keepsHostVisible: true,
                isInteractive: false
            )

        case let .exiting(progress):
            let t = clamped(progress)
            return CanvasToolbarTransitionPresentation(
                frame: interpolatedRect(
                    from: frames.collapsedFrame,
                    to: frames.offscreenFrame,
                    progress: t
                ),
                itemStates: visibleState.items,
                showsBackground: visibleState.showsBackground,
                contentAlpha: 0,
                contentScale: minimumScale,
                keepsHostVisible: true,
                isInteractive: false
            )

        case .hidden:
            return CanvasToolbarTransitionPresentation(
                frame: frames.offscreenFrame,
                itemStates: visibleState.items,
                showsBackground: visibleState.showsBackground,
                contentAlpha: 0,
                contentScale: minimumScale,
                keepsHostVisible: false,
                isInteractive: false
            )

        case let .entering(progress):
            let t = clamped(progress)
            return CanvasToolbarTransitionPresentation(
                frame: interpolatedRect(
                    from: frames.offscreenFrame,
                    to: frames.collapsedFrame,
                    progress: t
                ),
                itemStates: visibleState.items,
                showsBackground: visibleState.showsBackground,
                contentAlpha: 0,
                contentScale: minimumScale,
                keepsHostVisible: true,
                isInteractive: false
            )

        case let .expanding(progress):
            let t = clamped(progress)
            return CanvasToolbarTransitionPresentation(
                frame: interpolatedRect(
                    from: frames.collapsedFrame,
                    to: frames.visibleFrame,
                    progress: t
                ),
                itemStates: visibleState.items,
                showsBackground: visibleState.showsBackground,
                contentAlpha: interpolatedValue(
                    from: 0,
                    to: 1,
                    progress: t
                ),
                contentScale: interpolatedValue(
                    from: minimumScale,
                    to: 1,
                    progress: t
                ),
                keepsHostVisible: true,
                isInteractive: false
            )
        }
    }

    private static func normalizedFrames(
        from context: CanvasToolbarTransitionContext
    ) -> CanvasToolbarTransitionFrames {
        let visibleFrame = sanitizedRectOrFallback(
            context.frames.visibleFrame,
            fallbackOrigin: finiteOrigin(from: context.visibleSnapshot.frame.origin),
            fallbackSize: CGSize(
                width: collapsedSquareEdge(from: context.visibleSnapshot.frame),
                height: collapsedSquareEdge(from: context.visibleSnapshot.frame)
            )
        )
        let collapsedFrame = sanitizedRectOrFallback(
            context.frames.collapsedFrame,
            fallbackOrigin: visibleFrame.origin,
            fallbackSize: CGSize(
                width: visibleFrame.width,
                height: visibleFrame.width
            )
        )
        let offscreenFrame = sanitizedRectOrFallback(
            context.frames.offscreenFrame,
            fallbackOrigin: CGPoint(
                x: collapsedFrame.maxX,
                y: collapsedFrame.minY
            ),
            fallbackSize: collapsedFrame.size
        )
        return CanvasToolbarTransitionFrames(
            visibleFrame: visibleFrame,
            collapsedFrame: collapsedFrame,
            offscreenFrame: offscreenFrame
        )
    }

    private static func collapsedSquareEdge(from visibleFrame: CGRect) -> CGFloat {
        if let sanitizedVisibleFrame = CanvasChromeLayoutGeometry.sanitizedRect(
            visibleFrame
        ) {
            return sanitizedVisibleFrame.width
        }

        return CanvasToolbarMeasurement.measuredContentSize(
            forMeasuredStackSize: CGSize(
                width: CanvasToolbarChromeMetrics.buttonEdge,
                height: CanvasToolbarChromeMetrics.buttonEdge
            )
        ).width
    }

    private static func sanitizedRectOrFallback(
        _ rect: CGRect,
        fallbackOrigin: CGPoint,
        fallbackSize: CGSize
    ) -> CGRect {
        if let sanitizedRect = CanvasChromeLayoutGeometry.sanitizedRect(rect) {
            return sanitizedRect
        }

        let sanitizedFallbackSize = CanvasChromeLayoutGeometry.sanitizedSize(
            fallbackSize
        )
        return CGRect(
            origin: fallbackOrigin,
            size: CGSize(
                width: max(sanitizedFallbackSize.width, 0),
                height: max(sanitizedFallbackSize.height, 0)
            )
        ).standardized
    }

    private static func finiteOrigin(from origin: CGPoint) -> CGPoint {
        CGPoint(
            x: origin.x.isFinite ? origin.x : 0,
            y: origin.y.isFinite ? origin.y : 0
        )
    }

    private static func interpolatedRect(
        from start: CGRect,
        to end: CGRect,
        progress: CGFloat
    ) -> CGRect {
        let t = clamped(progress)
        return CGRect(
            x: interpolatedValue(from: start.minX, to: end.minX, progress: t),
            y: interpolatedValue(from: start.minY, to: end.minY, progress: t),
            width: interpolatedValue(from: start.width, to: end.width, progress: t),
            height: interpolatedValue(from: start.height, to: end.height, progress: t)
        ).standardized
    }

    private static func interpolatedValue(
        from start: CGFloat,
        to end: CGFloat,
        progress: CGFloat
    ) -> CGFloat {
        let t = clamped(progress)
        return start + ((end - start) * t)
    }

    private static func clamped(_ progress: CGFloat) -> CGFloat {
        min(max(progress, 0), 1)
    }
}
