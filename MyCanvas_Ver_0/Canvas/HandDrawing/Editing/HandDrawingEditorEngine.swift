import CoreGraphics
import Foundation

struct HandDrawingInputSample: Equatable {
    var location: CGPoint
    var force: CGFloat
    var timestamp: TimeInterval
    var azimuthRadians: CGFloat?
    var altitudeRadians: CGFloat?

    init(
        location: CGPoint,
        force: CGFloat = 1,
        timestamp: TimeInterval = 0,
        azimuthRadians: CGFloat? = nil,
        altitudeRadians: CGFloat? = nil
    ) {
        self.location = location
        self.force = force
        self.timestamp = timestamp
        self.azimuthRadians = azimuthRadians
        self.altitudeRadians = altitudeRadians
    }
}

enum HandDrawingLayerCommand: Equatable {
    case addLayer(name: String?)
    case deleteLayer(id: UUID)
    case renameLayer(id: UUID, name: String)
    case moveLayer(id: UUID, toIndex: Int)
    case setVisibility(id: UUID, isVisible: Bool)
    case setLocked(id: UUID, isLocked: Bool)
    case setActive(id: UUID)
}

enum HandDrawingEditorCommand: Equatable {
    case deselectAll
    case layer(HandDrawingLayerCommand)
}

struct HandDrawingEditorState: Equatable {
    var document: HandDrawingDocument
    var selectedStrokeIDs: Set<UUID>

    init(
        document: HandDrawingDocument,
        selectedStrokeIDs: Set<UUID> = []
    ) {
        self.document = document
        self.selectedStrokeIDs = selectedStrokeIDs.intersection(
            document.activeLayerStrokeIDs
        )
    }

    var activeLayerID: UUID {
        document.activeLayerID
    }
}

struct HandDrawingEditorEngine {
    private let previewRenderer: HandDrawingPreviewRenderer
    private var historyController: HandDrawingHistoryController

    private(set) var state: HandDrawingEditorState
    private(set) var dirtyRegionTracker = HandDrawingDirtyRegionTracker()

    init(
        document: HandDrawingDocument,
        previewRenderer: HandDrawingPreviewRenderer = HandDrawingPreviewRenderer(),
        historyController: HandDrawingHistoryController = HandDrawingHistoryController()
    ) {
        state = HandDrawingEditorState(document: document)
        self.previewRenderer = previewRenderer
        self.historyController = historyController
    }

    init(documentData: Data) throws {
        self.init(
            document: try HandDrawingDocumentCodec.decodeDocument(from: documentData)
        )
    }

    var canUndo: Bool {
        historyController.canUndo
    }

    var canRedo: Bool {
        historyController.canRedo
    }

    var canInteractWithActiveLayer: Bool {
        state.document.isActiveLayerInteractive
    }

    @discardableResult
    mutating func appendStroke(_ stroke: HandDrawingStroke) -> HandDrawingStroke? {
        guard canInteractWithActiveLayer else {
            return nil
        }
        recordSnapshotForUndo()
        state.document.appendStroke(stroke)
        dirtyRegionTracker.markDirty(
            stroke.bounds ?? state.document.paperBounds,
            padding: HandDrawingStrokePerformanceProfile.brushStroke(for: stroke.brush)
                .dirtyRegionPadding
        )
        return stroke
    }

    @discardableResult
    mutating func appendStroke(
        brush: HandDrawingBrushStyle,
        samples: [HandDrawingInputSample],
        transform: HandDrawingStrokeTransform = .identity
    ) -> HandDrawingStroke? {
        guard let stroke = HandDrawingStrokeBuilder.makeStroke(
            brush: brush,
            samples: samples,
            transform: transform
        )
        else {
            return nil
        }
        return appendStroke(stroke)
    }

    @discardableResult
    mutating func selectStrokes(
        withIDs strokeIDs: Set<UUID>,
        recordUndo: Bool = true
    ) -> Bool {
        let existingStrokeIDs = state.document.activeLayerStrokeIDs
        let resolvedSelection = strokeIDs.intersection(existingStrokeIDs)
        guard resolvedSelection != state.selectedStrokeIDs else {
            return false
        }
        if recordUndo {
            recordSnapshotForUndo()
        }
        state.selectedStrokeIDs = resolvedSelection
        return true
    }

