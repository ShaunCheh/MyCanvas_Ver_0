import CoreGraphics
import Foundation

struct CanvasTextEditCommitResult {
    let itemID: CanvasItemID
    let didDeleteItem: Bool
    let didChangeDocument: Bool
}

final class CanvasEditorSession {
    let scene = CanvasScene()
    var camera = CanvasCamera()
    var boardState: CanvasBoardState?
    var interactionState = CanvasInteractionState()
    var inlineEditState: CanvasInlineEditState?
    var rotationPreviewState: CanvasRotationPreviewState?
    var rotationInteractionState: CanvasRotationInteractionState?

    private(set) var lastRenderSnapshot: CanvasRenderSnapshot = .empty
    private(set) var activeBoardID: UUID?
    private(set) var activeBoardCreatedAt: Date?
    var activeBoardTitle = BoardDocument.defaultTitle

    private let renderer = CanvasRenderer()
    private let miniMapRenderer = CanvasMiniMapRenderer()
    private let contextResolver = CanvasContextResolver()
    private let saveCoordinator: BoardSaveCoordinator
    private let historyController = BoardHistoryController()
    private let boardStoreLogPrefix: String
    private var transientImageAssetPayloads: [CanvasImageAssetReference: CanvasTransientImageAssetPayload] = [:]

    var imageAssetContract: CanvasImageAssetContract {
        .current
    }

    var shouldAutoplayAnimatedImagesOnCanvas: Bool {
        imageAssetContract.shouldAutoplayAnimatedImagesOnCanvas
    }

    func transientImageAssetPayload(
        for assetReference: CanvasImageAssetReference
    ) -> CanvasTransientImageAssetPayload? {
        transientImageAssetPayloads[assetReference]
    }

    init(
        saveQueueLabel: String,
        logPrefix: String
    ) {
        boardStoreLogPrefix = logPrefix
        saveCoordinator = BoardSaveCoordinator(
            queueLabel: saveQueueLabel,
            logPrefix: logPrefix
        )
    }

    var canUndoCommand: Bool {
        inlineEditState == nil && historyController.canUndo
    }

    var canRedoCommand: Bool {
        inlineEditState == nil && historyController.canRedo
    }

    var canAddTextItem: Bool {
        inlineEditState == nil
    }

    var canBeginCropMode: Bool {
        guard inlineEditState == nil else {
            return false
        }

        guard let selectedItemID = interactionState.selectedItemID else {
            return false
        }

        return scene.item(withID: selectedItemID) != nil
    }

    var canCommitTextEdit: Bool {
        isInlineTextModeActive
    }

    var canClearSelection: Bool {
        interactionState.selectedItemID != nil
    }

    var isInlineCropModeActive: Bool {
        inlineEditState?.mode == .crop
    }

    var isInlineEditModeActive: Bool {
        inlineEditState != nil
    }

    var isInlineTextModeActive: Bool {
        inlineEditState?.mode == .text
    }

    var selectedBoardItem: CanvasBoardItem? {
        guard let selectedItemID = interactionState.selectedItemID else {
            return nil
        }

        return scene.boardItem(withID: selectedItemID)
    }

    var selectedBoardItemKind: CanvasBoardItemKind? {
        selectedBoardItem?.kind
    }

    func makeCanvasSnapshot() -> CanvasRenderSnapshot {
        let snapshot = renderer.makeSnapshot(
            scene: scene,
            boardState: boardState,
            camera: camera,
            interactionState: interactionState,
            inlineEditState: inlineEditState,
            rotationPreviewState: rotationPreviewState,
            rotationInteractionState: rotationInteractionState
        )
        lastRenderSnapshot = snapshot
        return snapshot
    }

    func makeMiniMapSnapshot() -> CanvasMiniMapSnapshot {
        miniMapRenderer.makeSnapshot(
            context: CanvasMiniMapRenderContext(
                scene: scene,
                boardState: boardState,
                camera: camera,
                inlineEditState: inlineEditState,
                rotationPreviewState: rotationPreviewState
            )
        )
    }

