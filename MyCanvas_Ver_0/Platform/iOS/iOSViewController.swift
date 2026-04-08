//
//  iOSViewController.swift
//  MyCanvas_Ver_0
//
//  Created by Shaun on 2026/3/13.
//
#if os(iOS)
import PhotosUI
import UIKit

final class iOSViewController: UIViewController, PHPickerViewControllerDelegate, UIDropInteractionDelegate, UITextViewDelegate {
    private struct PointerResizeState {
        let itemID: CanvasItemID
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
        let itemID: CanvasItemID
        let referenceCenter: CGPoint
        let rotationOffsetToPointerAngle: CGFloat
    }

    private enum PointerDragState {
        case idle
        case pressed(
            pressedLocation: CGPoint,
            pressContext: CanvasPointerPressContext
        )
        case croppingSelectedItem(PointerCropState)
        case movingCropFrame(PointerCropTranslationState)
        case rotatingSelectedItem(PointerRotateState)
        case draggingSelectedItem(itemID: CanvasItemID)
        case resizingSelectedItem(PointerResizeState)
        case draggingCanvas
    }

    private static let isDiagnosticLoggingEnabled = false
    private static let isPinchZoomDiagnosticLoggingEnabled = true
    private static let pointerDragActivationDistance: CGFloat = 4
    private static let selectionHandleHitTargetSize: CGFloat = 28
    private static let minimumResizeViewportDimension: CGFloat = 28
    private static let cropHandleHitTargetSize: CGFloat = 28
    private static let cropOutlineHitTargetWidth: CGFloat = 20
    private static let minimumCropViewportDimension: CGFloat = 28
    private static let rotateHandleHitTargetSize: CGFloat = 32
    private let miniMapLayoutSolver = CanvasOverlayLayoutSolver()
    private let alignmentGuideSolver = CanvasAlignmentGuideSolver()
    var miniMapConfiguration = CanvasMiniMapConfiguration()
    var launchContext: CanvasLaunchContext?
    var onBackToBoardList: (() -> Void)?
    private let editorSession = CanvasEditorSession(
        saveQueueLabel: "MyCanvas.BoardSave.iOS",
        logPrefix: "[BoardStore][iOS]"
    )
    private let commandCatalog = CanvasCommandCatalog()
    private let toolbarStateBuilder = CanvasToolbarStateBuilder()
    private let contextMenuActionResolver = CanvasContextMenuActionResolver()
    private let canvasHostView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        view.clipsToBounds = true
        return view
    }()
    private let chromeOverlayView: iOSCanvasChromeOverlayView = {
        let view = iOSCanvasChromeOverlayView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let backButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.filled()
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 17,
            weight: .semibold
        )
        configuration.image = UIImage(systemName: "chevron.left")
        configuration.baseBackgroundColor = .secondarySystemBackground
        configuration.baseForegroundColor = .label
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .zero
        button.configuration = configuration
        button.accessibilityLabel = "Back to board list"
        return button
    }()
    private let workspaceModeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.filled()
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 17,
            weight: .semibold
        )
        configuration.image = UIImage(
            systemName: CanvasWorkspaceMode.editing.systemImageName
        )
        configuration.baseBackgroundColor = .secondarySystemBackground
        configuration.baseForegroundColor = .label
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .zero
        button.configuration = configuration
        return button
    }()
    // Keep placement transient until persistence is designed; future UIPanGestureRecognizer
    // bridge code should write drag results back into this value.
    private var transientToolbarPlacement = CanvasToolbarPlacement(
        preferredEdge: .trailing
    ) {
        didSet {
            guard isViewLoaded else {
                return
            }

            updatePreparedToolbarPlacement()
        }
    }
    private let toolbarPlacementSolver = CanvasToolbarPlacementSolver()
    private let toolbarHostView = iOSCanvasToolbarHostView()
    private var toolbarTransitionRuntime: CanvasToolbarTransitionRuntime?
    private var toolbarTransitionAnimator: UIViewPropertyAnimator?
    private var isToolbarTransitionActive: Bool {
        toolbarTransitionRuntime != nil
    }
    private let textEditorOverlayView = iOSCanvasTextEditorOverlayView()
    private let historyButtonsStackView: iOSCanvasChromeStackView = {
        let stackView = iOSCanvasChromeStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .trailing
        stackView.distribution = .fill
        stackView.spacing = 12
        return stackView
    }()
    private let miniMapMountView: iOSCanvasChromeOverlayView = {
        let view = iOSCanvasChromeOverlayView()
        view.translatesAutoresizingMaskIntoConstraints = true
        view.isHidden = true
        return view
    }()
    private let contextMenuHostView = CanvasContextMenuHostView()
    private let miniMapView = iOSCanvasMiniMapView()
    private let importButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let saveButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let cropButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let textButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let undoButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let redoButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private var toolbarButtonsByID: [CanvasToolbarItemID: UIButton] {
        [
            .crop: cropButton,
            .save: saveButton,
            .text: textButton,
            .importMedia: importButton
        ]
    }
    private var historyButtons: [UIButton] {
        [undoButton, redoButton]
    }
    private let canvasViewportView = iOSCanvasViewportView()
    private var canvasContentView: UIView?
    private var pendingRefreshReason: String?
    private var pointerDragState: PointerDragState = .idle
    private var lastZoomDispatchTimestamp: TimeInterval?
    private var lastZoomRefreshTimestamp: TimeInterval?
    private var didMutateCameraDuringZoomGesture = false
    private var saveButtonResetWorkItem: DispatchWorkItem?
    private var saveButtonState: CanvasSaveState = .idle {
        didSet {
            renderToolbar()
        }
    }
    private lazy var commandExecutor = CanvasCommandExecutor(
        session: editorSession
    )
    private var contextMenuState: CanvasContextMenuState? {
        didSet {
            updateContextMenuPresentation()
        }
    }
    private var activeTextEditorItemID: CanvasItemID?
    private var isSyncingTextEditorContent = false

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

    private var alignmentInteractionState: CanvasAlignmentInteractionState? {
        get { editorSession.alignmentInteractionState }
        set { editorSession.alignmentInteractionState = newValue }
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

    private func resolvePointerPressContext(
        at viewportLocation: CGPoint
    ) -> CanvasPointerPressContext {
        editorSession.resolvePointerTarget(
            at: viewportLocation,
            interactionMetrics: contextResolverMetrics
        )
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
        if command.id != .commitTextEdit,
           isInlineTextModeActive,
           workspaceMode == .editing
        {
            performCommand(.commitTextEdit)
        }

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
            requestCanvasRefresh(reason: refreshReason)
        }
    }

    private func presentContextMenu(
        for resolvedContext: CanvasContextMenuContext
    ) {
        let actionStates = contextMenuActionResolver.actionStates(
            for: resolvedContext,
            session: editorSession
        )
        guard actionStates.isEmpty == false else {
            dismissContextMenu()
            return
        }

        contextMenuState = CanvasContextMenuState(
            resolvedContext: resolvedContext,
            layoutAnchorPoint: contextMenuLayoutAnchorPoint(for: resolvedContext),
            actionStates: actionStates
        )
    }

    private func dismissContextMenu() {
        contextMenuState = nil
    }

    private func updateContextMenuPresentation() {
        guard isViewLoaded else {
            return
        }

        let layoutContext = contextMenuLayoutContextForCurrentChromeState()
        if let contextMenuState {
            logContextMenuPresentation(
                state: contextMenuState,
                layoutContext: layoutContext
            )
        }
        contextMenuHostView.apply(
            state: contextMenuState,
            layoutContext: layoutContext
        )
    }

    private func contextMenuLayoutContextForCurrentChromeState() -> CanvasChromeLayoutContext {
        if let runtime = toolbarTransitionRuntime {
            return transitionContextMenuLayoutContext(for: runtime)
        }

        return performOverlayLayoutPass()
    }

    private func transitionContextMenuLayoutContext(
        for runtime: CanvasToolbarTransitionRuntime
    ) -> CanvasChromeLayoutContext {
        var chromeBlockers = baseChromeBlockersForToolbarLayout()
        let transitionFrame = normalizedToolbarFrame(
            currentToolbarAnimatedFrame(fallback: runtime.currentPresentation.frame),
            fallback: runtime.currentPresentation.frame
        )
        appendChromeBlocker(
            kind: .toolbar,
            rect: transitionFrame,
            to: &chromeBlockers
        )

        let chromeLayoutContext = CanvasChromeLayoutContext(
            safeBounds: toolbarLayoutSafeBounds(),
            toolbarPreferredPlacement: runtime.context.visibleSnapshot.state.placement,
            toolbarMeasuredSize: CanvasChromeLayoutGeometry.sanitizedSize(
                runtime.context.frames.visibleFrame.size
            ),
            chromeBlockers: chromeBlockers
        )
        return makeContextMenuLayoutContext(
            chromeLayoutContext: chromeLayoutContext,
            miniMapFrame: miniMapMountView.frame
        )
    }

    private func updateContextMenuLayout(
        using layoutContext: CanvasChromeLayoutContext
    ) {
        contextMenuHostView.updateLayout(layoutContext: layoutContext)
    }

    private func performContextMenuAction(_ actionID: CanvasContextMenuActionID) {
        guard let contextMenuState else {
            dismissContextMenu()
            return
        }

        switch actionID {
        case let .command(commandID):
            guard let command = contextMenuActionResolver.command(
                for: commandID,
                context: contextMenuState.resolvedContext
            ) else {
                dismissContextMenu()
                return
            }

            dismissContextMenu()
            performCommand(command)
        case let .uiAction(uiActionID):
            dismissContextMenu()
            performContextMenuUIAction(
                uiActionID,
                context: contextMenuState.resolvedContext
            )
        }
    }

    private func performContextMenuUIAction(
        _ actionID: CanvasContextMenuUIActionID,
        context: CanvasContextMenuContext
    ) {
        switch actionID {
        case .editVideoDisplayFrame:
            guard let itemID = targetVideoItemID(for: context) else {
                return
            }

            presentVideoDisplayFrameEditor(for: itemID)
        case .importGIFFrames:
            guard let itemID = targetGIFItemID(for: context) else {
                return
            }

            presentGIFFrameImportEditor(for: itemID)
        }
    }

    private func targetVideoItemID(
        for context: CanvasContextMenuContext
    ) -> CanvasItemID? {
        guard
            let itemID = context.targetItemID,
            let item = scene.item(withID: itemID),
            item.isVideo
        else {
            return nil
        }

        return itemID
    }

    private func targetGIFItemID(
        for context: CanvasContextMenuContext
    ) -> CanvasItemID? {
        guard
            let itemID = context.targetItemID,
            let item = scene.item(withID: itemID),
            item.isVideo == false,
            item.assetKind == .animatedGIF
        else {
            return nil
        }

        return itemID
    }

    private func presentVideoDisplayFrameEditor(for itemID: CanvasItemID) {
        guard presentedViewController == nil else {
            return
        }

        do {
            let editorContext = try editorSession.videoEditorContext(for: itemID)
            let editorViewController = iOSVideoDisplayFrameEditorViewController(
                editorContext: editorContext,
                loadTimelineStrip: { [weak self] request in
                    guard let self else {
                        throw iOSVideoEditorFlowError.presenterUnavailable
                    }

                    return try self.editorSession.videoTimelineStrip(
                        for: itemID,
                        request: request
                    )
                }
            ) { [weak self] frameImage in
                guard let self else {
                    throw iOSVideoEditorFlowError.presenterUnavailable
                }

                let updateResult = try self.editorSession.commitVideoPosterFrame(
                    withID: itemID,
                    frameImage: frameImage
                )
                self.requestCanvasRefresh(reason: updateResult.refreshReason)
            }
            present(editorViewController, animated: true)
        } catch {
            presentVideoEditorError(message: error.localizedDescription)
        }
    }

    private func presentGIFFrameImportEditor(for itemID: CanvasItemID) {
        guard presentedViewController == nil else {
            return
        }

        do {
            let editorContext = try editorSession.gifFrameImportEditorContext(
                for: itemID
            )
            let editorViewController = iOSGIFFrameImportViewController(
                editorContext: editorContext
            ) { [weak self] frameIndices in
                guard let self else {
                    throw iOSGIFFrameImportFlowError.presenterUnavailable
                }

                try self.performGIFFrameImport(
                    for: itemID,
                    frameIndices: frameIndices
                )
            }
            present(editorViewController, animated: true)
        } catch {
            presentGIFFrameImportEditorError(
                message: error.localizedDescription
            )
        }
    }

    private func performGIFFrameImport(
        for itemID: CanvasItemID,
        frameIndices: [Int]
    ) throws {
        let request = try editorSession.gifFrameImportRequest(
            for: itemID,
            frameIndices: frameIndices
        )
        performCommand(.importMedia(request))
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    override var keyCommands: [UIKeyCommand]? {
        let pasteCommand = UIKeyCommand(
            input: "v",
            modifierFlags: [.command],
            action: #selector(handlePasteKeyCommand(_:))
        )
        pasteCommand.discoverabilityTitle = "Paste Image"
        return [pasteCommand]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViewHierarchy()
        setupConstraints()
        updatePreparedToolbarPlacement()
        setupTextEditorOverlay()
        setupImportButton()
        setupSaveButton()
        setupCropButton()
        setupTextButton()
        setupUndoButton()
        setupRedoButton()
        setupBackButton()
        setupWorkspaceModeButton()
        setupMiniMapView()
        setupContextMenuHostView()
        restoreInitialBoardState()
        setupCanvasViewport()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        syncCameraViewportSizeIfNeeded(
            canvasViewportView.bounds.size,
            source: "controller layout fallback"
        )
        guard isToolbarTransitionActive == false else {
            markToolbarTransitionLayoutReconcilePending()
            return
        }
        updateChromeOverlayLayout()
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
        view.addSubview(chromeOverlayView)
        chromeOverlayView.addSubview(miniMapMountView)
        chromeOverlayView.addSubview(historyButtonsStackView)
        toolbarHostView.translatesAutoresizingMaskIntoConstraints = true
        chromeOverlayView.addSubview(toolbarHostView)
        chromeOverlayView.addSubview(textEditorOverlayView)
        chromeOverlayView.addSubview(contextMenuHostView)
        chromeOverlayView.addSubview(backButton)
        chromeOverlayView.addSubview(workspaceModeButton)
        installHistoryButtons()
        registerToolbarButtons()
    }

    private func setupConstraints() {
        let safeAreaLayoutGuide = chromeOverlayView.safeAreaLayoutGuide
        let preferredTextEditorWidth = textEditorOverlayView.widthAnchor.constraint(equalToConstant: 320)
        preferredTextEditorWidth.priority = .defaultHigh
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
            workspaceModeButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            workspaceModeButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
            workspaceModeButton.widthAnchor.constraint(equalToConstant: 44),
            workspaceModeButton.heightAnchor.constraint(equalToConstant: 44),
            textEditorOverlayView.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
            textEditorOverlayView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 76),
            textEditorOverlayView.leadingAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor, constant: 20),
            textEditorOverlayView.trailingAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            preferredTextEditorWidth,
            textEditorOverlayView.heightAnchor.constraint(equalToConstant: 148),
            historyButtonsStackView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            historyButtonsStackView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),
            undoButton.heightAnchor.constraint(equalToConstant: 40),
            redoButton.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    private func registerToolbarButtons() {
        toolbarHostView.registerButtons(toolbarButtonsByID)
    }

    private func installHistoryButtons() {
        historyButtons.forEach { button in
            historyButtonsStackView.addArrangedSubview(button)
        }
    }

    private func updatePreparedToolbarPlacement() {
        guard isToolbarTransitionActive == false else {
            markToolbarTransitionLayoutReconcilePending()
            return
        }

        renderToolbar()
        if view.bounds.isEmpty == false {
            view.layoutIfNeeded()
            updateChromeOverlayLayout()
        }
    }

    private func updateChromeOverlayLayout() {
        guard isToolbarTransitionActive == false else {
            markToolbarTransitionLayoutReconcilePending()
            return
        }

        let contextMenuLayoutContext = performOverlayLayoutPass()
        updateContextMenuLayout(using: contextMenuLayoutContext)
    }

    private func toolbarPreferredPlacement() -> CanvasToolbarPlacement {
        transientToolbarPlacement
    }

    private func performOverlayLayoutPass() -> CanvasChromeLayoutContext {
        let toolbarPlacementResult = CanvasToolbarPlacementPass.resolve(
            safeBounds: toolbarLayoutSafeBounds(),
            toolbarPreferredPlacement: toolbarPreferredPlacement(),
            toolbarMeasuredSize: measuredToolbarHostSize(),
            baseChromeBlockers: baseChromeBlockersForToolbarLayout(),
            scale: toolbarPlacementScale(),
            solver: toolbarPlacementSolver
        )
        applyToolbarFrame(toolbarPlacementResult.toolbarFrame)
        let miniMapFrame = resolveMiniMapFrame(
            in: toolbarPlacementResult.chromeLayoutContext
        )
        applyMiniMapFrame(miniMapFrame)
        return makeContextMenuLayoutContext(
            chromeLayoutContext: toolbarPlacementResult.chromeLayoutContext,
            miniMapFrame: miniMapFrame
        )
    }

    private func applyToolbarFrame(_ toolbarFrame: CGRect) {
        guard isToolbarTransitionActive == false else {
            markToolbarTransitionLayoutReconcilePending()
            return
        }

        if toolbarHostView.frame != toolbarFrame {
            toolbarHostView.frame = toolbarFrame
        }
    }

    private func toolbarLayoutSafeBounds() -> CGRect {
        chromeOverlayView.safeAreaLayoutGuide.layoutFrame
    }

    private func baseChromeBlockersForToolbarLayout() -> [CanvasChromeBlocker] {
        var chromeBlockers: [CanvasChromeBlocker] = []
        appendChromeBlocker(
            kind: .backButton,
            for: backButton,
            to: &chromeBlockers
        )
        appendChromeBlocker(
            kind: .modeToggle,
            for: workspaceModeButton,
            to: &chromeBlockers
        )
        appendChromeBlocker(
            kind: .historyButtons,
            for: historyButtonsStackView,
            to: &chromeBlockers
        )
        return chromeBlockers
    }

    private func resolveMiniMapFrame(
        in layoutContext: CanvasChromeLayoutContext
    ) -> CGRect {
        miniMapLayoutSolver.resolveMiniMapFrame(
            safeBounds: layoutContext.safeBounds,
            occupiedRects: layoutContext.occupiedRects,
            configuration: miniMapConfiguration
        )?.integral ?? .zero
    }

    private func applyMiniMapFrame(_ miniMapFrame: CGRect) {
        if miniMapMountView.frame != miniMapFrame {
            miniMapMountView.frame = miniMapFrame
        }
        miniMapMountView.isHidden = miniMapFrame.isEmpty
        if miniMapView.frame != miniMapMountView.bounds {
            miniMapView.frame = miniMapMountView.bounds
        }
    }

    private func makeContextMenuLayoutContext(
        chromeLayoutContext: CanvasChromeLayoutContext,
        miniMapFrame: CGRect
    ) -> CanvasChromeLayoutContext {
        var chromeBlockers = chromeLayoutContext.chromeBlockers.map { blocker in
            CanvasChromeBlocker(
                kind: blocker.kind,
                rect: convertToContextMenuHost(
                    blocker.rect,
                    from: chromeOverlayView
                )
            )
        }

        if let miniMapRect = CanvasChromeLayoutGeometry.sanitizedRect(
            miniMapFrame
        ) {
            chromeBlockers.append(
                CanvasChromeBlocker(
                    kind: .miniMap,
                    rect: convertToContextMenuHost(
                        miniMapRect,
                        from: chromeOverlayView
                    )
                )
            )
        }

        return CanvasChromeLayoutContext(
            safeBounds: convertToContextMenuHost(
                chromeLayoutContext.safeBounds,
                from: chromeOverlayView
            ),
            toolbarPreferredPlacement: chromeLayoutContext.toolbarPreferredPlacement,
            toolbarMeasuredSize: chromeLayoutContext.toolbarMeasuredSize,
            chromeBlockers: chromeBlockers
        )
    }

    private func appendChromeBlocker(
        kind: CanvasChromeBlockerKind,
        for view: UIView,
        to chromeBlockers: inout [CanvasChromeBlocker]
    ) {
        guard view.isHidden == false else {
            return
        }

        appendChromeBlocker(
            kind: kind,
            rect: view.frame,
            to: &chromeBlockers
        )
    }

    private func appendChromeBlocker(
        kind: CanvasChromeBlockerKind,
        rect: CGRect,
        to chromeBlockers: inout [CanvasChromeBlocker]
    ) {
        guard let standardizedRect = CanvasChromeLayoutGeometry.sanitizedRect(
            rect
        ) else {
            return
        }

        chromeBlockers.append(
            CanvasChromeBlocker(
                kind: kind,
                rect: standardizedRect
            )
        )
    }

    private func measuredToolbarHostSize() -> CGSize {
        CanvasChromeLayoutGeometry.sanitizedSize(
            toolbarHostView.measuredContentSize()
        )
    }

    private func toolbarPlacementScale() -> CGFloat {
        let scale = chromeOverlayView.window?.screen.scale
            ?? view.window?.screen.scale
            ?? UIScreen.main.scale
        return scale.isFinite && scale > 0 ? scale : 1
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
        from sourceView: UIView
    ) -> CGPoint {
        contextMenuHostView.convert(
            point,
            from: sourceView
        )
    }

    private func convertToContextMenuHost(
        _ rect: CGRect,
        from sourceView: UIView
    ) -> CGRect {
        contextMenuHostView.convert(
            rect,
            from: sourceView
        ).standardized
    }

    private func setupImportButton() {
        importButton.addTarget(self, action: #selector(handleImportButtonTap), for: .touchUpInside)
        renderToolbar()
    }

    private func setupTextEditorOverlay() {
        textEditorOverlayView.textView.delegate = self
        syncTextEditorPresentation()
    }

    private func setupSaveButton() {
        saveButton.addTarget(self, action: #selector(handleSaveButtonTap), for: .touchUpInside)
        renderToolbar()
    }

    private func setupCropButton() {
        cropButton.addTarget(self, action: #selector(handleCropButtonTap), for: .touchUpInside)
        updateInlineEditButtonsAppearance()
    }

    private func setupTextButton() {
        textButton.addTarget(self, action: #selector(handleTextButtonTap), for: .touchUpInside)
        updateInlineEditButtonsAppearance()
    }

    private func setupUndoButton() {
        undoButton.addTarget(self, action: #selector(handleUndoButtonTap), for: .touchUpInside)
        updateHistoryButtonsAppearance()
    }

    private func setupRedoButton() {
        redoButton.addTarget(self, action: #selector(handleRedoButtonTap), for: .touchUpInside)
        updateHistoryButtonsAppearance()
    }

    private func setupBackButton() {
        backButton.addTarget(self, action: #selector(handleBackButtonTap), for: .touchUpInside)
    }

    private func setupWorkspaceModeButton() {
        workspaceModeButton.addTarget(
            self,
            action: #selector(handleWorkspaceModeButtonTap),
            for: .touchUpInside
        )
        updateWorkspaceModeButtonAppearance()
    }

    private func updateWorkspaceModeButtonAppearance() {
        var configuration = workspaceModeButton.configuration ?? UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: workspaceMode.systemImageName)
        workspaceModeButton.configuration = configuration
        workspaceModeButton.accessibilityLabel = workspaceMode.accessibilityLabel
        workspaceModeButton.accessibilityValue = workspaceMode.accessibilityValue
    }

    private func setupMiniMapView() {
        miniMapView.frame = miniMapMountView.bounds
        miniMapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        miniMapView.onNavigate = { [weak self] point in
            self?.handleMiniMapNavigate(to: point)
        }
        miniMapMountView.addSubview(miniMapView)
    }

    private func setupContextMenuHostView() {
        contextMenuHostView.onDismissRequested = { [weak self] in
            self?.dismissContextMenu()
        }
        contextMenuHostView.onActionSelected = { [weak self] actionID in
            self?.performContextMenuAction(actionID)
        }
    }

    private func setupCanvasViewport() {
        canvasViewportView.shouldAutoplayAnimatedImages =
            editorSession.shouldAutoplayAnimatedImagesOnCanvas
        canvasViewportView.resolveAnimatedImagePlaybackSource = { [weak self] assetReference in
            self?.editorSession.animatedImagePlaybackSource(for: assetReference)
        }
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
        canvasViewportView.onLongPress = { [weak self] location in
            self?.handleLongPress(at: location)
        }
        canvasViewportView.onPan = { [weak self] translation in
            self?.handleIndirectPan(translation)
        }
        canvasViewportView.onZoom = { [weak self] scaleDelta, anchor in
            self?.handleZoom(scaleDelta, around: anchor)
        }
        canvasViewportView.onZoomGestureBegan = { [weak self] in
            self?.handleZoomGestureBegan()
        }
        canvasViewportView.onZoomGestureEnded = { [weak self] in
            self?.handleZoomGestureEnded()
        }
        canvasViewportView.onViewportSizeChange = { [weak self] viewportSize in
            self?.syncCameraViewportSizeIfNeeded(
                viewportSize,
                source: "viewport layout"
            )
        }
        canvasViewportView.addInteraction(
            UIDropInteraction(delegate: self)
        )

        installCanvasContentView(canvasViewportView)
        requestCanvasRefresh(reason: "initial setup")
    }

    private func handleZoomGestureBegan() {
        didMutateCameraDuringZoomGesture = false
    }

    private func handleZoomGestureEnded() {
        guard didMutateCameraDuringZoomGesture else {
            return
        }

        scheduleAutosave(reason: "zoom canvas")
        didMutateCameraDuringZoomGesture = false
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

        if workspaceMode == .editing, commitActiveTextEditIfNeeded() {
            return
        }

        if contextMenuState != nil {
            dismissContextMenu()
            return
        }

        let pressContext = resolvePointerPressContext(at: location)
        pointerDragState = .pressed(
            pressedLocation: location,
            pressContext: pressContext
        )
        beginPointerHistoryTransactionIfNeeded(for: pressContext)
    }

    private func handleLongPress(at location: CGPoint) {
        syncCameraViewportSizeFromCurrentBoundsIfPossible()
        guard hasRenderableViewportSize else {
            logIgnoredCanvasInput("long press \(describe(point: location))")
            return
        }

        guard isReadingModeActive == false else {
            dismissContextMenu()
            return
        }

        if commitActiveTextEditIfNeeded() {
            return
        }

        print(
            "[Canvas iOS][ContextMenuInput] " +
            "longPressLocation=\(describe(point: location)) " +
            "viewportBounds=\(describe(rect: canvasViewportView.bounds)) " +
            "viewportFrame=\(describe(rect: canvasViewportView.frame)) " +
            "overlayBounds=\(describe(rect: chromeOverlayView.bounds)) " +
            "overlayFrame=\(describe(rect: chromeOverlayView.frame))"
        )
        prepareForLongPressContextMenu()

        let resolvedContext = resolveContext(at: location)
        presentContextMenu(for: resolvedContext)
    }

    private func prepareForLongPressContextMenu() {
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
            // Reuse primary cancel semantics so long press never leaves a
            // half-committed drag/crop/rotate interaction behind.
            handlePrimaryPointerCancel()
        }
    }

    private func handlePrimaryPointerMove(to location: CGPoint, from previousLocation: CGPoint) {
        syncCameraViewportSizeFromCurrentBoundsIfPossible()
        guard hasRenderableViewportSize else {
            logIgnoredCanvasInput("pointer move \(describe(point: location))")
            return
        }

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
            case .cropTranslationArea:
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

            let clearedAlignmentInteractionState =
                clearAlignmentInteractionStateIfNeeded()
            let pressedItemID = pressContext.targetItemID
            let releasedContext = resolvePointerPressContext(at: location)
            let releasedItemID = releasedContext.targetItemID
            let previousSelectedItemID = interactionState.selectedItemID
            var clickTarget = "blank"
            var clickResult = "selection_unchanged"
            var affectedItemID: CanvasItemID?
            var didTriggerPressedRefresh = false

            switch pressContext.targetKind {
            case .rotateHandle:
                clickTarget = "rotate_handle"
                affectedItemID = pressContext.targetItemID
            case .cropHandle:
                clickTarget = "crop_handle"
                affectedItemID = pressContext.targetItemID
            case .cropTranslationArea:
                clickTarget = "crop_translation_area"
                affectedItemID = pressContext.targetItemID
            case .selectionHandle:
                clickTarget = "handle"
                affectedItemID = pressContext.targetItemID
            case .selectedItemBody, .unselectedItemBody:
                if let itemID = pressContext.targetItemID,
                   releasedItemID == itemID
                {
                    clickTarget = "item"
                    affectedItemID = itemID
                    selectItem(
                        withID: itemID,
                        recordHistory: true
                    )
                    if previousSelectedItemID != itemID {
                        clickResult = "item_selected"
                        didTriggerPressedRefresh = true
                    } else {
                        if case .selectedItemBody = pressContext.targetKind,
                           beginTextEditIfPossible(for: itemID)
                        {
                            clickResult = "text_edit_began"
                            didTriggerPressedRefresh = true
                        }
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
                        clickResult = "item_deselected"
                        didTriggerPressedRefresh = true
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
            if clearedAlignmentInteractionState, didTriggerPressedRefresh == false {
                requestCanvasRefresh(
                    reason: "clear alignment interaction on pointer up"
                )
            }
            editorSession.cancelPendingHistoryTransaction()
        case .rotatingSelectedItem:
            commitRotationDraftIfNeeded()
        case .croppingSelectedItem, .movingCropFrame:
            commitCropDraftIfNeeded()
        case .draggingSelectedItem:
            commitPendingPointerHistoryTransaction(autosaveReason: "move item")
            clearAlignmentInteractionStateIfNeeded(
                refreshReason: "finish move alignment interaction"
            )
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
                refreshReason: "cancel rotate interaction"
            )
        case .croppingSelectedItem, .movingCropFrame:
            commitCropDraftIfNeeded()
        case .draggingSelectedItem:
            commitPendingPointerHistoryTransaction(autosaveReason: "move item")
            clearAlignmentInteractionStateIfNeeded(
                refreshReason: "cancel move alignment interaction"
            )
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
        syncCameraViewportSizeFromCurrentBoundsIfPossible()
        guard hasRenderableViewportSize else {
            logIgnoredCanvasInput("indirect pan \(describe(point: translation))")
            return
        }

        if contextMenuState != nil {
            dismissContextMenu()
            return
        }

        guard case .idle = pointerDragState else {
            logIgnoredCanvasInput("indirect pan \(describe(point: translation)) while pointer interaction is active")
            return
        }

        applyCanvasPan(
            translation,
            refreshReason: "indirect pan \(describe(point: translation))"
        )
    }

    private func handleZoom(_ scaleDelta: CGFloat, around anchor: CGPoint) {
        let eventTime = ProcessInfo.processInfo.systemUptime
        syncCameraViewportSizeFromCurrentBoundsIfPossible()
        guard hasRenderableViewportSize else {
            logIgnoredCanvasInput(
                "zoom scaleDelta=\(String(format: "%.4f", scaleDelta)) anchor=\(describe(point: anchor))"
            )
            return
        }

        if contextMenuState != nil {
            dismissContextMenu()
            return
        }

        let zoomBefore = camera.zoomScale
        camera.zoom(by: scaleDelta, around: anchor)
        let zoomAfter = camera.zoomScale
        let afterZoomApply = ProcessInfo.processInfo.systemUptime
        guard zoomAfter != zoomBefore else {
            return
        }

        didMutateCameraDuringZoomGesture = true
        let refreshReason = "zoom scaleDelta=\(String(format: "%.4f", scaleDelta)) anchor=\(describe(point: anchor))"
        requestCanvasRefresh(reason: refreshReason)
        let afterRefresh = ProcessInfo.processInfo.systemUptime
        let afterAutosave = afterRefresh

        logZoomDispatch(
            eventTime: eventTime,
            scaleDelta: scaleDelta,
            anchor: anchor,
            zoomBefore: zoomBefore,
            zoomAfter: zoomAfter,
            applyCostMs: (afterZoomApply - eventTime) * 1000,
            refreshCostMs: (afterRefresh - afterZoomApply) * 1000,
            autosaveCostMs: (afterAutosave - afterRefresh) * 1000,
            totalCostMs: (afterAutosave - eventTime) * 1000
        )
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
        let refreshStart = ProcessInfo.processInfo.systemUptime
        let snapshot = editorSession.makeCanvasSnapshot()
        let afterSnapshotBuild = ProcessInfo.processInfo.systemUptime
        canvasViewportView.apply(snapshot)
        let afterViewportApply = ProcessInfo.processInfo.systemUptime
        refreshMiniMap()
        let afterMiniMapRefresh = ProcessInfo.processInfo.systemUptime

        logZoomRefreshIfNeeded(
            reason: reason,
            refreshStart: refreshStart,
            afterSnapshotBuild: afterSnapshotBuild,
            afterViewportApply: afterViewportApply,
            afterMiniMapRefresh: afterMiniMapRefresh,
            visibleItemCount: snapshot.items.count
        )
        logCanvasState(reason: reason, snapshot: snapshot)
    }

    private func refreshMiniMap() {
        let snapshot = editorSession.makeMiniMapSnapshot()
        miniMapView.apply(snapshot)
    }

    private func handleMiniMapNavigate(to miniMapPoint: CGPoint) {
        syncCameraViewportSizeFromCurrentBoundsIfPossible()
        guard let worldPoint = miniMapView.worldPoint(atMiniMapPoint: miniMapPoint) else {
            return
        }

        guard camera.center != worldPoint else {
            return
        }

        camera.center = worldPoint
        requestCanvasRefresh(reason: "navigate minimap to \(describe(point: worldPoint))")
        scheduleAutosave(reason: "navigate canvas via minimap")
    }

    @objc
    private func handleImportButtonTap() {
        guard isReadingModeActive == false else {
            return
        }

        commitActiveTextEditIfNeeded()
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 0

        let pickerViewController = PHPickerViewController(configuration: configuration)
        pickerViewController.delegate = self
        present(pickerViewController, animated: true)
    }

    @objc
    private func handleSaveButtonTap() {
        commitActiveTextEditIfNeeded()
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
                self.showSaveButtonFeedback(.success)
            case let .failure(error):
                if case FolderBookmarkStoreError.missingBookmarkData = error {
                    self.showSaveButtonFeedback(.missingFolder)
                    self.presentSaveError(
                        message: "Select a folder from the board list before saving."
                    )
                } else {
                    self.showSaveButtonFeedback(.failure)
                    self.presentSaveError(message: error.localizedDescription)
                }
            }
        }
    }

    @objc
    private func handleCropButtonTap() {
        performCommand(.crop)
    }

    @objc
    private func handleTextButtonTap() {
        if isInlineTextModeActive {
            performCommand(.commitTextEdit)
        } else {
            performCommand(.addTextItem)
        }
    }

    @objc
    private func handleUndoButtonTap() {
        performCommand(.undo)
    }

    @objc
    private func handleRedoButtonTap() {
        performCommand(.redo)
    }

    @objc
    private func handleBackButtonTap() {
        commitActiveTextEditIfNeeded()
        dismissContextMenu()
        onBackToBoardList?()
    }

    @objc
    private func handleWorkspaceModeButtonTap() {
        beginToolbarModeTransition(
            to: workspaceMode == .editing ? .toReading : .toEditing
        )
    }

    private func beginToolbarModeTransition(
        to direction: CanvasToolbarTransitionDirection
    ) {
        let targetMode = toolbarTargetWorkspaceMode(for: direction)
        if let runtime = toolbarTransitionRuntime,
           toolbarTargetWorkspaceMode(for: runtime.context.direction) == targetMode
        {
            return
        }

        dismissContextMenu()
        cancelAndRebaseToolbarTransitionIfNeeded(targetMode: targetMode)

        guard let context = prepareToolbarTransitionContext(direction: direction) else {
            toolbarTransitionAnimator?.stopAnimation(true)
            toolbarTransitionAnimator = nil
            toolbarTransitionRuntime = nil
            updatePreparedToolbarPlacement()
            return
        }

        let initialStage = initialToolbarTransitionStage(
            for: direction,
            context: context
        )
        let initialPresentation = CanvasToolbarTransitionGeometry.presentation(
            for: initialStage,
            context: context
        )

        toolbarTransitionRuntime = CanvasToolbarTransitionRuntime(
            context: context,
            stage: initialStage,
            currentPresentation: initialPresentation,
            pendingLayoutReconcile: true
        )
        toolbarHostView.renderTransition(initialPresentation)

        switch initialStage {
        case .collapsing, .expanding:
            runToolbarCollapsePhase()
        case .exiting, .entering:
            runToolbarSlidePhase()
        case .steadyVisible, .hidden:
            finishToolbarModeTransition(applying: context.settledState)
        }
    }

    private func prepareToolbarTransitionContext(
        direction: CanvasToolbarTransitionDirection
    ) -> CanvasToolbarTransitionContext? {
        let configuration = CanvasToolbarTransitionConfiguration()

        switch direction {
        case .toReading:
            let visibleState = makeToolbarState()
            let visibleFrame = currentToolbarTransitionStartFrame(
                fallbackState: visibleState
            )

            applyWorkspaceModeForToolbarTransition(to: .reading)

            let settledState = makeToolbarState()
            guard visibleState.items.isEmpty == false else {
                return nil
            }

            let collapsedFrame = CanvasToolbarTransitionGeometry.collapsedFrame(
                from: visibleFrame
            )
            let offscreenFrame = CanvasToolbarTransitionGeometry.offscreenFrame(
                from: collapsedFrame,
                safeBounds: toolbarLayoutSafeBounds()
            )

            return CanvasToolbarTransitionContext(
                direction: direction,
                visibleSnapshot: CanvasToolbarTransitionSnapshot(
                    state: visibleState,
                    frame: visibleFrame
                ),
                settledState: settledState,
                frames: CanvasToolbarTransitionFrames(
                    visibleFrame: visibleFrame,
                    collapsedFrame: collapsedFrame,
                    offscreenFrame: offscreenFrame
                ),
                configuration: configuration
            )

        case .toEditing:
            applyWorkspaceModeForToolbarTransition(to: .editing)

            let visibleState = makeToolbarState()
            guard visibleState.items.isEmpty == false else {
                return nil
            }

            let visibleFrame = resolvedSteadyToolbarFrame(for: visibleState)
            let collapsedFrame = CanvasToolbarTransitionGeometry.collapsedFrame(
                from: visibleFrame
            )
            let offscreenFrame = CanvasToolbarTransitionGeometry.offscreenFrame(
                from: collapsedFrame,
                safeBounds: toolbarLayoutSafeBounds()
            )

            return CanvasToolbarTransitionContext(
                direction: direction,
                visibleSnapshot: CanvasToolbarTransitionSnapshot(
                    state: visibleState,
                    frame: visibleFrame
                ),
                settledState: visibleState,
                frames: CanvasToolbarTransitionFrames(
                    visibleFrame: visibleFrame,
                    collapsedFrame: collapsedFrame,
                    offscreenFrame: offscreenFrame
                ),
                configuration: configuration
            )
        }
    }

    private func runToolbarCollapsePhase() {
        guard let runtime = toolbarTransitionRuntime else {
            return
        }

        let targetStage: CanvasToolbarTransitionStage
        let completion: () -> Void

        switch runtime.context.direction {
        case .toReading:
            targetStage = .collapsing(progress: 1)
            completion = { [weak self] in
                self?.runToolbarSlidePhase()
            }
        case .toEditing:
            targetStage = .expanding(progress: 1)
            completion = { [weak self] in
                guard let self else {
                    return
                }
                self.finishToolbarModeTransition(
                    applying: runtime.context.settledState
                )
            }
        }

        animateToolbarTransition(
            to: targetStage,
            duration: remainingToolbarTransitionDuration(
                fullDuration: runtime.context.configuration.collapseDuration,
                currentStage: runtime.stage,
                targetStage: targetStage
            ),
            completion: completion
        )
    }

    private func runToolbarSlidePhase() {
        guard let runtime = toolbarTransitionRuntime else {
            return
        }

        let targetStage: CanvasToolbarTransitionStage
        let completion: () -> Void

        switch runtime.context.direction {
        case .toReading:
            targetStage = .exiting(progress: 1)
            completion = { [weak self] in
                guard let self else {
                    return
                }
                self.finishToolbarModeTransition(
                    applying: runtime.context.settledState
                )
            }
        case .toEditing:
            targetStage = .entering(progress: 1)
            completion = { [weak self] in
                self?.runToolbarCollapsePhase()
            }
        }

        animateToolbarTransition(
            to: targetStage,
            duration: remainingToolbarTransitionDuration(
                fullDuration: runtime.context.configuration.slideDuration,
                currentStage: runtime.stage,
                targetStage: targetStage
            ),
            completion: completion
        )
    }

    private func finishToolbarModeTransition(
        applying settledState: CanvasToolbarState
    ) {
        let pendingLayoutReconcile = toolbarTransitionRuntime?.pendingLayoutReconcile
            ?? true
        toolbarTransitionAnimator = nil
        toolbarTransitionRuntime = nil
        toolbarHostView.completeTransition(applying: settledState)
        if pendingLayoutReconcile {
            updatePreparedToolbarPlacement()
        }
    }

    private func cancelAndRebaseToolbarTransitionIfNeeded(
        targetMode: CanvasWorkspaceMode
    ) {
        guard var runtime = toolbarTransitionRuntime else {
            return
        }

        guard
            toolbarTargetWorkspaceMode(for: runtime.context.direction) != targetMode
        else {
            return
        }

        runtime.currentPresentation = inferredCurrentToolbarTransitionPresentation(
            from: runtime
        )
        runtime.pendingLayoutReconcile = true
        toolbarTransitionRuntime = runtime

        toolbarTransitionAnimator?.stopAnimation(true)
        toolbarTransitionAnimator = nil
        toolbarHostView.renderTransition(runtime.currentPresentation)
    }

    private func animateToolbarTransition(
        to targetStage: CanvasToolbarTransitionStage,
        duration: TimeInterval,
        completion: @escaping () -> Void
    ) {
        guard var runtime = toolbarTransitionRuntime else {
            return
        }

        let targetPresentation = CanvasToolbarTransitionGeometry.presentation(
            for: targetStage,
            context: runtime.context
        )
        runtime.stage = targetStage
        runtime.currentPresentation = targetPresentation
        toolbarTransitionRuntime = runtime

        if duration <= 0 {
            toolbarHostView.renderTransition(targetPresentation)
            completion()
            return
        }

        let animator = UIViewPropertyAnimator(
            duration: duration,
            curve: .easeInOut
        ) { [weak self] in
            self?.toolbarHostView.renderTransition(targetPresentation)
        }
        animator.addCompletion { [weak self] position in
            guard let self else {
                return
            }
            guard self.toolbarTransitionAnimator === animator else {
                return
            }

            self.toolbarTransitionAnimator = nil
            guard position == .end else {
                return
            }

            completion()
        }

        toolbarTransitionAnimator?.stopAnimation(true)
        toolbarTransitionAnimator = animator
        animator.startAnimation()
    }

    private func applyWorkspaceModeForToolbarTransition(
        to targetMode: CanvasWorkspaceMode
    ) {
        workspaceMode = targetMode
        updateWorkspaceModeButtonAppearance()
        updateHistoryButtonsAppearance()
        syncTextEditorPresentation()
        requestCanvasRefresh(reason: "toggle workspace mode")
        scheduleAutosave(reason: "toggle workspace mode")
    }

    private func toolbarTargetWorkspaceMode(
        for direction: CanvasToolbarTransitionDirection
    ) -> CanvasWorkspaceMode {
        switch direction {
        case .toReading:
            return .reading
        case .toEditing:
            return .editing
        }
    }

    private func markToolbarTransitionLayoutReconcilePending() {
        guard var runtime = toolbarTransitionRuntime else {
            return
        }

        runtime.pendingLayoutReconcile = true
        toolbarTransitionRuntime = runtime
    }

    private func initialToolbarTransitionStage(
        for direction: CanvasToolbarTransitionDirection,
        context: CanvasToolbarTransitionContext
    ) -> CanvasToolbarTransitionStage {
        guard let currentPresentation = toolbarTransitionRuntime?.currentPresentation else {
            switch direction {
            case .toReading:
                return .collapsing(progress: 0)
            case .toEditing:
                return .entering(progress: 0)
            }
        }

        let currentFrame = normalizedToolbarFrame(
            currentPresentation.frame,
            fallback: context.frames.visibleFrame
        )
        let collapsedFrame = normalizedToolbarFrame(
            context.frames.collapsedFrame,
            fallback: currentFrame
        )

        switch direction {
        case .toReading:
            let isCollapsed = currentFrame.height <= (collapsedFrame.height + 0.5)
            if isCollapsed {
                return .exiting(
                    progress: toolbarLinearProgress(
                        from: collapsedFrame.minX,
                        to: context.frames.offscreenFrame.minX,
                        current: currentFrame.minX
                    )
                )
            }

            return .collapsing(progress: 0)

        case .toEditing:
            if currentFrame.height > (collapsedFrame.height + 0.5) {
                let expandingProgress = toolbarLinearProgress(
                    from: collapsedFrame.height,
                    to: context.frames.visibleFrame.height,
                    current: currentFrame.height
                )
                if expandingProgress >= 0.999 {
                    return .steadyVisible
                }

                return .expanding(progress: expandingProgress)
            }

            let enteringProgress = toolbarLinearProgress(
                from: context.frames.offscreenFrame.minX,
                to: collapsedFrame.minX,
                current: currentFrame.minX
            )
            if enteringProgress >= 0.999 {
                return .expanding(progress: 0)
            }

            return .entering(progress: enteringProgress)
        }
    }

    private func inferredCurrentToolbarTransitionPresentation(
        from runtime: CanvasToolbarTransitionRuntime
    ) -> CanvasToolbarTransitionPresentation {
        let currentFrame = currentToolbarAnimatedFrame(
            fallback: runtime.currentPresentation.frame
        )

        switch runtime.stage {
        case .steadyVisible:
            return CanvasToolbarTransitionGeometry.presentation(
                for: .steadyVisible,
                context: runtime.context
            )
        case .hidden:
            return CanvasToolbarTransitionGeometry.presentation(
                for: .hidden,
                context: runtime.context
            )
        case .collapsing:
            return CanvasToolbarTransitionGeometry.presentation(
                for: .collapsing(
                    progress: toolbarLinearProgress(
                        from: runtime.context.frames.visibleFrame.height,
                        to: runtime.context.frames.collapsedFrame.height,
                        current: currentFrame.height
                    )
                ),
                context: runtime.context
            )
        case .exiting:
            return CanvasToolbarTransitionGeometry.presentation(
                for: .exiting(
                    progress: toolbarLinearProgress(
                        from: runtime.context.frames.collapsedFrame.minX,
                        to: runtime.context.frames.offscreenFrame.minX,
                        current: currentFrame.minX
                    )
                ),
                context: runtime.context
            )
        case .entering:
            return CanvasToolbarTransitionGeometry.presentation(
                for: .entering(
                    progress: toolbarLinearProgress(
                        from: runtime.context.frames.offscreenFrame.minX,
                        to: runtime.context.frames.collapsedFrame.minX,
                        current: currentFrame.minX
                    )
                ),
                context: runtime.context
            )
        case .expanding:
            return CanvasToolbarTransitionGeometry.presentation(
                for: .expanding(
                    progress: toolbarLinearProgress(
                        from: runtime.context.frames.collapsedFrame.height,
                        to: runtime.context.frames.visibleFrame.height,
                        current: currentFrame.height
                    )
                ),
                context: runtime.context
            )
        }
    }

    private func remainingToolbarTransitionDuration(
        fullDuration: TimeInterval,
        currentStage: CanvasToolbarTransitionStage,
        targetStage: CanvasToolbarTransitionStage
    ) -> TimeInterval {
        let progress: CGFloat
        switch (currentStage, targetStage) {
        case let (.collapsing(currentProgress), .collapsing),
             let (.exiting(currentProgress), .exiting),
             let (.entering(currentProgress), .entering),
             let (.expanding(currentProgress), .expanding):
            progress = clampedToolbarTransitionProgress(currentProgress)
        default:
            progress = 0
        }

        return max(fullDuration * TimeInterval(1 - progress), 0)
    }

    private func currentToolbarTransitionStartFrame(
        fallbackState: CanvasToolbarState
    ) -> CGRect {
        if let runtime = toolbarTransitionRuntime,
           let runtimeFrame = CanvasChromeLayoutGeometry.sanitizedRect(
               runtime.currentPresentation.frame
           ),
           runtimeFrame.isEmpty == false
        {
            return runtimeFrame
        }

        if let currentFrame = CanvasChromeLayoutGeometry.sanitizedRect(
            toolbarHostView.frame
        ),
           currentFrame.isEmpty == false
        {
            return currentFrame
        }

        return resolvedSteadyToolbarFrame(for: fallbackState)
    }

    private func currentToolbarAnimatedFrame(fallback: CGRect) -> CGRect {
        if let animatedFrame = toolbarHostView.layer.presentation()?.frame,
           let sanitizedAnimatedFrame = CanvasChromeLayoutGeometry.sanitizedRect(
               animatedFrame
           )
        {
            return sanitizedAnimatedFrame
        }

        if let currentFrame = CanvasChromeLayoutGeometry.sanitizedRect(
            toolbarHostView.frame
        ) {
            return currentFrame
        }

        return normalizedToolbarFrame(fallback, fallback: fallback)
    }

    private func normalizedToolbarFrame(
        _ frame: CGRect,
        fallback: CGRect
    ) -> CGRect {
        CanvasChromeLayoutGeometry.sanitizedRect(frame)
            ?? CanvasChromeLayoutGeometry.sanitizedRect(fallback)
            ?? fallback.standardized
    }

    private func resolvedSteadyToolbarFrame(
        for state: CanvasToolbarState
    ) -> CGRect {
        let placementResult = CanvasToolbarPlacementPass.resolve(
            safeBounds: toolbarLayoutSafeBounds(),
            toolbarPreferredPlacement: state.placement,
            toolbarMeasuredSize: measuredToolbarHostSize(for: state),
            baseChromeBlockers: baseChromeBlockersForToolbarLayout(),
            scale: toolbarPlacementScale(),
            solver: toolbarPlacementSolver
        )

        return normalizedToolbarFrame(
            placementResult.toolbarFrame,
            fallback: placementResult.toolbarFrame
        )
    }

    private func measuredToolbarHostSize(
        for state: CanvasToolbarState
    ) -> CGSize {
        guard state.items.isEmpty == false else {
            return .zero
        }

        let itemCount = CGFloat(state.items.count)
        let stackedLength = (itemCount * CanvasToolbarChromeMetrics.buttonEdge)
            + (max(itemCount - 1, 0) * CanvasToolbarChromeMetrics.spacing)
        let measuredStackSize: CGSize

        switch state.preferredAxis {
        case .horizontal:
            measuredStackSize = CGSize(
                width: stackedLength,
                height: CanvasToolbarChromeMetrics.buttonEdge
            )
        case .vertical:
            measuredStackSize = CGSize(
                width: CanvasToolbarChromeMetrics.buttonEdge,
                height: stackedLength
            )
        }

        return CanvasChromeLayoutGeometry.sanitizedSize(
            CanvasToolbarMeasurement.measuredContentSize(
                forMeasuredStackSize: measuredStackSize
            )
        )
    }

    private func toolbarLinearProgress(
        from start: CGFloat,
        to end: CGFloat,
        current: CGFloat
    ) -> CGFloat {
        guard start.isFinite, end.isFinite, current.isFinite else {
            return 0
        }

        let delta = end - start
        guard delta != 0 else {
            return 0
        }

        return clampedToolbarTransitionProgress((current - start) / delta)
    }

    private func clampedToolbarTransitionProgress(_ progress: CGFloat) -> CGFloat {
        min(max(progress, 0), 1)
    }

    @objc
    private func handlePasteKeyCommand(_ sender: UIKeyCommand) {
        handlePasteRequest()
    }

    func dropInteraction(
        _ interaction: UIDropInteraction,
        canHandle session: UIDropSession
    ) -> Bool {
        isReadingModeActive == false &&
            iOSCanvasImportAdapter.canResolveTransfer(from: session)
    }

    func dropInteraction(
        _ interaction: UIDropInteraction,
        sessionDidUpdate session: UIDropSession
    ) -> UIDropProposal {
        if isReadingModeActive == false,
           iOSCanvasImportAdapter.canResolveTransfer(from: session)
        {
            return UIDropProposal(operation: .copy)
        }

        return UIDropProposal(operation: .cancel)
    }

    func dropInteraction(
        _ interaction: UIDropInteraction,
        performDrop session: UIDropSession
    ) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            guard self.isReadingModeActive == false else {
                return
            }

            guard let transferRequest = await iOSCanvasImportAdapter.transferRequest(
                from: session,
                sourceDescription: "drag and drop"
            ) else {
                return
            }

            _ = self.performTransferRequest(transferRequest)
            self.becomeFirstResponder()
        }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        guard results.isEmpty == false, isReadingModeActive == false else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            guard let transferRequest = await iOSCanvasImportAdapter.transferRequest(
                from: results,
                sourceDescription: "photo picker"
            ) else {
                return
            }

            _ = self.performTransferRequest(transferRequest)
            self.becomeFirstResponder()
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        guard
            textView === textEditorOverlayView.textView,
            isSyncingTextEditorContent == false,
            editorSession.updateTextEditDraft(textView.text)
        else {
            return
        }

        requestCanvasRefresh(reason: "update text edit draft")
    }

    private func canTransferContent(from pasteboard: UIPasteboard) -> Bool {
        isReadingModeActive == false &&
            iOSCanvasImportAdapter.canResolveTransfer(from: pasteboard)
    }

    private func handlePasteRequest() {
        guard canTransferContent(from: .general) else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            guard let transferRequest = await iOSCanvasImportAdapter.transferRequest(
                from: .general,
                sourceDescription: "pasteboard"
            ) else {
                return
            }

            _ = self.performTransferRequest(transferRequest)
            self.becomeFirstResponder()
        }
    }

    @discardableResult
    private func performTransferRequest(
        _ request: CanvasTransferRequest
    ) -> Bool {
        guard isReadingModeActive == false else {
            return false
        }

        do {
            guard let importRequest = try buildImportRequest(
                from: request
            ),
            let command = CanvasTransferCommandLowerer.loweredCommand(
                for: importRequest
            ) else {
                return false
            }

            performCommand(command)
            return true
        } catch {
            handleImportError(error)
            return false
        }
    }

    private func buildImportRequest(
        from request: CanvasTransferRequest
    ) throws -> CanvasImportRequest? {
        let boardID: UUID?
        if request.containsVideo {
            guard editorSession.ensureActiveBoardIdentityIfNeeded() else {
                return nil
            }

            boardID = editorSession.activeBoardID
        } else {
            boardID = nil
        }

        return try CanvasMediaImportService.makeImportRequest(
            from: request,
            boardID: boardID
        )
    }

    private func handleImportError(
        _ error: Error
    ) {
        if case FolderBookmarkStoreError.missingBookmarkData = error {
            showSaveButtonFeedback(.missingFolder)
            presentImportError(
                message: "Select a folder from the board list before importing videos."
            )
            return
        }

        presentImportError(message: error.localizedDescription)
    }

    private func selectItem(
        withID itemID: CanvasItemID,
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
        pressedItemID: CanvasItemID?,
        releasedItemID: CanvasItemID?,
        previousSelectedItemID: CanvasItemID?,
        currentSelectedItemID: CanvasItemID?,
        affectedItemID: CanvasItemID?
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

    private func makePointerRotateState(
        itemID: CanvasItemID,
        initialViewportLocation: CGPoint
    ) -> PointerRotateState? {
        guard
            inlineEditState == nil,
            let item = scene.boardItem(withID: itemID)
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
        requestCanvasRefresh(reason: "update crop draft")
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
        requestCanvasRefresh(reason: "update crop draft")
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
        requestCanvasRefresh(reason: "commit crop item")
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
            let item = scene.boardItem(withID: rotateState.itemID)
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
        requestCanvasRefresh(reason: "update rotate draft")
    }

    private func commitRotationDraftIfNeeded() {
        guard
            let rotationPreviewState,
            let item = scene.boardItem(withID: rotationPreviewState.itemID)
        else {
            cancelRotationInteractionIfNeeded(
                refreshReason: "discard rotate interaction"
            )
            return
        }

        guard !anglesMatch(item.rotationRadians, rotationPreviewState.draftRotationRadians) else {
            cancelRotationInteractionIfNeeded(
                refreshReason: "discard unchanged rotate interaction"
            )
            return
        }

        guard let rotatedItem = scene.rotateBoardItem(
            withID: rotationPreviewState.itemID,
            to: rotationPreviewState.draftRotationRadians
        ) else {
            cancelRotationInteractionIfNeeded(
                refreshReason: "discard failed rotate interaction"
            )
            return
        }

        expandBoardIfNeeded(toInclude: rotatedItem.worldBounds)
        clearRotationTransientState()
        requestCanvasRefresh(reason: "commit rotate item")
        commitPendingPointerHistoryTransaction(autosaveReason: "rotate item")
    }

    private func displayedRotationRadians(for item: CanvasBoardItem) -> CGFloat {
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

    private func beginRotationInteraction(for itemID: CanvasItemID) {
        guard rotationInteractionState?.itemID != itemID else {
            return
        }

        rotationInteractionState = CanvasRotationInteractionState(itemID: itemID)
        requestCanvasRefresh(reason: "begin rotate interaction")
    }

    private func clearRotationInteractionState() {
        rotationInteractionState = nil
    }

    @discardableResult
    private func clearAlignmentInteractionStateIfNeeded(
        refreshReason: String? = nil
    ) -> Bool {
        guard alignmentInteractionState != nil else {
            return false
        }

        alignmentInteractionState = nil
        if let refreshReason {
            requestCanvasRefresh(reason: refreshReason)
        }
        return true
    }

    private func cancelRotationInteractionIfNeeded(
        resetPointerDragState: Bool = false,
        refreshReason: String? = nil
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

        if hadVisibleRotationState, let refreshReason {
            requestCanvasRefresh(reason: refreshReason)
        }
    }

    private func moveSelectedItem(
        withID itemID: CanvasItemID,
        from previousLocation: CGPoint,
        to location: CGPoint
    ) {
        guard let movingItem = scene.boardItem(withID: itemID) else {
            clearAlignmentInteractionStateIfNeeded(
                refreshReason: "clear missing alignment interaction item"
            )
            return
        }

        let previousWorldLocation = camera.viewportToWorld(previousLocation)
        let currentWorldLocation = camera.viewportToWorld(location)
        let rawDeltaInWorld = CGPoint(
            x: currentWorldLocation.x - previousWorldLocation.x,
            y: currentWorldLocation.y - previousWorldLocation.y
        )
        guard rawDeltaInWorld != .zero else {
            return
        }

        let proposedCenter = CGPoint(
            x: movingItem.center.x + rawDeltaInWorld.x,
            y: movingItem.center.y + rawDeltaInWorld.y
        )
        let solveResult = alignmentGuideSolver.solve(
            CanvasAlignmentSolveRequest(
                movingItemID: itemID,
                proposedCenter: proposedCenter,
                scene: scene,
                boardState: boardState,
                camera: camera
            )
        )
        let resolvedDeltaInWorld = CGPoint(
            x: solveResult.resolvedCenter.x - movingItem.center.x,
            y: solveResult.resolvedCenter.y - movingItem.center.y
        )

        alignmentInteractionState = solveResult.interactionState
        scene.moveItem(withID: itemID, by: resolvedDeltaInWorld)
        if let movedItem = scene.boardItem(withID: itemID) {
            expandBoardIfNeeded(toInclude: movedItem.worldBounds)
        }
        requestCanvasRefresh(
            reason: "move selected item by \(describe(point: resolvedDeltaInWorld))"
        )
    }

    private func makePointerResizeState(
        itemID: CanvasItemID,
        handleRole: CanvasSelectionHandleRole
    ) -> PointerResizeState? {
        guard let item = scene.boardItem(withID: itemID) else {
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
            let currentItem = scene.boardItem(withID: resizeState.itemID)
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

        guard let resizedItem = scene.resizeBoardItem(
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
        applyCanvasPan(
            translation,
            refreshReason: "pan \(describe(point: translation))"
        )
    }

    private func applyCanvasPan(
        _ translation: CGPoint,
        refreshReason: String
    ) {
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
        requestCanvasRefresh(reason: refreshReason)
        scheduleAutosave(reason: "pan canvas")
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
        do {
            try editorSession.loadBoard(id: boardID)
        } catch {
            print(
                "[Canvas iOS][RuntimeRestore] " +
                "action=controllerLoadBoard.failed " +
                "boardID=\(boardID.uuidString) " +
                "error=\(error)"
            )
        }
        updateWorkspaceModeButtonAppearance()
        updateInlineEditButtonsAppearance()
    }

    private func startNewBoard() {
        editorSession.startNewBoard()
        updateWorkspaceModeButtonAppearance()
        updateInlineEditButtonsAppearance()
    }

    private func restorePersistedBoardIfPossible() {
        editorSession.restorePersistedBoardIfPossible()
        updateWorkspaceModeButtonAppearance()
        updateInlineEditButtonsAppearance()
    }

    private func applyBoardRuntimeState(_ runtimeState: BoardRuntimeState) {
        cancelRotationInteractionIfNeeded(resetPointerDragState: true)
        editorSession.applyBoardRuntimeState(runtimeState)
        updateWorkspaceModeButtonAppearance()
        updateInlineEditButtonsAppearance()
    }

    private func currentBoardHistorySnapshot() -> BoardHistorySnapshot {
        editorSession.currentBoardHistorySnapshot()
    }

    private func beginPointerHistoryTransactionIfNeeded(
        for pressContext: CanvasPointerPressContext
    ) {
        let reason: String
        switch pressContext.targetKind {
        case .rotateHandle:
            reason = "rotate item"
        case .cropHandle, .cropTranslationArea:
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
        updateHistoryButtonsAppearance()
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
        updateHistoryButtonsAppearance()
    }

    private var isInlineEditModeActive: Bool {
        editorSession.isInlineEditModeActive
    }

    private var workspaceMode: CanvasWorkspaceMode {
        get { editorSession.workspaceMode }
        set { editorSession.workspaceMode = newValue }
    }

    private var presentationInlineEditState: CanvasInlineEditState? {
        editorSession.presentationInlineEditState
    }

    private var isReadingModeActive: Bool {
        editorSession.isReadingModeActive
    }

    private var isInlineTextModeActive: Bool {
        editorSession.isInlineTextModeActive
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
        saveButtonState = .saving
    }

    private func showSaveButtonFeedback(_ state: CanvasSaveState) {
        saveButtonState = state
        saveButtonResetWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.applyDefaultSaveButtonAppearance()
        }
        saveButtonResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }

    private func applyDefaultSaveButtonAppearance() {
        saveButtonState = .idle
    }

    @discardableResult
    private func commitActiveTextEditIfNeeded() -> Bool {
        guard isInlineTextModeActive else {
            return false
        }

        performCommand(.commitTextEdit)
        return true
    }

    private func beginTextEditIfPossible(for itemID: CanvasItemID) -> Bool {
        guard isReadingModeActive == false else {
            return false
        }

        guard scene.textItem(withID: itemID) != nil else {
            return false
        }

        performCommand(.beginTextEdit(itemID: itemID))
        return isInlineTextModeActive
    }

    private func syncTextEditorPresentation() {
        guard isViewLoaded else {
            return
        }

        guard
            let inlineEditState = presentationInlineEditState,
            inlineEditState.mode == .text
        else {
            if textEditorOverlayView.textView.isFirstResponder {
                textEditorOverlayView.textView.resignFirstResponder()
            }
            textEditorOverlayView.isHidden = true
            activeTextEditorItemID = nil
            becomeFirstResponder()
            return
        }

        let didChangeEditedItem = activeTextEditorItemID != inlineEditState.itemID
        activeTextEditorItemID = inlineEditState.itemID
        textEditorOverlayView.isHidden = false
        if textEditorOverlayView.textView.text != inlineEditState.draftText {
            isSyncingTextEditorContent = true
            textEditorOverlayView.apply(text: inlineEditState.draftText)
            isSyncingTextEditorContent = false
        }

        guard textEditorOverlayView.window != nil else {
            return
        }

        if textEditorOverlayView.textView.isFirstResponder == false {
            textEditorOverlayView.textView.becomeFirstResponder()
        }

        if didChangeEditedItem {
            let textLength = textEditorOverlayView.textView.text.utf16.count
            textEditorOverlayView.textView.selectedRange = NSRange(
                location: 0,
                length: textLength
            )
        }
    }

    private func makeToolbarState() -> CanvasToolbarState {
        toolbarStateBuilder.mainToolbarState(
            session: editorSession,
            saveState: saveButtonState,
            placement: toolbarPreferredPlacement()
        )
    }

    private func renderToolbar() {
        guard isViewLoaded else {
            return
        }

        guard isToolbarTransitionActive == false else {
            markToolbarTransitionLayoutReconcilePending()
            return
        }

        toolbarHostView.render(makeToolbarState())
    }

    private func updateInlineEditButtonsAppearance() {
        updateHistoryButtonsAppearance()
        updatePreparedToolbarPlacement()
        syncTextEditorPresentation()
    }

    private func updateHistoryButtonsAppearance() {
        historyButtonsStackView.isHidden = isReadingModeActive
        updateUndoButtonAppearance()
        updateRedoButtonAppearance()
    }

    private func updateUndoButtonAppearance() {
        let descriptor = commandDescriptor(for: .undo)
        applyUndoButtonAppearance(
            title: descriptor.title,
            systemImageName: descriptor.systemImageName,
            backgroundColor: .systemBlue,
            isEnabled: descriptor.isEnabled
        )
    }

    private func updateRedoButtonAppearance() {
        let descriptor = commandDescriptor(for: .redo)
        applyRedoButtonAppearance(
            title: descriptor.title,
            systemImageName: descriptor.systemImageName,
            backgroundColor: .systemIndigo,
            isEnabled: descriptor.isEnabled
        )
    }

    private func applyUndoButtonAppearance(
        title: String,
        systemImageName: String,
        backgroundColor: UIColor,
        isEnabled: Bool
    ) {
        undoButton.isEnabled = isEnabled
        var configuration = undoButton.configuration ?? UIButton.Configuration.filled()
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        configuration.imagePlacement = .leading
        configuration.imagePadding = 6
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = .white
        configuration.title = title
        configuration.image = UIImage(systemName: systemImageName)
        configuration.baseBackgroundColor = isEnabled ? backgroundColor : .systemGray3
        undoButton.configuration = configuration
    }

    private func applyRedoButtonAppearance(
        title: String,
        systemImageName: String,
        backgroundColor: UIColor,
        isEnabled: Bool
    ) {
        redoButton.isEnabled = isEnabled
        var configuration = redoButton.configuration ?? UIButton.Configuration.filled()
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        configuration.imagePlacement = .leading
        configuration.imagePadding = 6
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = .white
        configuration.title = title
        configuration.image = UIImage(systemName: systemImageName)
        configuration.baseBackgroundColor = isEnabled ? backgroundColor : .systemGray3
        redoButton.configuration = configuration
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

    private func presentImportError(message: String) {
        let alertController = UIAlertController(
            title: "Unable to Import Media",
            message: message,
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        present(alertController, animated: true)
    }

    private func presentVideoEditorError(message: String) {
        let alertController = UIAlertController(
            title: "Unable to Open Video Editor",
            message: message,
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        present(alertController, animated: true)
    }

    private func presentGIFFrameImportEditorError(message: String) {
        let alertController = UIAlertController(
            title: "Unable to Open GIF Frame Importer",
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

    private func logZoomDispatch(
        eventTime: TimeInterval,
        scaleDelta: CGFloat,
        anchor: CGPoint,
        zoomBefore: CGFloat,
        zoomAfter: CGFloat,
        applyCostMs: TimeInterval,
        refreshCostMs: TimeInterval,
        autosaveCostMs: TimeInterval,
        totalCostMs: TimeInterval
    ) {
        guard Self.isPinchZoomDiagnosticLoggingEnabled else {
            return
        }

        let deltaSinceLastEventMs = lastZoomDispatchTimestamp.map { (eventTime - $0) * 1000 } ?? 0
        lastZoomDispatchTimestamp = eventTime

        print(
            "[Canvas iOS][ControllerZoom] " +
            "t=\(String(format: "%.6f", eventTime)) " +
            "dtMs=\(String(format: "%.3f", deltaSinceLastEventMs)) " +
            "scaleDelta=\(String(format: "%.6f", scaleDelta)) " +
            "anchor=\(describe(point: anchor)) " +
            "zoomBefore=\(String(format: "%.6f", zoomBefore)) " +
            "zoomAfter=\(String(format: "%.6f", zoomAfter)) " +
            "applyMs=\(String(format: "%.3f", applyCostMs)) " +
            "refreshMs=\(String(format: "%.3f", refreshCostMs)) " +
            "autosaveMs=\(String(format: "%.3f", autosaveCostMs)) " +
            "totalMs=\(String(format: "%.3f", totalCostMs))"
        )
    }

    private func logZoomRefreshIfNeeded(
        reason: String,
        refreshStart: TimeInterval,
        afterSnapshotBuild: TimeInterval,
        afterViewportApply: TimeInterval,
        afterMiniMapRefresh: TimeInterval,
        visibleItemCount: Int
    ) {
        guard
            Self.isPinchZoomDiagnosticLoggingEnabled,
            reason.hasPrefix("zoom scaleDelta=")
        else {
            return
        }

        let deltaSinceLastRefreshMs = lastZoomRefreshTimestamp.map {
            (refreshStart - $0) * 1000
        } ?? 0
        lastZoomRefreshTimestamp = refreshStart

        print(
            "[Canvas iOS][RenderZoom] " +
            "t=\(String(format: "%.6f", refreshStart)) " +
            "dtMs=\(String(format: "%.3f", deltaSinceLastRefreshMs)) " +
            "snapshotMs=\(String(format: "%.3f", (afterSnapshotBuild - refreshStart) * 1000)) " +
            "applyMs=\(String(format: "%.3f", (afterViewportApply - afterSnapshotBuild) * 1000)) " +
            "miniMapMs=\(String(format: "%.3f", (afterMiniMapRefresh - afterViewportApply) * 1000)) " +
            "totalMs=\(String(format: "%.3f", (afterMiniMapRefresh - refreshStart) * 1000)) " +
            "zoom=\(String(format: "%.6f", camera.zoomScale)) " +
            "visibleItems=\(visibleItemCount) " +
            "reason=\(reason)"
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

    private func describe(itemID: CanvasItemID?) -> String {
        itemID?.uuidString ?? "nil"
    }

    private func logContextMenuPresentation(
        state: CanvasContextMenuState,
        layoutContext: CanvasChromeLayoutContext
    ) {
        let occupiedRectsDescription = layoutContext.occupiedRects
            .map(describe(rect:))
            .joined(separator: ", ")
        let actionIDsDescription = state.actionStates
            .map(\.actionID.rawValueDescription)
            .joined(separator: ",")
        let layoutAnchorPoint = contextMenuLayoutAnchorPoint(
            for: state.resolvedContext
        )

        print(
            "[Canvas iOS][ContextMenuPosition] " +
            state.resolvedContext.debugSummary + " " +
            "viewportBounds=\(describe(rect: canvasViewportView.bounds)) " +
            "viewportFrame=\(describe(rect: canvasViewportView.frame)) " +
            "overlayBounds=\(describe(rect: chromeOverlayView.bounds)) " +
            "overlayFrame=\(describe(rect: chromeOverlayView.frame)) " +
            "hostBounds=\(describe(rect: contextMenuHostView.bounds)) " +
            "hostFrame=\(describe(rect: contextMenuHostView.frame)) " +
            "layoutAnchorPoint=\(describe(point: layoutAnchorPoint)) " +
            "safeBounds=\(describe(rect: layoutContext.safeBounds)) " +
            "occupiedRects=[\(occupiedRectsDescription)] " +
            "actionIDs=[\(actionIDsDescription)]"
        )
    }
}

private enum iOSVideoEditorFlowError: LocalizedError {
    case presenterUnavailable

    var errorDescription: String? {
        switch self {
        case .presenterUnavailable:
            "The canvas editor is no longer available."
        }
    }
}

private enum iOSGIFFrameImportFlowError: LocalizedError {
    case presenterUnavailable

    var errorDescription: String? {
        switch self {
        case .presenterUnavailable:
            "The canvas editor is no longer available."
        }
    }
}
#endif
