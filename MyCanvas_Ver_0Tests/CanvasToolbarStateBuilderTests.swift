import CoreGraphics
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

    func testMainToolbarStateDisablesMultiSelectDuringInlineTextEdit() throws {
        let session = makeToolbarStateBuilderTestSession()
        let builder = CanvasToolbarStateBuilder()

        XCTAssertNotNil(session.addTextItem())

        let state = builder.mainToolbarState(
            session: session,
            saveState: .idle,
            placement: CanvasToolbarPlacement(preferredEdge: .trailing),
            isMultiSelectModeActive: true
        )

        let multiSelectItem = try XCTUnwrap(
            state.items.first(where: { $0.id == .multiSelect })
        )
        XCTAssertFalse(multiSelectItem.isEnabled)
        XCTAssertTrue(multiSelectItem.isActive)
    }

    func testMainToolbarStateDisablesMultiSelectDuringCropMode() throws {
        let session = makeToolbarStateBuilderTestSession()
        let builder = CanvasToolbarStateBuilder()
        let imageItem = CanvasImageItem(
            asset: CanvasImageAsset.transientStaticImage(
                cgImage: try makeToolbarStateBuilderTestImage()
            ),
            center: CGPoint(x: 60, y: 40),
            size: CGSize(width: 120, height: 80),
            zIndex: 0
        )
        session.scene.append(imageItem)
        session.interactionState = CanvasInteractionState(selectedItemID: imageItem.id)
        XCTAssertTrue(session.beginCropModeIfPossible())

        let state = builder.mainToolbarState(
            session: session,
            saveState: .idle,
            placement: CanvasToolbarPlacement(preferredEdge: .trailing),
            isMultiSelectModeActive: true
        )

        let multiSelectItem = try XCTUnwrap(
            state.items.first(where: { $0.id == .multiSelect })
        )
        XCTAssertFalse(multiSelectItem.isEnabled)
        XCTAssertTrue(multiSelectItem.isActive)
    }

    func testMainToolbarStateHidesItemsInReadingMode() {
        let session = makeToolbarStateBuilderTestSession()
        let builder = CanvasToolbarStateBuilder()
        session.workspaceMode = .reading

        let state = builder.mainToolbarState(
            session: session,
            saveState: .idle,
            placement: CanvasToolbarPlacement(preferredEdge: .trailing),
            isMultiSelectModeActive: true,
            includesHistoryItems: true
        )

        XCTAssertTrue(state.items.isEmpty)
    }
}

private enum CanvasToolbarStateBuilderTestRetainer {
    static var sessions: [CanvasEditorSession] = []
}

private func makeToolbarStateBuilderTestSession() -> CanvasEditorSession {
    let session = CanvasEditorSession(
        saveQueueLabel: "CanvasToolbarStateBuilderTests",
        logPrefix: "[CanvasToolbarStateBuilderTests]"
    )
    CanvasToolbarStateBuilderTestRetainer.sessions.append(session)
    return session
}

private func makeToolbarStateBuilderTestImage() throws -> CGImage {
    let bitmapInfo =
        CGImageAlphaInfo.premultipliedLast.rawValue
        | CGBitmapInfo.byteOrder32Big.rawValue
    guard
        let context = CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        )
    else {
        throw ToolbarStateBuilderTestError.invalidBitmapContext
    }

    context.setFillColor(
        CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
    )
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))

    guard let image = context.makeImage() else {
        throw ToolbarStateBuilderTestError.invalidBitmapContext
    }
    return image
}

private enum ToolbarStateBuilderTestError: Error {
    case invalidBitmapContext
}
