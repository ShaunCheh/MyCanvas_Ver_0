import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasInteractionPolicyTests: XCTestCase {
    private let policy = CanvasInteractionPolicy()

    func testPasteKeyboardShortcutAllowsInEditingModeWhenNotFrozen() {
        let decision = policy.decision(
            for: .transferEntry(.pasteKeyboardShortcut),
            environment: makeEnvironment(workspaceMode: .editing, isFrozen: false)
        )

        XCTAssertEqual(decision, .allow)
    }

    func testPasteKeyboardShortcutBlocksInReadingModeWhenNotFrozen() {
        let decision = policy.decision(
            for: .transferEntry(.pasteKeyboardShortcut),
            environment: makeEnvironment(workspaceMode: .reading, isFrozen: false)
        )

        XCTAssertEqual(
            decision,
            .block(reason: .readingMode, feedback: .shakeWorkspaceModeButton)
        )
    }

    func testPasteKeyboardShortcutBlocksInEditingModeWhenFrozen() {
        let decision = policy.decision(
            for: .transferEntry(.pasteKeyboardShortcut),
            environment: makeEnvironment(workspaceMode: .editing, isFrozen: true)
        )

        XCTAssertEqual(
            decision,
            .block(reason: .transitionInteractionFrozen, feedback: nil)
        )
    }

    func testPasteKeyboardShortcutPrioritizesFrozenBlockInReadingMode() {
        let decision = policy.decision(
            for: .transferEntry(.pasteKeyboardShortcut),
            environment: makeEnvironment(workspaceMode: .reading, isFrozen: true)
        )

        XCTAssertEqual(
            decision,
            .block(reason: .transitionInteractionFrozen, feedback: nil)
        )
    }

    func testImportButtonBlocksInReadingModeWithoutFeedback() {
        let decision = policy.decision(
            for: .transferEntry(.importButton),
            environment: makeEnvironment(workspaceMode: .reading, isFrozen: false)
        )

        XCTAssertEqual(decision, .block(reason: .readingMode, feedback: nil))
    }

    func testDragAndDropBlocksInReadingModeWithoutFeedback() {
        let decision = policy.decision(
            for: .transferEntry(.dragAndDrop),
            environment: makeEnvironment(workspaceMode: .reading, isFrozen: false)
        )

        XCTAssertEqual(decision, .block(reason: .readingMode, feedback: nil))
    }

    func testCommandAllowsInEditingModeWhenNotFrozen() {
        let decision = policy.decision(
            for: .command(.undo),
            environment: makeEnvironment(workspaceMode: .editing, isFrozen: false)
        )

        XCTAssertEqual(decision, .allow)
    }

    func testCommandBlocksInReadingModeWhenMetadataDisallowsIt() {
        let decision = policy.decision(
            for: .command(.undo),
            environment: makeEnvironment(workspaceMode: .reading, isFrozen: false)
        )

        XCTAssertEqual(decision, .block(reason: .readingMode, feedback: nil))
    }

    private func makeEnvironment(
        workspaceMode: CanvasWorkspaceMode,
        isFrozen: Bool
    ) -> CanvasInteractionEnvironment {
        CanvasInteractionEnvironment(
            workspaceMode: workspaceMode,
            isTransitionInteractionFrozen: isFrozen
        )
    }
}
