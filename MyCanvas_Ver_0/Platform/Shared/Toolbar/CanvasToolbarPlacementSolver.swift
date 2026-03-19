import CoreGraphics
import Foundation

struct CanvasToolbarPlacementConfiguration: Hashable, Sendable {
    var edgeInset: CGFloat = 20
    var blockerClearance: CGFloat = 12
}

struct CanvasToolbarPlacementSolver {
    func resolveFrame(
        in layoutContext: CanvasChromeLayoutContext,
        configuration: CanvasToolbarPlacementConfiguration = CanvasToolbarPlacementConfiguration()
    ) -> CGRect? {
        guard
            let safeBounds = CanvasChromeLayoutGeometry.sanitizedRect(
                layoutContext.safeBounds
            )
        else {
            return nil
        }

        let inset = max(configuration.edgeInset, 0)
        guard
            let layoutBounds = CanvasChromeLayoutGeometry.sanitizedRect(
                safeBounds.insetBy(dx: inset, dy: inset)
            )
        else {
            return nil
        }

        let measuredSize = CanvasChromeLayoutGeometry.sanitizedSize(
            layoutContext.toolbarMeasuredSize
        )
        guard
            measuredSize.width > 0,
            measuredSize.height > 0,
            measuredSize.width <= layoutBounds.width,
            measuredSize.height <= layoutBounds.height
        else {
            return nil
        }

        let placement = layoutContext.toolbarPreferredPlacement
        let preferredLeadingCoordinate = clampedLeadingCoordinate(
            for: placement,
            size: measuredSize,
            in: layoutBounds
        )
        let blockerRects = expandedBlockerRects(
            from: layoutContext,
            configuration: configuration
        )
        let candidateLeadingCoordinates = candidateLeadingCoordinates(
            around: preferredLeadingCoordinate,
            placement: placement,
            size: measuredSize,
            in: layoutBounds,
            blockerRects: blockerRects
        )

        var bestFrame: CGRect?
        var bestOverlap = CGFloat.greatestFiniteMagnitude
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for candidateLeadingCoordinate in candidateLeadingCoordinates {
            let candidateFrame = frame(
                for: placement,
                size: measuredSize,
                leadingCoordinate: candidateLeadingCoordinate,
                in: layoutBounds
            )
            let overlap = totalOverlapArea(
                of: candidateFrame,
                with: blockerRects
            )
            let distance = abs(
                candidateLeadingCoordinate - preferredLeadingCoordinate
            )

            if
                overlap < bestOverlap ||
                (
                    overlap == bestOverlap &&
                    distance < bestDistance
                )
            {
                bestFrame = candidateFrame
                bestOverlap = overlap
                bestDistance = distance
            }
        }

        return bestFrame?.standardized
    }

    private func expandedBlockerRects(
        from layoutContext: CanvasChromeLayoutContext,
        configuration: CanvasToolbarPlacementConfiguration
    ) -> [CGRect] {
        let clearance = max(configuration.blockerClearance, 0)
        return layoutContext
            .occupiedRects(excluding: [.toolbar])
            .compactMap(CanvasChromeLayoutGeometry.sanitizedRect)
            .map { rect in
                rect.insetBy(dx: -clearance, dy: -clearance)
            }
            .compactMap(CanvasChromeLayoutGeometry.sanitizedRect)
    }

    private func clampedLeadingCoordinate(
        for placement: CanvasToolbarPlacement,
        size: CGSize,
        in bounds: CGRect
    ) -> CGFloat {
        let range = leadingCoordinateRange(
            for: placement.dockEdge,
            size: size,
            in: bounds
        )
        let centeredLeadingCoordinate: CGFloat

        switch placement.dockEdge {
        case .top, .bottom:
            centeredLeadingCoordinate = bounds.midX - (size.width / 2)
        case .leading, .trailing:
            centeredLeadingCoordinate = bounds.midY - (size.height / 2)
        }

        return clamp(
            centeredLeadingCoordinate + placement.offsetAlongEdge,
            minValue: range.min,
            maxValue: range.max
        )
    }

