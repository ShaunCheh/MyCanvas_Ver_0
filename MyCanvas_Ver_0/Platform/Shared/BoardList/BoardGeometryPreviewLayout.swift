import CoreGraphics
import Foundation

struct BoardGeometryPreviewLayout {
    let boardRect: CGRect?
    let nodePaths: [CGPath]

    init(
        seed: BoardPreviewSeed,
        viewBounds: CGRect,
        contentInset: CGFloat,
        geometryPreviewBuilder: BoardGeometryPreviewBuilder = BoardGeometryPreviewBuilder()
    ) {
        let snapshot = geometryPreviewBuilder.makeSnapshot(from: seed)
        guard
            let geometry = CanvasMiniMapViewGeometry(
                displayWorldRect: snapshot.displayWorldRect,
                viewBounds: viewBounds,
                contentInset: contentInset
            )
        else {
            boardRect = nil
            nodePaths = []
            return
        }

        let mappedBoardRect = geometry.worldToMiniMap(snapshot.boardWorldRect)
        if mappedBoardRect.width > 0, mappedBoardRect.height > 0 {
            boardRect = mappedBoardRect
        } else {
            boardRect = nil
        }

        nodePaths = snapshot.nodes.compactMap { node in
            let mappedQuad = geometry.worldToMiniMap(node.worldQuad)
            let mappedBounds = mappedQuad.boundingRect.standardized
            guard mappedBounds.width > 0, mappedBounds.height > 0 else {
                return nil
            }

            return mappedQuad.cgPath
        }
    }
}
