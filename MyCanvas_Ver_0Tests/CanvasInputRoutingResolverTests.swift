import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasInputRoutingResolverTests: XCTestCase {
    private let resolver = CanvasInputRoutingResolver()

    func testPasteKeyboardShortcutRoutesToIndicatorAndTransferEntryIntent() {
        let rawInput = CanvasRawInputIntent.pasteKeyboardShortcut

        let result = resolver.route(rawInput)

        XCTAssertEqual(
            result.indicatorEvent,
            .keyChord(CanvasKeyChord(modifiers: [.command], key: .character("v")))
        )
        XCTAssertEqual(
            result.interactionIntent,
            .transferEntry(.pasteKeyboardShortcut)
        )
        XCTAssertFalse(result.isEmpty)
    }

    func testCopyKeyboardShortcutRoutesOnlyToIndicatorEvent() {
        let rawInput = CanvasRawInputIntent.copyKeyboardShortcut

        let result = resolver.route(rawInput)

        XCTAssertEqual(
            result.indicatorEvent,
            .keyChord(CanvasKeyChord(modifiers: [.command], key: .character("c")))
        )
        XCTAssertNil(result.interactionIntent)
    }

    func testUndoKeyboardShortcutRoutesToIndicatorAndUndoCommandIntent() {
        let rawInput = CanvasRawInputIntent.undoKeyboardShortcut

        let result = resolver.route(rawInput)

        XCTAssertEqual(
            result.indicatorEvent,
            .keyChord(CanvasKeyChord(modifiers: [.command], key: .character("z")))
        )
        XCTAssertEqual(result.interactionIntent, .command(.undo))
    }

    func testRedoKeyboardShortcutRoutesToIndicatorAndRedoCommandIntent() {
        let rawInput = CanvasRawInputIntent.redoKeyboardShortcut

        let result = resolver.route(rawInput)

        XCTAssertEqual(
            result.indicatorEvent,
            .keyChord(
                CanvasKeyChord(modifiers: [.command, .shift], key: .character("z"))
            )
        )
        XCTAssertEqual(result.interactionIntent, .command(.redo))
    }

    func testPrimaryClickRoutesOnlyToLeftClickIndicator() {
        let result = resolver.route(.primaryPointerClick)

        XCTAssertEqual(result.indicatorEvent, .action(.leftClick))
        XCTAssertNil(result.interactionIntent)
    }

    func testSecondaryClickRoutesToRightClickIndicatorAndContextMenuRequest() {
        let result = resolver.route(.secondaryPointerClick)

        XCTAssertEqual(result.indicatorEvent, .action(.rightClick))
        XCTAssertEqual(result.interactionIntent, .contextMenuRequest)
    }

    func testTouchTapRoutesOnlyToTapIndicator() {
        let result = resolver.route(.touchTapGesture)

        XCTAssertEqual(result.indicatorEvent, .action(.tap))
        XCTAssertNil(result.interactionIntent)
    }

    func testTouchLongPressRoutesToLongPressIndicatorAndContextMenuRequest() {
        let result = resolver.route(.touchLongPressGesture)

        XCTAssertEqual(result.indicatorEvent, .action(.longPress))
        XCTAssertEqual(result.interactionIntent, .contextMenuRequest)
    }

    func testPointerScrollRoutesOnlyToScrollIndicator() {
        let result = resolver.route(.pointerScrollGesture)

        XCTAssertEqual(result.indicatorEvent, .action(.scroll))
        XCTAssertNil(result.interactionIntent)
    }

    func testTouchPinchRoutesOnlyToPinchIndicator() {
        let result = resolver.route(.touchPinchGesture)

        XCTAssertEqual(result.indicatorEvent, .action(.pinch))
        XCTAssertNil(result.interactionIntent)
    }
}
