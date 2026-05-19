import CoreGraphics
import Foundation

struct CanvasTextEditCommitResult {
    let itemID: CanvasItemID
    let didDeleteItem: Bool
    let didChangeDocument: Bool
}

struct CanvasVideoPosterUpdateResult {
    let item: CanvasImageItem
    let refreshReason: String
}

private struct CanvasPreparedImportItem {
    let asset: CanvasImageAsset
    let transientPayload: CanvasTransientImageAssetPayload?
    let videoSource: CanvasVideoSource?
    let posterTimeSeconds: Double?
    let size: CGSize
    let cropRectNormalized: CanvasImageCropRect
    let rotationRadians: CGFloat
}

final class CanvasEditorSession {
    private static let inlineTextFontSizeStep: CGFloat = 2

    let scene = CanvasScene()
    var camera = CanvasCamera()
    var boardState: CanvasBoardState?
    var interactionState = CanvasInteractionState()
    var workspaceMode: CanvasWorkspaceMode = .editing
    var inlineEditState: CanvasInlineEditState?
    var rotationPreviewState: CanvasRotationPreviewState?
    var rotationInteractionState: CanvasRotationInteractionState?
    var alignmentInteractionState: CanvasAlignmentInteractionState?

    private(set) var lastRenderSnapshot: CanvasRenderSnapshot = .empty
    private(set) var activeBoardID: UUID?
    private(set) var activeBoardCreatedAt: Date?
    private(set) var activeBoardContentUpdatedAt: Date?
    private(set) var activeBoardViewStateUpdatedAt: Date?
    var activeBoardTitle = BoardDocument.defaultTitle

    private let renderer = CanvasRenderer()
    private let miniMapRenderer = CanvasMiniMapRenderer()
    private let contextResolver = CanvasContextResolver()
    private let userDefaults: UserDefaults
    private let saveCoordinator: BoardSaveCoordinator
    private let historyController = BoardHistoryController()
    private let boardStoreLogPrefix: String
    private var transientImageAssetPayloads: [CanvasImageAssetReference: CanvasTransientImageAssetPayload] = [:]
    private var transientHandDrawingAssetPayloads: [CanvasItemID: BoardTransientHandDrawingAssetPayload] = [:]

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

    func transientHandDrawingAssetPayload(
        for itemID: CanvasItemID
    ) -> BoardTransientHandDrawingAssetPayload? {
        transientHandDrawingAssetPayloads[itemID]
    }

    func animatedImagePlaybackSource(
        for assetReference: CanvasImageAssetReference
    ) -> CanvasAnimatedImagePlaybackSource? {
        guard assetReference.kind.isAnimated else {
            return nil
        }

        if let payload = transientImageAssetPayload(for: assetReference),
           let data = payload.source?.data
        {
            return CanvasAnimatedImagePlaybackSource(
                assetReference: assetReference,
                data: data,
                animatedMetadata: payload.animatedMetadata
            )
        }

        guard let activeBoardID else {
            return nil
        }

        guard let data = try? BoardStore.loadImageAssetData(
            boardID: activeBoardID,
            filename: assetReference.stableAssetFilename,
            userDefaults: userDefaults
        ) else {
            return nil
        }

        return CanvasAnimatedImagePlaybackSource(
            assetReference: assetReference,
            data: data,
            animatedMetadata: nil
        )
    }