    func resolveContext(
        at viewportPoint: CGPoint,
        interactionMetrics: CanvasContextResolverMetrics
    ) -> CanvasContextMenuContext {
        contextResolver.resolveContext(
            at: viewportPoint,
            scene: scene,
            camera: camera,
            renderSnapshot: lastRenderSnapshot,
            selectedItemID: interactionState.selectedItemID,
            isInlineEditModeActive: isInlineEditModeActive,
            isInlineCropModeActive: isInlineCropModeActive,
            interactionMetrics: interactionMetrics
        )
    }

    func expandBoardIfNeeded(toInclude worldFrame: CGRect) {
        guard var boardState else {
            return
        }

        if boardState.expandIfNeeded(toInclude: worldFrame) {
            self.boardState = boardState
        }
    }

    @discardableResult
    func configureBoardStateIfNeeded(for viewportSize: CGSize) -> Bool {
        guard boardState == nil else {
            return false
        }

        boardState = CanvasBoardState(
            baseSize: viewportSize,
            centeredAt: camera.center
        )
        return true
    }

    func loadBoard(id: UUID) throws {
        let runtimeState = try BoardStore.loadBoard(id: id)
        print(
            "[Canvas Shared][RuntimeRestore] " +
            "action=loadBoard " +
            "boardID=\(runtimeState.boardID.uuidString) " +
            "items=\(runtimeState.items.count) " +
            "cameraCenter=\(describeRuntimeRestorePoint(runtimeState.camera.center)) " +
            "cameraZoomScale=\(formatRuntimeRestoreValue(runtimeState.camera.zoomScale)) " +
            "cameraViewportSize=\(describeRuntimeRestoreSize(runtimeState.camera.viewportSize)) " +
            "selectedItemID=\(describeRuntimeRestoreItemID(runtimeState.interactionState.selectedItemID))"
        )
        applyBoardRuntimeState(runtimeState)
        resetHistory()
    }

    func startNewBoard(now: Date = Date()) {
        let runtimeState = BoardRuntimeState.makeEmpty(now: now)
        print(
            "[Canvas Shared][RuntimeRestore] " +
            "action=startNewBoard " +
            "boardID=\(runtimeState.boardID.uuidString) " +
            "items=\(runtimeState.items.count) " +
            "cameraCenter=\(describeRuntimeRestorePoint(runtimeState.camera.center)) " +
            "cameraZoomScale=\(formatRuntimeRestoreValue(runtimeState.camera.zoomScale)) " +
            "cameraViewportSize=\(describeRuntimeRestoreSize(runtimeState.camera.viewportSize)) " +
            "selectedItemID=\(describeRuntimeRestoreItemID(runtimeState.interactionState.selectedItemID))"
        )
        applyBoardRuntimeState(runtimeState)
        resetHistory()
    }

    func restorePersistedBoardIfPossible() {
        do {
            let runtimeState = try BoardStore.loadOrCreateInitialBoard()
            print(
                "[Canvas Shared][RuntimeRestore] " +
                "action=restorePersistedBoardIfPossible " +
                "boardID=\(runtimeState.boardID.uuidString) " +
                "items=\(runtimeState.items.count) " +
                "cameraCenter=\(describeRuntimeRestorePoint(runtimeState.camera.center)) " +
                "cameraZoomScale=\(formatRuntimeRestoreValue(runtimeState.camera.zoomScale)) " +
                "cameraViewportSize=\(describeRuntimeRestoreSize(runtimeState.camera.viewportSize)) " +
                "selectedItemID=\(describeRuntimeRestoreItemID(runtimeState.interactionState.selectedItemID))"
            )
            applyBoardRuntimeState(runtimeState)
            resetHistory()
        } catch FolderBookmarkStoreError.missingBookmarkData {
            return
        } catch {
            print("\(boardStoreLogPrefix) Failed to restore board: \(error)")
        }
    }

