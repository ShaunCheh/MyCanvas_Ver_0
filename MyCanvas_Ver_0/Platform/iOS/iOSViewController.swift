//
//  iOSViewController.swift
//  MyCanvas_Ver_0
//
//  Created by Shaun on 2026/3/13.
//
#if os(iOS)
import ImageIO
import PhotosUI
import UniformTypeIdentifiers
import UIKit

final class iOSViewController: UIViewController, PHPickerViewControllerDelegate {
    private enum PointerPressTarget {
        case rotateHandle(itemID: CanvasImageItemID)
        case cropHandle(role: CanvasCropHandleRole, itemID: CanvasImageItemID)
        case handle(role: CanvasSelectionHandleRole, itemID: CanvasImageItemID)
        case selectedBody(itemID: CanvasImageItemID)
        case unselectedItem(itemID: CanvasImageItemID)
        case blank

        var itemID: CanvasImageItemID? {
            switch self {
            case let .rotateHandle(itemID), let .cropHandle(_, itemID), let .handle(_, itemID), let .selectedBody(itemID), let .unselectedItem(itemID):
                return itemID
            case .blank:
                return nil
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
        let fixedOppositeLocalCorner: CGPoint
        let minimumLocalSize: CGSize
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
        case rotatingSelectedItem(PointerRotateState)
        case draggingSelectedItem(itemID: CanvasImageItemID)
        case resizingSelectedItem(PointerResizeState)
        case draggingCanvas
    }

    private static let isDiagnosticLoggingEnabled = false
    private static let pointerDragActivationDistance: CGFloat = 4
    private static let selectionHandleHitTargetSize: CGFloat = 28
    private static let minimumResizeViewportDimension: CGFloat = 28
    private static let cropHandleHitTargetSize: CGFloat = 28
    private static let minimumCropViewportDimension: CGFloat = 28
    private static let rotateHandleHitTargetSize: CGFloat = 32
    private let scene = CanvasScene()
    private var camera = CanvasCamera()
    private let renderer = CanvasRenderer()
    private let canvasHostView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        view.clipsToBounds = true
        return view
    }()
    private let importButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.filled()
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        configuration.image = UIImage(systemName: "plus")
        configuration.baseBackgroundColor = .systemBlue
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        button.configuration = configuration
        return button
    }()
    private let saveButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.filled()
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        configuration.image = UIImage(systemName: "square.and.arrow.down")
        configuration.imagePlacement = .leading
        configuration.imagePadding = 6
        configuration.title = "Save"
        configuration.baseBackgroundColor = .systemGreen
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        button.configuration = configuration
        return button
    }()
    private let cropButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let rotateButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let canvasViewportView = iOSCanvasViewportView()
    private var canvasContentView: UIView?
    private var pendingRefreshReason: String?
    private var boardState: CanvasBoardState?
    private var interactionState = CanvasInteractionState()
    private var inlineEditState: CanvasInlineEditState?
    private var lastRenderSnapshot: CanvasRenderSnapshot = .empty
    private var pointerDragState: PointerDragState = .idle
    private var activeBoardID: UUID?
    private var activeBoardTitle = BoardDocument.defaultTitle
    private var activeBoardCreatedAt: Date?
    private let saveCoordinator = BoardSaveCoordinator(
        queueLabel: "MyCanvas.BoardSave.iOS",
        logPrefix: "[BoardStore][iOS]"
    )
    private let historyController = BoardHistoryController()
    private var saveButtonResetWorkItem: DispatchWorkItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViewHierarchy()
        setupConstraints()
        setupImportButton()
        setupSaveButton()
        setupCropButton()
        setupRotateButton()
        restorePersistedBoardIfPossible()
        setupCanvasViewport()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        syncCameraViewportSizeIfNeeded(
            canvasViewportView.bounds.size,
            source: "controller layout fallback"
        )
    }

    // Future canvas viewport views should always be mounted through this host.
    func installCanvasContentView(_ contentView: UIView) {
        loadViewIfNeeded()
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
        view.backgroundColor = .systemBackground
        view.addSubview(canvasHostView)
        view.addSubview(rotateButton)
        view.addSubview(cropButton)
        view.addSubview(saveButton)
        view.addSubview(importButton)
    }

    private func setupConstraints() {
        let safeAreaLayoutGuide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            canvasHostView.topAnchor.constraint(equalTo: view.topAnchor),
            canvasHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvasHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvasHostView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            rotateButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            rotateButton.bottomAnchor.constraint(equalTo: cropButton.topAnchor, constant: -12),
            cropButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            cropButton.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -12),
            saveButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            saveButton.bottomAnchor.constraint(equalTo: importButton.topAnchor, constant: -12),
            importButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            importButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),
            rotateButton.heightAnchor.constraint(equalToConstant: 40),
            cropButton.heightAnchor.constraint(equalToConstant: 40),
            saveButton.heightAnchor.constraint(equalToConstant: 40),
            importButton.heightAnchor.constraint(equalToConstant: 56)
        ])
    }

    private func setupImportButton() {
        importButton.addTarget(self, action: #selector(handleImportButtonTap), for: .touchUpInside)
    }

    private func setupSaveButton() {
        saveButton.addTarget(self, action: #selector(handleSaveButtonTap), for: .touchUpInside)
    }

    private func setupCropButton() {
        cropButton.addTarget(self, action: #selector(handleCropButtonTap), for: .touchUpInside)
        updateInlineEditButtonsAppearance()
    }

    private func setupRotateButton() {
        rotateButton.addTarget(self, action: #selector(handleRotateButtonTap), for: .touchUpInside)
        updateInlineEditButtonsAppearance()
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
        canvasViewportView.onZoom = { [weak self] scaleDelta, anchor in
            self?.handleZoom(scaleDelta, around: anchor)
        }
        canvasViewportView.onViewportSizeChange = { [weak self] viewportSize in
            self?.syncCameraViewportSizeIfNeeded(
                viewportSize,
                source: "viewport layout"
            )
        }

        installCanvasContentView(canvasViewportView)
        requestCanvasRefresh(reason: "initial setup")
    }

    private func syncCameraViewportSizeIfNeeded(
        _ viewportSize: CGSize,
        source: String
    ) {
        guard isRenderable(viewportSize: viewportSize) else {
            return
        }

        let sizeChanged = viewportSize != camera.viewportSize
        let didConfigureBoardState = configureBoardStateIfNeeded(for: viewportSize)
        let deferredReason = pendingRefreshReason
        guard sizeChanged || deferredReason != nil || didConfigureBoardState else {
            return
        }

        if sizeChanged {
            camera.setViewportSize(viewportSize)
        }

        pendingRefreshReason = nil

        if let deferredReason {
            performCanvasRefresh(
                reason: "flush deferred refresh (\(deferredReason)) after \(source) size=\(describe(size: viewportSize))"
            )
        } else {
            performCanvasRefresh(
                reason: "viewport size changed to \(describe(size: viewportSize)) via \(source)"
            )
        }

        if didConfigureBoardState {
            scheduleAutosave(reason: "configure board state")
        }
    }

    private func handlePrimaryPointerDown(at location: CGPoint) {
        syncCameraViewportSizeFromCurrentBoundsIfPossible()
        guard hasRenderableViewportSize else {
            logIgnoredCanvasInput("pointer down \(describe(point: location))")
            return
        }

        let pressTarget = pointerPressTarget(at: location)
        pointerDragState = .pressed(
            pressedLocation: location,
            pressTarget: pressTarget
        )
        beginPointerHistoryTransactionIfNeeded(for: pressTarget)
    }

    private func handlePrimaryPointerMove(to location: CGPoint, from previousLocation: CGPoint) {
        syncCameraViewportSizeFromCurrentBoundsIfPossible()
        guard hasRenderableViewportSize else {
            logIgnoredCanvasInput("pointer move \(describe(point: location))")
            return
        }

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
                    historyController.cancelPendingTransaction()
                    pointerDragState = .idle
                    return
                }

                pointerDragState = .rotatingSelectedItem(rotateState)
                updateRotationDraft(using: rotateState, to: location)
            case let .cropHandle(handleRole, itemID):
                guard let cropState = makePointerCropState(itemID: itemID, handleRole: handleRole) else {
                    historyController.cancelPendingTransaction()
                    pointerDragState = .idle
                    return
                }

                pointerDragState = .croppingSelectedItem(cropState)
                updateCropDraft(using: cropState, to: location)
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
                historyController.cancelPendingTransaction()
                return
            }

            let pressedItemID = pressTarget.itemID
            let releasedHandleHit = hitTestSelectionHandle(at: location)
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
            historyController.cancelPendingTransaction()
        case .rotatingSelectedItem:
            commitRotationDraftIfNeeded()
        case .croppingSelectedItem:
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
            commitRotationDraftIfNeeded()
        case .croppingSelectedItem:
            commitCropDraftIfNeeded()
        case .draggingSelectedItem:
            commitPendingPointerHistoryTransaction(autosaveReason: "move item")
        case .resizingSelectedItem:
            commitPendingPointerHistoryTransaction(autosaveReason: "resize item")
        case .pressed, .draggingCanvas, .idle:
            historyController.cancelPendingTransaction()
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

    private func handleZoom(_ scaleDelta: CGFloat, around anchor: CGPoint) {
        syncCameraViewportSizeFromCurrentBoundsIfPossible()
        guard hasRenderableViewportSize else {
            logIgnoredCanvasInput(
                "zoom scaleDelta=\(String(format: "%.4f", scaleDelta)) anchor=\(describe(point: anchor))"
            )
            return
        }

        camera.zoom(by: scaleDelta, around: anchor)
        requestCanvasRefresh(
            reason: "zoom scaleDelta=\(String(format: "%.4f", scaleDelta)) anchor=\(describe(point: anchor))"
        )
        scheduleAutosave(reason: "zoom canvas")
    }

    private func requestCanvasRefresh(reason: String) {
        syncCameraViewportSizeFromCurrentBoundsIfPossible()
        guard hasRenderableViewportSize else {
            pendingRefreshReason = reason
            logDeferredCanvasRefresh(
                reason: reason,
                actualViewportSize: canvasViewportView.bounds.size
            )
            return
        }

        pendingRefreshReason = nil
        performCanvasRefresh(reason: reason)
    }

    private func syncCameraViewportSizeFromCurrentBoundsIfPossible() {
        let viewportSize = canvasViewportView.bounds.size
        guard
            isRenderable(viewportSize: viewportSize),
            viewportSize != camera.viewportSize
        else {
            return
        }

        camera.setViewportSize(viewportSize)
        _ = configureBoardStateIfNeeded(for: viewportSize)
    }

    private func performCanvasRefresh(reason: String) {
        let snapshot = renderer.makeSnapshot(
            scene: scene,
            boardState: boardState,
            camera: camera,
            interactionState: interactionState,
            inlineEditState: inlineEditState
        )
        lastRenderSnapshot = snapshot
        canvasViewportView.apply(snapshot)
        logCanvasState(reason: reason, snapshot: snapshot)
    }

    @objc
    private func handleImportButtonTap() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1

        let pickerViewController = PHPickerViewController(configuration: configuration)
        pickerViewController.delegate = self
        present(pickerViewController, animated: true)
    }

    @objc
    private func handleSaveButtonTap() {
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
                    backgroundColor: .systemGreen
                )
            case let .failure(error):
                if case FolderBookmarkStoreError.missingBookmarkData = error {
                    self.showSaveButtonFeedback(
                        title: "No Folder",
                        systemImageName: "exclamationmark.triangle",
                        backgroundColor: .systemOrange
                    )
                    self.presentSaveError(
                        message: "Select a folder from the board list before saving."
                    )
                } else {
                    self.showSaveButtonFeedback(
                        title: "Failed",
                        systemImageName: "xmark",
                        backgroundColor: .systemRed
                    )
                    self.presentSaveError(message: error.localizedDescription)
                }
            }
        }
    }

    @objc
    private func handleCropButtonTap() {
        if isInlineCropModeActive {
            endInlineEditMode(reason: "exit crop mode")
        } else {
            beginCropModeIfPossible()
        }
    }

    @objc
    private func handleRotateButtonTap() {
        if isInlineRotateModeActive {
            endInlineEditMode(reason: "exit rotate mode")
        } else {
            beginRotateModeIfPossible()
        }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        guard let result = results.first else {
            return
        }

        loadSelectedImage(from: result)
    }

    private func loadSelectedImage(from result: PHPickerResult) {
        let itemProvider = result.itemProvider
        guard itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
            return
        }

        itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
            guard
                let data,
                let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
                let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
            else {
                return
            }

            Task { @MainActor [weak self] in
                self?.logImport(dataCount: data.count, cgImage: cgImage)
                self?.appendImportedImage(cgImage)
            }
        }
    }

    private func appendImportedImage(_ cgImage: CGImage) {
        let beforeSnapshot = currentBoardHistorySnapshot()
        let item = CanvasImageItem(
            cgImage: cgImage,
            center: camera.center,
            size: normalizedDisplaySize(for: cgImage),
            zIndex: nextImageZIndex()
        )

        scene.append(item)
        expandBoardIfNeeded(toInclude: item.worldFrame)
        requestCanvasRefresh(
            reason: "append image size=\(describe(size: item.size)) center=\(describe(point: item.center))"
        )
        recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: "append image",
            autosaveReason: "append image"
        )
    }

    private func normalizedDisplaySize(for cgImage: CGImage) -> CGSize {
        let pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
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

    private func nextImageZIndex() -> CGFloat {
        (scene.orderedItems().last?.zIndex ?? -1) + 1
    }

    private func selectItem(
        withID itemID: CanvasImageItemID,
        recordHistory: Bool = false
    ) {
        guard interactionState.selectedItemID != itemID else {
            return
        }

        let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
        interactionState.selectedItemID = itemID
        syncInlineEditStateWithSelection()
        requestCanvasRefresh(reason: "select item \(itemID.uuidString)")

        if let beforeSnapshot {
            recordImmediateHistoryChange(
                from: beforeSnapshot,
                reason: "select item"
            )
        }
    }

    private func clearSelectionIfNeeded(recordHistory: Bool = false) {
        guard interactionState.selectedItemID != nil else {
            return
        }

        let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
        interactionState.selectedItemID = nil
        syncInlineEditStateWithSelection()
        requestCanvasRefresh(reason: "clear selection")

        if let beforeSnapshot {
            recordImmediateHistoryChange(
                from: beforeSnapshot,
                reason: "clear selection"
            )
        }
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
            "[Canvas iOS][ClickSelection] " +
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

    private func hitTestSelectionHandle(at viewportLocation: CGPoint) -> (role: CanvasSelectionHandleRole, itemID: CanvasImageItemID)? {
        guard let selectionOverlay = lastRenderSnapshot.selectionOverlay else {
            return nil
        }

        return selectionOverlay.handles.first(where: { handle in
            Self.selectionHandleHitRect(centeredAt: handle.screenCenter).contains(viewportLocation)
        }).map { handle in
            (role: handle.role, itemID: selectionOverlay.itemID)
        }
    }

    private func hitTestCropHandle(at viewportLocation: CGPoint) -> (role: CanvasCropHandleRole, itemID: CanvasImageItemID)? {
        guard let cropOverlay = lastRenderSnapshot.cropOverlay else {
            return nil
        }

        return cropOverlay.handles.first(where: { handle in
            Self.cropHandleHitRect(centeredAt: handle.screenCenter).contains(viewportLocation)
        }).map { handle in
            (role: handle.role, itemID: cropOverlay.itemID)
        }
    }

    private func hitTestRotateHandle(at viewportLocation: CGPoint) -> CanvasImageItemID? {
        guard let rotateOverlay = lastRenderSnapshot.rotateOverlay else {
            return nil
        }

        guard Self.rotateHandleHitRect(
            centeredAt: rotateOverlay.handle.screenCenter
        ).contains(viewportLocation) else {
            return nil
        }

        return rotateOverlay.itemID
    }

    // Keep interaction priority aligned with common editors: resize handles win
    // over body hits so a visible handle is always the first-class press target.
    private func pointerPressTarget(at viewportLocation: CGPoint) -> PointerPressTarget {
        if isInlineCropModeActive {
            if let cropHandleHit = hitTestCropHandle(at: viewportLocation) {
                return .cropHandle(role: cropHandleHit.role, itemID: cropHandleHit.itemID)
            }

            return .blank
        }

        if isInlineRotateModeActive {
            if let rotateHandleItemID = hitTestRotateHandle(at: viewportLocation) {
                return .rotateHandle(itemID: rotateHandleItemID)
            }

            return .blank
        }

        if let handleHit = hitTestSelectionHandle(at: viewportLocation) {
            return .handle(role: handleHit.role, itemID: handleHit.itemID)
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
            let item = scene.item(withID: itemID),
            let inlineEditState,
            inlineEditState.mode == .rotate,
            inlineEditState.itemID == itemID
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
                inlineEditState.draftRotationRadians - initialPointerAngle
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
            fixedOppositeLocalCorner: fixedOppositeLocalCorner(
                for: handleRole,
                in: draftLocalFrame
            ),
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
        let constrainedLocalPoint = constrainedDraggedCropLocalCorner(
            draggedLocalPoint,
            for: cropState.handleRole,
            oppositeCorner: cropState.fixedOppositeLocalCorner,
            fullImageLocalFrame: cropState.fullImageLocalFrame,
            minimumLocalSize: cropState.minimumLocalSize
        )
        let cropLocalFrame = CGRect(
            x: min(constrainedLocalPoint.x, cropState.fixedOppositeLocalCorner.x),
            y: min(constrainedLocalPoint.y, cropState.fixedOppositeLocalCorner.y),
            width: abs(constrainedLocalPoint.x - cropState.fixedOppositeLocalCorner.x),
            height: abs(constrainedLocalPoint.y - cropState.fixedOppositeLocalCorner.y)
        ).standardized
        let draftCropRectNormalized = item.normalizedCropRect(fromLocalFrame: cropLocalFrame)
        guard inlineEditState.draftCropRectNormalized != draftCropRectNormalized else {
            return
        }

        inlineEditState.draftCropRectNormalized = draftCropRectNormalized
        self.inlineEditState = inlineEditState
        requestCanvasRefresh(reason: "update crop draft")
    }

    private func commitCropDraftIfNeeded() {
        guard
            let inlineEditState,
            inlineEditState.mode == .crop,
            let item = scene.item(withID: inlineEditState.itemID)
        else {
            historyController.cancelPendingTransaction()
            return
        }

        guard item.cropRectNormalized != inlineEditState.draftCropRectNormalized else {
            historyController.cancelPendingTransaction()
            return
        }

        guard let croppedItem = scene.cropItem(
            withID: inlineEditState.itemID,
            toNormalizedCropRect: inlineEditState.draftCropRectNormalized
        ) else {
            historyController.cancelPendingTransaction()
            return
        }

        expandBoardIfNeeded(toInclude: croppedItem.worldBounds)
        self.inlineEditState = CanvasInlineEditState(item: croppedItem, mode: .crop)
        requestCanvasRefresh(reason: "commit crop item")
        commitPendingPointerHistoryTransaction(autosaveReason: "crop item")
    }

    private func updateRotationDraft(
        using rotateState: PointerRotateState,
        to viewportLocation: CGPoint
    ) {
        guard
            var inlineEditState,
            inlineEditState.mode == .rotate,
            inlineEditState.itemID == rotateState.itemID
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
            inlineEditState.draftRotationRadians,
            draftRotationRadians
        ) else {
            return
        }

        inlineEditState.draftRotationRadians = draftRotationRadians
        self.inlineEditState = inlineEditState
        requestCanvasRefresh(reason: "update rotate draft")
    }

    private func commitRotationDraftIfNeeded() {
        guard
            let inlineEditState,
            inlineEditState.mode == .rotate,
            let item = scene.item(withID: inlineEditState.itemID)
        else {
            historyController.cancelPendingTransaction()
            return
        }

        guard !anglesMatch(item.rotationRadians, inlineEditState.draftRotationRadians) else {
            historyController.cancelPendingTransaction()
            return
        }

        guard let rotatedItem = scene.rotateItem(
            withID: inlineEditState.itemID,
            to: inlineEditState.draftRotationRadians
        ) else {
            historyController.cancelPendingTransaction()
            return
        }

        expandBoardIfNeeded(toInclude: rotatedItem.worldBounds)
        self.inlineEditState = CanvasInlineEditState(item: rotatedItem, mode: .rotate)
        requestCanvasRefresh(reason: "commit rotate item")
        commitPendingPointerHistoryTransaction(autosaveReason: "rotate item")
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
        requestCanvasRefresh(reason: "move selected item by \(describe(point: deltaInWorld))")
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
        requestCanvasRefresh(reason: "resize selected item to \(describe(rect: resizedItem.worldBounds))")
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

    private func fixedOppositeLocalCorner(
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
        }
    }

    private func constrainedDraggedCropLocalCorner(
        _ draggedLocalCorner: CGPoint,
        for handleRole: CanvasCropHandleRole,
        oppositeCorner: CGPoint,
        fullImageLocalFrame: CGRect,
        minimumLocalSize: CGSize
    ) -> CGPoint {
        switch handleRole {
        case .topLeading:
            return CGPoint(
                x: min(
                    max(draggedLocalCorner.x, fullImageLocalFrame.minX),
                    oppositeCorner.x - minimumLocalSize.width
                ),
                y: min(
                    max(draggedLocalCorner.y, fullImageLocalFrame.minY),
                    oppositeCorner.y - minimumLocalSize.height
                )
            )
        case .topTrailing:
            return CGPoint(
                x: max(
                    min(draggedLocalCorner.x, fullImageLocalFrame.maxX),
                    oppositeCorner.x + minimumLocalSize.width
                ),
                y: min(
                    max(draggedLocalCorner.y, fullImageLocalFrame.minY),
                    oppositeCorner.y - minimumLocalSize.height
                )
            )
        case .bottomLeading:
            return CGPoint(
                x: min(
                    max(draggedLocalCorner.x, fullImageLocalFrame.minX),
                    oppositeCorner.x - minimumLocalSize.width
                ),
                y: max(
                    min(draggedLocalCorner.y, fullImageLocalFrame.maxY),
                    oppositeCorner.y + minimumLocalSize.height
                )
            )
        case .bottomTrailing:
            return CGPoint(
                x: max(
                    min(draggedLocalCorner.x, fullImageLocalFrame.maxX),
                    oppositeCorner.x + minimumLocalSize.width
                ),
                y: max(
                    min(draggedLocalCorner.y, fullImageLocalFrame.maxY),
                    oppositeCorner.y + minimumLocalSize.height
                )
            )
        }
    }

    private func panCanvas(from previousLocation: CGPoint, to location: CGPoint) {
        let translation = CGPoint(
            x: location.x - previousLocation.x,
            y: location.y - previousLocation.y
        )
        guard translation != .zero else {
            return
        }

        let cameraCenterBeforePan = camera.center
        camera.pan(by: translation)
        logPanDispatch(
            translation: translation,
            cameraCenterBeforePan: cameraCenterBeforePan,
            cameraCenterAfterPan: camera.center
        )
        requestCanvasRefresh(reason: "pan \(describe(point: translation))")
        scheduleAutosave(reason: "pan canvas")
    }

    private func expandBoardIfNeeded(toInclude worldFrame: CGRect) {
        guard var boardState else {
            return
        }

        if boardState.expandIfNeeded(toInclude: worldFrame) {
            self.boardState = boardState
        }
    }

    private func configureBoardStateIfNeeded(for viewportSize: CGSize) -> Bool {
        guard boardState == nil else {
            return false
        }

        boardState = CanvasBoardState(
            baseSize: viewportSize,
            centeredAt: camera.center
        )
        return true
    }

    private func restorePersistedBoardIfPossible() {
        do {
            let runtimeState = try BoardStore.loadOrCreateInitialBoard()
            applyBoardRuntimeState(runtimeState)
            historyController.reset()
        } catch FolderBookmarkStoreError.missingBookmarkData {
            return
        } catch {
            print("[BoardStore][iOS] Failed to restore board: \(error)")
        }
    }

    private func applyBoardRuntimeState(_ runtimeState: BoardRuntimeState) {
        activeBoardID = runtimeState.boardID
        activeBoardTitle = runtimeState.title
        activeBoardCreatedAt = runtimeState.createdAt
        scene.setItems(runtimeState.items)
        boardState = runtimeState.boardState
        camera = runtimeState.camera
        interactionState = runtimeState.interactionState
        inlineEditState = nil
        updateInlineEditButtonsAppearance()
    }

    private func currentBoardHistorySnapshot() -> BoardHistorySnapshot {
        BoardHistorySnapshot(
            items: scene.orderedItems(),
            boardState: boardState,
            interactionState: interactionState
        )
    }

    private func applyBoardHistorySnapshot(_ snapshot: BoardHistorySnapshot) {
        if let runtimeState = currentBoardRuntimeState() {
            applyBoardRuntimeState(
                runtimeState.replacingDocumentState(with: snapshot)
            )
        } else {
            scene.setItems(snapshot.items)
            boardState = snapshot.boardState
            interactionState = snapshot.interactionState
        }

        requestCanvasRefresh(reason: "apply history snapshot")
    }

    private func beginPointerHistoryTransactionIfNeeded(
        for pressTarget: PointerPressTarget
    ) {
        let reason: String
        switch pressTarget {
        case .rotateHandle:
            reason = "rotate item"
        case .cropHandle:
            reason = "crop item"
        case .handle:
            reason = "resize item"
        case .selectedBody:
            reason = "move item"
        case .unselectedItem, .blank:
            return
        }

        historyController.beginTransaction(
            from: currentBoardHistorySnapshot(),
            reason: reason
        )
    }

    private func commitPendingPointerHistoryTransaction(
        autosaveReason: String
    ) {
        guard historyController.commitPendingTransaction(to: currentBoardHistorySnapshot()) else {
            return
        }

        scheduleAutosave(reason: autosaveReason)
    }

    private func recordImmediateHistoryChange(
        from beforeSnapshot: BoardHistorySnapshot,
        reason: String,
        autosaveReason: String? = nil
    ) {
        guard historyController.recordChange(
            from: beforeSnapshot,
            to: currentBoardHistorySnapshot(),
            reason: reason
        ) else {
            return
        }

        if let autosaveReason {
            scheduleAutosave(reason: autosaveReason)
        }
    }

    private var isInlineCropModeActive: Bool {
        inlineEditState?.mode == .crop
    }

    private var isInlineRotateModeActive: Bool {
        inlineEditState?.mode == .rotate
    }

    private var isInlineEditModeActive: Bool {
        inlineEditState != nil
    }

    private func beginCropModeIfPossible() {
        guard
            !isInlineRotateModeActive,
            let selectedItemID = interactionState.selectedItemID,
            let item = scene.item(withID: selectedItemID)
        else {
            return
        }

        inlineEditState = CanvasInlineEditState(item: item, mode: .crop)
        updateInlineEditButtonsAppearance()
        requestCanvasRefresh(reason: "enter crop mode")
    }

    private func beginRotateModeIfPossible() {
        guard
            !isInlineCropModeActive,
            let selectedItemID = interactionState.selectedItemID,
            let item = scene.item(withID: selectedItemID)
        else {
            return
        }

        inlineEditState = CanvasInlineEditState(item: item, mode: .rotate)
        updateInlineEditButtonsAppearance()
        requestCanvasRefresh(reason: "enter rotate mode")
    }

    private func endInlineEditMode(reason: String) {
        guard inlineEditState != nil else {
            return
        }

        inlineEditState = nil
        updateInlineEditButtonsAppearance()
        requestCanvasRefresh(reason: reason)
    }

    private func syncInlineEditStateWithSelection() {
        guard let inlineEditState else {
            updateInlineEditButtonsAppearance()
            return
        }

        guard interactionState.selectedItemID == inlineEditState.itemID else {
            self.inlineEditState = nil
            updateInlineEditButtonsAppearance()
            return
        }

        if let item = scene.item(withID: inlineEditState.itemID) {
            self.inlineEditState = CanvasInlineEditState(item: item, mode: inlineEditState.mode)
        }
        updateInlineEditButtonsAppearance()
    }

    private func scheduleAutosave(reason: String) {
        guard let snapshot = currentBoardRuntimeState() else {
            return
        }

        saveCoordinator.scheduleAutosave(
            snapshot: snapshot,
            reason: reason
        )
    }

    private func saveBoardNow(
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

    private func currentBoardRuntimeState(
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

    private func ensureActiveBoardIdentityIfNeeded() -> Bool {
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

    private func beginSaveButtonSaveState() {
        saveButtonResetWorkItem?.cancel()
        saveButton.isEnabled = false
        applySaveButtonAppearance(
            title: "Saving",
            systemImageName: "square.and.arrow.down",
            backgroundColor: .systemBlue
        )
    }

    private func showSaveButtonFeedback(
        title: String,
        systemImageName: String,
        backgroundColor: UIColor
    ) {
        saveButton.isEnabled = true
        applySaveButtonAppearance(
            title: title,
            systemImageName: systemImageName,
            backgroundColor: backgroundColor
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
            backgroundColor: .systemGreen
        )
    }

    private func updateInlineEditButtonsAppearance() {
        updateCropButtonAppearance()
        updateRotateButtonAppearance()
    }

    private func updateCropButtonAppearance() {
        let isActive = isInlineCropModeActive
        let isEnabled = isActive || (interactionState.selectedItemID != nil && !isInlineRotateModeActive)
        applyCropButtonAppearance(
            title: isActive ? "Done" : "Crop",
            systemImageName: isActive ? "checkmark" : "crop",
            backgroundColor: isActive ? .systemOrange : .systemIndigo,
            isEnabled: isEnabled
        )
    }

    private func updateRotateButtonAppearance() {
        let isActive = isInlineRotateModeActive
        let isEnabled = isActive || (interactionState.selectedItemID != nil && !isInlineCropModeActive)
        applyRotateButtonAppearance(
            title: isActive ? "Done" : "Rotate",
            systemImageName: isActive ? "checkmark" : "rotate.right",
            backgroundColor: isActive ? .systemPurple : .systemTeal,
            isEnabled: isEnabled
        )
    }

    private func applySaveButtonAppearance(
        title: String,
        systemImageName: String,
        backgroundColor: UIColor
    ) {
        var configuration = saveButton.configuration ?? UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: systemImageName)
        configuration.baseBackgroundColor = backgroundColor
        saveButton.configuration = configuration
    }

    private func applyCropButtonAppearance(
        title: String,
        systemImageName: String,
        backgroundColor: UIColor,
        isEnabled: Bool
    ) {
        cropButton.isEnabled = isEnabled
        var configuration = cropButton.configuration ?? UIButton.Configuration.filled()
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        configuration.imagePlacement = .leading
        configuration.imagePadding = 6
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = .white
        configuration.title = title
        configuration.image = UIImage(systemName: systemImageName)
        configuration.baseBackgroundColor = isEnabled ? backgroundColor : .systemGray3
        cropButton.configuration = configuration
    }

    private func applyRotateButtonAppearance(
        title: String,
        systemImageName: String,
        backgroundColor: UIColor,
        isEnabled: Bool
    ) {
        rotateButton.isEnabled = isEnabled
        var configuration = rotateButton.configuration ?? UIButton.Configuration.filled()
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        configuration.imagePlacement = .leading
        configuration.imagePadding = 6
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = .white
        configuration.title = title
        configuration.image = UIImage(systemName: systemImageName)
        configuration.baseBackgroundColor = isEnabled ? backgroundColor : .systemGray3
        rotateButton.configuration = configuration
    }

    private func presentSaveError(message: String) {
        let alertController = UIAlertController(
            title: "Unable to Save Board",
            message: message,
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        present(alertController, animated: true)
    }

    private func logImport(dataCount: Int, cgImage: CGImage) {
        guard Self.isDiagnosticLoggingEnabled else {
            return
        }

        print(
            "[Canvas iOS] loaded image data bytes=\(dataCount) " +
            "pixelSize=\(cgImage.width)x\(cgImage.height)"
        )
    }

    private func logCanvasState(reason: String, snapshot: CanvasRenderSnapshot) {
        guard Self.isDiagnosticLoggingEnabled else {
            return
        }

        let orderedItems = scene.orderedItems()
        let firstWorldFrame = orderedItems.first.map { describe(rect: $0.worldFrame) } ?? "nil"
        let firstScreenFrame = snapshot.items.first.map { describe(rect: $0.screenFrame) } ?? "nil"

        print(
            "[Canvas iOS] \(reason) " +
            "cameraCenter=\(describe(point: camera.center)) " +
            "zoom=\(String(format: "%.4f", camera.zoomScale)) " +
            "viewportSize=\(describe(size: camera.viewportSize)) " +
            "visibleWorldRect=\(describe(rect: camera.visibleWorldRect)) " +
            "sceneItems=\(orderedItems.count) " +
            "visibleItems=\(snapshot.items.count) " +
            "firstWorldFrame=\(firstWorldFrame) " +
            "firstScreenFrame=\(firstScreenFrame)"
        )
    }

    private func logDeferredCanvasRefresh(
        reason: String,
        actualViewportSize: CGSize
    ) {
        guard Self.isDiagnosticLoggingEnabled else {
            return
        }

        print(
            "[Canvas iOS] deferred refresh reason=\(reason) " +
            "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
            "viewBoundsSize=\(describe(size: actualViewportSize))"
        )
    }

    private func logIgnoredCanvasInput(_ input: String) {
        guard Self.isDiagnosticLoggingEnabled else {
            return
        }

        print(
            "[Canvas iOS] ignored input=\(input) " +
            "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
            "viewBoundsSize=\(describe(size: canvasViewportView.bounds.size))"
        )
    }

    private func logPanDispatch(
        translation: CGPoint,
        cameraCenterBeforePan: CGPoint,
        cameraCenterAfterPan: CGPoint
    ) {
        guard Self.isDiagnosticLoggingEnabled else {
            return
        }

        print(
            "[Canvas iOS][ControllerPan] " +
            "translation=\(describe(point: translation)) " +
            "cameraCenterBefore=\(describe(point: cameraCenterBeforePan)) " +
            "cameraCenterAfter=\(describe(point: cameraCenterAfterPan)) " +
            "zoom=\(String(format: "%.4f", camera.zoomScale)) " +
            "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
            "viewBoundsSize=\(describe(size: canvasViewportView.bounds.size))"
        )
    }

    private var hasRenderableViewportSize: Bool {
        isRenderable(viewportSize: camera.viewportSize)
    }

    private func isRenderable(viewportSize: CGSize) -> Bool {
        viewportSize.width > 0 && viewportSize.height > 0
    }

    private func describe(point: CGPoint) -> String {
        NSCoder.string(for: point)
    }

    private func describe(size: CGSize) -> String {
        NSCoder.string(for: size)
    }

    private func describe(rect: CGRect) -> String {
        NSCoder.string(for: rect)
    }

    private func describe(itemID: CanvasImageItemID?) -> String {
        itemID?.uuidString ?? "nil"
    }
}
#endif
