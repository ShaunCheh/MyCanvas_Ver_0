#if os(iOS)
import CoreGraphics
import Foundation

enum HandDrawingEditorTool: Equatable {
    case brush
    case pixelEraser
    case lasso
}

struct HandDrawingCommittedCanvasHostState {
    var output: HandDrawingCommittedCanvasRenderOutput
}

struct HandDrawingRealtimeDraftHostState {
    var output: HandDrawingRealtimeDraftRenderOutput
}

struct HandDrawingCanvasInteractionOverlayState {
    var lassoPathPoints: [CGPoint]
    var selectedStrokeBounds: CGRect?
}

struct HandDrawingCanvasSurfaceState {
    var paperSize: CGSize
    var committedHost: HandDrawingCommittedCanvasHostState
    var realtimeDraftHost: HandDrawingRealtimeDraftHostState
    var interactionOverlay: HandDrawingCanvasInteractionOverlayState
}

struct HandDrawingToolPaletteState {
    var selectedTool: HandDrawingEditorTool
    var selectedColor: HandDrawingColor
    var selectedBrushPresetID: String
    var availableColors: [HandDrawingColor]
    var availableBrushPresets: [HandDrawingBrushPreset]
    var canUndo: Bool
    var canRedo: Bool
    var isBrushEnabled: Bool
    var isPixelEraserEnabled: Bool
    var isLassoEnabled: Bool
    var canDeselectSelection: Bool
}

@MainActor
final class HandDrawingEditorCoordinator {
    static let defaultColors: [HandDrawingColor] = [
        .black,
        HandDrawingColor(red: 0.87, green: 0.18, blue: 0.18),
        HandDrawingColor(red: 0.17, green: 0.45, blue: 0.88),
        HandDrawingColor(red: 0.15, green: 0.63, blue: 0.29),
        HandDrawingColor(red: 0.96, green: 0.57, blue: 0.12),
        HandDrawingColor(red: 0.57, green: 0.28, blue: 0.84)
    ]
    static let defaultLineWidths: [CGFloat] = [4, 8, 12, 18]
    static let defaultBrushPresets: [HandDrawingBrushPreset] =
        HandDrawingBrushPresetCatalog.defaultPenPresets(
            lineWidths: defaultLineWidths,
            tiltSizeInfluence: HandDrawingBrushStyle.defaultPresetTiltSizeInfluence,
            tiltOpacityInfluence: HandDrawingBrushStyle.defaultPresetTiltOpacityInfluence
        )

    private let editorContext: CanvasHandDrawingEditorContext
    private let committedCanvasBackend: HandDrawingCommittedCanvasBackend
    private let realtimeBrushRenderer: HandDrawingRealtimeBrushRenderer
    private let previewRenderer = HandDrawingPreviewRenderer()
    private let initialDocument: HandDrawingDocument
    private var engine: HandDrawingEditorEngine
    private var committedCanvas: HandDrawingCommittedCanvasRenderOutput = .none
    private var selectedTool: HandDrawingEditorTool = .brush
    private var selectedColor: HandDrawingColor
    private var availableBrushPresets: [HandDrawingBrushPreset]
    private var selectedBrushPresetID: String
    private var activeStrokeBrush: HandDrawingBrushStyle?
    private var activeStrokePerformanceProfile: HandDrawingStrokePerformanceProfile?
    private var activeStrokeInputSamples: [HandDrawingInputSample] = []
    private var pixelEraserToolController = HandDrawingPixelEraserToolController()
    private var lassoToolController = HandDrawingLassoToolController()
    private var moveSelectionController = HandDrawingMoveSelectionController()

    var onSurfaceStateChange: ((HandDrawingCanvasSurfaceState) -> Void)?
    var onPaletteStateChange: ((HandDrawingToolPaletteState) -> Void)?
    var onLayerPanelStateChange: ((HandDrawingLayerPanelState) -> Void)?
    var onErrorMessage: ((String) -> Void)?

    init(
        editorContext: CanvasHandDrawingEditorContext,
        committedCanvasBackend: HandDrawingCommittedCanvasBackend? = nil,
        realtimeBrushRenderer: HandDrawingRealtimeBrushRenderer = HandDrawingCPURealtimeBrushRenderer()
    ) throws {
        self.editorContext = editorContext
        let document = try HandDrawingDocumentLoader.loadDocument(
            from: editorContext.documentData,
            paper: editorContext.paper
        )
        let resolvedCommittedCanvasBackend = try committedCanvasBackend
            ?? HandDrawingCPUCommittedCanvasBackend(paperSize: document.paper.size)
        self.committedCanvasBackend = resolvedCommittedCanvasBackend
        self.realtimeBrushRenderer = realtimeBrushRenderer
        initialDocument = document
        engine = HandDrawingEditorEngine(document: document)
        let initialBrush = document.strokes.last?.brush
            ?? Self.defaultBrushPresets.first?.makeBrushStyle(color: .black)
            ?? .defaultPen
        let initialPresetSelection = HandDrawingBrushPresetCatalog.resolveSelection(
            for: initialBrush,
            presets: Self.defaultBrushPresets
        )
        selectedColor = initialBrush.color
        availableBrushPresets = initialPresetSelection.availablePresets
        selectedBrushPresetID = initialPresetSelection.selectedPresetID
        committedCanvas = try resolvedCommittedCanvasBackend.render(
            document: document,
            dirtyRegion: document.paperBounds
        )
    }

