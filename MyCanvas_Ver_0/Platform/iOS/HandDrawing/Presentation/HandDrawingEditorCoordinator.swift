#if os(iOS)
import CoreGraphics
import Foundation

enum HandDrawingEditorTool: Equatable {
    case brush
    case pixelEraser
    case lasso
}

struct HandDrawingCanvasSurfaceState {
    var paperSize: CGSize
    var committedImage: CGImage?
    var draftStroke: HandDrawingStroke?
    var lassoPathPoints: [CGPoint]
    var selectedStrokeBounds: CGRect?
}

struct HandDrawingToolPaletteState {
    var selectedTool: HandDrawingEditorTool
    var selectedColor: HandDrawingColor
    var selectedLineWidth: CGFloat
    var availableColors: [HandDrawingColor]
    var availableLineWidths: [CGFloat]
    var canUndo: Bool
    var canRedo: Bool
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

    private let editorContext: CanvasHandDrawingEditorContext
    private let canvasRenderer: HandDrawingCanvasRenderer
    private let previewRenderer = HandDrawingPreviewRenderer()
    private let initialDocument: HandDrawingDocument
    private var engine: HandDrawingEditorEngine
    private var committedImage: CGImage?
    private var selectedTool: HandDrawingEditorTool = .brush
    private var selectedColor: HandDrawingColor
    private var selectedLineWidth: CGFloat
    private var activeStrokeBrush: HandDrawingBrushStyle?
    private var activeStrokeSamples: [HandDrawingInputSample] = []
    private var pixelEraserToolController = HandDrawingPixelEraserToolController()
    private var lassoToolController = HandDrawingLassoToolController()
    private var moveSelectionController = HandDrawingMoveSelectionController()

    var onSurfaceStateChange: ((HandDrawingCanvasSurfaceState) -> Void)?
    var onPaletteStateChange: ((HandDrawingToolPaletteState) -> Void)?
    var onErrorMessage: ((String) -> Void)?

    init(editorContext: CanvasHandDrawingEditorContext) throws {
        self.editorContext = editorContext
        let document = try HandDrawingDocumentLoader.loadDocument(
            from: editorContext.documentData,
            paper: editorContext.paper
        )
        canvasRenderer = try HandDrawingCanvasRenderer(paperSize: document.paper.size)
        initialDocument = document
        engine = HandDrawingEditorEngine(document: document)
        let initialBrush = document.strokes.last?.brush ?? .defaultPen
        selectedColor = initialBrush.color
        selectedLineWidth = CGFloat(initialBrush.baseSize)
        committedImage = try canvasRenderer.render(
            document: document,
            dirtyRegion: document.paperBounds
        )
    }

