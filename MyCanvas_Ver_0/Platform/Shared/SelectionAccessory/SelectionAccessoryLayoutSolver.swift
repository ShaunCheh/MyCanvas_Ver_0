import CoreGraphics
import Foundation

struct SelectionAccessoryLayoutConfiguration: Equatable, Sendable {
    var minimumWidth: CGFloat
    var edgeInset: CGFloat
    var anchorSpacing: CGFloat
    var chromeClearance: CGFloat

    init(
        minimumWidth: CGFloat = 132,
        edgeInset: CGFloat = 16,
        anchorSpacing: CGFloat = 10,
        chromeClearance: CGFloat = 12
    ) {
        self.minimumWidth = max(minimumWidth, 0)
        self.edgeInset = max(edgeInset, 0)
        self.anchorSpacing = max(anchorSpacing, 0)
        self.chromeClearance = max(chromeClearance, 0)
    }
}

struct SelectionAccessoryLayoutSolver {
    private enum Placement: CaseIterable {
        case aboveCentered
        case belowCentered
        case aboveTrailing
        case belowTrailing
    }

    func resolveAccessoryFrame(
        anchorRect: CGRect,
        preferredSize: CGSize,
        layoutContext: CanvasChromeLayoutContext,
        configuration: SelectionAccessoryLayoutConfiguration = .init()
    ) -> CGRect? {
        guard
            let safeBounds = CanvasChromeLayoutGeometry.sanitizedRect(
                layoutContext.safeBounds
            ),
            let sanitizedAnchorRect = CanvasChromeLayoutGeometry.sanitizedRect(
                anchorRect
            )
        else {
            return nil
        }

        let layoutBounds = safeBounds
            .insetBy(dx: configuration.edgeInset, dy: configuration.edgeInset)
            .standardized
        guard layoutBounds.width > 0, layoutBounds.height > 0 else {
            return nil
        }

        let sanitizedPreferredSize = CanvasChromeLayoutGeometry.sanitizedSize(
            preferredSize
        )
        let resolvedSize = CGSize(
            width: min(
                max(sanitizedPreferredSize.width, configuration.minimumWidth),
                layoutBounds.width
            ),
            height: min(sanitizedPreferredSize.height, layoutBounds.height)
        )
        guard resolvedSize.width > 0, resolvedSize.height > 0 else {
            return nil
        }

        let chromeBlockerRects = layoutContext
            .occupiedRects(excluding: [.selectionAccessory])
            .compactMap(CanvasChromeLayoutGeometry.sanitizedRect)
            .map {
                $0.insetBy(
                    dx: -configuration.chromeClearance,
                    dy: -configuration.chromeClearance
                )
            }
        let anchorExclusionRect = sanitizedAnchorRect.insetBy(
            dx: -configuration.anchorSpacing,
            dy: -configuration.anchorSpacing
        )
        let blockerRects = chromeBlockerRects + [anchorExclusionRect]

        var bestFrame: CGRect?
        var bestScore = CGFloat.greatestFiniteMagnitude
        for placement in Placement.allCases {
            let candidateFrame = clampedFrame(
                frame(
                    for: placement,
                    anchorRect: sanitizedAnchorRect,
                    size: resolvedSize,
                    anchorSpacing: configuration.anchorSpacing
                ),
                within: layoutBounds
            )
            let overlapScore = totalOverlapArea(
                of: candidateFrame,
                with: blockerRects
            )
            if overlapScore == 0 {
                return candidateFrame.integral
            }
            if overlapScore < bestScore {
                bestScore = overlapScore
                bestFrame = candidateFrame
            }
        }

        return bestFrame?.integral
    }

    private func frame(
        for placement: Placement,
        anchorRect: CGRect,
        size: CGSize,
        anchorSpacing: CGFloat
    ) -> CGRect {
        let x: CGFloat
        let y: CGFloat
        switch placement {
        case .aboveCentered:
            x = anchorRect.midX - size.width / 2
            y = anchorRect.minY - anchorSpacing - size.height
        case .belowCentered:
            x = anchorRect.midX - size.width / 2
            y = anchorRect.maxY + anchorSpacing
        case .aboveTrailing:
            x = anchorRect.maxX - size.width
            y = anchorRect.minY - anchorSpacing - size.height
        case .belowTrailing:
            x = anchorRect.maxX - size.width
            y = anchorRect.maxY + anchorSpacing
        }
        return CGRect(
            x: x,
            y: y,
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
}

private extension CGRect {
    var area: CGFloat {
        guard isNull == false, isInfinite == false else {
            return 0
        }
        let standardizedRect = standardized
        guard standardizedRect.width > 0, standardizedRect.height > 0 else {
            return 0
        }
        return standardizedRect.width * standardizedRect.height
    }
}
