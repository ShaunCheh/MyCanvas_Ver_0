import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasInputRoutingResolverTests: XCTestCase {
    private let resolver = CanvasInputRoutingResolver()

    func testPasteKeyboardShortcutRoutesToIndicatorAndTransferEntryIntent() {
        let rawInput = CanvasRawInputIntent.keyChord(
            CanvasKeyChord(
                modifiers: [.command],
                key: .character("v")
            )
        )

        let result = resolver.route(rawInput)

        XCTAssertEqual(
            result.indicatorEvent,
            .keyChord(
                CanvasKeyChord(
                    modifiers: [.command],
                    key: .character("v")
                )
            )
        )
        XCTAssertEqual(
            result.interactionIntent,
            .transferEntry(.pasteKeyboardShortcut)
        )
        XCTAssertFalse(result.isEmpty)
    }

    func testCopyKeyboardShortcutRoutesOnlyToIndicatorEvent() {
        let rawInput = CanvasRawInputIntent.keyChord(
            CanvasKeyChord(
                modifiers: [.command],
                key: .character("c")
            )
        )

        let result = resolver.route(rawInput)

        XCTAssertEqual(
            result.indicatorEvent,
            .keyChord(
                CanvasKeyChord(
                    modifiers: [.command],
                    key: .character("c")
                )
            )
        )
        XCTAssertNil(result.interactionIntent)
    }

    func testPrimaryClickRoutesOnlyToLeftClickIndicator() {
        let result = resolver.route(.pointerClick(.primary))

        XCTAssertEqual(result.indicatorEvent, .action(.leftClick))
        XCTAssertNil(result.interactionIntent)
    }

    func testTouchTapRoutesOnlyToTapIndicator() {
        let result = resolver.route(
            .gesture(.tap, source: .touch)
        )

        XCTAssertEqual(result.indicatorEvent, .action(.tap))
        XCTAssertNil(result.interactionIntent)
    }

    func testPointerScrollRoutesOnlyToScrollIndicator() {
        let result = resolver.route(
            .gesture(.scroll, source: .pointer)
        )

        XCTAssertEqual(result.indicatorEvent, .action(.scroll))
        XCTAssertNil(result.interactionIntent)
    }
}