    func activate() {
        publishSurfaceState()
        publishPaletteState()
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

    func selectLineWidth(_ lineWidth: CGFloat) {
        selectedLineWidth = lineWidth
        publishPaletteState()
    }

    func undo() {
        endTransientInteractionState()
        guard engine.undo() else {
            return
        }
        refreshCommittedImageAndPublishState(forceFullRender: true)
    }

    func redo() {
        endTransientInteractionState()
        guard engine.redo() else {
            return
        }
        refreshCommittedImageAndPublishState(forceFullRender: true)
    }

    func applyLayerCommand(_ command: HandDrawingLayerCommand) {
        endTransientInteractionState()
        guard engine.apply(layerCommand: command) else {
            publishSurfaceState()
            publishPaletteState()
            return
        }
        refreshCommittedImageAndPublishState(forceFullRender: true)
    }

    func handlePencilStrokeBegan(_ sample: HandDrawingInputSample) {
        switch selectedTool {
        case .brush:
            activeStrokeBrush = currentBrushStyle
            activeStrokeSamples = [sample]
            publishSurfaceState()
        case .pixelEraser:
            pixelEraserToolController.beginErasing(
                with: sample,
                baseSize: selectedLineWidth,
                engine: &engine
            )
            refreshCommittedImageAndPublishState()
        case .lasso:
            if moveSelectionController.beginMoving(with: sample, engine: engine) {
                publishSurfaceState()
                return
            }
            lassoToolController.beginLasso(with: sample)
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
                baseSize: selectedLineWidth,
                engine: &engine
            )
            refreshCommittedImageAndPublishState()
        case .lasso:
            if moveSelectionController.isActive {
                moveSelectionController.appendSamples(
                    samples,
                    engine: &engine
                )
                refreshCommittedImageAndPublishState()
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
            guard activeStrokeSamples.isEmpty == false else {
                clearActiveStroke()
                publishSurfaceState()
                return
            }
            let committedStrokeSamples = activeStrokeSamples
            clearActiveStroke()
            _ = engine.appendStroke(
                brush: activeStrokeBrush,
                samples: committedStrokeSamples
            )
            refreshCommittedImageAndPublishState()
        case .pixelEraser:
            pixelEraserToolController.appendSamples(
                samples,
                baseSize: selectedLineWidth,
                engine: &engine
            )
            pixelEraserToolController.endErasing()
            refreshCommittedImageAndPublishState()
        case .lasso:
            if moveSelectionController.isActive {
                moveSelectionController.appendSamples(
                    samples,
                    engine: &engine
                )
                moveSelectionController.endMoving()
                refreshCommittedImageAndPublishState()
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
            refreshCommittedImageAndPublishState(forceFullRender: true)
            return
        }
        if selectedTool == .lasso {
            if moveSelectionController.isActive {
                moveSelectionController.cancelMoving(engine: &engine)
                refreshCommittedImageAndPublishState(forceFullRender: true)
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
        HandDrawingBrushStyle(
            kind: .pen,
            color: selectedColor,
            baseSize: Double(selectedLineWidth),
            opacity: 1
        )
    }

    private var draftStroke: HandDrawingStroke? {
        guard
            let activeStrokeBrush,
            activeStrokeSamples.isEmpty == false
        else {
            return nil
        }
        return HandDrawingStroke(
            brush: activeStrokeBrush,
            samplePoints: activeStrokeSamples.map {
                HandDrawingSamplePoint(
                    point: $0.location,
                    force: Double($0.force),
                    timestamp: $0.timestamp,
                    azimuthRadians: $0.azimuthRadians.map(Double.init),
                    altitudeRadians: $0.altitudeRadians.map(Double.init)
                )
            }
        )
    }

    private func appendStrokeSamples(_ samples: [HandDrawingInputSample]) {
        for sample in samples {
            if activeStrokeSamples.last == sample {
                continue
            }
            activeStrokeSamples.append(sample)
        }
    }

    private func clearActiveStroke() {
        activeStrokeBrush = nil
        activeStrokeSamples.removeAll()
    }

    private func publishSurfaceState() {
        onSurfaceStateChange?(
            HandDrawingCanvasSurfaceState(
                paperSize: editorContext.paper.size,
                committedImage: committedImage,
                draftStroke: draftStroke,
                lassoPathPoints: lassoToolController.points,
                selectedStrokeBounds: selectedStrokeBounds
            )
        )
    }

    private func publishPaletteState() {
        onPaletteStateChange?(
            HandDrawingToolPaletteState(
                selectedTool: selectedTool,
                selectedColor: selectedColor,
                selectedLineWidth: selectedLineWidth,
                availableColors: Self.defaultColors,
                availableLineWidths: Self.defaultLineWidths,
                canUndo: engine.canUndo,
                canRedo: engine.canRedo,
                isPixelEraserEnabled: true,
                isLassoEnabled: true,
                canDeselectSelection: engine.state.selectedStrokeIDs.isEmpty == false
            )
        )
    }

    private func refreshCommittedImageAndPublishState(
        forceFullRender: Bool = false
    ) {
        do {
            let dirtyRegion = forceFullRender
                ? engine.state.document.paperBounds
                : engine.consumeDirtyRegion()
            guard forceFullRender || dirtyRegion != nil else {
                return
            }
            committedImage = try canvasRenderer.render(
                document: engine.state.document,
                dirtyRegion: dirtyRegion
            )
            publishSurfaceState()
            publishPaletteState()
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
        HandDrawingStrokeGeometry.unionBounds(
            forStrokeIDs: engine.state.selectedStrokeIDs,
            in: engine.state.document
        )
    }

    private func endTransientInteractionState() {
        clearActiveStroke()
        pixelEraserToolController.endErasing()
        lassoToolController.cancelLasso()
        moveSelectionController.endMoving()
    }
}
#endif