    func activate() {
        publishSurfaceState()
        publishPaletteState()
        publishLayerPanelState()
    }

    func selectTool(_ tool: HandDrawingEditorTool) {
        endTransientInteractionState()
        switch tool {
        case .brush, .pixelEraser:
            selectedTool = tool
            clearActiveStroke()
        case .lasso:
            selectedTool = .lasso
        }
        publishSurfaceState()
        publishPaletteState()
    }

    func deselectSelection() {
        endTransientInteractionState()
        if engine.apply(command: .deselectAll) {
            publishSurfaceState()
            publishPaletteState()
        }
    }

    func selectColor(_ color: HandDrawingColor) {
        selectedColor = color
        publishPaletteState()
    }

    func selectBrushPreset(_ presetID: String) {
        guard availableBrushPresets.contains(where: { $0.id == presetID }) else {
            return
        }
        selectedBrushPresetID = presetID
        publishPaletteState()
    }

    func undo() {
        endTransientInteractionState()
        guard engine.undo() else {
            return
        }
        refreshCommittedCanvasAndPublishState(forceFullRender: true)
    }

    func redo() {
        endTransientInteractionState()
        guard engine.redo() else {
            return
        }
        refreshCommittedCanvasAndPublishState(forceFullRender: true)
    }

    func applyLayerCommand(_ command: HandDrawingLayerCommand) {
        endTransientInteractionState()
        guard engine.apply(layerCommand: command) else {
            publishSurfaceState()
            publishPaletteState()
            publishLayerPanelState()
            return
        }
        refreshCommittedCanvasAndPublishState(forceFullRender: true)
    }

    func addLayer() {
        applyLayerCommand(.addLayer(name: nil))
    }

    func deleteLayer(withID layerID: UUID) {
        applyLayerCommand(.deleteLayer(id: layerID))
    }

    func renameLayer(withID layerID: UUID, to proposedName: String) {
        applyLayerCommand(.renameLayer(id: layerID, name: proposedName))
    }

    func selectLayer(withID layerID: UUID) {
        applyLayerCommand(.setActive(id: layerID))
    }

    func toggleLayerVisibility(withID layerID: UUID) {
        guard let layer = engine.state.document.layer(withID: layerID) else {
            return
        }
        applyLayerCommand(
            .setVisibility(id: layerID, isVisible: layer.isVisible == false)
        )
    }

    func toggleLayerLock(withID layerID: UUID) {
        guard let layer = engine.state.document.layer(withID: layerID) else {
            return
        }
        applyLayerCommand(
            .setLocked(id: layerID, isLocked: layer.isLocked == false)
        )
    }

    func moveLayerUp(withID layerID: UUID) {
        guard
            let layerIndex = engine.state.document.layers.firstIndex(
                where: { $0.id == layerID }
            )
        else {
            return
        }
        applyLayerCommand(.moveLayer(id: layerID, toIndex: layerIndex + 1))
    }

    func moveLayerDown(withID layerID: UUID) {
        guard
            let layerIndex = engine.state.document.layers.firstIndex(
                where: { $0.id == layerID }
            )
        else {
            return
        }
        applyLayerCommand(.moveLayer(id: layerID, toIndex: layerIndex - 1))
    }

    func handlePencilStrokeBegan(_ sample: HandDrawingInputSample) {
        switch selectedTool {
        case .brush:
            guard engine.canInteractWithActiveLayer else {
                return
            }
            activeStrokeBrush = currentBrushStyle
            let performanceProfile = HandDrawingStrokePerformanceProfile
                .brushStroke(for: currentBrushStyle)
            activeStrokePerformanceProfile = performanceProfile
            activeStrokeInputSamples = HandDrawingInputNormalizer.normalized(
                [sample],
                configuration: performanceProfile.inputNormalization
            )
            publishSurfaceState()
        case .pixelEraser:
            guard engine.canInteractWithActiveLayer else {
                return
            }
            pixelEraserToolController.beginErasing(
                with: sample,
                baseSize: selectedBrushBaseSize,
                engine: &engine
            )
            refreshCommittedCanvasAndPublishState()
        case .lasso:
            guard engine.canInteractWithActiveLayer else {
                return
            }
            if moveSelectionController.beginMoving(with: sample, engine: engine) {
                publishSurfaceState()
                return
            }
            guard lassoToolController.beginLasso(with: sample, engine: engine) else {
                return
            }
            publishSurfaceState()
        }
    }

