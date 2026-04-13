import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasContextMenuActionResolverTests: XCTestCase {
    func testSelectedAnimatedGIFIncludesGIFFrameImportAction() throws {
        let session = makeContextMenuActionResolverTestSession()
        let gifItem = CanvasImageItem(
            asset: CanvasImageAsset.transientAnimatedGIF(
                posterCGImage: try makeContextMenuActionResolverTestImage(
                    red: 1,
                    green: 0,
                    blue: 0
                )
            ),
            center: CGPoint(x: 40, y: 60),
            size: CGSize(width: 120, height: 80),
            zIndex: 0
        )
        session.scene.append(gifItem)

        let actionStates = CanvasContextMenuActionResolver().actionStates(
            for: makeContextMenuContext(
                targetKind: .selectedItemBody,
                targetItemID: gifItem.id,
                selectedItemID: gifItem.id
            ),
            session: session
        )

        XCTAssertTrue(actionStates.contains(where: isGIFFrameImportAction))
        XCTAssertFalse(actionStates.contains(where: isVideoDisplayFrameAction))
    }

    func testUnselectedAnimatedGIFIncludesGIFFrameImportAction() throws {
        let session = makeContextMenuActionResolverTestSession()
        let gifItem = CanvasImageItem(
            asset: CanvasImageAsset.transientAnimatedGIF(
                posterCGImage: try makeContextMenuActionResolverTestImage(
                    red: 0,
                    green: 1,
                    blue: 0
                )
            ),
            center: CGPoint(x: 55, y: 75),
            size: CGSize(width: 100, height: 70),
            zIndex: 0
        )
        session.scene.append(gifItem)

        let actionStates = CanvasContextMenuActionResolver().actionStates(
            for: makeContextMenuContext(
                targetKind: .unselectedItemBody,
                targetItemID: gifItem.id,
                selectedItemID: nil
            ),
            session: session
        )

        XCTAssertTrue(actionStates.contains(where: isGIFFrameImportAction))
    }

    func testStaticImageDoesNotIncludeGIFFrameImportAction() throws {
        let session = makeContextMenuActionResolverTestSession()
        let staticItem = CanvasImageItem(
            asset: CanvasImageAsset.transientStaticImage(
                cgImage: try makeContextMenuActionResolverTestImage(
                    red: 0,
                    green: 0,
                    blue: 1
                )
            ),
            center: CGPoint(x: 30, y: 45),
            size: CGSize(width: 90, height: 60),
            zIndex: 0
        )
        session.scene.append(staticItem)

        let actionStates = CanvasContextMenuActionResolver().actionStates(
            for: makeContextMenuContext(
                targetKind: .selectedItemBody,
                targetItemID: staticItem.id,
                selectedItemID: staticItem.id
            ),
            session: session
        )

        XCTAssertFalse(actionStates.contains(where: isGIFFrameImportAction))
    }

    func testVideoItemKeepsVideoActionAndExcludesGIFAction() throws {
        let session = makeContextMenuActionResolverTestSession()
        let videoItem = CanvasImageItem(
            asset: CanvasImageAsset.transientStaticImage(
                cgImage: try makeContextMenuActionResolverTestImage(
                    red: 1,
                    green: 1,
                    blue: 0
                )
            ),
            videoSource: CanvasVideoSource(
                assetReference: .persisted(filename: "sample.mov")
            ),
            posterTimeSeconds: 0.5,
            center: CGPoint(x: 80, y: 110),
            size: CGSize(width: 160, height: 90),
            zIndex: 0
        )
        session.scene.append(videoItem)

        let actionStates = CanvasContextMenuActionResolver().actionStates(
            for: makeContextMenuContext(
                targetKind: .selectedItemBody,
                targetItemID: videoItem.id,
                selectedItemID: videoItem.id
            ),
            session: session
        )

        XCTAssertTrue(actionStates.contains(where: isVideoDisplayFrameAction))
        XCTAssertFalse(actionStates.contains(where: isGIFFrameImportAction))
    }

    func testReadingModeReturnsNoActionsEvenWhenContextHasCandidates() throws {
        let session = makeContextMenuActionResolverTestSession()
        let imageItem = CanvasImageItem(
            asset: CanvasImageAsset.transientStaticImage(
                cgImage: try makeContextMenuActionResolverTestImage(
                    red: 0.3,
                    green: 0.5,
                    blue: 0.7
                )
            ),
            center: CGPoint(x: 40, y: 50),
            size: CGSize(width: 120, height: 90),
            zIndex: 0
        )
        session.scene.append(imageItem)
        session.workspaceMode = .reading

        let actionStates = CanvasContextMenuActionResolver().actionStates(
            for: makeContextMenuContext(
                targetKind: .selectedItemBody,
                targetItemID: imageItem.id,
                selectedItemID: imageItem.id
            ),
            session: session
        )

        XCTAssertTrue(actionStates.isEmpty)
    }

    func testFrozenEnvironmentReturnsNoActionsEvenInEditingMode() throws {
        let session = makeContextMenuActionResolverTestSession()
        let imageItem = CanvasImageItem(
            asset: CanvasImageAsset.transientStaticImage(
                cgImage: try makeContextMenuActionResolverTestImage(
                    red: 0.9,
                    green: 0.4,
                    blue: 0.2
                )
            ),
            center: CGPoint(x: 52, y: 68),
            size: CGSize(width: 140, height: 96),
            zIndex: 0
        )
        session.scene.append(imageItem)

        let actionStates = CanvasContextMenuActionResolver().actionStates(
            for: makeContextMenuContext(
                targetKind: .selectedItemBody,
                targetItemID: imageItem.id,
                selectedItemID: imageItem.id
            ),
            session: session,
            environment: makeContextMenuEnvironment(
                workspaceMode: .editing,
                isFrozen: true
            )
        )

        XCTAssertTrue(actionStates.isEmpty)
    }
}

