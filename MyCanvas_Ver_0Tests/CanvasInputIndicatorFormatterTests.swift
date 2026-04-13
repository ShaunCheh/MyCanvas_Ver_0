import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasInputIndicatorFormatterTests: XCTestCase {
    private let formatter = CanvasInputIndicatorFormatter()

    func testKeyChordUsesCanonicalModifierOrderAndNamedKeyDisplayText() {
        let text = formatter.text(
            for: .keyChord(
                CanvasKeyChord(
                    modifiers: [.control, .command, .shift],
                    key: .named(.returnKey)
                )
            )
        )

        XCTAssertEqual(text, "Command + Shift + Control + Return")
    }

    func testKeyChordUppercasesCharacterDisplayText() {
        let text = formatter.text(for: .keyChord(.copyKeyboardShortcut))

        XCTAssertEqual(text, "Command + C")
    }

    func testActionUsesReadableSemanticDisplayName() {
        let text = formatter.text(for: .action(.rightClick))

        XCTAssertEqual(text, "Right Click")
    }
}
