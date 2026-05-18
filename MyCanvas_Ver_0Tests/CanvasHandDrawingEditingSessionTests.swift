import CoreGraphics
import Foundation
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasHandDrawingEditingSessionTests: XCTestCase {
    func testCommitHandDrawingEditUpdatesItemAndSupportsUndoRedo() throws {
        let session = makeHandDrawingEditingTestSession()
        let item = try XCTUnwrap(session.addHandDrawingItem(paper: .square))
        let originalRevision = item.contentRevision
        session.resetHistory()

        let previewImage = try makeHandDrawingEditingTestImage(
            red: 0.2,
            green: 0.3,
            blue: 0.9
        )
        let updatedRevision = UUID()
        let documentData = try HandDrawingDocumentCodec.makeDocumentData(
            for: makeHandDrawingTestDocument()
        )
        let result = try XCTUnwrap(
            session.commitHandDrawingEdit(
                withID: item.id,
                submission: CanvasHandDrawingEditSubmission(
                    documentData: documentData,
                    previewCGImage: previewImage,
                    isEmpty: false,
                    contentRevision: updatedRevision
                )
            )
        )

        XCTAssertEqual(result.refreshReason, "commit hand drawing edit")
        let updatedItem = try XCTUnwrap(session.scene.handDrawingItem(withID: item.id))
        XCTAssertFalse(updatedItem.isEmpty)
        XCTAssertEqual(updatedItem.contentRevision, updatedRevision)
        let transientPayload = try XCTUnwrap(
            session.transientHandDrawingAssetPayload(for: item.id)
        )
        XCTAssertEqual(transientPayload.documentData, documentData)

        let undoSnapshot = try XCTUnwrap(session.undoHistorySnapshot())
        session.applyBoardHistorySnapshot(undoSnapshot)
        let undoneItem = try XCTUnwrap(session.scene.handDrawingItem(withID: item.id))
        XCTAssertTrue(undoneItem.isEmpty)
        XCTAssertEqual(undoneItem.contentRevision, originalRevision)

        let redoSnapshot = try XCTUnwrap(session.redoHistorySnapshot())
        session.applyBoardHistorySnapshot(redoSnapshot)
        let redoneItem = try XCTUnwrap(session.scene.handDrawingItem(withID: item.id))
        XCTAssertFalse(redoneItem.isEmpty)
        XCTAssertEqual(redoneItem.contentRevision, updatedRevision)
    }

    func testHandDrawingEditorContextReopensFromTransientDocumentData() throws {
        let session = makeHandDrawingEditingTestSession()
        let item = try XCTUnwrap(session.addHandDrawingItem(paper: .square))
        let previewImage = try makeHandDrawingEditingTestImage(
            red: 0.75,
            green: 0.2,
            blue: 0.45
        )
        let documentData = try HandDrawingDocumentCodec.makeDocumentData(
            for: makeHandDrawingTestDocument(includeEraseMask: true)
        )

        _ = try session.commitHandDrawingEdit(
            withID: item.id,
            submission: CanvasHandDrawingEditSubmission(
                documentData: documentData,
                previewCGImage: previewImage,
                isEmpty: false,
                contentRevision: UUID()
            )
        )

        let editorContext = try session.handDrawingEditorContext(for: item.id)
        XCTAssertEqual(editorContext.documentData, documentData)
        XCTAssertEqual(editorContext.storage, .bundle)
        XCTAssertFalse(editorContext.didMigrateLegacyDocument)
    }

    func testAddHandDrawingItemProvidesImmediateEmptyEditorContext() throws {
        let session = makeHandDrawingEditingTestSession()
        let item = try XCTUnwrap(session.addHandDrawingItem(paper: .square))

        let editorContext = try session.handDrawingEditorContext(for: item.id)
        XCTAssertEqual(editorContext.itemID, item.id)
        XCTAssertTrue(editorContext.documentData.isEmpty)
        XCTAssertTrue(editorContext.isEmpty)
        XCTAssertEqual(editorContext.storage, .bundle)
        XCTAssertFalse(editorContext.didMigrateLegacyDocument)
    }

    func testHandDrawingEditPersistsAcrossBoardReload() throws {
        try withTemporaryHandDrawingEditingWorkspace { _, userDefaults in
            let session = makeHandDrawingEditingTestSession(userDefaults: userDefaults)
            session.startNewBoard(now: Date(timeIntervalSince1970: 1_720_300_000))

            let item = try XCTUnwrap(session.addHandDrawingItem(paper: .square))
            let boardID = try XCTUnwrap(session.activeBoardID)
            let previewImage = try makeHandDrawingEditingTestImage(
                red: 0.1,
                green: 0.6,
                blue: 0.85
            )
            let documentData = try HandDrawingDocumentCodec.makeDocumentData(
                for: makeHandDrawingTestDocument(includeEraseMask: true)
            )

            _ = try session.commitHandDrawingEdit(
                withID: item.id,
                submission: CanvasHandDrawingEditSubmission(
                    documentData: documentData,
                    previewCGImage: previewImage,
                    isEmpty: false,
                    contentRevision: UUID()
                )
            )

            let saveSnapshot = try XCTUnwrap(session.currentBoardSaveSnapshot())
            try BoardStore.saveBoard(saveSnapshot, userDefaults: userDefaults)

            let restartedSession = makeHandDrawingEditingTestSession(
                userDefaults: userDefaults
            )
            try restartedSession.loadBoard(id: boardID)

            let editorContext = try restartedSession.handDrawingEditorContext(
                for: item.id
            )
            XCTAssertEqual(editorContext.documentData, documentData)
            XCTAssertFalse(editorContext.isEmpty)
            XCTAssertEqual(editorContext.storage, .bundle)
            XCTAssertFalse(editorContext.didMigrateLegacyDocument)
        }
    }
}