    @discardableResult
    mutating func apply(
        command: HandDrawingEditorCommand,
        recordUndo: Bool = true
    ) -> Bool {
        switch command {
        case .deselectAll:
            return selectStrokes(
                withIDs: [],
                recordUndo: recordUndo
            )
        case let .layer(layerCommand):
            return apply(
                layerCommand: layerCommand,
                recordUndo: recordUndo
            )
        }
    }

    @discardableResult
    mutating func apply(
        layerCommand: HandDrawingLayerCommand,
        recordUndo: Bool = true
    ) -> Bool {
        applyDocumentMutation(recordUndo: recordUndo) { document in
            switch layerCommand {
            case let .addLayer(name):
                _ = document.insertLayer(named: name)
            case let .deleteLayer(id):
                _ = document.removeLayer(withID: id)
            case let .renameLayer(id, name):
                _ = document.renameLayer(withID: id, to: name)
            case let .moveLayer(id, toIndex):
                _ = document.moveLayer(withID: id, toIndex: toIndex)
            case let .setVisibility(id, isVisible):
                _ = document.setLayerVisibility(withID: id, isVisible: isVisible)
            case let .setLocked(id, isLocked):
                _ = document.setLayerLock(withID: id, isLocked: isLocked)
            case let .setActive(id):
                _ = document.setActiveLayer(withID: id)
            }
        }
    }

    @discardableResult
    mutating func translateSelectedStrokes(
        by delta: CGPoint,
        recordUndo: Bool = true
    ) -> Set<UUID> {
        translateStrokes(
            withIDs: state.selectedStrokeIDs,
            by: delta,
            recordUndo: recordUndo
        )
    }

    @discardableResult
    mutating func upsertErasePaths(
        _ pathsByStrokeID: [UUID: [HandDrawingErasePath]],
        recordUndo: Bool = true
    ) -> Set<UUID> {
        guard canInteractWithActiveLayer else {
            return []
        }
        var activeLayerStrokes = state.document.activeLayerStrokes
        let targetStrokeIndexes = activeLayerStrokes.indices.filter { index in
            let strokeID = activeLayerStrokes[index].id
            guard let paths = pathsByStrokeID[strokeID] else {
                return false
            }
            return paths.isEmpty == false
        }
        guard targetStrokeIndexes.isEmpty == false else {
            return []
        }

        if recordUndo {
            recordSnapshotForUndo()
        }

        var mutatedStrokeIDs: Set<UUID> = []
        for index in targetStrokeIndexes {
            let strokeID = activeLayerStrokes[index].id
            guard let paths = pathsByStrokeID[strokeID] else {
                continue
            }

            let oldBounds = activeLayerStrokes[index].bounds
            for path in paths {
                upsertErasePath(
                    path,
                    into: &activeLayerStrokes[index]
                )
            }
            let newBounds = activeLayerStrokes[index].bounds
            dirtyRegionTracker.markDirty(
                resolvedDirtyRegion(oldBounds: oldBounds, newBounds: newBounds),
                padding: HandDrawingStrokePerformanceProfile
                    .brushStroke(for: activeLayerStrokes[index].brush)
                    .dirtyRegionPadding
            )
            mutatedStrokeIDs.insert(strokeID)
        }

        state.document.replaceStrokesInActiveLayer(with: activeLayerStrokes)
        return mutatedStrokeIDs
    }

    @discardableResult
    mutating func undo() -> Bool {
        guard let snapshot = historyController.undo(current: makeSnapshot()) else {
            return false
        }
        restore(snapshot: snapshot)
        return true
    }

    @discardableResult
    mutating func redo() -> Bool {
        guard let snapshot = historyController.redo(current: makeSnapshot()) else {
            return false
        }
        restore(snapshot: snapshot)
        return true
    }

    func encodedDocumentData() throws -> Data {
        try HandDrawingDocumentCodec.makeDocumentData(for: state.document)
    }

    func renderPreviewImage(
        scale: CGFloat = 1,
        backgroundColor: HandDrawingColor? = nil
    ) throws -> CGImage {
        try previewRenderer.renderPreviewImage(
            for: state.document,
            scale: scale,
            backgroundColor: backgroundColor
        )
    }

