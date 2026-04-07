import CoreGraphics
import Foundation

// Keep GIF frame import defaults centralized so later phases can reuse one
// shared source instead of hard-coding editor and board layout values.
struct CanvasGIFFrameImportInsets: Equatable {
    var top: CGFloat
    var leading: CGFloat
    var bottom: CGFloat
    var trailing: CGFloat

    init(
        top: CGFloat,
        leading: CGFloat,
        bottom: CGFloat,
        trailing: CGFloat
    ) {
        self.top = max(top, 0)
        self.leading = max(leading, 0)
        self.bottom = max(bottom, 0)
        self.trailing = max(trailing, 0)
    }

    static func uniform(_ value: CGFloat) -> CanvasGIFFrameImportInsets {
        CanvasGIFFrameImportInsets(
            top: value,
            leading: value,
            bottom: value,
            trailing: value
        )
    }
}

struct CanvasGIFFrameImportGridConfiguration: Equatable {
    var columns: Int
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat
    var contentInsets: CanvasGIFFrameImportInsets

    init(
        columns: Int,
        horizontalSpacing: CGFloat,
        verticalSpacing: CGFloat,
        contentInsets: CanvasGIFFrameImportInsets
    ) {
        self.columns = max(columns, 1)
        self.horizontalSpacing = max(horizontalSpacing, 0)
        self.verticalSpacing = max(verticalSpacing, 0)
        self.contentInsets = contentInsets
    }
}

struct CanvasGIFFrameImportConfiguration: Equatable {
    static let sharedDefaultColumnCount = 4

    static let current = CanvasGIFFrameImportConfiguration(
        selectionGrid: CanvasGIFFrameImportGridConfiguration(
            columns: sharedDefaultColumnCount,
            horizontalSpacing: 12,
            verticalSpacing: 12,
            contentInsets: .uniform(16)
        ),
        boardPlacementGrid: CanvasGIFFrameImportGridConfiguration(
            columns: sharedDefaultColumnCount,
            horizontalSpacing: 24,
            verticalSpacing: 24,
            contentInsets: .uniform(24)
        ),
        thumbnailMaxPixelSize: 240
    )

    var selectionGrid: CanvasGIFFrameImportGridConfiguration
    var boardPlacementGrid: CanvasGIFFrameImportGridConfiguration
    var thumbnailMaxPixelSize: Int

    init(
        selectionGrid: CanvasGIFFrameImportGridConfiguration,
        boardPlacementGrid: CanvasGIFFrameImportGridConfiguration,
        thumbnailMaxPixelSize: Int
    ) {
        self.selectionGrid = selectionGrid
        self.boardPlacementGrid = boardPlacementGrid
        self.thumbnailMaxPixelSize = max(thumbnailMaxPixelSize, 64)
    }
}
