import CoreGraphics
import Foundation

struct CanvasResolvedImportLayout: Equatable {
    let effectiveLayout: CanvasImportLayout
    let itemOffsets: [CGPoint]
    let contentSize: CGSize
}

struct CanvasImportLayoutSolver {
    func resolve(
        requestedLayout: CanvasImportLayout,
        itemBoundingSizes: [CGSize],
        automaticConfiguration: CanvasBatchImportLayoutConfiguration = .current
    ) -> CanvasResolvedImportLayout {
        let sanitizedItemBoundingSizes = itemBoundingSizes.map(
            sanitizedBoundingSize
        )
        let effectiveLayout = resolvedLayout(
            requestedLayout,
            itemCount: sanitizedItemBoundingSizes.count,
            automaticConfiguration: automaticConfiguration
        )

        switch effectiveLayout {
        case .automatic, .stacked:
            return stackedLayout(
                effectiveLayout: .stacked,
                itemBoundingSizes: sanitizedItemBoundingSizes
            )
        case let .diagonal(stepInWorld):
            return diagonalLayout(
                stepInWorld: stepInWorld,
                itemBoundingSizes: sanitizedItemBoundingSizes
            )
        case .grid:
            guard let gridConfiguration = effectiveLayout.gridConfiguration else {
                return stackedLayout(
                    effectiveLayout: .stacked,
                    itemBoundingSizes: sanitizedItemBoundingSizes
                )
            }

            return gridLayout(
                configuration: gridConfiguration,
                itemBoundingSizes: sanitizedItemBoundingSizes
            )
        }
    }

    private func resolvedLayout(
        _ requestedLayout: CanvasImportLayout,
        itemCount: Int,
        automaticConfiguration: CanvasBatchImportLayoutConfiguration
    ) -> CanvasImportLayout {
        switch requestedLayout {
        case .automatic:
            guard itemCount > 1 else {
                return .stacked
            }

            let gridConfiguration = automaticConfiguration.grid
            return .grid(
                columns: gridConfiguration.columns,
                horizontalSpacing: gridConfiguration.horizontalSpacing,
                verticalSpacing: gridConfiguration.verticalSpacing
            )
        case .stacked:
            return .stacked
        case let .diagonal(stepInWorld):
            return .diagonal(stepInWorld: stepInWorld)
        case let .grid(columns, horizontalSpacing, verticalSpacing):
            let gridConfiguration = CanvasImportGridConfiguration(
                columns: columns,
                horizontalSpacing: horizontalSpacing,
                verticalSpacing: verticalSpacing
            )
            return .grid(
                columns: gridConfiguration.columns,
                horizontalSpacing: gridConfiguration.horizontalSpacing,
                verticalSpacing: gridConfiguration.verticalSpacing
            )
        }
    }

    private func stackedLayout(
        effectiveLayout: CanvasImportLayout,
        itemBoundingSizes: [CGSize]
    ) -> CanvasResolvedImportLayout {
        CanvasResolvedImportLayout(
            effectiveLayout: effectiveLayout,
            itemOffsets: Array(
                repeating: .zero,
                count: itemBoundingSizes.count
            ),
            contentSize: maximumBoundingSize(in: itemBoundingSizes)
        )
    }

    private func diagonalLayout(
        stepInWorld: CGPoint,
        itemBoundingSizes: [CGSize]
    ) -> CanvasResolvedImportLayout {
        let itemOffsets = itemBoundingSizes.indices.map { index in
            let multiplier = CGFloat(index)
            return CGPoint(
                x: stepInWorld.x * multiplier,
                y: stepInWorld.y * multiplier
            )
        }
        return CanvasResolvedImportLayout(
            effectiveLayout: .diagonal(stepInWorld: stepInWorld),
            itemOffsets: itemOffsets,
            contentSize: contentSize(
                itemBoundingSizes: itemBoundingSizes,
                itemOffsets: itemOffsets
            )
        )
    }

    private func gridLayout(
        configuration: CanvasImportGridConfiguration,
        itemBoundingSizes: [CGSize]
    ) -> CanvasResolvedImportLayout {
        guard itemBoundingSizes.isEmpty == false else {
            return CanvasResolvedImportLayout(
                effectiveLayout: .grid(
                    columns: configuration.columns,
                    horizontalSpacing: configuration.horizontalSpacing,
                    verticalSpacing: configuration.verticalSpacing
                ),
                itemOffsets: [],
                contentSize: .zero
            )
        }

        let cellSize = maximumBoundingSize(in: itemBoundingSizes)
        let itemCount = itemBoundingSizes.count
        let usedColumnCount = min(configuration.columns, itemCount)
        let rowCount = ((itemCount - 1) / configuration.columns) + 1
        let horizontalPitch =
            cellSize.width + configuration.horizontalSpacing
        let verticalPitch =
            cellSize.height + configuration.verticalSpacing
        let contentSize = CGSize(
            width: CGFloat(usedColumnCount) * cellSize.width
                + CGFloat(usedColumnCount - 1)
                * configuration.horizontalSpacing,
            height: CGFloat(rowCount) * cellSize.height
                + CGFloat(rowCount - 1)
                * configuration.verticalSpacing
        )
        let firstCellCenter = CGPoint(
            x: (-contentSize.width + cellSize.width) / 2,
            y: (-contentSize.height + cellSize.height) / 2
        )
        let itemOffsets = itemBoundingSizes.indices.map { index in
            let columnIndex = index % configuration.columns
            let rowIndex = index / configuration.columns
            return CGPoint(
                x: firstCellCenter.x
                    + CGFloat(columnIndex) * horizontalPitch,
                y: firstCellCenter.y
                    + CGFloat(rowIndex) * verticalPitch
            )
        }

        return CanvasResolvedImportLayout(
            effectiveLayout: .grid(
                columns: configuration.columns,
                horizontalSpacing: configuration.horizontalSpacing,
                verticalSpacing: configuration.verticalSpacing
            ),
            itemOffsets: itemOffsets,
            contentSize: contentSize
        )
    }

    private func sanitizedBoundingSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: sanitizedDimension(size.width),
            height: sanitizedDimension(size.height)
        )
    }

    private func sanitizedDimension(_ dimension: CGFloat) -> CGFloat {
        dimension.isFinite ? max(dimension, 1) : 1
    }

    private func maximumBoundingSize(in sizes: [CGSize]) -> CGSize {
        guard sizes.isEmpty == false else {
            return .zero
        }

        return CGSize(
            width: sizes.map(\.width).max() ?? 1,
            height: sizes.map(\.height).max() ?? 1
        )
    }

    private func contentSize(
        itemBoundingSizes: [CGSize],
        itemOffsets: [CGPoint]
    ) -> CGSize {
        let contentBounds = zip(
            itemBoundingSizes,
            itemOffsets
        ).reduce(into: CGRect.null) { partialResult, item in
            let (size, offset) = item
            partialResult = partialResult.union(
                CGRect(
                    x: offset.x - size.width / 2,
                    y: offset.y - size.height / 2,
                    width: size.width,
                    height: size.height
                )
            )
        }
        return contentBounds.isNull
            ? .zero
            : contentBounds.standardized.size
    }
}
