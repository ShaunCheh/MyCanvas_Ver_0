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
    private enum PointerDragState {
        case idle
        case pressed(
            pressedLocation: CGPoint,
            pressedItemID: CanvasImageItemID?,
            pressedItemWasSelected: Bool
        )
        case draggingSelectedItem(itemID: CanvasImageItemID)
        case draggingCanvas
    }

    private static let isDiagnosticLoggingEnabled = false
    private static let pointerDragActivationDistance: CGFloat = 4
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
    private let canvasViewportView = iOSCanvasViewportView()
    private var canvasContentView: UIView?
    private var pendingRefreshReason: String?
    private var boardState: CanvasBoardState?
    private var interactionState = CanvasInteractionState()
    private var lastRenderSnapshot: CanvasRenderSnapshot = .empty
    private var pointerDragState: PointerDragState = .idle
    private var activeBoardID: UUID?
    private var activeBoardTitle = BoardDocument.defaultTitle
    private var activeBoardCreatedAt: Date?
    private let saveCoordinator = BoardSaveCoordinator(
        queueLabel: "MyCanvas.BoardSave.iOS",
        logPrefix: "[BoardStore][iOS]"
    )
    private var saveButtonResetWorkItem: DispatchWorkItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViewHierarchy()
        setupConstraints()
        setupImportButton()
        setupSaveButton()
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
            saveButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            saveButton.bottomAnchor.constraint(equalTo: importButton.topAnchor, constant: -12),
            importButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            importButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),
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

        let pressedItemID = hitTestItemID(at: location)
        pointerDragState = .pressed(
            pressedLocation: location,
            pressedItemID: pressedItemID,
            pressedItemWasSelected: pressedItemID == interactionState.selectedItemID
        )
    }

    private func handlePrimaryPointerMove(to location: CGPoint, from previousLocation: CGPoint) {
        syncCameraViewportSizeFromCurrentBoundsIfPossible()
        guard hasRenderableViewportSize else {
            logIgnoredCanvasInput("pointer move \(describe(point: location))")
            return
        }

        switch pointerDragState {
        case let .pressed(pressedLocation, pressedItemID, pressedItemWasSelected):
            guard hasExceededPointerDragActivationDistance(from: pressedLocation, to: location) else {
                return
            }

            if pressedItemWasSelected, let pressedItemID {
                pointerDragState = .draggingSelectedItem(itemID: pressedItemID)
                moveSelectedItem(withID: pressedItemID, from: pressedLocation, to: location)
            } else {
                pointerDragState = .draggingCanvas
                panCanvas(from: pressedLocation, to: location)
            }
        case let .draggingSelectedItem(itemID):
            moveSelectedItem(withID: itemID, from: previousLocation, to: location)
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
        case let .pressed(_, pressedItemID, _):
            let releasedItemID = hitTestItemID(at: location)
            let previousSelectedItemID = interactionState.selectedItemID
            var clickTarget = "blank"
            var clickResult = "selection_unchanged"
            var affectedItemID: CanvasImageItemID?

            if let pressedItemID, releasedItemID == pressedItemID {
                clickTarget = "image"
                affectedItemID = pressedItemID
                selectItem(withID: pressedItemID)
                if previousSelectedItemID != pressedItemID {
                    clickResult = "image_selected"
                }
            } else if pressedItemID == nil, releasedItemID == nil {
                affectedItemID = previousSelectedItemID
                clearSelectionIfNeeded()
                if previousSelectedItemID != nil {
                    clickResult = "image_deselected"
                }
            } else {
                clickTarget = "mismatched_hit_test"
                affectedItemID = releasedItemID ?? pressedItemID
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
        case .draggingSelectedItem, .draggingCanvas, .idle:
            break
        }
    }

    private func handlePrimaryPointerCancel() {
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
            interactionState: interactionState
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
        scheduleAutosave(reason: "append image")
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

    private func selectItem(withID itemID: CanvasImageItemID) {
        guard interactionState.selectedItemID != itemID else {
            return
        }

        interactionState.selectedItemID = itemID
        requestCanvasRefresh(reason: "select item \(itemID.uuidString)")
    }

    private func clearSelectionIfNeeded() {
        guard interactionState.selectedItemID != nil else {
            return
        }

        interactionState.selectedItemID = nil
        requestCanvasRefresh(reason: "clear selection")
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
        lastRenderSnapshot.items
            .reversed()
            .first(where: { $0.screenFrame.contains(viewportLocation) })?
            .id
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
            expandBoardIfNeeded(toInclude: movedItem.worldFrame)
        }
        requestCanvasRefresh(reason: "move selected item by \(describe(point: deltaInWorld))")
        scheduleAutosave(reason: "move item")
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
            applyBoardRuntimeState(try BoardStore.loadOrCreateInitialBoard())
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