    func handlePencilStrokeMoved(_ samples: [HandDrawingInputSample]) {
        switch selectedTool {
        case .brush:
            guard activeStrokeBrush != nil else {
                return
            }
            appendStrokeSamples(samples)
            publishSurfaceState()
        case .pixelEraser:
            pixelEraserToolController.appendSamples(
                samples,
                baseSize: selectedBrushBaseSize,
                engine: &engine
            )
            refreshCommittedCanvasAndPublishState()
        case .lasso:
            if moveSelectionController.isActive {
                moveSelectionController.appendSamples(
                    samples,
                    engine: &engine
                )
                refreshCommittedCanvasAndPublishState()
                return
            }
            lassoToolController.appendSamples(samples)
            publishSurfaceState()
        }
    }

    func handlePencilStrokeEnded(_ samples: [HandDrawingInputSample]) {
        switch selectedTool {
        case .brush:
            guard let activeStrokeBrush else {
                return
            }
            appendStrokeSamples(samples)
            guard activeStrokeInputSamples.isEmpty == false else {
                clearActiveStroke()
                publishSurfaceState()
                return
            }
            let committedStroke = HandDrawingStrokeBuilder.makeStroke(
                brush: activeStrokeBrush,
                normalizedSamples: activeStrokeInputSamples
            )
            clearActiveStroke()
            guard
                let committedStroke,
                engine.appendStroke(committedStroke) != nil
            else {
                publishSurfaceState()
                publishPaletteState()
                return
            }
            refreshCommittedCanvasAndPublishState()
        case .pixelEraser:
            pixelEraserToolController.appendSamples(
                samples,
                baseSize: selectedBrushBaseSize,
                engine: &engine
            )
            pixelEraserToolController.endErasing()
            refreshCommittedCanvasAndPublishState()
        case .lasso:
            if moveSelectionController.isActive {
                moveSelectionController.appendSamples(
                    samples,
                    engine: &engine
                )
                moveSelectionController.endMoving()
                refreshCommittedCanvasAndPublishState()
                return
            }
            lassoToolController.appendSamples(samples)
            _ = lassoToolController.endLasso(engine: &engine)
            publishSurfaceState()
            publishPaletteState()
        }
    }

    func handlePencilStrokeCancelled() {
        clearActiveStroke()
        if selectedTool == .pixelEraser {
            pixelEraserToolController.cancelErasing(engine: &engine)
            refreshCommittedCanvasAndPublishState(forceFullRender: true)
            return
        }
        if selectedTool == .lasso {
            if moveSelectionController.isActive {
                moveSelectionController.cancelMoving(engine: &engine)
                refreshCommittedCanvasAndPublishState(forceFullRender: true)
                return
            }
            if lassoToolController.isActive {
                lassoToolController.cancelLasso()
                publishSurfaceState()
                return
            }
        }
        publishSurfaceState()
    }

    func makeCommitSubmissionIfNeeded() throws -> CanvasHandDrawingEditSubmission? {
        if activeStrokeBrush != nil {
            handlePencilStrokeEnded([])
        }
        if pixelEraserToolController.isActive {
            pixelEraserToolController.endErasing()
        }
        if lassoToolController.isActive {
            lassoToolController.cancelLasso()
        }
        if moveSelectionController.isActive {
            moveSelectionController.endMoving()
        }

        let currentDocument = engine.state.document
        guard currentDocument != initialDocument else {
            return nil
        }

        let previewCGImage = try makeCommitPreviewImage(for: currentDocument)
        let isEmpty = CanvasHandDrawingPreviewAssetFactory
            .isPreviewVisuallyEmpty(previewCGImage)

        return CanvasHandDrawingEditSubmission(
            documentData: try engine.encodedDocumentData(),
            previewCGImage: previewCGImage,
            isEmpty: isEmpty,
            contentRevision: UUID()
        )
    }

    private var currentBrushStyle: HandDrawingBrushStyle {
        selectedBrushPreset.makeBrushStyle(color: selectedColor)
    }

