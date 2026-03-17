import CoreGraphics
import Foundation

enum CanvasMiniMapAnchor {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    fileprivate var prefersTop: Bool {
        switch self {
        case .topLeading, .topTrailing:
            return true
        case .bottomLeading, .bottomTrailing:
            return false
        }
    }

    fileprivate var prefersLeading: Bool {
        switch self {
        case .topLeading, .bottomLeading:
            return true
        case .topTrailing, .bottomTrailing:
            return false
        }
    }

    fileprivate var horizontalMirrored: CanvasMiniMapAnchor {
        switch self {
        case .topLeading:
            return .topTrailing
        case .topTrailing:
            return .topLeading
        case .bottomLeading:
            return .bottomTrailing
        case .bottomTrailing:
            return .bottomLeading
        }
    }

    fileprivate var verticalMirrored: CanvasMiniMapAnchor {
        switch self {
        case .topLeading:
            return .bottomLeading
        case .topTrailing:
            return .bottomTrailing
        case .bottomLeading:
            return .topLeading
        case .bottomTrailing:
            return .topTrailing
        }
    }
}

struct CanvasMiniMapConfiguration {
    var preferredAnchor: CanvasMiniMapAnchor = .bottomLeading
    var preferredSize: CGSize = CGSize(width: 180, height: 132)
    var edgeInset: CGFloat = 16
    var chromeClearance: CGFloat = 12
    var minimumAllowedSize: CGSize = CGSize(width: 120, height: 88)
}

struct CanvasOverlayLayoutSolver {
    func resolveMiniMapFrame(
        safeBounds: CGRect,
        occupiedRects: [CGRect],
        configuration: CanvasMiniMapConfiguration
    ) -> CGRect? {
        guard
            let layoutBounds = sanitizedLayoutBounds(
                from: safeBounds,
                edgeInset: configuration.edgeInset
            )
        else {
            return nil
        }

        let blockerRects: [CGRect] = occupiedRects.compactMap { rect -> CGRect? in
            guard let sanitizedOccupiedRect = sanitizedRect(rect) else {
                return nil
            }

            return sanitizedOccupiedRect.insetBy(
                dx: -configuration.chromeClearance,
                dy: -configuration.chromeClearance
            )
        }
        let sizeCandidates = candidateSizes(
            for: configuration,
            in: layoutBounds
        )
        guard sizeCandidates.isEmpty == false else {
            return nil
        }

        for anchor in candidateAnchors(for: configuration.preferredAnchor) {
            for size in sizeCandidates {
                var candidateFrame = anchoredFrame(
                    for: anchor,
                    size: size,
                    in: layoutBounds
                )
                candidateFrame = adjustedFrame(
                    candidateFrame,
                    for: anchor,
                    avoiding: blockerRects,
                    within: layoutBounds
                )

                guard layoutBounds.contains(candidateFrame) else {
                    continue
                }

                guard blockerRects.contains(where: { $0.intersects(candidateFrame) }) == false else {
                    continue
                }

                return candidateFrame.standardized
            }
        }

        return nil
    }

    private func candidateAnchors(
        for preferredAnchor: CanvasMiniMapAnchor
    ) -> [CanvasMiniMapAnchor] {
        [
            preferredAnchor,
            preferredAnchor.horizontalMirrored,
            preferredAnchor.verticalMirrored,
            preferredAnchor.verticalMirrored.horizontalMirrored
        ]
    }

    private func candidateSizes(
        for configuration: CanvasMiniMapConfiguration,
        in layoutBounds: CGRect
    ) -> [CGSize] {
        let preferredSize = sanitizedSize(configuration.preferredSize)
        let minimumSize = sanitizedSize(configuration.minimumAllowedSize)
        let fittedPreferredSize = aspectFit(
            preferredSize,
            into: layoutBounds.size
        )

        guard
            fittedPreferredSize.width >= minimumSize.width,
            fittedPreferredSize.height >= minimumSize.height
        else {
            return []
        }

        var sizes: [CGSize] = [fittedPreferredSize]
        for scale in [CGFloat(0.9), CGFloat(0.8), CGFloat(0.7)] {
            let scaledSize = CGSize(
                width: fittedPreferredSize.width * scale,
                height: fittedPreferredSize.height * scale
            )
            guard
                scaledSize.width >= minimumSize.width,
                scaledSize.height >= minimumSize.height
            else {
                continue
            }

            sizes.append(scaledSize)
        }

        sizes.append(minimumSize)
        return uniqueSizes(sizes)
    }

