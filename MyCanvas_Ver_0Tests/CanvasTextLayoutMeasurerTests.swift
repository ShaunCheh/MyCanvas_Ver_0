import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

final class CanvasTextLayoutMeasurerTests: XCTestCase {
    func testIntrinsicContentSizeGrowsWithFontSize() {
        let smallStyle = CanvasTextStyle(fontSize: 16)
        let largeStyle = CanvasTextStyle(fontSize: 48)

        let smallSize = CanvasTextLayoutMeasurer.intrinsicContentSize(
            for: "Hello",
            style: smallStyle
        )
        let largeSize = CanvasTextLayoutMeasurer.intrinsicContentSize(
            for: "Hello",
            style: largeStyle
        )

        XCTAssertGreaterThan(largeSize.width, smallSize.width)
        XCTAssertGreaterThan(largeSize.height, smallSize.height)
    }

    func testIntrinsicItemSizeAppliesInsetsAndMinimums() {
        let style = CanvasTextStyle(fontSize: 18)
        let metrics = CanvasTextLayoutMetrics(
            minimumSize: CGSize(width: 120, height: 72),
            horizontalInset: 12,
            verticalInset: 10
        )

        let contentSize = CanvasTextLayoutMeasurer.intrinsicContentSize(
            for: "Hi",
            style: style
        )
        let itemSize = CanvasTextLayoutMeasurer.intrinsicItemSize(
            for: "Hi",
            style: style,
            metrics: metrics
        )

        XCTAssertGreaterThanOrEqual(itemSize.width, contentSize.width + metrics.horizontalInset * 2)
        XCTAssertGreaterThanOrEqual(itemSize.height, contentSize.height + metrics.verticalInset * 2)
        XCTAssertGreaterThanOrEqual(itemSize.width, metrics.minimumSize.width)
        XCTAssertGreaterThanOrEqual(itemSize.height, metrics.minimumSize.height)
    }
}
