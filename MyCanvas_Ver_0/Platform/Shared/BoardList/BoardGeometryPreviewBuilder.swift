import CoreGraphics
import Foundation

struct BoardGeometryPreviewBuilder {
    func makeSeed(from document: BoardDocument) -> BoardPreviewSeed {
        let nodes = makeNodes(from: document.items)
        let boardWorldRect = resolveBoardWorldRect(
            documentBoardRect: document.boardRect?.cgRect,
            nodes: nodes
        )
        return BoardPreviewSeed(
            boardWorldRect: boardWorldRect,
            nodes: nodes
        )
    }

    func makeSnapshot(from seed: BoardPreviewSeed) -> CanvasMiniMapSnapshot {
        CanvasMiniMapSnapshot(
            boardWorldRect: seed.boardWorldRect,
            displayWorldRect: resolveDisplayWorldRect(
                boardWorldRect: seed.boardWorldRect,
                nodes: seed.nodes
            ),
            visibleWorldRect: .zero,
            nodes: seed.nodes
        )
    }

    private func makeNodes(
        from itemRecords: [BoardItemRecord]
    ) -> [CanvasMiniMapNode] {
        itemRecords
            .compactMap(makeNode)
            .sorted { lhs, rhs in
                if lhs.zIndex == rhs.zIndex {
                    return lhs.id.uuidString < rhs.id.uuidString
                }

                return lhs.zIndex < rhs.zIndex
            }
    }

    private func makeNode(
        from itemRecord: BoardItemRecord
    ) -> CanvasMiniMapNode? {
        switch itemRecord {
        case let .image(imageRecord):
            return makeNode(
                id: imageRecord.id,
                kind: .image,
                center: imageRecord.center,
                size: imageRecord.size,
                zIndex: imageRecord.zIndex,
                rotationRadians: imageRecord.rotationRadians
            )
        case let .text(textRecord):
            return makeNode(
                id: textRecord.id,
                kind: .text,
                center: textRecord.center,
                size: textRecord.size,
                zIndex: textRecord.zIndex,
                rotationRadians: textRecord.rotationRadians
            )
        }
    }

    private func makeNode(
        id: UUID,
        kind: CanvasMiniMapNodeKind,
        center: BoardPointRecord,
        size: BoardSizeRecord,
        zIndex: Double,
        rotationRadians: Double?
    ) -> CanvasMiniMapNode? {
        let resolvedSize = size.cgSize
        guard resolvedSize.width > 0, resolvedSize.height > 0 else {
            return nil
        }

        return CanvasMiniMapNode(
            id: id,
            kind: kind,
            worldQuad: makeVisibleWorldQuad(
                center: center,
                size: size,
                rotationRadians: rotationRadians
            ),
            zIndex: CGFloat(zIndex),
            isPreviewActive: false
        )
    }

    private func makeVisibleWorldQuad(
        center: BoardPointRecord,
        size: BoardSizeRecord,
        rotationRadians: Double?
    ) -> CanvasQuad {
        // Persisted item size is already the committed visible footprint, so the
        // catalog preview can rebuild board geometry without decoding image assets
        // or creating runtime text layout.
        let localFrame = CGRect(
            x: -size.cgSize.width / 2,
            y: -size.cgSize.height / 2,
            width: size.cgSize.width,
            height: size.cgSize.height
        )
        let localQuad = CanvasQuad(rect: localFrame)
        let worldCenter = center.cgPoint
        let normalizedRotationRadians = normalizedCanvasAngle(
            CGFloat(rotationRadians ?? 0)
        )

        return localQuad.map { localPoint in
            let rotatedPoint = rotated(localPoint, by: normalizedRotationRadians)
            return CGPoint(
                x: rotatedPoint.x + worldCenter.x,
                y: rotatedPoint.y + worldCenter.y
            )
        }
    }

    private func resolveBoardWorldRect(
        documentBoardRect: CGRect?,
        nodes: [CanvasMiniMapNode]
    ) -> CGRect {
        if let boardWorldRect = sanitizedWorldRect(documentBoardRect) {
            return boardWorldRect
        }

        return combinedWorldBounds(of: nodes) ?? .zero
    }

    private func resolveDisplayWorldRect(
        boardWorldRect: CGRect,
        nodes: [CanvasMiniMapNode]
    ) -> CGRect {
        var resolvedDisplayWorldRect = sanitizedWorldRect(boardWorldRect)

        if let nodeBounds = combinedWorldBounds(of: nodes) {
            if let currentDisplayWorldRect = resolvedDisplayWorldRect {
                resolvedDisplayWorldRect = currentDisplayWorldRect
                    .union(nodeBounds)
                    .standardized
            } else {
                resolvedDisplayWorldRect = nodeBounds
            }
        }

        return resolvedDisplayWorldRect ?? .zero
    }

    private func combinedWorldBounds(of nodes: [CanvasMiniMapNode]) -> CGRect? {
        var combinedBounds: CGRect?

        for node in nodes {
            let nodeBounds = node.worldBounds
            guard let sanitizedNodeBounds = sanitizedWorldRect(nodeBounds) else {
                continue
            }

            if let existingBounds = combinedBounds {
                combinedBounds = existingBounds.union(sanitizedNodeBounds).standardized
            } else {
                combinedBounds = sanitizedNodeBounds
            }
        }

        return combinedBounds
    }

    private func sanitizedWorldRect(_ rect: CGRect?) -> CGRect? {
        guard let rect else {
            return nil
        }

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

    private func rotated(
        _ point: CGPoint,
        by radians: CGFloat
    ) -> CGPoint {
        guard radians != 0 else {
            return point
        }

        let cosine = cos(radians)
        let sine = sin(radians)
        return CGPoint(
            x: point.x * cosine - point.y * sine,
            y: point.x * sine + point.y * cosine
        )
    }
}
