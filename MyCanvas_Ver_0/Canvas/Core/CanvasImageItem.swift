import CoreGraphics
import Foundation

typealias CanvasImageItemID = UUID

struct CanvasImageItem {
    let id: CanvasImageItemID
    let cgImage: CGImage
    var center: CGPoint
    var size: CGSize
    var zIndex: CGFloat

    init(
        id: CanvasImageItemID = UUID(),
        cgImage: CGImage,
        center: CGPoint,
        size: CGSize,
        zIndex: CGFloat = 0
    ) {
        self.id = id
        self.cgImage = cgImage
        self.center = center
        self.size = size
        self.zIndex = zIndex
    }

    var worldFrame: CGRect {
        CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
