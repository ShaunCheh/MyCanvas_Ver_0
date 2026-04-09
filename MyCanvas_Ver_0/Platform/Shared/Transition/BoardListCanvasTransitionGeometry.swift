import CoreGraphics
import Foundation

struct BoardListCanvasTransitionSourceGeometry: Hashable, Sendable {
    var cardRect: CGRect?
    var focusRect: CGRect?

    init(
        cardRect: CGRect? = nil,
        focusRect: CGRect? = nil
    ) {
        self.cardRect = BoardListCanvasTransitionGeometry.sanitizedRect(
            cardRect
        )
        self.focusRect = BoardListCanvasTransitionGeometry.sanitizedRect(
            focusRect
        )
    }

    var preferredRect: CGRect? {
        focusRect ?? cardRect
    }
}

struct BoardListCanvasTransitionTargetGeometry: Hashable, Sendable {
    var cardRect: CGRect?
    var focusRect: CGRect?

    init(
        cardRect: CGRect? = nil,
        focusRect: CGRect? = nil
    ) {
        self.cardRect = BoardListCanvasTransitionGeometry.sanitizedRect(
            cardRect
        )
        self.focusRect = BoardListCanvasTransitionGeometry.sanitizedRect(
            focusRect
        )
    }

    var preferredRect: CGRect? {
        focusRect ?? cardRect
    }
}

enum BoardListCanvasTransitionGeometry {
    static func sanitizedRect(_ rect: CGRect?) -> CGRect? {
        guard let rect else {
            return nil
        }

        let standardizedRect = rect.standardized
        guard
            rectHasFiniteComponents(standardizedRect),
            standardizedRect.isNull == false,
            standardizedRect.isInfinite == false,
            standardizedRect.isEmpty == false
        else {
            return nil
        }

        return standardizedRect
    }

    private static func rectHasFiniteComponents(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite &&
            rect.origin.y.isFinite &&
            rect.width.isFinite &&
            rect.height.isFinite
    }
}
