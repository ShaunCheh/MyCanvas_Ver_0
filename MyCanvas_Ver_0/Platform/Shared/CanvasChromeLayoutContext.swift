import CoreGraphics
import Foundation

enum CanvasChromeBlockerKind: String, Sendable {
    case backButton
    case modeToggle
    case historyButtons
    case toolbar
    case miniMap
    case contextMenu
}

struct CanvasChromeBlocker: Hashable, Sendable {
    var kind: CanvasChromeBlockerKind
    var rect: CGRect

    init(
        kind: CanvasChromeBlockerKind,
        rect: CGRect
    ) {
        self.kind = kind
        self.rect = rect
    }
}

enum CanvasChromeLayoutGeometry {
    static func sanitizedRect(_ rect: CGRect) -> CGRect? {
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

    static func pixelAlignedRectPreservingSize(
        _ rect: CGRect,
        scale: CGFloat
    ) -> CGRect? {
        guard let sanitizedRect = sanitizedRect(rect) else {
            return nil
        }

        let sanitizedScale: CGFloat
        if scale.isFinite, scale > 0 {
            sanitizedScale = scale
        } else {
            sanitizedScale = 1
        }

        func alignToPixel(_ value: CGFloat) -> CGFloat {
            (value * sanitizedScale).rounded() / sanitizedScale
        }

        return CGRect(
            x: alignToPixel(sanitizedRect.minX),
            y: alignToPixel(sanitizedRect.minY),
            width: sanitizedRect.width,
            height: sanitizedRect.height
        ).standardized
    }

    static func sanitizedSize(_ size: CGSize) -> CGSize {
        guard
            size.width.isFinite,
            size.height.isFinite
        else {
            return .zero
        }

        return CGSize(
            width: max(size.width, 0),
            height: max(size.height, 0)
        )
    }
}

struct CanvasChromeLayoutContext: Hashable, Sendable {
    var safeBounds: CGRect
    var toolbarPreferredPlacement: CanvasToolbarPlacement
    var toolbarMeasuredSize: CGSize
    var chromeBlockers: [CanvasChromeBlocker]

    init(
        safeBounds: CGRect,
        toolbarPreferredPlacement: CanvasToolbarPlacement,
        toolbarMeasuredSize: CGSize,
        chromeBlockers: [CanvasChromeBlocker]
    ) {
        self.safeBounds = CanvasChromeLayoutGeometry.sanitizedRect(safeBounds) ?? .zero
        self.toolbarPreferredPlacement = toolbarPreferredPlacement
        self.toolbarMeasuredSize = CanvasChromeLayoutGeometry.sanitizedSize(
            toolbarMeasuredSize
        )
        self.chromeBlockers = chromeBlockers.compactMap { blocker in
            guard let sanitizedRect = CanvasChromeLayoutGeometry.sanitizedRect(
                blocker.rect
            ) else {
                return nil
            }

            return CanvasChromeBlocker(
                kind: blocker.kind,
                rect: sanitizedRect
            )
        }
    }

    var occupiedRects: [CGRect] {
        chromeBlockers.map(\.rect)
    }

    func occupiedRects(
        excluding excludedKinds: Set<CanvasChromeBlockerKind>
    ) -> [CGRect] {
        chromeBlockers
            .filter { excludedKinds.contains($0.kind) == false }
            .map(\.rect)
    }
}