    func applyBoardRuntimeState(
        _ runtimeState: BoardRuntimeState,
        preserveTransientImageAssetPayloads: Bool = false
    ) {
        print(
            "[Canvas Shared][RuntimeRestore] " +
            "action=applyBoardRuntimeState " +
            "boardID=\(runtimeState.boardID.uuidString) " +
            "items=\(runtimeState.items.count) " +
            "boardState=\(describeRuntimeRestoreBoardState(runtimeState.boardState)) " +
            "cameraCenter=\(describeRuntimeRestorePoint(runtimeState.camera.center)) " +
            "cameraZoomScale=\(formatRuntimeRestoreValue(runtimeState.camera.zoomScale)) " +
            "cameraViewportSize=\(describeRuntimeRestoreSize(runtimeState.camera.viewportSize)) " +
            "selectedItemID=\(describeRuntimeRestoreItemID(runtimeState.interactionState.selectedItemID))"
        )
        activeBoardID = runtimeState.boardID
        activeBoardTitle = runtimeState.title
        activeBoardCreatedAt = runtimeState.createdAt
        scene.setItems(runtimeState.items)
        boardState = runtimeState.boardState
        camera = runtimeState.camera
        interactionState = runtimeState.interactionState
        inlineEditState = nil
        rotationPreviewState = nil
        rotationInteractionState = nil
        if preserveTransientImageAssetPayloads == false {
            transientImageAssetPayloads.removeAll()
        }
        lastRenderSnapshot = .empty
    }

    func currentBoardHistorySnapshot() -> BoardHistorySnapshot {
        BoardHistorySnapshot(
            items: scene.orderedBoardItems(),
            boardState: boardState,
            interactionState: interactionState
        )
    }

    func applyBoardHistorySnapshot(_ snapshot: BoardHistorySnapshot) {
        if let runtimeState = currentBoardRuntimeState() {
            applyBoardRuntimeState(
                runtimeState.replacingDocumentState(with: snapshot),
                preserveTransientImageAssetPayloads: true
            )
        } else {
            scene.setItems(snapshot.items)
            boardState = snapshot.boardState
            interactionState = snapshot.interactionState
            inlineEditState = nil
            rotationPreviewState = nil
            rotationInteractionState = nil
            lastRenderSnapshot = .empty
        }
    }

    func resetHistory() {
        historyController.reset()
    }

    func cancelPendingHistoryTransaction() {
        historyController.cancelPendingTransaction()
    }

    func undoHistorySnapshot() -> BoardHistorySnapshot? {
        guard canUndoCommand else {
            return nil
        }

        return historyController.undo()
    }

    func redoHistorySnapshot() -> BoardHistorySnapshot? {
        guard canRedoCommand else {
            return nil
        }

        return historyController.redo()
    }

    func beginHistoryTransaction(reason: String) {
        historyController.beginTransaction(
            from: currentBoardHistorySnapshot(),
            reason: reason
        )
    }

    @discardableResult
    func commitPendingHistoryTransaction(
        autosaveReason: String? = nil
    ) -> Bool {
        guard historyController.commitPendingTransaction(to: currentBoardHistorySnapshot()) else {
            return false
        }

        if let autosaveReason {
            scheduleAutosave(reason: autosaveReason)
        }

        return true
    }

    @discardableResult
    func recordImmediateHistoryChange(
        from beforeSnapshot: BoardHistorySnapshot,
        reason: String,
        autosaveReason: String? = nil
    ) -> Bool {
        guard historyController.recordChange(
            from: beforeSnapshot,
            to: currentBoardHistorySnapshot(),
            reason: reason
        ) else {
            return false
        }

        if let autosaveReason {
            scheduleAutosave(reason: autosaveReason)
        }

        return true
    }

    func canBeginTextEdit(withID itemID: CanvasItemID) -> Bool {
        guard inlineEditState == nil else {
            return false
        }

        return scene.textItem(withID: itemID) != nil
    }

    @discardableResult
    func beginTextEdit(withID itemID: CanvasItemID) -> Bool {
        guard
            canBeginTextEdit(withID: itemID),
            let item = scene.textItem(withID: itemID)
        else {
            return false
        }

        interactionState.selectedItemID = itemID
        inlineEditState = CanvasInlineEditState(item: item)
        return true
    }

    @discardableResult
    func updateTextEditDraft(_ draftText: String) -> Bool {
        guard
            var inlineEditState,
            inlineEditState.mode == .text,
            inlineEditState.draftText != draftText
        else {
            return false
        }

        inlineEditState.draftText = draftText
        self.inlineEditState = inlineEditState
        return true
    }

