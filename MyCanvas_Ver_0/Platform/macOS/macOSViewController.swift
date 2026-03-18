//
//  macOSViewController.swift
//  MyCanvas_Ver_0
//
//  Created by Shaun on 2026/3/13.
//

#if os(macOS)
import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

final class macOSViewController: NSViewController {
    private enum PointerPressTarget {
        case rotateHandle(itemID: CanvasImageItemID)
        case cropHandle(role: CanvasCropHandleRole, itemID: CanvasImageItemID)
        case cropOutline(itemID: CanvasImageItemID)
        case handle(role: CanvasSelectionHandleRole, itemID: CanvasImageItemID)
        case selectedBody(itemID: CanvasImageItemID)
        case unselectedItem(itemID: CanvasImageItemID)
        case blank

        var itemID: CanvasImageItemID? {
            switch self {
            case let .rotateHandle(itemID), let .cropHandle(_, itemID), let .cropOutline(itemID), let .handle(_, itemID), let .selectedBody(itemID), let .unselectedItem(itemID):
                return itemID
            case .blank:
                return nil
            }
        }
    }

    private enum EditHandleHit {
        case rotate(itemID: CanvasImageItemID)
        case crop(role: CanvasCropHandleRole, itemID: CanvasImageItemID)
        case resize(role: CanvasSelectionHandleRole, itemID: CanvasImageItemID)

        var itemID: CanvasImageItemID {
            switch self {
            case let .rotate(itemID), let .crop(_, itemID), let .resize(_, itemID):
                return itemID
            }
        }

        var pressTarget: PointerPressTarget {
            switch self {
            case let .rotate(itemID):
                return .rotateHandle(itemID: itemID)
            case let .crop(role, itemID):
                return .cropHandle(role: role, itemID: itemID)
            case let .resize(role, itemID):
                return .handle(role: role, itemID: itemID)
            }
        }
    }

    private struct PointerResizeState {
        let itemID: CanvasImageItemID
        let handleRole: CanvasSelectionHandleRole
        let referenceCenter: CGPoint
        let referenceRotationRadians: CGFloat
        let initialLocalFrame: CGRect
        let fixedOppositeLocalCorner: CGPoint
        let minimumScale: CGFloat
    }

    private struct PointerCropState {
        let itemID: CanvasImageItemID
        let handleRole: CanvasCropHandleRole
        let fullImageLocalFrame: CGRect
        let initialLocalFrame: CGRect
        let minimumLocalSize: CGSize
    }

    private struct PointerCropTranslationState {
        let itemID: CanvasImageItemID
        let fullImageLocalFrame: CGRect
        let initialLocalFrame: CGRect
        let initialPointerLocalPoint: CGPoint
    }

    private struct PointerRotateState {
        let itemID: CanvasImageItemID
        let referenceCenter: CGPoint
        let rotationOffsetToPointerAngle: CGFloat
    }

    private enum PointerDragState {
        case idle
        case pressed(
            pressedLocation: CGPoint,
            pressTarget: PointerPressTarget
        )
        case croppingSelectedItem(PointerCropState)
        case movingCropFrame(PointerCropTranslationState)
        case rotatingSelectedItem(PointerRotateState)
        case draggingSelectedItem(itemID: CanvasImageItemID)
        case resizingSelectedItem(PointerResizeState)
        case draggingCanvas
    }

    private static let pointerDragActivationDistance: CGFloat = 4
    private static let selectionHandleHitTargetSize: CGFloat = 18
    private static let minimumResizeViewportDimension: CGFloat = 20
    private static let cropHandleHitTargetSize: CGFloat = 18
    private static let cropOutlineHitTargetWidth: CGFloat = 14
    private static let minimumCropViewportDimension: CGFloat = 20
    private static let rotateHandleHitTargetSize: CGFloat = 22

