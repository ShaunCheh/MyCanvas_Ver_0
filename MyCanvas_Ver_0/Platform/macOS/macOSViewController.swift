//
//  macOSViewController.swift
//  MyCanvas_Ver_0
//
//  Created by Shaun on 2026/3/13.
//

#if os(macOS)
import Foundation
import AppKit
import QuartzCore
import UniformTypeIdentifiers

final class macOSViewController: NSViewController, NSUserInterfaceValidations, NSTextViewDelegate, macOSBoardListCanvasTransitionInteractionControlling {
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
            pressContext: CanvasPointerPressContext,
            pointerModifiers: CanvasPointerModifiers
        )
        case croppingSelectedItem(PointerCropState)
        case movingCropFrame(PointerCropTranslationState)
        case rotatingSelectedItem(PointerRotateState)
        case rotatingSelection(CanvasSelectionRotateState)
        case draggingSelectedItem(CanvasSelectedItemDragState)
        case draggingSelection(CanvasSelectionDragState)
        case resizingSelectedItem(PointerResizeState)
        case resizingSelection(CanvasSelectionResizeState)
        case draggingCanvas
    }

    private enum TransferEntryDeliverySource {
        case macOSPasteAction
        case importButton
        case dragAndDrop

        var debugName: String {
            switch self {
            case .macOSPasteAction:
                return "macOSPasteAction"
            case .importButton:
                return "importButton"
            case .dragAndDrop:
                return "dragAndDrop"
            }
        }
    }

    private enum RawInputDeliverySource {
        case localKeyMonitor
        case pasteAction
        case undoAction
        case redoAction
        case primaryClick
        case secondaryClick
        case scrollGesture
        case zoomGesture

        var debugName: String {
            switch self {
            case .localKeyMonitor:
                return "macOSLocalKeyMonitor"
            case .pasteAction:
                return "macOSPasteAction"
            case .undoAction:
                return "macOSUndoAction"
            case .redoAction:
                return "macOSRedoAction"
            case .primaryClick:
                return "macOSPrimaryClick"
            case .secondaryClick:
                return "macOSSecondaryClick"
            case .scrollGesture:
                return "macOSScrollGesture"
            case .zoomGesture:
                return "macOSZoomGesture"
            }
        }
    }

    private enum ContinuousRawInputKind: Hashable {
        case scroll
        case zoom
    }

    private struct ObservedKeyboardShortcut {
        let rawInput: CanvasRawInputIntent
        let observedAt: Date
    }

    private static let pointerDragActivationDistance: CGFloat = 4
    private static let selectionHandleHitTargetSize: CGFloat = 18
    private static let selectionOutlineHitTargetWidth: CGFloat = 14
    private static let minimumResizeViewportDimension: CGFloat = 20
    private static let cropHandleHitTargetSize: CGFloat = 18
    private static let cropOutlineHitTargetWidth: CGFloat = 14
    private static let minimumCropViewportDimension: CGFloat = 20
    private static let rotateHandleHitTargetSize: CGFloat = 22
    private static let observedKeyboardShortcutReuseWindow: TimeInterval = 0.45
    private static let continuousRawInputObservationInterval: TimeInterval = 0.32

    private let miniMapLayoutSolver = CanvasOverlayLayoutSolver()
    private let alignmentGuideSolver = CanvasAlignmentGuideSolver()
    var miniMapConfiguration = CanvasMiniMapConfiguration()
    var launchContext: CanvasLaunchContext?
    var onReturnToBoardList: ((BoardListCanvasReturnRequest) -> Void)?
    private let editorSession = CanvasEditorSession(
        saveQueueLabel: "MyCanvas.BoardSave.macOS",
        logPrefix: "[BoardStore][macOS]"
    )
    private let commandCatalog = CanvasCommandCatalog()
    private let toolbarStateBuilder = CanvasToolbarStateBuilder()
    private let contextMenuActionResolver = CanvasContextMenuActionResolver()
    private let clickSelectionResolver = CanvasClickSelectionResolver()
    private let interactionPolicy = CanvasInteractionPolicy()
    private let inputRoutingResolver = CanvasInputRoutingResolver()
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
    private let transitionInteractionShieldView = macOSTransitionInteractionShieldView()
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
    private let workspaceModeButton: NSButton = {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.title = ""
        button.wantsLayer = true
        button.layer?.cornerRadius = 22
        button.layer?.masksToBounds = true
        button.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.92).cgColor
        button.layer?.borderWidth = 1
        button.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        button.contentTintColor = .labelColor
        if let image = NSImage(
            systemSymbolName: CanvasWorkspaceMode.editing.systemImageName,
            accessibilityDescription: CanvasWorkspaceMode.editing.accessibilityValue
        ) {
            button.image = image
            button.imagePosition = .imageOnly
        }
        return button
    }()
    // Keep placement transient until persistence is designed; future NSPanGestureRecognizer
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
    private let toolbarHostView = macOSCanvasToolbarHostView()
    private var toolbarTransitionRuntime: CanvasToolbarTransitionRuntime?
    private var isToolbarTransitionActive: Bool {
        toolbarTransitionRuntime != nil
    }
    private let textEditorOverlayView = macOSCanvasTextEditorOverlayView()
    private let miniMapMountView: macOSCanvasChromeOverlayView = {
        let view = macOSCanvasChromeOverlayView()
        view.translatesAutoresizingMaskIntoConstraints = true
        view.isHidden = true
        return view
    }()
    private let contextMenuHostView = CanvasContextMenuHostView()
    private let inputIndicatorHostView = CanvasInputIndicatorHostView()
    private let miniMapView = macOSCanvasMiniMapView()
    private let importButton: NSButton = {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let saveButton: NSButton = {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let cropButton: NSButton = {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let multiSelectButton: NSButton = {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let textButton: NSButton = {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let handDrawingButton: NSButton = {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let undoButton: NSButton = {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let redoButton: NSButton = {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private var toolbarButtonsByID: [CanvasToolbarItemID: NSButton] {
        [
            .undo: undoButton,
            .redo: redoButton,
            .crop: cropButton,
            .multiSelect: multiSelectButton,
            .save: saveButton,
            .text: textButton,
            .handDrawing: handDrawingButton,
            .importMedia: importButton
        ]
    }
    private let canvasViewportView = macOSCanvasViewportView()
    private var canvasContentView: NSView?
    private var pendingRefreshReason: String?
    private var pointerDragState: PointerDragState = .idle
    private var isMultiSelectModeActive = false {
        didSet {
            guard oldValue != isMultiSelectModeActive else {
                return
            }

            dismissContextMenu()
            renderToolbar()
        }
    }
    private var isTransitionInteractionFrozen = false
    private var keyboardShortcutObservationMonitor: Any?
    private var observedKeyboardShortcuts: [ObservedKeyboardShortcut] = []
    private var lastContinuousRawInputObservationByKind: [ContinuousRawInputKind: Date] = [:]
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

    deinit {
        removeKeyboardShortcutObservationIfNeeded()
    }

    private var scene: CanvasScene {
        editorSession.scene
    }

    private var supportsHandDrawingEditing: Bool {
        false
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
            selectionOutlineHitTargetWidth: Self.selectionOutlineHitTargetWidth,
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
        guard isTransitionInteractionFrozen == false else {
            return
        }

        if command.shouldCommitActiveInlineTextBeforeExecuting,
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
            refreshCanvas(reason: refreshReason)
        }
        if let followUp = executionResult.followUp {
            handleCommandFollowUp(followUp)
        }
    }

    private func handleCommandFollowUp(_ followUp: CanvasCommandFollowUp) {
        switch followUp {
        case .presentHandDrawingEditor:
            return
        }
    }

    private func applyTransitionInteractionFreeze() {
        transitionInteractionShieldView.isHidden = isTransitionInteractionFrozen == false
        if isTransitionInteractionFrozen {
            dismissContextMenu()
            handlePrimaryPointerCancel()
            view.window?.makeFirstResponder(nil)
        } else if view.window != nil, view.isHidden == false {
            view.window?.makeFirstResponder(canvasViewportView)
        }
        updateKeyboardShortcutObservationIfNeeded()
    }

    private func presentContextMenu(
        for resolvedContext: CanvasContextMenuContext
    ) {
        let actionStates = contextMenuActionResolver.actionStates(
            for: resolvedContext,
            session: editorSession,
            environment: makeInteractionEnvironment(),
            supportsHandDrawingEditing: supportsHandDrawingEditing
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

    private func updateInputIndicatorLayout(
        using layoutContext: CanvasChromeLayoutContext
    ) {
        inputIndicatorHostView.updateLayout(layoutContext: layoutContext)
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
                context: contextMenuState.resolvedContext,
                session: editorSession
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
        case .editHandDrawing:
            return
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
            let itemID = context.singleEffectiveItemID,
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
            let itemID = context.singleEffectiveItemID,
            let item = scene.item(withID: itemID),
            item.isVideo == false,
            item.assetKind == .animatedGIF
        else {
            return nil
        }

        return itemID
    }

    private func presentVideoDisplayFrameEditor(for itemID: CanvasItemID) {
        guard presentedViewControllers?.isEmpty != false else {
            return
        }

        do {
            let editorContext = try editorSession.videoEditorContext(for: itemID)
            let editorViewController = macOSVideoDisplayFrameEditorViewController(
                editorContext: editorContext,
                loadTimelineStrip: { [weak self] request in
                    guard let self else {
                        throw macOSVideoEditorFlowError.presenterUnavailable
                    }

                    return try self.editorSession.videoTimelineStrip(
                        for: itemID,
                        request: request
                    )
                }
            ) { [weak self] frameImage in
                guard let self else {
                    throw macOSVideoEditorFlowError.presenterUnavailable
                }

                let updateResult = try self.editorSession.commitVideoPosterFrame(
                    withID: itemID,
                    frameImage: frameImage
                )
                self.refreshCanvas(reason: updateResult.refreshReason)
            }
            presentAsSheet(editorViewController)
        } catch {
            presentVideoEditorError(message: error.localizedDescription)
        }
    }

    private func presentGIFFrameImportEditor(for itemID: CanvasItemID) {
        guard presentedViewControllers?.isEmpty != false else {
            return
        }

        do {
            let editorContext = try editorSession.gifFrameImportEditorContext(
                for: itemID
            )
            let editorViewController = macOSGIFFrameImportViewController(
                editorContext: editorContext
            ) { [weak self] frameIndices in
                guard let self else {
                    throw macOSGIFFrameImportFlowError.presenterUnavailable
                }

                try self.performGIFFrameImport(
                    for: itemID,
                    frameIndices: frameIndices
                )
            }
            presentAsSheet(editorViewController)
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

    func canPerformCommand(_ commandID: CanvasCommandID) -> Bool {
        isTransitionInteractionFrozen == false &&
            commandDescriptor(for: commandID).isEnabled
    }

    func performCommand(withID commandID: CanvasCommandID) {
        guard isTransitionInteractionFrozen == false else {
            return
        }

        switch commandID {
        case .importMedia:
            break
        case .addTextItem:
            performCommand(.addTextItem)
        case .addMarkdownItem:
            performCommand(.addMarkdownItem)
        case .addHandDrawingItem:
            if supportsHandDrawingEditing {
                performCommand(.addHandDrawingItem(paper: .square))
            }
        case .beginTextEdit:
            if let selectedItemID = interactionState.selectedItemID {
                performCommand(.beginTextEdit(itemID: selectedItemID))
            }
        case .beginMarkdownEdit:
            if let selectedItemID = interactionState.selectedItemID {
                performCommand(.beginMarkdownEdit(itemID: selectedItemID))
            }
        case .commitTextEdit:
            performCommand(.commitTextEdit)
        case .commitMarkdownEdit:
            performCommand(.commitMarkdownEdit)
        case .decreaseTextFontSize:
            performCommand(.decreaseTextFontSize)
        case .increaseTextFontSize:
            performCommand(.increaseTextFontSize)
        case .decreaseMarkdownContentSize:
            performCommand(.decreaseMarkdownContentSize)
        case .increaseMarkdownContentSize:
            performCommand(.increaseMarkdownContentSize)
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

    func validateUserInterfaceItem(
        _ item: any NSValidatedUserInterfaceItem
    ) -> Bool {
        switch item.action {
        case #selector(macOSViewController.undo(_:)):
            return canPerformCommand(.undo)
        case #selector(macOSViewController.redo(_:)):
            return canPerformCommand(.redo)
        case #selector(macOSViewController.paste(_:)):
            return canTransferContent(
                from: .general,
                entry: resolvedPasteTransferEntryIntent()
            )
        default:
            return true
        }
    }

    @objc
    func undo(_ sender: Any?) {
        let rawInput = CanvasRawInputIntent.undoKeyboardShortcut
        if consumeObservedKeyboardShortcut(rawInput) {
            performCommand(.undo)
            return
        }

        if isCurrentKeyboardShortcut(rawInput) {
            _ = handleCapturedInput(
                rawInput,
                sourceDescription: RawInputDeliverySource.undoAction.debugName
            ) { routingResult in
                guard routingResult.interactionIntent == .command(.undo) else {
                    return false
                }

                performCommand(.undo)
                return true
            }
            return
        }

        _ = handleCommandAttempt(
            .undo,
            sourceDescription: RawInputDeliverySource.undoAction.debugName
        ) {
            performCommand(.undo)
            return true
        }
    }

    @objc
    func redo(_ sender: Any?) {
        let rawInput = CanvasRawInputIntent.redoKeyboardShortcut
        if consumeObservedKeyboardShortcut(rawInput) {
            performCommand(.redo)
            return
        }

        if isCurrentKeyboardShortcut(rawInput) {
            _ = handleCapturedInput(
                rawInput,
                sourceDescription: RawInputDeliverySource.redoAction.debugName
            ) { routingResult in
                guard routingResult.interactionIntent == .command(.redo) else {
                    return false
                }

                performCommand(.redo)
                return true
            }
            return
        }

        _ = handleCommandAttempt(
            .redo,
            sourceDescription: RawInputDeliverySource.redoAction.debugName
        ) {
            performCommand(.redo)
            return true
        }
    }

    @objc
    func paste(_ sender: Any?) {
        let rawInput = CanvasRawInputIntent.pasteKeyboardShortcut
        if consumeObservedKeyboardShortcut(rawInput) {
            handlePasteRequest()
            return
        }

        switch resolvedPasteTransferEntryIntent() {
        case .pasteKeyboardShortcut:
            handleCapturedInput(
                rawInput,
                sourceDescription: RawInputDeliverySource.pasteAction.debugName
            ) { routingResult in
                guard
                    routingResult.interactionIntent
                        == .transferEntry(.pasteKeyboardShortcut)
                else {
                    return false
                }

                handlePasteRequest()
                return true
            }
        case .pasteMenu:
            handleTransferEntryAttempt(
                .pasteMenu,
                deliverySource: .macOSPasteAction
            ) {
                handlePasteRequest()
                return true
            }
        case .importButton,
             .dragAndDrop:
            return
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
        updatePreparedToolbarPlacement()
        setupTextEditorOverlay()
        setupImportButton()
        setupSaveButton()
        setupCropButton()
        setupMultiSelectButton()
        setupTextButton()
        setupHandDrawingButton()
        setupUndoButton()
        setupRedoButton()
        setupBackButton()
        setupWorkspaceModeButton()
        setupMiniMapView()
        setupContextMenuHostView()
        restoreInitialBoardState()
        setupCanvasViewport()
        applyTransitionInteractionFreeze()
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

    func setTransitionInteractionFrozen(_ isFrozen: Bool) {
        guard isTransitionInteractionFrozen != isFrozen else {
            return
        }

        isTransitionInteractionFrozen = isFrozen
        guard isViewLoaded else {
            return
        }

        applyTransitionInteractionFreeze()
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
        updateChromeOverlayLayout()
        updateKeyboardShortcutObservationIfNeeded()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        removeKeyboardShortcutObservationIfNeeded()
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
        guard isToolbarTransitionActive == false else {
            markToolbarTransitionLayoutReconcilePending()
            return
        }
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
        view.addSubview(transitionInteractionShieldView)
        chromeOverlayView.addSubview(miniMapMountView)
        toolbarHostView.translatesAutoresizingMaskIntoConstraints = true
        chromeOverlayView.addSubview(toolbarHostView)
        chromeOverlayView.addSubview(textEditorOverlayView)
        chromeOverlayView.addSubview(inputIndicatorHostView)
        chromeOverlayView.addSubview(contextMenuHostView)
        chromeOverlayView.addSubview(backButton)
        chromeOverlayView.addSubview(workspaceModeButton)
        registerToolbarButtons()
    }

    private func setupConstraints() {
        let safeAreaLayoutGuide = chromeOverlayView.safeAreaLayoutGuide
        let preferredTextEditorWidth = textEditorOverlayView.widthAnchor.constraint(equalToConstant: 360)
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
            transitionInteractionShieldView.topAnchor.constraint(equalTo: view.topAnchor),
            transitionInteractionShieldView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            transitionInteractionShieldView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            transitionInteractionShieldView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            inputIndicatorHostView.topAnchor.constraint(equalTo: chromeOverlayView.topAnchor),
            inputIndicatorHostView.leadingAnchor.constraint(equalTo: chromeOverlayView.leadingAnchor),
            inputIndicatorHostView.trailingAnchor.constraint(equalTo: chromeOverlayView.trailingAnchor),
            inputIndicatorHostView.bottomAnchor.constraint(equalTo: chromeOverlayView.bottomAnchor),
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
            textEditorOverlayView.heightAnchor.constraint(equalToConstant: 156)
        ])
    }

    private func registerToolbarButtons() {
        toolbarHostView.registerButtons(toolbarButtonsByID)
    }

    private func updatePreparedToolbarPlacement() {
        guard isToolbarTransitionActive == false else {
            markToolbarTransitionLayoutReconcilePending()
            return
        }

        renderToolbar()
        if view.bounds.isEmpty == false {
            view.layoutSubtreeIfNeeded()
            if chromeOverlayView.bounds.isEmpty == false {
                chromeOverlayView.layoutSubtreeIfNeeded()
            }
            updateChromeOverlayLayout()
        }
    }

    private func updateChromeOverlayLayout() {
        guard isToolbarTransitionActive == false else {
            markToolbarTransitionLayoutReconcilePending()
            return
        }

        if chromeOverlayView.bounds.isEmpty == false {
            chromeOverlayView.layoutSubtreeIfNeeded()
        }
        let contextMenuLayoutContext = performOverlayLayoutPass()
        updateInputIndicatorLayout(using: contextMenuLayoutContext)
        updateContextMenuLayout(using: contextMenuLayoutContext)
    }

    private func toolbarPreferredPlacement() -> CanvasToolbarPlacement {
        transientToolbarPlacement
    }

    private func performOverlayLayoutPass() -> CanvasChromeLayoutContext {
        let safeBounds = toolbarLayoutSafeBounds()
        let baseChromeBlockers = baseChromeBlockersForToolbarLayout()
        let toolbarState = makeToolbarState()
        let toolbarPlacementResult = CanvasToolbarPlacementPass.resolve(
            safeBounds: safeBounds,
            toolbarPreferredPlacement: toolbarState.placement,
            toolbarMeasuredSize: measuredToolbarHostSize(for: toolbarState),
            baseChromeBlockers: baseChromeBlockers,
            scale: toolbarPlacementScale(),
            solver: toolbarPlacementSolver
        )
        applyToolbarFrame(
            toolbarState.items.isEmpty
                ? toolbarPlacementResult.hiddenToolbarFrame
                : toolbarPlacementResult.toolbarFrame
        )
        let miniMapFrame = resolveMiniMapFrame(
            in: toolbarPlacementResult.chromeLayoutContext
        )
        applyMiniMapFrame(miniMapFrame)
        logChromeOverlayLayoutPass(
            safeBounds: safeBounds,
            baseChromeBlockers: baseChromeBlockers,
            chromeLayoutContext: toolbarPlacementResult.chromeLayoutContext,
            miniMapFrame: miniMapFrame
        )
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

        guard let sanitizedToolbarFrame = CanvasChromeLayoutGeometry.sanitizedRect(
            toolbarFrame
        ) else {
            return
        }

        if toolbarHostView.frame != sanitizedToolbarFrame {
            toolbarHostView.frame = sanitizedToolbarFrame
        }
    }

    private func toolbarLayoutSafeBounds() -> CGRect {
        CGRect(
            x: chromeOverlayView.bounds.minX + chromeOverlayView.safeAreaInsets.left,
            y: chromeOverlayView.bounds.minY + chromeOverlayView.safeAreaInsets.top,
            width: max(
                chromeOverlayView.bounds.width -
                    chromeOverlayView.safeAreaInsets.left -
                    chromeOverlayView.safeAreaInsets.right,
                0
            ),
            height: max(
                chromeOverlayView.bounds.height -
                    chromeOverlayView.safeAreaInsets.top -
                    chromeOverlayView.safeAreaInsets.bottom,
                0
            )
        ).standardized
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
        for view: NSView,
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

    private func toolbarPlacementScale() -> CGFloat {
        let scale = chromeOverlayView.window?.backingScaleFactor
            ?? view.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
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
        renderToolbar()
    }

    private func setupTextEditorOverlay() {
        textEditorOverlayView.textView.delegate = self
        textEditorOverlayView.onDecreaseFontSize = { [weak self] in
            self?.performCommand(.decreaseTextFontSize)
        }
        textEditorOverlayView.onIncreaseFontSize = { [weak self] in
            self?.performCommand(.increaseTextFontSize)
        }
        syncTextEditorPresentation()
    }

    private func setupSaveButton() {
        saveButton.target = self
        saveButton.action = #selector(handleSaveButtonClick)
        renderToolbar()
    }

    private func setupCropButton() {
        cropButton.target = self
        cropButton.action = #selector(handleCropButtonClick)
        updateInlineEditButtonsAppearance()
    }

    private func setupMultiSelectButton() {
        multiSelectButton.target = self
        multiSelectButton.action = #selector(handleMultiSelectButtonClick)
        renderToolbar()
    }

    private func setupTextButton() {
        textButton.target = self
        textButton.action = #selector(handleTextButtonClick)
        updateInlineEditButtonsAppearance()
    }

    private func setupHandDrawingButton() {
        handDrawingButton.target = self
        handDrawingButton.action = #selector(handleHandDrawingButtonClick)
        updateInlineEditButtonsAppearance()
    }

    private func setupUndoButton() {
        undoButton.target = self
        undoButton.action = #selector(handleUndoButtonClick)
        updateInlineEditButtonsAppearance()
    }

    private func setupRedoButton() {
        redoButton.target = self
        redoButton.action = #selector(handleRedoButtonClick)
        updateInlineEditButtonsAppearance()
    }

    private func setupBackButton() {
        backButton.target = self
        backButton.action = #selector(handleBackButtonClick)
    }

    private func setupWorkspaceModeButton() {
        workspaceModeButton.target = self
        workspaceModeButton.action = #selector(handleWorkspaceModeButtonClick)
        updateWorkspaceModeButtonAppearance()
    }

    private func updateWorkspaceModeButtonAppearance() {
        workspaceModeButton.toolTip = "\(workspaceMode.accessibilityLabel): \(workspaceMode.accessibilityValue)"
        if let image = NSImage(
            systemSymbolName: workspaceMode.systemImageName,
            accessibilityDescription: workspaceMode.accessibilityValue
        ) {
            workspaceModeButton.image = image
            workspaceModeButton.imagePosition = .imageOnly
        }
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
        canvasViewportView.onPointerDown = { [weak self] location, modifiers in
            self?.observeRawInput(
                .primaryPointerClick,
                sourceDescription: RawInputDeliverySource.primaryClick.debugName
            )
            guard self?.isTransitionInteractionFrozen == false else {
                return
            }
            self?.handlePrimaryPointerDown(at: location, modifiers: modifiers)
        }
        canvasViewportView.onPointerMove = { [weak self] location, previousLocation in
            guard self?.isTransitionInteractionFrozen == false else {
                return
            }
            self?.handlePrimaryPointerMove(to: location, from: previousLocation)
        }
        canvasViewportView.onPointerUp = { [weak self] location, modifiers in
            guard self?.isTransitionInteractionFrozen == false else {
                return
            }
            self?.handlePrimaryPointerUp(at: location, modifiers: modifiers)
        }
        canvasViewportView.onPointerCancel = { [weak self] in
            guard self?.isTransitionInteractionFrozen == false else {
                return
            }
            self?.handlePrimaryPointerCancel()
        }
        canvasViewportView.onSecondaryClick = { [weak self] location in
            self?.handleSecondaryClick(at: location)
        }
        canvasViewportView.onPan = { [weak self] translation in
            self?.observeContinuousRawInput(
                .pointerScrollGesture,
                sourceDescription: RawInputDeliverySource.scrollGesture.debugName,
                kind: .scroll
            )
            guard self?.isTransitionInteractionFrozen == false else {
                return
            }
            self?.handleIndirectPan(translation)
        }
        canvasViewportView.onZoom = { [weak self] scaleDelta, anchor in
            self?.observeContinuousRawInput(
                .pointerZoomGesture,
                sourceDescription: RawInputDeliverySource.zoomGesture.debugName,
                kind: .zoom
            )
            guard self?.isTransitionInteractionFrozen == false else {
                return
            }
            self?.handleZoom(scaleDelta, around: anchor)
        }
        canvasViewportView.onViewportSizeChange = { [weak self] viewportSize in
            self?.syncCameraViewportSizeIfNeeded(
                viewportSize,
                source: "viewport layout"
            )
        }
        canvasViewportView.onImportDragOperation = { [weak self] _, pasteboard in
            return self?.dragOperation(for: pasteboard) ?? []
        }
        canvasViewportView.onImportDrop = { [weak self] _, pasteboard in
            return self?.handleTransferEntryAttempt(
                .dragAndDrop,
                deliverySource: .dragAndDrop
            ) {
                self?.handleImportDrop(pasteboard: pasteboard) ?? false
            } ?? false
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
            scheduleAutosave(
                reason: "configure board state",
                updateKind: .viewStateOnly
            )
        }
    }

    private func handlePrimaryPointerDown(
        at location: CGPoint,
        modifiers: CanvasPointerModifiers
    ) {
        print(
            "[Canvas macOS][PrimaryPointerInput] " +
            "phase=down " +
            "location=\(describe(point: location)) " +
            "worldPoint=\(describe(point: camera.viewportToWorld(location))) " +
            "selection=\(describe(selectionState: interactionState)) " +
            "pointerModifiers=\(describe(pointerModifiers: modifiers)) " +
            "cameraCenter=\(describe(point: camera.center)) " +
            "zoom=\(String(format: "%.4f", Double(camera.zoomScale))) " +
            "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
            "canvasViewportBounds=\(describe(rect: canvasViewportView.bounds)) " +
            "snapshotViewportBounds=\(describe(rect: lastRenderSnapshot.viewportBounds)) " +
            "snapshotEditOverlay=\(describe(editOverlay: lastRenderSnapshot.editOverlay))"
        )
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
            pressContext: pressContext,
            pointerModifiers: modifiers
        )
        beginPointerHistoryTransactionIfNeeded(for: pressContext)
    }

    private func handleSecondaryClick(at location: CGPoint) {
        let didContinue = handleCapturedInput(
            .secondaryPointerClick,
            sourceDescription: RawInputDeliverySource.secondaryClick.debugName
        ) { routingResult in
            guard routingResult.interactionIntent == .contextMenuRequest else {
                return false
            }

            return presentSecondaryClickContextMenu(at: location)
        }

        if didContinue == false {
            dismissContextMenuIfContextMenuRequestBlocked()
        }
    }

    private func presentSecondaryClickContextMenu(at location: CGPoint) -> Bool {
        if commitActiveTextEditIfNeeded() {
            return true
        }

        updateCameraViewportSizeIfNeeded(trigger: "secondary click")
        prepareForSecondaryClickContextMenu()

        let resolvedContext = resolveContext(at: location)
        presentContextMenu(for: resolvedContext)
        return true
    }

    private func dismissContextMenuIfContextMenuRequestBlocked() {
        guard case .block = interactionDecision(for: .contextMenuRequest) else {
            return
        }

        dismissContextMenu()
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
             .rotatingSelection,
             .draggingSelectedItem,
             .draggingSelection,
             .resizingSelectedItem,
             .resizingSelection,
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
        case let .pressed(pressedLocation, pressContext, _):
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
            case .groupRotateHandle:
                guard let rotateState = makeSelectionRotateState(
                    initialViewportLocation: pressedLocation
                ) else {
                    editorSession.cancelPendingHistoryTransaction()
                    pointerDragState = .idle
                    return
                }

                pointerDragState = .rotatingSelection(rotateState)
                beginRotationInteraction(for: rotateState.snapshot)
                updateSelectionRotationDraft(using: rotateState, to: location)
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
            case let .groupSelectionHandle(handleRole):
                guard let resizeState = makeSelectionResizeState(
                    handleRole: handleRole
                ) else {
                    editorSession.cancelPendingHistoryTransaction()
                    pointerDragState = .idle
                    return
                }

                pointerDragState = .resizingSelection(resizeState)
                resizeSelection(using: resizeState, to: location)
            case .selectionTranslationArea, .selectedItemBody:
                guard let itemID = pressContext.targetItemID else {
                    pointerDragState = .idle
                    return
                }

                if interactionState.selectionCount > 1 {
                    guard let dragState = makeSelectionDragState(
                        initialViewportLocation: pressedLocation
                    ) else {
                        pointerDragState = .idle
                        return
                    }

                    guard let updatedDragState = moveSelection(
                        using: dragState,
                        to: location
                    ) else {
                        pointerDragState = .idle
                        return
                    }

                    pointerDragState = .draggingSelection(updatedDragState)
                } else {
                    guard let dragState = makeSelectedItemDragState(
                        itemID: itemID,
                        initialViewportLocation: pressedLocation
                    ) else {
                        pointerDragState = .idle
                        return
                    }

                    guard let updatedDragState = moveSelectedItem(
                        using: dragState,
                        to: location
                    ) else {
                        pointerDragState = .idle
                        return
                    }

                    pointerDragState = .draggingSelectedItem(updatedDragState)
                }
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
        case let .rotatingSelection(rotateState):
            updateSelectionRotationDraft(using: rotateState, to: location)
        case let .draggingSelectedItem(dragState):
            guard let updatedDragState = moveSelectedItem(
                using: dragState,
                to: location
            ) else {
                pointerDragState = .idle
                return
            }
            pointerDragState = .draggingSelectedItem(updatedDragState)
        case let .draggingSelection(dragState):
            guard let updatedDragState = moveSelection(
                using: dragState,
                to: location
            ) else {
                pointerDragState = .idle
                return
            }
            pointerDragState = .draggingSelection(updatedDragState)
        case let .resizingSelectedItem(resizeState):
            resizeSelectedItem(using: resizeState, to: location)
        case let .resizingSelection(resizeState):
            resizeSelection(using: resizeState, to: location)
        case .draggingCanvas:
            panCanvas(from: previousLocation, to: location)
        case .idle:
            break
        }
    }

    private func handlePrimaryPointerUp(
        at location: CGPoint,
        modifiers: CanvasPointerModifiers
    ) {
        defer {
            pointerDragState = .idle
        }

        switch pointerDragState {
        case let .pressed(_, pressContext, pressedModifiers):
            if isInlineEditModeActive {
                editorSession.cancelPendingHistoryTransaction()
                return
            }

            let clearedAlignmentInteractionState =
                clearAlignmentInteractionStateIfNeeded()
            let pressedItemID = pressContext.targetItemID
            let releasedContext = resolvePointerPressContext(at: location)
            let releasedItemID = releasedContext.targetItemID
            let previousInteractionState = interactionState
            let clickDecision = clickSelectionResolver.resolve(
                pressTargetKind: pressContext.targetKind,
                pressedItemID: pressContext.targetItemID,
                releasedItemID: releasedItemID,
                selection: previousInteractionState,
                isPersistentMultiSelectModeEnabled: isMultiSelectModeActive,
                pressedModifiers: pressedModifiers,
                releasedModifiers: modifiers
            )
            let executionResult = executeClickSelectionDecision(clickDecision)

            logClickResult(
                target: clickDecision.target,
                result: executionResult.result,
                pressedItemID: pressedItemID,
                releasedItemID: releasedItemID,
                previousInteractionState: previousInteractionState,
                currentInteractionState: interactionState,
                affectedItemID: clickDecision.affectedItemID
            )
            if clearedAlignmentInteractionState,
               executionResult.didTriggerPressedRefresh == false
            {
                refreshCanvas(reason: "clear alignment interaction on pointer up")
            }
            editorSession.cancelPendingHistoryTransaction()
        case .rotatingSelectedItem, .rotatingSelection:
            commitRotationDraftIfNeeded()
        case .croppingSelectedItem, .movingCropFrame:
            commitCropDraftIfNeeded()
        case .draggingSelectedItem:
            commitPendingPointerHistoryTransaction(autosaveReason: "move item")
            clearAlignmentInteractionStateIfNeeded(
                refreshReason: "finish move alignment interaction"
            )
        case .draggingSelection:
            commitPendingPointerHistoryTransaction(autosaveReason: "move selection")
            clearAlignmentInteractionStateIfNeeded(
                refreshReason: "finish move alignment interaction"
            )
        case .resizingSelectedItem:
            commitPendingPointerHistoryTransaction(autosaveReason: "resize item")
        case .resizingSelection:
            commitPendingPointerHistoryTransaction(autosaveReason: "resize selection")
        case .draggingCanvas, .idle:
            break
        }
    }

    private func handlePrimaryPointerCancel() {
        switch pointerDragState {
        case .rotatingSelectedItem, .rotatingSelection:
            cancelRotationInteractionIfNeeded(
                refreshAfterCancellation: true
            )
        case .croppingSelectedItem, .movingCropFrame:
            commitCropDraftIfNeeded()
        case .draggingSelectedItem:
            commitPendingPointerHistoryTransaction(autosaveReason: "move item")
            clearAlignmentInteractionStateIfNeeded(
                refreshReason: "cancel move alignment interaction"
            )
        case .draggingSelection:
            commitPendingPointerHistoryTransaction(autosaveReason: "move selection")
            clearAlignmentInteractionStateIfNeeded(
                refreshReason: "cancel move alignment interaction"
            )
        case .resizingSelectedItem:
            commitPendingPointerHistoryTransaction(autosaveReason: "resize item")
        case .resizingSelection:
            commitPendingPointerHistoryTransaction(autosaveReason: "resize selection")
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
        scheduleAutosave(
            reason: "pan canvas",
            updateKind: .viewStateOnly
        )
    }

    private func handleZoom(_ scaleDelta: CGFloat, around anchor: CGPoint) {
        if contextMenuState != nil {
            dismissContextMenu()
            return
        }

        camera.zoom(by: scaleDelta, around: anchor)
        refreshCanvas()
        scheduleAutosave(
            reason: "zoom canvas",
            updateKind: .viewStateOnly
        )
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
        scheduleAutosave(
            reason: "navigate canvas via minimap",
            updateKind: .viewStateOnly
        )
    }

    @objc
    private func handleImportButtonClick() {
        handleTransferEntryAttempt(
            .importButton,
            deliverySource: .importButton
        ) {
            commitActiveTextEditIfNeeded()
            guard let window = view.window else {
                return false
            }

            let openPanel = NSOpenPanel()
            openPanel.allowedContentTypes = [.image, .movie]
            openPanel.allowsMultipleSelection = true
            openPanel.canChooseDirectories = false
            openPanel.canChooseFiles = true

            openPanel.beginSheetModal(for: window) { [weak self] response in
                guard
                    response == .OK,
                    let self
                else {
                    return
                }

                guard let transferRequest = macOSCanvasImportAdapter.transferRequest(
                    from: openPanel.urls,
                    sourceDescription: "open panel"
                ) else {
                    return
                }

                _ = self.performTransferRequest(transferRequest)
            }
            return true
        }
    }

    @objc
    private func handleSaveButtonClick() {
        commitActiveTextEditIfNeeded()
        beginSaveButtonSaveState()
        saveBoardNow(
            reason: "manual save",
            createBoardIfNeeded: true
        ) { [weak self] result in
            guard let self else {
                return
            }

            self.handleImmediateBoardSaveResult(
                result,
                missingFolderMessage: "Select a folder from the board list before saving."
            )
        }
    }

    @objc
    private func handleCropButtonClick() {
        performCommand(CanvasCommand.crop)
    }

    @objc
    private func handleMultiSelectButtonClick() {
        guard
            editorSession.isInlineEditModeActive == false,
            editorSession.isReadingModeActive == false
        else {
            return
        }

        isMultiSelectModeActive.toggle()
    }

    @objc
    private func handleTextButtonClick() {
        if isInlineTextModeActive {
            performCommand(.commitTextEdit)
        } else {
            performCommand(.addTextItem)
        }
    }

    @objc
    private func handleHandDrawingButtonClick() {
        guard supportsHandDrawingEditing else {
            return
        }

        if let itemID = editorSession.singleSelectedItemID,
           editorSession.canEditHandDrawing(withID: itemID)
        {
            return
        }

        performCommand(.addHandDrawingItem(paper: .square))
    }

    @objc
    private func handleUndoButtonClick() {
        performCommand(.undo)
    }

    @objc
    private func handleRedoButtonClick() {
        performCommand(.redo)
    }

    private func makeReturnToBoardListRequest() -> BoardListCanvasReturnRequest {
        .backButton(
            boardID: editorSession.activeBoardID,
            launchContext: launchContext
        )
    }

    @objc
    private func handleBackButtonClick() {
        commitActiveTextEditIfNeeded()
        dismissContextMenu()
        requestReturnToBoardList()
    }

    private func requestReturnToBoardList() {
        let request = makeReturnToBoardListRequest()
        guard request.requiresBoardPersistence else {
            onReturnToBoardList?(request)
            return
        }

        beginSaveButtonSaveState()
        saveBoardNow(
            reason: "return to board list",
            createBoardIfNeeded: true
        ) { [weak self] result in
            guard let self else {
                return
            }

            self.handleImmediateBoardSaveResult(
                result,
                missingFolderMessage: "Select a folder from the board list before returning so the new board can be saved."
            ) { [weak self] in
                guard let self else {
                    return
                }

                self.onReturnToBoardList?(self.makeReturnToBoardListRequest())
            }
        }
    }

    @objc
    private func handleWorkspaceModeButtonClick() {
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
        toolbarHostView.renderTransition(
            initialPresentation,
            animated: false
        )

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
            let offscreenFrame = CanvasToolbarTransitionGeometry.hiddenFrame(
                for: visibleState.placement,
                visibleFrame: visibleFrame,
                safeBounds: toolbarLayoutSafeBounds(),
                scale: toolbarPlacementScale(),
                baseChromeBlockers: baseChromeBlockersForToolbarLayout(),
                solver: toolbarPlacementSolver
            )

            let context = CanvasToolbarTransitionContext(
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
            logToolbarTransitionContext(context)
            return context

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
            let offscreenFrame = CanvasToolbarTransitionGeometry.hiddenFrame(
                for: visibleState.placement,
                visibleFrame: visibleFrame,
                safeBounds: toolbarLayoutSafeBounds(),
                scale: toolbarPlacementScale(),
                baseChromeBlockers: baseChromeBlockersForToolbarLayout(),
                solver: toolbarPlacementSolver
            )

            let context = CanvasToolbarTransitionContext(
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
            logToolbarTransitionContext(context)
            return context
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
        toolbarHostView.renderTransition(
            runtime.currentPresentation,
            animated: false
        )
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
        logToolbarTransitionAnimation(
            context: runtime.context,
            stage: targetStage,
            presentation: targetPresentation,
            duration: duration
        )
        let expectedDirection = runtime.context.direction
        runtime.stage = targetStage
        runtime.currentPresentation = targetPresentation
        toolbarTransitionRuntime = runtime

        if duration <= 0 {
            toolbarHostView.renderTransition(
                targetPresentation,
                animated: false
            )
            completion()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.toolbarHostView.renderTransition(
                targetPresentation,
                animated: true
            )
        } completionHandler: { [weak self] in
            guard let self else {
                return
            }
            guard let currentRuntime = self.toolbarTransitionRuntime,
                  currentRuntime.context.direction == expectedDirection,
                  currentRuntime.stage == targetStage
            else {
                return
            }

            completion()
        }
    }

    private func applyWorkspaceModeForToolbarTransition(
        to targetMode: CanvasWorkspaceMode
    ) {
        workspaceMode = targetMode
        updateWorkspaceModeButtonAppearance()
        updateKeyboardShortcutObservationIfNeeded()
        syncTextEditorPresentation()
        refreshCanvas(reason: "toggle workspace mode")
        scheduleAutosave(
            reason: "toggle workspace mode",
            updateKind: .viewStateOnly
        )
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
        if let animatedFrame = toolbarHostView.layer?.presentation()?.frame,
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
        let steadyFrame = state.items.isEmpty
            ? placementResult.hiddenToolbarFrame
            : placementResult.toolbarFrame

        return normalizedToolbarFrame(
            steadyFrame,
            fallback: steadyFrame
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

    private func makeInteractionEnvironment() -> CanvasInteractionEnvironment {
        CanvasInteractionEnvironment(
            workspaceMode: workspaceMode,
            isTransitionInteractionFrozen: isTransitionInteractionFrozen
        )
    }

    private func interactionDecision(
        for intent: CanvasInteractionIntent
    ) -> CanvasInteractionDecision {
        interactionPolicy.decision(
            for: intent,
            environment: makeInteractionEnvironment()
        )
    }

    private func isInteractionAllowed(
        _ intent: CanvasInteractionIntent
    ) -> Bool {
        switch interactionDecision(for: intent) {
        case .allow:
            return true
        case .block:
            return false
        }
    }

    @discardableResult
    private func handleInteractionAttempt(
        _ intent: CanvasInteractionIntent,
        sourceDescription: String,
        continueIfAllowed: () -> Bool
    ) -> Bool {
        let decision = interactionDecision(for: intent)
        logInteractionDecision(
            intent: intent,
            decision: decision,
            sourceDescription: sourceDescription
        )
        switch decision {
        case .allow:
            return continueIfAllowed()
        case .block(_, let feedback):
            if let feedback {
                applyInteractionFeedback(feedback)
            }
            return false
        }
    }

    private func logCapturedInputRouting(
        rawInput: CanvasRawInputIntent,
        routingResult: CanvasInputRoutingResult,
        sourceDescription: String
    ) {
        print(
            "[Canvas macOS][RawInputRoute] " +
            "source=\"\(sourceDescription)\" " +
            "rawInput=\(rawInput.debugName) " +
            routingResult.debugSummary
        )
    }

    @discardableResult
    private func handleCapturedInput(
        _ rawInput: CanvasRawInputIntent,
        sourceDescription: String,
        continueIfAllowed: (CanvasInputRoutingResult) -> Bool
    ) -> Bool {
        let routingResult = resolveCapturedInputRouting(
            rawInput,
            sourceDescription: sourceDescription
        )

        guard let interactionIntent = routingResult.interactionIntent else {
            return continueIfAllowed(routingResult)
        }

        return handleInteractionAttempt(
            interactionIntent,
            sourceDescription: sourceDescription
        ) {
            continueIfAllowed(routingResult)
        }
    }

    @discardableResult
    private func resolveCapturedInputRouting(
        _ rawInput: CanvasRawInputIntent,
        sourceDescription: String
    ) -> CanvasInputRoutingResult {
        let routingResult = inputRoutingResolver.route(rawInput)
        logCapturedInputRouting(
            rawInput: rawInput,
            routingResult: routingResult,
            sourceDescription: sourceDescription
        )
        recordCapturedInputIndicator(routingResult.indicatorEvent)
        return routingResult
    }

    private func recordCapturedInputIndicator(
        _ indicatorEvent: CanvasInputIndicatorEvent?
    ) {
        guard let indicatorEvent else {
            return
        }

        inputIndicatorHostView.record(event: indicatorEvent)
    }

    private func observeRawInput(
        _ rawInput: CanvasRawInputIntent,
        sourceDescription: String
    ) {
        _ = handleCapturedInput(
            rawInput,
            sourceDescription: sourceDescription
        ) { _ in
            true
        }
    }

    private func observeContinuousRawInput(
        _ rawInput: CanvasRawInputIntent,
        sourceDescription: String,
        kind: ContinuousRawInputKind,
        now: Date = Date()
    ) {
        if let lastObservedAt = lastContinuousRawInputObservationByKind[kind],
           now.timeIntervalSince(lastObservedAt)
                < Self.continuousRawInputObservationInterval
        {
            return
        }

        lastContinuousRawInputObservationByKind[kind] = now
        observeRawInput(
            rawInput,
            sourceDescription: sourceDescription
        )
    }

    @discardableResult
    private func handleCommandAttempt(
        _ commandID: CanvasCommandID,
        sourceDescription: String,
        continueIfAllowed: () -> Bool
    ) -> Bool {
        handleInteractionAttempt(
            .command(commandID),
            sourceDescription: sourceDescription
        ) {
            continueIfAllowed()
        }
    }

    private func transferEntryDecision(
        for entry: CanvasTransferEntryIntent
    ) -> CanvasInteractionDecision {
        interactionDecision(for: .transferEntry(entry))
    }

    private func isTransferEntryAllowed(
        _ entry: CanvasTransferEntryIntent
    ) -> Bool {
        isInteractionAllowed(.transferEntry(entry))
    }

    @discardableResult
    private func handleTransferEntryAttempt(
        _ entry: CanvasTransferEntryIntent,
        deliverySource: TransferEntryDeliverySource,
        continueIfAllowed: () -> Bool
    ) -> Bool {
        handleInteractionAttempt(
            .transferEntry(entry),
            sourceDescription: deliverySource.debugName
        ) {
            continueIfAllowed()
        }
    }

    private func logInteractionDecision(
        intent: CanvasInteractionIntent,
        decision: CanvasInteractionDecision,
        sourceDescription: String
    ) {
        print(
            "[Canvas macOS][InteractionGate] " +
            "source=\"\(sourceDescription)\" " +
            "intent=\(intent.debugName) " +
            "decision=\(decision.debugName) " +
            "reason=\(decision.blockReason?.debugName ?? "none") " +
            "feedback=\(decision.feedbackHint?.debugName ?? "none") " +
            "workspaceMode=\(workspaceMode.rawValue) " +
            "frozen=\(isTransitionInteractionFrozen)"
        )
    }

    private func transferSafetyNetBlockReason() -> CanvasInteractionBlockReason? {
        if isTransitionInteractionFrozen {
            return .transitionInteractionFrozen
        }

        if isReadingModeActive {
            return .readingMode
        }

        return nil
    }

    private func logTransferSafetyNetBlock(
        request: CanvasTransferRequest,
        reason: CanvasInteractionBlockReason
    ) {
        print(
            "[Canvas macOS][InteractionGate] " +
            "source=\"\(request.sourceDescription)\" " +
            "intent=transferRequestSafetyNet " +
            "decision=block " +
            "reason=\(reason.debugName) " +
            "feedback=none " +
            "workspaceMode=\(workspaceMode.rawValue) " +
            "frozen=\(isTransitionInteractionFrozen)"
        )
    }

    private func applyInteractionFeedback(_ hint: CanvasInteractionFeedbackHint) {
        switch hint {
        case .shakeWorkspaceModeButton:
            animateWorkspaceModeButtonShake()
        }
    }

    private func animateWorkspaceModeButtonShake() {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [0, -10, 10, -7, 7, -4, 4, 0]
        animation.duration = 0.36
        animation.isAdditive = true
        animation.calculationMode = .linear
        workspaceModeButton.layer?.removeAnimation(
            forKey: "CanvasWorkspaceModeButtonShake"
        )
        workspaceModeButton.layer?.add(
            animation,
            forKey: "CanvasWorkspaceModeButtonShake"
        )
    }

    private func shouldEnableKeyboardShortcutObservation() -> Bool {
        guard
            view.window != nil,
            view.isHiddenOrHasHiddenAncestor == false
        else {
            return false
        }

        return true
    }

    private func updateKeyboardShortcutObservationIfNeeded() {
        guard shouldEnableKeyboardShortcutObservation() else {
            removeKeyboardShortcutObservationIfNeeded()
            return
        }

        guard keyboardShortcutObservationMonitor == nil else {
            return
        }

        keyboardShortcutObservationMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown]
        ) { [weak self] event in
            self?.handleObservedKeyboardShortcut(event) ?? event
        }
    }

    private func removeKeyboardShortcutObservationIfNeeded() {
        guard let keyboardShortcutObservationMonitor else {
            return
        }

        NSEvent.removeMonitor(keyboardShortcutObservationMonitor)
        self.keyboardShortcutObservationMonitor = nil
        observedKeyboardShortcuts.removeAll()
    }

    private func handleObservedKeyboardShortcut(
        _ event: NSEvent
    ) -> NSEvent? {
        guard
            shouldEnableKeyboardShortcutObservation(),
            let window = view.window,
            event.window === window,
            let rawInput = observedKeyboardShortcutRawInput(from: event)
        else {
            return event
        }

        if window.firstResponder === textEditorOverlayView.textView {
            _ = resolveCapturedInputRouting(
                rawInput,
                sourceDescription: RawInputDeliverySource.localKeyMonitor.debugName
            )
            return event
        }

        let shouldContinue = handleCapturedInput(
            rawInput,
            sourceDescription: RawInputDeliverySource.localKeyMonitor.debugName
        ) { _ in
            true
        }

        if shouldContinue,
           inputRoutingResolver.route(rawInput).interactionIntent != nil
        {
            rememberObservedKeyboardShortcut(rawInput)
        }

        return shouldContinue ? event : nil
    }

    private func observedKeyboardShortcutRawInput(
        from event: NSEvent?
    ) -> CanvasRawInputIntent? {
        guard
            let event,
            event.type == .keyDown,
            event.isARepeat == false
        else {
            return nil
        }

        let relevantFlags = event.modifierFlags.intersection(
            [.command, .control, .option, .shift]
        )
        guard let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return nil
        }

        switch (relevantFlags, characters) {
        case ([.command], "c"):
            return .copyKeyboardShortcut
        case ([.command], "v"):
            return .pasteKeyboardShortcut
        case ([.command], "z"):
            return .undoKeyboardShortcut
        case ([.command, .shift], "z"):
            return .redoKeyboardShortcut
        default:
            return nil
        }
    }

    private func rememberObservedKeyboardShortcut(
        _ rawInput: CanvasRawInputIntent,
        now: Date = Date()
    ) {
        pruneObservedKeyboardShortcuts(asOf: now)
        observedKeyboardShortcuts.append(
            ObservedKeyboardShortcut(
                rawInput: rawInput,
                observedAt: now
            )
        )
    }

    private func consumeObservedKeyboardShortcut(
        _ rawInput: CanvasRawInputIntent,
        now: Date = Date()
    ) -> Bool {
        pruneObservedKeyboardShortcuts(asOf: now)
        guard let index = observedKeyboardShortcuts.firstIndex(where: {
            $0.rawInput == rawInput
        }) else {
            return false
        }

        observedKeyboardShortcuts.remove(at: index)
        return true
    }

    private func pruneObservedKeyboardShortcuts(
        asOf now: Date = Date()
    ) {
        observedKeyboardShortcuts.removeAll { observedShortcut in
            now.timeIntervalSince(observedShortcut.observedAt)
                > Self.observedKeyboardShortcutReuseWindow
        }
    }

    private func isCurrentKeyboardShortcut(
        _ rawInput: CanvasRawInputIntent
    ) -> Bool {
        observedKeyboardShortcutRawInput(from: NSApp.currentEvent) == rawInput
    }

    private func resolvedPasteTransferEntryIntent() -> CanvasTransferEntryIntent {
        if NSApp.currentEvent?.type == .keyDown {
            return .pasteKeyboardShortcut
        }

        return .pasteMenu
    }

    private func canTransferContent(
        from pasteboard: NSPasteboard,
        entry: CanvasTransferEntryIntent
    ) -> Bool {
        isTransferEntryAllowed(entry) &&
            macOSCanvasImportAdapter.canResolveTransfer(from: pasteboard)
    }

    private func handlePasteRequest() {
        guard let transferRequest = macOSCanvasImportAdapter.transferRequest(
            from: .general,
            sourceDescription: "pasteboard"
        ) else {
            return
        }

        _ = performTransferRequest(transferRequest)
    }

    private func dragOperation(for pasteboard: NSPasteboard) -> NSDragOperation {
        canTransferContent(from: pasteboard, entry: .dragAndDrop) ? .copy : []
    }

    private func handleImportDrop(
        pasteboard: NSPasteboard
    ) -> Bool {
        guard let transferRequest = macOSCanvasImportAdapter.transferRequest(
            from: pasteboard,
            sourceDescription: "drag and drop"
        ) else {
            return false
        }

        let didImport = performTransferRequest(transferRequest)
        if didImport {
            view.window?.makeFirstResponder(canvasViewportView)
        }

        return didImport
    }

    @discardableResult
    private func performTransferRequest(
        _ request: CanvasTransferRequest
    ) -> Bool {
        if let reason = transferSafetyNetBlockReason() {
            logTransferSafetyNetBlock(request: request, reason: reason)
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

    func textDidChange(_ notification: Notification) {
        guard
            let textView = notification.object as? NSTextView,
            textView === textEditorOverlayView.textView,
            isSyncingTextEditorContent == false,
            editorSession.updateTextEditDraft(textView.string)
        else {
            return
        }

        refreshCanvas(reason: "update text edit draft")
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

    private func toggleSelectionMembership(
        of itemID: CanvasItemID,
        recordHistory: Bool = false
    ) {
        performCommand(
            .toggleSelectionMembership(
                itemID: itemID,
                recordHistory: recordHistory
            )
        )
    }

    private func clearSelectionIfNeeded(recordHistory: Bool = false) {
        performCommand(.clearSelection(recordHistory: recordHistory))
    }

    private func executeClickSelectionDecision(
        _ decision: CanvasClickSelectionDecision
    ) -> (result: String, didTriggerPressedRefresh: Bool) {
        let interactionStateBefore = interactionState

        switch decision.action {
        case .none:
            return ("selection_unchanged", false)
        case let .selectSingle(itemID):
            selectItem(withID: itemID, recordHistory: true)
            let didChangeSelection = interactionStateBefore != interactionState
            return (
                didChangeSelection ? "item_selected" : "selection_unchanged",
                didChangeSelection
            )
        case let .toggleMembership(itemID):
            let wasSelected = interactionStateBefore.selectedItemIDs.contains(itemID)
            toggleSelectionMembership(of: itemID, recordHistory: true)
            let didChangeSelection = interactionStateBefore != interactionState
            guard didChangeSelection else {
                return ("selection_unchanged", false)
            }
            return (
                wasSelected
                    ? "item_removed_from_selection"
                    : "item_added_to_selection",
                true
            )
        case .clearSelection:
            clearSelectionIfNeeded(recordHistory: true)
            let didChangeSelection = interactionStateBefore != interactionState
            return (
                didChangeSelection ? "selection_cleared" : "selection_unchanged",
                didChangeSelection
            )
        case let .attemptTextEdit(itemID):
            if beginTextEditIfPossible(for: itemID) {
                return ("text_edit_began", true)
            }
            return ("selection_unchanged", false)
        }
    }

    private func logClickResult(
        target: String,
        result: String,
        pressedItemID: CanvasItemID?,
        releasedItemID: CanvasItemID?,
        previousInteractionState: CanvasInteractionState,
        currentInteractionState: CanvasInteractionState,
        affectedItemID: CanvasItemID?
    ) {
        print(
            "[Canvas macOS][ClickSelection] " +
            "target=\(target) " +
            "result=\(result) " +
            "pressedItemID=\(describe(itemID: pressedItemID)) " +
            "releasedItemID=\(describe(itemID: releasedItemID)) " +
            "previousSelection=\(describe(selectionState: previousInteractionState)) " +
            "currentSelection=\(describe(selectionState: currentInteractionState)) " +
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

    private func makeSelectionRotateState(
        initialViewportLocation: CGPoint
    ) -> CanvasSelectionRotateState? {
        guard
            inlineEditState == nil,
            interactionState.selectionCount > 1,
            let snapshot = currentSelectionTransformSnapshot()
        else {
            return nil
        }

        let initialPointerAngle = angle(
            from: snapshot.selectionCenter,
            to: camera.viewportToWorld(initialViewportLocation)
        )
        return CanvasSelectionRotateState(
            snapshot: snapshot,
            rotationOffsetToPointerAngle: normalizedCanvasAngle(-initialPointerAngle)
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
            item: item,
            draftRotationRadians: draftRotationRadians
        )
        refreshCanvas()
    }

    private func updateSelectionRotationDraft(
        using rotateState: CanvasSelectionRotateState,
        to viewportLocation: CGPoint
    ) {
        guard
            inlineEditState == nil,
            interactionStateMatchesSelection(
                itemIDs: rotateState.snapshot.memberItemIDs
            ),
            interactionState.selectionCount > 1,
            rotationInteractionState.map({
                Set($0.memberItemIDs) == Set(rotateState.snapshot.memberItemIDs)
            }) == true
        else {
            return
        }

        let pointerWorldLocation = camera.viewportToWorld(viewportLocation)
        let draftRotationRadians = rotateState.draftRotationRadians(
            for: pointerWorldLocation
        )
        guard !anglesMatch(
            rotationPreviewState?.displayRotationRadians ?? 0,
            draftRotationRadians
        ) else {
            return
        }

        rotationPreviewState = CanvasRotationPreviewState(
            snapshot: rotateState.snapshot,
            draftGeometries: rotateState.rotatedMemberGeometries(
                for: pointerWorldLocation
            ),
            displayRotationRadians: draftRotationRadians
        )
        refreshCanvas(reason: "update rotate selection draft")
    }

    private func commitRotationDraftIfNeeded() {
        guard let rotationPreviewState else {
            cancelRotationInteractionIfNeeded(
                refreshAfterCancellation: true
            )
            return
        }

        guard rotationPreviewState.draftGeometries.allSatisfy({
            scene.boardItem(withID: $0.itemID) != nil
        }) else {
            cancelRotationInteractionIfNeeded(
                refreshAfterCancellation: true
            )
            return
        }

        let needsCommit = rotationPreviewState.draftGeometries.contains { geometry in
            guard let item = scene.boardItem(withID: geometry.itemID) else {
                return false
            }
            return item.center != geometry.center ||
                item.size != geometry.size ||
                anglesMatch(item.rotationRadians, geometry.rotationRadians) == false
        }
        guard needsCommit else {
            cancelRotationInteractionIfNeeded(
                refreshAfterCancellation: true
            )
            return
        }

        guard let rotatedItems = scene.applyBoardItemGeometries(
            rotationPreviewState.draftGeometries
        ) else {
            cancelRotationInteractionIfNeeded(
                refreshAfterCancellation: true
            )
            return
        }

        if let rotatedBounds = worldBounds(for: rotatedItems) {
            expandBoardIfNeeded(toInclude: rotatedBounds)
        }
        clearRotationTransientState()
        refreshCanvas(reason: rotationPreviewState.memberItemIDs.count > 1
            ? "commit rotate selection"
            : "commit rotate item")
        commitPendingPointerHistoryTransaction(
            autosaveReason: rotationPreviewState.memberItemIDs.count > 1
                ? "rotate selection"
                : "rotate item"
        )
    }

    private func displayedRotationRadians(for item: CanvasBoardItem) -> CGFloat {
        guard
            let rotationPreviewState,
            let previewGeometry = rotationPreviewState.geometry(for: item.id)
        else {
            return item.rotationRadians
        }

        return previewGeometry.rotationRadians
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
        refreshCanvas()
    }

    private func beginRotationInteraction(
        for snapshot: CanvasSelectionTransformSnapshot
    ) {
        guard interactionStateMatchesSelection(itemIDs: snapshot.memberItemIDs) else {
            return
        }

        let interactionState = CanvasRotationInteractionState(
            primaryItemID: snapshot.primaryItemID,
            memberItemIDs: snapshot.memberItemIDs
        )
        guard rotationInteractionState?.memberItemIDs != interactionState.memberItemIDs else {
            return
        }

        rotationInteractionState = interactionState
        refreshCanvas(reason: "begin rotate selection interaction")
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
            refreshCanvas(reason: refreshReason)
        }
        return true
    }

    private func cancelRotationInteractionIfNeeded(
        resetPointerDragState: Bool = false,
        refreshAfterCancellation: Bool = false
    ) {
        let hadVisibleRotationState =
            rotationPreviewState != nil || rotationInteractionState != nil
        let wasRotating: Bool
        switch pointerDragState {
        case .rotatingSelectedItem, .rotatingSelection:
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

    private func makeSelectedItemDragState(
        itemID: CanvasItemID,
        initialViewportLocation: CGPoint
    ) -> CanvasSelectedItemDragState? {
        guard let movingItem = scene.boardItem(withID: itemID) else {
            return nil
        }

        return CanvasSelectedItemDragState(
            itemID: itemID,
            dragStartWorldLocation: camera.viewportToWorld(initialViewportLocation),
            dragStartCenter: movingItem.center
        )
    }

    private func makeSelectionDragState(
        initialViewportLocation: CGPoint
    ) -> CanvasSelectionDragState? {
        guard
            interactionState.selectionCount > 1,
            let snapshot = currentSelectionTransformSnapshot()
        else {
            return nil
        }

        return CanvasSelectionDragState(
            snapshot: snapshot,
            dragStartWorldLocation: camera.viewportToWorld(initialViewportLocation)
        )
    }

    private func moveSelectedItem(
        using dragState: CanvasSelectedItemDragState,
        to location: CGPoint
    ) -> CanvasSelectedItemDragState? {
        guard let movingItem = scene.boardItem(withID: dragState.itemID) else {
            clearAlignmentInteractionStateIfNeeded(
                refreshReason: "clear missing alignment interaction item"
            )
            return nil
        }

        let currentWorldLocation = camera.viewportToWorld(location)
        let proposedCenter = dragState.proposedCenter(
            for: currentWorldLocation
        )
        let solveResult = alignmentGuideSolver.solve(
            CanvasAlignmentSolveRequest(
                movingItemID: dragState.itemID,
                proposedCenter: proposedCenter,
                scene: scene,
                boardState: boardState,
                camera: camera,
                lockState: dragState.alignmentLock
            )
        )
        let resolvedDeltaInWorld = CGPoint(
            x: solveResult.resolvedCenter.x - movingItem.center.x,
            y: solveResult.resolvedCenter.y - movingItem.center.y
        )

        alignmentInteractionState = solveResult.interactionState
        scene.moveItem(withID: dragState.itemID, by: resolvedDeltaInWorld)
        if let movedItem = scene.boardItem(withID: dragState.itemID) {
            expandBoardIfNeeded(toInclude: movedItem.worldBounds)
        }
        refreshCanvas(
            reason: "move selected item by \(describe(point: resolvedDeltaInWorld))"
        )
        return dragState.replacingAlignmentLock(solveResult.lockState)
    }

    private func moveSelection(
        using dragState: CanvasSelectionDragState,
        to location: CGPoint
    ) -> CanvasSelectionDragState? {
        guard interactionStateMatchesSelection(itemIDs: dragState.snapshot.memberItemIDs) else {
            clearAlignmentInteractionStateIfNeeded(
                refreshReason: "clear stale selection alignment interaction"
            )
            return nil
        }

        let currentWorldLocation = camera.viewportToWorld(location)
        let proposedBounds = dragState.proposedBounds(
            for: currentWorldLocation
        )
        let solveResult = alignmentGuideSolver.solve(
            CanvasAlignmentSolveRequest(
                primaryMovingItemID: dragState.snapshot.primaryItemID,
                movingItemIDs: dragState.snapshot.memberItemIDs,
                movingBounds: proposedBounds,
                scene: scene,
                boardState: boardState,
                camera: camera,
                lockState: dragState.alignmentLock
            )
        )
        let resolvedTranslation = CGPoint(
            x: solveResult.resolvedBounds.midX - dragState.snapshot.selectionBounds.midX,
            y: solveResult.resolvedBounds.midY - dragState.snapshot.selectionBounds.midY
        )
        guard let movedItems = scene.applyBoardItemGeometries(
            dragState.snapshot.translatedMemberGeometries(
                by: resolvedTranslation
            )
        ) else {
            clearAlignmentInteractionStateIfNeeded(
                refreshReason: "clear failed selection alignment interaction"
            )
            return nil
        }

        alignmentInteractionState = solveResult.interactionState
        if let movedBounds = worldBounds(for: movedItems) {
            expandBoardIfNeeded(toInclude: movedBounds)
        }
        refreshCanvas(
            reason: "move selection by \(describe(point: resolvedTranslation))"
        )
        return dragState.replacingAlignmentLock(solveResult.lockState)
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

    private func makeSelectionResizeState(
        handleRole: CanvasSelectionHandleRole
    ) -> CanvasSelectionResizeState? {
        guard
            interactionState.selectionCount > 1,
            let snapshot = currentSelectionTransformSnapshot(),
            snapshot.selectionBounds.width > 0,
            snapshot.selectionBounds.height > 0
        else {
            return nil
        }

        let minimumWorldDimension = Self.minimumResizeViewportDimension / camera.zoomScale
        let minimumScale = max(
            minimumWorldDimension / snapshot.selectionBounds.width,
            minimumWorldDimension / snapshot.selectionBounds.height
        )
        return CanvasSelectionResizeState(
            snapshot: snapshot,
            handleRole: handleRole,
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
        refreshCanvas()
    }

    private func resizeSelection(
        using resizeState: CanvasSelectionResizeState,
        to viewportLocation: CGPoint
    ) {
        guard interactionStateMatchesSelection(itemIDs: resizeState.snapshot.memberItemIDs) else {
            return
        }

        guard
            let resizedItems = resizeState.resizedMemberItems(
                for: camera.viewportToWorld(viewportLocation)
            ),
            let appliedItems = scene.applyBoardItems(resizedItems),
            let resizedBounds = worldBounds(for: appliedItems)
        else {
            return
        }

        expandBoardIfNeeded(toInclude: resizedBounds)
        refreshCanvas(reason: "resize selection to \(describe(rect: resizedBounds))")
    }

    private func currentSelectionTransformSnapshot() -> CanvasSelectionTransformSnapshot? {
        CanvasSelectionTransformSnapshot(
            scene: scene,
            interactionState: interactionState
        )
    }

    private func interactionStateMatchesSelection(
        itemIDs: [CanvasItemID]
    ) -> Bool {
        Set(interactionState.selectedItemIDs) == Set(itemIDs)
    }

    private func worldBounds(
        for items: [CanvasBoardItem]
    ) -> CGRect? {
        let bounds = items.reduce(into: CGRect.null) { partialResult, item in
            partialResult = partialResult.union(item.worldBounds.standardized)
        }
        return bounds.isNull ? nil : bounds.standardized
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
        scheduleAutosave(
            reason: "drag canvas",
            updateKind: .viewStateOnly
        )
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
        updateWorkspaceModeButtonAppearance()
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
        updateWorkspaceModeButtonAppearance()
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
        updateWorkspaceModeButtonAppearance()
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
        updateWorkspaceModeButtonAppearance()
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
        for pressContext: CanvasPointerPressContext
    ) {
        let reason: String
        switch pressContext.targetKind {
        case .rotateHandle:
            reason = "rotate item"
        case .groupRotateHandle:
            reason = "rotate selection"
        case .cropHandle, .cropTranslationArea:
            reason = "crop item"
        case .selectionHandle:
            reason = "resize item"
        case .groupSelectionHandle:
            reason = "resize selection"
        case .selectionTranslationArea, .selectedItemBody:
            reason = interactionState.selectionCount > 1
                ? "move selection"
                : "move item"
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
        updateInlineEditButtonsAppearance()
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
        updateInlineEditButtonsAppearance()
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

    private func scheduleAutosave(
        reason: String,
        updateKind: BoardPersistenceUpdateKind = .contentAndViewState
    ) {
        editorSession.scheduleAutosave(
            reason: reason,
            updateKind: updateKind
        )
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

    private func handleImmediateBoardSaveResult(
        _ result: Result<Void, Error>,
        missingFolderMessage: String,
        onSuccess: (() -> Void)? = nil
    ) {
        switch result {
        case .success:
            showSaveButtonFeedback(.success)
            onSuccess?()
        case let .failure(error):
            if case FolderBookmarkStoreError.missingBookmarkData = error {
                showSaveButtonFeedback(.missingFolder)
                presentSaveError(message: missingFolderMessage)
            } else {
                showSaveButtonFeedback(.failure)
                presentSaveError(message: error.localizedDescription)
            }
        }
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
        handleInteractionAttempt(
            .beginTextEdit(itemID: itemID),
            sourceDescription: "itemClickReentry"
        ) {
            guard scene.textItem(withID: itemID) != nil else {
                return false
            }

            performCommand(.beginTextEdit(itemID: itemID))
            return isInlineTextModeActive
        }
    }

    private func syncTextEditorPresentation() {
        guard isViewLoaded else {
            return
        }

        guard
            let inlineEditState = presentationInlineEditState,
            inlineEditState.mode == .text,
            let textItem = editorSession.activeInlineTextItem
        else {
            if view.window?.firstResponder === textEditorOverlayView.textView {
                view.window?.makeFirstResponder(canvasViewportView)
            }
            textEditorOverlayView.isHidden = true
            activeTextEditorItemID = nil
            return
        }

        let didChangeEditedItem = activeTextEditorItemID != inlineEditState.itemID
        activeTextEditorItemID = inlineEditState.itemID
        textEditorOverlayView.isHidden = false
        let decreaseFontSizeDescriptor = commandDescriptor(for: .decreaseTextFontSize)
        let increaseFontSizeDescriptor = commandDescriptor(for: .increaseTextFontSize)
        isSyncingTextEditorContent = true
        textEditorOverlayView.apply(
            text: inlineEditState.draftText,
            style: textItem.style,
            canDecreaseFontSize: decreaseFontSizeDescriptor.isEnabled,
            canIncreaseFontSize: increaseFontSizeDescriptor.isEnabled
        )
        isSyncingTextEditorContent = false

        guard let window = view.window else {
            return
        }

        if window.firstResponder !== textEditorOverlayView.textView {
            window.makeFirstResponder(textEditorOverlayView.textView)
        }

        if didChangeEditedItem {
            textEditorOverlayView.textView.selectAll(nil)
        }
    }

    private func makeToolbarState() -> CanvasToolbarState {
        toolbarStateBuilder.mainToolbarState(
            session: editorSession,
            saveState: saveButtonState,
            placement: toolbarPreferredPlacement(),
            supportsHandDrawingEditing: supportsHandDrawingEditing,
            isMultiSelectModeActive: isMultiSelectModeActive,
            includesHistoryItems: true
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
        updatePreparedToolbarPlacement()
        syncTextEditorPresentation()
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

    private func presentImportError(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Unable to Import Media"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")

        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func presentVideoEditorError(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Unable to Open Video Editor"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")

        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func presentGIFFrameImportEditorError(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Unable to Open GIF Frame Importer"
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

    private func describe(
        toolbarTransitionDirection: CanvasToolbarTransitionDirection
    ) -> String {
        switch toolbarTransitionDirection {
        case .toReading:
            return "toReading"
        case .toEditing:
            return "toEditing"
        }
    }

    private func describe(
        toolbarTransitionStage: CanvasToolbarTransitionStage
    ) -> String {
        switch toolbarTransitionStage {
        case .steadyVisible:
            return "steadyVisible"
        case let .collapsing(progress):
            return "collapsing(\(formatCoordinate(progress)))"
        case let .exiting(progress):
            return "exiting(\(formatCoordinate(progress)))"
        case .hidden:
            return "hidden"
        case let .entering(progress):
            return "entering(\(formatCoordinate(progress)))"
        case let .expanding(progress):
            return "expanding(\(formatCoordinate(progress)))"
        }
    }

    private func describe(miniMapAnchor: CanvasMiniMapAnchor) -> String {
        switch miniMapAnchor {
        case .topLeading:
            return "topLeading"
        case .topTrailing:
            return "topTrailing"
        case .bottomLeading:
            return "bottomLeading"
        case .bottomTrailing:
            return "bottomTrailing"
        }
    }

    private func describe(
        chromeBlocker: CanvasChromeBlocker
    ) -> String {
        "\(chromeBlocker.kind.rawValue)=\(describe(rect: chromeBlocker.rect))"
    }

    private func describe(itemID: CanvasItemID?) -> String {
        itemID?.uuidString ?? "nil"
    }

    private func describe(selectionState: CanvasInteractionState) -> String {
        let selectedItemIDs = selectionState.selectedItemIDs
            .map(\.uuidString)
            .joined(separator: ",")
        return "primary=\(describe(itemID: selectionState.primarySelectedItemID)) members=[\(selectedItemIDs)]"
    }

    private func describe(pointerModifiers: CanvasPointerModifiers) -> String {
        "command=\(pointerModifiers.isCommandPressed) " +
        "shift=\(pointerModifiers.isShiftPressed) " +
        "option=\(pointerModifiers.isOptionPressed) " +
        "control=\(pointerModifiers.isControlPressed)"
    }

    private func describe(editOverlay: CanvasEditRenderOverlay?) -> String {
        guard let editOverlay else {
            return "nil"
        }

        return "itemID=\(editOverlay.itemID.uuidString) kind=\(String(describing: editOverlay.kind)) activeScreenQuad=\(describe(rect: editOverlay.activeScreenQuad.boundingRect.standardized))"
    }

    private func logToolbarTransitionContext(
        _ context: CanvasToolbarTransitionContext
    ) {
        let safeBounds = toolbarLayoutSafeBounds()
        let slideDelta = CGPoint(
            x: context.frames.offscreenFrame.minX - context.frames.collapsedFrame.minX,
            y: context.frames.offscreenFrame.minY - context.frames.collapsedFrame.minY
        )
        let itemIDs = context.visibleSnapshot.state.items
            .map(\.id.rawValue)
            .joined(separator: ",")

        print(
            "[Canvas macOS][ToolbarTransition] " +
            "event=contextBuilt " +
            "direction=\(describe(toolbarTransitionDirection: context.direction)) " +
            "placementEdge=\(context.visibleSnapshot.state.placement.preferredEdge.rawValue) " +
            "preferredAxis=\(context.visibleSnapshot.state.preferredAxis.rawValue) " +
            "overlayIsFlipped=\(chromeOverlayView.isFlipped) " +
            "hostSuperviewIsFlipped=\(toolbarHostView.superview?.isFlipped ?? false) " +
            "hostIsFlipped=\(toolbarHostView.isFlipped) " +
            "safeBounds=\(describe(rect: safeBounds)) " +
            "currentHostFrame=\(describe(rect: toolbarHostView.frame)) " +
            "visibleFrame=\(describe(rect: context.frames.visibleFrame)) " +
            "collapsedFrame=\(describe(rect: context.frames.collapsedFrame)) " +
            "offscreenFrame=\(describe(rect: context.frames.offscreenFrame)) " +
            "slideDelta=\(describe(point: slideDelta)) " +
            "slideDirection=\(toolbarSlideDirectionDescription(for: context.frames)) " +
            "collapseVerticalAnchor=\(toolbarCollapseVerticalAnchorDescription(for: context.frames)) " +
            "items=[\(itemIDs)]"
        )
    }

    private func logToolbarTransitionAnimation(
        context: CanvasToolbarTransitionContext,
        stage: CanvasToolbarTransitionStage,
        presentation: CanvasToolbarTransitionPresentation,
        duration: TimeInterval
    ) {
        print(
            "[Canvas macOS][ToolbarTransition] " +
            "event=animate " +
            "direction=\(describe(toolbarTransitionDirection: context.direction)) " +
            "stage=\(describe(toolbarTransitionStage: stage)) " +
            "duration=\(formatCoordinate(duration)) " +
            "currentHostFrame=\(describe(rect: toolbarHostView.frame)) " +
            "targetFrame=\(describe(rect: presentation.frame)) " +
            "targetAlpha=\(formatCoordinate(presentation.contentAlpha)) " +
            "targetScale=\(formatCoordinate(presentation.contentScale)) " +
            "keepsHostVisible=\(presentation.keepsHostVisible) " +
            "isInteractive=\(presentation.isInteractive)"
        )
    }

    private func logChromeOverlayLayoutPass(
        safeBounds: CGRect,
        baseChromeBlockers: [CanvasChromeBlocker],
        chromeLayoutContext: CanvasChromeLayoutContext,
        miniMapFrame: CGRect
    ) {
        let sanitizedMiniMapFrame = CanvasChromeLayoutGeometry.sanitizedRect(
            miniMapFrame
        ) ?? .zero
        let sanitizedBackButtonFrame = CanvasChromeLayoutGeometry.sanitizedRect(
            backButton.frame
        ) ?? .zero
        let sanitizedModeToggleFrame = CanvasChromeLayoutGeometry.sanitizedRect(
            workspaceModeButton.frame
        ) ?? .zero
        let sanitizedToolbarFrame = chromeLayoutContext.chromeBlockers
            .first(where: { $0.kind == .toolbar })?.rect ?? .zero
        let layoutBounds = CanvasChromeLayoutGeometry.sanitizedRect(
            safeBounds.insetBy(
                dx: miniMapConfiguration.edgeInset,
                dy: miniMapConfiguration.edgeInset
            )
        ) ?? .zero
        let overlapBackButtonArea = intersectionArea(
            between: sanitizedMiniMapFrame,
            and: sanitizedBackButtonFrame
        )
        let overlapModeToggleArea = intersectionArea(
            between: sanitizedMiniMapFrame,
            and: sanitizedModeToggleFrame
        )
        let overlapToolbarArea = intersectionArea(
            between: sanitizedMiniMapFrame,
            and: sanitizedToolbarFrame
        )
        let baseBlockersDescription = baseChromeBlockers
            .map(describe(chromeBlocker:))
            .joined(separator: ", ")
        let occupiedRectsDescription = chromeLayoutContext.chromeBlockers
            .map(describe(chromeBlocker:))
            .joined(separator: ", ")

        print(
            "[Canvas macOS][ChromeOverlayLayout] " +
            "event=miniMapLayout " +
            "overlayIsFlipped=\(chromeOverlayView.isFlipped) " +
            "preferredMiniMapAnchor=\(describe(miniMapAnchor: miniMapConfiguration.preferredAnchor)) " +
            "visualPreferredMiniMapAnchor=\(visualMiniMapAnchorDescription()) " +
            "safeBounds=\(describe(rect: safeBounds)) " +
            "layoutBounds=\(describe(rect: layoutBounds)) " +
            "backButtonFrame=\(describe(rect: sanitizedBackButtonFrame)) " +
            "modeToggleFrame=\(describe(rect: sanitizedModeToggleFrame)) " +
            "toolbarFrame=\(describe(rect: sanitizedToolbarFrame)) " +
            "miniMapFrame=\(describe(rect: sanitizedMiniMapFrame)) " +
            "miniMapHidden=\(miniMapMountView.isHidden) " +
            "overlapBackButton=\(overlapBackButtonArea > 0) " +
            "overlapBackButtonArea=\(formatCoordinate(overlapBackButtonArea)) " +
            "overlapModeToggle=\(overlapModeToggleArea > 0) " +
            "overlapModeToggleArea=\(formatCoordinate(overlapModeToggleArea)) " +
            "overlapToolbar=\(overlapToolbarArea > 0) " +
            "overlapToolbarArea=\(formatCoordinate(overlapToolbarArea)) " +
            "baseBlockers=[\(baseBlockersDescription)] " +
            "occupiedRects=[\(occupiedRectsDescription)]"
        )
    }

    private func toolbarSlideDirectionDescription(
        for frames: CanvasToolbarTransitionFrames
    ) -> String {
        let deltaX = frames.offscreenFrame.minX - frames.collapsedFrame.minX
        let deltaY = frames.offscreenFrame.minY - frames.collapsedFrame.minY

        if abs(deltaX) >= 0.5, abs(deltaY) < 0.5 {
            return deltaX > 0 ? "right(+x)" : "left(-x)"
        }

        if abs(deltaY) >= 0.5, abs(deltaX) < 0.5 {
            if chromeOverlayView.isFlipped {
                return deltaY > 0 ? "down(+y in flipped)" : "up(-y in flipped)"
            }

            return deltaY > 0 ? "up(+y in nonflipped)" : "down(-y in nonflipped)"
        }

        if abs(deltaX) < 0.5, abs(deltaY) < 0.5 {
            return "none"
        }

        return "diagonal"
    }

    private func toolbarCollapseVerticalAnchorDescription(
        for frames: CanvasToolbarTransitionFrames
    ) -> String {
        if abs(frames.visibleFrame.minY - frames.collapsedFrame.minY) < 0.5 {
            return chromeOverlayView.isFlipped
                ? "top(minY preserved in flipped container)"
                : "bottom(minY preserved in nonflipped container)"
        }

        if abs(frames.visibleFrame.maxY - frames.collapsedFrame.maxY) < 0.5 {
            return chromeOverlayView.isFlipped
                ? "bottom(maxY preserved in flipped container)"
                : "top(maxY preserved in nonflipped container)"
        }

        return "custom"
    }

    private func visualMiniMapAnchorDescription() -> String {
        let semanticAnchor = miniMapConfiguration.preferredAnchor
        if chromeOverlayView.isFlipped {
            return describe(miniMapAnchor: semanticAnchor)
        }

        switch semanticAnchor {
        case .topLeading:
            return "bottomLeading(nonflipped)"
        case .topTrailing:
            return "bottomTrailing(nonflipped)"
        case .bottomLeading:
            return "topLeading(nonflipped)"
        case .bottomTrailing:
            return "topTrailing(nonflipped)"
        }
    }

    private func intersectionArea(
        between lhs: CGRect,
        and rhs: CGRect
    ) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard intersection.isNull == false, intersection.isEmpty == false else {
            return 0
        }

        return intersection.width * intersection.height
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
        case .rotatingSelection:
            return "rotatingSelection"
        case .draggingSelectedItem:
            return "draggingSelectedItem"
        case .draggingSelection:
            return "draggingSelection"
        case .resizingSelectedItem:
            return "resizingSelectedItem"
        case .resizingSelection:
            return "resizingSelection"
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
            "[Canvas macOS][ContextMenuPosition] " +
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

    private func formatCoordinate(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }
}

private enum macOSVideoEditorFlowError: LocalizedError {
    case presenterUnavailable

    var errorDescription: String? {
        switch self {
        case .presenterUnavailable:
            "The canvas editor is no longer available."
        }
    }
}

private enum macOSGIFFrameImportFlowError: LocalizedError {
    case presenterUnavailable

    var errorDescription: String? {
        switch self {
        case .presenterUnavailable:
            "The canvas editor is no longer available."
        }
    }
}
#endif
