import CoreGraphics
import Foundation

struct CanvasToolbarPlacementPassResult: Hashable, Sendable {
    var toolbarFrame: CGRect
    var chromeLayoutContext: CanvasChromeLayoutContext
}

enum CanvasToolbarPlacementPass {
    static func resolve(
        safeBounds: CGRect,
        toolbarPreferredPlacement: CanvasToolbarPlacement,
        toolbarMeasuredSize: CGSize,
        baseChromeBlockers: [CanvasChromeBlocker],
        scale: CGFloat,
        solver: CanvasToolbarPlacementSolver = CanvasToolbarPlacementSolver(),
        configuration: CanvasToolbarPlacementConfiguration = CanvasToolbarPlacementConfiguration()
    ) -> CanvasToolbarPlacementPassResult {
        let toolbarPlacementContext = makeChromeLayoutContext(
            safeBounds: safeBounds,
            toolbarPreferredPlacement: toolbarPreferredPlacement,
            toolbarMeasuredSize: toolbarMeasuredSize,
            chromeBlockers: baseChromeBlockers
        )
        let toolbarFrame = solver.resolveFrame(
            in: toolbarPlacementContext,
            configuration: configuration
        ).flatMap { frame in
            CanvasChromeLayoutGeometry.pixelAlignedRectPreservingSize(
                frame,
                scale: scale
            )
        } ?? .zero

        var chromeBlockers = baseChromeBlockers
        if let toolbarRect = CanvasChromeLayoutGeometry.sanitizedRect(
            toolbarFrame
        ) {
            chromeBlockers.append(
                CanvasChromeBlocker(
                    kind: .toolbar,
                    rect: toolbarRect
                )
            )
        }

        return CanvasToolbarPlacementPassResult(
            toolbarFrame: toolbarFrame,
            chromeLayoutContext: makeChromeLayoutContext(
                safeBounds: safeBounds,
                toolbarPreferredPlacement: toolbarPreferredPlacement,
                toolbarMeasuredSize: toolbarMeasuredSize,
                chromeBlockers: chromeBlockers
            )
        )
    }

    private static func makeChromeLayoutContext(
        safeBounds: CGRect,
        toolbarPreferredPlacement: CanvasToolbarPlacement,
        toolbarMeasuredSize: CGSize,
        chromeBlockers: [CanvasChromeBlocker]
    ) -> CanvasChromeLayoutContext {
        CanvasChromeLayoutContext(
            safeBounds: safeBounds,
            toolbarPreferredPlacement: toolbarPreferredPlacement,
            toolbarMeasuredSize: toolbarMeasuredSize,
            chromeBlockers: chromeBlockers
        )
    }
}
