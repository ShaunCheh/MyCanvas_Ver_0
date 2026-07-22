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
        offscreenFrame(
            from: collapsedFrame,
            safeBounds: safeBounds,
            placement: CanvasToolbarPlacement(preferredEdge: .trailing)
        )
    }

    static func offscreenFrame(
        from collapsedFrame: CGRect,
        safeBounds: CGRect,
        placement: CanvasToolbarPlacement
    ) -> CGRect {
        let baseFrame = sanitizedRectOrFallback(
            collapsedFrame,
            fallbackOrigin: finiteOrigin(from: collapsedFrame.origin),
            fallbackSize: CGSize(
                width: collapsedSquareEdge(from: collapsedFrame),
                height: collapsedSquareEdge(from: collapsedFrame)
            )
        )
        let sanitizedSafeBounds = CanvasChromeLayoutGeometry
            .sanitizedRect(safeBounds)
        let origin: CGPoint

        switch placement.preferredEdge {
        case .top:
            origin = CGPoint(
                x: baseFrame.minX,
                y: min(
                    baseFrame.minY,
                    (sanitizedSafeBounds?.minY ?? baseFrame.minY) - baseFrame.height
                )
            )
        case .bottom:
            origin = CGPoint(
                x: baseFrame.minX,
                y: max(
                    baseFrame.minY,
                    sanitizedSafeBounds?.maxY ?? baseFrame.maxY
                )
            )
        case .leading:
            origin = CGPoint(
                x: min(
                    baseFrame.minX,
                    (sanitizedSafeBounds?.minX ?? baseFrame.minX) - baseFrame.width
                ),
                y: baseFrame.minY
            )
        case .trailing:
            origin = CGPoint(
                x: max(
                    baseFrame.minX,
                    sanitizedSafeBounds?.maxX ?? baseFrame.maxX
                ),
                y: baseFrame.minY
            )
        }

        return CGRect(
            origin: origin,
            size: baseFrame.size
        ).standardized
    }

    static func hiddenFrame(
        for placement: CanvasToolbarPlacement,
        visibleFrame: CGRect?,
        safeBounds: CGRect,
        scale: CGFloat,
        baseChromeBlockers: [CanvasChromeBlocker],
        solver: CanvasToolbarPlacementSolver = CanvasToolbarPlacementSolver(),
        configuration: CanvasToolbarPlacementConfiguration = CanvasToolbarPlacementConfiguration()
    ) -> CGRect {
        let hiddenCollapsedFrame: CGRect
        if let visibleFrame,
           let sanitizedVisibleFrame = CanvasChromeLayoutGeometry.sanitizedRect(
               visibleFrame
           )
        {
            hiddenCollapsedFrame = collapsedFrame(from: sanitizedVisibleFrame)
        } else {
            hiddenCollapsedFrame = resolvedFallbackCollapsedFrame(
                for: placement,
                safeBounds: safeBounds,
                scale: scale,
                baseChromeBlockers: baseChromeBlockers,
                solver: solver,
                configuration: configuration
            )
        }

        return offscreenFrame(
            from: hiddenCollapsedFrame,
            safeBounds: safeBounds,
            placement: placement
        )
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
                contentAlpha: 1,
                contentScale: 1,
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
                contentAlpha: 1,
                contentScale: 1,
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
            return min(sanitizedVisibleFrame.width, sanitizedVisibleFrame.height)
        }

        return CanvasToolbarMeasurement.measuredContentSize(
            forMeasuredStackSize: CGSize(
                width: CanvasToolbarChromeMetrics.buttonEdge,
                height: CanvasToolbarChromeMetrics.buttonEdge
            )
        ).width
    }

    private static func resolvedFallbackCollapsedFrame(
        for placement: CanvasToolbarPlacement,
        safeBounds: CGRect,
        scale: CGFloat,
        baseChromeBlockers: [CanvasChromeBlocker],
        solver: CanvasToolbarPlacementSolver,
        configuration: CanvasToolbarPlacementConfiguration
    ) -> CGRect {
        let collapsedEdge = collapsedSquareEdge(from: .zero)
        let collapsedSize = CGSize(
            width: collapsedEdge,
            height: collapsedEdge
        )
        let fallbackFrame = fallbackCollapsedFrame(
            for: placement,
            size: collapsedSize,
            safeBounds: safeBounds,
            configuration: configuration
        )
        let layoutContext = CanvasChromeLayoutContext(
            safeBounds: safeBounds,
            toolbarPreferredPlacement: placement,
            toolbarMeasuredSize: collapsedSize,
            chromeBlockers: baseChromeBlockers
        )

        guard let resolvedFrame = solver.resolveFrame(
            in: layoutContext,
            configuration: configuration
        ).flatMap({
            CanvasChromeLayoutGeometry.pixelAlignedRectPreservingSize(
                $0,
                scale: scale
            )
        }) else {
            return fallbackFrame
        }

        return sanitizedRectOrFallback(
            resolvedFrame,
            fallbackOrigin: fallbackFrame.origin,
            fallbackSize: fallbackFrame.size
        )
    }

    private static func fallbackCollapsedFrame(
        for placement: CanvasToolbarPlacement,
        size: CGSize,
        safeBounds: CGRect,
        configuration: CanvasToolbarPlacementConfiguration
    ) -> CGRect {
        let collapsedSize = CanvasChromeLayoutGeometry.sanitizedSize(size)
        let layoutBounds = fallbackLayoutBounds(
            from: safeBounds,
            configuration: configuration
        )
        let leadingCoordinate: CGFloat

        switch placement.preferredEdge {
        case .top, .bottom:
            let centeredCoordinate = layoutBounds.midX - (collapsedSize.width / 2)
                + placement.offsetAlongEdge
            leadingCoordinate = clamped(
                centeredCoordinate,
                minValue: layoutBounds.minX,
                maxValue: layoutBounds.maxX - collapsedSize.width
            )
        case .leading, .trailing:
            let centeredCoordinate = layoutBounds.midY - (collapsedSize.height / 2)
                + placement.offsetAlongEdge
            leadingCoordinate = clamped(
                centeredCoordinate,
                minValue: layoutBounds.minY,
                maxValue: layoutBounds.maxY - collapsedSize.height
            )
        }

        switch placement.preferredEdge {
        case .top:
            return CGRect(
                x: leadingCoordinate,
                y: layoutBounds.minY,
                width: collapsedSize.width,
                height: collapsedSize.height
            ).standardized
        case .bottom:
            return CGRect(
                x: leadingCoordinate,
                y: layoutBounds.maxY - collapsedSize.height,
                width: collapsedSize.width,
                height: collapsedSize.height
            ).standardized
        case .leading:
            return CGRect(
                x: layoutBounds.minX,
                y: leadingCoordinate,
                width: collapsedSize.width,
                height: collapsedSize.height
            ).standardized
        case .trailing:
            return CGRect(
                x: layoutBounds.maxX - collapsedSize.width,
                y: leadingCoordinate,
                width: collapsedSize.width,
                height: collapsedSize.height
            ).standardized
        }
    }

    private static func fallbackLayoutBounds(
        from safeBounds: CGRect,
        configuration: CanvasToolbarPlacementConfiguration
    ) -> CGRect {
        let sanitizedSafeBounds = CanvasChromeLayoutGeometry.sanitizedRect(
            safeBounds
        ) ?? CGRect(
            x: 0,
            y: 0,
            width: collapsedSquareEdge(from: .zero),
            height: collapsedSquareEdge(from: .zero)
        )
        let inset = max(configuration.edgeInset, 0)

        if let sanitizedLayoutBounds = CanvasChromeLayoutGeometry.sanitizedRect(
            sanitizedSafeBounds.insetBy(dx: inset, dy: inset)
        ) {
            return sanitizedLayoutBounds
        }

        return sanitizedSafeBounds
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

    private static func clamped(
        _ value: CGFloat,
        minValue: CGFloat,
        maxValue: CGFloat
    ) -> CGFloat {
        guard value.isFinite else {
            return minValue.isFinite ? minValue : 0
        }

        guard minValue.isFinite, maxValue.isFinite else {
            return value
        }

        guard maxValue >= minValue else {
            return minValue
        }

        return min(max(value, minValue), maxValue)
    }
}
