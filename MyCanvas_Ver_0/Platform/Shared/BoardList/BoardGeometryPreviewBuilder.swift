import CoreGraphics
import Foundation

struct BoardGeometryPreviewBuilder {
    func makeSeed(from document: BoardDocument) -> BoardPreviewSeed {
        let nodes = makeNodes(
            from: document.items,
            boardID: document.boardID
        )
        let boardWorldRect = resolveBoardWorldRect(
            documentBoardRect: document.boardRect?.cgRect,
            nodes: nodes
        )
        logBoardPreviewSeedSummary(
            boardID: document.boardID,
            itemCount: document.items.count,
            nodeCount: nodes.count,
            boardWorldRect: boardWorldRect
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
        from itemRecords: [BoardItemRecord],
        boardID: UUID? = nil
    ) -> [CanvasMiniMapNode] {
        itemRecords
            .enumerated()
            .compactMap { documentOrder, itemRecord in
                makeNode(
                    from: itemRecord,
                    boardID: boardID,
                    documentOrder: documentOrder
                )
            }
            .sorted { lhs, rhs in
                if lhs.zIndex == rhs.zIndex {
                    return lhs.id.uuidString < rhs.id.uuidString
                }

                return lhs.zIndex < rhs.zIndex
            }
    }

    private func makeNode(
        from itemRecord: BoardItemRecord,
        boardID: UUID? = nil,
        documentOrder: Int
    ) -> CanvasMiniMapNode? {
        switch itemRecord {
        case let .image(imageRecord):
            return makeNode(
                boardID: boardID,
                documentOrder: documentOrder,
                id: imageRecord.id,
                kind: .image,
                center: imageRecord.center,
                size: imageRecord.size,
                zIndex: imageRecord.zIndex,
                rotationRadians: imageRecord.rotationRadians
            )
        case let .text(textRecord):
            return makeNode(
                boardID: boardID,
                documentOrder: documentOrder,
                id: textRecord.id,
                kind: .text,
                center: textRecord.center,
                size: textRecord.size,
                zIndex: textRecord.zIndex,
                rotationRadians: textRecord.rotationRadians
            )
        case let .markdown(markdownRecord):
            return makeNode(
                boardID: boardID,
                documentOrder: documentOrder,
                id: markdownRecord.id,
                kind: .markdown,
                center: markdownRecord.center,
                size: markdownRecord.size,
                zIndex: markdownRecord.zIndex,
                rotationRadians: markdownRecord.rotationRadians
            )
        case let .handDrawing(handDrawingRecord):
            return makeNode(
                boardID: boardID,
                documentOrder: documentOrder,
                id: handDrawingRecord.id,
                kind: .handDrawing,
                center: handDrawingRecord.center,
                size: handDrawingRecord.size,
                zIndex: handDrawingRecord.zIndex,
                rotationRadians: handDrawingRecord.rotationRadians
            )
        case let .arrow(arrowRecord):
            let arrowItem = CanvasArrowItem(
                id: arrowRecord.id,
                startPoint: arrowRecord.startPoint.cgPoint,
                endPoint: arrowRecord.endPoint.cgPoint,
                shaftThickness: CGFloat(arrowRecord.shaftThickness),
                zIndex: CGFloat(arrowRecord.zIndex)
            )
            return makeNode(
                boardID: boardID,
                documentOrder: documentOrder,
                id: arrowRecord.id,
                kind: .shape,
                center: BoardPointRecord(arrowItem.center),
                size: BoardSizeRecord(arrowItem.size),
                zIndex: arrowRecord.zIndex,
                rotationRadians: Double(arrowItem.rotationRadians)
            )
        }
    }

    private func makeNode(
        boardID: UUID?,
        documentOrder: Int,
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

        let worldQuad = makeVisibleWorldQuad(
            center: center,
            size: size,
            rotationRadians: rotationRadians
        )
        logBoardPreviewSeedNode(
            boardID: boardID,
            documentOrder: documentOrder,
            itemID: id,
            kind: kind,
            worldCenter: center.cgPoint,
            worldSize: resolvedSize,
            zIndex: CGFloat(zIndex),
            rotationRadians: normalizedCanvasAngle(
                CGFloat(rotationRadians ?? 0)
            ),
            worldQuad: worldQuad
        )

        return CanvasMiniMapNode(
            id: id,
            kind: kind,
            worldQuad: worldQuad,
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

private func logBoardPreviewSeedSummary(
    boardID: UUID,
    itemCount: Int,
    nodeCount: Int,
    boardWorldRect: CGRect
) {
    // Temporarily muted: BoardList ThumbnailTrace noise.
    #if false
    print(
        "[BoardList][ThumbnailTrace][Seed] " +
            "boardID=\(boardID.uuidString) " +
            "itemCount=\(itemCount) " +
            "nodeCount=\(nodeCount) " +
            "boardWorldRect=\(describeBoardPreviewRect(boardWorldRect))"
    )
    #endif
}

private func logBoardPreviewSeedNode(
    boardID: UUID?,
    documentOrder: Int,
    itemID: UUID,
    kind: CanvasMiniMapNodeKind,
    worldCenter: CGPoint,
    worldSize: CGSize,
    zIndex: CGFloat,
    rotationRadians: CGFloat,
    worldQuad: CanvasQuad
) {
    // Temporarily muted: BoardList ThumbnailTrace noise.
    #if false
    print(
        "[BoardList][ThumbnailTrace][SeedNode] " +
            "boardID=\(boardID?.uuidString ?? "nil") " +
            "documentOrder=\(documentOrder) " +
            "itemID=\(itemID.uuidString) " +
            "kind=\(describeBoardPreviewNodeKind(kind)) " +
            "worldCenter=\(describeBoardPreviewPoint(worldCenter)) " +
            "worldCenterY=\(formatBoardPreviewValue(worldCenter.y)) " +
            "worldSize=\(describeBoardPreviewSize(worldSize)) " +
            "zIndex=\(formatBoardPreviewValue(zIndex)) " +
            "rotationDeg=\(formatBoardPreviewValue(rotationRadians * 180 / .pi)) " +
            "worldQuad=\(describeBoardPreviewQuad(worldQuad))"
    )
    #endif
}

private func describeBoardPreviewNodeKind(_ kind: CanvasMiniMapNodeKind) -> String {
    switch kind {
    case .image:
        return "image"
    case .handDrawing:
        return "handDrawing"
    case .text:
        return "text"
    case .markdown:
        return "markdown"
    case .sticker:
        return "sticker"
    case .shape:
        return "shape"
    }
}

private func describeBoardPreviewQuad(_ quad: CanvasQuad) -> String {
    "tl=\(describeBoardPreviewPoint(quad.topLeading)) " +
        "tr=\(describeBoardPreviewPoint(quad.topTrailing)) " +
        "bl=\(describeBoardPreviewPoint(quad.bottomLeading)) " +
        "br=\(describeBoardPreviewPoint(quad.bottomTrailing))"
}

private func describeBoardPreviewRect(_ rect: CGRect) -> String {
    "{{\(formatBoardPreviewValue(rect.minX)), \(formatBoardPreviewValue(rect.minY))}, {\(formatBoardPreviewValue(rect.width)), \(formatBoardPreviewValue(rect.height))}}"
}

private func describeBoardPreviewPoint(_ point: CGPoint) -> String {
    "{\(formatBoardPreviewValue(point.x)), \(formatBoardPreviewValue(point.y))}"
}

private func describeBoardPreviewSize(_ size: CGSize) -> String {
    "{\(formatBoardPreviewValue(size.width)), \(formatBoardPreviewValue(size.height))}"
}

private func formatBoardPreviewValue(_ value: CGFloat) -> String {
    String(format: "%.2f", Double(value))
}
