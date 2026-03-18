import CoreGraphics
import Foundation

struct CanvasContextMenuCommandState {
    let commandID: CanvasCommandID
    let descriptor: CanvasCommandDescriptor
}

struct CanvasContextMenuState {
    let resolvedContext: CanvasContextMenuContext
    let commandStates: [CanvasContextMenuCommandState]

    var isEmpty: Bool {
        commandStates.isEmpty
    }
}

struct CanvasContextMenuLayoutConfiguration {
    var minimumWidth: CGFloat = 180
    var maximumWidth: CGFloat = 280
    var edgeInset: CGFloat = 16
    var anchorSpacing: CGFloat = 10
    var chromeClearance: CGFloat = 12
}

struct CanvasContextMenuLayoutSolver {
    func resolveMenuFrame(
        anchorPoint: CGPoint,
        preferredSize: CGSize,
        safeBounds: CGRect,
        occupiedRects: [CGRect],
        configuration: CanvasContextMenuLayoutConfiguration = CanvasContextMenuLayoutConfiguration()
    ) -> CGRect? {
        let layoutBounds = safeBounds
            .standardized
            .insetBy(dx: configuration.edgeInset, dy: configuration.edgeInset)
            .standardized
        guard
            layoutBounds.width > 0,
            layoutBounds.height > 0
        else {
            return nil
        }

        let resolvedSize = resolvedMenuSize(
            from: preferredSize,
            within: layoutBounds.size,
            configuration: configuration
        )
        guard resolvedSize.width > 0, resolvedSize.height > 0 else {
            return nil
        }

        let blockerRects = occupiedRects
            .map(\.standardized)
            .filter { $0.isEmpty == false }
            .map {
                $0.insetBy(
                    dx: -configuration.chromeClearance,
                    dy: -configuration.chromeClearance
                )
            }

        let prefersTrailing = anchorPoint.x < layoutBounds.midX
        let prefersBottom = anchorPoint.y < layoutBounds.midY
        let placements = candidatePlacements(
            prefersTrailing: prefersTrailing,
            prefersBottom: prefersBottom
        )

        var bestFrame: CGRect?
        var bestScore = CGFloat.greatestFiniteMagnitude

        for placement in placements {
            let rawFrame = frame(
                around: anchorPoint,
                size: resolvedSize,
                placement: placement,
                anchorSpacing: configuration.anchorSpacing
            )
            let clampedFrame = clampedFrame(
                rawFrame,
                within: layoutBounds
            )
            let overlapScore = totalOverlapArea(
                of: clampedFrame,
                with: blockerRects
            )

            if overlapScore == 0 {
                return clampedFrame.standardized
            }

            if overlapScore < bestScore {
                bestScore = overlapScore
                bestFrame = clampedFrame.standardized
            }
        }

        return bestFrame
    }

    private func resolvedMenuSize(
        from preferredSize: CGSize,
        within layoutSize: CGSize,
        configuration: CanvasContextMenuLayoutConfiguration
    ) -> CGSize {
        let maxWidth = min(configuration.maximumWidth, layoutSize.width)
        let width = min(
            max(max(preferredSize.width, configuration.minimumWidth), 0),
            maxWidth
        )
        let height = min(max(preferredSize.height, 0), layoutSize.height)
        return CGSize(
            width: width,
            height: height
        )
    }

    private func candidatePlacements(
        prefersTrailing: Bool,
        prefersBottom: Bool
    ) -> [Placement] {
        [
            Placement(
                attachesTrailing: prefersTrailing,
                attachesBottom: prefersBottom
            ),
            Placement(
                attachesTrailing: !prefersTrailing,
                attachesBottom: prefersBottom
            ),
            Placement(
                attachesTrailing: prefersTrailing,
                attachesBottom: !prefersBottom
            ),
            Placement(
                attachesTrailing: !prefersTrailing,
                attachesBottom: !prefersBottom
            )
        ]
    }

    private func frame(
        around anchorPoint: CGPoint,
        size: CGSize,
        placement: Placement,
        anchorSpacing: CGFloat
    ) -> CGRect {
        let originX = placement.attachesTrailing
            ? anchorPoint.x + anchorSpacing
            : anchorPoint.x - anchorSpacing - size.width
        let originY = placement.attachesBottom
            ? anchorPoint.y + anchorSpacing
            : anchorPoint.y - anchorSpacing - size.height
        return CGRect(
            x: originX,
            y: originY,
            width: size.width,
            height: size.height
        ).standardized
    }

    private func clampedFrame(
        _ frame: CGRect,
        within bounds: CGRect
    ) -> CGRect {
        var clampedFrame = frame.standardized
        clampedFrame.origin.x = min(
            max(clampedFrame.minX, bounds.minX),
            bounds.maxX - clampedFrame.width
        )
        clampedFrame.origin.y = min(
            max(clampedFrame.minY, bounds.minY),
            bounds.maxY - clampedFrame.height
        )
        return clampedFrame.standardized
    }

    private func totalOverlapArea(
        of frame: CGRect,
        with blockerRects: [CGRect]
    ) -> CGFloat {
        blockerRects.reduce(0) { partialResult, blockerRect in
            partialResult + frame.intersection(blockerRect).standardized.area
        }
    }

    private struct Placement {
        let attachesTrailing: Bool
        let attachesBottom: Bool
    }
}

private extension CGRect {
    var area: CGFloat {
        guard isEmpty == false else {
            return 0
        }

        return width * height
    }
}