    @discardableResult
    func commitTextEdit() -> CanvasTextEditCommitResult? {
        guard
            let inlineEditState,
            inlineEditState.mode == .text
        else {
            return nil
        }

        let itemID = inlineEditState.itemID
        defer {
            self.inlineEditState = nil
        }

        guard let item = scene.textItem(withID: itemID) else {
            if interactionState.selectedItemID == itemID {
                interactionState.selectedItemID = nil
            }
            return CanvasTextEditCommitResult(
                itemID: itemID,
                didDeleteItem: false,
                didChangeDocument: false
            )
        }

        let draftText = inlineEditState.draftText
        if draftText == item.text {
            return CanvasTextEditCommitResult(
                itemID: itemID,
                didDeleteItem: false,
                didChangeDocument: false
            )
        }

        let beforeSnapshot = currentBoardHistorySnapshot()
        if draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard scene.removeItem(withID: itemID) else {
                return CanvasTextEditCommitResult(
                    itemID: itemID,
                    didDeleteItem: false,
                    didChangeDocument: false
                )
            }

            if interactionState.selectedItemID == itemID {
                interactionState.selectedItemID = nil
            }
            let changeReason = "delete empty text item"
            _ = recordImmediateHistoryChange(
                from: beforeSnapshot,
                reason: changeReason,
                autosaveReason: changeReason
            )
            return CanvasTextEditCommitResult(
                itemID: itemID,
                didDeleteItem: true,
                didChangeDocument: true
            )
        }

        guard scene.updateTextItem(withID: itemID, text: draftText) != nil else {
            return CanvasTextEditCommitResult(
                itemID: itemID,
                didDeleteItem: false,
                didChangeDocument: false
            )
        }

