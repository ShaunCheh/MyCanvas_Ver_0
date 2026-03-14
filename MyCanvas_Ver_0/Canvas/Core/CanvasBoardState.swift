import CoreGraphics
import Foundation

struct CanvasBoardState {
    let baseSize: CGSize
    private(set) var worldRect: CGRect

    init(
        baseSize: CGSize,
        centeredAt center: CGPoint = .zero
    ) {
        let sanitizedBaseSize = Self.sanitizedBaseSize(from: baseSize)
        self.baseSize = sanitizedBaseSize
        worldRect = CGRect(
            x: center.x - sanitizedBaseSize.width / 2,
            y: center.y - sanitizedBaseSize.height / 2,
            width: sanitizedBaseSize.width,
            height: sanitizedBaseSize.height
        )
    }

    init(
        baseSize: CGSize,
        worldRect: CGRect
    ) {
        let sanitizedBaseSize = Self.sanitizedBaseSize(from: baseSize)
        let standardizedWorldRect = worldRect.standardized
        self.baseSize = sanitizedBaseSize
        self.worldRect = CGRect(
            x: standardizedWorldRect.origin.x,
            y: standardizedWorldRect.origin.y,
            width: max(standardizedWorldRect.width, sanitizedBaseSize.width),
            height: max(standardizedWorldRect.height, sanitizedBaseSize.height)
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

    private static func sanitizedBaseSize(from baseSize: CGSize) -> CGSize {
        CGSize(
            width: max(baseSize.width, 1),
            height: max(baseSize.height, 1)
        )
    }
}
