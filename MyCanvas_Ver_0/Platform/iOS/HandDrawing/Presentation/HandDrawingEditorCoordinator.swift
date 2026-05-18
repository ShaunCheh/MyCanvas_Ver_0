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
    private let previewRenderer = HandDrawingPreviewRenderer()
    private let initialDocument: HandDrawingDocument
    private var engine: HandDrawingEditorEngine
    private var committedImage: CGImage?
    private var selectedTool: HandDrawingEditorTool = .brush
    private var selectedColor: HandDrawingColor
    private var selectedLineWidth: CGFloat
    private var activeStrokeBrush: HandDrawingBrushStyle?
    private var activeStrokeSamples: [HandDrawingInputSample] = []

    var onSurfaceStateChange: ((HandDrawingCanvasSurfaceState) -> Void)?
    var onPaletteStateChange: ((HandDrawingToolPaletteState) -> Void)?
    var onErrorMessage: ((String) -> Void)?

    init(editorContext: CanvasHandDrawingEditorContext) throws {
        self.editorContext = editorContext
        let document = try HandDrawingDocumentLoader.loadDocument(
            from: editorContext.documentData,
            paper: editorContext.paper
        )
        initialDocument = document
        engine = HandDrawingEditorEngine(document: document)
        let initialBrush = document.strokes.last?.brush ?? .defaultPen
        selectedColor = initialBrush.color
        selectedLineWidth = CGFloat(initialBrush.baseSize)
        committedImage = try Self.renderCommittedImage(
            for: document,
            previewRenderer: previewRenderer
        )
    }

    func activate() {
        publishSurfaceState()
        publishPaletteState()
    }

    func selectTool(_ tool: HandDrawingEditorTool) {
        switch tool {
        case .brush:
            selectedTool = tool
        case .pixelEraser, .lasso:
            return
        }
        publishPaletteState()
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
        clearActiveStroke()
        guard engine.undo() else {
            return
        }
        refreshCommittedImageAndPublishState()
    }

    func redo() {
        clearActiveStroke()
        guard engine.redo() else {
            return
        }
        refreshCommittedImageAndPublishState()
    }

    func handlePencilStrokeBegan(_ sample: HandDrawingInputSample) {
        guard selectedTool == .brush else {
            return
        }
        activeStrokeBrush = currentBrushStyle
        activeStrokeSamples = [sample]
        publishSurfaceState()
    }

    func handlePencilStrokeMoved(_ samples: [HandDrawingInputSample]) {
        guard activeStrokeBrush != nil else {
            return
        }
        appendStrokeSamples(samples)
        publishSurfaceState()
    }

    func handlePencilStrokeEnded(_ samples: [HandDrawingInputSample]) {
        guard let activeStrokeBrush else {
            return
        }
        appendStrokeSamples(samples)
        defer {
            clearActiveStroke()
        }
        guard activeStrokeSamples.isEmpty == false else {
            publishSurfaceState()
            return
        }
        _ = engine.appendStroke(
            brush: activeStrokeBrush,
            samples: activeStrokeSamples
        )
        refreshCommittedImageAndPublishState()
    }

    func handlePencilStrokeCancelled() {
        clearActiveStroke()
        publishSurfaceState()
    }

    func makeCommitSubmissionIfNeeded() throws -> CanvasHandDrawingEditSubmission? {
        if activeStrokeBrush != nil {
            handlePencilStrokeEnded([])
        }

        let currentDocument = engine.state.document
        guard currentDocument != initialDocument else {
            return nil
        }

        let previewCGImage: CGImage
        if currentDocument.isEmpty {
            previewCGImage = try CanvasHandDrawingPreviewAssetFactory
                .makeTransparentPreview(for: editorContext.paper)
        } else {
            previewCGImage = try previewRenderer.renderPreviewImage(
                for: currentDocument,
                scale: 1
            )
        }

        return CanvasHandDrawingEditSubmission(
            documentData: try engine.encodedDocumentData(),
            previewCGImage: previewCGImage,
            isEmpty: currentDocument.isEmpty,
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
                draftStroke: draftStroke
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
                isPixelEraserEnabled: false,
                isLassoEnabled: false
            )
        )
    }

    private func refreshCommittedImageAndPublishState() {
        do {
            committedImage = try Self.renderCommittedImage(
                for: engine.state.document,
                previewRenderer: previewRenderer
            )
            publishSurfaceState()
            publishPaletteState()
        } catch {
            onErrorMessage?(error.localizedDescription)
        }
    }

    private static func renderCommittedImage(
        for document: HandDrawingDocument,
        previewRenderer: HandDrawingPreviewRenderer
    ) throws -> CGImage? {
        guard document.isEmpty == false else {
            return nil
        }
        return try previewRenderer.renderPreviewImage(for: document, scale: 1)
    }
}
#endif