        let changeReason = "edit text item"
        _ = recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: changeReason,
            autosaveReason: changeReason
        )
        return CanvasTextEditCommitResult(
            itemID: itemID,
            didDeleteItem: false,
            didChangeDocument: true
        )
    }

    @discardableResult
    func beginCropModeIfPossible() -> Bool {
        guard
            canBeginCropMode,
            let selectedItemID = interactionState.selectedItemID,
            let item = scene.item(withID: selectedItemID)
        else {
            return false
        }

        inlineEditState = CanvasInlineEditState(item: item, mode: .crop)
        return true
    }

    @discardableResult
    func endInlineEditMode() -> Bool {
        guard inlineEditState != nil else {
            return false
        }

        inlineEditState = nil
        return true
    }

    func syncInlineEditStateWithSelection() {
        guard let inlineEditState else {
            return
        }

        guard interactionState.selectedItemID == inlineEditState.itemID else {
            self.inlineEditState = nil
            return
        }

        switch inlineEditState.mode {
        case .crop:
            if let item = scene.item(withID: inlineEditState.itemID) {
                self.inlineEditState = CanvasInlineEditState(
                    item: item,
                    mode: .crop
                )
            } else {
                self.inlineEditState = nil
            }
        case .text:
            if scene.textItem(withID: inlineEditState.itemID) == nil {
                self.inlineEditState = nil
            }
        }
    }

    func canSelectItem(withID itemID: CanvasItemID) -> Bool {
        guard scene.boardItem(withID: itemID) != nil else {
            return false
        }

        return interactionState.selectedItemID != itemID
    }

    func canDeleteItem(withID itemID: CanvasItemID) -> Bool {
        scene.boardItem(withID: itemID) != nil
    }

    func canDuplicateItem(withID itemID: CanvasItemID) -> Bool {
        scene.boardItem(withID: itemID) != nil
    }

    func canBringItemForward(withID itemID: CanvasItemID) -> Bool {
        scene.canBringItemForward(withID: itemID)
    }

    func canSendItemBackward(withID itemID: CanvasItemID) -> Bool {
        scene.canSendItemBackward(withID: itemID)
    }

    func canBringItemToFront(withID itemID: CanvasItemID) -> Bool {
        scene.canBringItemToFront(withID: itemID)
    }

    func canSendItemToBack(withID itemID: CanvasItemID) -> Bool {
        scene.canSendItemToBack(withID: itemID)
    }

    @discardableResult
    func selectItem(
        withID itemID: CanvasItemID,
        recordHistory: Bool = false
    ) -> Bool {
        guard canSelectItem(withID: itemID) else {
            print(
                "[Canvas Shared][SelectionMutation] " +
                "action=select " +
                "result=rejected " +
                "requestedItemID=\(itemID.uuidString) " +
                "recordHistory=\(recordHistory) " +
                "previousSelectedItemID=\(describeSelectionMutationItemID(interactionState.selectedItemID))"
            )
            return false
        }

        let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
        let previousSelectedItemID = interactionState.selectedItemID
        let inlineEditModeBefore = inlineEditState.map(\.mode)
        interactionState.selectedItemID = itemID
        syncInlineEditStateWithSelection()

        if let beforeSnapshot {
            _ = recordImmediateHistoryChange(
                from: beforeSnapshot,
                reason: "select item"
            )
        }

        print(
            "[Canvas Shared][SelectionMutation] " +
            "action=select " +
            "result=applied " +
            "requestedItemID=\(itemID.uuidString) " +
            "recordHistory=\(recordHistory) " +
            "previousSelectedItemID=\(describeSelectionMutationItemID(previousSelectedItemID)) " +
            "currentSelectedItemID=\(describeSelectionMutationItemID(interactionState.selectedItemID)) " +
            "inlineEditModeBefore=\(describeSelectionMutationInlineEditMode(inlineEditModeBefore)) " +
            "inlineEditModeAfter=\(describeSelectionMutationInlineEditMode(inlineEditState.map(\.mode)))"
        )

        return true
    }

    @discardableResult
    func clearSelection(recordHistory: Bool = false) -> Bool {
        guard canClearSelection else {
            print(
                "[Canvas Shared][SelectionMutation] " +
                "action=clear " +
                "result=rejected " +
                "recordHistory=\(recordHistory) " +
                "previousSelectedItemID=\(describeSelectionMutationItemID(interactionState.selectedItemID))"
            )
            return false
        }

        let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
        let previousSelectedItemID = interactionState.selectedItemID
        let inlineEditModeBefore = inlineEditState.map(\.mode)
        interactionState.selectedItemID = nil
        syncInlineEditStateWithSelection()

        if let beforeSnapshot {
            _ = recordImmediateHistoryChange(
                from: beforeSnapshot,
                reason: "clear selection"
            )
        }

        print(
            "[Canvas Shared][SelectionMutation] " +
            "action=clear " +
            "result=applied " +
            "recordHistory=\(recordHistory) " +
            "previousSelectedItemID=\(describeSelectionMutationItemID(previousSelectedItemID)) " +
            "currentSelectedItemID=\(describeSelectionMutationItemID(interactionState.selectedItemID)) " +
            "inlineEditModeBefore=\(describeSelectionMutationInlineEditMode(inlineEditModeBefore)) " +
            "inlineEditModeAfter=\(describeSelectionMutationInlineEditMode(inlineEditState.map(\.mode)))"
        )

        return true
    }

    @discardableResult
    func deleteItem(
        withID itemID: CanvasItemID,
        recordHistory: Bool = false
    ) -> Bool {
        guard canDeleteItem(withID: itemID) else {
            return false
        }

        let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
        guard scene.removeItem(withID: itemID) else {
            return false
        }

        if interactionState.selectedItemID == itemID {
            interactionState.selectedItemID = nil
        }
        syncInlineEditStateWithSelection()

        if let beforeSnapshot {
            _ = recordImmediateHistoryChange(
                from: beforeSnapshot,
                reason: "delete item"
            )
        }

        return true
    }

    @discardableResult
    func duplicateItem(
        withID itemID: CanvasItemID,
        selectDuplicatedItem: Bool = true,
        recordHistory: Bool = false
    ) -> CanvasBoardItem? {
        guard canDuplicateItem(withID: itemID) else {
            return nil
        }

        let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
        guard let duplicatedItem = scene.duplicateBoardItem(
            withID: itemID,
            offsetInWorld: duplicateOffsetInWorld()
        ) else {
            return nil
        }

        expandBoardIfNeeded(toInclude: duplicatedItem.worldBounds)
        if selectDuplicatedItem {
            interactionState.selectedItemID = duplicatedItem.id
        }
        syncInlineEditStateWithSelection()

        if let beforeSnapshot {
            _ = recordImmediateHistoryChange(
                from: beforeSnapshot,
                reason: "duplicate item"
            )
        }

        return duplicatedItem
    }

    @discardableResult
    func bringItemForward(
        withID itemID: CanvasItemID,
        recordHistory: Bool = false
    ) -> Bool {
        guard canBringItemForward(withID: itemID) else {
            return false
        }

        let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
        guard scene.bringItemForward(withID: itemID) != nil else {
            return false
        }
        syncInlineEditStateWithSelection()

        if let beforeSnapshot {
            _ = recordImmediateHistoryChange(
                from: beforeSnapshot,
                reason: "bring item forward"
            )
        }

        return true
    }

    @discardableResult
    func sendItemBackward(
        withID itemID: CanvasItemID,
        recordHistory: Bool = false
    ) -> Bool {
        guard canSendItemBackward(withID: itemID) else {
            return false
        }

        let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
        guard scene.sendItemBackward(withID: itemID) != nil else {
            return false
        }
        syncInlineEditStateWithSelection()

        if let beforeSnapshot {
            _ = recordImmediateHistoryChange(
                from: beforeSnapshot,
                reason: "send item backward"
            )
        }

        return true
    }

    @discardableResult
    func bringItemToFront(
        withID itemID: CanvasItemID,
        recordHistory: Bool = false
    ) -> Bool {
        guard canBringItemToFront(withID: itemID) else {
            return false
        }

        let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
        guard scene.bringItemToFront(withID: itemID) != nil else {
            return false
        }
        syncInlineEditStateWithSelection()

        if let beforeSnapshot {
            _ = recordImmediateHistoryChange(
                from: beforeSnapshot,
                reason: "bring item to front"
            )
        }

        return true
    }

    @discardableResult
    func sendItemToBack(
        withID itemID: CanvasItemID,
        recordHistory: Bool = false
    ) -> Bool {
        guard canSendItemToBack(withID: itemID) else {
            return false
        }

        let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
        guard scene.sendItemToBack(withID: itemID) != nil else {
            return false
        }
        syncInlineEditStateWithSelection()

        if let beforeSnapshot {
            _ = recordImmediateHistoryChange(
                from: beforeSnapshot,
                reason: "send item to back"
            )
        }

        return true
    }

    func scheduleAutosave(reason: String) {
        guard let snapshot = currentBoardSaveSnapshot() else {
            return
        }

        saveCoordinator.scheduleAutosave(
            snapshot: snapshot,
            reason: reason
        )
    }

    func saveBoardNow(
        reason: String,
        createBoardIfNeeded: Bool = false,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let snapshot = currentBoardSaveSnapshot(createBoardIfNeeded: createBoardIfNeeded) else {
            completion(.failure(FolderBookmarkStoreError.missingBookmarkData))
            return
        }

        saveCoordinator.saveImmediately(
            snapshot: snapshot,
            reason: reason,
            completion: completion
        )
    }

    func currentBoardRuntimeState(
        createBoardIfNeeded: Bool = false
    ) -> BoardRuntimeState? {
        if createBoardIfNeeded, ensureActiveBoardIdentityIfNeeded() == false {
            return nil
        }

        guard
            let activeBoardID,
            let activeBoardCreatedAt
        else {
            return nil
        }

        return BoardRuntimeState(
            boardID: activeBoardID,
            title: activeBoardTitle,
            createdAt: activeBoardCreatedAt,
            updatedAt: Date(),
            items: scene.orderedBoardItems(),
            boardState: boardState,
            camera: camera,
            interactionState: interactionState
        )
    }

    func currentBoardSaveSnapshot(
        createBoardIfNeeded: Bool = false
    ) -> BoardSaveSnapshot? {
        guard let runtimeState = currentBoardRuntimeState(
            createBoardIfNeeded: createBoardIfNeeded
        ) else {
            return nil
        }

        let referencedAssetReferences = Set(
            runtimeState.imageItems.map(\.assetReference)
        )
        let payloads = Dictionary(
            uniqueKeysWithValues: transientImageAssetPayloads.filter {
                referencedAssetReferences.contains($0.key)
            }
        )
        return BoardSaveSnapshot(
            runtimeState: runtimeState,
            transientImageAssetPayloads: payloads
        )
    }

    @discardableResult
    func ensureActiveBoardIdentityIfNeeded() -> Bool {
        guard activeBoardID == nil || activeBoardCreatedAt == nil else {
            return true
        }

        guard FolderBookmarkStore.hasStoredBookmarkData() else {
            return false
        }

        let now = Date()
        activeBoardID = activeBoardID ?? UUID()
        activeBoardCreatedAt = activeBoardCreatedAt ?? now
        if activeBoardTitle.isEmpty {
            activeBoardTitle = BoardDocument.defaultTitle
        }
        return true
    }

    func normalizedDisplaySize(for cgImage: CGImage) -> CGSize {
        normalizedDisplaySize(
            for: CGSize(
                width: cgImage.width,
                height: cgImage.height
            )
        )
    }

    func normalizedDisplaySize(for pixelSize: CGSize) -> CGSize {
        let longestSide = max(pixelSize.width, pixelSize.height)
        guard longestSide > 0 else {
            return CGSize(width: 240, height: 240)
        }

        let targetLongestSide: CGFloat = 320
        let scale = targetLongestSide / longestSide
        return CGSize(
            width: pixelSize.width * scale,
            height: pixelSize.height * scale
        )
    }

    func defaultTextItemSize(
        for style: CanvasTextStyle = .default
    ) -> CGSize {
        CGSize(
            width: max(style.fontSize * 7.5, 240),
            height: max(style.fontSize * 3, 96)
        )
    }

    func nextBoardItemZIndex() -> CGFloat {
        (scene.orderedBoardItems().last?.zIndex ?? -1) + 1
    }

    func nextImageZIndex() -> CGFloat {
        nextBoardItemZIndex()
    }

    func duplicateOffsetInWorld() -> CGPoint {
        let viewportOffset: CGFloat = 24
        let worldOffset = viewportOffset / max(camera.zoomScale, 0.01)
        return CGPoint(
            x: worldOffset,
            y: worldOffset
        )
    }

    private func resolvedImportCenter(
        for placement: CanvasImportPlacement
    ) -> CGPoint {
        switch placement {
        case .cameraCenter:
            return camera.center
        case let .worldPoint(point):
            return point
        }
    }

    private func resolvedImportLayout(
        _ layout: CanvasImportLayout,
        imageCount: Int
    ) -> CanvasImportLayout {
        switch layout {
        case .automatic:
            if imageCount <= 1 {
                return .stacked
            }

            return .staggered(stepInWorld: duplicateOffsetInWorld())
        case .stacked:
            return .stacked
        case let .staggered(stepInWorld):
            return .staggered(stepInWorld: stepInWorld)
        }
    }

    private func importOffset(
        forImageAt index: Int,
        layout: CanvasImportLayout
    ) -> CGPoint {
        switch layout {
        case .automatic, .stacked:
            return .zero
        case let .staggered(stepInWorld):
            let multiplier = CGFloat(index)
            return CGPoint(
                x: stepInWorld.x * multiplier,
                y: stepInWorld.y * multiplier
            )
        }
    }

    private func importedImageChangeReason(for imageCount: Int) -> String {
        guard imageCount > 1 else {
            return "append image"
        }

        return "append \(imageCount) images"
    }

    @discardableResult
    func addTextItem(
        text: String = "Text",
        style: CanvasTextStyle = .default
    ) -> CanvasTextItem? {
        guard canAddTextItem else {
            return nil
        }

        let beforeSnapshot = currentBoardHistorySnapshot()
        let item = CanvasTextItem(
            text: text,
            style: style,
            center: camera.center,
            size: defaultTextItemSize(for: style),
            zIndex: nextBoardItemZIndex()
        )
        scene.append(item)
        interactionState.selectedItemID = item.id
        inlineEditState = CanvasInlineEditState(item: item)
        expandBoardIfNeeded(toInclude: item.worldFrame)
        let changeReason = "add text item"
        _ = recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: changeReason,
            autosaveReason: changeReason
        )
        return item
    }

    @discardableResult
    func appendImportedImages(
        _ images: [CanvasResolvedImportImage],
        placement: CanvasImportPlacement = .cameraCenter,
        layout: CanvasImportLayout = .automatic
    ) -> [CanvasImageItem] {
        guard images.isEmpty == false else {
            return []
        }

        let beforeSnapshot = currentBoardHistorySnapshot()
        let importCenter = resolvedImportCenter(for: placement)
        let resolvedLayout = resolvedImportLayout(
            layout,
            imageCount: images.count
        )
        let startingZIndex = nextImageZIndex()
        var importedItems: [CanvasImageItem] = []
        importedItems.reserveCapacity(images.count)

        for (index, image) in images.enumerated() {
            let importRegistration = image.makeTransientImageAssetRegistration()
            let asset = importRegistration.asset
            if let payload = importRegistration.payload {
                transientImageAssetPayloads[payload.assetReference] = payload
            }
            let offset = importOffset(
                forImageAt: index,
                layout: resolvedLayout
            )
            let item = CanvasImageItem(
                asset: asset,
                center: CGPoint(
                    x: importCenter.x + offset.x,
                    y: importCenter.y + offset.y
                ),
                size: normalizedDisplaySize(for: asset.logicalPixelSize),
                zIndex: startingZIndex + CGFloat(index)
            )

            scene.append(item)
            expandBoardIfNeeded(toInclude: item.worldFrame)
            importedItems.append(item)
        }

        let changeReason = importedImageChangeReason(
            for: importedItems.count
        )
        _ = recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: changeReason,
            autosaveReason: changeReason
        )
        return importedItems
    }

    @discardableResult
    func appendImportedImage(
        _ cgImage: CGImage,
        placement: CanvasImportPlacement = .cameraCenter
    ) -> CanvasImageItem {
        let importedItems = appendImportedImages(
            [CanvasResolvedImportImage(cgImage: cgImage)],
            placement: placement,
            layout: .stacked
        )
        guard let item = importedItems.first else {
            preconditionFailure("Expected a single imported image result.")
        }

        return item
    }
}

