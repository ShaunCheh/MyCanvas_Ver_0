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
            [.undo, .redo, .crop, .multiSelect, .save, .text, .markdown, .importMedia]
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

    func testMainToolbarStateIncludesMarkdownItem() throws {
        let session = makeToolbarStateBuilderTestSession()
        let builder = CanvasToolbarStateBuilder()

        let state = builder.mainToolbarState(
            session: session,
            saveState: .idle,
            placement: CanvasToolbarPlacement(preferredEdge: .trailing)
        )

        let markdownItem = try XCTUnwrap(
            state.items.first(where: { $0.id == .markdown })
        )
        XCTAssertEqual(markdownItem.systemImageName, "text.alignleft")
        XCTAssertEqual(markdownItem.accessibilityLabel, "Add markdown")
        XCTAssertTrue(markdownItem.isEnabled)
        XCTAssertEqual(markdownItem.visualRole, .accent)
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

    func testMainToolbarStateIncludesHandDrawingItemWhenSupported() {
        let session = makeToolbarStateBuilderTestSession()
        let builder = CanvasToolbarStateBuilder()

        let state = builder.mainToolbarState(
            session: session,
            saveState: .idle,
            placement: CanvasToolbarPlacement(preferredEdge: .trailing),
            supportsHandDrawingEditing: true,
            includesHistoryItems: true
        )

        XCTAssertEqual(
            state.items.map(\.id),
            [.undo, .redo, .crop, .multiSelect, .save, .text, .markdown, .handDrawing, .importMedia]
        )
    }

    func testSelectedHandDrawingShowsEditToolbarItemAndHidesCrop() throws {
        let session = makeToolbarStateBuilderTestSession()
        let builder = CanvasToolbarStateBuilder()
        let handDrawingItem = try makeToolbarStateBuilderTestHandDrawingItem()
        session.scene.append(handDrawingItem)
        session.interactionState = CanvasInteractionState(
            selectedItemID: handDrawingItem.id
        )

        let state = builder.mainToolbarState(
            session: session,
            saveState: .idle,
            placement: CanvasToolbarPlacement(preferredEdge: .trailing),
            supportsHandDrawingEditing: true
        )

        let handDrawingToolbarItem = try XCTUnwrap(
            state.items.first(where: { $0.id == .handDrawing })
        )
        XCTAssertEqual(handDrawingToolbarItem.accessibilityLabel, "Edit hand drawing")
        XCTAssertEqual(handDrawingToolbarItem.systemImageName, "pencil.and.scribble")
        XCTAssertFalse(state.items.contains(where: { $0.id == .crop }))
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

private func makeToolbarStateBuilderTestHandDrawingItem() throws -> CanvasHandDrawingItem {
    let itemID = CanvasItemID()
    let previewImage = try CanvasHandDrawingPreviewAssetFactory.makeTransparentPreview(
        for: .square
    )
    return CanvasHandDrawingItem(
        id: itemID,
        paper: .square,
        previewAsset: CanvasHandDrawingItem.persistedPreviewAsset(
            for: itemID,
            cgImage: previewImage,
            logicalPixelSize: CanvasHandDrawingPaperSpec.square.size
        ),
        isEmpty: true,
        center: CGPoint(x: 80, y: 60),
        size: CGSize(width: 240, height: 240),
        zIndex: 0
    )
}

private enum ToolbarStateBuilderTestError: Error {
    case invalidBitmapContext
}
