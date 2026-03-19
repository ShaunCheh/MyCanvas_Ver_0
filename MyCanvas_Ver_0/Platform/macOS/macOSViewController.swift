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
            pressContext: CanvasContextMenuContext
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
    var launchContext: CanvasLaunchContext?
    var onBackToBoardList: (() -> Void)?
    private let editorSession = CanvasEditorSession(
        saveQueueLabel: "MyCanvas.BoardSave.macOS",
        logPrefix: "[BoardStore][macOS]"
    )
    private let commandCatalog = CanvasCommandCatalog()
    private let contextMenuCommandResolver = CanvasContextMenuCommandResolver()
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
    private let backButton: NSButton = {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.title = ""
        button.toolTip = "Back to board list"
        button.wantsLayer = true
        button.layer?.cornerRadius = 22
        button.layer?.masksToBounds = true
        button.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.92).cgColor
        button.layer?.borderWidth = 1
        button.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        button.contentTintColor = .labelColor
        if let image = NSImage(
            systemSymbolName: "chevron.left",
            accessibilityDescription: "Back to board list"
        ) {
            button.image = image
            button.imagePosition = .imageOnly
        } else {
            button.title = "<"
        }
        return button
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
    private let contextMenuHostView = CanvasContextMenuHostView()
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
    private var pendingRefreshReason: String?
    private var pointerDragState: PointerDragState = .idle
    private var saveButtonResetWorkItem: DispatchWorkItem?
    private lazy var commandExecutor = CanvasCommandExecutor(
        session: editorSession
    )
    private var contextMenuState: CanvasContextMenuState? {
        didSet {
            updateContextMenuPresentation()
        }
    }

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

    private var contextResolverMetrics: CanvasContextResolverMetrics {
        CanvasContextResolverMetrics(
            selectionHandleHitTargetSize: Self.selectionHandleHitTargetSize,
            cropHandleHitTargetSize: Self.cropHandleHitTargetSize,
            cropOutlineHitTargetWidth: Self.cropOutlineHitTargetWidth,
            rotateHandleHitTargetSize: Self.rotateHandleHitTargetSize
        )
    }

    private func resolveContext(
        at viewportLocation: CGPoint
    ) -> CanvasContextMenuContext {
        editorSession.resolveContext(
            at: viewportLocation,
            interactionMetrics: contextResolverMetrics
        )
    }

    private func frozenContextMenuCommandStates(
        for commandIDs: [CanvasCommandID],
        context: CanvasContextMenuContext
    ) -> [CanvasContextMenuCommandState] {
        commandIDs.map { commandID in
            CanvasContextMenuCommandState(
                commandID: commandID,
                descriptor: commandDescriptor(
                    for: commandID,
                    context: context
                )
            )
        }
    }

    private func commandDescriptor(
        for commandID: CanvasCommandID,
        context: CanvasContextMenuContext? = nil
    ) -> CanvasCommandDescriptor {
        commandCatalog.descriptor(
            for: commandID,
            session: editorSession,
            context: context
        )
    }

    private func performCommand(_ command: CanvasCommand) {
        guard commandExecutor.canExecute(command) else {
            return
        }

        dismissContextMenu()

        if command.shouldCancelActiveRotation {
            cancelRotationInteractionIfNeeded(
                resetPointerDragState: command.shouldResetPointerDragStateWhenCancellingRotation
            )
        }

        guard let executionResult = commandExecutor.execute(command) else {
            return
        }

        updateInlineEditButtonsAppearance()

        if let refreshReason = executionResult.refreshReason {
            refreshCanvas(reason: refreshReason)
        }
    }

    private func presentContextMenu(
        for resolvedContext: CanvasContextMenuContext
    ) {
        let commandIDs = contextMenuCommandResolver.commandIDs(
            for: resolvedContext,
            session: editorSession
        )
        logContextMenuPresentation(
            resolvedContext: resolvedContext,
            commandIDs: commandIDs
        )
        let commandStates = frozenContextMenuCommandStates(
            for: commandIDs,
            context: resolvedContext
        )
        guard commandStates.isEmpty == false else {
            dismissContextMenu()
            return
        }

        contextMenuState = CanvasContextMenuState(
            resolvedContext: resolvedContext,
            layoutAnchorPoint: contextMenuLayoutAnchorPoint(for: resolvedContext),
            commandStates: commandStates
        )
    }

    private func dismissContextMenu() {
        contextMenuState = nil
    }

    private func updateContextMenuPresentation() {
        contextMenuHostView.apply(
            state: contextMenuState,
            safeBounds: contextMenuSafeBounds(),
            occupiedRects: contextMenuOccupiedRects()
        )
    }

    private func updateContextMenuLayout() {
        contextMenuHostView.updateLayout(
            safeBounds: contextMenuSafeBounds(),
            occupiedRects: contextMenuOccupiedRects()
        )
    }

    private func performContextMenuCommand(_ commandID: CanvasCommandID) {
        guard
            let contextMenuState,
            let command = contextMenuCommandResolver.command(
                for: commandID,
                context: contextMenuState.resolvedContext
            )
        else {
            dismissContextMenu()
            return
        }

        dismissContextMenu()
        performCommand(command)
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
        case .selectItem,
             .clearSelection,
             .duplicateItem,
             .deleteItem,
             .bringItemForward,
             .sendItemBackward,
             .bringItemToFront,
             .sendItemToBack:
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
        print(
            "[Canvas macOS][ControllerLifecycle] " +
            "action=viewDidLoad.begin " +
            "viewBounds=\(describe(rect: view.bounds)) " +
            "viewFrame=\(describe(rect: view.frame)) " +
            "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
            "selectedItemID=\(describe(itemID: interactionState.selectedItemID))"
        )
        setupViewHierarchy()
        setupConstraints()
        setupImportButton()
        setupSaveButton()
        setupCropButton()
        setupBackButton()
        setupMiniMapView()
        setupContextMenuHostView()
        restoreInitialBoardState()
        setupCanvasViewport()
        print(
            "[Canvas macOS][ControllerLifecycle] " +
            "action=viewDidLoad.end " +
            "viewBounds=\(describe(rect: view.bounds)) " +
            "viewFrame=\(describe(rect: view.frame)) " +
            "canvasHostBounds=\(describe(rect: canvasHostView.bounds)) " +
            "canvasHostFrame=\(describe(rect: canvasHostView.frame)) " +
            "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
            "selectedItemID=\(describe(itemID: interactionState.selectedItemID))"
        )
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        print(
            "[Canvas macOS][ControllerLifecycle] " +
            "action=viewWillAppear " +
            "viewBounds=\(describe(rect: view.bounds)) " +
            "viewFrame=\(describe(rect: view.frame)) " +
            "windowFrame=\(view.window.map { describe(rect: $0.frame) } ?? "nil") " +
            "cameraViewportSize=\(describe(size: camera.viewportSize))"
        )
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        print(
            "[Canvas macOS][ControllerLifecycle] " +
            "action=viewDidAppear " +
            "viewBounds=\(describe(rect: view.bounds)) " +
            "viewFrame=\(describe(rect: view.frame)) " +
            "windowFrame=\(view.window.map { describe(rect: $0.frame) } ?? "nil") " +
            "canvasHostBounds=\(describe(rect: canvasHostView.bounds)) " +
            "canvasHostFrame=\(describe(rect: canvasHostView.frame)) " +
            "canvasViewportBounds=\(describe(rect: canvasViewportView.bounds)) " +
            "canvasViewportFrame=\(describe(rect: canvasViewportView.frame)) " +
            "cameraViewportSize=\(describe(size: camera.viewportSize))"
        )
        updateCameraViewportSizeIfNeeded(trigger: "viewDidAppear")
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        print(
            "[Canvas macOS][ControllerLifecycle] " +
            "action=viewDidLayout.begin " +
            "viewBounds=\(describe(rect: view.bounds)) " +
            "viewFrame=\(describe(rect: view.frame)) " +
            "canvasHostBounds=\(describe(rect: canvasHostView.bounds)) " +
            "canvasHostFrame=\(describe(rect: canvasHostView.frame)) " +
            "canvasViewportBounds=\(describe(rect: canvasViewportView.bounds)) " +
            "canvasViewportFrame=\(describe(rect: canvasViewportView.frame)) " +
            "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
            "snapshotViewportBounds=\(describe(rect: lastRenderSnapshot.viewportBounds))"
        )
        updateCameraViewportSizeIfNeeded(trigger: "viewDidLayout")
        updateChromeOverlayLayout()
        print(
            "[Canvas macOS][ControllerLifecycle] " +
            "action=viewDidLayout.end " +
            "viewBounds=\(describe(rect: view.bounds)) " +
            "canvasViewportBounds=\(describe(rect: canvasViewportView.bounds)) " +
            "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
            "snapshotViewportBounds=\(describe(rect: lastRenderSnapshot.viewportBounds))"
        )
    }

    // Future canvas viewport views should always be mounted through this host.
    func installCanvasContentView(_ contentView: NSView) {
        _ = view
        print(
            "[Canvas macOS][ViewportInstall] " +
            "action=begin " +
            "contentViewType=\(String(describing: type(of: contentView))) " +
            "rootViewBounds=\(describe(rect: view.bounds)) " +
            "canvasHostBounds=\(describe(rect: canvasHostView.bounds)) " +
            "canvasHostFrame=\(describe(rect: canvasHostView.frame)) " +
            "contentViewBounds=\(describe(rect: contentView.bounds)) " +
            "contentViewFrame=\(describe(rect: contentView.frame))"
        )
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
        print(
            "[Canvas macOS][ViewportInstall] " +
            "action=end " +
            "contentViewType=\(String(describing: type(of: contentView))) " +
            "rootViewBounds=\(describe(rect: view.bounds)) " +
            "canvasHostBounds=\(describe(rect: canvasHostView.bounds)) " +
            "canvasHostFrame=\(describe(rect: canvasHostView.frame)) " +
            "contentViewBounds=\(describe(rect: contentView.bounds)) " +
            "contentViewFrame=\(describe(rect: contentView.frame))"
        )
    }

    private func setupViewHierarchy() {
        view.addSubview(canvasHostView)
        view.addSubview(chromeOverlayView)
        chromeOverlayView.addSubview(miniMapMountView)
        chromeOverlayView.addSubview(controlsStackView)
        chromeOverlayView.addSubview(contextMenuHostView)
        chromeOverlayView.addSubview(backButton)
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
            contextMenuHostView.topAnchor.constraint(equalTo: chromeOverlayView.topAnchor),
            contextMenuHostView.leadingAnchor.constraint(equalTo: chromeOverlayView.leadingAnchor),
            contextMenuHostView.trailingAnchor.constraint(equalTo: chromeOverlayView.trailingAnchor),
            contextMenuHostView.bottomAnchor.constraint(equalTo: chromeOverlayView.bottomAnchor),
            backButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 20),
            backButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),
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
        updateContextMenuLayout()
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
        var rects: [CGRect] = []
        appendChromeOccupiedRect(for: backButton, to: &rects)
        appendChromeOccupiedRect(for: controlsStackView, to: &rects)
        return rects
    }

    private func contextMenuOccupiedRects() -> [CGRect] {
        var rects = chromeOccupiedRects()
        let miniMapFrame = miniMapMountView.frame.standardized
        if miniMapMountView.isHidden == false, miniMapFrame.isEmpty == false {
            rects.append(miniMapFrame)
        }

        return rects.map { rect in
            convertToContextMenuHost(rect, from: chromeOverlayView)
        }
    }

    private func contextMenuSafeBounds() -> CGRect {
        convertToContextMenuHost(
            chromeSafeBounds(),
            from: chromeOverlayView
        )
    }

    private func appendChromeOccupiedRect(
        for view: NSView,
        to rects: inout [CGRect]
    ) {
        guard view.isHidden == false else {
            return
        }

        let standardizedRect = view.frame.standardized
        guard standardizedRect.isEmpty == false else {
            return
        }

        rects.append(standardizedRect)
    }

    private func contextMenuLayoutAnchorPoint(
        for resolvedContext: CanvasContextMenuContext
    ) -> CGPoint {
        convertToContextMenuHost(
            resolvedContext.anchorPoint,
            from: canvasViewportView
        )
    }

    private func convertToContextMenuHost(
        _ point: CGPoint,
        from sourceView: NSView
    ) -> CGPoint {
        contextMenuHostView.convert(
            point,
            from: sourceView
        )
    }

    private func convertToContextMenuHost(
        _ rect: CGRect,
        from sourceView: NSView
    ) -> CGRect {
        contextMenuHostView.convert(
            rect,
            from: sourceView
        ).standardized
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

    private func setupBackButton() {
        backButton.target = self
        backButton.action = #selector(handleBackButtonClick)
    }

    private func setupMiniMapView() {
        miniMapView.frame = miniMapMountView.bounds
        miniMapView.autoresizingMask = [.width, .height]
        miniMapView.onNavigate = { [weak self] point in
            self?.handleMiniMapNavigate(to: point)
        }
        miniMapMountView.addSubview(miniMapView)
    }

    private func setupContextMenuHostView() {
        contextMenuHostView.onDismissRequested = { [weak self] in
            self?.dismissContextMenu()
        }
        contextMenuHostView.onCommandSelected = { [weak self] commandID in
            self?.performContextMenuCommand(commandID)
        }
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
        canvasViewportView.onSecondaryClick = { [weak self] location in
            self?.handleSecondaryClick(at: location)
        }
        canvasViewportView.onPan = { [weak self] translation in
            self?.handleIndirectPan(translation)
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
        print(
            "[Canvas macOS][ViewportInstall] " +
            "action=afterSetupCanvasViewport " +
            "canvasViewportBounds=\(describe(rect: canvasViewportView.bounds)) " +
            "canvasViewportFrame=\(describe(rect: canvasViewportView.frame)) " +
            "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
            "snapshotViewportBounds=\(describe(rect: lastRenderSnapshot.viewportBounds))"
        )
        refreshCanvas(reason: "initial setup")
    }

    private func updateCameraViewportSizeIfNeeded(
        trigger: String = "unspecified"
    ) {
        syncCameraViewportSizeIfNeeded(
            canvasViewportView.bounds.size,
            source: trigger
        )
    }

    private func syncCameraViewportSizeIfNeeded(
        _ viewportSize: CGSize,
        source: String
    ) {
        let cameraBeforeSync = camera
        let snapshotBeforeSync = lastRenderSnapshot
        print(
            "[Canvas macOS][ViewportSync] " +
            "trigger=\(source) " +
            "phase=begin " +
            "viewBoundsSize=\(describe(size: view.bounds.size)) " +
            "canvasHostBounds=\(describe(rect: canvasHostView.bounds)) " +
            "canvasViewportBounds=\(describe(rect: canvasViewportView.bounds)) " +
            "canvasViewportFrame=\(describe(rect: canvasViewportView.frame)) " +
            "cameraViewportSizeBefore=\(describe(size: cameraBeforeSync.viewportSize)) " +
            "snapshotViewportBoundsBefore=\(describe(rect: snapshotBeforeSync.viewportBounds))"
        )
        guard isRenderable(viewportSize: viewportSize) else {
            print(
                "[Canvas macOS][ViewportSync] " +
                "trigger=\(source) " +
                "phase=skipEmptyViewport " +
                "viewBoundsSize=\(describe(size: view.bounds.size)) " +
                "canvasViewportBounds=\(describe(rect: canvasViewportView.bounds)) " +
                "canvasViewportFrame=\(describe(rect: canvasViewportView.frame)) " +
                "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
                "snapshotViewportBounds=\(describe(rect: lastRenderSnapshot.viewportBounds))"
            )
            return
        }

        let sizeChanged = viewportSize != camera.viewportSize
        if sizeChanged {
            camera.setViewportSize(viewportSize)
        }

        let didConfigureBoardState = configureBoardStateIfNeeded(for: viewportSize)
        let deferredReason = pendingRefreshReason
        guard sizeChanged || didConfigureBoardState || deferredReason != nil else {
            print(
                "[Canvas macOS][ViewportSync] " +
                "trigger=\(source) " +
                "phase=noChange " +
                "viewBoundsSize=\(describe(size: viewportSize)) " +
                "cameraViewportSizeBefore=\(describe(size: cameraBeforeSync.viewportSize)) " +
                "cameraViewportSizeAfter=\(describe(size: camera.viewportSize)) " +
                "sizeChanged=\(sizeChanged) " +
                "didConfigureBoardState=\(didConfigureBoardState) " +
                "cameraCenterBefore=\(describe(point: cameraBeforeSync.center)) " +
                "cameraCenterAfter=\(describe(point: camera.center)) " +
                "zoomBefore=\(String(format: "%.4f", Double(cameraBeforeSync.zoomScale))) " +
                "zoomAfter=\(String(format: "%.4f", Double(camera.zoomScale))) " +
                "visibleWorldRectBefore=\(describe(rect: cameraBeforeSync.visibleWorldRect)) " +
                "visibleWorldRectAfter=\(describe(rect: camera.visibleWorldRect)) " +
                "snapshotViewportBoundsBefore=\(describe(rect: snapshotBeforeSync.viewportBounds)) " +
                "snapshotViewportBoundsAfter=\(describe(rect: lastRenderSnapshot.viewportBounds)) " +
                "snapshotEditOverlayBefore=\(describe(editOverlay: snapshotBeforeSync.editOverlay)) " +
                "snapshotEditOverlayAfter=\(describe(editOverlay: lastRenderSnapshot.editOverlay))"
            )
            return
        }

        pendingRefreshReason = nil

        if let deferredReason {
            performCanvasRefresh(
                reason: "flush deferred refresh (\(deferredReason)) after \(source) size=\(describe(size: viewportSize))"
            )
        } else {
            performCanvasRefresh(
                reason: "viewport sync trigger=\(source) sizeChanged=\(sizeChanged) didConfigureBoardState=\(didConfigureBoardState)"
            )
        }

        print(
            "[Canvas macOS][ViewportSync] " +
            "trigger=\(source) " +
            "viewBoundsSize=\(describe(size: viewportSize)) " +
            "cameraViewportSizeBefore=\(describe(size: cameraBeforeSync.viewportSize)) " +
            "cameraViewportSizeAfter=\(describe(size: camera.viewportSize)) " +
            "sizeChanged=\(sizeChanged) " +
            "didConfigureBoardState=\(didConfigureBoardState) " +
            "cameraCenterBefore=\(describe(point: cameraBeforeSync.center)) " +
            "cameraCenterAfter=\(describe(point: camera.center)) " +
            "zoomBefore=\(String(format: "%.4f", Double(cameraBeforeSync.zoomScale))) " +
            "zoomAfter=\(String(format: "%.4f", Double(camera.zoomScale))) " +
            "visibleWorldRectBefore=\(describe(rect: cameraBeforeSync.visibleWorldRect)) " +
            "visibleWorldRectAfter=\(describe(rect: camera.visibleWorldRect)) " +
            "snapshotViewportBoundsBefore=\(describe(rect: snapshotBeforeSync.viewportBounds)) " +
            "snapshotViewportBoundsAfter=\(describe(rect: lastRenderSnapshot.viewportBounds)) " +
            "snapshotEditOverlayBefore=\(describe(editOverlay: snapshotBeforeSync.editOverlay)) " +
            "snapshotEditOverlayAfter=\(describe(editOverlay: lastRenderSnapshot.editOverlay))"
        )

        if didConfigureBoardState {
            scheduleAutosave(reason: "configure board state")
        }
    }

    private func handlePrimaryPointerDown(at location: CGPoint) {
        print(
            "[Canvas macOS][PrimaryPointerInput] " +
            "phase=down " +
            "location=\(describe(point: location)) " +
            "worldPoint=\(describe(point: camera.viewportToWorld(location))) " +
            "selectedItemID=\(describe(itemID: interactionState.selectedItemID)) " +
            "cameraCenter=\(describe(point: camera.center)) " +
            "zoom=\(String(format: "%.4f", Double(camera.zoomScale))) " +
            "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
            "canvasViewportBounds=\(describe(rect: canvasViewportView.bounds)) " +
            "snapshotViewportBounds=\(describe(rect: lastRenderSnapshot.viewportBounds)) " +
            "snapshotEditOverlay=\(describe(editOverlay: lastRenderSnapshot.editOverlay))"
        )
        if contextMenuState != nil {
            dismissContextMenu()
            return
        }

        let pressContext = resolveContext(at: location)
        pointerDragState = .pressed(
            pressedLocation: location,
            pressContext: pressContext
        )
        beginPointerHistoryTransactionIfNeeded(for: pressContext)
    }

    private func handleSecondaryClick(at location: CGPoint) {
        let cameraBeforeSync = camera
        let snapshotBeforeSync = lastRenderSnapshot
        let worldPointBeforeSync = cameraBeforeSync.viewportToWorld(location)
        updateCameraViewportSizeIfNeeded(trigger: "secondary click")
        let worldPointAfterSync = camera.viewportToWorld(location)
        print(
            "[Canvas macOS][ContextMenuInput] " +
            "secondaryClickLocation=\(describe(point: location)) " +
            "worldPointBeforeSync=\(describe(point: worldPointBeforeSync)) " +
            "worldPointAfterSync=\(describe(point: worldPointAfterSync)) " +
            "pointerDragState=\(describe(pointerDragState: pointerDragState)) " +
            "selectedItemID=\(describe(itemID: interactionState.selectedItemID)) " +
            "viewportBounds=\(describe(rect: canvasViewportView.bounds)) " +
            "viewportFrame=\(describe(rect: canvasViewportView.frame)) " +
            "overlayBounds=\(describe(rect: chromeOverlayView.bounds)) " +
            "overlayFrame=\(describe(rect: chromeOverlayView.frame)) " +
            "cameraCenterBefore=\(describe(point: cameraBeforeSync.center)) " +
            "cameraCenterAfter=\(describe(point: camera.center)) " +
            "zoomBefore=\(String(format: "%.4f", Double(cameraBeforeSync.zoomScale))) " +
            "zoomAfter=\(String(format: "%.4f", Double(camera.zoomScale))) " +
            "cameraViewportSizeBefore=\(describe(size: cameraBeforeSync.viewportSize)) " +
            "cameraViewportSizeAfter=\(describe(size: camera.viewportSize)) " +
            "snapshotViewportBoundsBefore=\(describe(rect: snapshotBeforeSync.viewportBounds)) " +
            "snapshotViewportBoundsAfter=\(describe(rect: lastRenderSnapshot.viewportBounds)) " +
            "snapshotEditOverlayBefore=\(describe(editOverlay: snapshotBeforeSync.editOverlay)) " +
            "snapshotEditOverlayAfter=\(describe(editOverlay: lastRenderSnapshot.editOverlay))"
        )
        prepareForSecondaryClickContextMenu()

        let resolvedContext = resolveContext(at: location)
        presentContextMenu(for: resolvedContext)
    }

    private func prepareForSecondaryClickContextMenu() {
        let pointerDragStateBefore = describe(pointerDragState: pointerDragState)
        let selectedItemIDBefore = interactionState.selectedItemID
        dismissContextMenu()

        switch pointerDragState {
        case .idle:
            break
        case .pressed,
             .croppingSelectedItem,
             .movingCropFrame,
             .rotatingSelectedItem,
             .draggingSelectedItem,
             .resizingSelectedItem,
             .draggingCanvas:
            // Reuse primary-cancel semantics so secondary click never leaves a
            // half-committed drag/crop/rotate interaction behind.
            handlePrimaryPointerCancel()
        }

        print(
            "[Canvas macOS][ContextMenuPreparation] " +
            "pointerDragStateBefore=\(pointerDragStateBefore) " +
            "pointerDragStateAfter=\(describe(pointerDragState: pointerDragState)) " +
            "selectedItemIDBefore=\(describe(itemID: selectedItemIDBefore)) " +
            "selectedItemIDAfter=\(describe(itemID: interactionState.selectedItemID))"
        )
    }

    private func handlePrimaryPointerMove(to location: CGPoint, from previousLocation: CGPoint) {
        switch pointerDragState {
        case let .pressed(pressedLocation, pressContext):
            guard hasExceededPointerDragActivationDistance(from: pressedLocation, to: location) else {
                return
            }

            switch pressContext.targetKind {
            case .rotateHandle:
                guard let itemID = pressContext.targetItemID else {
                    editorSession.cancelPendingHistoryTransaction()
                    pointerDragState = .idle
                    return
                }

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
            case let .cropHandle(handleRole):
                guard let itemID = pressContext.targetItemID else {
                    editorSession.cancelPendingHistoryTransaction()
                    pointerDragState = .idle
                    return
                }

                guard let cropState = makePointerCropState(itemID: itemID, handleRole: handleRole) else {
                    editorSession.cancelPendingHistoryTransaction()
                    pointerDragState = .idle
                    return
                }

                pointerDragState = .croppingSelectedItem(cropState)
                updateCropDraft(using: cropState, to: location)
            case .cropOutline:
                guard let itemID = pressContext.targetItemID else {
                    editorSession.cancelPendingHistoryTransaction()
                    pointerDragState = .idle
                    return
                }

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
            case let .selectionHandle(handleRole):
                guard let itemID = pressContext.targetItemID else {
                    pointerDragState = .idle
                    return
                }

                guard let resizeState = makePointerResizeState(itemID: itemID, handleRole: handleRole) else {
                    pointerDragState = .idle
                    return
                }

                pointerDragState = .resizingSelectedItem(resizeState)
                resizeSelectedItem(using: resizeState, to: location)
            case .selectedItemBody:
                guard let itemID = pressContext.targetItemID else {
                    pointerDragState = .idle
                    return
                }

                pointerDragState = .draggingSelectedItem(itemID: itemID)
                moveSelectedItem(withID: itemID, from: pressedLocation, to: location)
            case .unselectedItemBody, .blank:
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
        case let .pressed(_, pressContext):
            if isInlineEditModeActive {
                editorSession.cancelPendingHistoryTransaction()
                return
            }

            let pressedItemID = pressContext.targetItemID
            let releasedContext = resolveContext(at: location)
            let releasedItemID = releasedContext.targetItemID
            let previousSelectedItemID = interactionState.selectedItemID
            var clickTarget = "blank"
            var clickResult = "selection_unchanged"
            var affectedItemID: CanvasImageItemID?

            switch pressContext.targetKind {
            case .rotateHandle:
                clickTarget = "rotate_handle"
                affectedItemID = pressContext.targetItemID
            case .cropHandle:
                clickTarget = "crop_handle"
                affectedItemID = pressContext.targetItemID
            case .cropOutline:
                clickTarget = "crop_outline"
                affectedItemID = pressContext.targetItemID
            case .selectionHandle:
                clickTarget = "handle"
                affectedItemID = pressContext.targetItemID
            case .selectedItemBody, .unselectedItemBody:
                if let itemID = pressContext.targetItemID,
                   releasedItemID == itemID
                {
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
                    affectedItemID = releasedItemID ?? pressContext.targetItemID
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
        if contextMenuState != nil {
            dismissContextMenu()
            return
        }

        camera.pan(by: translation)
        refreshCanvas()
        scheduleAutosave(reason: "pan canvas")
    }

    private func handleZoom(_ scaleDelta: CGFloat, around anchor: CGPoint) {
        if contextMenuState != nil {
            dismissContextMenu()
            return
        }

        camera.zoom(by: scaleDelta, around: anchor)
        refreshCanvas()
        scheduleAutosave(reason: "zoom canvas")
    }

    private func refreshCanvas(reason: String = "unspecified") {
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
        let snapshot = editorSession.makeCanvasSnapshot()
        logCanvasState(reason: reason, snapshot: snapshot)
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

    @objc
    private func handleBackButtonClick() {
        dismissContextMenu()
        onBackToBoardList?()
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

    private func restoreInitialBoardState() {
        switch launchContext {
        case let .existing(boardID):
            restoreBoard(withID: boardID)
        case .newBoard:
            startNewBoard()
        case .none:
            restorePersistedBoardIfPossible()
        }
    }

    private func restoreBoard(withID boardID: UUID) {
        print(
            "[Canvas macOS][RuntimeRestore] " +
            "action=controllerLoadBoard.begin " +
            "boardID=\(boardID.uuidString) " +
            "viewBounds=\(describe(rect: view.bounds)) " +
            "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
            "selectedItemID=\(describe(itemID: interactionState.selectedItemID))"
        )
        do {
            try editorSession.loadBoard(id: boardID)
        } catch {
            print(
                "[Canvas macOS][RuntimeRestore] " +
                "action=controllerLoadBoard.failed " +
                "boardID=\(boardID.uuidString) " +
                "error=\(error)"
            )
        }
        updateInlineEditButtonsAppearance()
        print(
            "[Canvas macOS][RuntimeRestore] " +
            "action=controllerLoadBoard.end " +
            "boardID=\(boardID.uuidString) " +
            "cameraCenter=\(describe(point: camera.center)) " +
            "zoom=\(String(format: "%.4f", Double(camera.zoomScale))) " +
            "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
            "selectedItemID=\(describe(itemID: interactionState.selectedItemID))"
        )
    }

    private func startNewBoard() {
        print(
            "[Canvas macOS][RuntimeRestore] " +
            "action=controllerStartNewBoard.begin " +
            "viewBounds=\(describe(rect: view.bounds)) " +
            "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
            "selectedItemID=\(describe(itemID: interactionState.selectedItemID))"
        )
        editorSession.startNewBoard()
        updateInlineEditButtonsAppearance()
        print(
            "[Canvas macOS][RuntimeRestore] " +
            "action=controllerStartNewBoard.end " +
            "cameraCenter=\(describe(point: camera.center)) " +
            "zoom=\(String(format: "%.4f", Double(camera.zoomScale))) " +
            "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
            "selectedItemID=\(describe(itemID: interactionState.selectedItemID))"
        )
    }

    private func restorePersistedBoardIfPossible() {
        print(
            "[Canvas macOS][RuntimeRestore] " +
            "action=controllerRestore.begin " +
            "viewBounds=\(describe(rect: view.bounds)) " +
            "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
            "selectedItemID=\(describe(itemID: interactionState.selectedItemID))"
        )
        editorSession.restorePersistedBoardIfPossible()
        updateInlineEditButtonsAppearance()
        print(
            "[Canvas macOS][RuntimeRestore] " +
            "action=controllerRestore.end " +
            "viewBounds=\(describe(rect: view.bounds)) " +
            "cameraCenter=\(describe(point: camera.center)) " +
            "zoom=\(String(format: "%.4f", Double(camera.zoomScale))) " +
            "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
            "selectedItemID=\(describe(itemID: interactionState.selectedItemID))"
        )
    }

    private func applyBoardRuntimeState(_ runtimeState: BoardRuntimeState) {
        cancelRotationInteractionIfNeeded(resetPointerDragState: true)
        print(
            "[Canvas macOS][RuntimeRestore] " +
            "action=controllerApplyRuntimeState.begin " +
            "runtimeBoardID=\(runtimeState.boardID.uuidString) " +
            "runtimeCameraViewportSize=\(describe(size: runtimeState.camera.viewportSize)) " +
            "runtimeSelectedItemID=\(describe(itemID: runtimeState.interactionState.selectedItemID))"
        )
        editorSession.applyBoardRuntimeState(runtimeState)
        updateInlineEditButtonsAppearance()
        print(
            "[Canvas macOS][RuntimeRestore] " +
            "action=controllerApplyRuntimeState.end " +
            "cameraCenter=\(describe(point: camera.center)) " +
            "zoom=\(String(format: "%.4f", Double(camera.zoomScale))) " +
            "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
            "selectedItemID=\(describe(itemID: interactionState.selectedItemID))"
        )
    }

    private func currentBoardHistorySnapshot() -> BoardHistorySnapshot {
        editorSession.currentBoardHistorySnapshot()
    }

    private func beginPointerHistoryTransactionIfNeeded(
        for pressContext: CanvasContextMenuContext
    ) {
        let reason: String
        switch pressContext.targetKind {
        case .rotateHandle:
            reason = "rotate item"
        case .cropHandle, .cropOutline:
            reason = "crop item"
        case .selectionHandle:
            reason = "resize item"
        case .selectedItemBody:
            reason = "move item"
        case .unselectedItemBody, .blank:
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

    private var hasRenderableViewportSize: Bool {
        isRenderable(viewportSize: camera.viewportSize)
    }

    private func isRenderable(viewportSize: CGSize) -> Bool {
        viewportSize.width > 0 && viewportSize.height > 0
    }

    private func describe(point: CGPoint) -> String {
        "{\(formatCoordinate(point.x)), \(formatCoordinate(point.y))}"
    }

    private func describe(size: CGSize) -> String {
        "{\(formatCoordinate(size.width)), \(formatCoordinate(size.height))}"
    }

    private func describe(rect: CGRect) -> String {
        "{{\(formatCoordinate(rect.origin.x)), \(formatCoordinate(rect.origin.y))}, {\(formatCoordinate(rect.size.width)), \(formatCoordinate(rect.size.height))}}"
    }

    private func describe(itemID: CanvasImageItemID?) -> String {
        itemID?.uuidString ?? "nil"
    }

    private func describe(editOverlay: CanvasEditRenderOverlay?) -> String {
        guard let editOverlay else {
            return "nil"
        }

        return "itemID=\(editOverlay.itemID.uuidString) kind=\(String(describing: editOverlay.kind)) activeScreenQuad=\(describe(rect: editOverlay.activeScreenQuad.boundingRect.standardized))"
    }

    private func describe(pointerDragState: PointerDragState) -> String {
        switch pointerDragState {
        case .idle:
            return "idle"
        case .pressed:
            return "pressed"
        case .croppingSelectedItem:
            return "croppingSelectedItem"
        case .movingCropFrame:
            return "movingCropFrame"
        case .rotatingSelectedItem:
            return "rotatingSelectedItem"
        case .draggingSelectedItem:
            return "draggingSelectedItem"
        case .resizingSelectedItem:
            return "resizingSelectedItem"
        case .draggingCanvas:
            return "draggingCanvas"
        }
    }

    private func logDeferredCanvasRefresh(
        reason: String,
        actualViewportSize: CGSize
    ) {
        print(
            "[Canvas macOS][CanvasRefresh] " +
            "phase=deferred " +
            "reason=\(reason) " +
            "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
            "viewBoundsSize=\(describe(size: actualViewportSize))"
        )
    }

    private func logCanvasState(reason: String, snapshot: CanvasRenderSnapshot) {
        let orderedItems = scene.orderedItems()
        let firstWorldFrame = orderedItems.first.map { describe(rect: $0.worldFrame) } ?? "nil"
        let firstScreenFrame = snapshot.items.first.map { describe(rect: $0.screenFrame) } ?? "nil"

        print(
            "[Canvas macOS][CanvasRefresh] " +
            "reason=\(reason) " +
            "cameraCenter=\(describe(point: camera.center)) " +
            "zoom=\(String(format: "%.4f", Double(camera.zoomScale))) " +
            "viewportSize=\(describe(size: camera.viewportSize)) " +
            "visibleWorldRect=\(describe(rect: camera.visibleWorldRect)) " +
            "selectedItemID=\(describe(itemID: interactionState.selectedItemID)) " +
            "sceneItems=\(orderedItems.count) " +
            "visibleItems=\(snapshot.items.count) " +
            "snapshotViewportBounds=\(describe(rect: snapshot.viewportBounds)) " +
            "snapshotVisibleWorldRect=\(describe(rect: snapshot.visibleWorldRect)) " +
            "editOverlay=\(describe(editOverlay: snapshot.editOverlay)) " +
            "firstWorldFrame=\(firstWorldFrame) " +
            "firstScreenFrame=\(firstScreenFrame)"
        )
    }

    private func logContextMenuPresentation(
        resolvedContext: CanvasContextMenuContext,
        commandIDs: [CanvasCommandID]
    ) {
        let occupiedRectsDescription = contextMenuOccupiedRects()
            .map(describe(rect:))
            .joined(separator: ", ")
        let commandIDsDescription = commandIDs.map(\.rawValue).joined(separator: ",")
        let layoutAnchorPoint = contextMenuLayoutAnchorPoint(
            for: resolvedContext
        )

        print(
            "[Canvas macOS][ContextMenuPosition] " +
            resolvedContext.debugSummary + " " +
            "viewportBounds=\(describe(rect: canvasViewportView.bounds)) " +
            "viewportFrame=\(describe(rect: canvasViewportView.frame)) " +
            "overlayBounds=\(describe(rect: chromeOverlayView.bounds)) " +
            "overlayFrame=\(describe(rect: chromeOverlayView.frame)) " +
            "hostBounds=\(describe(rect: contextMenuHostView.bounds)) " +
            "hostFrame=\(describe(rect: contextMenuHostView.frame)) " +
            "layoutAnchorPoint=\(describe(point: layoutAnchorPoint)) " +
            "safeBounds=\(describe(rect: contextMenuSafeBounds())) " +
            "occupiedRects=[\(occupiedRectsDescription)] " +
            "commandIDs=[\(commandIDsDescription)]"
        )
    }

    private func formatCoordinate(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }
}
#endif
