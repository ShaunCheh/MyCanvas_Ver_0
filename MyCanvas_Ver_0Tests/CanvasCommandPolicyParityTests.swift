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

    func testAddMarkdownDescriptorAndExecutorMatchPolicyInEditingMode() {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)

        let descriptor = commandCatalog.descriptor(
            for: .addMarkdownItem,
            session: session
        )
        let decision = policy.commandDecision(
            for: .addMarkdownItem,
            workspaceMode: session.workspaceMode
        )

        XCTAssertEqual(decision, .allow)
        XCTAssertTrue(descriptor.isEnabled)
        XCTAssertFalse(descriptor.isActive)
        XCTAssertTrue(executor.canExecute(.addMarkdownItem(markdownSource: nil)))
    }

    func testAddMarkdownDescriptorAndExecutorMatchPolicyInReadingMode() {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .reading)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)

        let descriptor = commandCatalog.descriptor(
            for: .addMarkdownItem,
            session: session
        )
        let decision = policy.commandDecision(
            for: .addMarkdownItem,
            workspaceMode: session.workspaceMode
        )

        XCTAssertEqual(decision, .block(reason: .readingMode, feedback: nil))
        XCTAssertFalse(descriptor.isEnabled)
        XCTAssertFalse(descriptor.isActive)
        XCTAssertFalse(executor.canExecute(.addMarkdownItem(markdownSource: nil)))
    }

    func testAddMarkdownCommandUsesProvidedSourceWhenPresent() throws {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)
        let source = """
        # Pasted

        Body from clipboard.
        """

        let result = try XCTUnwrap(
            executor.execute(.addMarkdownItem(markdownSource: source))
        )
        let item = try XCTUnwrap(session.selectedMarkdownItem)

        XCTAssertEqual(item.markdownSource, source)
        XCTAssertEqual(
            result.refreshReason,
            "add markdown item \(item.id.uuidString)"
        )
    }

    func testAddMarkdownItemUsesMeasuredHeightAtDefaultWidth() throws {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let source = """
        ## Markdown

        A wrapped paragraph for measurement.
        """
        let style = CanvasTextStyle(fontSize: 20)

        let item = try XCTUnwrap(
            session.addMarkdownItem(
                markdownSource: source,
                style: style
            )
        )
        let expectedHeight = CanvasMarkdownLayoutMeasurer.measuredContentHeight(
            markdownSource: source,
            style: style,
            maxLayoutWidth: 320
        )

        XCTAssertEqual(item.size.width, 320, accuracy: 0.0001)
        XCTAssertEqual(item.size.height, expectedHeight, accuracy: 0.0001)
    }

    func testFinalizeMarkdownResizeCommitRemeasuresHeightAndPreservesFixedCorner() throws {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let source = """
        ## Markdown

        A wrapped paragraph that needs a real height recompute after resize commit.

        - First
        - Second
        - Third
        """
        let style = CanvasTextStyle(fontSize: 20)
        let originalItem = CanvasMarkdownItem(
            markdownSource: source,
            style: style,
            center: CGPoint(x: 40, y: 30),
            size: CGSize(width: 80, height: 60),
            scrollOffsetY: 10_000
        )
        session.scene.append(originalItem)

        let provisionalItem = try XCTUnwrap(
            session.scene.resizeBoardItem(
                withID: originalItem.id,
                toCenter: CGPoint(x: 80, y: 45),
                size: CGSize(width: 160, height: 90)
            )?.markdownItem
        )
        let provisionalFixedCorner = provisionalItem.worldPoint(
            fromLocal: CGPoint(
                x: provisionalItem.localFrame.minX,
                y: provisionalItem.localFrame.minY
            )
        )

        let committedItem = try XCTUnwrap(
            session.finalizeMarkdownResizeCommit(
                withID: originalItem.id,
                handleRole: .bottomTrailing,
                originalLayoutWidth: originalItem.size.width
            )
        )
        let expectedContentHeight = CanvasMarkdownLayoutMeasurer.measuredContentHeight(
            markdownSource: source,
            style: style,
            maxLayoutWidth: provisionalItem.size.width
        )
        let expectedScrollOffsetY = min(
            originalItem.scrollOffsetY,
            max(expectedContentHeight - provisionalItem.size.height, 0)
        )
        let committedFixedCorner = committedItem.worldPoint(
            fromLocal: CGPoint(
                x: committedItem.localFrame.minX,
                y: committedItem.localFrame.minY
            )
        )

        XCTAssertEqual(committedItem.size.width, provisionalItem.size.width, accuracy: 0.0001)
        XCTAssertEqual(committedItem.size.height, provisionalItem.size.height, accuracy: 0.0001)
        XCTAssertEqual(committedItem.scrollOffsetY, expectedScrollOffsetY, accuracy: 0.0001)
        XCTAssertEqual(committedFixedCorner.x, provisionalFixedCorner.x, accuracy: 0.0001)
        XCTAssertEqual(committedFixedCorner.y, provisionalFixedCorner.y, accuracy: 0.0001)
    }

    func testFinalizeMarkdownWidthOnlyResizeCommitClampsScrollAndPreservesFixedEdge() throws {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let source = """
        ## Markdown

        A wrapped paragraph that should only resize by width while keeping the explicit viewport height.

        - First
        - Second
        """
        let style = CanvasTextStyle(fontSize: 20)
        let originalItem = CanvasMarkdownItem(
            markdownSource: source,
            style: style,
            center: CGPoint(x: 40, y: 30),
            size: CGSize(width: 80, height: 60),
            scrollOffsetY: 10_000
        )
        session.scene.append(originalItem)

        let provisionalItem = try XCTUnwrap(
            session.scene.resizeBoardItem(
                withID: originalItem.id,
                toCenter: CGPoint(x: 80, y: 30),
                size: CGSize(width: 160, height: 90)
            )?.markdownItem
        )
        let provisionalFixedEdgeAnchor = provisionalItem.worldPoint(
            fromLocal: CGPoint(
                x: provisionalItem.localFrame.minX,
                y: provisionalItem.localFrame.midY
            )
        )

        let committedItem = try XCTUnwrap(
            session.finalizeMarkdownResizeCommit(
                withID: originalItem.id,
                handleRole: .trailing,
                originalLayoutWidth: originalItem.size.width
            )
        )
        let expectedContentHeight = CanvasMarkdownLayoutMeasurer.measuredContentHeight(
            markdownSource: source,
            style: style,
            maxLayoutWidth: provisionalItem.size.width
        )
        let expectedScrollOffsetY = min(
            originalItem.scrollOffsetY,
            max(expectedContentHeight - provisionalItem.size.height, 0)
        )
        let committedFixedEdgeAnchor = committedItem.worldPoint(
            fromLocal: CGPoint(
                x: committedItem.localFrame.minX,
                y: committedItem.localFrame.midY
            )
        )

        XCTAssertEqual(committedItem.size.width, provisionalItem.size.width, accuracy: 0.0001)
        XCTAssertEqual(committedItem.size.height, provisionalItem.size.height, accuracy: 0.0001)
        XCTAssertEqual(committedItem.center.y, provisionalItem.center.y, accuracy: 0.0001)
        XCTAssertEqual(committedItem.scrollOffsetY, expectedScrollOffsetY, accuracy: 0.0001)
        XCTAssertEqual(committedFixedEdgeAnchor.x, provisionalFixedEdgeAnchor.x, accuracy: 0.0001)
        XCTAssertEqual(committedFixedEdgeAnchor.y, provisionalFixedEdgeAnchor.y, accuracy: 0.0001)
    }

    func testBeginMarkdownEditCommandProducesEditorFollowUp() throws {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)
        let item = try XCTUnwrap(session.addMarkdownItem())

        let result = try XCTUnwrap(
            executor.execute(.beginMarkdownEdit(itemID: item.id))
        )
        guard case let .presentMarkdownEditor(followUpItemID)? = result.followUp else {
            XCTFail("Expected beginMarkdownEdit to request markdown editor follow-up.")
            return
        }

        XCTAssertEqual(followUpItemID, item.id)
        XCTAssertEqual(session.singleSelectedItemID, item.id)
    }

    func testAddHandDrawingDescriptorAndExecutorMatchPolicyInEditingMode() {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)

        let descriptor = commandCatalog.descriptor(
            for: .addHandDrawingItem,
            session: session
        )
        let decision = policy.commandDecision(
            for: .addHandDrawingItem,
            workspaceMode: session.workspaceMode
        )

        XCTAssertEqual(decision, .allow)
        XCTAssertTrue(descriptor.isEnabled)
        XCTAssertFalse(descriptor.isActive)
        XCTAssertTrue(executor.canExecute(.addHandDrawingItem(paper: .square)))
    }

    func testAddHandDrawingDescriptorAndExecutorMatchPolicyInReadingMode() {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .reading)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)

        let descriptor = commandCatalog.descriptor(
            for: .addHandDrawingItem,
            session: session
        )
        let decision = policy.commandDecision(
            for: .addHandDrawingItem,
            workspaceMode: session.workspaceMode
        )

        XCTAssertEqual(decision, .block(reason: .readingMode, feedback: nil))
        XCTAssertFalse(descriptor.isEnabled)
        XCTAssertFalse(descriptor.isActive)
        XCTAssertFalse(executor.canExecute(.addHandDrawingItem(paper: .square)))
    }

    func testAddHandDrawingCommandProducesFollowUpAndTransientPayload() throws {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)

        let result = try XCTUnwrap(
            executor.execute(.addHandDrawingItem(paper: .square))
        )
        guard case let .presentHandDrawingEditor(itemID)? = result.followUp else {
            XCTFail("Expected addHandDrawingItem to request editor follow-up.")
            return
        }

        let addedItem = try XCTUnwrap(
            session.scene.handDrawingItem(withID: itemID)
        )
        XCTAssertTrue(addedItem.isEmpty)
        XCTAssertEqual(session.singleSelectedItemID, itemID)
        XCTAssertNotNil(session.transientHandDrawingAssetPayload(for: itemID))
    }

    func testAddArrowDescriptorAndExecutorMatchPolicyInEditingMode() {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)

        let descriptor = commandCatalog.descriptor(
            for: .addArrowItem,
            session: session
        )
        let decision = policy.commandDecision(
            for: .addArrowItem,
            workspaceMode: session.workspaceMode
        )

        XCTAssertEqual(decision, .allow)
        XCTAssertTrue(descriptor.isEnabled)
        XCTAssertFalse(descriptor.isActive)
        XCTAssertTrue(executor.canExecute(.addArrowItem))
    }

    func testAddArrowDescriptorAndExecutorMatchPolicyInReadingMode() {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .reading)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)

        let descriptor = commandCatalog.descriptor(
            for: .addArrowItem,
            session: session
        )
        let decision = policy.commandDecision(
            for: .addArrowItem,
            workspaceMode: session.workspaceMode
        )

        XCTAssertEqual(decision, .block(reason: .readingMode, feedback: nil))
        XCTAssertFalse(descriptor.isEnabled)
        XCTAssertFalse(descriptor.isActive)
        XCTAssertFalse(executor.canExecute(.addArrowItem))
    }

    func testAddArrowCommandCreatesDefaultHorizontalArrow() throws {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)

        let result = try XCTUnwrap(executor.execute(.addArrowItem))
        let itemID = try XCTUnwrap(session.singleSelectedItemID)
        let item = try XCTUnwrap(session.scene.arrowItem(withID: itemID))

        XCTAssertEqual(item.center, session.camera.center)
        XCTAssertEqual(item.size, CGSize(width: 220, height: 80))
        XCTAssertEqual(item.rotationRadians, 0, accuracy: 0.0001)
        XCTAssertEqual(itemID, item.id)
        XCTAssertEqual(
            result.refreshReason,
            "add arrow item \(item.id.uuidString)"
        )
    }

    func testArrowThicknessCommandsPreserveEndpointsAndSupportUndoRedo() throws {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)
        let originalItem = try XCTUnwrap(session.addArrowItem())

        let decreaseDescriptor = commandCatalog.descriptor(
            for: .decreaseArrowThickness,
            session: session
        )
        let increaseDescriptor = commandCatalog.descriptor(
            for: .increaseArrowThickness,
            session: session
        )
        XCTAssertTrue(decreaseDescriptor.isEnabled)
        XCTAssertTrue(increaseDescriptor.isEnabled)
        XCTAssertTrue(executor.canExecute(.decreaseArrowThickness))
        XCTAssertTrue(executor.canExecute(.increaseArrowThickness))

        let result = try XCTUnwrap(executor.execute(.increaseArrowThickness))
        let thickenedItem = try XCTUnwrap(
            session.scene.arrowItem(withID: originalItem.id)
        )
        XCTAssertEqual(thickenedItem.startPoint, originalItem.startPoint)
        XCTAssertEqual(thickenedItem.endPoint, originalItem.endPoint)
        XCTAssertGreaterThan(
            thickenedItem.shaftThickness,
            originalItem.shaftThickness
        )
        XCTAssertGreaterThan(thickenedItem.size.height, originalItem.size.height)
        XCTAssertEqual(
            result.refreshReason,
            "increase arrow thickness \(originalItem.id.uuidString)"
        )

        XCTAssertNotNil(executor.execute(.undo))
        let undoneItem = try XCTUnwrap(
            session.scene.arrowItem(withID: originalItem.id)
        )
        XCTAssertTrue(undoneItem.matchesDocumentState(originalItem))

        XCTAssertNotNil(executor.execute(.redo))
        let redoneItem = try XCTUnwrap(
            session.scene.arrowItem(withID: originalItem.id)
        )
        XCTAssertTrue(redoneItem.matchesDocumentState(thickenedItem))

        XCTAssertNotNil(executor.execute(.decreaseArrowThickness))
        let restoredItem = try XCTUnwrap(
            session.scene.arrowItem(withID: originalItem.id)
        )
        XCTAssertTrue(restoredItem.matchesDocumentState(originalItem))
    }

    func testArrowThicknessCommandsRespectMinimumThickness() {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)
        let item = CanvasArrowItem(
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 180, y: 0),
            shaftThickness: 0
        )
        session.scene.append(item)
        session.interactionState = CanvasInteractionState(selectedItemID: item.id)

        let decreaseDescriptor = commandCatalog.descriptor(
            for: .decreaseArrowThickness,
            session: session
        )
        let increaseDescriptor = commandCatalog.descriptor(
            for: .increaseArrowThickness,
            session: session
        )

        XCTAssertFalse(decreaseDescriptor.isEnabled)
        XCTAssertTrue(increaseDescriptor.isEnabled)
        XCTAssertFalse(executor.canExecute(.decreaseArrowThickness))
        XCTAssertTrue(executor.canExecute(.increaseArrowThickness))
    }

    func testArrowEndpointDragPreservesArrowProfile() throws {
        let item = CanvasArrowItem(
            center: CGPoint(x: 120, y: 80),
            size: CGSize(width: 220, height: 80)
        )
        let dragState = CanvasArrowEndpointDragState(
            item: item,
            draggedEndpointRole: .end,
            minimumLength: 1
        )
        let draggedEndPoint = CGPoint(x: 420, y: 180)
        let geometry = dragState.updatedGeometry(
            draggedWorldPoint: draggedEndPoint
        )
        let updatedItem = try XCTUnwrap(
            CanvasBoardItem
                .arrow(item)
                .applyingGeometry(geometry)?
                .arrowItem
        )

        let originalHeadLength = item.localFrame.maxX -
            canvasArrowPolygonPoints(in: item.localFrame)[1].x
        let updatedHeadLength = updatedItem.localFrame.maxX -
            canvasArrowPolygonPoints(in: updatedItem.localFrame)[1].x

        XCTAssertEqual(updatedItem.startPoint.x, item.startPoint.x, accuracy: 0.0001)
        XCTAssertEqual(updatedItem.startPoint.y, item.startPoint.y, accuracy: 0.0001)
        XCTAssertEqual(updatedItem.endPoint.x, draggedEndPoint.x, accuracy: 0.0001)
        XCTAssertEqual(updatedItem.endPoint.y, draggedEndPoint.y, accuracy: 0.0001)
        XCTAssertEqual(updatedItem.size.height, item.size.height, accuracy: 0.0001)
        XCTAssertEqual(updatedItem.shaftThickness, item.shaftThickness, accuracy: 0.0001)
        XCTAssertEqual(originalHeadLength, updatedHeadLength, accuracy: 0.0001)
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
        XCTAssertFalse(CanvasCommand.commitMarkdownEdit.shouldCommitActiveInlineTextBeforeExecuting)
        XCTAssertFalse(CanvasCommand.decreaseMarkdownContentSize.shouldCommitActiveInlineTextBeforeExecuting)
        XCTAssertFalse(CanvasCommand.increaseMarkdownContentSize.shouldCommitActiveInlineTextBeforeExecuting)
        XCTAssertFalse(CanvasCommand.decreaseArrowThickness.shouldCommitActiveInlineTextBeforeExecuting)
        XCTAssertFalse(CanvasCommand.increaseArrowThickness.shouldCommitActiveInlineTextBeforeExecuting)
        XCTAssertTrue(CanvasCommand.undo.shouldCommitActiveInlineTextBeforeExecuting)
    }

    func testInlineAndHistoryCommandsResetEditHandleInteractionBoundary() {
        let itemID = CanvasItemID()
        let boundaryCommands: [CanvasCommand] = [
            .beginTextEdit(itemID: itemID),
            .commitTextEdit,
            .beginMarkdownEdit(itemID: itemID),
            .commitMarkdownEdit,
            .crop,
            .beginCropMode(itemID: itemID),
            .undo,
            .redo
        ]

        for command in boundaryCommands {
            XCTAssertTrue(command.resetsEditHandleInteractionAfterExecution)
        }

        XCTAssertFalse(
            CanvasCommand
                .selectItem(itemID: itemID, recordHistory: false)
                .resetsEditHandleInteractionAfterExecution
        )
        XCTAssertFalse(
            CanvasCommand.addArrowItem
                .resetsEditHandleInteractionAfterExecution
        )
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

    func testIncreaseMarkdownContentSizeCommandPreservesViewportHeightAndSupportsUndoRedo() throws {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)
        let initialStyle = CanvasTextStyle(fontSize: 20)
        let item = try XCTUnwrap(
            session.addMarkdownItem(
                markdownSource: "## Seed",
                style: initialStyle
            )
        )
        let resizedContainer = try XCTUnwrap(
            session.scene.updateMarkdownItem(
                withID: item.id,
                markdownSource: item.markdownSource,
                style: item.style,
                size: CGSize(width: 180, height: 48)
            )
        )
        let originalItem = try XCTUnwrap(
            session.scene.markdownItem(withID: resizedContainer.id)
        )

        XCTAssertNotNil(executor.execute(.increaseMarkdownContentSize))

        let resizedItem = try XCTUnwrap(session.scene.markdownItem(withID: item.id))
        XCTAssertGreaterThan(resizedItem.style.fontSize, originalItem.style.fontSize)
        XCTAssertEqual(resizedItem.size.width, originalItem.size.width)
        XCTAssertEqual(resizedItem.size.height, originalItem.size.height, accuracy: 0.0001)
        XCTAssertEqual(resizedItem.markdownSource, originalItem.markdownSource)

        XCTAssertNotNil(executor.execute(.undo))

        let undoneItem = try XCTUnwrap(session.scene.markdownItem(withID: item.id))
        XCTAssertEqual(undoneItem.style, originalItem.style)
        XCTAssertEqual(undoneItem.size, originalItem.size)
        XCTAssertEqual(undoneItem.markdownSource, originalItem.markdownSource)

        XCTAssertNotNil(executor.execute(.redo))

        let redoneItem = try XCTUnwrap(session.scene.markdownItem(withID: item.id))
        XCTAssertEqual(redoneItem.style, resizedItem.style)
        XCTAssertEqual(redoneItem.size, resizedItem.size)
        XCTAssertEqual(redoneItem.markdownSource, resizedItem.markdownSource)
    }

    func testCommitMarkdownEditKeepsCurrentWidthAndViewportHeight() throws {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let item = try XCTUnwrap(
            session.addMarkdownItem(
                markdownSource: "Seed",
                style: CanvasTextStyle(fontSize: 18)
            )
        )
        let customizedItem = try XCTUnwrap(
            session.scene.updateMarkdownItem(
                withID: item.id,
                markdownSource: item.markdownSource,
                style: item.style,
                size: CGSize(width: 210, height: 60)
            )
        )
        let updatedSource = """
        ## Updated

        A much longer markdown paragraph that should be reflowed using the current block width.
        """

        let commitResult = try XCTUnwrap(
            session.commitMarkdownEdit(
                withID: item.id,
                markdownSource: updatedSource
            )
        )
        let updatedItem = try XCTUnwrap(session.scene.markdownItem(withID: item.id))

        XCTAssertTrue(commitResult.didChangeDocument)
        XCTAssertEqual(updatedItem.size.width, customizedItem.size.width)
        XCTAssertEqual(updatedItem.size.height, customizedItem.size.height, accuracy: 0.0001)
        XCTAssertEqual(updatedItem.markdownSource, updatedSource)
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
