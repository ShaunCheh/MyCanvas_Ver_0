import CoreGraphics
import Foundation

struct CanvasBoardState {
    let baseSize: CGSize
    private(set) var worldRect: CGRect

    init(
        baseSize: CGSize,
        centeredAt center: CGPoint = .zero
    ) {
        let sanitizedBaseSize = CGSize(
            width: max(baseSize.width, 1),
            height: max(baseSize.height, 1)
        )
        self.baseSize = sanitizedBaseSize
        worldRect = CGRect(
            x: center.x - sanitizedBaseSize.width / 2,
            y: center.y - sanitizedBaseSize.height / 2,
            width: sanitizedBaseSize.width,
            height: sanitizedBaseSize.height
        )
    }

    @discardableResult
    mutating func expandIfNeeded(toInclude worldFrame: CGRect) -> Bool {
        let standardizedFrame = worldFrame.standardized
        var didExpand = false

        while standardizedFrame.minX < worldRect.minX {
            worldRect.origin.x -= baseSize.width
            worldRect.size.width += baseSize.width
            didExpand = true
        }

        while standardizedFrame.maxX > worldRect.maxX {
            worldRect.size.width += baseSize.width
            didExpand = true
        }

        while standardizedFrame.minY < worldRect.minY {
            worldRect.origin.y -= baseSize.height
            worldRect.size.height += baseSize.height
            didExpand = true
        }

        while standardizedFrame.maxY > worldRect.maxY {
            worldRect.size.height += baseSize.height
            didExpand = true
        }

        return didExpand
    }
}
