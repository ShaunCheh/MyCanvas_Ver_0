import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasCommandPolicyParityTests: XCTestCase {
    private let policy = CanvasInteractionPolicy()
    private let commandCatalog = CanvasCommandCatalog()

    func testAddTextDescriptorAndExecutorMatchPolicyInEditingMode() {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)

        let descriptor = commandCatalog.descriptor(for: .addTextItem, session: session)
        let decision = policy.commandDecision(
            for: .addTextItem,
            workspaceMode: session.workspaceMode
        )

        XCTAssertEqual(decision, .allow)
        XCTAssertTrue(descriptor.isEnabled)
        XCTAssertFalse(descriptor.isActive)
        XCTAssertTrue(executor.canExecute(.addTextItem))
    }

    func testAddTextDescriptorAndExecutorMatchPolicyInReadingMode() {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .reading)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)

        let descriptor = commandCatalog.descriptor(for: .addTextItem, session: session)
        let decision = policy.commandDecision(
            for: .addTextItem,
            workspaceMode: session.workspaceMode
        )

        XCTAssertEqual(decision, .block(reason: .readingMode, feedback: nil))
        XCTAssertFalse(descriptor.isEnabled)
        XCTAssertFalse(descriptor.isActive)
        XCTAssertFalse(executor.canExecute(.addTextItem))
    }

    func testCommitTextDescriptorResetsActiveStateWhenPolicyBlocksInReadingMode() {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)

        XCTAssertNotNil(session.addTextItem())
        session.workspaceMode = .reading

        let descriptor = commandCatalog.descriptor(
            for: .commitTextEdit,
            session: session
        )
        let decision = policy.commandDecision(
            for: .commitTextEdit,
            workspaceMode: session.workspaceMode
        )

        XCTAssertEqual(decision, .block(reason: .readingMode, feedback: nil))
        XCTAssertFalse(descriptor.isEnabled)
        XCTAssertFalse(descriptor.isActive)
        XCTAssertFalse(executor.canExecute(.commitTextEdit))
    }

    func testInlineTextFontSizeCommandsDoNotForceInlineCommit() {
        XCTAssertFalse(CanvasCommand.decreaseTextFontSize.shouldCommitActiveInlineTextBeforeExecuting)
        XCTAssertFalse(CanvasCommand.increaseTextFontSize.shouldCommitActiveInlineTextBeforeExecuting)
        XCTAssertTrue(CanvasCommand.undo.shouldCommitActiveInlineTextBeforeExecuting)
    }

    func testInlineTextFontSizeDescriptorAndExecutorMatchPolicyInEditingMode() throws {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)

        XCTAssertNotNil(session.addTextItem())

        let increaseDescriptor = commandCatalog.descriptor(
            for: .increaseTextFontSize,
            session: session
        )
        let decreaseDescriptor = commandCatalog.descriptor(
            for: .decreaseTextFontSize,
            session: session
        )
        let increaseDecision = policy.commandDecision(
            for: .increaseTextFontSize,
            workspaceMode: session.workspaceMode
        )
        let decreaseDecision = policy.commandDecision(
            for: .decreaseTextFontSize,
            workspaceMode: session.workspaceMode
        )

        XCTAssertEqual(increaseDecision, .allow)
        XCTAssertEqual(decreaseDecision, .allow)
        XCTAssertTrue(increaseDescriptor.isEnabled)
        XCTAssertTrue(decreaseDescriptor.isEnabled)
        XCTAssertFalse(increaseDescriptor.isActive)
        XCTAssertFalse(decreaseDescriptor.isActive)
        XCTAssertTrue(executor.canExecute(.increaseTextFontSize))
        XCTAssertTrue(executor.canExecute(.decreaseTextFontSize))
    }

    func testInlineTextFontSizeDescriptorResetsWhenPolicyBlocksInReadingMode() {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)

        XCTAssertNotNil(session.addTextItem())
        session.workspaceMode = .reading

        let increaseDescriptor = commandCatalog.descriptor(
            for: .increaseTextFontSize,
            session: session
        )
        let decreaseDescriptor = commandCatalog.descriptor(
            for: .decreaseTextFontSize,
            session: session
        )
        let increaseDecision = policy.commandDecision(
            for: .increaseTextFontSize,
            workspaceMode: session.workspaceMode
        )
        let decreaseDecision = policy.commandDecision(
            for: .decreaseTextFontSize,
            workspaceMode: session.workspaceMode
        )

        XCTAssertEqual(increaseDecision, .block(reason: .readingMode, feedback: nil))
        XCTAssertEqual(decreaseDecision, .block(reason: .readingMode, feedback: nil))
        XCTAssertFalse(increaseDescriptor.isEnabled)
        XCTAssertFalse(decreaseDescriptor.isEnabled)
        XCTAssertFalse(executor.canExecute(.increaseTextFontSize))
        XCTAssertFalse(executor.canExecute(.decreaseTextFontSize))
    }

    func testIncreaseTextFontSizeCommandRecordsHistoryAndSupportsUndoRedo() throws {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)
        let initialStyle = CanvasTextStyle(fontSize: 20)
        let item = try XCTUnwrap(
            session.addTextItem(
                text: "Seed",
                style: initialStyle
            )
        )
        let originalItem = try XCTUnwrap(session.scene.textItem(withID: item.id))

        XCTAssertTrue(session.updateTextEditDraft("A much longer edited draft"))
        XCTAssertTrue(session.isInlineTextModeActive)
        XCTAssertNotNil(executor.execute(.increaseTextFontSize))

        let resizedItem = try XCTUnwrap(session.scene.textItem(withID: item.id))
        XCTAssertTrue(session.isInlineTextModeActive)
        XCTAssertGreaterThan(resizedItem.style.fontSize, originalItem.style.fontSize)
        XCTAssertEqual(
            resizedItem.size,
            CanvasTextLayoutMeasurer.intrinsicItemSize(
                for: "A much longer edited draft",
                style: resizedItem.style
            )
        )

        XCTAssertNotNil(executor.execute(.commitTextEdit))
        XCTAssertFalse(session.isInlineTextModeActive)
        XCTAssertNotNil(executor.execute(.undo))

        let undoneItem = try XCTUnwrap(session.scene.textItem(withID: item.id))
        XCTAssertEqual(undoneItem.style, originalItem.style)
        XCTAssertEqual(
            undoneItem.size,
            CanvasTextLayoutMeasurer.intrinsicItemSize(
                for: undoneItem.text,
                style: undoneItem.style
            )
        )

        XCTAssertNotNil(executor.execute(.redo))

        let redoneItem = try XCTUnwrap(session.scene.textItem(withID: item.id))
        XCTAssertEqual(redoneItem.style, resizedItem.style)
        XCTAssertEqual(redoneItem.size, resizedItem.size)
    }

    func testImportMediaExecutorMatchesPolicyInEditingMode() throws {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)
        let request = try makeCommandPolicyParityImportRequest()

        let decision = policy.commandDecision(
            for: .importMedia,
            workspaceMode: session.workspaceMode
        )

        XCTAssertEqual(decision, .allow)
        XCTAssertTrue(executor.canExecute(.importMedia(request)))
    }

    func testImportMediaExecutorMatchesPolicyInReadingMode() throws {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .reading)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)
        let request = try makeCommandPolicyParityImportRequest()

        let decision = policy.commandDecision(
            for: .importMedia,
            workspaceMode: session.workspaceMode
        )

        XCTAssertEqual(decision, .block(reason: .readingMode, feedback: nil))
        XCTAssertFalse(executor.canExecute(.importMedia(request)))
    }

    func testToggleSelectionMembershipExecutorBuildsAndShrinksSelectionSet() {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)
        let firstItem = makeCommandPolicyParityTextItem(
            text: "First",
            center: CGPoint(x: 20, y: 20),
            zIndex: 0
        )
        let secondItem = makeCommandPolicyParityTextItem(
            text: "Second",
            center: CGPoint(x: 60, y: 40),
            zIndex: 1
        )
        session.scene.append(firstItem)
        session.scene.append(secondItem)

        XCTAssertNotNil(
            executor.execute(
                .selectItem(itemID: firstItem.id, recordHistory: true)
            )
        )
        XCTAssertNotNil(
            executor.execute(
                .toggleSelectionMembership(
                    itemID: secondItem.id,
                    recordHistory: true
                )
            )
        )
        XCTAssertEqual(session.selectedItemIDs, [firstItem.id, secondItem.id])
        XCTAssertEqual(session.primarySelectedItemID, secondItem.id)

        XCTAssertNotNil(
            executor.execute(
                .toggleSelectionMembership(
                    itemID: firstItem.id,
                    recordHistory: true
                )
            )
        )
        XCTAssertEqual(session.selectedItemIDs, [secondItem.id])
        XCTAssertEqual(session.primarySelectedItemID, secondItem.id)
    }

    func testDuplicateSelectionExecutorSelectsDuplicatedItems() {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)
        let firstItem = makeCommandPolicyParityTextItem(
            text: "First",
            center: CGPoint(x: 12, y: 24),
            zIndex: 0
        )
        let secondItem = makeCommandPolicyParityTextItem(
            text: "Second",
            center: CGPoint(x: 96, y: 72),
            zIndex: 1
        )
        session.scene.append(firstItem)
        session.scene.append(secondItem)
        session.interactionState = CanvasInteractionState(
            selectedItemIDs: [firstItem.id, secondItem.id],
            primarySelectedItemID: secondItem.id
        )

        XCTAssertNotNil(executor.execute(.duplicateSelection(recordHistory: true)))

        let duplicatedItems = session.selectedBoardItems
        let offset = session.duplicateOffsetInWorld()
        XCTAssertEqual(session.scene.orderedBoardItems().count, 4)
        XCTAssertEqual(duplicatedItems.count, 2)
        XCTAssertEqual(session.selectionCount, 2)
        XCTAssertFalse(duplicatedItems.map(\.id).contains(firstItem.id))
        XCTAssertFalse(duplicatedItems.map(\.id).contains(secondItem.id))
        XCTAssertEqual(
            duplicatedItems.map(\.center),
            [
                CGPoint(
                    x: firstItem.center.x + offset.x,
                    y: firstItem.center.y + offset.y
                ),
                CGPoint(
                    x: secondItem.center.x + offset.x,
                    y: secondItem.center.y + offset.y
                )
            ]
        )
        XCTAssertEqual(session.primarySelectedItemID, duplicatedItems.last?.id)
    }

    func testDeleteSelectionExecutorRemovesAllSelectedItems() {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)
        let firstItem = makeCommandPolicyParityTextItem(
            text: "First",
            center: CGPoint(x: 10, y: 10),
            zIndex: 0
        )
        let secondItem = makeCommandPolicyParityTextItem(
            text: "Second",
            center: CGPoint(x: 40, y: 40),
            zIndex: 1
        )
        let thirdItem = makeCommandPolicyParityTextItem(
            text: "Third",
            center: CGPoint(x: 80, y: 60),
            zIndex: 2
        )
        session.scene.append(firstItem)
        session.scene.append(secondItem)
        session.scene.append(thirdItem)
        session.interactionState = CanvasInteractionState(
            selectedItemIDs: [firstItem.id, secondItem.id],
            primarySelectedItemID: secondItem.id
        )

        XCTAssertNotNil(executor.execute(.deleteSelection(recordHistory: true)))

        XCTAssertEqual(session.scene.orderedBoardItems().map(\.id), [thirdItem.id])
        XCTAssertEqual(session.selectedItemIDs, [])
        XCTAssertNil(session.primarySelectedItemID)
    }

    func testBringSelectionForwardExecutorPreservesRelativeOrder() {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)
        let firstItem = makeCommandPolicyParityTextItem(
            text: "First",
            center: CGPoint(x: 0, y: 0),
            zIndex: 0
        )
        let secondItem = makeCommandPolicyParityTextItem(
            text: "Second",
            center: CGPoint(x: 20, y: 20),
            zIndex: 1
        )
        let thirdItem = makeCommandPolicyParityTextItem(
            text: "Third",
            center: CGPoint(x: 40, y: 40),
            zIndex: 2
        )
        let fourthItem = makeCommandPolicyParityTextItem(
            text: "Fourth",
            center: CGPoint(x: 60, y: 60),
            zIndex: 3
        )
        session.scene.append(firstItem)
        session.scene.append(secondItem)
        session.scene.append(thirdItem)
        session.scene.append(fourthItem)
        session.interactionState = CanvasInteractionState(
            selectedItemIDs: [secondItem.id, thirdItem.id],
            primarySelectedItemID: thirdItem.id
        )

        XCTAssertNotNil(
            executor.execute(.bringSelectionForward(recordHistory: true))
        )

        XCTAssertEqual(
            session.scene.orderedBoardItems().map(\.id),
            [firstItem.id, fourthItem.id, secondItem.id, thirdItem.id]
        )
        XCTAssertEqual(session.selectedItemIDs, [secondItem.id, thirdItem.id])
        XCTAssertEqual(session.primarySelectedItemID, thirdItem.id)
    }

    func testTargetDuplicateCommandPreservesCurrentSelection() {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)
        let selectedItem = makeCommandPolicyParityTextItem(
            text: "Selected",
            center: CGPoint(x: 16, y: 16),
            zIndex: 0
        )
        let targetItem = makeCommandPolicyParityTextItem(
            text: "Target",
            center: CGPoint(x: 80, y: 48),
            zIndex: 1
        )
        session.scene.append(selectedItem)
        session.scene.append(targetItem)
        session.interactionState = CanvasInteractionState(selectedItemID: selectedItem.id)

        XCTAssertNotNil(
            executor.execute(
                .duplicateItem(
                    itemID: targetItem.id,
                    selectDuplicatedItem: false,
                    recordHistory: true
                )
            )
        )

        XCTAssertEqual(session.scene.orderedBoardItems().count, 3)
        XCTAssertEqual(session.selectedItemIDs, [selectedItem.id])
        XCTAssertEqual(session.primarySelectedItemID, selectedItem.id)
    }

    func testBeginCropModeCommandTargetsUnselectedItemAndReplacesSelection() throws {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)
        let selectedItem = makeCommandPolicyParityTextItem(
            text: "Selected",
            center: CGPoint(x: 24, y: 24),
            zIndex: 0
        )
        let targetItem = CanvasImageItem(
            asset: CanvasImageAsset.transientStaticImage(
                cgImage: try makeCommandPolicyParityImage(width: 24, height: 16)
            ),
            center: CGPoint(x: 100, y: 60),
            size: CGSize(width: 140, height: 90),
            zIndex: 1
        )
        session.scene.append(selectedItem)
        session.scene.append(targetItem)
        session.interactionState = CanvasInteractionState(selectedItemID: selectedItem.id)

        XCTAssertTrue(executor.canExecute(.beginCropMode(itemID: targetItem.id)))
        XCTAssertNotNil(executor.execute(.beginCropMode(itemID: targetItem.id)))
        XCTAssertEqual(session.selectedItemIDs, [targetItem.id])
        XCTAssertEqual(session.primarySelectedItemID, targetItem.id)
        XCTAssertTrue(session.isInlineCropModeActive)
    }
}