    init(
        saveQueueLabel: String,
        logPrefix: String,
        userDefaults: UserDefaults = .standard
    ) {
        self.userDefaults = userDefaults
        boardStoreLogPrefix = logPrefix
        saveCoordinator = BoardSaveCoordinator(
            queueLabel: saveQueueLabel,
            logPrefix: logPrefix,
            userDefaults: userDefaults
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

    var canAddHandDrawingItem: Bool {
        inlineEditState == nil
    }

    var hasSelection: Bool {
        interactionState.hasSelection
    }

    var selectionCount: Int {
        interactionState.selectionCount
    }

    var selectedItemIDs: [CanvasItemID] {
        interactionState.selectedItemIDs
    }

    var primarySelectedItemID: CanvasItemID? {
        interactionState.primarySelectedItemID
    }

    var singleSelectedItemID: CanvasItemID? {
        interactionState.singleSelectedItemID
    }

    var canBeginCropMode: Bool {
        guard inlineEditState == nil else {
            return false
        }

        guard let selectedItemID = singleSelectedItemID else {
            return false
        }

        return canBeginCropMode(withID: selectedItemID)
    }

    var canCommitTextEdit: Bool {
        isInlineTextModeActive
    }

    var canDecreaseInlineTextFontSize: Bool {
        canAdjustInlineTextFontSize(by: -Self.inlineTextFontSizeStep)
    }

    var canIncreaseInlineTextFontSize: Bool {
        canAdjustInlineTextFontSize(by: Self.inlineTextFontSizeStep)
    }

    var canClearSelection: Bool {
        hasSelection
    }

    var canDeleteSelection: Bool {
        selectedBoardItems.isEmpty == false
    }

    var canDuplicateSelection: Bool {
        selectedBoardItems.isEmpty == false
    }

    var canBringSelectionForward: Bool {
        scene.canBringBoardItemsForward(withIDs: selectedItemIDs)
    }

    var canSendSelectionBackward: Bool {
        scene.canSendBoardItemsBackward(withIDs: selectedItemIDs)
    }

    var canBringSelectionToFront: Bool {
        scene.canBringBoardItemsToFront(withIDs: selectedItemIDs)
    }

    var canSendSelectionToBack: Bool {
        scene.canSendBoardItemsToBack(withIDs: selectedItemIDs)
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

    var isReadingModeActive: Bool {
        workspaceMode == .reading
    }

    var isEditingModeActive: Bool {
        workspaceMode == .editing
    }

    var presentationInteractionState: CanvasInteractionState {
        guard isReadingModeActive else {
            return interactionState
        }

        return CanvasInteractionState()
    }

    var presentationInlineEditState: CanvasInlineEditState? {
        isReadingModeActive ? nil : inlineEditState
    }

    var presentationRotationPreviewState: CanvasRotationPreviewState? {
        isReadingModeActive ? nil : rotationPreviewState
    }

    var presentationRotationInteractionState: CanvasRotationInteractionState? {
        isReadingModeActive ? nil : rotationInteractionState
    }

    var presentationAlignmentInteractionState: CanvasAlignmentInteractionState? {
        isReadingModeActive ? nil : alignmentInteractionState
    }

    var selectedBoardItem: CanvasBoardItem? {
        guard let selectedItemID = singleSelectedItemID else {
            return nil
        }

        return scene.boardItem(withID: selectedItemID)
    }

    var selectedHandDrawingItem: CanvasHandDrawingItem? {
        selectedBoardItem?.handDrawingItem
    }

    var selectedBoardItems: [CanvasBoardItem] {
        selectedItemIDs.compactMap { itemID in
            scene.boardItem(withID: itemID)
        }
    }

    var selectedBoardItemKind: CanvasBoardItemKind? {
        selectedBoardItem?.kind
    }

    var canEditSelectedHandDrawing: Bool {
        guard let selectedItemID = singleSelectedItemID else {
            return false
        }

        return canEditHandDrawing(withID: selectedItemID)
    }

    var activeInlineTextItem: CanvasTextItem? {
        guard
            let inlineEditState,
            inlineEditState.mode == .text
        else {
            return nil
        }

        return scene.textItem(withID: inlineEditState.itemID)
    }

    func makeCanvasSnapshot() -> CanvasRenderSnapshot {
        let snapshot = renderer.makeSnapshot(
            scene: scene,
            boardState: boardState,
            camera: camera,
            interactionState: presentationInteractionState,
            inlineEditState: presentationInlineEditState,
            rotationPreviewState: presentationRotationPreviewState,
            rotationInteractionState: presentationRotationInteractionState,
            alignmentInteractionState: presentationAlignmentInteractionState
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
                inlineEditState: presentationInlineEditState,
                rotationPreviewState: presentationRotationPreviewState
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
            selectedItemIDs: interactionState.selectedItemIDs,
            primarySelectedItemID: interactionState.primarySelectedItemID,
            isInlineEditModeActive: isInlineEditModeActive,
            isInlineCropModeActive: isInlineCropModeActive,
            isReadingModeActive: isReadingModeActive,
            interactionMetrics: interactionMetrics
        )
    }

    func resolvePointerTarget(
        at viewportPoint: CGPoint,
        interactionMetrics: CanvasContextResolverMetrics
    ) -> CanvasPointerPressContext {
        contextResolver.resolvePointerTarget(
            at: viewportPoint,
            scene: scene,
            camera: camera,
            renderSnapshot: lastRenderSnapshot,
            selectedItemIDs: interactionState.selectedItemIDs,
            isInlineEditModeActive: isInlineEditModeActive,
            isReadingModeActive: isReadingModeActive,
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
        let runtimeState = try BoardStore.loadBoard(
            id: id,
            userDefaults: userDefaults
        )
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
            let runtimeState = try BoardStore.loadOrCreateInitialBoard(
                userDefaults: userDefaults
            )
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
        activeBoardContentUpdatedAt = runtimeState.contentUpdatedAt
        activeBoardViewStateUpdatedAt = runtimeState.viewStateUpdatedAt
        scene.setItems(runtimeState.items)
        boardState = runtimeState.boardState
        camera = runtimeState.camera
        interactionState = runtimeState.interactionState
        workspaceMode = runtimeState.workspaceMode
        inlineEditState = nil
        rotationPreviewState = nil
        rotationInteractionState = nil
        alignmentInteractionState = nil
        if preserveTransientImageAssetPayloads == false {
            transientImageAssetPayloads.removeAll()
            transientHandDrawingAssetPayloads.removeAll()
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
            alignmentInteractionState = nil
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

    func canBeginCropMode(withID itemID: CanvasItemID) -> Bool {
        guard inlineEditState == nil else {
            return false
        }

        return scene.item(withID: itemID) != nil
    }

    func canEditHandDrawing(withID itemID: CanvasItemID) -> Bool {
        guard inlineEditState == nil else {
            return false
        }

        return scene.handDrawingItem(withID: itemID) != nil
    }

    @discardableResult
    func beginTextEdit(withID itemID: CanvasItemID) -> Bool {
        guard
            canBeginTextEdit(withID: itemID),
            let item = scene.textItem(withID: itemID)
        else {
            return false
        }

        _ = replaceSelection(
            with: [itemID],
            primarySelectedItemID: itemID
        )
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
    func decreaseInlineTextFontSize() -> CanvasTextItem? {
        adjustInlineTextFontSize(by: -Self.inlineTextFontSizeStep)
    }

    @discardableResult
    func increaseInlineTextFontSize() -> CanvasTextItem? {
        adjustInlineTextFontSize(by: Self.inlineTextFontSizeStep)
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
            _ = normalizeSelectionAfterMutation()
            return CanvasTextEditCommitResult(
                itemID: itemID,
                didDeleteItem: false,
                didChangeDocument: false
            )
        }

        let draftText = inlineEditState.draftText
        if draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let beforeSnapshot = currentBoardHistorySnapshot()
            guard scene.removeItem(withID: itemID) else {
                return CanvasTextEditCommitResult(
                    itemID: itemID,
                    didDeleteItem: false,
                    didChangeDocument: false
                )
            }

            _ = normalizeSelectionAfterMutation()
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

        if draftText == item.text {
            return CanvasTextEditCommitResult(
                itemID: itemID,
                didDeleteItem: false,
                didChangeDocument: false
            )
        }

        let beforeSnapshot = currentBoardHistorySnapshot()

        guard updateTextItemContent(withID: itemID, text: draftText, style: item.style) != nil else {
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

    func handDrawingEditorContext(
        for itemID: CanvasItemID
    ) throws -> CanvasHandDrawingEditorContext {
        guard let item = scene.handDrawingItem(withID: itemID) else {
            throw CanvasHandDrawingEditingError.invalidHandDrawingItem(
                itemID: itemID
            )
        }

        if let payload = transientHandDrawingAssetPayload(for: itemID) {
            return CanvasHandDrawingEditorContext(
                itemID: itemID,
                documentID: item.documentID,
                paper: item.paper,
                documentData: payload.documentData,
                isEmpty: item.isEmpty,
                storage: .bundle,
                didMigrateLegacyDocument: false
            )
        }

        guard let activeBoardID else {
            throw CanvasHandDrawingEditingError.missingBoardIdentity
        }

        let preparedDocument = try HandDrawingMigrationService.prepareDocumentForEditing(
            boardID: activeBoardID,
            itemID: itemID,
            userDefaults: userDefaults
        )
        return CanvasHandDrawingEditorContext(
            itemID: itemID,
            documentID: item.documentID,
            paper: item.paper,
            documentData: preparedDocument.documentData,
            isEmpty: item.isEmpty,
            storage: preparedDocument.record.storage,
            didMigrateLegacyDocument: preparedDocument.didMigrateLegacyDocument
        )
    }

    @discardableResult
    func commitHandDrawingEdit(
        withID itemID: CanvasItemID,
        submission: CanvasHandDrawingEditSubmission
    ) throws -> CanvasHandDrawingEditCommitResult? {
        guard var item = scene.handDrawingItem(withID: itemID) else {
            throw CanvasHandDrawingEditingError.invalidHandDrawingItem(
                itemID: itemID
            )
        }

        if item.contentRevision == submission.contentRevision,
           item.isEmpty == submission.isEmpty,
           resolvedHandDrawingDocumentData(for: item) == submission.documentData
        {
            return nil
        }

        let beforeSnapshot = currentBoardHistorySnapshot()
        item.previewAsset = CanvasHandDrawingItem.persistedPreviewAsset(
            for: item.documentID,
            cgImage: submission.previewCGImage,
            logicalPixelSize: item.paper.size
        )
        item.isEmpty = submission.isEmpty
        item.contentRevision = submission.contentRevision
        scene.upsert(item)
        transientHandDrawingAssetPayloads[itemID] =
            BoardTransientHandDrawingAssetPayload(
                itemID: itemID,
                documentData: submission.documentData,
                previewCGImage: submission.previewCGImage
            )
        syncInlineEditStateWithSelection()
        let changeReason = "commit hand drawing edit"
        _ = recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: changeReason,
            autosaveReason: changeReason
        )
        return CanvasHandDrawingEditCommitResult(
            item: item,
            refreshReason: changeReason
        )
    }

    func videoEditorContext(
        for itemID: CanvasItemID
    ) throws -> CanvasVideoEditorContext {
        guard let activeBoardID else {
            throw CanvasVideoFrameServiceError.missingBoardIdentity
        }
        guard let item = scene.item(withID: itemID), item.isVideo else {
            throw CanvasVideoFrameServiceError.invalidVideoItem(itemID: itemID)
        }

        return try CanvasVideoFrameService.editorContext(
            for: item,
            boardID: activeBoardID
        )
    }

    func gifFrameImportEditorContext(
        for itemID: CanvasItemID,
        configuration: CanvasGIFFrameImportConfiguration = .current,
        userDefaults: UserDefaults = .standard
    ) throws -> CanvasGIFFrameImportEditorContext {
        guard
            let sourceItem = scene.item(withID: itemID),
            sourceItem.isVideo == false,
            sourceItem.assetKind == .animatedGIF
        else {
            throw CanvasGIFFrameImportBuilderError.invalidAnimatedGIFItem(
                itemID: itemID
            )
        }

        let sourceData = try gifFrameImportSourceData(
            for: sourceItem,
            userDefaults: userDefaults
        )
        guard
            let imageSource = CanvasGIFFrameService.makeImageSource(from: sourceData)
        else {
            throw CanvasGIFFrameImportBuilderError.invalidGIFData
        }

        let frameCount = CanvasGIFFrameService.frameCount(from: imageSource)
        guard frameCount > 1 else {
            throw CanvasGIFFrameImportBuilderError.invalidGIFData
        }

        return CanvasGIFFrameImportEditorContext(
            itemID: itemID,
            gifData: sourceData,
            frameCount: frameCount,
            selectionGrid: configuration.selectionGrid,
            thumbnailMaxPixelSize: configuration.thumbnailMaxPixelSize
        )
    }

    func gifFrameImportRequest(
        for itemID: CanvasItemID,
        frameIndices: [Int],
        configuration: CanvasGIFFrameImportConfiguration = .current,
        userDefaults: UserDefaults = .standard
    ) throws -> CanvasImportRequest {
        guard
            let sourceItem = scene.item(withID: itemID),
            sourceItem.isVideo == false,
            sourceItem.assetKind == .animatedGIF
        else {
            throw CanvasGIFFrameImportBuilderError.invalidAnimatedGIFItem(
                itemID: itemID
            )
        }

        let sourceData = try gifFrameImportSourceData(
            for: sourceItem,
            userDefaults: userDefaults
        )
        return try CanvasGIFFrameImportBuilder.makeImportRequest(
            from: sourceItem,
            gifData: sourceData,
            selectedFrameIndices: frameIndices,
            configuration: configuration
        )
    }

    private func gifFrameImportSourceData(
        for sourceItem: CanvasImageItem,
        userDefaults: UserDefaults = .standard
    ) throws -> Data {
        if let sourceData = transientImageAssetPayload(
            for: sourceItem.assetReference
        )?.source?.data {
            return sourceData
        }

        guard let activeBoardID else {
            throw CanvasGIFFrameImportBuilderError.missingBoardIdentity
        }

        do {
            return try BoardStore.loadImageAssetData(
                boardID: activeBoardID,
                filename: sourceItem.assetReference.stableAssetFilename,
                userDefaults: userDefaults
            )
        } catch let error as FolderBookmarkStoreError {
            throw error
        } catch {
            throw CanvasGIFFrameImportBuilderError.missingAnimatedImageSource(
                itemID: sourceItem.id
            )
        }
    }

    func videoFrameImage(
        for itemID: CanvasItemID,
        at timeSeconds: Double,
        quality: CanvasVideoFrameRenderQuality = .posterCommit
    ) throws -> CanvasVideoFrameImage {
        let editorContext = try videoEditorContext(for: itemID)
        return try CanvasVideoFrameService.frameImage(
            from: editorContext.sourceVideoURL,
            at: timeSeconds,
            quality: quality
        )
    }

    func videoPreviewStrip(
        for itemID: CanvasItemID,
        frameCount: Int = 9,
        maxPixelSize: Int = 160
    ) throws -> CanvasVideoPreviewStrip {
        let editorContext = try videoEditorContext(for: itemID)
        return try CanvasVideoFrameService.previewStrip(
            from: editorContext.sourceVideoURL,
            frameCount: frameCount,
            maxPixelSize: maxPixelSize
        )
    }

    func videoTimelineStrip(
        for itemID: CanvasItemID,
        request: CanvasVideoTimelineStripRequest
    ) throws -> CanvasVideoTimelineStrip {
        let editorContext = try videoEditorContext(for: itemID)
        let normalizedRequest = CanvasVideoTimelineStripRequest(
            viewport: request.viewport.with(
                durationSeconds: editorContext.durationSeconds
            ),
            thumbnailWidth: request.thumbnailWidth,
            maxPixelSize: request.maxPixelSize,
            overscanWidth: request.overscanWidth
        )
        return try CanvasVideoFrameService.timelineStrip(
            from: editorContext.sourceVideoURL,
            request: normalizedRequest
        )
    }

    func canUpdateVideoPoster(withID itemID: CanvasItemID) -> Bool {
        scene.item(withID: itemID)?.isVideo == true
    }

    @discardableResult
    func commitVideoPosterFrame(
        withID itemID: CanvasItemID,
        frameImage: CanvasVideoFrameImage
    ) throws -> CanvasVideoPosterUpdateResult {
        let editorContext = try videoEditorContext(for: itemID)
        let persistedPoster = try CanvasVideoFrameService.persistPosterAsset(
            cgImage: frameImage.cgImage,
            logicalPixelSize: frameImage.logicalPixelSize,
            posterTimeSeconds: frameImage.actualTimeSeconds,
            boardID: editorContext.boardID,
            itemID: itemID
        )
        guard let updateResult = updateVideoPoster(
            withID: itemID,
            posterAsset: persistedPoster.asset,
            posterTimeSeconds: persistedPoster.posterTimeSeconds
        ) else {
            throw CanvasVideoFrameServiceError.invalidVideoItem(itemID: itemID)
        }

        return updateResult
    }

    @discardableResult
    func updateVideoPoster(
        withID itemID: CanvasItemID,
        posterAsset: CanvasImageAsset,
        posterTimeSeconds: Double
    ) -> CanvasVideoPosterUpdateResult? {
        guard canUpdateVideoPoster(withID: itemID) else {
            return nil
        }

        let beforeSnapshot = currentBoardHistorySnapshot()
        guard let updatedItem = scene.updateVideoPoster(
            withID: itemID,
            posterAsset: posterAsset,
            posterTimeSeconds: posterTimeSeconds
        ) else {
            return nil
        }

        syncInlineEditStateWithSelection()
        let changeReason = "update video poster"
        _ = recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: changeReason,
            autosaveReason: changeReason
        )
        return CanvasVideoPosterUpdateResult(
            item: updatedItem,
            refreshReason: changeReason
        )
    }

    @discardableResult
    func beginCropModeIfPossible() -> Bool {
        guard
            let selectedItemID = singleSelectedItemID
        else {
            return false
        }

        return beginCropModeIfPossible(withID: selectedItemID)
    }

    @discardableResult
    func beginCropModeIfPossible(withID itemID: CanvasItemID) -> Bool {
        guard
            canBeginCropMode(withID: itemID),
            let item = scene.item(withID: itemID)
        else {
            return false
        }

        _ = replaceSelection(
            with: [itemID],
            primarySelectedItemID: itemID
        )
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

        guard
            selectionCount == 1,
            singleSelectedItemID == inlineEditState.itemID
        else {
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

        let normalizedSelection = normalizedSelectionStateForExistingItems(
            selectedItemIDs: [itemID],
            primarySelectedItemID: itemID
        )
        return interactionState.selectedItemIDs != normalizedSelection.selectedItemIDs
            || interactionState.primarySelectedItemID != normalizedSelection.primarySelectedItemID
    }

    func canToggleSelectionMembership(withID itemID: CanvasItemID) -> Bool {
        scene.boardItem(withID: itemID) != nil
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
    func replaceSelection(
        with itemIDs: [CanvasItemID],
        primarySelectedItemID: CanvasItemID? = nil,
        recordHistory: Bool = false
    ) -> Bool {
        let normalizedSelection = normalizedSelectionStateForExistingItems(
            selectedItemIDs: itemIDs,
            primarySelectedItemID: primarySelectedItemID
        )
        guard
            interactionState.selectedItemIDs != normalizedSelection.selectedItemIDs
                || interactionState.primarySelectedItemID != normalizedSelection.primarySelectedItemID
        else {
            print(
                "[Canvas Shared][SelectionMutation] " +
                "action=replace " +
                "result=rejected " +
                "recordHistory=\(recordHistory) " +
                "requestedSelectedItemIDs=\(describeSelectionMutationItemIDs(itemIDs)) " +
                "requestedPrimarySelectedItemID=\(describeSelectionMutationItemID(primarySelectedItemID)) " +
                "currentSelection=\(describeSelectionMutationState(interactionState))"
            )
            return false
        }

        let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
        let previousInteractionState = interactionState
        let inlineEditModeBefore = inlineEditState.map(\.mode)
        applySelectionState(normalizedSelection)

        if let beforeSnapshot {
            _ = recordImmediateHistoryChange(
                from: beforeSnapshot,
                reason: normalizedSelection.selectedItemIDs.isEmpty
                    ? "clear selection"
                    : "replace selection"
            )
        }

        print(
            "[Canvas Shared][SelectionMutation] " +
            "action=replace " +
            "result=applied " +
            "recordHistory=\(recordHistory) " +
            "requestedSelectedItemIDs=\(describeSelectionMutationItemIDs(itemIDs)) " +
            "requestedPrimarySelectedItemID=\(describeSelectionMutationItemID(primarySelectedItemID)) " +
            "previousSelection=\(describeSelectionMutationState(previousInteractionState)) " +
            "currentSelection=\(describeSelectionMutationState(interactionState)) " +
            "inlineEditModeBefore=\(describeSelectionMutationInlineEditMode(inlineEditModeBefore)) " +
            "inlineEditModeAfter=\(describeSelectionMutationInlineEditMode(inlineEditState.map(\.mode)))"
        )

        return true
    }

    @discardableResult
    func selectItem(
        withID itemID: CanvasItemID,
        recordHistory: Bool = false
    ) -> Bool {
        replaceSelection(
            with: [itemID],
            primarySelectedItemID: itemID,
            recordHistory: recordHistory
        )
    }

    @discardableResult
    func addToSelection(
        withID itemID: CanvasItemID,
        recordHistory: Bool = false
    ) -> Bool {
        guard scene.boardItem(withID: itemID) != nil else {
            print(
                "[Canvas Shared][SelectionMutation] " +
                "action=add " +
                "result=rejected " +
                "recordHistory=\(recordHistory) " +
                "requestedItemID=\(itemID.uuidString) " +
                "currentSelection=\(describeSelectionMutationState(interactionState))"
            )
            return false
        }

        return replaceSelection(
            with: interactionState.selectedItemIDs + [itemID],
            primarySelectedItemID: itemID,
            recordHistory: recordHistory
        )
    }

    @discardableResult
    func removeFromSelection(
        withID itemID: CanvasItemID,
        recordHistory: Bool = false
    ) -> Bool {
        guard interactionState.selectedItemIDs.contains(itemID) else {
            print(
                "[Canvas Shared][SelectionMutation] " +
                "action=remove " +
                "result=rejected " +
                "recordHistory=\(recordHistory) " +
                "requestedItemID=\(itemID.uuidString) " +
                "currentSelection=\(describeSelectionMutationState(interactionState))"
            )
            return false
        }

        return replaceSelection(
            with: interactionState.selectedItemIDs.filter { $0 != itemID },
            primarySelectedItemID: interactionState.primarySelectedItemID == itemID
                ? nil
                : interactionState.primarySelectedItemID,
            recordHistory: recordHistory
        )
    }

    @discardableResult
    func toggleSelectionMembership(
        of itemID: CanvasItemID,
        recordHistory: Bool = false
    ) -> Bool {
        guard canToggleSelectionMembership(withID: itemID) else {
            print(
                "[Canvas Shared][SelectionMutation] " +
                "action=toggle " +
                "result=rejected " +
                "recordHistory=\(recordHistory) " +
                "requestedItemID=\(itemID.uuidString) " +
                "currentSelection=\(describeSelectionMutationState(interactionState))"
            )
            return false
        }

        if interactionState.selectedItemIDs.contains(itemID) {
            return removeFromSelection(
                withID: itemID,
                recordHistory: recordHistory
            )
        }

        return addToSelection(
            withID: itemID,
            recordHistory: recordHistory
        )
    }

    @discardableResult
    func clearSelection(recordHistory: Bool = false) -> Bool {
        replaceSelection(with: [], recordHistory: recordHistory)
    }

    @discardableResult
    func normalizeSelectionAfterMutation(
        preferredPrimarySelectedItemID: CanvasItemID? = nil
    ) -> Bool {
        let normalizedSelection = normalizedSelectionStateForExistingItems(
            selectedItemIDs: interactionState.selectedItemIDs,
            primarySelectedItemID: preferredPrimarySelectedItemID
                ?? interactionState.primarySelectedItemID
        )
        let didChangeSelection =
            interactionState.selectedItemIDs != normalizedSelection.selectedItemIDs
            || interactionState.primarySelectedItemID != normalizedSelection.primarySelectedItemID
        if didChangeSelection {
            applySelectionState(normalizedSelection)
        } else {
            syncInlineEditStateWithSelection()
        }

        return didChangeSelection
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
        guard scene.removeBoardItems(withIDs: [itemID]).isEmpty == false else {
            return false
        }

        _ = normalizeSelectionAfterMutation()

        if let beforeSnapshot {
            _ = recordImmediateHistoryChange(
                from: beforeSnapshot,
                reason: "delete item"
            )
        }

        return true
    }

    @discardableResult
    func deleteSelection(recordHistory: Bool = false) -> Bool {
        let itemIDsToDelete = filteredExistingItemIDs(from: interactionState.selectedItemIDs)
        guard itemIDsToDelete.isEmpty == false else {
            return false
        }

        let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
        guard scene.removeBoardItems(withIDs: itemIDsToDelete).isEmpty == false else {
            return false
        }

        _ = normalizeSelectionAfterMutation()

        if let beforeSnapshot {
            _ = recordImmediateHistoryChange(
                from: beforeSnapshot,
                reason: itemIDsToDelete.count == 1
                    ? "delete selection item"
                    : "delete selection"
            )
        }

        return true
    }

    @discardableResult
    func duplicateItem(
        withID itemID: CanvasItemID,
        selectDuplicatedItem: Bool = false,
        recordHistory: Bool = false
    ) -> CanvasBoardItem? {
        guard canDuplicateItem(withID: itemID) else {
            return nil
        }

        let sourceItems = scene.orderedBoardItems().filter { $0.id == itemID }
        guard
            let sourceDocumentDataByItemID = preparedHandDrawingDuplicationDocumentData(
                for: sourceItems
            )
        else {
            return nil
        }
        let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
        guard let duplicatedItem = scene.duplicateBoardItem(
            withID: itemID,
            offsetInWorld: duplicateOffsetInWorld()
        ) else {
            return nil
        }
        registerDuplicatedHandDrawingPayloads(
            sourceItems: sourceItems,
            duplicatedItems: [duplicatedItem],
            sourceDocumentDataByItemID: sourceDocumentDataByItemID
        )

        expandBoardIfNeeded(toInclude: duplicatedItem.worldBounds)
        if selectDuplicatedItem {
            _ = replaceSelection(
                with: [duplicatedItem.id],
                primarySelectedItemID: duplicatedItem.id
            )
        } else {
            _ = normalizeSelectionAfterMutation()
        }

        if let beforeSnapshot {
            _ = recordImmediateHistoryChange(
                from: beforeSnapshot,
                reason: "duplicate item"
            )
        }

        return duplicatedItem
    }

    @discardableResult
    func duplicateSelection(
        selectDuplicatedItems: Bool = true,
        recordHistory: Bool = false
    ) -> [CanvasBoardItem]? {
        let sourceItemIDs = filteredExistingItemIDs(from: interactionState.selectedItemIDs)
        guard sourceItemIDs.isEmpty == false else {
            return nil
        }

        let sourceItemIDSet = Set(sourceItemIDs)
        let sourceItems = scene.orderedBoardItems().filter { sourceItemIDSet.contains($0.id) }
        guard
            let sourceDocumentDataByItemID = preparedHandDrawingDuplicationDocumentData(
                for: sourceItems
            )
        else {
            return nil
        }
        let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
        let duplicatedItems = scene.duplicateBoardItems(
            withIDs: sourceItemIDs,
            offsetInWorld: duplicateOffsetInWorld()
        )
        guard duplicatedItems.isEmpty == false else {
            return nil
        }
        registerDuplicatedHandDrawingPayloads(
            sourceItems: sourceItems,
            duplicatedItems: duplicatedItems,
            sourceDocumentDataByItemID: sourceDocumentDataByItemID
        )

        for duplicatedItem in duplicatedItems {
            expandBoardIfNeeded(toInclude: duplicatedItem.worldBounds)
        }
        if selectDuplicatedItems {
            _ = replaceSelection(
                with: duplicatedItems.map(\.id),
                primarySelectedItemID: duplicatedItems.last?.id
            )
        } else {
            _ = normalizeSelectionAfterMutation()
        }

        if let beforeSnapshot {
            _ = recordImmediateHistoryChange(
                from: beforeSnapshot,
                reason: duplicatedItems.count == 1
                    ? "duplicate selection item"
                    : "duplicate selection"
            )
        }

        return duplicatedItems
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
        guard scene.bringBoardItemForward(withID: itemID) != nil else {
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
    func bringSelectionForward(recordHistory: Bool = false) -> Bool {
        guard canBringSelectionForward else {
            return false
        }

        let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
        guard scene.bringBoardItemsForward(withIDs: selectedItemIDs) else {
            return false
        }
        syncInlineEditStateWithSelection()

        if let beforeSnapshot {
            _ = recordImmediateHistoryChange(
                from: beforeSnapshot,
                reason: selectionCount == 1
                    ? "bring selection item forward"
                    : "bring selection forward"
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
        guard scene.sendBoardItemBackward(withID: itemID) != nil else {
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
    func sendSelectionBackward(recordHistory: Bool = false) -> Bool {
        guard canSendSelectionBackward else {
            return false
        }

        let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
        guard scene.sendBoardItemsBackward(withIDs: selectedItemIDs) else {
            return false
        }
        syncInlineEditStateWithSelection()

        if let beforeSnapshot {
            _ = recordImmediateHistoryChange(
                from: beforeSnapshot,
                reason: selectionCount == 1
                    ? "send selection item backward"
                    : "send selection backward"
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
        guard scene.bringBoardItemToFront(withID: itemID) != nil else {
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
    func bringSelectionToFront(recordHistory: Bool = false) -> Bool {
        guard canBringSelectionToFront else {
            return false
        }

        let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
        guard scene.bringBoardItemsToFront(withIDs: selectedItemIDs) else {
            return false
        }
        syncInlineEditStateWithSelection()

        if let beforeSnapshot {
            _ = recordImmediateHistoryChange(
                from: beforeSnapshot,
                reason: selectionCount == 1
                    ? "bring selection item to front"
                    : "bring selection to front"
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
        guard scene.sendBoardItemToBack(withID: itemID) != nil else {
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

    @discardableResult
    func sendSelectionToBack(recordHistory: Bool = false) -> Bool {
        guard canSendSelectionToBack else {
            return false
        }

        let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
        guard scene.sendBoardItemsToBack(withIDs: selectedItemIDs) else {
            return false
        }
        syncInlineEditStateWithSelection()

        if let beforeSnapshot {
            _ = recordImmediateHistoryChange(
                from: beforeSnapshot,
                reason: selectionCount == 1
                    ? "send selection item to back"
                    : "send selection to back"
            )
        }

        return true
    }

    func scheduleAutosave(
        reason: String,
        updateKind: BoardPersistenceUpdateKind = .contentAndViewState
    ) {
        guard let snapshot = currentBoardSaveSnapshot(updateKind: updateKind) else {
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
        updateKind: BoardPersistenceUpdateKind = .contentAndViewState,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let snapshot = currentBoardSaveSnapshot(
            createBoardIfNeeded: createBoardIfNeeded,
            updateKind: updateKind
        ) else {
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
            let activeBoardCreatedAt,
            let activeBoardContentUpdatedAt,
            let activeBoardViewStateUpdatedAt
        else {
            return nil
        }

        return BoardRuntimeState(
            boardID: activeBoardID,
            title: activeBoardTitle,
            createdAt: activeBoardCreatedAt,
            contentUpdatedAt: activeBoardContentUpdatedAt,
            viewStateUpdatedAt: activeBoardViewStateUpdatedAt,
            items: scene.orderedBoardItems(),
            boardState: boardState,
            camera: camera,
            interactionState: interactionState,
            workspaceMode: workspaceMode
        )
    }

    func currentBoardSaveSnapshot(
        createBoardIfNeeded: Bool = false,
        updateKind: BoardPersistenceUpdateKind = .contentAndViewState
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
        let referencedHandDrawingItemIDs = Set(
            runtimeState.handDrawingItems.map(\.id)
        )
        let handDrawingPayloads = Dictionary(
            uniqueKeysWithValues: transientHandDrawingAssetPayloads.filter {
                referencedHandDrawingItemIDs.contains($0.key)
            }
        )
        return BoardSaveSnapshot(
            runtimeState: runtimeState,
            transientImageAssetPayloads: payloads,
            transientHandDrawingAssetPayloads: handDrawingPayloads,
            updateKind: updateKind
        )
    }

    private func preparedHandDrawingDuplicationDocumentData(
        for sourceItems: [CanvasBoardItem]
    ) -> [CanvasItemID: Data]? {
        var sourceDocumentDataByItemID: [CanvasItemID: Data] = [:]
        for sourceItem in sourceItems {
            guard let handDrawingItem = sourceItem.handDrawingItem else {
                continue
            }
            guard let documentData = resolvedHandDrawingDocumentData(
                for: handDrawingItem
            ) else {
                return nil
            }
            sourceDocumentDataByItemID[handDrawingItem.id] = documentData
        }
        return sourceDocumentDataByItemID
    }

    private func resolvedHandDrawingDocumentData(
        for item: CanvasHandDrawingItem
    ) -> Data? {
        if let payload = transientHandDrawingAssetPayload(for: item.id) {
            return payload.documentData
        }
        guard let activeBoardID else {
            return nil
        }
        return try? BoardStore.loadHandDrawingDocumentData(
            boardID: activeBoardID,
            documentID: item.documentID,
            userDefaults: userDefaults
        )
    }

    private func registerDuplicatedHandDrawingPayloads(
        sourceItems: [CanvasBoardItem],
        duplicatedItems: [CanvasBoardItem],
        sourceDocumentDataByItemID: [CanvasItemID: Data]
    ) {
        guard sourceItems.count == duplicatedItems.count else {
            return
        }
        for (sourceItem, duplicatedItem) in zip(sourceItems, duplicatedItems) {
            guard
                let sourceHandDrawingItem = sourceItem.handDrawingItem,
                let duplicatedHandDrawingItem = duplicatedItem.handDrawingItem,
                let documentData = sourceDocumentDataByItemID[sourceHandDrawingItem.id]
            else {
                continue
            }
            transientHandDrawingAssetPayloads[duplicatedHandDrawingItem.id] =
                BoardTransientHandDrawingAssetPayload(
                    itemID: duplicatedHandDrawingItem.id,
                    documentData: documentData,
                    previewCGImage: duplicatedHandDrawingItem.previewAsset.posterCGImage
                )
        }
    }

    @discardableResult
    func ensureActiveBoardIdentityIfNeeded() -> Bool {
        guard
            activeBoardID == nil ||
            activeBoardCreatedAt == nil ||
            activeBoardContentUpdatedAt == nil ||
            activeBoardViewStateUpdatedAt == nil
        else {
            return true
        }

        guard FolderBookmarkStore.hasStoredBookmarkData(
            userDefaults: userDefaults
        ) else {
            return false
        }

        let now = Date()
        activeBoardID = activeBoardID ?? UUID()
        activeBoardCreatedAt = activeBoardCreatedAt ?? now
        activeBoardContentUpdatedAt = activeBoardContentUpdatedAt ?? now
        activeBoardViewStateUpdatedAt = activeBoardViewStateUpdatedAt ?? now
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

    func measuredTextItemSize(
        for text: String,
        style: CanvasTextStyle
    ) -> CGSize {
        CanvasTextLayoutMeasurer.intrinsicItemSize(
            for: text,
            style: style
        )
    }

    @discardableResult
    func updateTextItemContent(
        withID itemID: CanvasItemID,
        text: String,
        style: CanvasTextStyle
    ) -> CanvasTextItem? {
        let size = measuredTextItemSize(
            for: text,
            style: style
        )
        return scene.updateTextItem(
            withID: itemID,
            text: text,
            style: style,
            size: size
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
        itemCount: Int
    ) -> CanvasImportLayout {
        switch layout {
        case .automatic:
            if itemCount <= 1 {
                return .stacked
            }

            return .staggered(stepInWorld: duplicateOffsetInWorld())
        case .stacked:
            return .stacked
        case let .staggered(stepInWorld):
            return .staggered(stepInWorld: stepInWorld)
        case let .grid(columns, horizontalSpacing, verticalSpacing):
            let gridConfiguration = CanvasImportGridConfiguration(
                columns: columns,
                horizontalSpacing: horizontalSpacing,
                verticalSpacing: verticalSpacing
            )
            return .grid(
                columns: gridConfiguration.columns,
                horizontalSpacing: gridConfiguration.horizontalSpacing,
                verticalSpacing: gridConfiguration.verticalSpacing
            )
        }
    }

    private func importOffset(
        forItemAt index: Int,
        layout: CanvasImportLayout,
        gridCellSize: CGSize? = nil
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
        case .grid:
            guard
                let gridConfiguration = layout.gridConfiguration,
                let gridCellSize
            else {
                return .zero
            }

            let columnIndex = index % gridConfiguration.columns
            let rowIndex = index / gridConfiguration.columns
            return CGPoint(
                x: CGFloat(columnIndex) * (
                    gridCellSize.width + gridConfiguration.horizontalSpacing
                ),
                y: CGFloat(rowIndex) * (
                    gridCellSize.height + gridConfiguration.verticalSpacing
                )
            )
        }
    }

    private func resolvedImportPresentationTemplate(
        _ presentationTemplate: CanvasImportPresentationTemplate?,
        defaultSize: CGSize
    ) -> CanvasImportPresentationTemplate {
        presentationTemplate ?? CanvasImportPresentationTemplate(
            size: defaultSize
        )
    }

    private func preparedImportItem(
        from item: CanvasImportItem,
        presentationTemplate: CanvasImportPresentationTemplate?
    ) -> CanvasPreparedImportItem {
        switch item {
        case let .image(image):
            let importRegistration = image.makeTransientImageAssetRegistration()
            let asset = importRegistration.asset
            let presentationTemplate = resolvedImportPresentationTemplate(
                presentationTemplate,
                defaultSize: normalizedDisplaySize(for: asset.logicalPixelSize)
            )
            return CanvasPreparedImportItem(
                asset: asset,
                transientPayload: importRegistration.payload,
                videoSource: nil,
                posterTimeSeconds: nil,
                size: presentationTemplate.size,
                cropRectNormalized: presentationTemplate.cropRectNormalized,
                rotationRadians: presentationTemplate.resolvedRotationRadians(
                    assetDefaultRadians: 0
                )
            )
        case let .video(video):
            let presentationTemplate = resolvedImportPresentationTemplate(
                presentationTemplate,
                defaultSize: normalizedDisplaySize(
                    for: video.asset.logicalPixelSize
                )
            )
            return CanvasPreparedImportItem(
                asset: video.asset,
                transientPayload: nil,
                videoSource: video.videoSource,
                posterTimeSeconds: video.posterTimeSeconds,
                size: presentationTemplate.size,
                cropRectNormalized: presentationTemplate.cropRectNormalized,
                rotationRadians: presentationTemplate.resolvedRotationRadians(
                    assetDefaultRadians: 0
                )
            )
        }
    }

    private func gridCellSize(
        for preparedItems: [CanvasPreparedImportItem],
        layout: CanvasImportLayout
    ) -> CGSize? {
        guard layout.gridConfiguration != nil else {
            return nil
        }

        let maxWidth = preparedItems.map(\.size.width).max() ?? 1
        let maxHeight = preparedItems.map(\.size.height).max() ?? 1
        return CGSize(
            width: max(maxWidth, 1),
            height: max(maxHeight, 1)
        )
    }

    private func importedMediaChangeReason(for itemCount: Int) -> String {
        guard itemCount > 1 else {
            return "append media item"
        }

        return "append \(itemCount) media items"
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
            size: measuredTextItemSize(
                for: text,
                style: style
            ),
            zIndex: nextBoardItemZIndex()
        )
        scene.append(item)
        _ = replaceSelection(
            with: [item.id],
            primarySelectedItemID: item.id
        )
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
    func addHandDrawingItem(
        paper: CanvasHandDrawingPaperSpec = .square
    ) -> CanvasHandDrawingItem? {
        guard canAddHandDrawingItem else {
            return nil
        }

        let beforeSnapshot = currentBoardHistorySnapshot()
        guard
            let emptyDocumentData = try? HandDrawingDocumentLoader
                .normalizeDocumentData(from: Data(), paper: paper),
            let previewImage = try? CanvasHandDrawingPreviewAssetFactory
                .makeTransparentPreview(for: paper)
        else {
            return nil
        }

        let itemID = CanvasItemID()
        let documentID = HandDrawingDocumentID()
        let item = CanvasHandDrawingItem(
            id: itemID,
            documentID: documentID,
            paper: paper,
            previewAsset: CanvasHandDrawingItem.persistedPreviewAsset(
                for: documentID,
                cgImage: previewImage,
                logicalPixelSize: paper.size
            ),
            isEmpty: true,
            center: camera.center,
            size: normalizedDisplaySize(for: paper.size),
            zIndex: nextBoardItemZIndex()
        )
        scene.append(item)
        transientHandDrawingAssetPayloads[item.id] =
            BoardTransientHandDrawingAssetPayload(
                itemID: item.id,
                documentData: emptyDocumentData,
                previewCGImage: previewImage
            )
        _ = replaceSelection(
            with: [item.id],
            primarySelectedItemID: item.id
        )
        expandBoardIfNeeded(toInclude: item.worldFrame)
        let changeReason = "add hand drawing item"
        _ = recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: changeReason,
            autosaveReason: changeReason
        )
        return item
    }

    private func canAdjustInlineTextFontSize(by delta: CGFloat) -> Bool {
        guard
            let item = activeInlineTextItem,
            delta != 0
        else {
            return false
        }

        return adjustedInlineTextStyle(
            from: item.style,
            fontSizeDelta: delta
        ) != item.style
    }

    @discardableResult
    private func adjustInlineTextFontSize(by delta: CGFloat) -> CanvasTextItem? {
        guard
            let inlineEditState,
            inlineEditState.mode == .text,
            let item = activeInlineTextItem
        else {
            return nil
        }

        let updatedStyle = adjustedInlineTextStyle(
            from: item.style,
            fontSizeDelta: delta
        )
        guard updatedStyle != item.style else {
            return nil
        }

        let beforeSnapshot = currentBoardHistorySnapshot()
        guard let updatedItem = updateTextItemContent(
            withID: item.id,
            text: inlineEditState.draftText,
            style: updatedStyle
        ) else {
            return nil
        }

        expandBoardIfNeeded(toInclude: updatedItem.worldBounds)
        let changeReason = delta < 0
            ? "decrease inline text font size"
            : "increase inline text font size"
        _ = recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: changeReason,
            autosaveReason: changeReason
        )
        return updatedItem
    }

    private func adjustedInlineTextStyle(
        from style: CanvasTextStyle,
        fontSizeDelta: CGFloat
    ) -> CanvasTextStyle {
        CanvasTextStyle(
            fontName: style.fontName,
            fontSize: style.fontSize + fontSizeDelta,
            color: style.color
        )
    }

    @discardableResult
    func appendImportedMedia(
        _ items: [CanvasImportItem],
        placement: CanvasImportPlacement = .cameraCenter,
        layout: CanvasImportLayout = .automatic,
        presentationTemplate: CanvasImportPresentationTemplate? = nil
    ) -> [CanvasImageItem] {
        guard items.isEmpty == false else {
            return []
        }

        let beforeSnapshot = currentBoardHistorySnapshot()
        let importCenter = resolvedImportCenter(for: placement)
        let resolvedLayout = resolvedImportLayout(
            layout,
            itemCount: items.count
        )
        let startingZIndex = nextImageZIndex()
        let preparedItems = items.map { item in
            preparedImportItem(
                from: item,
                presentationTemplate: presentationTemplate
            )
        }
        let resolvedGridCellSize = gridCellSize(
            for: preparedItems,
            layout: resolvedLayout
        )
        var importedItems: [CanvasImageItem] = []
        importedItems.reserveCapacity(items.count)

        for (index, preparedItem) in preparedItems.enumerated() {
            let offset = importOffset(
                forItemAt: index,
                layout: resolvedLayout,
                gridCellSize: resolvedGridCellSize
            )
            if let payload = preparedItem.transientPayload {
                transientImageAssetPayloads[payload.assetReference] = payload
            }

            let importedItem = CanvasImageItem(
                asset: preparedItem.asset,
                videoSource: preparedItem.videoSource,
                posterTimeSeconds: preparedItem.posterTimeSeconds,
                center: CGPoint(
                    x: importCenter.x + offset.x,
                    y: importCenter.y + offset.y
                ),
                size: preparedItem.size,
                zIndex: startingZIndex + CGFloat(index),
                cropRectNormalized: preparedItem.cropRectNormalized,
                rotationRadians: preparedItem.rotationRadians
            )

            scene.append(importedItem)
            expandBoardIfNeeded(toInclude: importedItem.worldBounds)
            importedItems.append(importedItem)
        }

        let changeReason = importedMediaChangeReason(
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
        let importedItems = appendImportedMedia(
            [.image(CanvasResolvedImportImage(cgImage: cgImage))],
            placement: placement,
            layout: .stacked
        )
        guard let item = importedItems.first else {
            preconditionFailure("Expected a single imported image result.")
        }

        return item
    }

    private func filteredExistingItemIDs(
        from itemIDs: [CanvasItemID]
    ) -> [CanvasItemID] {
        itemIDs.filter { itemID in
            scene.boardItem(withID: itemID) != nil
        }
    }

    private func normalizedSelectionStateForExistingItems(
        selectedItemIDs: [CanvasItemID],
        primarySelectedItemID: CanvasItemID?
    ) -> CanvasNormalizedSelectionState<CanvasItemID> {
        let existingSelectedItemIDs = filteredExistingItemIDs(from: selectedItemIDs)
        let existingPrimarySelectedItemID = primarySelectedItemID.flatMap { itemID in
            scene.boardItem(withID: itemID) != nil ? itemID : nil
        }
        return normalizeCanvasSelectionState(
            selectedItemIDs: existingSelectedItemIDs,
            primarySelectedItemID: existingPrimarySelectedItemID
        )
    }

    private func applySelectionState(
        _ selectionState: CanvasNormalizedSelectionState<CanvasItemID>
    ) {
        interactionState = CanvasInteractionState(
            selectedItemIDs: selectionState.selectedItemIDs,
            primarySelectedItemID: selectionState.primarySelectedItemID
        )
        syncInlineEditStateWithSelection()
    }
}

private func describeSelectionMutationItemID(_ itemID: CanvasItemID?) -> String {
    itemID?.uuidString ?? "nil"
}

private func describeSelectionMutationItemIDs(
    _ itemIDs: [CanvasItemID]
) -> String {
    guard itemIDs.isEmpty == false else {
        return "[]"
    }

    return "[" + itemIDs.map(\.uuidString).joined(separator: ",") + "]"
}

private func describeSelectionMutationState(
    _ state: CanvasInteractionState
) -> String {
    "selectedItemIDs=\(describeSelectionMutationItemIDs(state.selectedItemIDs)) " +
        "primarySelectedItemID=\(describeSelectionMutationItemID(state.primarySelectedItemID))"
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