private enum CanvasHandDrawingEditingSessionTestRetainer {
    static var sessions: [CanvasEditorSession] = []
}

private func makeHandDrawingEditingTestSession(
    userDefaults: UserDefaults = .standard
) -> CanvasEditorSession {
    let session = CanvasEditorSession(
        saveQueueLabel: "CanvasHandDrawingEditingSessionTests",
        logPrefix: "[CanvasHandDrawingEditingSessionTests]",
        userDefaults: userDefaults
    )
    CanvasHandDrawingEditingSessionTestRetainer.sessions.append(session)
    return session
}

private func makeHandDrawingEditingTestImage(
    red: CGFloat,
    green: CGFloat,
    blue: CGFloat
) throws -> CGImage {
    let bitmapInfo =
        CGImageAlphaInfo.premultipliedLast.rawValue
        | CGBitmapInfo.byteOrder32Big.rawValue
    guard
        let context = CGContext(
            data: nil,
            width: 12,
            height: 12,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        )
    else {
        throw CanvasHandDrawingEditingSessionTestError.invalidBitmapContext
    }

    context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
    guard let image = context.makeImage() else {
        throw CanvasHandDrawingEditingSessionTestError.invalidBitmapContext
    }
    return image
}

private enum CanvasHandDrawingEditingSessionTestError: Error {
    case invalidBitmapContext
}

private func withTemporaryHandDrawingEditingWorkspace(
    _ body: (URL, UserDefaults) throws -> Void
) throws {
    let fileManager = FileManager.default
    let identifier = UUID().uuidString
    let selectedFolderURL = fileManager.temporaryDirectory.appendingPathComponent(
        "CanvasHandDrawingEditingSessionTests-\(identifier)",
        isDirectory: true
    )
    try fileManager.createDirectory(
        at: selectedFolderURL,
        withIntermediateDirectories: true
    )

    let suiteName = "CanvasHandDrawingEditingSessionTests.\(identifier)"
    guard let userDefaults = UserDefaults(suiteName: suiteName) else {
        XCTFail("Failed to create isolated UserDefaults suite.")
        return
    }
    userDefaults.removePersistentDomain(forName: suiteName)

    let bookmarkData = try selectedFolderURL.bookmarkData(
        options: handDrawingEditingBookmarkCreationOptions(),
        includingResourceValuesForKeys: nil,
        relativeTo: nil
    )
    FolderBookmarkStore.save(bookmarkData, userDefaults: userDefaults)

    defer {
        userDefaults.removePersistentDomain(forName: suiteName)
        try? fileManager.removeItem(at: selectedFolderURL)
    }

    try body(selectedFolderURL, userDefaults)
}

private func handDrawingEditingBookmarkCreationOptions() -> URL.BookmarkCreationOptions {
    #if os(macOS)
    return [.withSecurityScope]
    #else
    return []
    #endif
}