private enum CanvasCommandPolicyParityTestRetainer {
    static var sessions: [CanvasEditorSession] = []
    static var executors: [CanvasCommandExecutor] = []
}

private enum CanvasCommandPolicyParityTestError: Error {
    case invalidBitmapContext
    case invalidImage
}

private func makeCommandPolicyParityTestSession(
    workspaceMode: CanvasWorkspaceMode
) -> CanvasEditorSession {
    let session = CanvasEditorSession(
        saveQueueLabel: "CanvasCommandPolicyParityTests",
        logPrefix: "[CanvasCommandPolicyParityTests]"
    )
    session.workspaceMode = workspaceMode
    CanvasCommandPolicyParityTestRetainer.sessions.append(session)
    return session
}

private func makeCommandPolicyParityImportRequest() throws -> CanvasImportRequest {
    let image = CanvasResolvedImportImage(
        cgImage: try makeCommandPolicyParityImage(width: 24, height: 16)
    )
    return CanvasImportRequest(
        images: [image],
        sourceDescription: "command policy parity"
    )
}

private func makeCommandPolicyParityTextItem(
    text: String,
    center: CGPoint,
    zIndex: CGFloat
) -> CanvasTextItem {
    CanvasTextItem(
        text: text,
        center: center,
        size: CGSize(width: 120, height: 56),
        zIndex: zIndex
    )
}

private func makeCommandPolicyParityImage(
    width: Int,
    height: Int
) throws -> CGImage {
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
        throw CanvasCommandPolicyParityTestError.invalidBitmapContext
    }

    context.setFillColor(
        CGColor(red: 0.15, green: 0.45, blue: 0.85, alpha: 1)
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
        throw CanvasCommandPolicyParityTestError.invalidImage
    }

    return image
}
