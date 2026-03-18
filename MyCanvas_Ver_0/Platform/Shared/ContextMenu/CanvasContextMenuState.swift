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

enum CanvasContextMenuOcclusionPolicy {
    case avoidOverlayChrome
    case allowChromeOverlap
}

enum CanvasContextMenuPlacementStyle {
    case cursorPreferred
    case fingerPreferred
    case fixedRightOfAnchor
}

struct CanvasContextMenuLayoutConfiguration {
    var minimumWidth: CGFloat = 180
    var maximumWidth: CGFloat = 280
    var edgeInset: CGFloat = 16
    var anchorSpacing: CGFloat = 10
    var chromeClearance: CGFloat = 12
    var occlusionPolicy: CanvasContextMenuOcclusionPolicy = .allowChromeOverlap
    var placementStyle: CanvasContextMenuPlacementStyle = .cursorPreferred
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

        let blockerRects: [CGRect]
        let placements: [Placement]
        switch configuration.occlusionPolicy {
        case .avoidOverlayChrome:
            blockerRects = occupiedRects
                .map(\.standardized)
                .filter { $0.isEmpty == false }
                .map {
                    $0.insetBy(
                        dx: -configuration.chromeClearance,
                        dy: -configuration.chromeClearance
                    )
                }
            placements = candidatePlacements(
                for: configuration.placementStyle,
                around: anchorPoint,
                size: resolvedSize,
                within: layoutBounds,
                anchorSpacing: configuration.anchorSpacing,
                configuration: configuration
            )
        case .allowChromeOverlap:
            // Keep safeBounds as the hard boundary, but allow menus to cover
            // floating buttons and the minimap. Placement style still controls
            // whether the menu prefers finger-above or cursor-near behavior.
            blockerRects = []
            placements = preferredPlacements(for: configuration.placementStyle)
        }

        var bestFrame: CGRect?
        var bestScore = CGFloat.greatestFiniteMagnitude

