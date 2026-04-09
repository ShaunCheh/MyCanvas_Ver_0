import CoreGraphics
import Foundation

enum BoardListCanvasTransitionFocusRectResolver {
    private enum Layout {
        static let previewInset: CGFloat = 12
        static let previewGridHeight: CGFloat = 120
        static let previewListSize = CGSize(width: 72, height: 72)
        static let placeholderIconSize = CGSize(width: 22, height: 22)
        static let placeholderListLeadingInset: CGFloat = 24
    }

    static func focusRect(
        in cardRect: CGRect?,
        displayMode: BoardListDisplayMode,
        isPlaceholder: Bool
    ) -> CGRect? {
        guard
            let cardRect = BoardListCanvasTransitionGeometry.sanitizedRect(
                cardRect
            )
        else {
            return nil
        }

        let rawRect: CGRect
        switch (isPlaceholder, displayMode) {
        case (false, .grid):
            rawRect = CGRect(
                x: cardRect.minX + Layout.previewInset,
                y: cardRect.minY + Layout.previewInset,
                width: cardRect.width - (Layout.previewInset * 2),
                height: Layout.previewGridHeight
            )
        case (false, .list):
            rawRect = CGRect(
                x: cardRect.minX + Layout.previewInset,
                y: cardRect.midY - (Layout.previewListSize.height / 2),
                width: Layout.previewListSize.width,
                height: Layout.previewListSize.height
            )
        case (true, .grid):
            rawRect = CGRect(
                x: cardRect.midX - (Layout.placeholderIconSize.width / 2),
                y: cardRect.midY - (Layout.placeholderIconSize.height / 2),
                width: Layout.placeholderIconSize.width,
                height: Layout.placeholderIconSize.height
            )
        case (true, .list):
            rawRect = CGRect(
                x: cardRect.minX + Layout.placeholderListLeadingInset,
                y: cardRect.midY - (Layout.placeholderIconSize.height / 2),
                width: Layout.placeholderIconSize.width,
                height: Layout.placeholderIconSize.height
            )
        }

        return BoardListCanvasTransitionGeometry.sanitizedRect(rawRect)
    }
}
