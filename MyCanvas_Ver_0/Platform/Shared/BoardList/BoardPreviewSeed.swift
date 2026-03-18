import CoreGraphics
import Foundation

struct BoardPreviewSeed {
    let boardWorldRect: CGRect
    let nodes: [CanvasMiniMapNode]

    static let empty = BoardPreviewSeed(
        boardWorldRect: .zero,
        nodes: []
    )
}
