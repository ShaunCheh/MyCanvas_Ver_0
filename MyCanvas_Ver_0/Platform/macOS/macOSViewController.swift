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

private func macOSGroupTitleEditTrace(
    _ phase: String,
    groupID: CanvasItemGroupID? = nil,
    editingGroupTitleID: CanvasItemGroupID? = nil,
    title: String? = nil,
    firstResponder: NSResponder? = nil,
    detail: String? = nil
) {
    let groupIDDescription = groupID?.uuidString ?? "nil"
    let editingGroupIDDescription = editingGroupTitleID?.uuidString ?? "nil"
    let titleDescription = title.map { "\"\($0)\"" } ?? "nil"
    let responderDescription = firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
    let detailDescription = detail ?? "nil"
    print(
        "[Canvas macOS][GroupTitleEdit] " +
        "phase=\(phase) " +
        "groupID=\(groupIDDescription) " +
        "editingGroupTitleID=\(editingGroupIDDescription) " +
        "title=\(titleDescription) " +
        "firstResponder=\(responderDescription) " +
        "detail=\(detailDescription)"
    )
}

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

    private struct PointerGroupDragState {
        let groupID: CanvasItemGroupID
        let initialFrame: CGRect
        let initialSubtreeGeometries: CanvasGroupSubtreeGeometries
        let dragStartWorldLocation: CGPoint
    }

    private struct PointerGroupResizeState {
        let groupID: CanvasItemGroupID
        let handleRole: CanvasSelectionHandleRole
        let initialFrame: CGRect
        let initialDraggedAnchor: CGPoint
        let dragStartWorldLocation: CGPoint
        let minimumSize: CGSize
    }

    private struct CameraCenterAnimationState {
        let startCenter: CGPoint
        let targetCenter: CGPoint
        let startTimestamp: CFTimeInterval
        let refreshReason: String
        let autosaveReason: String
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
        case draggingGroupFrame(PointerGroupDragState)
        case resizingGroupFrame(PointerGroupResizeState)
        case resizingSelectedItem(PointerResizeState)
        case adjustingArrowEndpoint(CanvasArrowEndpointDragState)
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

    private enum OverlayEditorPresentationState: Equatable {
        case none
        case videoDisplayFrame
        case gifFrameImport
        case markdown
    }

    private struct ObservedKeyboardShortcut {
        let rawInput: CanvasRawInputIntent
        let observedAt: Date
    }

    private static let pointerDragActivationDistance: CGFloat = 4
    private static let selectionHandleHitTargetSize: CGFloat = 18
    private static let selectionOutlineHitTargetWidth: CGFloat = 14
    private static let minimumResizeViewportDimension: CGFloat = 20
    private static let minimumGroupFrameSize = CGSize(width: 80, height: 60)
    private static let cropHandleHitTargetSize: CGFloat = 18
    private static let cropOutlineHitTargetWidth: CGFloat = 14
    private static let minimumCropViewportDimension: CGFloat = 20
    private static let rotateHandleHitTargetSize: CGFloat = 22
    private static let geometryComparisonEpsilon: CGFloat = 0.0001
    private static let markdownScrollHistoryCommitDelay: TimeInterval = 0.25
    private static let isSelectionAccessoryTraceLoggingEnabled = true
    private static let isPointerHitTraceLoggingEnabled = true
    private static let observedKeyboardShortcutReuseWindow: TimeInterval = 0.45
    private static let continuousRawInputObservationInterval: TimeInterval = 0.32
    private static let groupListNavigationAnimationDuration: TimeInterval = 0.28
    private static let showsMiniMap = false

    private let miniMapLayoutSolver = CanvasOverlayLayoutSolver()
    private let alignmentGuideSolver = CanvasAlignmentGuideSolver()
    var miniMapConfiguration = CanvasMiniMapConfiguration()
    var launchContext: CanvasLaunchContext?
    var onReturnToBoardList: ((BoardListCanvasReturnRequest) -> Void)?
    private let editorSession = CanvasEditorSession(
        saveQueueLabel: "MyCanvas.BoardSave.macOS",
        logPrefix: "[BoardStore][macOS]"
    )
    private var isMarkdownScrollHistoryTransactionActive = false
    private var markdownScrollHistoryCommitWorkItem: DispatchWorkItem?
    private var activeOverlayEditorPresentationState: OverlayEditorPresentationState = .none
    private let commandCatalog = CanvasCommandCatalog()
    private let selectionAccessoryResolver =
        CanvasSelectionAccessoryResolver()
    private let toolbarStateBuilder = CanvasToolbarStateBuilder()
    private let contextMenuActionResolver = CanvasContextMenuActionResolver()
    private let clickSelectionResolver = CanvasClickSelectionResolver()
    private let interactionPolicy = CanvasInteractionPolicy()
    private let inputRoutingResolver = CanvasInputRoutingResolver()
    private let canvasHostView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
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
        button.layer?.borderWidth = 1
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
        button.layer?.borderWidth = 1
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
    private let groupListButton: NSButton = {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.title = ""
        button.toolTip = "Canvas groups"
        button.wantsLayer = true
        button.layer?.cornerRadius = 22
        button.layer?.masksToBounds = true
        button.layer?.borderWidth = 1
        button.contentTintColor = .labelColor
        if let image = NSImage(
            systemSymbolName: "rectangle.3.group",
            accessibilityDescription: "Canvas groups"
        ) {
            button.image = image
            button.imagePosition = .imageOnly
        }
        return button
    }()
    private let groupListView: macOSCanvasGroupListView = {
        let view = macOSCanvasGroupListView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
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
    private var toolbarManualTransitionTimer: Timer?
    private var toolbarManualTransitionID = UUID()
    private var groupListNavigationTimer: Timer?
    private var groupListNavigationAnimationState: CameraCenterAnimationState?
    private var preservedHiddenToolbarFrame: CGRect?
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
    private let selectionAccessoryHostView = SelectionAccessoryHostView()
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
    private let deleteSelectionButton: NSButton = {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let textButton: NSButton = {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let markdownButton: NSButton = {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let handDrawingButton: NSButton = {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let arrowButton: NSButton = {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let groupButton: NSButton = {
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
            .deleteSelection: deleteSelectionButton,
            .save: saveButton,
            .text: textButton,
            .markdown: markdownButton,
            .handDrawing: handDrawingButton,
            .arrow: arrowButton,
            .group: groupButton,
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
    private var isGroupListVisible = false
    private var editingGroupTitleID: CanvasItemGroupID?
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
        cancelGroupListNavigationAnimation()
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
        updateGroupListPresentation()
        if let followUp = executionResult.followUp {
            handleCommandFollowUp(followUp)
        }
    }

    private func handleCommandFollowUp(_ followUp: CanvasCommandFollowUp) {
        switch followUp {
        case .presentHandDrawingEditor:
            return
        case let .presentMarkdownEditor(itemID):
            presentMarkdownEditor(for: itemID)
        }
    }

    private func performSelectionAccessoryCommand(_ commandID: CanvasCommandID) {
        switch commandID {
        case .beginMarkdownEdit:
            guard let itemID = selectionAccessoryHostView.currentState?.itemID else {
                return
            }
            performCommand(.beginMarkdownEdit(itemID: itemID))
        case .decreaseMarkdownContentSize:
            performCommand(.decreaseMarkdownContentSize)
        case .increaseMarkdownContentSize:
            performCommand(.increaseMarkdownContentSize)
        case .decreaseArrowThickness:
            performCommand(.decreaseArrowThickness)
        case .increaseArrowThickness:
            performCommand(.increaseArrowThickness)
        default:
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
        syncSelectionAccessoryPresentation(layoutContext: layoutContext)
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

    private func updateSelectionAccessoryLayout(
        using layoutContext: CanvasChromeLayoutContext
    ) {
        selectionAccessoryHostView.updateLayout(layoutContext: layoutContext)
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
        guard activeOverlayEditorPresentationState == .none else {
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
                },
                onDidDismiss: { [weak self] in
                    self?.activeOverlayEditorPresentationState = .none
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
            activeOverlayEditorPresentationState = .videoDisplayFrame
            presentAsSheet(editorViewController)
        } catch {
            presentVideoEditorError(message: error.localizedDescription)
        }
    }

    private func presentGIFFrameImportEditor(for itemID: CanvasItemID) {
        guard activeOverlayEditorPresentationState == .none else {
            return
        }

        do {
            let editorContext = try editorSession.gifFrameImportEditorContext(
                for: itemID
            )
            let editorViewController = macOSGIFFrameImportViewController(
                editorContext: editorContext,
                onDidDismiss: { [weak self] in
                    self?.activeOverlayEditorPresentationState = .none
                }
            ) { [weak self] frameIndices in
                guard let self else {
                    throw macOSGIFFrameImportFlowError.presenterUnavailable
                }

                try self.performGIFFrameImport(
                    for: itemID,
                    frameIndices: frameIndices
                )
            }
            activeOverlayEditorPresentationState = .gifFrameImport
            presentAsSheet(editorViewController)
        } catch {
            presentGIFFrameImportEditorError(
                message: error.localizedDescription
            )
        }
    }

    private func presentMarkdownEditor(for itemID: CanvasItemID) {
        guard activeOverlayEditorPresentationState == .none else {
            return
        }

        guard let item = scene.markdownItem(withID: itemID) else {
            presentMarkdownEditorError(
                message: "Markdown item is no longer available."
            )
            return
        }

        cancelRotationInteractionIfNeeded(resetPointerDragState: true)
        selectionAccessoryHostView.dismiss()

        let editorViewController = macOSCanvasMarkdownEditorViewController(
            markdownSource: item.markdownSource,
            onCommitMarkdownSource: { [weak self] markdownSource in
                guard let self else {
                    return false
                }

                guard let commitResult = self.editorSession.commitMarkdownEdit(
                    withID: itemID,
                    markdownSource: markdownSource
                ) else {
                    self.presentMarkdownEditorError(
                        message: "Markdown item is no longer available."
                    )
                    return false
                }

                if commitResult.didChangeDocument {
                    self.refreshCanvas(
                        reason: "commit markdown edit \(itemID.uuidString)"
                    )
                }
                return true
            },
            onDidDismiss: { [weak self] in
                self?.activeOverlayEditorPresentationState = .none
            },
            onDismissAfterSuccessfulCommit: { [weak self] in
                self?.restoreMarkdownSelectionAccessoryAfterEditorDismiss(
                    reason: "markdown editor dismiss"
                )
            }
        )
        activeOverlayEditorPresentationState = .markdown
        presentAsSheet(editorViewController)
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
            performCommand(.addMarkdownItem(markdownSource: nil))
        case .addHandDrawingItem:
            if supportsHandDrawingEditing {
                performCommand(.addHandDrawingItem(paper: .square))
            }
        case .addArrowItem:
            performCommand(.addArrowItem)
        case .addGroup:
            performCommand(.addGroup)
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
        case .decreaseArrowThickness:
            performCommand(.decreaseArrowThickness)
        case .increaseArrowThickness:
            performCommand(.increaseArrowThickness)
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
            if let editableTextResponder = currentEditableTextResponder {
                return NSPasteboard.general.availableType(
                    from: editableTextResponder.readablePasteboardTypes
                ) != nil
            }

            return canPasteContent(
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
        if let editableTextResponder = currentEditableTextResponder {
            editableTextResponder.paste(sender)
            return
        }

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
        let rootView = macOSAppearanceAwareView()
        rootView.wantsLayer = true
        rootView.onEffectiveAppearanceChange = { [weak self] in
            self?.updateAppearance()
        }
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateAppearance()
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
        setupDeleteSelectionButton()
        setupTextButton()
        setupMarkdownButton()
        setupHandDrawingButton()
        setupArrowButton()
        setupGroupButton()
        setupUndoButton()
        setupRedoButton()
        setupBackButton()
        setupWorkspaceModeButton()
        setupGroupListButton()
        setupMiniMapView()
        setupContextMenuHostView()
        setupSelectionAccessoryHostView()
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

    private func updateAppearance() {
        guard isViewLoaded else {
            return
        }

        let appearance = view.effectiveAppearance
        let chromeBackgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.92)
        let chromeBorderColor = NSColor.separatorColor.withAlphaComponent(0.35)
        PlatformLayerAppearance.performWithoutAnimations {
            view.layer?.backgroundColor = PlatformLayerAppearance.resolvedCGColor(
                .windowBackgroundColor,
                for: appearance
            )
            canvasHostView.layer?.backgroundColor = PlatformLayerAppearance.resolvedCGColor(
                .windowBackgroundColor,
                for: appearance
            )
            for button in [backButton, workspaceModeButton, groupListButton] {
                button.layer?.backgroundColor = PlatformLayerAppearance.resolvedCGColor(
                    chromeBackgroundColor,
                    for: appearance
                )
                button.layer?.borderColor = PlatformLayerAppearance.resolvedCGColor(
                    chromeBorderColor,
                    for: appearance
                )
            }
        }
        groupListView.updateAppearance()
        updateGroupListPresentation()
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
        syncSelectionAccessoryPresentation()
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
        chromeOverlayView.addSubview(selectionAccessoryHostView)
        chromeOverlayView.addSubview(inputIndicatorHostView)
        chromeOverlayView.addSubview(contextMenuHostView)
        chromeOverlayView.addSubview(backButton)
        chromeOverlayView.addSubview(groupListButton)
        chromeOverlayView.addSubview(workspaceModeButton)
        chromeOverlayView.addSubview(groupListView)
        registerToolbarButtons()
    }

    private func setupConstraints() {
        let safeAreaLayoutGuide = chromeOverlayView.safeAreaLayoutGuide
        let preferredTextEditorWidth = textEditorOverlayView.widthAnchor.constraint(equalToConstant: 360)
        preferredTextEditorWidth.priority = .defaultHigh
        let preferredGroupListWidth = groupListView.widthAnchor.constraint(equalToConstant: 280)
        preferredGroupListWidth.priority = .defaultHigh
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
            selectionAccessoryHostView.topAnchor.constraint(equalTo: chromeOverlayView.topAnchor),
            selectionAccessoryHostView.leadingAnchor.constraint(equalTo: chromeOverlayView.leadingAnchor),
            selectionAccessoryHostView.trailingAnchor.constraint(equalTo: chromeOverlayView.trailingAnchor),
            selectionAccessoryHostView.bottomAnchor.constraint(equalTo: chromeOverlayView.bottomAnchor),
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
            groupListButton.trailingAnchor.constraint(equalTo: workspaceModeButton.leadingAnchor, constant: -12),
            groupListButton.topAnchor.constraint(equalTo: workspaceModeButton.topAnchor),
            groupListButton.widthAnchor.constraint(equalToConstant: 44),
            groupListButton.heightAnchor.constraint(equalToConstant: 44),
            groupListView.topAnchor.constraint(equalTo: groupListButton.bottomAnchor, constant: 8),
            groupListView.trailingAnchor.constraint(equalTo: groupListButton.trailingAnchor),
            groupListView.leadingAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor, constant: 20),
            groupListView.widthAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.widthAnchor, constant: -40),
            preferredGroupListWidth,
            groupListView.heightAnchor.constraint(equalToConstant: 280),
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
        updateSelectionAccessoryLayout(using: contextMenuLayoutContext)
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
        let resolvedToolbarFrame = resolvedOverlayToolbarFrame(
            for: toolbarState,
            placementResult: toolbarPlacementResult
        )
        applyToolbarFrame(resolvedToolbarFrame)
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

    private func resolvedOverlayToolbarFrame(
        for toolbarState: CanvasToolbarState,
        placementResult: CanvasToolbarPlacementPassResult
    ) -> CGRect {
        guard toolbarState.items.isEmpty else {
            preserveHiddenToolbarFrame(nil)
            return placementResult.toolbarFrame
        }

        return sanitizedPreservedHiddenToolbarFrame()
            ?? placementResult.hiddenToolbarFrame
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

    private func preserveHiddenToolbarFrame(_ frame: CGRect?) {
        preservedHiddenToolbarFrame = frame.flatMap { candidateFrame in
            CanvasChromeLayoutGeometry.sanitizedRect(candidateFrame)
        }
    }

    private func sanitizedPreservedHiddenToolbarFrame() -> CGRect? {
        guard let preservedHiddenToolbarFrame else {
            return nil
        }

        return CanvasChromeLayoutGeometry.sanitizedRect(
            preservedHiddenToolbarFrame
        )
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
        appendChromeBlocker(
            kind: .groupList,
            for: groupListButton,
            to: &chromeBlockers
        )
        appendChromeBlocker(
            kind: .groupList,
            for: groupListView,
            to: &chromeBlockers
        )
        return chromeBlockers
    }

    private func resolveMiniMapFrame(
        in layoutContext: CanvasChromeLayoutContext
    ) -> CGRect {
        guard Self.showsMiniMap else {
            return .zero
        }

        return miniMapLayoutSolver.resolveMiniMapFrame(
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

    private func setupDeleteSelectionButton() {
        deleteSelectionButton.target = self
        deleteSelectionButton.action = #selector(handleDeleteSelectionButtonClick)
        renderToolbar()
    }

    private func setupTextButton() {
        textButton.target = self
        textButton.action = #selector(handleTextButtonClick)
        updateInlineEditButtonsAppearance()
    }

    private func setupMarkdownButton() {
        markdownButton.target = self
        markdownButton.action = #selector(handleMarkdownButtonClick)
        renderToolbar()
    }

    private func setupHandDrawingButton() {
        handDrawingButton.target = self
        handDrawingButton.action = #selector(handleHandDrawingButtonClick)
        updateInlineEditButtonsAppearance()
    }

    private func setupArrowButton() {
        arrowButton.target = self
        arrowButton.action = #selector(handleArrowButtonClick)
        renderToolbar()
    }

    private func setupGroupButton() {
        groupButton.target = self
        groupButton.action = #selector(handleGroupButtonClick)
        renderToolbar()
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

    private func setupGroupListButton() {
        groupListButton.target = self
        groupListButton.action = #selector(handleGroupListButtonClick)
        groupListView.onAddGroupRequested = { [weak self] in
            self?.handleAddGroupRequested()
        }
        groupListView.onGroupSelected = { [weak self] groupID in
            self?.navigateToGroup(withID: groupID)
        }
        groupListView.onEditGroupTitleRequested = { [weak self] groupID in
            self?.beginGroupTitleEditing(groupID: groupID)
        }
        groupListView.onGroupTitleSubmitted = { [weak self] groupID, title in
            self?.commitGroupTitleEditing(groupID: groupID, title: title)
        }
        updateGroupListPresentation()
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

    private func updateGroupListPresentation() {
        macOSGroupTitleEditTrace(
            "controller.updateGroupListPresentation",
            editingGroupTitleID: editingGroupTitleID,
            firstResponder: view.window?.firstResponder
        )
        groupListView.render(
            groups: editorSession.groups,
            editingGroupTitleID: editingGroupTitleID
        )
        groupListView.isHidden = isGroupListVisible == false
        groupListButton.toolTip = isGroupListVisible
            ? "Canvas groups: Expanded"
            : "Canvas groups: Collapsed"

        let appearance = view.effectiveAppearance
        PlatformLayerAppearance.performWithoutAnimations {
            groupListButton.layer?.backgroundColor = PlatformLayerAppearance.resolvedCGColor(
                isGroupListVisible
                    ? NSColor.tertiaryLabelColor.withAlphaComponent(0.18)
                    : NSColor.controlBackgroundColor.withAlphaComponent(0.92),
                for: appearance
            )
            groupListButton.layer?.borderColor = PlatformLayerAppearance.resolvedCGColor(
                NSColor.separatorColor.withAlphaComponent(0.35),
                for: appearance
            )
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

    private func setupSelectionAccessoryHostView() {
        selectionAccessoryHostView.onCommandSelected = { [weak self] commandID in
            self?.performSelectionAccessoryCommand(commandID)
        }
        selectionAccessoryHostView.onDismissRequested = { [weak self] in
            self?.selectionAccessoryHostView.dismiss()
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
        canvasViewportView.onPan = { [weak self] translation, location in
            self?.observeContinuousRawInput(
                .pointerScrollGesture,
                sourceDescription: RawInputDeliverySource.scrollGesture.debugName,
                kind: .scroll
            )
            guard self?.isTransitionInteractionFrozen == false else {
                return
            }
            self?.handleIndirectPan(translation, at: location)
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
        logPointerHitResolution(
            phase: "down",
            location: location,
            context: pressContext
        )
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
             .draggingGroupFrame,
             .resizingGroupFrame,
             .resizingSelectedItem,
             .adjustingArrowEndpoint,
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
            case let .arrowEndpointHandle(endpointRole):
                guard let itemID = pressContext.targetItemID else {
                    pointerDragState = .idle
                    return
                }

                guard let endpointState = makePointerArrowEndpointState(
                    itemID: itemID,
                    endpointRole: endpointRole
                ) else {
                    pointerDragState = .idle
                    return
                }

                pointerDragState = .adjustingArrowEndpoint(endpointState)
                adjustArrowEndpoint(using: endpointState, to: location)
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
            case .groupFrameBody:
                guard
                    let groupID = pressContext.targetGroupID,
                    let groupDragState = makePointerGroupDragState(
                        groupID: groupID,
                        initialViewportLocation: pressedLocation
                    )
                else {
                    pointerDragState = .idle
                    return
                }

                editorSession.beginHistoryTransaction(reason: "move group frame")
                guard moveGroupFrame(using: groupDragState, to: location) else {
                    editorSession.cancelPendingHistoryTransaction()
                    pointerDragState = .idle
                    return
                }

                pointerDragState = .draggingGroupFrame(groupDragState)
            case let .groupFrameResizeHandle(handleRole):
                guard
                    let groupID = pressContext.targetGroupID,
                    let groupResizeState = makePointerGroupResizeState(
                        groupID: groupID,
                        handleRole: handleRole,
                        initialViewportLocation: pressedLocation
                    )
                else {
                    pointerDragState = .idle
                    return
                }

                editorSession.beginHistoryTransaction(reason: "resize group frame")
                guard resizeGroupFrame(using: groupResizeState, to: location) else {
                    editorSession.cancelPendingHistoryTransaction()
                    pointerDragState = .idle
                    return
                }

                pointerDragState = .resizingGroupFrame(groupResizeState)
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
        case let .draggingGroupFrame(groupDragState):
            guard moveGroupFrame(using: groupDragState, to: location) else {
                editorSession.cancelPendingHistoryTransaction()
                pointerDragState = .idle
                return
            }
        case let .resizingGroupFrame(groupResizeState):
            guard resizeGroupFrame(using: groupResizeState, to: location) else {
                editorSession.cancelPendingHistoryTransaction()
                pointerDragState = .idle
                return
            }
        case let .resizingSelectedItem(resizeState):
            resizeSelectedItem(using: resizeState, to: location)
        case let .adjustingArrowEndpoint(endpointState):
            adjustArrowEndpoint(using: endpointState, to: location)
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
            logPointerHitResolution(
                phase: "up",
                location: location,
                context: releasedContext
            )
            let releasedItemID = releasedContext.targetItemID
            let previousInteractionState = interactionState
            let previousClickSelectionState = currentClickSelectionState()
            if let groupClickResult = executeGroupFrameClickSelectionIfMatched(
                pressContext: pressContext,
                releasedContext: releasedContext
            ) {
                logClickResult(
                    target: "group_frame",
                    result: groupClickResult.result,
                    pressedItemID: pressedItemID,
                    releasedItemID: releasedItemID,
                    previousInteractionState: previousInteractionState,
                    currentInteractionState: interactionState,
                    affectedItemID: nil
                )
                if clearedAlignmentInteractionState,
                   groupClickResult.didTriggerPressedRefresh == false
                {
                    refreshCanvas(reason: "clear alignment interaction on pointer up")
                }
                editorSession.cancelPendingHistoryTransaction()
                return
            }
            let clickDecision = clickSelectionResolver.resolve(
                pressTargetKind: pressContext.targetKind,
                pressedItemID: pressContext.targetItemID,
                releasedItemID: releasedItemID,
                selection: previousClickSelectionState,
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
        case .draggingGroupFrame:
            commitPendingPointerHistoryTransaction(autosaveReason: "move group frame")
        case .resizingGroupFrame:
            commitPendingPointerHistoryTransaction(autosaveReason: "resize group frame")
        case .resizingSelectedItem:
            finalizeMarkdownResizeCommitIfNeeded(for: pointerDragState)
            commitPendingPointerHistoryTransaction(autosaveReason: "resize item")
        case .adjustingArrowEndpoint:
            commitPendingPointerHistoryTransaction(autosaveReason: "adjust arrow")
        case .resizingSelection:
            finalizeMarkdownResizeCommitIfNeeded(for: pointerDragState)
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
        case .draggingGroupFrame:
            commitPendingPointerHistoryTransaction(autosaveReason: "move group frame")
        case .resizingGroupFrame:
            commitPendingPointerHistoryTransaction(autosaveReason: "resize group frame")
        case .resizingSelectedItem:
            finalizeMarkdownResizeCommitIfNeeded(for: pointerDragState)
            commitPendingPointerHistoryTransaction(autosaveReason: "resize item")
        case .adjustingArrowEndpoint:
            commitPendingPointerHistoryTransaction(autosaveReason: "adjust arrow")
        case .resizingSelection:
            finalizeMarkdownResizeCommitIfNeeded(for: pointerDragState)
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

    private func handleIndirectPan(
        _ translation: CGPoint,
        at viewportLocation: CGPoint
    ) {
        if contextMenuState != nil {
            dismissContextMenu()
            return
        }

        guard case .idle = pointerDragState else {
            return
        }

        let remainingTranslation =
            consumeMarkdownScrollIfNeeded(
                for: translation,
                at: viewportLocation
            )
            ?? translation
        guard remainingTranslation != .zero else {
            return
        }

        cancelGroupListNavigationAnimation()
        camera.pan(by: remainingTranslation)
        refreshCanvas(reason: "indirect pan \(describe(point: remainingTranslation))")
        scheduleAutosave(
            reason: "pan canvas",
            updateKind: .viewStateOnly
        )
    }

    private func consumeMarkdownScrollIfNeeded(
        for translation: CGPoint,
        at viewportLocation: CGPoint
    ) -> CGPoint? {
        guard isInlineEditModeActive == false else {
            return nil
        }
        let worldLocation = camera.viewportToWorld(viewportLocation)
        guard let markdownItem = scene.topmostBoardItem(containing: worldLocation)?.markdownItem else {
            return nil
        }
        let contentHeight = editorSession.measuredMarkdownContentHeight(for: markdownItem)
        let maxScrollOffsetY = max(contentHeight - markdownItem.size.height, 0)
        guard maxScrollOffsetY > Self.geometryComparisonEpsilon else {
            return nil
        }

        let resolvedZoomScale =
            camera.zoomScale.isFinite && camera.zoomScale > 0 ? camera.zoomScale : 1
        let proposedScrollDeltaY = -translation.y / resolvedZoomScale
        guard proposedScrollDeltaY.isFinite else {
            return translation
        }

        let resolvedScrollOffsetY = min(
            max(markdownItem.scrollOffsetY + proposedScrollDeltaY, 0),
            maxScrollOffsetY
        )
        let appliedScrollDeltaY = resolvedScrollOffsetY - markdownItem.scrollOffsetY
        if abs(appliedScrollDeltaY) > Self.geometryComparisonEpsilon {
            beginMarkdownScrollHistoryTransactionIfNeeded()
            if editorSession.updateMarkdownItemScrollOffset(
                withID: markdownItem.id,
                scrollOffsetY: resolvedScrollOffsetY
            ) != nil {
                refreshCanvas(reason: "scroll markdown item")
                scheduleMarkdownScrollHistoryCommit()
            }
        }

        let consumedViewportDeltaY = -appliedScrollDeltaY * resolvedZoomScale
        return CGPoint(
            x: translation.x,
            y: translation.y - consumedViewportDeltaY
        )
    }

    private func handleZoom(_ scaleDelta: CGFloat, around anchor: CGPoint) {
        if contextMenuState != nil {
            dismissContextMenu()
            return
        }

        cancelGroupListNavigationAnimation()
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
        syncSelectionAccessoryPresentation()
    }

    private func refreshMiniMap() {
        guard Self.showsMiniMap else {
            miniMapView.apply(.empty)
            return
        }

        let snapshot = editorSession.makeMiniMapSnapshot()
        miniMapView.apply(snapshot)
    }

    private func handleMiniMapNavigate(to miniMapPoint: CGPoint) {
        cancelGroupListNavigationAnimation()
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
    private func handleDeleteSelectionButtonClick() {
        performCommand(.deleteSelection(recordHistory: true))
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
    private func handleMarkdownButtonClick() {
        performCommand(.addMarkdownItem(markdownSource: nil))
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
    private func handleArrowButtonClick() {
        performCommand(.addArrowItem)
    }

    @objc
    private func handleGroupButtonClick() {
        performCommand(.addGroup)
    }

    @objc
    private func handleGroupListButtonClick() {
        macOSGroupTitleEditTrace(
            "controller.groupListButtonClick.start",
            editingGroupTitleID: editingGroupTitleID,
            firstResponder: view.window?.firstResponder
        )
        if isGroupListVisible {
            view.window?.makeFirstResponder(nil)
            editingGroupTitleID = nil
            macOSGroupTitleEditTrace(
                "controller.groupListButtonClick.clearEditing",
                editingGroupTitleID: editingGroupTitleID,
                firstResponder: view.window?.firstResponder
            )
        }
        isGroupListVisible.toggle()
        updateGroupListPresentation()
        updateChromeOverlayLayout()
    }

    private func handleAddGroupRequested() {
        _ = editorSession.appendGroup(recordHistory: true)
        updateGroupListPresentation()
        updateInlineEditButtonsAppearance()
        refreshCanvas(reason: "add group")
    }

    private func navigateToGroup(withID groupID: CanvasItemGroupID) {
        guard let groupFrame = editorSession.groupFrame(withID: groupID) else {
            return
        }

        let targetCenter = CGPoint(x: groupFrame.midX, y: groupFrame.midY)
        guard
            targetCenter.x.isFinite,
            targetCenter.y.isFinite,
            camera.center != targetCenter
        else {
            return
        }

        beginGroupListNavigationAnimation(
            to: targetCenter,
            refreshReason: "navigate group list to \(groupID.uuidString)",
            autosaveReason: "navigate canvas via group list"
        )
    }

    private func beginGroupListNavigationAnimation(
        to targetCenter: CGPoint,
        refreshReason: String,
        autosaveReason: String
    ) {
        cancelGroupListNavigationAnimation()

        let startCenter = camera.center
        guard startCenter != targetCenter else {
            return
        }

        groupListNavigationAnimationState = CameraCenterAnimationState(
            startCenter: startCenter,
            targetCenter: targetCenter,
            startTimestamp: CACurrentMediaTime(),
            refreshReason: refreshReason,
            autosaveReason: autosaveReason
        )
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            self?.handleGroupListNavigationTimer(timer)
        }
        groupListNavigationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func handleGroupListNavigationTimer(_ timer: Timer) {
        guard let animationState = groupListNavigationAnimationState else {
            timer.invalidate()
            groupListNavigationTimer = nil
            return
        }

        let elapsed = max(0, CACurrentMediaTime() - animationState.startTimestamp)
        let rawProgress = min(
            CGFloat(elapsed / Self.groupListNavigationAnimationDuration),
            1
        )
        if rawProgress >= 1 {
            camera.center = animationState.targetCenter
            cancelGroupListNavigationAnimation()
            refreshCanvas(reason: animationState.refreshReason)
            scheduleAutosave(
                reason: animationState.autosaveReason,
                updateKind: .viewStateOnly
            )
            return
        }

        let easedProgress = Self.easeOutCubic(rawProgress)
        camera.center = CGPoint(
            x: animationState.startCenter.x +
                (animationState.targetCenter.x - animationState.startCenter.x) * easedProgress,
            y: animationState.startCenter.y +
                (animationState.targetCenter.y - animationState.startCenter.y) * easedProgress
        )
        refreshCanvas(reason: animationState.refreshReason)
    }

    private func cancelGroupListNavigationAnimation() {
        groupListNavigationTimer?.invalidate()
        groupListNavigationTimer = nil
        groupListNavigationAnimationState = nil
    }

    private static func easeOutCubic(_ progress: CGFloat) -> CGFloat {
        let clampedProgress = min(max(progress, 0), 1)
        let inverseProgress = 1 - clampedProgress
        return 1 - inverseProgress * inverseProgress * inverseProgress
    }

    private func beginGroupTitleEditing(groupID: CanvasItemGroupID) {
        macOSGroupTitleEditTrace(
            "controller.begin.start",
            groupID: groupID,
            editingGroupTitleID: editingGroupTitleID,
            firstResponder: view.window?.firstResponder
        )
        if let editingGroupTitleID,
           editingGroupTitleID != groupID {
            view.window?.makeFirstResponder(nil)
            macOSGroupTitleEditTrace(
                "controller.begin.endedPreviousResponder",
                groupID: groupID,
                editingGroupTitleID: editingGroupTitleID,
                firstResponder: view.window?.firstResponder
            )
        }

        guard editorSession.group(withID: groupID) != nil else {
            editingGroupTitleID = nil
            macOSGroupTitleEditTrace(
                "controller.begin.missingGroup",
                groupID: groupID,
                editingGroupTitleID: editingGroupTitleID,
                firstResponder: view.window?.firstResponder
            )
            updateGroupListPresentation()
            updateChromeOverlayLayout()
            return
        }

        editingGroupTitleID = groupID
        macOSGroupTitleEditTrace(
            "controller.begin.setEditing",
            groupID: groupID,
            editingGroupTitleID: editingGroupTitleID,
            firstResponder: view.window?.firstResponder
        )
        updateGroupListPresentation()
        updateChromeOverlayLayout()
    }

    private func commitGroupTitleEditing(
        groupID: CanvasItemGroupID,
        title: String
    ) {
        macOSGroupTitleEditTrace(
            "controller.commit.start",
            groupID: groupID,
            editingGroupTitleID: editingGroupTitleID,
            title: title,
            firstResponder: view.window?.firstResponder
        )
        guard editingGroupTitleID == groupID else {
            macOSGroupTitleEditTrace(
                "controller.commit.ignoredMismatchedEditingID",
                groupID: groupID,
                editingGroupTitleID: editingGroupTitleID,
                title: title,
                firstResponder: view.window?.firstResponder
            )
            return
        }

        editingGroupTitleID = nil
        guard editorSession.group(withID: groupID) != nil else {
            macOSGroupTitleEditTrace(
                "controller.commit.missingGroup",
                groupID: groupID,
                editingGroupTitleID: editingGroupTitleID,
                title: title,
                firstResponder: view.window?.firstResponder
            )
            updateGroupListPresentation()
            updateChromeOverlayLayout()
            return
        }

        _ = editorSession.renameGroup(
            withID: groupID,
            to: title,
            recordHistory: true
        )
        macOSGroupTitleEditTrace(
            "controller.commit.renamed",
            groupID: groupID,
            editingGroupTitleID: editingGroupTitleID,
            title: title,
            firstResponder: view.window?.firstResponder
        )
        updateGroupListPresentation()
        updateChromeOverlayLayout()
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
        let hadActiveToolbarTransition = toolbarTransitionRuntime != nil
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
        let synchronizedInitialPresentation = synchronizedInitialToolbarPresentation(
            initialPresentation,
            stage: initialStage,
            direction: direction,
            context: context,
            shouldSynchronizeOffscreenStart: hadActiveToolbarTransition == false
        )

        toolbarTransitionRuntime = CanvasToolbarTransitionRuntime(
            context: context,
            stage: initialStage,
            currentPresentation: synchronizedInitialPresentation,
            pendingLayoutReconcile: true
        )
        toolbarHostView.applyTransitionImmediately(synchronizedInitialPresentation)

        switch initialStage {
        case .collapsing, .expanding:
            runToolbarCollapsePhase()
        case .exiting, .entering:
            runToolbarSlidePhase()
        case .steadyVisible, .hidden:
            finishToolbarModeTransition(applying: context.settledState)
        }
    }

    private func synchronizedInitialToolbarPresentation(
        _ presentation: CanvasToolbarTransitionPresentation,
        stage: CanvasToolbarTransitionStage,
        direction: CanvasToolbarTransitionDirection,
        context: CanvasToolbarTransitionContext,
        shouldSynchronizeOffscreenStart: Bool
    ) -> CanvasToolbarTransitionPresentation {
        guard shouldSynchronizeOffscreenStart,
              direction == .toEditing,
              case .entering = stage
        else {
            return presentation
        }

        var synchronizedPresentation = presentation
        synchronizedPresentation.frame = normalizedToolbarFrame(
            context.frames.offscreenFrame,
            fallback: presentation.frame
        )
        return synchronizedPresentation
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

            let collapsedFrame = visibleFrame
            let offscreenFrame = CanvasToolbarTransitionGeometry.offscreenFrame(
                from: collapsedFrame,
                safeBounds: toolbarLayoutSafeBounds(),
                placement: visibleState.placement
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
            return context

        case .toEditing:
            applyWorkspaceModeForToolbarTransition(to: .editing)

            let visibleState = makeToolbarState()
            guard visibleState.items.isEmpty == false else {
                return nil
            }

            let visibleFrame = resolvedSteadyToolbarFrame(for: visibleState)
            let collapsedFrame = visibleFrame
            let offscreenFrame = CanvasToolbarTransitionGeometry.offscreenFrame(
                from: collapsedFrame,
                safeBounds: toolbarLayoutSafeBounds(),
                placement: visibleState.placement
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
        let transitionContext = toolbarTransitionRuntime?.context
        let pendingLayoutReconcile = toolbarTransitionRuntime?.pendingLayoutReconcile
            ?? true
        if settledState.items.isEmpty {
            preserveHiddenToolbarFrame(transitionContext?.frames.offscreenFrame)
        } else {
            preserveHiddenToolbarFrame(nil)
        }
        cancelManualToolbarTransition()
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
        cancelManualToolbarTransition()
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
        let expectedDirection = runtime.context.direction
        let sourcePresentation = runtime.currentPresentation
        runtime.stage = targetStage
        runtime.currentPresentation = targetPresentation
        toolbarTransitionRuntime = runtime

        if duration <= 0 {
            let completionPresentation = reconciledToolbarCompletionPresentation(
                targetPresentation,
                targetStage: targetStage,
                context: runtime.context
            )
            updateCurrentToolbarTransitionPresentation(
                completionPresentation,
                targetStage: targetStage,
                expectedDirection: expectedDirection
            )
            cancelManualToolbarTransition()
            toolbarHostView.applyTransitionImmediately(completionPresentation)
            completion()
            return
        }

        runManualToolbarTransition(
            from: sourcePresentation,
            to: targetPresentation,
            context: runtime.context,
            targetStage: targetStage,
            duration: duration
        ) { [weak self] in
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

    private func runManualToolbarTransition(
        from sourcePresentation: CanvasToolbarTransitionPresentation,
        to targetPresentation: CanvasToolbarTransitionPresentation,
        context: CanvasToolbarTransitionContext,
        targetStage: CanvasToolbarTransitionStage,
        duration: TimeInterval,
        completion: @escaping () -> Void
    ) {
        cancelManualToolbarTransition()

        let transitionID = UUID()
        toolbarManualTransitionID = transitionID
        let startTime = CACurrentMediaTime()
        let sanitizedDuration = max(duration, 0)
        let locksFrameToHorizontalSlide = locksToolbarFrameToHorizontalSlide(
            for: targetStage
        )
        let initialPresentation = initialManualToolbarPresentation(
            from: sourcePresentation,
            to: targetPresentation,
            locksFrameToHorizontalSlide: locksFrameToHorizontalSlide
        )

        toolbarHostView.renderTransition(
            initialPresentation,
            animated: false
        )

        let timer = Timer(
            timeInterval: 1.0 / 60.0,
            repeats: true
        ) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            guard self.toolbarManualTransitionID == transitionID else {
                timer.invalidate()
                return
            }

            let elapsed = CACurrentMediaTime() - startTime
            let linearProgress = sanitizedDuration <= 0
                ? 1
                : min(max(CGFloat(elapsed / sanitizedDuration), 0), 1)
            let easedProgress = self.easeInOutToolbarProgress(linearProgress)
            let presentation = self.interpolatedToolbarPresentation(
                from: initialPresentation,
                to: targetPresentation,
                progress: easedProgress,
                locksFrameToHorizontalSlide: locksFrameToHorizontalSlide
            )

            self.toolbarHostView.applyTransitionImmediately(presentation)

            guard linearProgress >= 1 else {
                return
            }

            timer.invalidate()
            if self.toolbarManualTransitionTimer === timer {
                self.toolbarManualTransitionTimer = nil
            }
            let completionPresentation = self.reconciledToolbarCompletionPresentation(
                targetPresentation,
                targetStage: targetStage,
                context: context
            )
            self.updateCurrentToolbarTransitionPresentation(
                completionPresentation,
                targetStage: targetStage,
                expectedDirection: context.direction
            )
            self.toolbarHostView.applyTransitionImmediately(completionPresentation)
            completion()
        }

        toolbarManualTransitionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        timer.fire()
    }

    private func reconciledToolbarCompletionPresentation(
        _ presentation: CanvasToolbarTransitionPresentation,
        targetStage: CanvasToolbarTransitionStage,
        context: CanvasToolbarTransitionContext
    ) -> CanvasToolbarTransitionPresentation {
        guard let reconciledFrame = reconciledToolbarCompletionFrame(
            targetStage: targetStage,
            context: context,
            fallback: presentation.frame
        ) else {
            return presentation
        }

        var reconciledPresentation = presentation
        reconciledPresentation.frame = reconciledFrame
        return reconciledPresentation
    }

    private func reconciledToolbarCompletionFrame(
        targetStage: CanvasToolbarTransitionStage,
        context: CanvasToolbarTransitionContext,
        fallback: CGRect
    ) -> CGRect? {
        switch targetStage {
        case .steadyVisible:
            return resolvedSteadyToolbarFrame(
                for: context.settledState
            )

        case .hidden:
            return normalizedToolbarFrame(
                context.frames.offscreenFrame,
                fallback: fallback
            )

        case let .entering(progress)
            where clampedToolbarTransitionProgress(progress) >= 0.999:
            return resolvedSteadyToolbarFrame(
                for: context.settledState
            )

        case let .expanding(progress)
            where clampedToolbarTransitionProgress(progress) >= 0.999:
            return resolvedSteadyToolbarFrame(
                for: context.settledState
            )

        case let .exiting(progress)
            where clampedToolbarTransitionProgress(progress) >= 0.999:
            return normalizedToolbarFrame(
                context.frames.offscreenFrame,
                fallback: fallback
            )

        case .collapsing, .entering, .exiting, .expanding:
            return nil
        }
    }

    private func updateCurrentToolbarTransitionPresentation(
        _ presentation: CanvasToolbarTransitionPresentation,
        targetStage: CanvasToolbarTransitionStage,
        expectedDirection: CanvasToolbarTransitionDirection
    ) {
        guard var runtime = toolbarTransitionRuntime,
              runtime.context.direction == expectedDirection,
              runtime.stage == targetStage
        else {
            return
        }

        runtime.currentPresentation = presentation
        toolbarTransitionRuntime = runtime
    }

    private func cancelManualToolbarTransition() {
        toolbarManualTransitionID = UUID()
        toolbarManualTransitionTimer?.invalidate()
        toolbarManualTransitionTimer = nil
    }

    private func locksToolbarFrameToHorizontalSlide(
        for targetStage: CanvasToolbarTransitionStage
    ) -> Bool {
        switch targetStage {
        case .entering, .exiting:
            return true
        case .steadyVisible, .hidden, .collapsing, .expanding:
            return false
        }
    }

    private func initialManualToolbarPresentation(
        from sourcePresentation: CanvasToolbarTransitionPresentation,
        to targetPresentation: CanvasToolbarTransitionPresentation,
        locksFrameToHorizontalSlide: Bool
    ) -> CanvasToolbarTransitionPresentation {
        guard locksFrameToHorizontalSlide else {
            return sourcePresentation
        }

        var presentation = sourcePresentation
        presentation.frame = CGRect(
            x: sourcePresentation.frame.minX,
            y: targetPresentation.frame.minY,
            width: targetPresentation.frame.width,
            height: targetPresentation.frame.height
        ).standardized
        return presentation
    }

    private func interpolatedToolbarPresentation(
        from sourcePresentation: CanvasToolbarTransitionPresentation,
        to targetPresentation: CanvasToolbarTransitionPresentation,
        progress: CGFloat,
        locksFrameToHorizontalSlide: Bool
    ) -> CanvasToolbarTransitionPresentation {
        let t = min(max(progress, 0), 1)
        return CanvasToolbarTransitionPresentation(
            frame: interpolatedToolbarFrame(
                from: sourcePresentation.frame,
                to: targetPresentation.frame,
                progress: t,
                locksFrameToHorizontalSlide: locksFrameToHorizontalSlide
            ),
            itemStates: targetPresentation.itemStates,
            showsBackground: targetPresentation.showsBackground,
            contentAlpha: interpolatedToolbarValue(
                from: sourcePresentation.contentAlpha,
                to: targetPresentation.contentAlpha,
                progress: t
            ),
            contentScale: interpolatedToolbarValue(
                from: sourcePresentation.contentScale,
                to: targetPresentation.contentScale,
                progress: t
            ),
            keepsHostVisible: sourcePresentation.keepsHostVisible ||
                targetPresentation.keepsHostVisible,
            isInteractive: false
        )
    }

    private func interpolatedToolbarFrame(
        from sourceFrame: CGRect,
        to targetFrame: CGRect,
        progress: CGFloat,
        locksFrameToHorizontalSlide: Bool
    ) -> CGRect {
        if locksFrameToHorizontalSlide {
            return CGRect(
                x: interpolatedToolbarValue(
                    from: sourceFrame.minX,
                    to: targetFrame.minX,
                    progress: progress
                ),
                y: targetFrame.minY,
                width: targetFrame.width,
                height: targetFrame.height
            ).standardized
        }

        return CGRect(
            x: interpolatedToolbarValue(
                from: sourceFrame.minX,
                to: targetFrame.minX,
                progress: progress
            ),
            y: interpolatedToolbarValue(
                from: sourceFrame.minY,
                to: targetFrame.minY,
                progress: progress
            ),
            width: interpolatedToolbarValue(
                from: sourceFrame.width,
                to: targetFrame.width,
                progress: progress
            ),
            height: interpolatedToolbarValue(
                from: sourceFrame.height,
                to: targetFrame.height,
                progress: progress
            )
        ).standardized
    }

    private func interpolatedToolbarValue(
        from sourceValue: CGFloat,
        to targetValue: CGFloat,
        progress: CGFloat
    ) -> CGFloat {
        sourceValue + ((targetValue - sourceValue) * min(max(progress, 0), 1))
    }

    private func easeInOutToolbarProgress(_ progress: CGFloat) -> CGFloat {
        let t = min(max(progress, 0), 1)
        return 0.5 - (cos(t * .pi) / 2)
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
                return .exiting(progress: 0)
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
            return .exiting(
                progress: toolbarLinearProgress(
                    from: collapsedFrame.minX,
                    to: context.frames.offscreenFrame.minX,
                    current: currentFrame.minX
                )
            )

        case .toEditing:
            let enteringProgress = toolbarLinearProgress(
                from: context.frames.offscreenFrame.minX,
                to: collapsedFrame.minX,
                current: currentFrame.minX
            )
            if enteringProgress >= 0.999 {
                return .steadyVisible
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
        if state.items.isEmpty,
           let preservedHiddenToolbarFrame = sanitizedPreservedHiddenToolbarFrame()
        {
            return preservedHiddenToolbarFrame
        }

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
        let stackedLength = (itemCount * macOSCanvasToolbarChromeMetrics.buttonEdge)
            + (max(itemCount - 1, 0) * macOSCanvasToolbarChromeMetrics.spacing)
        let measuredStackSize: CGSize

        switch state.preferredAxis {
        case .horizontal:
            measuredStackSize = CGSize(
                width: stackedLength,
                height: macOSCanvasToolbarChromeMetrics.buttonEdge
            )
        case .vertical:
            measuredStackSize = CGSize(
                width: macOSCanvasToolbarChromeMetrics.buttonEdge,
                height: stackedLength
            )
        }

        return CanvasChromeLayoutGeometry.sanitizedSize(
            macOSCanvasToolbarChromeMetrics.measuredContentSize(
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

    private func canPasteContent(
        from pasteboard: NSPasteboard,
        entry: CanvasTransferEntryIntent
    ) -> Bool {
        isTransferEntryAllowed(entry) &&
            macOSCanvasPasteboardPayloadResolver.canResolvePayload(from: pasteboard)
    }

    private func handlePasteRequest() {
        guard let pastePayload = macOSCanvasPasteboardPayloadResolver.resolvedPayload(
            from: .general,
            sourceDescription: "pasteboard"
        ) else {
            return
        }

        switch pastePayload {
        case let .media(transferRequest):
            _ = performTransferRequest(transferRequest)
        case let .markdownText(markdownSource):
            performCommand(.addMarkdownItem(markdownSource: markdownSource))
        }
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

    private var currentEditableTextResponder: NSTextView? {
        guard
            let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
            textView.isEditable
        else {
            return nil
        }

        return textView
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

    private func currentClickSelectionState() -> CanvasClickSelectionState {
        CanvasClickSelectionState(
            itemSelection: interactionState,
            selectedGroupID: editorSession.selectedGroupID
        )
    }

    private func executeGroupFrameClickSelectionIfMatched(
        pressContext: CanvasPointerPressContext,
        releasedContext: CanvasPointerPressContext
    ) -> (result: String, didTriggerPressedRefresh: Bool)? {
        guard
            case .groupFrameBody = pressContext.targetKind,
            case .groupFrameBody = releasedContext.targetKind,
            let groupID = pressContext.targetGroupID,
            releasedContext.targetGroupID == groupID
        else {
            return nil
        }

        let didSelectGroup = editorSession.selectGroup(
            withID: groupID,
            recordHistory: true
        )
        guard didSelectGroup else {
            return ("selection_unchanged", false)
        }

        refreshCanvas(reason: "select group frame")
        return ("group_selected", true)
    }

    private func executeClickSelectionDecision(
        _ decision: CanvasClickSelectionDecision
    ) -> (result: String, didTriggerPressedRefresh: Bool) {
        let selectionStateBefore = currentClickSelectionState()

        switch decision.action {
        case .none:
            return ("selection_unchanged", false)
        case let .selectSingle(itemID):
            selectItem(withID: itemID, recordHistory: true)
            let didChangeSelection = selectionStateBefore != currentClickSelectionState()
            return (
                didChangeSelection ? "item_selected" : "selection_unchanged",
                didChangeSelection
            )
        case let .toggleMembership(itemID):
            let wasSelected = selectionStateBefore.itemSelection.selectedItemIDs.contains(itemID)
            toggleSelectionMembership(of: itemID, recordHistory: true)
            let didChangeSelection = selectionStateBefore != currentClickSelectionState()
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
            let didChangeSelection = selectionStateBefore != currentClickSelectionState()
            return (
                didChangeSelection ? "selection_cleared" : "selection_unchanged",
                didChangeSelection
            )
        case let .reenterSelectedItem(itemID):
            return handleSelectedItemReentry(for: itemID)
        }
    }

    private func handleSelectedItemReentry(
        for itemID: CanvasItemID
    ) -> (result: String, didTriggerPressedRefresh: Bool) {
        if beginTextEditIfPossible(for: itemID) {
            return ("text_edit_began", true)
        }
        if scene.markdownItem(withID: itemID) != nil {
            syncSelectionAccessoryPresentation()
            return ("markdown_accessory_presented", false)
        }
        return ("selection_unchanged", false)
    }

    private func restoreMarkdownSelectionAccessoryAfterEditorDismiss(
        reason: String
    ) {
        logMarkdownAccessoryDismissRestore(reason: reason, step: "requested")
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.logMarkdownAccessoryDismissRestore(reason: reason, step: "async-1")
            self.syncSelectionAccessoryPresentation()
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.logMarkdownAccessoryDismissRestore(reason: reason, step: "async-2")
                self.syncSelectionAccessoryPresentation()
            }
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

    private func makePointerGroupDragState(
        groupID: CanvasItemGroupID,
        initialViewportLocation: CGPoint
    ) -> PointerGroupDragState? {
        guard let initialFrame = editorSession.groupFrame(withID: groupID) else {
            return nil
        }

        return PointerGroupDragState(
            groupID: groupID,
            initialFrame: initialFrame,
            initialSubtreeGeometries: editorSession.groupSubtreeGeometries(withID: groupID),
            dragStartWorldLocation: camera.viewportToWorld(initialViewportLocation)
        )
    }

    private func makePointerGroupResizeState(
        groupID: CanvasItemGroupID,
        handleRole: CanvasSelectionHandleRole,
        initialViewportLocation: CGPoint
    ) -> PointerGroupResizeState? {
        guard let initialFrame = editorSession.groupFrame(withID: groupID)?.standardized,
              initialFrame.width > 0,
              initialFrame.height > 0
        else {
            return nil
        }

        return PointerGroupResizeState(
            groupID: groupID,
            handleRole: handleRole,
            initialFrame: initialFrame,
            initialDraggedAnchor: groupResizeDraggedAnchor(
                for: handleRole,
                in: initialFrame
            ),
            dragStartWorldLocation: camera.viewportToWorld(initialViewportLocation),
            minimumSize: Self.minimumGroupFrameSize
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

    private func moveGroupFrame(
        using dragState: PointerGroupDragState,
        to location: CGPoint
    ) -> Bool {
        let currentWorldLocation = camera.viewportToWorld(location)
        let translation = CGPoint(
            x: currentWorldLocation.x - dragState.dragStartWorldLocation.x,
            y: currentWorldLocation.y - dragState.dragStartWorldLocation.y
        )
        let proposedFrame = dragState.initialFrame.offsetBy(
            dx: translation.x,
            dy: translation.y
        )
        let proposedSubtreeGeometries = translatedGroupSubtreeGeometries(
            dragState.initialSubtreeGeometries,
            by: translation
        )
        guard editorSession.updateGroupFrameAndSubtreeGeometries(
            withID: dragState.groupID,
            to: proposedFrame,
            subtreeGeometries: proposedSubtreeGeometries,
            reconcileMembership: false
        ) else {
            return editorSession.groupFrame(withID: dragState.groupID)
                == proposedFrame.standardized
        }

        refreshCanvas(
            reason: "move group frame by \(describe(point: translation))"
        )
        return true
    }

    private func translatedGroupSubtreeGeometries(
        _ subtreeGeometries: CanvasGroupSubtreeGeometries,
        by translation: CGPoint
    ) -> CanvasGroupSubtreeGeometries {
        CanvasGroupSubtreeGeometries(
            descendantGroupFrames: subtreeGeometries.descendantGroupFrames.map { geometry in
                CanvasGroupFrameGeometry(
                    groupID: geometry.groupID,
                    frame: geometry.frame.offsetBy(
                        dx: translation.x,
                        dy: translation.y
                    )
                )
            },
            itemGeometries: subtreeGeometries.itemGeometries.map { geometry in
                CanvasBoardItemGeometry(
                    itemID: geometry.itemID,
                    center: CGPoint(
                        x: geometry.center.x + translation.x,
                        y: geometry.center.y + translation.y
                    ),
                    size: geometry.size,
                    rotationRadians: geometry.rotationRadians
                )
            }
        )
    }

    private func resizeGroupFrame(
        using resizeState: PointerGroupResizeState,
        to location: CGPoint
    ) -> Bool {
        let currentWorldLocation = camera.viewportToWorld(location)
        let pointerTranslation = CGPoint(
            x: currentWorldLocation.x - resizeState.dragStartWorldLocation.x,
            y: currentWorldLocation.y - resizeState.dragStartWorldLocation.y
        )
        let draggedAnchor = CGPoint(
            x: resizeState.initialDraggedAnchor.x + pointerTranslation.x,
            y: resizeState.initialDraggedAnchor.y + pointerTranslation.y
        )
        let proposedFrame = groupFrame(
            from: resizeState.initialFrame,
            handleRole: resizeState.handleRole,
            draggedAnchor: draggedAnchor,
            minimumSize: resizeState.minimumSize
        )
        guard editorSession.updateGroupFrame(
            withID: resizeState.groupID,
            to: proposedFrame,
            reconcileMembership: false
        ) else {
            return editorSession.groupFrame(withID: resizeState.groupID)
                == proposedFrame.standardized
        }

        refreshCanvas(
            reason: "resize group frame \(String(describing: resizeState.handleRole))"
        )
        return true
    }

    private func groupResizeDraggedAnchor(
        for handleRole: CanvasSelectionHandleRole,
        in frame: CGRect
    ) -> CGPoint {
        let frame = frame.standardized
        switch handleRole {
        case .topLeading:
            return CGPoint(x: frame.minX, y: frame.minY)
        case .top:
            return CGPoint(x: frame.midX, y: frame.minY)
        case .topTrailing:
            return CGPoint(x: frame.maxX, y: frame.minY)
        case .trailing:
            return CGPoint(x: frame.maxX, y: frame.midY)
        case .bottomTrailing:
            return CGPoint(x: frame.maxX, y: frame.maxY)
        case .bottom:
            return CGPoint(x: frame.midX, y: frame.maxY)
        case .bottomLeading:
            return CGPoint(x: frame.minX, y: frame.maxY)
        case .leading:
            return CGPoint(x: frame.minX, y: frame.midY)
        }
    }

    private func groupFrame(
        from initialFrame: CGRect,
        handleRole: CanvasSelectionHandleRole,
        draggedAnchor: CGPoint,
        minimumSize: CGSize
    ) -> CGRect {
        let frame = initialFrame.standardized
        let minimumWidth = max(minimumSize.width, 1)
        let minimumHeight = max(minimumSize.height, 1)

        switch handleRole {
        case .topLeading:
            let minX = min(draggedAnchor.x, frame.maxX - minimumWidth)
            let minY = min(draggedAnchor.y, frame.maxY - minimumHeight)
            return CGRect(
                x: minX,
                y: minY,
                width: frame.maxX - minX,
                height: frame.maxY - minY
            ).standardized
        case .top:
            let minY = min(draggedAnchor.y, frame.maxY - minimumHeight)
            return CGRect(
                x: frame.minX,
                y: minY,
                width: frame.width,
                height: frame.maxY - minY
            ).standardized
        case .topTrailing:
            let maxX = max(draggedAnchor.x, frame.minX + minimumWidth)
            let minY = min(draggedAnchor.y, frame.maxY - minimumHeight)
            return CGRect(
                x: frame.minX,
                y: minY,
                width: maxX - frame.minX,
                height: frame.maxY - minY
            ).standardized
        case .trailing:
            let maxX = max(draggedAnchor.x, frame.minX + minimumWidth)
            return CGRect(
                x: frame.minX,
                y: frame.minY,
                width: maxX - frame.minX,
                height: frame.height
            ).standardized
        case .bottomTrailing:
            let maxX = max(draggedAnchor.x, frame.minX + minimumWidth)
            let maxY = max(draggedAnchor.y, frame.minY + minimumHeight)
            return CGRect(
                x: frame.minX,
                y: frame.minY,
                width: maxX - frame.minX,
                height: maxY - frame.minY
            ).standardized
        case .bottom:
            let maxY = max(draggedAnchor.y, frame.minY + minimumHeight)
            return CGRect(
                x: frame.minX,
                y: frame.minY,
                width: frame.width,
                height: maxY - frame.minY
            ).standardized
        case .bottomLeading:
            let minX = min(draggedAnchor.x, frame.maxX - minimumWidth)
            let maxY = max(draggedAnchor.y, frame.minY + minimumHeight)
            return CGRect(
                x: minX,
                y: frame.minY,
                width: frame.maxX - minX,
                height: maxY - frame.minY
            ).standardized
        case .leading:
            let minX = min(draggedAnchor.x, frame.maxX - minimumWidth)
            return CGRect(
                x: minX,
                y: frame.minY,
                width: frame.maxX - minX,
                height: frame.height
            ).standardized
        }
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
        let minimumScale: CGFloat
        if handleRole.isWidthOnly {
            minimumScale = minimumWorldDimension / initialLocalFrame.width
        } else if handleRole.isHeightOnly {
            minimumScale = minimumWorldDimension / initialLocalFrame.height
        } else {
            minimumScale = max(
                minimumWorldDimension / initialLocalFrame.width,
                minimumWorldDimension / initialLocalFrame.height
            )
        }

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

    private func makePointerArrowEndpointState(
        itemID: CanvasItemID,
        endpointRole: CanvasArrowEndpointRole
    ) -> CanvasArrowEndpointDragState? {
        guard let arrowItem = scene.arrowItem(withID: itemID) else {
            return nil
        }

        let minimumWorldLength = Self.minimumResizeViewportDimension / camera.zoomScale
        return CanvasArrowEndpointDragState(
            item: arrowItem,
            draggedEndpointRole: endpointRole,
            minimumLength: minimumWorldLength
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
        let minimumScale: CGFloat
        if handleRole.isWidthOnly {
            minimumScale = minimumWorldDimension / snapshot.selectionBounds.width
        } else if handleRole.isHeightOnly {
            minimumScale = minimumWorldDimension / snapshot.selectionBounds.height
        } else {
            minimumScale = max(
                minimumWorldDimension / snapshot.selectionBounds.width,
                minimumWorldDimension / snapshot.selectionBounds.height
            )
        }
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
            let proposedLocalFrame = makeResizedLocalFrame(
                using: resizeState,
                draggedViewportLocation: viewportLocation
            ),
            let currentItem = scene.boardItem(withID: resizeState.itemID)
        else {
            return
        }
        let resizedLocalFrame = proposedLocalFrame

        let resizedCenter = referenceWorldPoint(
            fromLocal: CGPoint(
                x: resizedLocalFrame.midX,
                y: resizedLocalFrame.midY
            ),
            center: resizeState.referenceCenter,
            rotationRadians: resizeState.referenceRotationRadians
        )
        let resizedItem: CanvasBoardItem
        if let markdownItem = currentItem.markdownItem {
            let updatedItem = editorSession.normalizedMarkdownItem(
                markdownItem,
                center: resizedCenter,
                size: resizedLocalFrame.size
            )
            guard
                currentItem.center != updatedItem.center ||
                currentItem.size != updatedItem.size ||
                abs(updatedItem.scrollOffsetY - markdownItem.scrollOffsetY) > Self.geometryComparisonEpsilon,
                let appliedItem = scene.applyBoardItems([.markdown(updatedItem)])?.first
            else {
                return
            }
            resizedItem = appliedItem
        } else {
            guard
                currentItem.center != resizedCenter ||
                currentItem.size != resizedLocalFrame.size,
                let appliedItem = scene.resizeBoardItem(
                    withID: resizeState.itemID,
                    toCenter: resizedCenter,
                    size: resizedLocalFrame.size
                )
            else {
                return
            }
            resizedItem = appliedItem
        }

        expandBoardIfNeeded(toInclude: resizedItem.worldBounds)
        refreshCanvas()
    }

    private func adjustArrowEndpoint(
        using endpointState: CanvasArrowEndpointDragState,
        to viewportLocation: CGPoint
    ) {
        let geometry = endpointState.updatedGeometry(
            draggedWorldPoint: camera.viewportToWorld(viewportLocation)
        )
        guard
            let updatedArrowItem = scene.applyBoardItemGeometries([geometry])?.first,
            updatedArrowItem.worldBounds.isNull == false
        else {
            return
        }

        expandBoardIfNeeded(toInclude: updatedArrowItem.worldBounds)
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
        let resizedSize: CGSize
        if resizeState.handleRole.isWidthOnly {
            let resolvedWidthScale = max(widthScale, resizeState.minimumScale)
            guard resolvedWidthScale.isFinite else {
                return nil
            }
            resizedSize = CGSize(
                width: resizeState.initialLocalFrame.width * resolvedWidthScale,
                height: resizeState.initialLocalFrame.height
            )
        } else if resizeState.handleRole.isHeightOnly {
            let resolvedHeightScale = max(heightScale, resizeState.minimumScale)
            guard resolvedHeightScale.isFinite else {
                return nil
            }
            resizedSize = CGSize(
                width: resizeState.initialLocalFrame.width,
                height: resizeState.initialLocalFrame.height * resolvedHeightScale
            )
        } else {
            let scale = max(widthScale, heightScale, resizeState.minimumScale)
            guard scale.isFinite else {
                return nil
            }
            resizedSize = CGSize(
                width: resizeState.initialLocalFrame.width * scale,
                height: resizeState.initialLocalFrame.height * scale
            )
        }

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
        case .top:
            return CGPoint(x: localFrame.midX, y: localFrame.maxY)
        case .topTrailing:
            return CGPoint(x: localFrame.minX, y: localFrame.maxY)
        case .bottomLeading:
            return CGPoint(x: localFrame.maxX, y: localFrame.minY)
        case .bottomTrailing:
            return CGPoint(x: localFrame.minX, y: localFrame.minY)
        case .bottom:
            return CGPoint(x: localFrame.midX, y: localFrame.minY)
        case .leading:
            return CGPoint(x: localFrame.maxX, y: localFrame.midY)
        case .trailing:
            return CGPoint(x: localFrame.minX, y: localFrame.midY)
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
        case .top:
            return CGPoint(
                x: oppositeCorner.x,
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
        case .bottom:
            return CGPoint(
                x: oppositeCorner.x,
                y: max(draggedLocalCorner.y, oppositeCorner.y + minimumHeight)
            )
        case .leading:
            return CGPoint(
                x: min(draggedLocalCorner.x, oppositeCorner.x - minimumWidth),
                y: oppositeCorner.y
            )
        case .trailing:
            return CGPoint(
                x: max(draggedLocalCorner.x, oppositeCorner.x + minimumWidth),
                y: oppositeCorner.y
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
        case .top:
            return CGRect(
                x: oppositeCorner.x - (size.width / 2),
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
        case .bottom:
            return CGRect(
                x: oppositeCorner.x - (size.width / 2),
                y: oppositeCorner.y,
                width: size.width,
                height: size.height
            )
        case .leading:
            return CGRect(
                x: oppositeCorner.x - size.width,
                y: oppositeCorner.y - (size.height / 2),
                width: size.width,
                height: size.height
            )
        case .trailing:
            return CGRect(
                x: oppositeCorner.x,
                y: oppositeCorner.y - (size.height / 2),
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

        cancelGroupListNavigationAnimation()
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
        editingGroupTitleID = nil
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
        updateGroupListPresentation()
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
        editingGroupTitleID = nil
        updateWorkspaceModeButtonAppearance()
        updateInlineEditButtonsAppearance()
        updateGroupListPresentation()
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
        editingGroupTitleID = nil
        updateWorkspaceModeButtonAppearance()
        updateInlineEditButtonsAppearance()
        updateGroupListPresentation()
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
        editingGroupTitleID = nil
        updateWorkspaceModeButtonAppearance()
        updateInlineEditButtonsAppearance()
        updateGroupListPresentation()
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
        commitMarkdownScrollHistoryTransactionIfNeeded()
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
        case .arrowEndpointHandle:
            reason = "adjust arrow"
        case .groupSelectionHandle:
            reason = "resize selection"
        case .selectionTranslationArea, .selectedItemBody:
            reason = interactionState.selectionCount > 1
                ? "move selection"
                : "move item"
        case .groupFrameBody, .groupFrameResizeHandle, .unselectedItemBody, .blank:
            return
        }

        editorSession.beginHistoryTransaction(reason: reason)
    }

    private func beginMarkdownScrollHistoryTransactionIfNeeded() {
        guard isMarkdownScrollHistoryTransactionActive == false else {
            return
        }
        editorSession.beginHistoryTransaction(reason: "scroll markdown item")
        isMarkdownScrollHistoryTransactionActive = true
    }

    private func scheduleMarkdownScrollHistoryCommit() {
        markdownScrollHistoryCommitWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.commitMarkdownScrollHistoryTransactionIfNeeded()
        }
        markdownScrollHistoryCommitWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.markdownScrollHistoryCommitDelay,
            execute: workItem
        )
    }

    private func commitMarkdownScrollHistoryTransactionIfNeeded() {
        markdownScrollHistoryCommitWorkItem?.cancel()
        markdownScrollHistoryCommitWorkItem = nil
        guard isMarkdownScrollHistoryTransactionActive else {
            return
        }
        isMarkdownScrollHistoryTransactionActive = false
        guard editorSession.commitPendingHistoryTransaction(
            autosaveReason: "scroll markdown item"
        ) else {
            return
        }
        updateInlineEditButtonsAppearance()
    }

    private func commitPendingPointerHistoryTransaction(
        autosaveReason: String
    ) {
        guard editorSession.commitPendingHistoryTransaction(
            reconcilingFrameGroupMembershipsWithAutosaveReason: autosaveReason
        ) else {
            return
        }
        updateInlineEditButtonsAppearance()
    }

    private func finalizeMarkdownResizeCommitIfNeeded(
        for pointerDragState: PointerDragState
    ) {
        let updatedItems: [CanvasMarkdownItem]
        switch pointerDragState {
        case let .resizingSelectedItem(resizeState):
            updatedItems = editorSession.finalizeMarkdownResizeCommit(
                withID: resizeState.itemID,
                handleRole: resizeState.handleRole,
                originalLayoutWidth: resizeState.initialLocalFrame.width
            ).map { [$0] } ?? []
        case let .resizingSelection(resizeState):
            updatedItems = editorSession.finalizeMarkdownResizeCommits(
                handleRole: resizeState.handleRole,
                originalLayoutWidthsByItemID: resizeState.snapshot
                    .markdownLayoutWidthsByItemID()
            )
        case .idle, .pressed, .croppingSelectedItem, .movingCropFrame,
             .rotatingSelectedItem, .rotatingSelection, .draggingSelectedItem,
             .draggingSelection, .draggingGroupFrame, .resizingGroupFrame,
             .adjustingArrowEndpoint, .draggingCanvas:
            return
        }

        guard updatedItems.isEmpty == false else {
            return
        }
        refreshCanvas(reason: "finalize markdown resize commit")
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

    private func syncSelectionAccessoryPresentation(
        layoutContext: CanvasChromeLayoutContext? = nil
    ) {
        guard isViewLoaded else {
            return
        }

        guard let state = resolvedSelectionAccessoryState() else {
            logSelectionAccessoryPresentation(
                state: nil,
                layoutContext: layoutContext
            )
            selectionAccessoryHostView.dismiss()
            return
        }

        let resolvedLayoutContext =
            layoutContext ?? contextMenuLayoutContextForCurrentChromeState()
        logSelectionAccessoryPresentation(
            state: state,
            layoutContext: resolvedLayoutContext
        )
        selectionAccessoryHostView.apply(
            state: state,
            layoutContext: resolvedLayoutContext
        )
    }

    private func resolvedSelectionAccessoryState() -> SelectionAccessoryState? {
        let resolvedWorkspaceMode = workspaceMode
        let resolvedIsTransitionInteractionFrozen = isTransitionInteractionFrozen
        let resolvedHasContextMenu = contextMenuState != nil
        let resolvedHasPresentedOverlayEditor =
            activeOverlayEditorPresentationState != .none
        let resolvedHasInlineEditPresentation = presentationInlineEditState != nil
        let resolvedSelectedItemID = editorSession.singleSelectedItemID
        let resolvedAnchorRect = resolvedSelectedItemID.flatMap {
            selectionAccessoryAnchorRect(for: $0)
        }
        let resolvedState = selectionAccessoryResolver.resolveState(
            session: editorSession,
            environment: CanvasSelectionAccessoryResolver.Environment(
                workspaceMode: resolvedWorkspaceMode,
                isTransitionInteractionFrozen: resolvedIsTransitionInteractionFrozen,
                hasContextMenu: resolvedHasContextMenu,
                hasPresentedOverlayEditor: resolvedHasPresentedOverlayEditor,
                hasInlineEditPresentation: resolvedHasInlineEditPresentation
            ),
            anchorRect: resolvedAnchorRect
        )
        logSelectionAccessoryResolution(
            selectedItemID: resolvedSelectedItemID,
            selectedItemKind: editorSession.selectedBoardItemKind,
            workspaceMode: resolvedWorkspaceMode,
            isTransitionInteractionFrozen: resolvedIsTransitionInteractionFrozen,
            hasContextMenu: resolvedHasContextMenu,
            hasPresentedOverlayEditor: resolvedHasPresentedOverlayEditor,
            hasInlineEditPresentation: resolvedHasInlineEditPresentation,
            anchorRect: resolvedAnchorRect,
            state: resolvedState
        )
        return resolvedState
    }

    private func selectionAccessoryAnchorRect(
        for itemID: CanvasItemID
    ) -> CGRect? {
        if let editOverlay = lastRenderSnapshot.editOverlay,
           case let .selection(payload) = editOverlay.payload
        {
            switch payload.subject {
            case let .singleItem(selectedItemID) where selectedItemID == itemID:
                let resolvedRect = selectionAccessoryHostView.convert(
                    editOverlay.activeScreenQuad.boundingRect.standardized,
                    from: canvasViewportView
                )
                logSelectionAccessoryAnchorRect(
                    itemID: itemID,
                    source: "editOverlay",
                    resolvedRect: resolvedRect
                )
                return resolvedRect
            case .singleItem, .group:
                break
            }
        }

        guard let renderItem = lastRenderSnapshot.items.first(where: {
            $0.id == itemID
        }) else {
            logSelectionAccessoryAnchorRect(
                itemID: itemID,
                source: "renderItemFallbackMissing",
                resolvedRect: nil
            )
            return nil
        }
        let resolvedRect = selectionAccessoryHostView.convert(
            renderItem.screenQuad.boundingRect.standardized,
            from: canvasViewportView
        )
        logSelectionAccessoryAnchorRect(
            itemID: itemID,
            source: "renderItemFallback",
            resolvedRect: resolvedRect
        )
        return resolvedRect
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

    private func presentMarkdownEditorError(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Unable to Open Markdown Editor"
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

    private func logPointerHitResolution(
        phase: String,
        location: CGPoint,
        context: CanvasPointerPressContext
    ) {
        guard Self.isPointerHitTraceLoggingEnabled else {
            return
        }

        let worldPoint = camera.viewportToWorld(location)
        let hitCandidates = scene
            .orderedBoardItems()
            .filter { $0.contains(worldPoint: worldPoint) }
            .reversed()
            .map { item in
                describePointerHitCandidate(
                    item,
                    viewportLocation: location
                )
            }
        let hitCandidateDescriptions = hitCandidates.joined(separator: ", ")
        let resolvedItemDescription = context.targetItemID.flatMap { itemID in
            scene.boardItem(withID: itemID).map {
                describePointerHitCandidate(
                    $0,
                    viewportLocation: location
                )
            }
        } ?? "nil"
        print(
            "[Canvas macOS][PointerHitResolve] " +
            "phase=\(phase) " +
            "viewportPoint=\(describe(point: location)) " +
            "worldPoint=\(describe(point: worldPoint)) " +
            "targetKind=\(describe(pointerTargetKind: context.targetKind)) " +
            "targetItemID=\(describe(itemID: context.targetItemID)) " +
            "targetAnchorRect=\(context.anchorRect.map { describe(rect: $0) } ?? "nil") " +
            "resolvedItem=\(resolvedItemDescription) " +
            "candidateCount=\(hitCandidates.count) " +
            "candidates=[\(hitCandidateDescriptions)]"
        )
    }

    private func describePointerHitCandidate(
        _ item: CanvasBoardItem,
        viewportLocation: CGPoint
    ) -> String {
        let renderItem = lastRenderSnapshot.items.first(where: { $0.id == item.id })
        let renderScreenRect = renderItem.map { describe(rect: $0.screenQuad.boundingRect.standardized) } ?? "nil"
        let renderZIndex = renderItem.map { formatCoordinate($0.zIndex) } ?? "nil"
        let screenContains = renderItem.map { $0.screenQuad.contains(viewportLocation) } ?? false
        return
            "id=\(item.id.uuidString)" +
            "|kind=\(describe(boardItemKind: item.kind))" +
            "|z=\(formatCoordinate(item.zIndex))" +
            "|worldBounds=\(describe(rect: item.worldBounds.standardized))" +
            "|screenBounds=\(renderScreenRect)" +
            "|screenContains=\(screenContains)" +
            "|renderZ=\(renderZIndex)"
    }

    private func describe(boardItemKind: CanvasBoardItemKind) -> String {
        switch boardItemKind {
        case .image:
            return "image"
        case .text:
            return "text"
        case .markdown:
            return "markdown"
        case .handDrawing:
            return "handDrawing"
        case .arrow:
            return "arrow"
        }
    }

    private func describe(pointerTargetKind: CanvasPointerTargetKind) -> String {
        switch pointerTargetKind {
        case .rotateHandle:
            return "rotateHandle"
        case .groupRotateHandle:
            return "groupRotateHandle"
        case let .cropHandle(role):
            return "cropHandle(\(String(describing: role)))"
        case .cropTranslationArea:
            return "cropTranslationArea"
        case let .selectionHandle(role):
            return "selectionHandle(\(String(describing: role)))"
        case let .groupSelectionHandle(role):
            return "groupSelectionHandle(\(String(describing: role)))"
        case let .arrowEndpointHandle(role):
            return "arrowEndpointHandle(\(String(describing: role)))"
        case .selectionTranslationArea:
            return "selectionTranslationArea"
        case .selectedItemBody:
            return "selectedItemBody"
        case .unselectedItemBody:
            return "unselectedItemBody"
        case .groupFrameBody:
            return "groupFrameBody"
        case let .groupFrameResizeHandle(role):
            return "groupFrameResizeHandle(\(String(describing: role)))"
        case .blank:
            return "blank"
        }
    }

    private func logSelectionAccessoryResolution(
        selectedItemID: CanvasItemID?,
        selectedItemKind: CanvasBoardItemKind?,
        workspaceMode: CanvasWorkspaceMode,
        isTransitionInteractionFrozen: Bool,
        hasContextMenu: Bool,
        hasPresentedOverlayEditor: Bool,
        hasInlineEditPresentation: Bool,
        anchorRect: CGRect?,
        state: SelectionAccessoryState?
    ) {
        guard Self.isSelectionAccessoryTraceLoggingEnabled else {
            return
        }

        let resolvedAnchorRect = anchorRect.map(describe(rect:)) ?? "nil"
        let resolvedStateAnchorRect = state.map { describe(rect: $0.anchorRect) } ?? "nil"
        let resolvedActionStates = state?.actionStates.map {
            "\(String(describing: $0.commandID)) enabled=\($0.descriptor.isEnabled)"
        }.joined(separator: ", ") ?? "nil"
        print(
            "[Canvas macOS][SelectionAccessory] " +
            "event=resolveState " +
            "selectedItemID=\(describe(itemID: selectedItemID)) " +
            "selectedItemKind=\(String(describing: selectedItemKind)) " +
            "workspaceMode=\(workspaceMode.rawValue) " +
            "isTransitionInteractionFrozen=\(isTransitionInteractionFrozen) " +
            "hasContextMenu=\(hasContextMenu) " +
            "hasPresentedOverlayEditor=\(hasPresentedOverlayEditor) " +
            "hasInlineEditPresentation=\(hasInlineEditPresentation) " +
            "anchorRect=\(resolvedAnchorRect) " +
            "resolvedStateItemID=\(describe(itemID: state?.itemID)) " +
            "resolvedStateAnchorRect=\(resolvedStateAnchorRect) " +
            "resolvedActionCount=\(state?.actionStates.count ?? 0) " +
            "resolvedActionStates=[\(resolvedActionStates)]"
        )
    }

    private func logSelectionAccessoryPresentation(
        state: SelectionAccessoryState?,
        layoutContext: CanvasChromeLayoutContext?
    ) {
        guard Self.isSelectionAccessoryTraceLoggingEnabled else {
            return
        }

        let resolvedSafeBounds = layoutContext.map { describe(rect: $0.safeBounds) } ?? "nil"
        let resolvedOccupiedRectCount = layoutContext?.occupiedRects.count ?? 0
        print(
            "[Canvas macOS][SelectionAccessory] " +
            "event=syncPresentation " +
            "stateItemID=\(describe(itemID: state?.itemID)) " +
            "stateAnchorRect=\(state.map { describe(rect: $0.anchorRect) } ?? "nil") " +
            "stateIsEmpty=\(state?.isEmpty ?? true) " +
            "actionCount=\(state?.actionStates.count ?? 0) " +
            "layoutSafeBounds=\(resolvedSafeBounds) " +
            "occupiedRectCount=\(resolvedOccupiedRectCount) " +
            "hostViewBounds=\(describe(rect: selectionAccessoryHostView.bounds)) " +
            "hostViewFrame=\(describe(rect: selectionAccessoryHostView.frame))"
        )
    }

    private func logSelectionAccessoryAnchorRect(
        itemID: CanvasItemID,
        source: String,
        resolvedRect: CGRect?
    ) {
        guard Self.isSelectionAccessoryTraceLoggingEnabled else {
            return
        }

        print(
            "[Canvas macOS][SelectionAccessory] " +
            "event=resolveAnchorRect " +
            "itemID=\(itemID.uuidString) " +
            "source=\(source) " +
            "resolvedRect=\(resolvedRect.map { describe(rect: $0) } ?? "nil") " +
            "hostBounds=\(describe(rect: selectionAccessoryHostView.bounds)) " +
            "viewportBounds=\(describe(rect: canvasViewportView.bounds)) " +
            "snapshotViewportBounds=\(describe(rect: lastRenderSnapshot.viewportBounds))"
        )
    }

    private func logMarkdownAccessoryDismissRestore(
        reason: String,
        step: String
    ) {
        guard Self.isSelectionAccessoryTraceLoggingEnabled else {
            return
        }
        print(
            "[Canvas macOS][MarkdownAccessory] " +
            "event=restoreAfterDismiss " +
            "reason=\(reason) " +
            "step=\(step) " +
            "selectedItemID=\(describe(itemID: editorSession.singleSelectedItemID)) " +
            "selectedMarkdownItemID=\(describe(itemID: editorSession.selectedMarkdownItem?.id)) " +
            "presentedOverlayEditor=\(activeOverlayEditorPresentationState != .none) " +
            "inlineEditPresentation=\(presentationInlineEditState != nil) " +
            "hostHidden=\(selectionAccessoryHostView.isHidden)"
        )
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
        case .draggingGroupFrame:
            return "draggingGroupFrame"
        case .resizingGroupFrame:
            return "resizingGroupFrame"
        case .resizingSelectedItem:
            return "resizingSelectedItem"
        case .adjustingArrowEndpoint:
            return "adjustingArrowEndpoint"
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

private final class macOSCanvasGroupListView: NSView, NSTextFieldDelegate {
    var onAddGroupRequested: (() -> Void)?
    var onGroupSelected: ((CanvasItemGroupID) -> Void)?
    var onEditGroupTitleRequested: ((CanvasItemGroupID) -> Void)?
    var onGroupTitleSubmitted: ((CanvasItemGroupID, String) -> Void)?

    private var renderedGroups: [CanvasItemGroup] = []
    private var renderedEditingGroupTitleID: CanvasItemGroupID?
    private var programmaticFocusGroupTitleID: CanvasItemGroupID?

    private let scrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        return scrollView
    }()
    private let documentView: macOSCanvasChromeOverlayView = {
        let view = macOSCanvasChromeOverlayView()
        view.translatesAutoresizingMaskIntoConstraints = true
        return view
    }()
    private let stackView: NSStackView = {
        let stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = true
        stackView.orientation = .vertical
        stackView.alignment = .width
        stackView.distribution = .gravityAreas
        stackView.spacing = 10
        return stackView
    }()

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    override func layout() {
        super.layout()
        updateDocumentLayout()
    }

    func render(
        groups: [CanvasItemGroup],
        editingGroupTitleID: CanvasItemGroupID?
    ) {
        macOSGroupTitleEditTrace(
            "list.render.start",
            editingGroupTitleID: editingGroupTitleID,
            firstResponder: window?.firstResponder
        )
        renderedGroups = groups
        renderedEditingGroupTitleID = editingGroupTitleID
        var focusedTitleTextField: NSTextField?
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        stackView.addArrangedSubview(makeAddGroupRow())

        if groups.isEmpty {
            stackView.addArrangedSubview(makeEmptyStateLabel())
        } else {
            for group in groups {
                stackView.addArrangedSubview(
                    makeGroupRow(
                        for: group,
                        isEditingTitle: group.id == editingGroupTitleID,
                        focusedTitleTextField: &focusedTitleTextField
                    )
                )
            }
        }

        updateDocumentLayout()
        if let focusedTitleTextField {
            macOSGroupTitleEditTrace(
                "list.render.scheduleFocus",
                groupID: (focusedTitleTextField as? macOSCanvasGroupTitleTextField)?.groupID,
                editingGroupTitleID: editingGroupTitleID,
                title: focusedTitleTextField.stringValue,
                firstResponder: window?.firstResponder
            )
            DispatchQueue.main.async { [weak self, weak focusedTitleTextField] in
                guard let self, let focusedTitleTextField else {
                    return
                }

                let focusedGroupID = (focusedTitleTextField as? macOSCanvasGroupTitleTextField)?.groupID
                self.programmaticFocusGroupTitleID = focusedGroupID
                macOSGroupTitleEditTrace(
                    "list.render.focus.before",
                    groupID: focusedGroupID,
                    editingGroupTitleID: self.renderedEditingGroupTitleID,
                    title: focusedTitleTextField.stringValue,
                    firstResponder: self.window?.firstResponder
                )
                let didFocus = self.window?.makeFirstResponder(focusedTitleTextField) ?? false
                focusedTitleTextField.selectText(nil)
                macOSGroupTitleEditTrace(
                    "list.render.focus.after",
                    groupID: focusedGroupID,
                    editingGroupTitleID: self.renderedEditingGroupTitleID,
                    title: focusedTitleTextField.stringValue,
                    firstResponder: self.window?.firstResponder,
                    detail: "didFocus=\(didFocus)"
                )
                DispatchQueue.main.async { [weak self] in
                    guard self?.programmaticFocusGroupTitleID == focusedGroupID else {
                        return
                    }

                    self?.programmaticFocusGroupTitleID = nil
                }
            }
        }
    }

    func updateAppearance() {
        let appearance = effectiveAppearance
        PlatformLayerAppearance.performWithoutAnimations {
            layer?.backgroundColor = PlatformLayerAppearance.resolvedCGColor(
                NSColor.controlBackgroundColor.withAlphaComponent(0.92),
                for: appearance
            )
            layer?.borderColor = PlatformLayerAppearance.resolvedCGColor(
                NSColor.separatorColor.withAlphaComponent(0.35),
                for: appearance
            )
            layer?.shadowColor = PlatformLayerAppearance.resolvedCGColor(
                NSColor.black.withAlphaComponent(0.35),
                for: appearance
            )
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
        render(
            groups: renderedGroups,
            editingGroupTitleID: renderedEditingGroupTitleID
        )
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = false
        layer?.borderWidth = 1
        layer?.shadowOpacity = 0.16
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: -8)

        scrollView.documentView = documentView
        addSubview(scrollView)
        documentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        updateAppearance()
    }

    private func updateDocumentLayout() {
        let contentWidth = max(scrollView.contentView.bounds.width, 0)
        let stackWidth = max(contentWidth - 24, 0)
        stackView.frame = CGRect(
            x: 12,
            y: 12,
            width: stackWidth,
            height: max(stackView.frame.height, 1)
        )
        stackView.layoutSubtreeIfNeeded()
        let stackHeight = max(stackView.fittingSize.height, 0)

        stackView.frame = CGRect(
            x: 12,
            y: 12,
            width: stackWidth,
            height: stackHeight
        )

        documentView.frame = CGRect(
            x: 0,
            y: 0,
            width: contentWidth,
            height: max(
                stackView.frame.maxY + 12,
                scrollView.contentView.bounds.height
            )
        )
    }

    private func makeAddGroupRow() -> NSButton {
        let button = NSButton(title: "添加group", target: self, action: #selector(handleAddGroupButtonClick))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setButtonType(.momentaryPushIn)
        button.isBordered = false
        button.alignment = .left
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.contentTintColor = .labelColor
        button.image = NSImage(
            systemSymbolName: "plus.circle.fill",
            accessibilityDescription: "Add group"
        )
        button.imagePosition = .imageLeft
        button.wantsLayer = true
        button.layer?.cornerRadius = 12
        button.layer?.borderWidth = 1

        let appearance = effectiveAppearance
        PlatformLayerAppearance.performWithoutAnimations {
            button.layer?.backgroundColor = PlatformLayerAppearance.resolvedCGColor(
                .windowBackgroundColor,
                for: appearance
            )
            button.layer?.borderColor = PlatformLayerAppearance.resolvedCGColor(
                .separatorColor,
                for: appearance
            )
        }

        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return button
    }

    @objc
    private func handleAddGroupButtonClick() {
        onAddGroupRequested?()
    }

    private func makeEmptyStateLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "No groups yet")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }

    private func makeGroupRow(
        for group: CanvasItemGroup,
        isEditingTitle: Bool,
        focusedTitleTextField: inout NSTextField?
    ) -> NSView {
        let container = macOSCanvasChromeOverlayView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 12

        let outerStack = NSStackView()
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        outerStack.orientation = .horizontal
        outerStack.alignment = .top
        outerStack.distribution = .fill
        outerStack.spacing = 8

        let rowStack = NSStackView()
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rowStack.orientation = .vertical
        rowStack.alignment = .leading
        rowStack.spacing = 4
        rowStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if isEditingTitle == false {
            rowStack.addGestureRecognizer(
                macOSCanvasGroupClickGestureRecognizer(
                    groupID: group.id,
                    target: self,
                    action: #selector(handleGroupRowClick(_:))
                )
            )
        }

        if isEditingTitle {
            let titleTextField = macOSCanvasGroupTitleTextField(groupID: group.id)
            titleTextField.translatesAutoresizingMaskIntoConstraints = false
            titleTextField.font = .systemFont(ofSize: 13, weight: .semibold)
            titleTextField.textColor = .labelColor
            titleTextField.stringValue = group.title
            titleTextField.delegate = self
            titleTextField.lineBreakMode = .byTruncatingTail
            rowStack.addArrangedSubview(titleTextField)
            focusedTitleTextField = titleTextField
        } else {
            let titleLabel = NSTextField(labelWithString: group.displayTitle)
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            titleLabel.textColor = .labelColor
            titleLabel.lineBreakMode = .byWordWrapping
            titleLabel.maximumNumberOfLines = 2
            rowStack.addArrangedSubview(titleLabel)
        }

        let itemCount = group.itemIDs.count
        let metadataLabel = NSTextField(
            labelWithString: "\(itemCount) item\(itemCount == 1 ? "" : "s")"
        )
        metadataLabel.translatesAutoresizingMaskIntoConstraints = false
        metadataLabel.font = .systemFont(ofSize: 11)
        metadataLabel.textColor = .secondaryLabelColor

        rowStack.addArrangedSubview(metadataLabel)

        let descriptionText = group.description
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if descriptionText.isEmpty == false {
            let descriptionLabel = NSTextField(labelWithString: descriptionText)
            descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
            descriptionLabel.font = .systemFont(ofSize: 12)
            descriptionLabel.textColor = .secondaryLabelColor
            descriptionLabel.lineBreakMode = .byWordWrapping
            descriptionLabel.maximumNumberOfLines = 3
            rowStack.addArrangedSubview(descriptionLabel)
        }

        let editButton = makeEditGroupTitleButton(for: group)
        outerStack.addArrangedSubview(rowStack)
        outerStack.addArrangedSubview(editButton)

        container.addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            outerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            outerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            outerStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            editButton.widthAnchor.constraint(equalToConstant: 32),
            editButton.heightAnchor.constraint(equalToConstant: 32)
        ])

        PlatformLayerAppearance.performWithoutAnimations {
            container.layer?.backgroundColor = PlatformLayerAppearance.resolvedCGColor(
                NSColor.tertiaryLabelColor.withAlphaComponent(0.10),
                for: effectiveAppearance
            )
        }

        return container
    }

    @objc
    private func handleGroupRowClick(_ sender: macOSCanvasGroupClickGestureRecognizer) {
        onGroupSelected?(sender.groupID)
    }

    private func makeEditGroupTitleButton(for group: CanvasItemGroup) -> NSButton {
        let button = macOSCanvasGroupEditButton(groupID: group.id)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.title = ""
        button.toolTip = "Edit group name"
        button.image = NSImage(
            systemSymbolName: "pencil",
            accessibilityDescription: "Edit group name"
        )
        button.imagePosition = .imageOnly
        button.contentTintColor = .labelColor
        button.target = self
        button.action = #selector(handleEditGroupTitleButtonClick(_:))
        button.wantsLayer = true
        button.layer?.cornerRadius = 16
        button.layer?.borderWidth = 1

        PlatformLayerAppearance.performWithoutAnimations {
            button.layer?.backgroundColor = PlatformLayerAppearance.resolvedCGColor(
                .windowBackgroundColor,
                for: effectiveAppearance
            )
            button.layer?.borderColor = PlatformLayerAppearance.resolvedCGColor(
                .separatorColor,
                for: effectiveAppearance
            )
        }
        return button
    }

    @objc
    private func handleEditGroupTitleButtonClick(_ sender: macOSCanvasGroupEditButton) {
        macOSGroupTitleEditTrace(
            "list.editButton.click",
            groupID: sender.groupID,
            editingGroupTitleID: renderedEditingGroupTitleID,
            firstResponder: window?.firstResponder
        )
        onEditGroupTitleRequested?(sender.groupID)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else {
            return
        }

        macOSGroupTitleEditTrace(
            "list.controlTextDidEndEditing",
            groupID: (textField as? macOSCanvasGroupTitleTextField)?.groupID,
            editingGroupTitleID: renderedEditingGroupTitleID,
            title: textField.stringValue,
            firstResponder: window?.firstResponder
        )
        if let titleTextField = textField as? macOSCanvasGroupTitleTextField,
           programmaticFocusGroupTitleID == titleTextField.groupID {
            macOSGroupTitleEditTrace(
                "list.controlTextDidEndEditing.ignoredProgrammaticFocus",
                groupID: titleTextField.groupID,
                editingGroupTitleID: renderedEditingGroupTitleID,
                title: titleTextField.stringValue,
                firstResponder: window?.firstResponder
            )
            return
        }

        submitGroupTitle(from: textField)
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
            return false
        }

        macOSGroupTitleEditTrace(
            "list.control.insertNewline",
            groupID: (control as? macOSCanvasGroupTitleTextField)?.groupID,
            editingGroupTitleID: renderedEditingGroupTitleID,
            title: control.stringValue,
            firstResponder: window?.firstResponder
        )
        submitGroupTitle(from: control)
        window?.makeFirstResponder(nil)
        return true
    }

    private func submitGroupTitle(from control: NSControl) {
        guard let titleTextField = control as? macOSCanvasGroupTitleTextField else {
            macOSGroupTitleEditTrace(
                "list.submit.ignoredNonGroupTitleField",
                editingGroupTitleID: renderedEditingGroupTitleID,
                title: control.stringValue,
                firstResponder: window?.firstResponder
            )
            return
        }

        guard renderedEditingGroupTitleID == titleTextField.groupID else {
            macOSGroupTitleEditTrace(
                "list.submit.ignoredStaleEditingID",
                groupID: titleTextField.groupID,
                editingGroupTitleID: renderedEditingGroupTitleID,
                title: titleTextField.stringValue,
                firstResponder: window?.firstResponder
            )
            return
        }

        macOSGroupTitleEditTrace(
            "list.submit",
            groupID: titleTextField.groupID,
            editingGroupTitleID: renderedEditingGroupTitleID,
            title: titleTextField.stringValue,
            firstResponder: window?.firstResponder
        )
        onGroupTitleSubmitted?(
            titleTextField.groupID,
            titleTextField.stringValue
        )
    }
}

private final class macOSCanvasGroupEditButton: NSButton {
    let groupID: CanvasItemGroupID

    init(groupID: CanvasItemGroupID) {
        self.groupID = groupID
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        return nil
    }
}

private final class macOSCanvasGroupClickGestureRecognizer: NSClickGestureRecognizer {
    let groupID: CanvasItemGroupID

    init(
        groupID: CanvasItemGroupID,
        target: Any?,
        action: Selector?
    ) {
        self.groupID = groupID
        super.init(target: target, action: action)
    }

    required init?(coder: NSCoder) {
        return nil
    }
}

private final class macOSCanvasGroupTitleTextField: NSTextField {
    let groupID: CanvasItemGroupID

    init(groupID: CanvasItemGroupID) {
        self.groupID = groupID
        super.init(frame: .zero)
        isEditable = true
        isSelectable = true
        isBordered = true
        drawsBackground = true
        focusRingType = .default
    }

    required init?(coder: NSCoder) {
        return nil
    }
}
#endif
