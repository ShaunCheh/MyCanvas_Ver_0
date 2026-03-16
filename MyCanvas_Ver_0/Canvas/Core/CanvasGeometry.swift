import CoreGraphics
import Foundation

struct CanvasQuad: Equatable {
    let topLeading: CGPoint
    let topTrailing: CGPoint
    let bottomLeading: CGPoint
    let bottomTrailing: CGPoint

    init(
        topLeading: CGPoint,
        topTrailing: CGPoint,
        bottomLeading: CGPoint,
        bottomTrailing: CGPoint
    ) {
        self.topLeading = topLeading
        self.topTrailing = topTrailing
        self.bottomLeading = bottomLeading
        self.bottomTrailing = bottomTrailing
    }

    init(rect: CGRect) {
        let standardizedRect = rect.standardized
        self.init(
            topLeading: CGPoint(x: standardizedRect.minX, y: standardizedRect.minY),
            topTrailing: CGPoint(x: standardizedRect.maxX, y: standardizedRect.minY),
            bottomLeading: CGPoint(x: standardizedRect.minX, y: standardizedRect.maxY),
            bottomTrailing: CGPoint(x: standardizedRect.maxX, y: standardizedRect.maxY)
        )
    }

    var points: [CGPoint] {
        [
            topLeading,
            topTrailing,
            bottomTrailing,
            bottomLeading
        ]
    }

    var boundingRect: CGRect {
        let xs = points.map(\.x)
        let ys = points.map(\.y)

        guard
            let minX = xs.min(),
            let maxX = xs.max(),
            let minY = ys.min(),
            let maxY = ys.max()
        else {
            return .zero
        }

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    func map(_ transform: (CGPoint) -> CGPoint) -> CanvasQuad {
        CanvasQuad(
            topLeading: transform(topLeading),
            topTrailing: transform(topTrailing),
            bottomLeading: transform(bottomLeading),
            bottomTrailing: transform(bottomTrailing)
        )
    }
}