        for placement in placements {
            let rawFrame = frame(
                around: anchorPoint,
                size: resolvedSize,
                placement: placement,
                anchorSpacing: configuration.anchorSpacing
            )
            let resolvedFrame: CGRect
            if shouldClamp(
                placement: placement,
                configuration: configuration
            ) {
                resolvedFrame = clampedFrame(
                    rawFrame,
                    within: layoutBounds
                )
            } else {
                resolvedFrame = rawFrame.standardized
            }
            let overlapScore = totalOverlapArea(
                of: resolvedFrame,
                with: blockerRects
            )

            if overlapScore == 0 {
                return resolvedFrame.standardized
            }

            if overlapScore < bestScore {
                bestScore = overlapScore
                bestFrame = resolvedFrame.standardized
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

    private func preferredPlacements(
        for placementStyle: CanvasContextMenuPlacementStyle
    ) -> [Placement] {
        switch placementStyle {
        case .cursorPreferred:
            return [
                Placement(
                    horizontalAlignment: .trailing,
                    verticalAlignment: .below,
                    defaultPreferenceRank: 0
                ),
                Placement(
                    horizontalAlignment: .trailing,
                    verticalAlignment: .above,
                    defaultPreferenceRank: 1
                ),
                Placement(
                    horizontalAlignment: .leading,
                    verticalAlignment: .below,
                    defaultPreferenceRank: 2
                ),
                Placement(
                    horizontalAlignment: .leading,
                    verticalAlignment: .above,
                    defaultPreferenceRank: 3
                )
            ]
        case .fingerPreferred:
            return [
                Placement(
                    horizontalAlignment: .centered,
                    verticalAlignment: .above,
                    defaultPreferenceRank: 0
                ),
                Placement(
                    horizontalAlignment: .trailing,
                    verticalAlignment: .above,
                    defaultPreferenceRank: 1
                ),
                Placement(
                    horizontalAlignment: .leading,
                    verticalAlignment: .above,
                    defaultPreferenceRank: 2
                ),
                Placement(
                    horizontalAlignment: .centered,
                    verticalAlignment: .below,
                    defaultPreferenceRank: 3
                ),
                Placement(
                    horizontalAlignment: .trailing,
                    verticalAlignment: .below,
                    defaultPreferenceRank: 4
                ),
                Placement(
                    horizontalAlignment: .leading,
                    verticalAlignment: .below,
                    defaultPreferenceRank: 5
                )
            ]
        case .fixedRightOfAnchor:
            return [
                Placement(
                    horizontalAlignment: .trailing,
                    verticalAlignment: .anchored,
                    defaultPreferenceRank: 0
                )
            ]
        }
    }

    private func candidatePlacements(
        for placementStyle: CanvasContextMenuPlacementStyle,
        around anchorPoint: CGPoint,
        size: CGSize,
        within layoutBounds: CGRect,
        anchorSpacing: CGFloat,
        configuration: CanvasContextMenuLayoutConfiguration
    ) -> [Placement] {
        let placements = preferredPlacements(for: placementStyle)

        return placements.sorted { lhs, rhs in
            let lhsScore = candidateScore(
                for: lhs,
                anchorPoint: anchorPoint,
                menuSize: size,
                layoutBounds: layoutBounds,
                anchorSpacing: anchorSpacing,
                configuration: configuration
            )
            let rhsScore = candidateScore(
                for: rhs,
                anchorPoint: anchorPoint,
                menuSize: size,
                layoutBounds: layoutBounds,
                anchorSpacing: anchorSpacing,
                configuration: configuration
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
        anchorSpacing: CGFloat,
        configuration: CanvasContextMenuLayoutConfiguration
    ) -> CandidateScore {
        let rawFrame = frame(
            around: anchorPoint,
            size: menuSize,
            placement: placement,
            anchorSpacing: anchorSpacing
        )
        let resolvedFrame: CGRect
        if shouldClamp(
            placement: placement,
            configuration: configuration
        ) {
            resolvedFrame = clampedFrame(
                rawFrame,
                within: layoutBounds
            )
        } else {
            resolvedFrame = rawFrame.standardized
        }

        let clampDisplacement =
            abs(resolvedFrame.minX - rawFrame.minX) +
            abs(resolvedFrame.minY - rawFrame.minY)
        return CandidateScore(
            totalOverflow: clampDisplacement,
            availableArea: resolvedFrame.intersection(layoutBounds).standardized.area
        )
    }

    private func shouldClamp(
        placement: Placement,
        configuration: CanvasContextMenuLayoutConfiguration
    ) -> Bool {
        switch configuration.placementStyle {
        case .cursorPreferred, .fingerPreferred:
            return true
        case .fixedRightOfAnchor:
            break
        }

        switch (placement.horizontalAlignment, placement.verticalAlignment) {
        case (.trailing, .anchored):
            return false
        default:
            return true
        }
    }

    private func frame(
        around anchorPoint: CGPoint,
        size: CGSize,
        placement: Placement,
        anchorSpacing: CGFloat
    ) -> CGRect {
        let originX: CGFloat
        switch placement.horizontalAlignment {
        case .trailing:
            originX = anchorPoint.x + anchorSpacing
        case .leading:
            originX = anchorPoint.x - anchorSpacing - size.width
        case .centered:
            originX = anchorPoint.x - (size.width / 2)
        }

        let originY: CGFloat
        switch placement.verticalAlignment {
        case .below:
            originY = anchorPoint.y + anchorSpacing
        case .above:
            originY = anchorPoint.y - anchorSpacing - size.height
        case .anchored:
            originY = anchorPoint.y
        }

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
        let horizontalAlignment: HorizontalAlignment
        let verticalAlignment: VerticalAlignment
        let defaultPreferenceRank: Int
    }

    private struct CandidateScore {
        let totalOverflow: CGFloat
        let availableArea: CGFloat
    }

    private enum HorizontalAlignment {
        case leading
        case centered
        case trailing
    }

    private enum VerticalAlignment {
        case above
        case below
        case anchored
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
