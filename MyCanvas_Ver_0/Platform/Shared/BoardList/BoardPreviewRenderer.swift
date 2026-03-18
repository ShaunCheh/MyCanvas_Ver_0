import CoreGraphics
import Foundation
import QuartzCore

enum BoardPreviewRenderer {
    static func render(
        content: BoardPreviewContent,
        viewBounds: CGRect,
        contentInset: CGFloat,
        imageLayer: CALayer,
        boardLayer: CAShapeLayer,
        occupancyLayer: CAShapeLayer
    ) {
        let roundedBounds = viewBounds.integral
        imageLayer.frame = roundedBounds
        boardLayer.frame = roundedBounds
        occupancyLayer.frame = roundedBounds

        switch content {
        case .empty:
            imageLayer.contents = nil
            imageLayer.isHidden = true
            boardLayer.path = nil
            boardLayer.isHidden = true
            occupancyLayer.path = nil
            occupancyLayer.isHidden = true

        case let .geometry(seed):
            imageLayer.contents = nil
            imageLayer.isHidden = true

            let layout = BoardGeometryPreviewLayout(
                seed: seed,
                viewBounds: roundedBounds,
                contentInset: contentInset
            )

            if let boardRect = layout.boardRect {
                boardLayer.path = CGPath(rect: boardRect, transform: nil)
                boardLayer.isHidden = false
            } else {
                boardLayer.path = nil
                boardLayer.isHidden = true
            }

            if layout.nodePaths.isEmpty {
                occupancyLayer.path = nil
                occupancyLayer.isHidden = true
                return
            }

            let path = CGMutablePath()
            for nodePath in layout.nodePaths {
                path.addPath(nodePath)
            }
            occupancyLayer.path = path
            occupancyLayer.isHidden = false

        case let .thumbnail(image, seed):
            imageLayer.contents = image
            imageLayer.isHidden = false

            let layout = BoardGeometryPreviewLayout(
                seed: seed,
                viewBounds: roundedBounds,
                contentInset: contentInset
            )
            if let boardRect = layout.boardRect {
                boardLayer.path = CGPath(rect: boardRect, transform: nil)
                boardLayer.isHidden = false
            } else {
                boardLayer.path = nil
                boardLayer.isHidden = true
            }

            occupancyLayer.path = nil
            occupancyLayer.isHidden = true
        }
    }
}
