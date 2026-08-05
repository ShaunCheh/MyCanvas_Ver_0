import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasImportLayoutSolverTests: XCTestCase {
    private let solver = CanvasImportLayoutSolver()

    func testAutomaticUsesStackedForZeroOrOneAndGridForBatchCounts() throws {
        let emptyResult = solver.resolve(
            requestedLayout: .automatic,
            itemBoundingSizes: []
        )
        XCTAssertEqual(emptyResult.effectiveLayout, .stacked)
        XCTAssertEqual(emptyResult.itemOffsets, [])
        XCTAssertEqual(emptyResult.contentSize, .zero)

        let itemSize = CGSize(width: 100, height: 80)
        let singleResult = solver.resolve(
            requestedLayout: .automatic,
            itemBoundingSizes: [itemSize]
        )
        XCTAssertEqual(singleResult.effectiveLayout, .stacked)
        XCTAssertEqual(singleResult.itemOffsets, [.zero])
        XCTAssertEqual(singleResult.contentSize, itemSize)

        let configuration = CanvasBatchImportLayoutConfiguration.current.grid
        for itemCount in [2, 4, 5, 8, 9] {
            let result = solver.resolve(
                requestedLayout: .automatic,
                itemBoundingSizes: Array(
                    repeating: itemSize,
                    count: itemCount
                )
            )

            try assertGridLayout(
                result,
                itemCount: itemCount,
                cellSize: itemSize,
                configuration: configuration
            )
        }
    }

    func testExplicitGridHandlesOneColumnCustomColumnsAndIncompleteRows() throws {
        let cases: [
            (
                itemCount: Int,
                configuration: CanvasImportGridConfiguration
            )
        ] = [
            (
                3,
                CanvasImportGridConfiguration(
                    columns: 1,
                    horizontalSpacing: 7,
                    verticalSpacing: 9
                )
            ),
            (
                2,
                CanvasImportGridConfiguration(
                    columns: 5,
                    horizontalSpacing: 11,
                    verticalSpacing: 13
                )
            ),
            (
                5,
                CanvasImportGridConfiguration(
                    columns: 3,
                    horizontalSpacing: 17,
                    verticalSpacing: 19
                )
            )
        ]
        let itemSize = CGSize(width: 40, height: 30)

        for testCase in cases {
            let configuration = testCase.configuration
            let result = solver.resolve(
                requestedLayout: .grid(
                    columns: configuration.columns,
                    horizontalSpacing: configuration.horizontalSpacing,
                    verticalSpacing: configuration.verticalSpacing
                ),
                itemBoundingSizes: Array(
                    repeating: itemSize,
                    count: testCase.itemCount
                )
            )

            try assertGridLayout(
                result,
                itemCount: testCase.itemCount,
                cellSize: itemSize,
                configuration: configuration
            )
        }
    }

    func testGridUsesMaximumBoundingSizeWithoutOverlappingMixedAspectItems() throws {
        let itemBoundingSizes = [
            CGSize(width: 320, height: 120),
            CGSize(width: 100, height: 300),
            CGSize(width: 200, height: 200)
        ]
        let configuration = CanvasImportGridConfiguration(
            columns: 2,
            horizontalSpacing: 16,
            verticalSpacing: 20
        )

        let result = solver.resolve(
            requestedLayout: .grid(
                columns: configuration.columns,
                horizontalSpacing: configuration.horizontalSpacing,
                verticalSpacing: configuration.verticalSpacing
            ),
            itemBoundingSizes: itemBoundingSizes
        )

        try assertGridLayout(
            result,
            itemCount: itemBoundingSizes.count,
            cellSize: CGSize(width: 320, height: 300),
            configuration: configuration
        )
        assertItemsDoNotOverlap(
            sizes: itemBoundingSizes,
            offsets: result.itemOffsets
        )
    }

    func testDiagonalPreservesZeroPositiveAndNegativeIndexTimesStepFormula() {
        let itemBoundingSizes = Array(
            repeating: CGSize(width: 20, height: 10),
            count: 3
        )
        let steps = [
            CGPoint.zero,
            CGPoint(x: 12, y: 18),
            CGPoint(x: -12, y: -18)
        ]

        for step in steps {
            let result = solver.resolve(
                requestedLayout: .diagonal(stepInWorld: step),
                itemBoundingSizes: itemBoundingSizes
            )

            XCTAssertEqual(
                result.effectiveLayout,
                .diagonal(stepInWorld: step)
            )
            XCTAssertEqual(
                result.itemOffsets,
                [
                    .zero,
                    step,
                    CGPoint(x: step.x * 2, y: step.y * 2)
                ]
            )
        }
    }

    func testAllLayoutsReturnOneFiniteOffsetPerInputAndHandleEmptyInput() {
        let layouts: [CanvasImportLayout] = [
            .automatic,
            .stacked,
            .diagonal(stepInWorld: CGPoint(x: 10, y: 20)),
            .grid(
                columns: 2,
                horizontalSpacing: 8,
                verticalSpacing: 12
            )
        ]
        let invalidSizes = [
            CGSize.zero,
            CGSize(width: CGFloat.nan, height: CGFloat.infinity)
        ]

        for layout in layouts {
            let result = solver.resolve(
                requestedLayout: layout,
                itemBoundingSizes: invalidSizes
            )
            XCTAssertEqual(result.itemOffsets.count, invalidSizes.count)
            XCTAssertTrue(
                result.itemOffsets.allSatisfy {
                    $0.x.isFinite && $0.y.isFinite
                }
            )
            XCTAssertTrue(result.contentSize.width.isFinite)
            XCTAssertTrue(result.contentSize.height.isFinite)

            let emptyResult = solver.resolve(
                requestedLayout: layout,
                itemBoundingSizes: []
            )
            XCTAssertEqual(emptyResult.itemOffsets, [])
            XCTAssertEqual(emptyResult.contentSize, .zero)
        }
    }
}

