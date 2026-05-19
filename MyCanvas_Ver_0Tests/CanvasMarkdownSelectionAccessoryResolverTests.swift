import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasMarkdownSelectionAccessoryResolverTests: XCTestCase {
    private let resolver = CanvasMarkdownSelectionAccessoryResolver()

    func testResolveStateReturnsMarkdownAccessoryForSingleMarkdownSelection() throws {
        let item = CanvasMarkdownItem(
            markdownSource: "## Title\n\nBody",
            style: CanvasTextStyle(fontSize: 20),
            center: CGPoint(x: 80, y: 48),
            size: CGSize(width: 180, height: 96)
        )
        let session = makeMarkdownSelectionAccessoryResolverTestSession(
            items: [.markdown(item)],
            selectedItemID: item.id
        )

        let state = try XCTUnwrap(
            resolver.resolveState(
                session: session,
                environment: makeMarkdownSelectionAccessoryResolverEnvironment(),
                anchorRect: CGRect(x: 24, y: 40, width: 180, height: 96)
            )
        )

        XCTAssertEqual(state.itemID, item.id)
        XCTAssertEqual(
            state.actionStates.map(\.commandID),
            [
                .beginMarkdownEdit,
                .decreaseMarkdownContentSize,
                .increaseMarkdownContentSize
            ]
        )
        XCTAssertTrue(state.actionStates.allSatisfy(\.descriptor.isEnabled))
    }

    func testResolveStateReturnsNilForSingleTextSelection() {
        let item = CanvasTextItem(
            text: "Plain text",
            center: CGPoint(x: 64, y: 40),
            size: CGSize(width: 160, height: 48)
        )
        let session = makeMarkdownSelectionAccessoryResolverTestSession(
            items: [.text(item)],
            selectedItemID: item.id
        )

        let state = resolver.resolveState(
            session: session,
            environment: makeMarkdownSelectionAccessoryResolverEnvironment(),
            anchorRect: CGRect(x: 24, y: 40, width: 160, height: 48)
        )

        XCTAssertNil(state)
    }

    func testResolveStateReturnsNilForSingleHandDrawingSelection() throws {
        let handDrawingItem = CanvasHandDrawingItem(
            previewAsset: .transientStaticImage(
                cgImage: try makeMarkdownSelectionAccessoryResolverTestImage()
            ),
            isEmpty: false,
            center: CGPoint(x: 72, y: 72),
            size: CGSize(width: 120, height: 120)
        )
        let session = makeMarkdownSelectionAccessoryResolverTestSession(
            items: [.handDrawing(handDrawingItem)],
            selectedItemID: handDrawingItem.id
        )

        let state = resolver.resolveState(
            session: session,
            environment: makeMarkdownSelectionAccessoryResolverEnvironment(),
            anchorRect: CGRect(x: 12, y: 24, width: 120, height: 120)
        )

        XCTAssertNil(state)
    }

    func testResolveStateReturnsNilWhenInlineEditPresentationIsActive() {
        let item = CanvasMarkdownItem(
            markdownSource: "## Title\n\nBody",
            style: CanvasTextStyle(fontSize: 18),
            center: CGPoint(x: 80, y: 48),
            size: CGSize(width: 180, height: 96)
        )
        let session = makeMarkdownSelectionAccessoryResolverTestSession(
            items: [.markdown(item)],
            selectedItemID: item.id
        )

        let state = resolver.resolveState(
            session: session,
            environment: makeMarkdownSelectionAccessoryResolverEnvironment(
                hasInlineEditPresentation: true
            ),
            anchorRect: CGRect(x: 24, y: 40, width: 180, height: 96)
        )

        XCTAssertNil(state)
    }
}

private func makeMarkdownSelectionAccessoryResolverTestSession(
    items: [CanvasBoardItem],
    selectedItemID: CanvasItemID?
) -> CanvasEditorSession {
    let session = CanvasEditorSession(
        saveQueueLabel: "MyCanvas.Tests.MarkdownSelectionAccessoryResolver",
        logPrefix: "[Tests][MarkdownSelectionAccessoryResolver]"
    )
    for item in items {
        session.scene.append(item)
    }
    if let selectedItemID {
        session.interactionState = CanvasInteractionState(
            selectedItemIDs: [selectedItemID],
            primarySelectedItemID: selectedItemID
        )
    }
    MarkdownSelectionAccessoryResolverTestRetainer.sessions.append(session)
    return session
}

private func makeMarkdownSelectionAccessoryResolverEnvironment(
    workspaceMode: CanvasWorkspaceMode = .editing,
    isTransitionInteractionFrozen: Bool = false,
    hasContextMenu: Bool = false,
    hasPresentedOverlayEditor: Bool = false,
    hasInlineEditPresentation: Bool = false
) -> CanvasMarkdownSelectionAccessoryResolver.Environment {
    CanvasMarkdownSelectionAccessoryResolver.Environment(
        workspaceMode: workspaceMode,
        isTransitionInteractionFrozen: isTransitionInteractionFrozen,
        hasContextMenu: hasContextMenu,
        hasPresentedOverlayEditor: hasPresentedOverlayEditor,
        hasInlineEditPresentation: hasInlineEditPresentation
    )
}

private func makeMarkdownSelectionAccessoryResolverTestImage() throws -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: 4,
        height: 4,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw MarkdownSelectionAccessoryResolverTestError.failedToCreateBitmapContext
    }

    context.setFillColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    guard let image = context.makeImage() else {
        throw MarkdownSelectionAccessoryResolverTestError.failedToCreateImage
    }
    return image
}

private enum MarkdownSelectionAccessoryResolverTestError: Error {
    case failedToCreateBitmapContext
    case failedToCreateImage
}

private enum MarkdownSelectionAccessoryResolverTestRetainer {
    static var sessions: [CanvasEditorSession] = []
}
