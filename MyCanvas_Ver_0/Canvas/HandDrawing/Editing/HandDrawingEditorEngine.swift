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

enum HandDrawingEditorCommand: Equatable {
    case deselectAll
}

struct HandDrawingEditorState: Equatable {
    var document: HandDrawingDocument
    var selectedStrokeIDs: Set<UUID>

    init(
        document: HandDrawingDocument,
        selectedStrokeIDs: Set<UUID> = []
    ) {
        self.document = document
        self.selectedStrokeIDs = selectedStrokeIDs
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

    @discardableResult
    mutating func appendStroke(_ stroke: HandDrawingStroke) -> HandDrawingStroke {
        recordSnapshotForUndo()
        state.document.appendStroke(stroke)
        dirtyRegionTracker.markDirty(stroke.bounds ?? state.document.paperBounds)
        return stroke
    }

    @discardableResult
    mutating func appendStroke(
        brush: HandDrawingBrushStyle,
        samples: [HandDrawingInputSample],
        transform: HandDrawingStrokeTransform = .identity
    ) -> HandDrawingStroke? {
        guard samples.isEmpty == false else {
            return nil
        }
        let stroke = HandDrawingStroke(
            brush: brush,
            samplePoints: samples.map {
                HandDrawingSamplePoint(
                    point: $0.location,
                    force: Double($0.force),
                    timestamp: $0.timestamp,
                    azimuthRadians: $0.azimuthRadians.map(Double.init),
                    altitudeRadians: $0.altitudeRadians.map(Double.init)
                )
            },
            transform: transform
        )
        return appendStroke(stroke)
    }

    mutating func selectStrokes(withIDs strokeIDs: Set<UUID>) {
        let existingStrokeIDs = Set(state.document.strokes.map(\.id))
        state.selectedStrokeIDs = strokeIDs.intersection(existingStrokeIDs)
    }

    mutating func apply(command: HandDrawingEditorCommand) {
        switch command {
        case .deselectAll:
            state.selectedStrokeIDs.removeAll()
        }
    }

    @discardableResult
    mutating func upsertErasePaths(
        _ pathsByStrokeID: [UUID: [HandDrawingErasePath]],
        recordUndo: Bool = true
    ) -> Set<UUID> {
        let targetStrokeIndexes = state.document.strokes.indices.filter { index in
            let strokeID = state.document.strokes[index].id
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
            let strokeID = state.document.strokes[index].id
            guard let paths = pathsByStrokeID[strokeID] else {
                continue
            }

            let oldBounds = state.document.strokes[index].bounds
            for path in paths {
                upsertErasePath(
                    path,
                    into: &state.document.strokes[index]
                )
            }
            let newBounds = state.document.strokes[index].bounds
            dirtyRegionTracker.markDirty(
                resolvedDirtyRegion(oldBounds: oldBounds, newBounds: newBounds)
            )
            mutatedStrokeIDs.insert(strokeID)
        }

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
}