@MainActor
private func assertGridLayout(
    _ result: CanvasResolvedImportLayout,
    itemCount: Int,
    cellSize: CGSize,
    configuration: CanvasImportGridConfiguration,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let gridConfiguration = try XCTUnwrap(
        result.effectiveLayout.gridConfiguration,
        file: file,
        line: line
    )
    XCTAssertEqual(
        gridConfiguration,
        configuration,
        file: file,
        line: line
    )
    XCTAssertEqual(
        result.itemOffsets.count,
        itemCount,
        file: file,
        line: line
    )

    let usedColumnCount = min(configuration.columns, itemCount)
    let rowCount = ((itemCount - 1) / configuration.columns) + 1
    let horizontalPitch =
        cellSize.width + configuration.horizontalSpacing
    let verticalPitch =
        cellSize.height + configuration.verticalSpacing
    let expectedContentSize = CGSize(
        width: CGFloat(usedColumnCount) * cellSize.width
            + CGFloat(usedColumnCount - 1)
            * configuration.horizontalSpacing,
        height: CGFloat(rowCount) * cellSize.height
            + CGFloat(rowCount - 1)
            * configuration.verticalSpacing
    )
    XCTAssertEqual(
        result.contentSize,
        expectedContentSize,
        file: file,
        line: line
    )

    let firstCellCenter = CGPoint(
        x: (-expectedContentSize.width + cellSize.width) / 2,
        y: (-expectedContentSize.height + cellSize.height) / 2
    )
    let expectedOffsets = (0..<itemCount).map { index in
        CGPoint(
            x: firstCellCenter.x
                + CGFloat(index % configuration.columns) * horizontalPitch,
            y: firstCellCenter.y
                + CGFloat(index / configuration.columns) * verticalPitch
        )
    }
    XCTAssertEqual(
        result.itemOffsets,
        expectedOffsets,
        file: file,
        line: line
    )
}

@MainActor
private func assertItemsDoNotOverlap(
    sizes: [CGSize],
    offsets: [CGPoint],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let frames = zip(sizes, offsets).map { size, offset in
        CGRect(
            x: offset.x - size.width / 2,
            y: offset.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    for firstIndex in frames.indices {
        for secondIndex in frames.indices where secondIndex > firstIndex {
            XCTAssertFalse(
                frames[firstIndex].intersects(frames[secondIndex]),
                "Items \(firstIndex) and \(secondIndex) overlap.",
                file: file,
                line: line
            )
        }
    }
}
