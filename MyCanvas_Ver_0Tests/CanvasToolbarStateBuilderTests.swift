import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasToolbarStateBuilderTests: XCTestCase {
    func testMainToolbarStateIncludesMultiSelectItem() throws {
        let session = makeToolbarStateBuilderTestSession()
        let builder = CanvasToolbarStateBuilder()

        let state = builder.mainToolbarState(
            session: session,
            saveState: .idle,
            placement: CanvasToolbarPlacement(preferredEdge: .trailing),
            isMultiSelectModeActive: false,
            includesHistoryItems: true
        )

        XCTAssertEqual(
            state.items.map(\.id),
            [.undo, .redo, .crop, .multiSelect, .save, .text, .importMedia]
        )

        let multiSelectItem = try XCTUnwrap(
            state.items.first(where: { $0.id == .multiSelect })
        )
        XCTAssertEqual(multiSelectItem.systemImageName, "checklist")
        XCTAssertEqual(multiSelectItem.accessibilityLabel, "Multi-select")
        XCTAssertEqual(multiSelectItem.accessibilityValue, "Off")
        XCTAssertEqual(multiSelectItem.visualRole, .neutral)
        XCTAssertFalse(multiSelectItem.isActive)
    }

    func testMainToolbarStateReflectsActiveMultiSelectMode() throws {
        let session = makeToolbarStateBuilderTestSession()
        let builder = CanvasToolbarStateBuilder()

        let state = builder.mainToolbarState(
            session: session,
            saveState: .idle,
            placement: CanvasToolbarPlacement(preferredEdge: .trailing),
            isMultiSelectModeActive: true
        )

        let multiSelectItem = try XCTUnwrap(
            state.items.first(where: { $0.id == .multiSelect })
        )
        XCTAssertEqual(multiSelectItem.accessibilityValue, "On")
        XCTAssertEqual(multiSelectItem.visualRole, .accent)
        XCTAssertTrue(multiSelectItem.isActive)
    }
}

private func makeToolbarStateBuilderTestSession() -> CanvasEditorSession {
    CanvasEditorSession(
        saveQueueLabel: "CanvasToolbarStateBuilderTests",
        logPrefix: "[CanvasToolbarStateBuilderTests]"
    )
}