    private let miniMapLayoutSolver = CanvasOverlayLayoutSolver()
    var miniMapConfiguration = CanvasMiniMapConfiguration()
    private let editorSession = CanvasEditorSession(
        saveQueueLabel: "MyCanvas.BoardSave.macOS",
        logPrefix: "[BoardStore][macOS]"
    )
    private let commandCatalog = CanvasCommandCatalog()
    private let canvasHostView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.layer?.masksToBounds = true
        return view
    }()
    private let chromeOverlayView: macOSCanvasChromeOverlayView = {
        let view = macOSCanvasChromeOverlayView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let controlsStackView: macOSCanvasChromeStackView = {
        let stackView = macOSCanvasChromeStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .trailing
        stackView.distribution = .fill
        stackView.spacing = 12
        return stackView
    }()
    private let miniMapMountView: macOSCanvasChromeOverlayView = {
        let view = macOSCanvasChromeOverlayView()
        view.translatesAutoresizingMaskIntoConstraints = true
        view.isHidden = true
        return view
    }()
    private let miniMapView = macOSCanvasMiniMapView()
    private let importButton: NSButton = {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .texturedRounded
        button.isBordered = true
        if let image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Import image") {
            button.image = image
            button.imagePosition = .imageOnly
        } else {
            button.title = "+"
        }
        return button
    }()
    private let saveButton: NSButton = {
        let button = NSButton(title: "Save", target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.imagePosition = .imageLeading
        if let image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Save board") {
            button.image = image
        }
        return button
    }()
    private let cropButton: NSButton = {
        let button = NSButton(title: "Crop", target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.imagePosition = .imageLeading
        return button
    }()
    private let canvasViewportView = macOSCanvasViewportView()
    private var canvasContentView: NSView?
    private var pointerDragState: PointerDragState = .idle
    private var saveButtonResetWorkItem: DispatchWorkItem?
    private lazy var commandExecutor = CanvasCommandExecutor(
        session: editorSession
    )

    private var scene: CanvasScene {
        editorSession.scene
    }

    private var camera: CanvasCamera {
        get { editorSession.camera }
        set { editorSession.camera = newValue }
    }

    private var boardState: CanvasBoardState? {
        get { editorSession.boardState }
        set { editorSession.boardState = newValue }
    }

    private var interactionState: CanvasInteractionState {
        get { editorSession.interactionState }
        set { editorSession.interactionState = newValue }
    }

    private var inlineEditState: CanvasInlineEditState? {
        get { editorSession.inlineEditState }
        set { editorSession.inlineEditState = newValue }
    }

    private var rotationPreviewState: CanvasRotationPreviewState? {
        get { editorSession.rotationPreviewState }
        set { editorSession.rotationPreviewState = newValue }
    }

    private var rotationInteractionState: CanvasRotationInteractionState? {
        get { editorSession.rotationInteractionState }
        set { editorSession.rotationInteractionState = newValue }
    }

    private var lastRenderSnapshot: CanvasRenderSnapshot {
        editorSession.lastRenderSnapshot
    }

    private func commandDescriptor(
        for commandID: CanvasCommandID
    ) -> CanvasCommandDescriptor {
        commandCatalog.descriptor(
            for: commandID,
            session: editorSession
        )
    }

    private func performCommand(_ command: CanvasCommand) {
        guard commandExecutor.canExecute(command) else {
            return
        }

        if command.shouldCancelActiveRotation {
            cancelRotationInteractionIfNeeded(
                resetPointerDragState: command.shouldResetPointerDragStateWhenCancellingRotation
            )
        }

        guard let executionResult = commandExecutor.execute(command) else {
            return
        }

        updateInlineEditButtonsAppearance()

        if executionResult.refreshReason != nil {
            refreshCanvas()
        }
    }

    func canPerformCommand(_ commandID: CanvasCommandID) -> Bool {
        commandDescriptor(for: commandID).isEnabled
    }

    func performCommand(withID commandID: CanvasCommandID) {
        switch commandID {
        case .crop:
            performCommand(CanvasCommand.crop)
        case .undo:
            performCommand(CanvasCommand.undo)
        case .redo:
            performCommand(CanvasCommand.redo)
        case .selectItem, .clearSelection:
            break
        }
    }

    override func loadView() {
        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViewHierarchy()
        setupConstraints()
        setupImportButton()
        setupSaveButton()
        setupCropButton()
        setupMiniMapView()
        restorePersistedBoardIfPossible()
        setupCanvasViewport()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateCameraViewportSizeIfNeeded()
        updateChromeOverlayLayout()
    }

    // Future canvas viewport views should always be mounted through this host.
    func installCanvasContentView(_ contentView: NSView) {
        _ = view
        canvasContentView?.removeFromSuperview()

        contentView.translatesAutoresizingMaskIntoConstraints = false
        canvasHostView.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: canvasHostView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: canvasHostView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: canvasHostView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: canvasHostView.bottomAnchor)
        ])

        canvasContentView = contentView
    }

    private func setupViewHierarchy() {
        view.addSubview(canvasHostView)
        view.addSubview(chromeOverlayView)
        chromeOverlayView.addSubview(miniMapMountView)
        chromeOverlayView.addSubview(controlsStackView)
        controlsStackView.addArrangedSubview(cropButton)
        controlsStackView.addArrangedSubview(saveButton)
        controlsStackView.addArrangedSubview(importButton)
    }

    private func setupConstraints() {
        let safeAreaLayoutGuide = chromeOverlayView.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            canvasHostView.topAnchor.constraint(equalTo: view.topAnchor),
            canvasHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvasHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvasHostView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            chromeOverlayView.topAnchor.constraint(equalTo: view.topAnchor),
            chromeOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chromeOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chromeOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            controlsStackView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            controlsStackView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),
            importButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func updateChromeOverlayLayout() {
        let safeBounds = chromeSafeBounds()
        let occupiedRects = chromeOccupiedRects()
        let miniMapFrame = miniMapLayoutSolver.resolveMiniMapFrame(
            safeBounds: safeBounds,
            occupiedRects: occupiedRects,
            configuration: miniMapConfiguration
        )?.integral ?? .zero
        if miniMapMountView.frame != miniMapFrame {
            miniMapMountView.frame = miniMapFrame
        }
        miniMapMountView.isHidden = miniMapFrame.isEmpty
        if miniMapView.frame != miniMapMountView.bounds {
            miniMapView.frame = miniMapMountView.bounds
        }
    }

    private func chromeSafeBounds() -> CGRect {
        let safeAreaInsets = view.safeAreaInsets
        return CGRect(
            x: view.bounds.minX + safeAreaInsets.left,
            y: view.bounds.minY + safeAreaInsets.top,
            width: max(view.bounds.width - safeAreaInsets.left - safeAreaInsets.right, 0),
            height: max(view.bounds.height - safeAreaInsets.top - safeAreaInsets.bottom, 0)
        ).standardized
    }

    private func chromeOccupiedRects() -> [CGRect] {
        guard
            controlsStackView.bounds.width > 0,
            controlsStackView.bounds.height > 0
        else {
            return []
        }

        return [controlsStackView.frame.standardized]
    }

    private func setupImportButton() {
        importButton.target = self
        importButton.action = #selector(handleImportButtonClick)
    }

    private func setupSaveButton() {
        saveButton.target = self
        saveButton.action = #selector(handleSaveButtonClick)
    }

    private func setupCropButton() {
        cropButton.target = self
        cropButton.action = #selector(handleCropButtonClick)
        updateInlineEditButtonsAppearance()
    }

    private func setupMiniMapView() {
        miniMapView.frame = miniMapMountView.bounds
        miniMapView.autoresizingMask = [.width, .height]
        miniMapView.onNavigate = { [weak self] point in
            self?.handleMiniMapNavigate(to: point)
        }
        miniMapMountView.addSubview(miniMapView)
    }

    private func setupCanvasViewport() {
        canvasViewportView.onPointerDown = { [weak self] location in
            self?.handlePrimaryPointerDown(at: location)
        }
        canvasViewportView.onPointerMove = { [weak self] location, previousLocation in
            self?.handlePrimaryPointerMove(to: location, from: previousLocation)
        }
        canvasViewportView.onPointerUp = { [weak self] location in
            self?.handlePrimaryPointerUp(at: location)
        }
        canvasViewportView.onPointerCancel = { [weak self] in
            self?.handlePrimaryPointerCancel()
        }
        canvasViewportView.onPan = { [weak self] translation in
            self?.handleIndirectPan(translation)
        }
        canvasViewportView.onZoom = { [weak self] scaleDelta, anchor in
            self?.handleZoom(scaleDelta, around: anchor)
        }

        installCanvasContentView(canvasViewportView)
        refreshCanvas()
    }

    private func updateCameraViewportSizeIfNeeded() {
        let viewportSize = canvasViewportView.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            return
        }

        let sizeChanged = viewportSize != camera.viewportSize
        if sizeChanged {
            camera.setViewportSize(viewportSize)
        }

        let didConfigureBoardState = configureBoardStateIfNeeded(for: viewportSize)
        guard sizeChanged || didConfigureBoardState else {
            return
        }

        refreshCanvas()

        if didConfigureBoardState {
            scheduleAutosave(reason: "configure board state")
        }
    }

    private func handlePrimaryPointerDown(at location: CGPoint) {
        let pressTarget = pointerPressTarget(at: location)
        pointerDragState = .pressed(
            pressedLocation: location,
            pressTarget: pressTarget
        )
        beginPointerHistoryTransactionIfNeeded(for: pressTarget)
    }

    private func handlePrimaryPointerMove(to location: CGPoint, from previousLocation: CGPoint) {
        switch pointerDragState {
        case let .pressed(pressedLocation, pressTarget):
            guard hasExceededPointerDragActivationDistance(from: pressedLocation, to: location) else {
                return
            }

            switch pressTarget {
            case let .rotateHandle(itemID):
                guard let rotateState = makePointerRotateState(
                    itemID: itemID,
                    initialViewportLocation: pressedLocation
                ) else {
                    editorSession.cancelPendingHistoryTransaction()
                    pointerDragState = .idle
                    return
                }

                pointerDragState = .rotatingSelectedItem(rotateState)
                beginRotationInteraction(for: itemID)
                updateRotationDraft(using: rotateState, to: location)
            case let .cropHandle(handleRole, itemID):
                guard let cropState = makePointerCropState(itemID: itemID, handleRole: handleRole) else {
                    editorSession.cancelPendingHistoryTransaction()
                    pointerDragState = .idle
                    return
                }

                pointerDragState = .croppingSelectedItem(cropState)
                updateCropDraft(using: cropState, to: location)
            case let .cropOutline(itemID):
                guard let translationState = makePointerCropTranslationState(
                    itemID: itemID,
                    initialViewportLocation: pressedLocation
                ) else {
                    editorSession.cancelPendingHistoryTransaction()
                    pointerDragState = .idle
                    return
                }

                pointerDragState = .movingCropFrame(translationState)
                updateTranslatedCropDraft(using: translationState, to: location)
            case let .handle(handleRole, itemID):
                guard let resizeState = makePointerResizeState(itemID: itemID, handleRole: handleRole) else {
                    pointerDragState = .idle
                    return
                }

                pointerDragState = .resizingSelectedItem(resizeState)
                resizeSelectedItem(using: resizeState, to: location)
            case let .selectedBody(itemID):
                pointerDragState = .draggingSelectedItem(itemID: itemID)
                moveSelectedItem(withID: itemID, from: pressedLocation, to: location)
            case .unselectedItem, .blank:
                pointerDragState = .draggingCanvas
                panCanvas(from: pressedLocation, to: location)
            }
        case let .croppingSelectedItem(cropState):
            updateCropDraft(using: cropState, to: location)
        case let .movingCropFrame(translationState):
            updateTranslatedCropDraft(using: translationState, to: location)
        case let .rotatingSelectedItem(rotateState):
            updateRotationDraft(using: rotateState, to: location)
        case let .draggingSelectedItem(itemID):
            moveSelectedItem(withID: itemID, from: previousLocation, to: location)
        case let .resizingSelectedItem(resizeState):
            resizeSelectedItem(using: resizeState, to: location)
        case .draggingCanvas:
            panCanvas(from: previousLocation, to: location)
        case .idle:
            break
        }
    }

    private func handlePrimaryPointerUp(at location: CGPoint) {
        defer {
            pointerDragState = .idle
        }

        switch pointerDragState {
        case let .pressed(_, pressTarget):
            if isInlineEditModeActive {
                editorSession.cancelPendingHistoryTransaction()
                return
            }

            let pressedItemID = pressTarget.itemID
            let releasedHandleHit = hitTestEditHandle(at: location)
            let releasedItemID = hitTestItemID(at: location) ?? releasedHandleHit?.itemID
            let previousSelectedItemID = interactionState.selectedItemID
            var clickTarget = "blank"
            var clickResult = "selection_unchanged"
            var affectedItemID: CanvasImageItemID?

            switch pressTarget {
            case let .rotateHandle(itemID):
                clickTarget = "rotate_handle"
                affectedItemID = itemID
            case let .cropHandle(_, itemID):
                clickTarget = "crop_handle"
                affectedItemID = itemID
            case let .cropOutline(itemID):
                clickTarget = "crop_outline"
                affectedItemID = itemID
            case let .handle(_, itemID):
                clickTarget = "handle"
                affectedItemID = itemID
            case let .selectedBody(itemID), let .unselectedItem(itemID):
                if releasedItemID == itemID {
                    clickTarget = "image"
                    affectedItemID = itemID
                    selectItem(
                        withID: itemID,
                        recordHistory: true
                    )
                    if previousSelectedItemID != itemID {
                        clickResult = "image_selected"
                    }
                } else {
                    clickTarget = "mismatched_hit_test"
                    affectedItemID = releasedItemID ?? itemID
                }
            case .blank:
                if releasedItemID == nil {
                    affectedItemID = previousSelectedItemID
                    clearSelectionIfNeeded(recordHistory: true)
                    if previousSelectedItemID != nil {
                        clickResult = "image_deselected"
                    }
                } else {
                    clickTarget = "mismatched_hit_test"
                    affectedItemID = releasedItemID
                }
            }

            logClickResult(
                target: clickTarget,
                result: clickResult,
                pressedItemID: pressedItemID,
                releasedItemID: releasedItemID,
                previousSelectedItemID: previousSelectedItemID,
                currentSelectedItemID: interactionState.selectedItemID,
                affectedItemID: affectedItemID
            )
            editorSession.cancelPendingHistoryTransaction()
        case .rotatingSelectedItem:
            commitRotationDraftIfNeeded()
        case .croppingSelectedItem, .movingCropFrame:
            commitCropDraftIfNeeded()
        case .draggingSelectedItem:
            commitPendingPointerHistoryTransaction(autosaveReason: "move item")
        case .resizingSelectedItem:
            commitPendingPointerHistoryTransaction(autosaveReason: "resize item")
        case .draggingCanvas, .idle:
            break
        }
    }

    private func handlePrimaryPointerCancel() {
        switch pointerDragState {
        case .rotatingSelectedItem:
            cancelRotationInteractionIfNeeded(
                refreshAfterCancellation: true
            )
        case .croppingSelectedItem, .movingCropFrame:
            commitCropDraftIfNeeded()
        case .draggingSelectedItem:
            commitPendingPointerHistoryTransaction(autosaveReason: "move item")
        case .resizingSelectedItem:
            commitPendingPointerHistoryTransaction(autosaveReason: "resize item")
        case .pressed, .draggingCanvas, .idle:
            editorSession.cancelPendingHistoryTransaction()
        }

        pointerDragState = .idle
    }

    private func hasExceededPointerDragActivationDistance(
        from pressedLocation: CGPoint,
        to currentLocation: CGPoint
    ) -> Bool {
        let dx = currentLocation.x - pressedLocation.x
        let dy = currentLocation.y - pressedLocation.y
        let distanceSquared = (dx * dx) + (dy * dy)
        let thresholdSquared = Self.pointerDragActivationDistance * Self.pointerDragActivationDistance
        return distanceSquared >= thresholdSquared
    }

    private func handleIndirectPan(_ translation: CGPoint) {
        camera.pan(by: translation)
        refreshCanvas()
        scheduleAutosave(reason: "pan canvas")
    }

    private func handleZoom(_ scaleDelta: CGFloat, around anchor: CGPoint) {
        camera.zoom(by: scaleDelta, around: anchor)
        refreshCanvas()
        scheduleAutosave(reason: "zoom canvas")
    }

    private func refreshCanvas() {
        let snapshot = editorSession.makeCanvasSnapshot()
        canvasViewportView.apply(snapshot)
        refreshMiniMap()
    }

    private func refreshMiniMap() {
        let snapshot = editorSession.makeMiniMapSnapshot()
        miniMapView.apply(snapshot)
    }

    private func handleMiniMapNavigate(to miniMapPoint: CGPoint) {
        guard let worldPoint = miniMapView.worldPoint(atMiniMapPoint: miniMapPoint) else {
            return
        }

        guard camera.center != worldPoint else {
            return
        }

        camera.center = worldPoint
        refreshCanvas()
        scheduleAutosave(reason: "navigate canvas via minimap")
    }

    @objc
    private func handleImportButtonClick() {
        guard let window = view.window else {
            return
        }

        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.image]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true

        openPanel.beginSheetModal(for: window) { [weak self] response in
            guard
                response == .OK,
                let url = openPanel.url,
                let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
            else {
                return
            }

            self?.appendImportedImage(cgImage)
        }
    }

    @objc
    private func handleSaveButtonClick() {
        beginSaveButtonSaveState()
        saveBoardNow(
            reason: "manual save",
            createBoardIfNeeded: true
        ) { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success:
                self.showSaveButtonFeedback(
                    title: "Saved",
                    systemImageName: "checkmark",
                    tintColor: .systemGreen
                )
            case let .failure(error):
                if case FolderBookmarkStoreError.missingBookmarkData = error {
                    self.showSaveButtonFeedback(
                        title: "No Folder",
                        systemImageName: "exclamationmark.triangle",
                        tintColor: .systemOrange
                    )
                    self.presentSaveError(
                        message: "Select a folder from the board list before saving."
                    )
                } else {
                    self.showSaveButtonFeedback(
                        title: "Failed",
                        systemImageName: "xmark",
                        tintColor: .systemRed
                    )
                    self.presentSaveError(message: error.localizedDescription)
                }
            }
        }
    }

    @objc
    private func handleCropButtonClick() {
        performCommand(CanvasCommand.crop)
    }

    private func appendImportedImage(_ cgImage: CGImage) {
        _ = editorSession.appendImportedImage(cgImage)
        refreshCanvas()
    }

    private func selectItem(
        withID itemID: CanvasImageItemID,
        recordHistory: Bool = false
    ) {
        performCommand(
            .selectItem(
                itemID: itemID,
                recordHistory: recordHistory
            )
        )
    }

    private func clearSelectionIfNeeded(recordHistory: Bool = false) {
        performCommand(.clearSelection(recordHistory: recordHistory))
    }

    private func logClickResult(
        target: String,
        result: String,
        pressedItemID: CanvasImageItemID?,
        releasedItemID: CanvasImageItemID?,
        previousSelectedItemID: CanvasImageItemID?,
        currentSelectedItemID: CanvasImageItemID?,
        affectedItemID: CanvasImageItemID?
    ) {
        print(
            "[Canvas macOS][ClickSelection] " +
            "target=\(target) " +
            "result=\(result) " +
            "pressedItemID=\(describe(itemID: pressedItemID)) " +
            "releasedItemID=\(describe(itemID: releasedItemID)) " +
            "previousSelectedItemID=\(describe(itemID: previousSelectedItemID)) " +
            "currentSelectedItemID=\(describe(itemID: currentSelectedItemID)) " +
            "affectedItemID=\(describe(itemID: affectedItemID))"
        )
    }

    private func hitTestItemID(at viewportLocation: CGPoint) -> CanvasImageItemID? {
        scene.topmostItemID(
            containing: camera.viewportToWorld(viewportLocation)
        )
    }

    private func hitTestEditHandle(at viewportLocation: CGPoint) -> EditHandleHit? {
        guard let editOverlay = lastRenderSnapshot.editOverlay else {
            return nil
        }

        switch editOverlay.kind {
        case .crop:
            guard
                let handle = editOverlay.handles.first(where: { handle in
                    Self.cropHandleHitRect(centeredAt: handle.screenCenter)
                        .contains(viewportLocation)
                }),
                let role = handle.role.cropHandleRole
            else {
                return nil
            }

            return .crop(role: role, itemID: editOverlay.itemID)
        case .selection:
            guard
                case let .selection(payload) = editOverlay.payload
            else {
                return nil
            }

            if Self.rotateHandleHitRect(centeredAt: payload.rotateAffordance.handle.screenCenter)
                .contains(viewportLocation)
            {
                return .rotate(itemID: editOverlay.itemID)
            }

            guard
                let handle = editOverlay.handles.first(where: { handle in
                    Self.selectionHandleHitRect(centeredAt: handle.screenCenter)
                        .contains(viewportLocation)
                }),
                let role = handle.role.selectionHandleRole
            else {
                return nil
            }

            return .resize(role: role, itemID: editOverlay.itemID)
        }
    }

    private func hitTestCropOutline(at viewportLocation: CGPoint) -> CanvasImageItemID? {
        guard
            let editOverlay = lastRenderSnapshot.editOverlay,
            case let .crop(payload) = editOverlay.payload
        else {
            return nil
        }

        for (start, end) in Self.quadEdges(for: payload.cropScreenQuad) {
            if Self.distance(
                from: viewportLocation,
                toSegmentStart: start,
                segmentEnd: end
            ) <= (Self.cropOutlineHitTargetWidth / 2) {
                return editOverlay.itemID
            }
        }

        return nil
    }

    // Keep interaction priority aligned with common editors: resize handles win
    // over body hits so a visible handle is always the first-class press target.
    private func pointerPressTarget(at viewportLocation: CGPoint) -> PointerPressTarget {
        if let editHandleHit = hitTestEditHandle(at: viewportLocation) {
            return editHandleHit.pressTarget
        }

        if let cropOutlineItemID = hitTestCropOutline(at: viewportLocation) {
            return .cropOutline(itemID: cropOutlineItemID)
        }

        if isInlineEditModeActive {
            return .blank
        }

        guard let itemID = hitTestItemID(at: viewportLocation) else {
            return .blank
        }

        if itemID == interactionState.selectedItemID {
            return .selectedBody(itemID: itemID)
        }

        return .unselectedItem(itemID: itemID)
    }

    private func makePointerRotateState(
        itemID: CanvasImageItemID,
        initialViewportLocation: CGPoint
    ) -> PointerRotateState? {
        guard
            inlineEditState == nil,
            let item = scene.item(withID: itemID)
        else {
            return nil
        }

        let initialPointerAngle = angle(
            from: item.center,
            to: camera.viewportToWorld(initialViewportLocation)
        )

        return PointerRotateState(
            itemID: itemID,
            referenceCenter: item.center,
            rotationOffsetToPointerAngle: normalizedCanvasAngle(
                displayedRotationRadians(for: item) - initialPointerAngle
            )
        )
    }

    private func makePointerCropState(
        itemID: CanvasImageItemID,
        handleRole: CanvasCropHandleRole
    ) -> PointerCropState? {
        guard
            let item = scene.item(withID: itemID),
            let inlineEditState,
            inlineEditState.mode == .crop,
            inlineEditState.itemID == itemID
        else {
            return nil
        }

        let fullImageLocalFrame = item.fullImageLocalFrame.standardized
        let draftLocalFrame = item.localFrame(
            forNormalizedCropRect: inlineEditState.draftCropRectNormalized
        ).standardized
        let minimumLocalDimension = Self.minimumCropViewportDimension / camera.zoomScale

        return PointerCropState(
            itemID: itemID,
            handleRole: handleRole,
            fullImageLocalFrame: fullImageLocalFrame,
            initialLocalFrame: draftLocalFrame,
            minimumLocalSize: CGSize(
                width: min(minimumLocalDimension, fullImageLocalFrame.width),
                height: min(minimumLocalDimension, fullImageLocalFrame.height)
            )
        )
    }

    private func updateCropDraft(
        using cropState: PointerCropState,
        to viewportLocation: CGPoint
    ) {
        guard
            var inlineEditState,
            inlineEditState.mode == .crop,
            inlineEditState.itemID == cropState.itemID,
            let item = scene.item(withID: cropState.itemID)
        else {
            return
        }

        let draggedWorldPoint = camera.viewportToWorld(viewportLocation)
        let draggedLocalPoint = item.localPoint(fromWorld: draggedWorldPoint)
        let cropLocalFrame = constrainedCropLocalFrame(
            draggedLocalPoint,
            for: cropState.handleRole,
            initialLocalFrame: cropState.initialLocalFrame,
            fullImageLocalFrame: cropState.fullImageLocalFrame,
            minimumLocalSize: cropState.minimumLocalSize
        )
        let draftCropRectNormalized = item.normalizedCropRect(fromLocalFrame: cropLocalFrame)
        guard inlineEditState.draftCropRectNormalized != draftCropRectNormalized else {
            return
        }

        inlineEditState.draftCropRectNormalized = draftCropRectNormalized
        self.inlineEditState = inlineEditState
        refreshCanvas()
    }

    private func makePointerCropTranslationState(
        itemID: CanvasImageItemID,
        initialViewportLocation: CGPoint
    ) -> PointerCropTranslationState? {
        guard
            let item = scene.item(withID: itemID),
            let inlineEditState,
            inlineEditState.mode == .crop,
            inlineEditState.itemID == itemID
        else {
            return nil
        }

        return PointerCropTranslationState(
            itemID: itemID,
            fullImageLocalFrame: item.fullImageLocalFrame.standardized,
            initialLocalFrame: item.localFrame(
                forNormalizedCropRect: inlineEditState.draftCropRectNormalized
            ).standardized,
            initialPointerLocalPoint: item.localPoint(
                fromWorld: camera.viewportToWorld(initialViewportLocation)
            )
        )
    }

    private func updateTranslatedCropDraft(
        using translationState: PointerCropTranslationState,
        to viewportLocation: CGPoint
    ) {
        guard
            var inlineEditState,
            inlineEditState.mode == .crop,
            inlineEditState.itemID == translationState.itemID,
            let item = scene.item(withID: translationState.itemID)
        else {
            return
        }

        let draggedLocalPoint = item.localPoint(
            fromWorld: camera.viewportToWorld(viewportLocation)
        )
        let translatedLocalFrame = translatedCropLocalFrame(
            draggedLocalPoint,
            using: translationState
        )
        let draftCropRectNormalized = item.normalizedCropRect(
            fromLocalFrame: translatedLocalFrame
        )
        guard inlineEditState.draftCropRectNormalized != draftCropRectNormalized else {
            return
        }

        inlineEditState.draftCropRectNormalized = draftCropRectNormalized
        self.inlineEditState = inlineEditState
        refreshCanvas()
    }

    private func commitCropDraftIfNeeded() {
        guard
            let inlineEditState,
            inlineEditState.mode == .crop,
            let item = scene.item(withID: inlineEditState.itemID)
        else {
            editorSession.cancelPendingHistoryTransaction()
            return
        }

        guard item.cropRectNormalized != inlineEditState.draftCropRectNormalized else {
            editorSession.cancelPendingHistoryTransaction()
            return
        }

        guard let croppedItem = scene.cropItem(
            withID: inlineEditState.itemID,
            toNormalizedCropRect: inlineEditState.draftCropRectNormalized
        ) else {
            editorSession.cancelPendingHistoryTransaction()
            return
        }

        expandBoardIfNeeded(toInclude: croppedItem.worldBounds)
        self.inlineEditState = CanvasInlineEditState(item: croppedItem, mode: .crop)
        refreshCanvas()
        commitPendingPointerHistoryTransaction(autosaveReason: "crop item")
    }

    private func updateRotationDraft(
        using rotateState: PointerRotateState,
        to viewportLocation: CGPoint
    ) {
        guard
            inlineEditState == nil,
            interactionState.selectedItemID == rotateState.itemID,
            rotationInteractionState?.itemID == rotateState.itemID,
            let item = scene.item(withID: rotateState.itemID)
        else {
            return
        }

        let pointerAngle = angle(
            from: rotateState.referenceCenter,
            to: camera.viewportToWorld(viewportLocation)
        )
        let draftRotationRadians = normalizedCanvasAngle(
            pointerAngle + rotateState.rotationOffsetToPointerAngle
        )
        guard !anglesMatch(
            displayedRotationRadians(for: item),
            draftRotationRadians
        ) else {
            return
        }

        rotationPreviewState = CanvasRotationPreviewState(
            itemID: rotateState.itemID,
            draftRotationRadians: draftRotationRadians
        )
        refreshCanvas()
    }

    private func commitRotationDraftIfNeeded() {
        guard
            let rotationPreviewState,
            let item = scene.item(withID: rotationPreviewState.itemID)
        else {
            cancelRotationInteractionIfNeeded(
                refreshAfterCancellation: true
            )
            return
        }

        guard !anglesMatch(item.rotationRadians, rotationPreviewState.draftRotationRadians) else {
            cancelRotationInteractionIfNeeded(
                refreshAfterCancellation: true
            )
            return
        }

        guard let rotatedItem = scene.rotateItem(
            withID: rotationPreviewState.itemID,
            to: rotationPreviewState.draftRotationRadians
        ) else {
            cancelRotationInteractionIfNeeded(
                refreshAfterCancellation: true
            )
            return
        }

        expandBoardIfNeeded(toInclude: rotatedItem.worldBounds)
        clearRotationTransientState()
        refreshCanvas()
        commitPendingPointerHistoryTransaction(autosaveReason: "rotate item")
    }

    private func displayedRotationRadians(for item: CanvasImageItem) -> CGFloat {
        guard
            let rotationPreviewState,
            rotationPreviewState.itemID == item.id
        else {
            return item.rotationRadians
        }

        return rotationPreviewState.draftRotationRadians
    }

    private func clearRotationTransientState() {
        clearRotationPreviewState()
        clearRotationInteractionState()
    }

    private func clearRotationPreviewState() {
        rotationPreviewState = nil
    }

    private func beginRotationInteraction(for itemID: CanvasImageItemID) {
        guard rotationInteractionState?.itemID != itemID else {
            return
        }

        rotationInteractionState = CanvasRotationInteractionState(itemID: itemID)
        refreshCanvas()
    }

    private func clearRotationInteractionState() {
        rotationInteractionState = nil
    }

    private func cancelRotationInteractionIfNeeded(
        resetPointerDragState: Bool = false,
        refreshAfterCancellation: Bool = false
    ) {
        let hadVisibleRotationState =
            rotationPreviewState != nil || rotationInteractionState != nil
        let wasRotating: Bool
        switch pointerDragState {
        case .rotatingSelectedItem:
            wasRotating = true
        default:
            wasRotating = false
        }

        guard hadVisibleRotationState || wasRotating else {
            return
        }

        clearRotationTransientState()
        editorSession.cancelPendingHistoryTransaction()

        if resetPointerDragState, wasRotating {
            pointerDragState = .idle
        }

        if hadVisibleRotationState, refreshAfterCancellation {
            refreshCanvas()
        }
    }

    private func moveSelectedItem(
        withID itemID: CanvasImageItemID,
        from previousLocation: CGPoint,
        to location: CGPoint
    ) {
        let previousWorldLocation = camera.viewportToWorld(previousLocation)
        let currentWorldLocation = camera.viewportToWorld(location)
        let deltaInWorld = CGPoint(
            x: currentWorldLocation.x - previousWorldLocation.x,
            y: currentWorldLocation.y - previousWorldLocation.y
        )
        guard deltaInWorld != .zero else {
            return
        }

        scene.moveItem(withID: itemID, by: deltaInWorld)
        if let movedItem = scene.item(withID: itemID) {
            expandBoardIfNeeded(toInclude: movedItem.worldBounds)
        }
        refreshCanvas()
    }

    private func makePointerResizeState(
        itemID: CanvasImageItemID,
        handleRole: CanvasSelectionHandleRole
    ) -> PointerResizeState? {
        guard let item = scene.item(withID: itemID) else {
            return nil
        }

        let initialLocalFrame = item.localFrame.standardized
        guard initialLocalFrame.width > 0, initialLocalFrame.height > 0 else {
            return nil
        }

        let minimumWorldDimension = Self.minimumResizeViewportDimension / camera.zoomScale
        let minimumScale = max(
            minimumWorldDimension / initialLocalFrame.width,
            minimumWorldDimension / initialLocalFrame.height
        )

        return PointerResizeState(
            itemID: itemID,
            handleRole: handleRole,
            referenceCenter: item.center,
            referenceRotationRadians: item.rotationRadians,
            initialLocalFrame: initialLocalFrame,
            fixedOppositeLocalCorner: fixedOppositeResizeLocalCorner(
                for: handleRole,
                in: initialLocalFrame
            ),
            minimumScale: minimumScale
        )
    }

    // Controllers solve drag geometry, but Scene still performs the write so
    // move/resize mutations follow one shared data path across platforms.
    private func resizeSelectedItem(
        using resizeState: PointerResizeState,
        to viewportLocation: CGPoint
    ) {
        guard
            let resizedLocalFrame = makeResizedLocalFrame(
                using: resizeState,
                draggedViewportLocation: viewportLocation
            ),
            let currentItem = scene.item(withID: resizeState.itemID)
        else {
            return
        }

        let resizedCenter = referenceWorldPoint(
            fromLocal: CGPoint(
                x: resizedLocalFrame.midX,
                y: resizedLocalFrame.midY
            ),
            center: resizeState.referenceCenter,
            rotationRadians: resizeState.referenceRotationRadians
        )
        guard
            currentItem.center != resizedCenter ||
            currentItem.size != resizedLocalFrame.size
        else {
            return
        }

        guard let resizedItem = scene.resizeItem(
            withID: resizeState.itemID,
            toCenter: resizedCenter,
            size: resizedLocalFrame.size
        ) else {
            return
        }

        expandBoardIfNeeded(toInclude: resizedItem.worldBounds)
        refreshCanvas()
    }

    // Keep the opposite corner fixed and use the larger axis scale so resizing
    // stays proportional regardless of drag direction.
    private func makeResizedLocalFrame(
        using resizeState: PointerResizeState,
        draggedViewportLocation: CGPoint
    ) -> CGRect? {
        let minimumWidth = resizeState.initialLocalFrame.width * resizeState.minimumScale
        let minimumHeight = resizeState.initialLocalFrame.height * resizeState.minimumScale
        let draggedLocalCorner = constrainedDraggedResizeLocalCorner(
            referenceLocalPoint(
                fromWorld: camera.viewportToWorld(draggedViewportLocation),
                center: resizeState.referenceCenter,
                rotationRadians: resizeState.referenceRotationRadians
            ),
            for: resizeState.handleRole,
            oppositeCorner: resizeState.fixedOppositeLocalCorner,
            minimumWidth: minimumWidth,
            minimumHeight: minimumHeight
        )

        let widthScale = abs(draggedLocalCorner.x - resizeState.fixedOppositeLocalCorner.x) / resizeState.initialLocalFrame.width
        let heightScale = abs(draggedLocalCorner.y - resizeState.fixedOppositeLocalCorner.y) / resizeState.initialLocalFrame.height
        let scale = max(widthScale, heightScale, resizeState.minimumScale)
        guard scale.isFinite else {
            return nil
        }

        let resizedSize = CGSize(
            width: resizeState.initialLocalFrame.width * scale,
            height: resizeState.initialLocalFrame.height * scale
        )

        return localFrame(
            for: resizeState.handleRole,
            withFixedOppositeCorner: resizeState.fixedOppositeLocalCorner,
            size: resizedSize
        )
    }

    private func fixedOppositeResizeLocalCorner(
        for handleRole: CanvasSelectionHandleRole,
        in localFrame: CGRect
    ) -> CGPoint {
        switch handleRole {
        case .topLeading:
            return CGPoint(x: localFrame.maxX, y: localFrame.maxY)
        case .topTrailing:
            return CGPoint(x: localFrame.minX, y: localFrame.maxY)
        case .bottomLeading:
            return CGPoint(x: localFrame.maxX, y: localFrame.minY)
        case .bottomTrailing:
            return CGPoint(x: localFrame.minX, y: localFrame.minY)
        }
    }

    private func constrainedDraggedResizeLocalCorner(
        _ draggedLocalCorner: CGPoint,
        for handleRole: CanvasSelectionHandleRole,
        oppositeCorner: CGPoint,
        minimumWidth: CGFloat,
        minimumHeight: CGFloat
    ) -> CGPoint {
        switch handleRole {
        case .topLeading:
            return CGPoint(
                x: min(draggedLocalCorner.x, oppositeCorner.x - minimumWidth),
                y: min(draggedLocalCorner.y, oppositeCorner.y - minimumHeight)
            )
        case .topTrailing:
            return CGPoint(
                x: max(draggedLocalCorner.x, oppositeCorner.x + minimumWidth),
                y: min(draggedLocalCorner.y, oppositeCorner.y - minimumHeight)
            )
        case .bottomLeading:
            return CGPoint(
                x: min(draggedLocalCorner.x, oppositeCorner.x - minimumWidth),
                y: max(draggedLocalCorner.y, oppositeCorner.y + minimumHeight)
            )
        case .bottomTrailing:
            return CGPoint(
                x: max(draggedLocalCorner.x, oppositeCorner.x + minimumWidth),
                y: max(draggedLocalCorner.y, oppositeCorner.y + minimumHeight)
            )
        }
    }

    private func localFrame(
        for handleRole: CanvasSelectionHandleRole,
        withFixedOppositeCorner oppositeCorner: CGPoint,
        size: CGSize
    ) -> CGRect {
        switch handleRole {
        case .topLeading:
            return CGRect(
                x: oppositeCorner.x - size.width,
                y: oppositeCorner.y - size.height,
                width: size.width,
                height: size.height
            )
        case .topTrailing:
            return CGRect(
                x: oppositeCorner.x,
                y: oppositeCorner.y - size.height,
                width: size.width,
                height: size.height
            )
        case .bottomLeading:
            return CGRect(
                x: oppositeCorner.x - size.width,
                y: oppositeCorner.y,
                width: size.width,
                height: size.height
            )
        case .bottomTrailing:
            return CGRect(
                x: oppositeCorner.x,
                y: oppositeCorner.y,
                width: size.width,
                height: size.height
            )
        }
    }

    private static func selectionHandleHitRect(centeredAt center: CGPoint) -> CGRect {
        CGRect(
            x: center.x - selectionHandleHitTargetSize / 2,
            y: center.y - selectionHandleHitTargetSize / 2,
            width: selectionHandleHitTargetSize,
            height: selectionHandleHitTargetSize
        ).standardized
    }

    private static func cropHandleHitRect(centeredAt center: CGPoint) -> CGRect {
        CGRect(
            x: center.x - cropHandleHitTargetSize / 2,
            y: center.y - cropHandleHitTargetSize / 2,
            width: cropHandleHitTargetSize,
            height: cropHandleHitTargetSize
        ).standardized
    }

    private static func rotateHandleHitRect(centeredAt center: CGPoint) -> CGRect {
        CGRect(
            x: center.x - rotateHandleHitTargetSize / 2,
            y: center.y - rotateHandleHitTargetSize / 2,
            width: rotateHandleHitTargetSize,
            height: rotateHandleHitTargetSize
        ).standardized
    }

    private static func quadEdges(
        for quad: CanvasQuad
    ) -> [(start: CGPoint, end: CGPoint)] {
        [
            (quad.topLeading, quad.topTrailing),
            (quad.topTrailing, quad.bottomTrailing),
            (quad.bottomTrailing, quad.bottomLeading),
            (quad.bottomLeading, quad.topLeading)
        ]
    }

    private static func distance(
        from point: CGPoint,
        toSegmentStart start: CGPoint,
        segmentEnd end: CGPoint
    ) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = (dx * dx) + (dy * dy)
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let projection = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        let clampedProjection = min(max(projection, 0), 1)
        let closestPoint = CGPoint(
            x: start.x + (clampedProjection * dx),
            y: start.y + (clampedProjection * dy)
        )
        return hypot(point.x - closestPoint.x, point.y - closestPoint.y)
    }

    private func referenceLocalPoint(
        fromWorld worldPoint: CGPoint,
        center: CGPoint,
        rotationRadians: CGFloat
    ) -> CGPoint {
        let translatedPoint = CGPoint(
            x: worldPoint.x - center.x,
            y: worldPoint.y - center.y
        )
        let cosine = cos(rotationRadians)
        let sine = sin(rotationRadians)
        return CGPoint(
            x: (translatedPoint.x * cosine) + (translatedPoint.y * sine),
            y: (-translatedPoint.x * sine) + (translatedPoint.y * cosine)
        )
    }

    private func referenceWorldPoint(
        fromLocal localPoint: CGPoint,
        center: CGPoint,
        rotationRadians: CGFloat
    ) -> CGPoint {
        let cosine = cos(rotationRadians)
        let sine = sin(rotationRadians)
        return CGPoint(
            x: center.x + (localPoint.x * cosine) - (localPoint.y * sine),
            y: center.y + (localPoint.x * sine) + (localPoint.y * cosine)
        )
    }

    private func angle(
        from center: CGPoint,
        to point: CGPoint
    ) -> CGFloat {
        atan2(point.y - center.y, point.x - center.x)
    }

    private func anglesMatch(
        _ lhs: CGFloat,
        _ rhs: CGFloat,
        tolerance: CGFloat = 0.0001
    ) -> Bool {
        abs(normalizedCanvasAngle(lhs - rhs)) < tolerance
    }

    private func constrainedCropLocalFrame(
        _ draggedLocalPoint: CGPoint,
        for handleRole: CanvasCropHandleRole,
        initialLocalFrame: CGRect,
        fullImageLocalFrame: CGRect,
        minimumLocalSize: CGSize
    ) -> CGRect {
        let initialLocalFrame = initialLocalFrame.standardized
        let fullImageLocalFrame = fullImageLocalFrame.standardized

        switch handleRole {
        case .topLeading, .topTrailing, .bottomLeading, .bottomTrailing:
            return proportionalCropLocalFrame(
                draggedLocalPoint,
                for: handleRole,
                initialLocalFrame: initialLocalFrame,
                fullImageLocalFrame: fullImageLocalFrame,
                minimumLocalSize: minimumLocalSize
            )
        case .top:
            let minY = min(
                max(draggedLocalPoint.y, fullImageLocalFrame.minY),
                initialLocalFrame.maxY - minimumLocalSize.height
            )
            return CGRect(
                x: initialLocalFrame.minX,
                y: minY,
                width: initialLocalFrame.width,
                height: initialLocalFrame.maxY - minY
            )
        case .trailing:
            let maxX = max(
                min(draggedLocalPoint.x, fullImageLocalFrame.maxX),
                initialLocalFrame.minX + minimumLocalSize.width
            )
            return CGRect(
                x: initialLocalFrame.minX,
                y: initialLocalFrame.minY,
                width: maxX - initialLocalFrame.minX,
                height: initialLocalFrame.height
            )
        case .bottom:
            let maxY = max(
                min(draggedLocalPoint.y, fullImageLocalFrame.maxY),
                initialLocalFrame.minY + minimumLocalSize.height
            )
            return CGRect(
                x: initialLocalFrame.minX,
                y: initialLocalFrame.minY,
                width: initialLocalFrame.width,
                height: maxY - initialLocalFrame.minY
            )
        case .leading:
            let minX = min(
                max(draggedLocalPoint.x, fullImageLocalFrame.minX),
                initialLocalFrame.maxX - minimumLocalSize.width
            )
            return CGRect(
                x: minX,
                y: initialLocalFrame.minY,
                width: initialLocalFrame.maxX - minX,
                height: initialLocalFrame.height
            )
        }
    }

    // Corner crop drags now keep the opposite corner fixed and preserve the
    // current aspect ratio, while edge handles still use single-axis trimming.
    private func proportionalCropLocalFrame(
        _ draggedLocalPoint: CGPoint,
        for handleRole: CanvasCropHandleRole,
        initialLocalFrame: CGRect,
        fullImageLocalFrame: CGRect,
        minimumLocalSize: CGSize
    ) -> CGRect {
        guard
            initialLocalFrame.width > 0,
            initialLocalFrame.height > 0
        else {
            return initialLocalFrame
        }

        let oppositeCorner = fixedOppositeCropLocalCorner(
            for: handleRole,
            in: initialLocalFrame
        )
        let constrainedLocalCorner = constrainedDraggedCropLocalCorner(
            draggedLocalPoint,
            for: handleRole,
            oppositeCorner: oppositeCorner,
            fullImageLocalFrame: fullImageLocalFrame
        )
        let widthScale = abs(constrainedLocalCorner.x - oppositeCorner.x) / initialLocalFrame.width
        let heightScale = abs(constrainedLocalCorner.y - oppositeCorner.y) / initialLocalFrame.height
        let minimumScale = max(
            minimumLocalSize.width / initialLocalFrame.width,
            minimumLocalSize.height / initialLocalFrame.height
        )
        let maximumScale = maximumProportionalCropScale(
            for: handleRole,
            oppositeCorner: oppositeCorner,
            initialLocalFrame: initialLocalFrame,
            fullImageLocalFrame: fullImageLocalFrame
        )
        let scale = min(
            max(widthScale, heightScale, minimumScale),
            maximumScale
        )
        guard scale.isFinite, scale > 0 else {
            return initialLocalFrame
        }

        return cropLocalFrame(
            for: handleRole,
            withFixedOppositeCorner: oppositeCorner,
            size: CGSize(
                width: initialLocalFrame.width * scale,
                height: initialLocalFrame.height * scale
            )
        )
    }

    private func fixedOppositeCropLocalCorner(
        for handleRole: CanvasCropHandleRole,
        in localFrame: CGRect
    ) -> CGPoint {
        switch handleRole {
        case .topLeading:
            return CGPoint(x: localFrame.maxX, y: localFrame.maxY)
        case .topTrailing:
            return CGPoint(x: localFrame.minX, y: localFrame.maxY)
        case .bottomLeading:
            return CGPoint(x: localFrame.maxX, y: localFrame.minY)
        case .bottomTrailing:
            return CGPoint(x: localFrame.minX, y: localFrame.minY)
        case .top, .trailing, .bottom, .leading:
            assertionFailure("Only crop corner handles have an opposite corner.")
            return localFrame.origin
        }
    }

    private func constrainedDraggedCropLocalCorner(
        _ draggedLocalCorner: CGPoint,
        for handleRole: CanvasCropHandleRole,
        oppositeCorner: CGPoint,
        fullImageLocalFrame: CGRect
    ) -> CGPoint {
        switch handleRole {
        case .topLeading:
            return CGPoint(
                x: min(
                    max(draggedLocalCorner.x, fullImageLocalFrame.minX),
                    oppositeCorner.x
                ),
                y: min(
                    max(draggedLocalCorner.y, fullImageLocalFrame.minY),
                    oppositeCorner.y
                )
            )
        case .topTrailing:
            return CGPoint(
                x: max(
                    min(draggedLocalCorner.x, fullImageLocalFrame.maxX),
                    oppositeCorner.x
                ),
                y: min(
                    max(draggedLocalCorner.y, fullImageLocalFrame.minY),
                    oppositeCorner.y
                )
            )
        case .bottomLeading:
            return CGPoint(
                x: min(
                    max(draggedLocalCorner.x, fullImageLocalFrame.minX),
                    oppositeCorner.x
                ),
                y: max(
                    min(draggedLocalCorner.y, fullImageLocalFrame.maxY),
                    oppositeCorner.y
                )
            )
        case .bottomTrailing:
            return CGPoint(
                x: max(
                    min(draggedLocalCorner.x, fullImageLocalFrame.maxX),
                    oppositeCorner.x
                ),
                y: max(
                    min(draggedLocalCorner.y, fullImageLocalFrame.maxY),
                    oppositeCorner.y
                )
            )
        case .top, .trailing, .bottom, .leading:
            assertionFailure("Only crop corner handles support proportional dragging.")
            return draggedLocalCorner
        }
    }

    private func maximumProportionalCropScale(
        for handleRole: CanvasCropHandleRole,
        oppositeCorner: CGPoint,
        initialLocalFrame: CGRect,
        fullImageLocalFrame: CGRect
    ) -> CGFloat {
        let maxWidth: CGFloat
        let maxHeight: CGFloat

        switch handleRole {
        case .topLeading:
            maxWidth = oppositeCorner.x - fullImageLocalFrame.minX
            maxHeight = oppositeCorner.y - fullImageLocalFrame.minY
        case .topTrailing:
            maxWidth = fullImageLocalFrame.maxX - oppositeCorner.x
            maxHeight = oppositeCorner.y - fullImageLocalFrame.minY
        case .bottomLeading:
            maxWidth = oppositeCorner.x - fullImageLocalFrame.minX
            maxHeight = fullImageLocalFrame.maxY - oppositeCorner.y
        case .bottomTrailing:
            maxWidth = fullImageLocalFrame.maxX - oppositeCorner.x
            maxHeight = fullImageLocalFrame.maxY - oppositeCorner.y
        case .top, .trailing, .bottom, .leading:
            assertionFailure("Only crop corner handles have a proportional max scale.")
            return 1
        }

        return min(
            maxWidth / initialLocalFrame.width,
            maxHeight / initialLocalFrame.height
        )
    }

    private func cropLocalFrame(
        for handleRole: CanvasCropHandleRole,
        withFixedOppositeCorner oppositeCorner: CGPoint,
        size: CGSize
    ) -> CGRect {
        switch handleRole {
        case .topLeading:
            return CGRect(
                x: oppositeCorner.x - size.width,
                y: oppositeCorner.y - size.height,
                width: size.width,
                height: size.height
            )
        case .topTrailing:
            return CGRect(
                x: oppositeCorner.x,
                y: oppositeCorner.y - size.height,
                width: size.width,
                height: size.height
            )
        case .bottomLeading:
            return CGRect(
                x: oppositeCorner.x - size.width,
                y: oppositeCorner.y,
                width: size.width,
                height: size.height
            )
        case .bottomTrailing:
            return CGRect(
                x: oppositeCorner.x,
                y: oppositeCorner.y,
                width: size.width,
                height: size.height
            )
        case .top, .trailing, .bottom, .leading:
            assertionFailure("Only crop corner handles build proportional corner frames.")
            return CGRect(origin: oppositeCorner, size: size)
        }
    }

    private func translatedCropLocalFrame(
        _ draggedLocalPoint: CGPoint,
        using translationState: PointerCropTranslationState
    ) -> CGRect {
        let initialLocalFrame = translationState.initialLocalFrame.standardized
        let fullImageLocalFrame = translationState.fullImageLocalFrame.standardized
        let delta = CGPoint(
            x: draggedLocalPoint.x - translationState.initialPointerLocalPoint.x,
            y: draggedLocalPoint.y - translationState.initialPointerLocalPoint.y
        )
        let translatedOrigin = CGPoint(
            x: initialLocalFrame.minX + delta.x,
            y: initialLocalFrame.minY + delta.y
        )
        let clampedOrigin = CGPoint(
            x: min(
                max(translatedOrigin.x, fullImageLocalFrame.minX),
                fullImageLocalFrame.maxX - initialLocalFrame.width
            ),
            y: min(
                max(translatedOrigin.y, fullImageLocalFrame.minY),
                fullImageLocalFrame.maxY - initialLocalFrame.height
            )
        )
        return CGRect(
            origin: clampedOrigin,
            size: initialLocalFrame.size
        )
    }

    private func panCanvas(from previousLocation: CGPoint, to location: CGPoint) {
        let translation = CGPoint(
            x: location.x - previousLocation.x,
            y: location.y - previousLocation.y
        )
        guard translation != .zero else {
            return
        }

        camera.pan(by: translation)
        refreshCanvas()
        scheduleAutosave(reason: "drag canvas")
    }

    private func expandBoardIfNeeded(toInclude worldFrame: CGRect) {
        editorSession.expandBoardIfNeeded(toInclude: worldFrame)
    }

    private func configureBoardStateIfNeeded(for viewportSize: CGSize) -> Bool {
        editorSession.configureBoardStateIfNeeded(for: viewportSize)
    }

    private func restorePersistedBoardIfPossible() {
        editorSession.restorePersistedBoardIfPossible()
        updateInlineEditButtonsAppearance()
    }

    private func applyBoardRuntimeState(_ runtimeState: BoardRuntimeState) {
        cancelRotationInteractionIfNeeded(resetPointerDragState: true)
        editorSession.applyBoardRuntimeState(runtimeState)
        updateInlineEditButtonsAppearance()
    }

    private func currentBoardHistorySnapshot() -> BoardHistorySnapshot {
        editorSession.currentBoardHistorySnapshot()
    }

    private func beginPointerHistoryTransactionIfNeeded(
        for pressTarget: PointerPressTarget
    ) {
        let reason: String
        switch pressTarget {
        case .rotateHandle:
            reason = "rotate item"
        case .cropHandle, .cropOutline:
            reason = "crop item"
        case .handle:
            reason = "resize item"
        case .selectedBody:
            reason = "move item"
        case .unselectedItem, .blank:
            return
        }

        editorSession.beginHistoryTransaction(reason: reason)
    }

    private func commitPendingPointerHistoryTransaction(
        autosaveReason: String
    ) {
        guard editorSession.commitPendingHistoryTransaction(
            autosaveReason: autosaveReason
        ) else {
            return
        }
    }

    private func recordImmediateHistoryChange(
        from beforeSnapshot: BoardHistorySnapshot,
        reason: String,
        autosaveReason: String? = nil
    ) {
        guard editorSession.recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: reason,
            autosaveReason: autosaveReason
        ) else {
            return
        }
    }

    private var isInlineEditModeActive: Bool {
        editorSession.isInlineEditModeActive
    }

    private func scheduleAutosave(reason: String) {
        editorSession.scheduleAutosave(reason: reason)
    }

    private func saveBoardNow(
        reason: String,
        createBoardIfNeeded: Bool = false,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        editorSession.saveBoardNow(
            reason: reason,
            createBoardIfNeeded: createBoardIfNeeded,
            completion: completion
        )
    }

    private func beginSaveButtonSaveState() {
        saveButtonResetWorkItem?.cancel()
        saveButton.isEnabled = false
        applySaveButtonAppearance(
            title: "Saving",
            systemImageName: "square.and.arrow.down",
            tintColor: .controlAccentColor
        )
    }

    private func showSaveButtonFeedback(
        title: String,
        systemImageName: String,
        tintColor: NSColor
    ) {
        saveButton.isEnabled = true
        applySaveButtonAppearance(
            title: title,
            systemImageName: systemImageName,
            tintColor: tintColor
        )

        saveButtonResetWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.applyDefaultSaveButtonAppearance()
        }
        saveButtonResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }

    private func applyDefaultSaveButtonAppearance() {
        saveButton.isEnabled = true
        applySaveButtonAppearance(
            title: "Save",
            systemImageName: "square.and.arrow.down",
            tintColor: .controlAccentColor
        )
    }

    private func updateInlineEditButtonsAppearance() {
        updateCropButtonAppearance()
    }

    private func updateCropButtonAppearance() {
        let descriptor = commandDescriptor(for: .crop)
        applyCropButtonAppearance(
            title: descriptor.title,
            systemImageName: descriptor.systemImageName,
            tintColor: descriptor.isActive ? .systemOrange : .controlAccentColor,
            isEnabled: descriptor.isEnabled
        )
    }

    private func applySaveButtonAppearance(
        title: String,
        systemImageName: String,
        tintColor: NSColor
    ) {
        saveButton.title = title
        saveButton.image = NSImage(
            systemSymbolName: systemImageName,
            accessibilityDescription: title
        )
        saveButton.contentTintColor = tintColor
    }

    private func applyCropButtonAppearance(
        title: String,
        systemImageName: String,
        tintColor: NSColor,
        isEnabled: Bool
    ) {
        cropButton.title = title
        cropButton.image = NSImage(
            systemSymbolName: systemImageName,
            accessibilityDescription: title
        )
        cropButton.contentTintColor = isEnabled ? tintColor : .secondaryLabelColor
        cropButton.isEnabled = isEnabled
    }

    private func presentSaveError(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Unable to Save Board"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")

        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func describe(itemID: CanvasImageItemID?) -> String {
        itemID?.uuidString ?? "nil"
    }
}
#endif
