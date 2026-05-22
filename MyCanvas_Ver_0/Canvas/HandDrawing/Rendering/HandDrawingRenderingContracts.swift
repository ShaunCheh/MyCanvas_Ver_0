import CoreGraphics
import Foundation

struct HandDrawingRealtimeDraftPacket: Equatable {
    let brush: HandDrawingBrushStyle
    let performanceProfile: HandDrawingStrokePerformanceProfile
    let normalizedSamples: [HandDrawingInputSample]
    let draftStroke: HandDrawingStroke
    let resolvedStamps: [HandDrawingResolvedBrushSample]
}

enum HandDrawingRealtimeDraftRenderOutput {
    case none
    case stroke(HandDrawingStroke)

    var stroke: HandDrawingStroke? {
        switch self {
        case .none:
            return nil
        case let .stroke(stroke):
            return stroke
        }
    }
}

protocol HandDrawingRealtimeBrushRenderer {
    func render(
        packet: HandDrawingRealtimeDraftPacket?
    ) -> HandDrawingRealtimeDraftRenderOutput
}

struct HandDrawingCPURealtimeBrushRenderer: HandDrawingRealtimeBrushRenderer {
    func render(
        packet: HandDrawingRealtimeDraftPacket?
    ) -> HandDrawingRealtimeDraftRenderOutput {
        guard let packet else {
            return .none
        }
        return .stroke(packet.draftStroke)
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
