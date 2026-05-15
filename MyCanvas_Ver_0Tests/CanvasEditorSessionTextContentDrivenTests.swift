import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

final class CanvasEditorSessionTextContentDrivenTests: XCTestCase {
    func testAddTextItemUsesMeasuredIntrinsicSize() throws {
        let session = makeTextContentDrivenTestSession()
        let style = CanvasTextStyle(fontSize: 28)

        let item = try XCTUnwrap(
            session.addTextItem(
                text: "Hi",
                style: style
            )
        )

        let expectedSize = CanvasTextLayoutMeasurer.intrinsicItemSize(
            for: "Hi",
            style: style
        )

        XCTAssertEqual(item.size, expectedSize)
        XCTAssertEqual(session.scene.textItem(withID: item.id)?.size, expectedSize)
    }

    func testUpdateTextItemContentUpdatesTextStyleAndSizeTogether() throws {
        let session = makeTextContentDrivenTestSession()
        let item = CanvasTextItem(
            text: "Draft",
            style: CanvasTextStyle(fontSize: 22),
            center: CGPoint(x: 120, y: 48),
            size: CGSize(width: 240, height: 96)
        )
        session.scene.append(item)

        let nextStyle = CanvasTextStyle(
            fontName: "System",
            fontSize: 44,
            color: item.style.color
        )
        let updated = try XCTUnwrap(
            session.updateTextItemContent(
                withID: item.id,
                text: "Draft updated",
                style: nextStyle
            )
        )

        XCTAssertEqual(updated.text, "Draft updated")
        XCTAssertEqual(updated.style, nextStyle)
        XCTAssertEqual(
            updated.size,
            CanvasTextLayoutMeasurer.intrinsicItemSize(
                for: "Draft updated",
                style: nextStyle
            )
        )
        XCTAssertEqual(updated.center, item.center)
    }

    func testCommitTextEditUpdatesMeasuredSizeAndPreservesCenter() throws {
        let session = makeTextContentDrivenTestSession()
        let style = CanvasTextStyle(fontSize: 26)
        let item = CanvasTextItem(
            text: "Short",
            style: style,
            center: CGPoint(x: 80, y: 140),
            size: CGSize(width: 240, height: 96)
        )
        session.scene.append(item)

        XCTAssertTrue(session.beginTextEdit(withID: item.id))
        XCTAssertTrue(session.updateTextEditDraft("A much longer edited text"))

        let result = try XCTUnwrap(session.commitTextEdit())
        let updatedItem = try XCTUnwrap(session.scene.textItem(withID: item.id))
        let expectedSize = CanvasTextLayoutMeasurer.intrinsicItemSize(
            for: "A much longer edited text",
            style: style
        )

        XCTAssertTrue(result.didChangeDocument)
        XCTAssertFalse(result.didDeleteItem)
        XCTAssertEqual(updatedItem.text, "A much longer edited text")
        XCTAssertEqual(updatedItem.size, expectedSize)
        XCTAssertEqual(updatedItem.center, item.center)
    }
}

private enum CanvasEditorSessionTextContentDrivenTestRetainer {
    static var sessions: [CanvasEditorSession] = []
}

private func makeTextContentDrivenTestSession() -> CanvasEditorSession {
    let session = CanvasEditorSession(
        saveQueueLabel: "CanvasEditorSessionTextContentDrivenTests",
        logPrefix: "[CanvasEditorSessionTextContentDrivenTests]"
    )
    CanvasEditorSessionTextContentDrivenTestRetainer.sessions.append(session)
    return session
}