    mutating func consumeDirtyRegion() -> CGRect? {
        dirtyRegionTracker.consumeDirtyRegion()
    }

    private mutating func recordSnapshotForUndo() {
        historyController.record(snapshot: makeSnapshot())
    }

    @discardableResult
    private mutating func applyDocumentMutation(
        recordUndo: Bool,
        mutation: (inout HandDrawingDocument) -> Void
    ) -> Bool {
        let originalDocument = state.document
        let originalSelection = state.selectedStrokeIDs
        var updatedDocument = originalDocument
        mutation(&updatedDocument)
        guard updatedDocument != originalDocument else {
            return false
        }
        if recordUndo {
            recordSnapshotForUndo()
        }
        state.document = updatedDocument
        if updatedDocument.activeLayerID != originalDocument.activeLayerID {
            state.selectedStrokeIDs = []
        } else {
            state.selectedStrokeIDs = sanitizedSelection(
                originalSelection,
                in: updatedDocument
            )
        }
        dirtyRegionTracker.markDirty(updatedDocument.paperBounds)
        return true
    }

    @discardableResult
    private mutating func translateStrokes(
        withIDs strokeIDs: Set<UUID>,
        by delta: CGPoint,
        recordUndo: Bool
    ) -> Set<UUID> {
        guard
            canInteractWithActiveLayer,
            strokeIDs.isEmpty == false,
            delta != .zero
        else {
            return []
        }

        var activeLayerStrokes = state.document.activeLayerStrokes
        let targetStrokeIndexes = activeLayerStrokes.indices.filter { index in
            strokeIDs.contains(activeLayerStrokes[index].id)
        }
        guard targetStrokeIndexes.isEmpty == false else {
            return []
        }

        if recordUndo {
            recordSnapshotForUndo()
        }

        var translatedStrokeIDs: Set<UUID> = []
        for index in targetStrokeIndexes {
            let oldBounds = activeLayerStrokes[index].bounds
            activeLayerStrokes[index].transform.translationX += Double(delta.x)
            activeLayerStrokes[index].transform.translationY += Double(delta.y)
            let newBounds = activeLayerStrokes[index].bounds
            dirtyRegionTracker.markDirty(
                resolvedDirtyRegion(oldBounds: oldBounds, newBounds: newBounds),
                padding: HandDrawingStrokePerformanceProfile
                    .brushStroke(for: activeLayerStrokes[index].brush)
                    .dirtyRegionPadding
            )
            translatedStrokeIDs.insert(activeLayerStrokes[index].id)
        }

        state.document.replaceStrokesInActiveLayer(with: activeLayerStrokes)
        return translatedStrokeIDs
    }

    private func makeSnapshot() -> HandDrawingHistorySnapshot {
        HandDrawingHistorySnapshot(
            document: state.document,
            selectedStrokeIDs: state.selectedStrokeIDs
        )
    }

    private mutating func restore(snapshot: HandDrawingHistorySnapshot) {
        state = HandDrawingEditorState(
            document: snapshot.document,
            selectedStrokeIDs: snapshot.selectedStrokeIDs
        )
        dirtyRegionTracker.markDirty(state.document.paperBounds)
    }

    private func resolvedDirtyRegion(
        oldBounds: CGRect?,
        newBounds: CGRect?
    ) -> CGRect? {
        switch (oldBounds, newBounds) {
        case let (oldBounds?, newBounds?):
            return oldBounds.union(newBounds)
        case let (oldBounds?, nil):
            return oldBounds
        case let (nil, newBounds?):
            return newBounds
        case (nil, nil):
            return nil
        }
    }

    private func upsertErasePath(
        _ path: HandDrawingErasePath,
        into stroke: inout HandDrawingStroke
    ) {
        if let existingIndex = stroke.eraseMask.firstIndex(where: { $0.id == path.id }) {
            stroke.eraseMask[existingIndex] = path
        } else {
            stroke.eraseMask.append(path)
        }
    }

    private func sanitizedSelection(
        _ selection: Set<UUID>,
        in document: HandDrawingDocument
    ) -> Set<UUID> {
        selection.intersection(document.activeLayerStrokeIDs)
    }
}
