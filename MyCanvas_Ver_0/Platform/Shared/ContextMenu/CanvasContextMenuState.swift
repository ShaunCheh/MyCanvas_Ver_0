import CoreGraphics
import Foundation

struct CanvasContextMenuCommandState {
    let commandID: CanvasCommandID
    let descriptor: CanvasCommandDescriptor
}

struct CanvasContextMenuState {
    let resolvedContext: CanvasContextMenuContext
    let layoutAnchorPoint: CGPoint
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

        let placements = candidatePlacements(
            around: anchorPoint,
            menuSize: resolvedSize,
            within: layoutBounds,
            anchorSpacing: configuration.anchorSpacing
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
        around anchorPoint: CGPoint,
        menuSize: CGSize,
        within layoutBounds: CGRect,
        anchorSpacing: CGFloat
    ) -> [Placement] {
        let placements = [
            Placement(
                attachesTrailing: true,
                attachesBottom: true,
                defaultPreferenceRank: 0
            ),
            Placement(
                attachesTrailing: true,
                attachesBottom: false,
                defaultPreferenceRank: 1
            ),
            Placement(
                attachesTrailing: false,
                attachesBottom: true,
                defaultPreferenceRank: 2
            ),
            Placement(
                attachesTrailing: false,
                attachesBottom: false,
                defaultPreferenceRank: 3
            )
        ]

        return placements.sorted { lhs, rhs in
            let lhsScore = candidateScore(
                for: lhs,
                anchorPoint: anchorPoint,
                menuSize: menuSize,
                layoutBounds: layoutBounds,
                anchorSpacing: anchorSpacing
            )
            let rhsScore = candidateScore(
                for: rhs,
                anchorPoint: anchorPoint,
                menuSize: menuSize,
                layoutBounds: layoutBounds,
                anchorSpacing: anchorSpacing
            )

            if lhsScore.totalOverflow != rhsScore.totalOverflow {
                return lhsScore.totalOverflow < rhsScore.totalOverflow
            }

            if lhsScore.totalOverflow == 0, rhsScore.totalOverflow == 0 {
                return lhs.defaultPreferenceRank < rhs.defaultPreferenceRank
            }

            if lhsScore.availableArea != rhsScore.availableArea {
                return lhsScore.availableArea > rhsScore.availableArea
            }

            return lhs.defaultPreferenceRank < rhs.defaultPreferenceRank
        }
    }

    private func candidateScore(
        for placement: Placement,
        anchorPoint: CGPoint,
        menuSize: CGSize,
        layoutBounds: CGRect,
        anchorSpacing: CGFloat
    ) -> CandidateScore {
        let horizontalSpace = directionalSpace(
            attachesPositiveDirection: placement.attachesTrailing,
            coordinate: anchorPoint.x,
            minBound: layoutBounds.minX,
            maxBound: layoutBounds.maxX,
            anchorSpacing: anchorSpacing
        )
        let verticalSpace = directionalSpace(
            attachesPositiveDirection: placement.attachesBottom,
            coordinate: anchorPoint.y,
            minBound: layoutBounds.minY,
            maxBound: layoutBounds.maxY,
            anchorSpacing: anchorSpacing
        )

        let horizontalOverflow = max(menuSize.width - horizontalSpace, 0)
        let verticalOverflow = max(menuSize.height - verticalSpace, 0)
        return CandidateScore(
            totalOverflow: horizontalOverflow + verticalOverflow,
            availableArea: horizontalSpace * verticalSpace
        )
    }

    private func directionalSpace(
        attachesPositiveDirection: Bool,
        coordinate: CGFloat,
        minBound: CGFloat,
        maxBound: CGFloat,
        anchorSpacing: CGFloat
    ) -> CGFloat {
        let rawSpace = attachesPositiveDirection
            ? maxBound - coordinate - anchorSpacing
            : coordinate - minBound - anchorSpacing
        return max(rawSpace, 0)
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
        let defaultPreferenceRank: Int
    }

    private struct CandidateScore {
        let totalOverflow: CGFloat
        let availableArea: CGFloat
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
