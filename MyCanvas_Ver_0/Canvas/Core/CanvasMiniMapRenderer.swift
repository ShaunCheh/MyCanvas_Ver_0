import CoreGraphics
import Foundation

struct CanvasMiniMapRenderer {
    private let nodeProviders: [any CanvasMiniMapNodeProviding]

    init(nodeProviders: [any CanvasMiniMapNodeProviding]? = nil) {
        self.nodeProviders = nodeProviders ?? [CanvasMiniMapImageNodeProvider()]
    }

    func makeSnapshot(
        context: CanvasMiniMapRenderContext
    ) -> CanvasMiniMapSnapshot {
        let visibleWorldRect = sanitizedWorldRect(context.camera.visibleWorldRect) ?? .zero
        let nodes = resolveNodes(using: context.nodeProviderContext)

        let boardWorldRect = resolveBoardWorldRect(
            boardState: context.boardState,
            nodes: nodes,
            fallbackVisibleWorldRect: visibleWorldRect
        )
        let displayWorldRect = resolveDisplayWorldRect(
            boardWorldRect: boardWorldRect,
            visibleWorldRect: visibleWorldRect,
            nodes: nodes,
            fallbackVisibleWorldRect: visibleWorldRect
        )

        return CanvasMiniMapSnapshot(
            boardWorldRect: boardWorldRect,
            displayWorldRect: displayWorldRect,
            visibleWorldRect: visibleWorldRect,
            nodes: nodes
        )
    }

    private func resolveNodes(
        using context: CanvasMiniMapNodeProviderContext
    ) -> [CanvasMiniMapNode] {
        nodeProviders
            .flatMap { $0.makeNodes(context: context) }
            .sorted { lhs, rhs in
                if lhs.zIndex == rhs.zIndex {
                    return lhs.id.uuidString < rhs.id.uuidString
                }

                return lhs.zIndex < rhs.zIndex
            }
    }

    private func resolveBoardWorldRect(
        boardState: CanvasBoardState?,
        nodes: [CanvasMiniMapNode],
        fallbackVisibleWorldRect: CGRect
    ) -> CGRect {
        if let boardWorldRect = boardState.flatMap({ sanitizedWorldRect($0.worldRect) }) {
            return boardWorldRect
        }

        if let nodeBounds = combinedWorldBounds(of: nodes) {
            return nodeBounds
        }

        return fallbackVisibleWorldRect
    }

    private func resolveDisplayWorldRect(
        boardWorldRect: CGRect,
        visibleWorldRect: CGRect,
        nodes: [CanvasMiniMapNode],
        fallbackVisibleWorldRect: CGRect
    ) -> CGRect {
        var resolvedDisplayWorldRect = sanitizedWorldRect(boardWorldRect)
            ?? sanitizedWorldRect(fallbackVisibleWorldRect)

        if let previewWorldBounds = combinedWorldBounds(
            of: nodes.filter(\.isPreviewActive)
        ) {
            if let currentDisplayWorldRect = resolvedDisplayWorldRect {
                resolvedDisplayWorldRect = currentDisplayWorldRect
                    .union(previewWorldBounds)
                    .standardized
            } else {
                resolvedDisplayWorldRect = previewWorldBounds
            }
        }

        // Keep the viewport frame representable even if the user pans outside the
        // committed board bounds before any board expansion happens.
        if let sanitizedVisibleWorldRect = sanitizedWorldRect(visibleWorldRect) {
            if let currentDisplayWorldRect = resolvedDisplayWorldRect {
                resolvedDisplayWorldRect = currentDisplayWorldRect
                    .union(sanitizedVisibleWorldRect)
                    .standardized
            } else {
                resolvedDisplayWorldRect = sanitizedVisibleWorldRect
            }
        }

        return resolvedDisplayWorldRect ?? fallbackVisibleWorldRect
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

    private func sanitizedWorldRect(_ rect: CGRect) -> CGRect? {
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
