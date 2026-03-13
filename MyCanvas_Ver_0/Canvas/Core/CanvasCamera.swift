import CoreGraphics
import Foundation

struct CanvasCamera {
    private static let minimumZoomScale: CGFloat = 0.1
    private static let maximumZoomScale: CGFloat = 8

    var center: CGPoint
    var zoomScale: CGFloat
    var viewportSize: CGSize

    init(
        center: CGPoint = .zero,
        zoomScale: CGFloat = 1,
        viewportSize: CGSize = .zero
    ) {
        self.center = center
        self.zoomScale = Self.clampedZoomScale(for: zoomScale)
        self.viewportSize = viewportSize
    }

    var viewportBounds: CGRect {
        CGRect(origin: .zero, size: viewportSize)
    }

    var visibleWorldRect: CGRect {
        let visibleSize = CGSize(
            width: viewportSize.width / zoomScale,
            height: viewportSize.height / zoomScale
        )

        return CGRect(
            x: center.x - visibleSize.width / 2,
            y: center.y - visibleSize.height / 2,
            width: visibleSize.width,
            height: visibleSize.height
        )
    }

    mutating func setViewportSize(_ size: CGSize) {
        viewportSize = size
    }

    func worldToViewport(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - center.x) * zoomScale + viewportSize.width / 2,
            y: (point.y - center.y) * zoomScale + viewportSize.height / 2
        )
    }

    func viewportToWorld(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - viewportSize.width / 2) / zoomScale + center.x,
            y: (point.y - viewportSize.height / 2) / zoomScale + center.y
        )
    }

    func worldToViewport(_ rect: CGRect) -> CGRect {
        let standardizedRect = rect.standardized
        let origin = worldToViewport(standardizedRect.origin)

        return CGRect(
            x: origin.x,
            y: origin.y,
            width: standardizedRect.width * zoomScale,
            height: standardizedRect.height * zoomScale
        )
    }

    mutating func pan(by deltaInViewport: CGPoint) {
        center.x -= deltaInViewport.x / zoomScale
        center.y -= deltaInViewport.y / zoomScale
    }

    mutating func zoom(to newZoomScale: CGFloat, around anchorInViewport: CGPoint) {
        let worldAnchorBeforeZoom = viewportToWorld(anchorInViewport)
        zoomScale = Self.clampedZoomScale(for: newZoomScale)

        // Keep the zoom anchor visually stable while the scale changes.
        let worldAnchorAfterZoom = viewportToWorld(anchorInViewport)
        center.x += worldAnchorBeforeZoom.x - worldAnchorAfterZoom.x
        center.y += worldAnchorBeforeZoom.y - worldAnchorAfterZoom.y
    }

    mutating func zoom(by scaleDelta: CGFloat, around anchorInViewport: CGPoint) {
        zoom(to: zoomScale * scaleDelta, around: anchorInViewport)
    }

    private static func clampedZoomScale(for zoomScale: CGFloat) -> CGFloat {
        min(max(zoomScale, minimumZoomScale), maximumZoomScale)
    }
}