private enum CanvasContextMenuActionResolverTestRetainer {
    static var sessions: [CanvasEditorSession] = []
}

private func makeContextMenuActionResolverTestSession() -> CanvasEditorSession {
    let session = CanvasEditorSession(
        saveQueueLabel: "CanvasContextMenuActionResolverTests",
        logPrefix: "[CanvasContextMenuActionResolverTests]"
    )
    CanvasContextMenuActionResolverTestRetainer.sessions.append(session)
    return session
}

private func makeContextMenuContext(
    targetKind: CanvasContextMenuTargetKind,
    targetItemID: CanvasItemID,
    selectedItemID: CanvasItemID?
) -> CanvasContextMenuContext {
    CanvasContextMenuContext(
        invocationViewportPoint: CGPoint(x: 12, y: 18),
        invocationWorldPoint: CGPoint(x: 12, y: 18),
        targetKind: targetKind,
        editOverlayHitTargetKind: nil,
        targetItemID: targetItemID,
        anchorRect: nil,
        selectedItemID: selectedItemID,
        isInlineEditModeActive: false,
        isInlineCropModeActive: false
    )
}

private func makeContextMenuEnvironment(
    workspaceMode: CanvasWorkspaceMode,
    isFrozen: Bool
) -> CanvasInteractionEnvironment {
    CanvasInteractionEnvironment(
        workspaceMode: workspaceMode,
        isTransitionInteractionFrozen: isFrozen
    )
}

private func isGIFFrameImportAction(
    _ actionState: CanvasContextMenuActionState
) -> Bool {
    if case .uiAction(.importGIFFrames) = actionState.actionID {
        return true
    }

    return false
}

private func isVideoDisplayFrameAction(
    _ actionState: CanvasContextMenuActionState
) -> Bool {
    if case .uiAction(.editVideoDisplayFrame) = actionState.actionID {
        return true
    }

    return false
}

private func makeContextMenuActionResolverTestImage(
    red: CGFloat,
    green: CGFloat,
    blue: CGFloat,
    alpha: CGFloat = 1,
    size: CGSize = CGSize(width: 24, height: 16)
) throws -> CGImage {
    let width = max(Int(size.width), 1)
    let height = max(Int(size.height), 1)
    let bitmapInfo =
        CGImageAlphaInfo.premultipliedLast.rawValue
        | CGBitmapInfo.byteOrder32Big.rawValue
    guard
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        )
    else {
        throw CanvasContextMenuActionResolverTestError.invalidBitmapContext
    }

    context.setFillColor(
        CGColor(
            red: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    )
    context.fill(
        CGRect(
            x: 0,
            y: 0,
            width: width,
            height: height
        )
    )

    guard let image = context.makeImage() else {
        throw CanvasContextMenuActionResolverTestError.invalidBitmapContext
    }
    return image
}

private enum CanvasContextMenuActionResolverTestError: Error {
    case invalidBitmapContext
}