    private func candidateLeadingCoordinates(
        around preferredLeadingCoordinate: CGFloat,
        placement: CanvasToolbarPlacement,
        size: CGSize,
        in bounds: CGRect,
        blockerRects: [CGRect]
    ) -> [CGFloat] {
        let range = leadingCoordinateRange(
            for: placement.dockEdge,
            size: size,
            in: bounds
        )
        var candidates: [CGFloat] = [
            preferredLeadingCoordinate,
            range.min,
            range.max
        ]

        for blockerRect in blockerRects {
            guard
                let blockingInterval = blockingInterval(
                    for: blockerRect,
                    placement: placement,
                    size: size,
                    in: bounds
                )
            else {
                continue
            }

            candidates.append(
                clamp(
                    blockingInterval.lowerBound,
                    minValue: range.min,
                    maxValue: range.max
                )
            )
            candidates.append(
                clamp(
                    blockingInterval.upperBound,
                    minValue: range.min,
                    maxValue: range.max
                )
            )
        }

        var seen: Set<Int> = []
        var deduplicated: [CGFloat] = []
        for candidate in candidates {
            let clampedCandidate = clamp(
                candidate,
                minValue: range.min,
                maxValue: range.max
            )
            let key = Int((clampedCandidate * 1000).rounded())
            guard seen.insert(key).inserted else {
                continue
            }
            deduplicated.append(clampedCandidate)
        }

        return deduplicated
    }

    private func blockingInterval(
        for blockerRect: CGRect,
        placement: CanvasToolbarPlacement,
        size: CGSize,
        in bounds: CGRect
    ) -> ClosedRange<CGFloat>? {
        let anchoredFrame = frame(
            for: placement,
            size: size,
            leadingCoordinate: clampedLeadingCoordinate(
                for: placement,
                size: size,
                in: bounds
            ),
            in: bounds
        )
        let range = leadingCoordinateRange(
            for: placement.dockEdge,
            size: size,
            in: bounds
        )

        switch placement.dockEdge {
        case .top, .bottom:
            guard
                blockerRect.maxY > anchoredFrame.minY,
                blockerRect.minY < anchoredFrame.maxY
            else {
                return nil
            }

            let minLeadingCoordinate = max(
                blockerRect.minX - size.width,
                range.min
            )
            let maxLeadingCoordinate = min(
                blockerRect.maxX,
                range.max
            )
            guard minLeadingCoordinate <= maxLeadingCoordinate else {
                return nil
            }
            return minLeadingCoordinate...maxLeadingCoordinate

        case .leading, .trailing:
            guard
                blockerRect.maxX > anchoredFrame.minX,
                blockerRect.minX < anchoredFrame.maxX
            else {
                return nil
            }

            let minLeadingCoordinate = max(
                blockerRect.minY - size.height,
                range.min
            )
            let maxLeadingCoordinate = min(
                blockerRect.maxY,
                range.max
            )
            guard minLeadingCoordinate <= maxLeadingCoordinate else {
                return nil
            }
            return minLeadingCoordinate...maxLeadingCoordinate
        }
    }

    private func frame(
        for placement: CanvasToolbarPlacement,
        size: CGSize,
        leadingCoordinate: CGFloat,
        in bounds: CGRect
    ) -> CGRect {
        switch placement.dockEdge {
        case .top:
            return CGRect(
                x: leadingCoordinate,
                y: bounds.minY,
                width: size.width,
                height: size.height
            )
        case .bottom:
            return CGRect(
                x: leadingCoordinate,
                y: bounds.maxY - size.height,
                width: size.width,
                height: size.height
            )
        case .leading:
            return CGRect(
                x: bounds.minX,
                y: leadingCoordinate,
                width: size.width,
                height: size.height
            )
        case .trailing:
            return CGRect(
                x: bounds.maxX - size.width,
                y: leadingCoordinate,
                width: size.width,
                height: size.height
            )
        }
    }

    private func leadingCoordinateRange(
        for dockEdge: CanvasToolbarDockEdge,
        size: CGSize,
        in bounds: CGRect
    ) -> (min: CGFloat, max: CGFloat) {
        switch dockEdge {
        case .top, .bottom:
            return (
                min: bounds.minX,
                max: bounds.maxX - size.width
            )
        case .leading, .trailing:
            return (
                min: bounds.minY,
                max: bounds.maxY - size.height
            )
        }
    }

    private func totalOverlapArea(
        of rect: CGRect,
        with blockerRects: [CGRect]
    ) -> CGFloat {
        blockerRects.reduce(into: 0) { totalOverlapArea, blockerRect in
            let intersection = rect.intersection(blockerRect)
            guard intersection.isNull == false, intersection.isEmpty == false else {
                return
            }
            totalOverlapArea += intersection.width * intersection.height
        }
    }

    private func clamp(
        _ value: CGFloat,
        minValue: CGFloat,
        maxValue: CGFloat
    ) -> CGFloat {
        min(max(value, minValue), maxValue)
    }
}
