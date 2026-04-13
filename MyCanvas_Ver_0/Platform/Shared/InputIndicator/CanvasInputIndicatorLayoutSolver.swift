import CoreGraphics
import Foundation

struct CanvasInputIndicatorLayoutConfiguration: Equatable, Sendable {
    var horizontalMargin: CGFloat
    var verticalMargin: CGFloat
    var blockerSpacing: CGFloat

    init(
        horizontalMargin: CGFloat = 16,
        verticalMargin: CGFloat = 18,
        blockerSpacing: CGFloat = 12
    ) {
        self.horizontalMargin = max(horizontalMargin, 0)
        self.verticalMargin = max(verticalMargin, 0)
        self.blockerSpacing = max(blockerSpacing, 0)
    }
}

struct CanvasInputIndicatorLayoutSolver {
    var configuration: CanvasInputIndicatorLayoutConfiguration

    init(
        configuration: CanvasInputIndicatorLayoutConfiguration = .init()
    ) {
        self.configuration = configuration
    }

    func resolveHostFrame(
        preferredSize: CGSize,
        layoutContext: CanvasChromeLayoutContext
    ) -> CGRect? {
        guard
            let safeBounds = CanvasChromeLayoutGeometry.sanitizedRect(
                layoutContext.safeBounds
            )
        else {
            return nil
        }

        let availableWidth = max(
            safeBounds.width - configuration.horizontalMargin * 2,
            0
        )
        let availableHeight = max(
            safeBounds.height - configuration.verticalMargin * 2,
            0
        )
        let sanitizedPreferredSize = CanvasChromeLayoutGeometry.sanitizedSize(
            preferredSize
        )
        let width = min(sanitizedPreferredSize.width, availableWidth)
        let height = min(sanitizedPreferredSize.height, availableHeight)
        guard width > 0, height > 0 else {
            return nil
        }

        let x = safeBounds.midX - width / 2
        let minimumY = safeBounds.minY + configuration.verticalMargin
        var y = safeBounds.maxY - configuration.verticalMargin - height

        let blockers = layoutContext.occupiedRects.compactMap {
            CanvasChromeLayoutGeometry.sanitizedRect($0)
        }

        var candidateFrame = CGRect(
            x: x,
            y: y,
            width: width,
            height: height
        )
        var didAdjust = true
        while didAdjust {
            didAdjust = false
            for blocker in blockers {
                let expandedBlocker = blocker.insetBy(
                    dx: -configuration.blockerSpacing,
                    dy: -configuration.blockerSpacing
                )
                guard candidateFrame.intersects(expandedBlocker) else {
                    continue
                }

                let shiftedY = blocker.minY - configuration.blockerSpacing - height
                guard shiftedY < candidateFrame.minY else {
                    continue
                }

                candidateFrame.origin.y = shiftedY
                didAdjust = true
            }
        }

        guard candidateFrame.minY >= minimumY else {
            return nil
        }

        return candidateFrame.integral
    }
}
