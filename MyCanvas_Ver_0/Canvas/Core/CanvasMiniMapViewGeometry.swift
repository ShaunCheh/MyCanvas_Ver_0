import CoreGraphics
import Foundation

struct CanvasMiniMapViewGeometry {
    let displayWorldRect: CGRect
    let contentRect: CGRect
    let scale: CGFloat

    init?(
        displayWorldRect: CGRect,
        viewBounds: CGRect,
        contentInset: CGFloat
    ) {
        guard
            let sanitizedDisplayWorldRect = Self.sanitizedRect(displayWorldRect),
            let sanitizedViewBounds = Self.sanitizedRect(viewBounds)
        else {
            return nil
        }

        let inset = max(contentInset, 0)
        let availableRect = sanitizedViewBounds.insetBy(dx: inset, dy: inset)
        guard let sanitizedAvailableRect = Self.sanitizedRect(availableRect) else {
            return nil
        }

        let fittedContentSize = Self.aspectFit(
            sanitizedDisplayWorldRect.size,
            into: sanitizedAvailableRect.size
        )
        guard fittedContentSize.width > 0, fittedContentSize.height > 0 else {
            return nil
        }

        let contentRect = CGRect(
            x: sanitizedAvailableRect.midX - fittedContentSize.width / 2,
            y: sanitizedAvailableRect.midY - fittedContentSize.height / 2,
            width: fittedContentSize.width,
            height: fittedContentSize.height
        ).standardized
        guard let sanitizedContentRect = Self.sanitizedRect(contentRect) else {
            return nil
        }

        self.displayWorldRect = sanitizedDisplayWorldRect
        self.contentRect = sanitizedContentRect
        scale = sanitizedContentRect.width / sanitizedDisplayWorldRect.width
    }

    func worldToMiniMap(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: contentRect.minX + ((point.x - displayWorldRect.minX) * scale),
            y: contentRect.minY + ((point.y - displayWorldRect.minY) * scale)
        )
    }

    func worldToMiniMap(_ rect: CGRect) -> CGRect {
        let standardizedRect = rect.standardized
        let origin = worldToMiniMap(standardizedRect.origin)
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: standardizedRect.width * scale,
            height: standardizedRect.height * scale
        ).standardized
    }

    func worldToMiniMap(_ quad: CanvasQuad) -> CanvasQuad {
        quad.map(worldToMiniMap)
    }

    func miniMapToWorld(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: ((point.x - contentRect.minX) / scale) + displayWorldRect.minX,
            y: ((point.y - contentRect.minY) / scale) + displayWorldRect.minY
        )
    }

    func clampedMiniMapPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, contentRect.minX), contentRect.maxX),
            y: min(max(point.y, contentRect.minY), contentRect.maxY)
        )
    }

    private static func aspectFit(
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
            availableSize.height / size.height
        )
        return CGSize(
            width: size.width * scale,
            height: size.height * scale
        )
    }

    private static func sanitizedRect(_ rect: CGRect) -> CGRect? {
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
}
