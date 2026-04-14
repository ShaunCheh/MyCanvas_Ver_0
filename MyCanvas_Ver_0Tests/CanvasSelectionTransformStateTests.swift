import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

final class CanvasSelectionTransformStateTests: XCTestCase {
    func testTranslatedMemberGeometriesApplySharedWorldDelta() throws {
        let firstID = CanvasItemID()
        let secondID = CanvasItemID()
        let snapshot = CanvasSelectionTransformSnapshot(
            primaryItemID: secondID,
            memberGeometries: [
                CanvasBoardItemGeometry(
                    itemID: firstID,
                    center: CGPoint(x: 10, y: 20),
                    size: CGSize(width: 40, height: 20),
                    rotationRadians: 0
                ),
                CanvasBoardItemGeometry(
                    itemID: secondID,
                    center: CGPoint(x: 70, y: 50),
                    size: CGSize(width: 30, height: 10),
                    rotationRadians: .pi / 6
                )
            ],
            selectionBounds: CGRect(x: -10, y: 10, width: 95, height: 50)
        )

        let translated = snapshot.translatedMemberGeometries(
            by: CGPoint(x: 15, y: -8)
        )
        let firstGeometry = try XCTUnwrap(
            translated.first(where: { $0.itemID == firstID })
        )
        let secondGeometry = try XCTUnwrap(
            translated.first(where: { $0.itemID == secondID })
        )

        XCTAssertEqual(firstGeometry.center, CGPoint(x: 25, y: 12))
        XCTAssertEqual(secondGeometry.center, CGPoint(x: 85, y: 42))
        XCTAssertEqual(secondGeometry.rotationRadians, .pi / 6, accuracy: 0.0001)
    }

    func testResizedMemberGeometriesScaleCentersAndSizesFromFixedCorner() throws {
        let firstID = CanvasItemID()
        let secondID = CanvasItemID()
        let snapshot = CanvasSelectionTransformSnapshot(
            primaryItemID: secondID,
            memberGeometries: [
                CanvasBoardItemGeometry(
                    itemID: firstID,
                    center: CGPoint(x: 25, y: 25),
                    size: CGSize(width: 20, height: 20),
                    rotationRadians: 0
                ),
                CanvasBoardItemGeometry(
                    itemID: secondID,
                    center: CGPoint(x: 75, y: 75),
                    size: CGSize(width: 40, height: 20),
                    rotationRadians: .pi / 4
                )
            ],
            selectionBounds: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        let resized = snapshot.resizedMemberGeometries(
            handleRole: .bottomTrailing,
            draggedWorldCorner: CGPoint(x: 150, y: 150),
            minimumScale: 0.1
        )
        let firstGeometry = try XCTUnwrap(
            resized?.first(where: { $0.itemID == firstID })
        )
        let secondGeometry = try XCTUnwrap(
            resized?.first(where: { $0.itemID == secondID })
        )

        XCTAssertEqual(firstGeometry.center, CGPoint(x: 37.5, y: 37.5))
        XCTAssertEqual(secondGeometry.center, CGPoint(x: 112.5, y: 112.5))
        XCTAssertEqual(firstGeometry.size, CGSize(width: 30, height: 30))
        XCTAssertEqual(secondGeometry.size, CGSize(width: 60, height: 30))
    }

    func testRotatedMemberGeometriesRotateCentersAndItemAnglesAroundSelectionCenter() throws {
        let firstID = CanvasItemID()
        let secondID = CanvasItemID()
        let snapshot = CanvasSelectionTransformSnapshot(
            primaryItemID: secondID,
            memberGeometries: [
                CanvasBoardItemGeometry(
                    itemID: firstID,
                    center: CGPoint(x: 50, y: 0),
                    size: CGSize(width: 20, height: 20),
                    rotationRadians: 0
                ),
                CanvasBoardItemGeometry(
                    itemID: secondID,
                    center: CGPoint(x: 100, y: 50),
                    size: CGSize(width: 30, height: 10),
                    rotationRadians: .pi / 6
                )
            ],
            selectionBounds: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        let rotated = snapshot.rotatedMemberGeometries(by: .pi / 2)
        let firstGeometry = try XCTUnwrap(
            rotated.first(where: { $0.itemID == firstID })
        )
        let secondGeometry = try XCTUnwrap(
            rotated.first(where: { $0.itemID == secondID })
        )

        XCTAssertEqual(firstGeometry.center.x, 100, accuracy: 0.0001)
        XCTAssertEqual(firstGeometry.center.y, 50, accuracy: 0.0001)
        XCTAssertEqual(secondGeometry.center.x, 50, accuracy: 0.0001)
        XCTAssertEqual(secondGeometry.center.y, 100, accuracy: 0.0001)
        XCTAssertEqual(firstGeometry.rotationRadians, .pi / 2, accuracy: 0.0001)
        XCTAssertEqual(
            secondGeometry.rotationRadians,
            (.pi / 6) + (.pi / 2),
            accuracy: 0.0001
        )
    }
}
