import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasInputIndicatorEventTests: XCTestCase {
    func testKeyChordDebugNameUsesCanonicalModifierOrderAndUppercaseCharacter() {
        let event = CanvasInputIndicatorEvent.keyChord(
            CanvasKeyChord(
                modifiers: [.shift, .command],
                key: .character("z")
            )
        )

        XCTAssertEqual(event.debugName, "keyChord.command+shift+Z")
    }

    func testKeyChordNormalizesCharacterCaseForEquality() {
        let lowercased = CanvasKeyChord(
            modifiers: [.command],
            key: .character("v")
        )
        let uppercased = CanvasKeyChord(
            modifiers: [.command],
            key: .character("V")
        )

        XCTAssertEqual(lowercased, uppercased)
    }

    func testActionDebugNamePreservesSemanticActionName() {
        let event = CanvasInputIndicatorEvent.action(.leftClick)

        XCTAssertEqual(event.debugName, "action.leftClick")
    }
}
