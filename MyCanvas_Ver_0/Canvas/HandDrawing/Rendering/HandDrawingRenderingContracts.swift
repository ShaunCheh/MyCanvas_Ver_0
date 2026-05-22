import CoreGraphics
import Foundation

enum HandDrawingRealtimeDraftBackendPreference: Equatable {
    case cpu
    case gpuPreferred
}

struct HandDrawingRealtimeNormalizedSampleUpdate: Equatable {
    let stablePrefixCount: Int
    let tailSamples: [HandDrawingInputSample]
}

struct HandDrawingRealtimeResolvedStampUpdate: Equatable {
    let stablePrefixCount: Int
    let tailStamps: [HandDrawingResolvedBrushSample]
}

struct HandDrawingRealtimePredictedTail: Equatable {
    static let empty = HandDrawingRealtimePredictedTail(
        normalizedSamples: [],
        resolvedStamps: []
    )

    let normalizedSamples: [HandDrawingInputSample]
    let resolvedStamps: [HandDrawingResolvedBrushSample]

    var isEmpty: Bool {
        normalizedSamples.isEmpty && resolvedStamps.isEmpty
    }
}

struct HandDrawingRealtimeDraftPacket: Equatable {
    let strokeID: UUID
    let brush: HandDrawingBrushStyle
    let performanceProfile: HandDrawingStrokePerformanceProfile
    let committedSamples: HandDrawingRealtimeNormalizedSampleUpdate
    let committedResolvedStamps: HandDrawingRealtimeResolvedStampUpdate
    let predictedTail: HandDrawingRealtimePredictedTail
}

struct HandDrawingRealtimeDraftRenderState: Equatable {
    let brush: HandDrawingBrushStyle
    let committedResolvedStamps: [HandDrawingResolvedBrushSample]
    let predictedResolvedStamps: [HandDrawingResolvedBrushSample]

    var allResolvedStamps: [HandDrawingResolvedBrushSample] {
        committedResolvedStamps + predictedResolvedStamps
    }
}

final class HandDrawingRealtimeDraftPacketAccumulator {
    private var activeStrokeID: UUID?
    private var activeBrush: HandDrawingBrushStyle?
    private var committedResolvedStamps: [HandDrawingResolvedBrushSample] = []
    private var predictedResolvedStamps: [HandDrawingResolvedBrushSample] = []

    func apply(
        packet: HandDrawingRealtimeDraftPacket?
    ) -> HandDrawingRealtimeDraftRenderState? {
        guard let packet else {
            reset()
            return nil
        }

        if activeStrokeID != packet.strokeID {
            committedResolvedStamps.removeAll()
            predictedResolvedStamps.removeAll()
        }
        activeStrokeID = packet.strokeID
        activeBrush = packet.brush
        committedResolvedStamps = replaceTail(
            in: committedResolvedStamps,
            stablePrefixCount: packet.committedResolvedStamps.stablePrefixCount,
            tail: packet.committedResolvedStamps.tailStamps
        )
        predictedResolvedStamps = packet.predictedTail.resolvedStamps

        guard let activeBrush else {
            return nil
        }
        return HandDrawingRealtimeDraftRenderState(
            brush: activeBrush,
            committedResolvedStamps: committedResolvedStamps,
            predictedResolvedStamps: predictedResolvedStamps
        )
    }

    func reset() {
        activeStrokeID = nil
        activeBrush = nil
        committedResolvedStamps.removeAll()
        predictedResolvedStamps.removeAll()
    }

    private func replaceTail<T>(
        in existingValues: [T],
        stablePrefixCount: Int,
        tail: [T]
    ) -> [T] {
        let resolvedPrefixCount = min(
            max(stablePrefixCount, 0),
            existingValues.count
        )
        return Array(existingValues.prefix(resolvedPrefixCount)) + tail
    }
}

enum HandDrawingRealtimeDraftRenderOutput {
    case none
    case resolved(HandDrawingRealtimeDraftRenderState)

    var resolvedState: HandDrawingRealtimeDraftRenderState? {
        switch self {
        case .none:
            return nil
        case let .resolved(state):
            return state
        }
    }
}

protocol HandDrawingRealtimeBrushRenderer: AnyObject {
    func apply(
        packet: HandDrawingRealtimeDraftPacket?
    ) -> HandDrawingRealtimeDraftRenderOutput
}

final class HandDrawingCPURealtimeBrushRenderer: HandDrawingRealtimeBrushRenderer {
    private let accumulator = HandDrawingRealtimeDraftPacketAccumulator()

    func apply(
        packet: HandDrawingRealtimeDraftPacket?
    ) -> HandDrawingRealtimeDraftRenderOutput {
        guard let renderState = accumulator.apply(packet: packet) else {
            return .none
        }
        return .resolved(renderState)
    }
}

enum HandDrawingCommittedCanvasRenderOutput {
    case none
    case bitmap(CGImage)

    var image: CGImage? {
        switch self {
        case .none:
            return nil
        case let .bitmap(image):
            return image
        }
    }
}

protocol HandDrawingCommittedCanvasBackend {
    func render(
        document: HandDrawingDocument,
        dirtyRegion: CGRect?
    ) throws -> HandDrawingCommittedCanvasRenderOutput
}

final class HandDrawingCPUCommittedCanvasBackend: HandDrawingCommittedCanvasBackend {
    private let canvasRenderer: HandDrawingCanvasRenderer

    init(
        paperSize: CGSize,
        backgroundColor: HandDrawingColor? = nil
    ) throws {
        canvasRenderer = try HandDrawingCanvasRenderer(
            paperSize: paperSize,
            backgroundColor: backgroundColor
        )
    }

    func render(
        document: HandDrawingDocument,
        dirtyRegion: CGRect?
    ) throws -> HandDrawingCommittedCanvasRenderOutput {
        .bitmap(
            try canvasRenderer.render(
                document: document,
                dirtyRegion: dirtyRegion
            )
        )
    }
}
