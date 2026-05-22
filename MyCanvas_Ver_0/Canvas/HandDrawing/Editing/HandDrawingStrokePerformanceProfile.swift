import CoreGraphics
import Foundation

struct HandDrawingLiveInputConfiguration: Equatable {
    static let interactiveDraft = HandDrawingLiveInputConfiguration()

    let includesPredictedTouches: Bool
    let maximumPredictedSampleCount: Int

    init(
        includesPredictedTouches: Bool = false,
        maximumPredictedSampleCount: Int = 2
    ) {
        self.includesPredictedTouches = includesPredictedTouches
        self.maximumPredictedSampleCount = max(maximumPredictedSampleCount, 0)
    }
}

struct HandDrawingStrokePerformanceProfile: Equatable {
    let inputNormalization: HandDrawingInputNormalizer.Configuration
    let stampLayout: HandDrawingResolvedStampLayout
    let dirtyRegionPadding: CGFloat

    static func brushStroke(
        for brush: HandDrawingBrushStyle
    ) -> HandDrawingStrokePerformanceProfile {
        let baseSize = max(CGFloat(brush.baseSize), 0.25)
        return HandDrawingStrokePerformanceProfile(
            inputNormalization: HandDrawingInputNormalizer.Configuration(
                minimumSampleDistance: min(max(baseSize * 0.1, 0.5), 2),
                minimumTimestampDelta: 0.0001,
                minimumForce: 0.05,
                maximumForce: 1
            ),
            stampLayout: HandDrawingResolvedStampLayout(
                relativeSpacingFactor: 0.5,
                minimumSpacing: min(max(baseSize * 0.08, 0.5), 1.5)
            ),
            dirtyRegionPadding: min(max(baseSize * 0.2, 2), 6)
        )
    }
}