private func describeSelectionMutationItemID(_ itemID: CanvasItemID?) -> String {
    itemID?.uuidString ?? "nil"
}

private func describeSelectionMutationInlineEditMode(
    _ mode: CanvasInlineEditMode?
) -> String {
    mode.map { String(describing: $0) } ?? "nil"
}

private func describeRuntimeRestorePoint(_ point: CGPoint) -> String {
    "{\(formatRuntimeRestoreValue(point.x)), \(formatRuntimeRestoreValue(point.y))}"
}

private func describeRuntimeRestoreSize(_ size: CGSize) -> String {
    "{\(formatRuntimeRestoreValue(size.width)), \(formatRuntimeRestoreValue(size.height))}"
}

private func describeRuntimeRestoreRect(_ rect: CGRect) -> String {
    "{{\(formatRuntimeRestoreValue(rect.origin.x)), \(formatRuntimeRestoreValue(rect.origin.y))}, {\(formatRuntimeRestoreValue(rect.size.width)), \(formatRuntimeRestoreValue(rect.size.height))}}"
}

private func describeRuntimeRestoreItemID(_ itemID: CanvasItemID?) -> String {
    itemID?.uuidString ?? "nil"
}

private func describeRuntimeRestoreBoardState(_ boardState: CanvasBoardState?) -> String {
    guard let boardState else {
        return "nil"
    }

    return "baseSize=\(describeRuntimeRestoreSize(boardState.baseSize)) worldRect=\(describeRuntimeRestoreRect(boardState.worldRect))"
}

private func formatRuntimeRestoreValue(_ value: CGFloat) -> String {
    String(format: "%.2f", Double(value))
}