    private var currentRealtimeDraftPacket: HandDrawingRealtimeDraftPacket? {
        guard
            let activeStrokeBrush,
            let activeStrokePerformanceProfile,
            activeStrokeInputSamples.isEmpty == false
        else {
            return nil
        }
        guard let draftStroke = HandDrawingStrokeBuilder.makeStroke(
            brush: activeStrokeBrush,
            normalizedSamples: activeStrokeInputSamples
        ) else {
            return nil
        }
        return HandDrawingRealtimeDraftPacket(
            brush: activeStrokeBrush,
            performanceProfile: activeStrokePerformanceProfile,
            normalizedSamples: activeStrokeInputSamples,
            draftStroke: draftStroke,
            resolvedStamps: HandDrawingBrushDynamics.resolvedStamps(
                for: draftStroke,
                layout: activeStrokePerformanceProfile.stampLayout
            )
        )
    }

    private func appendStrokeSamples(_ samples: [HandDrawingInputSample]) {
        let normalizationConfiguration =
            activeStrokePerformanceProfile?.inputNormalization
            ?? HandDrawingStrokePerformanceProfile
                .brushStroke(for: activeStrokeBrush ?? currentBrushStyle)
                .inputNormalization
        activeStrokeInputSamples = HandDrawingInputNormalizer.normalized(
            samples,
            appendingTo: activeStrokeInputSamples,
            configuration: normalizationConfiguration
        )
    }

    private func clearActiveStroke() {
        activeStrokeBrush = nil
        activeStrokePerformanceProfile = nil
        activeStrokeInputSamples.removeAll()
    }

    private func publishSurfaceState() {
        let realtimeDraftOutput = realtimeBrushRenderer.render(
            packet: currentRealtimeDraftPacket
        )
        onSurfaceStateChange?(
            HandDrawingCanvasSurfaceState(
                paperSize: editorContext.paper.size,
                committedHost: HandDrawingCommittedCanvasHostState(
                    output: committedCanvas
                ),
                realtimeDraftHost: HandDrawingRealtimeDraftHostState(
                    output: realtimeDraftOutput
                ),
                interactionOverlay: HandDrawingCanvasInteractionOverlayState(
                    lassoPathPoints: lassoToolController.points,
                    selectedStrokeBounds: selectedStrokeBounds
                ),
            )
        )
    }

    private func publishPaletteState() {
        onPaletteStateChange?(
            HandDrawingToolPaletteState(
                selectedTool: selectedTool,
                selectedColor: selectedColor,
                selectedBrushPresetID: selectedBrushPresetID,
                availableColors: Self.defaultColors,
                availableBrushPresets: availableBrushPresets,
                canUndo: engine.canUndo,
                canRedo: engine.canRedo,
                isBrushEnabled: engine.canInteractWithActiveLayer,
                isPixelEraserEnabled: engine.canInteractWithActiveLayer,
                isLassoEnabled: engine.canInteractWithActiveLayer,
                canDeselectSelection: engine.state.selectedStrokeIDs.isEmpty == false
            )
        )
    }

    private func publishLayerPanelState() {
        onLayerPanelStateChange?(makeLayerPanelState())
    }

    private func makeLayerPanelState() -> HandDrawingLayerPanelState {
        HandDrawingLayerPanelStateBuilder.makeState(from: engine.state.document)
    }

    private func refreshCommittedCanvasAndPublishState(
        forceFullRender: Bool = false
    ) {
        do {
            let dirtyRegion = forceFullRender
                ? engine.state.document.paperBounds
                : engine.consumeDirtyRegion()
            guard forceFullRender || dirtyRegion != nil else {
                return
            }
            committedCanvas = try committedCanvasBackend.render(
                document: engine.state.document,
                dirtyRegion: dirtyRegion
            )
            publishSurfaceState()
            publishPaletteState()
            publishLayerPanelState()
        } catch {
            onErrorMessage?(error.localizedDescription)
        }
    }

    private func makeCommitPreviewImage(
        for document: HandDrawingDocument,
    ) throws -> CGImage {
        guard document.isEmpty == false else {
            return try CanvasHandDrawingPreviewAssetFactory
                .makeTransparentPreview(for: editorContext.paper)
        }
        return try previewRenderer.renderPreviewImage(for: document, scale: 1)
    }

    private var selectedStrokeBounds: CGRect? {
        guard engine.state.document.activeLayer?.isVisible != false else {
            return nil
        }
        return HandDrawingStrokeGeometry.unionBounds(
            forStrokeIDs: engine.state.selectedStrokeIDs,
            in: engine.state.document.activeLayerStrokes
        )
    }

    private var selectedBrushPreset: HandDrawingBrushPreset {
        if let matchedPreset = availableBrushPresets.first(where: {
            $0.id == selectedBrushPresetID
        }) {
            return matchedPreset
        }
        return availableBrushPresets[0]
    }

    private var selectedBrushBaseSize: CGFloat {
        selectedBrushPreset.displayLineWidth
    }

    private func endTransientInteractionState() {
        clearActiveStroke()
        pixelEraserToolController.endErasing()
        lassoToolController.cancelLasso()
        moveSelectionController.endMoving()
    }
}
#endif
