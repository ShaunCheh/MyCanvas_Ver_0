import CoreGraphics
import Foundation

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

    var canBeginCropMode: Bool {
        guard let selectedItemID = interactionState.selectedItemID else {
            return false
        }

        return scene.item(withID: selectedItemID) != nil
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
                imageInlineEditState: inlineEditState,
                imageRotationPreviewState: rotationPreviewState
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

    func restorePersistedBoardIfPossible() {
        do {
            let runtimeState = try BoardStore.loadOrCreateInitialBoard()
            applyBoardRuntimeState(runtimeState)
            resetHistory()
        } catch FolderBookmarkStoreError.missingBookmarkData {
            return
        } catch {
            print("\(boardStoreLogPrefix) Failed to restore board: \(error)")
        }
    }

    func applyBoardRuntimeState(_ runtimeState: BoardRuntimeState) {
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
        lastRenderSnapshot = .empty
    }

    func currentBoardHistorySnapshot() -> BoardHistorySnapshot {
        BoardHistorySnapshot(
            items: scene.orderedItems(),
            boardState: boardState,
            interactionState: interactionState
        )
    }

    func applyBoardHistorySnapshot(_ snapshot: BoardHistorySnapshot) {
        if let runtimeState = currentBoardRuntimeState() {
            applyBoardRuntimeState(
                runtimeState.replacingDocumentState(with: snapshot)
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

        if let item = scene.item(withID: inlineEditState.itemID) {
            self.inlineEditState = CanvasInlineEditState(
                item: item,
                mode: inlineEditState.mode
            )
        }
    }

    func canSelectItem(withID itemID: CanvasImageItemID) -> Bool {
        interactionState.selectedItemID != itemID
    }

    @discardableResult
    func selectItem(
        withID itemID: CanvasImageItemID,
        recordHistory: Bool = false
    ) -> Bool {
        guard canSelectItem(withID: itemID) else {
            return false
        }

        let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
        interactionState.selectedItemID = itemID
        syncInlineEditStateWithSelection()

        if let beforeSnapshot {
            _ = recordImmediateHistoryChange(
                from: beforeSnapshot,
                reason: "select item"
            )
        }

        return true
    }

    @discardableResult
    func clearSelection(recordHistory: Bool = false) -> Bool {
        guard canClearSelection else {
            return false
        }

        let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
        interactionState.selectedItemID = nil
        syncInlineEditStateWithSelection()

        if let beforeSnapshot {
            _ = recordImmediateHistoryChange(
                from: beforeSnapshot,
                reason: "clear selection"
            )
        }

        return true
    }

    func scheduleAutosave(reason: String) {
        guard let snapshot = currentBoardRuntimeState() else {
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
        guard let snapshot = currentBoardRuntimeState(createBoardIfNeeded: createBoardIfNeeded) else {
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
            items: scene.orderedItems(),
            boardState: boardState,
            camera: camera,
            interactionState: interactionState
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
        let pixelSize = CGSize(
            width: cgImage.width,
            height: cgImage.height
        )
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

    func nextImageZIndex() -> CGFloat {
        (scene.orderedItems().last?.zIndex ?? -1) + 1
    }

    @discardableResult
    func appendImportedImage(_ cgImage: CGImage) -> CanvasImageItem {
        let beforeSnapshot = currentBoardHistorySnapshot()
        let item = CanvasImageItem(
            cgImage: cgImage,
            center: camera.center,
            size: normalizedDisplaySize(for: cgImage),
            zIndex: nextImageZIndex()
        )

        scene.append(item)
        expandBoardIfNeeded(toInclude: item.worldFrame)
        _ = recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: "append image",
            autosaveReason: "append image"
        )
        return item
    }
}