    private func anchoredFrame(
        for anchor: CanvasMiniMapAnchor,
        size: CGSize,
        in bounds: CGRect
    ) -> CGRect {
        let originX = anchor.prefersLeading
            ? bounds.minX
            : bounds.maxX - size.width
        let originY = anchor.prefersTop
            ? bounds.minY
            : bounds.maxY - size.height
        return CGRect(
            x: originX,
            y: originY,
            width: size.width,
            height: size.height
        )
    }

    private func adjustedFrame(
        _ frame: CGRect,
        for anchor: CanvasMiniMapAnchor,
        avoiding blockerRects: [CGRect],
        within bounds: CGRect
    ) -> CGRect {
        var currentFrame = frame.standardized

        for _ in 0..<(blockerRects.count * 2) {
            var moved = false

            for blockerRect in blockerRects where blockerRect.intersects(currentFrame) {
                let verticallyAdjustedFrame = verticallyAdjustedFrame(
                    currentFrame,
                    for: anchor,
                    blocking: blockerRect,
                    within: bounds
                )
                if verticallyAdjustedFrame != currentFrame {
                    currentFrame = verticallyAdjustedFrame
                    moved = true
                }

                if blockerRect.intersects(currentFrame) {
                    let horizontallyAdjustedFrame = horizontallyAdjustedFrame(
                        currentFrame,
                        for: anchor,
                        blocking: blockerRect,
                        within: bounds
                    )
                    if horizontallyAdjustedFrame != currentFrame {
                        currentFrame = horizontallyAdjustedFrame
                        moved = true
                    }
                }
            }

            if moved == false {
                break
            }
        }

        return currentFrame
    }

    private func verticallyAdjustedFrame(
        _ frame: CGRect,
        for anchor: CanvasMiniMapAnchor,
        blocking blockerRect: CGRect,
        within bounds: CGRect
    ) -> CGRect {
        var adjustedFrame = frame
        if anchor.prefersTop {
            let targetY = min(
                max(blockerRect.maxY, bounds.minY),
                bounds.maxY - frame.height
            )
            adjustedFrame.origin.y = targetY
        } else {
            let targetY = max(
                min(blockerRect.minY - frame.height, bounds.maxY - frame.height),
                bounds.minY
            )
            adjustedFrame.origin.y = targetY
        }

        return adjustedFrame
    }

    private func horizontallyAdjustedFrame(
        _ frame: CGRect,
        for anchor: CanvasMiniMapAnchor,
        blocking blockerRect: CGRect,
        within bounds: CGRect
    ) -> CGRect {
        var adjustedFrame = frame
        if anchor.prefersLeading {
            let targetX = min(
                max(blockerRect.maxX, bounds.minX),
                bounds.maxX - frame.width
            )
            adjustedFrame.origin.x = targetX
        } else {
            let targetX = max(
                min(blockerRect.minX - frame.width, bounds.maxX - frame.width),
                bounds.minX
            )
            adjustedFrame.origin.x = targetX
        }

        return adjustedFrame
    }

    private func sanitizedLayoutBounds(
        from safeBounds: CGRect,
        edgeInset: CGFloat
    ) -> CGRect? {
        guard let sanitizedSafeBounds = sanitizedRect(safeBounds) else {
            return nil
        }

        let inset = max(edgeInset, 0)
        let layoutBounds = sanitizedSafeBounds.insetBy(dx: inset, dy: inset)
        return sanitizedRect(layoutBounds)
    }

    private func sanitizedRect(_ rect: CGRect) -> CGRect? {
        guard rect.isNull == false, rect.isInfinite == false else {
            return nil
        }

        let standardizedRect = rect.standardized
        guard
            standardizedRect.width > 0,
            standardizedRect.height > 0
        else {
            return nil
        }

        return standardizedRect
    }

    private func sanitizedSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(size.width, 1),
            height: max(size.height, 1)
        )
    }

    private func aspectFit(
        _ size: CGSize,
        into availableSize: CGSize
    ) -> CGSize {
        guard
            size.width > 0,
            size.height > 0,
            availableSize.width > 0,
            availableSize.height > 0
        else {
            return .zero
        }

        let scale = min(
            availableSize.width / size.width,
            availableSize.height / size.height,
            1
        )
        return CGSize(
            width: size.width * scale,
            height: size.height * scale
        )
    }

    private func uniqueSizes(_ sizes: [CGSize]) -> [CGSize] {
        var seen: Set<String> = []
        var result: [CGSize] = []

        for size in sizes {
            let key = "\(size.width.rounded(.toNearestOrAwayFromZero))x\(size.height.rounded(.toNearestOrAwayFromZero))"
            guard seen.insert(key).inserted else {
                continue
            }

            result.append(size)
        }

        return result
    }
}
