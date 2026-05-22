import CoreGraphics
import Foundation

enum HandDrawingCanonicalModelTruthSource: String, CaseIterable, Equatable {
    case documentModel
    case bitmapTiles
    case gpuFramebuffer
}

enum HandDrawingPreviewGoldenPath: String, CaseIterable, Equatable {
    case cpuPreviewRenderer
    case gpuFramebuffer
    case persistedBitmap
}

enum HandDrawingToolGraphSemanticSource: String, CaseIterable, Equatable {
    case vectorRenderGraphSnapshots
    case bitmapMask
}

enum HandDrawingSchemeTwoBoundaryRegression: String, CaseIterable, Hashable {
    case documentHistoryPersistenceTruth
    case cpuPreviewGoldenPath
    case vectorToolGraph
}

enum HandDrawingSchemeTwoHardeningReason: String, CaseIterable, Hashable {
    case realtimeDraftPerformance
    case largeCanvasValidationCoverage
}

enum HandDrawingSchemeThreeInvestigationReason: String, CaseIterable, Hashable {
    case committedCanvasPerformance
    case previewPipelinePerformance
    case toolGraphPerformance
}

enum HandDrawingSchemeThreeDecision: Equatable {
    case stayOnSchemeTwo
    case continueSchemeTwoHardening(reasons: Set<HandDrawingSchemeTwoHardeningReason>)
    case openSchemeThreePlan(reasons: Set<HandDrawingSchemeThreeInvestigationReason>)
    case blockedByBoundaryRegression(regressions: Set<HandDrawingSchemeTwoBoundaryRegression>)
}

enum HandDrawingToolSemanticDomain: String, CaseIterable, Hashable {
    case lasso
    case pixelEraser
    case moveSelection
}

struct HandDrawingSchemeTwoBoundaryAudit: Equatable {
    let historyTruthSource: HandDrawingCanonicalModelTruthSource
    let persistenceTruthSource: HandDrawingCanonicalModelTruthSource
    let canonicalPreviewTruthSource: HandDrawingPreviewGoldenPath
    let parityJudgeTruthSource: HandDrawingPreviewGoldenPath
    let toolTruthSources: [HandDrawingToolSemanticDomain: HandDrawingToolGraphSemanticSource]

    var regressions: Set<HandDrawingSchemeTwoBoundaryRegression> {
        var regressions: Set<HandDrawingSchemeTwoBoundaryRegression> = []
        if historyTruthSource != .documentModel || persistenceTruthSource != .documentModel {
            regressions.insert(.documentHistoryPersistenceTruth)
        }
        if canonicalPreviewTruthSource != .cpuPreviewRenderer
            || parityJudgeTruthSource != .cpuPreviewRenderer
        {
            regressions.insert(.cpuPreviewGoldenPath)
        }
        let expectedToolTruthSource = HandDrawingToolGraphSemanticSource.vectorRenderGraphSnapshots
        if toolTruthSources.values.contains(where: { $0 != expectedToolTruthSource }) {
            regressions.insert(.vectorToolGraph)
        }
        return regressions
    }

    var preservesPublishableSchemeTwoBoundary: Bool {
        regressions.isEmpty
    }
}

struct HandDrawingSchemeTwoCapabilitySnapshot: Equatable {
    let supportedRealtimeDraftBackends: Set<HandDrawingRealtimeDraftBackendPreference>
    let supportedCommittedCanvasBackends: Set<HandDrawingCommittedCanvasBackendPreference>
    let canonicalPreviewTruthSource: HandDrawingPreviewGoldenPath

    var hasGpuRealtimeDraftPath: Bool {
        supportedRealtimeDraftBackends.contains(.gpuPreferred)
    }

    var hasReplaceableCommittedBackend: Bool {
        supportedCommittedCanvasBackends.contains(.gpuPrototype)
    }
}

struct HandDrawingSchemeThreeDecisionMeasurements: Equatable {
    let realtimeDraftP95FrameDurationMS: Double
    let committedCanvasP95FrameDurationMS: Double
    let previewPipelineP95DurationMS: Double
    let toolGraphP95DurationMS: Double
    let validatedLargestCanvasSize: CGSize

    init(
        realtimeDraftP95FrameDurationMS: Double,
        committedCanvasP95FrameDurationMS: Double,
        previewPipelineP95DurationMS: Double,
        toolGraphP95DurationMS: Double,
        validatedLargestCanvasSize: CGSize
    ) {
        self.realtimeDraftP95FrameDurationMS = max(realtimeDraftP95FrameDurationMS, 0)
        self.committedCanvasP95FrameDurationMS = max(committedCanvasP95FrameDurationMS, 0)
        self.previewPipelineP95DurationMS = max(previewPipelineP95DurationMS, 0)
        self.toolGraphP95DurationMS = max(toolGraphP95DurationMS, 0)
        self.validatedLargestCanvasSize = CGSize(
            width: max(validatedLargestCanvasSize.width, 0),
            height: max(validatedLargestCanvasSize.height, 0)
        )
    }

    var validatedLargestCanvasLongestEdge: CGFloat {
        max(validatedLargestCanvasSize.width, validatedLargestCanvasSize.height)
    }
}

struct HandDrawingSchemeThreeDecisionThresholds: Equatable {
    let interactionFrameBudgetMS: Double
    let previewPipelineBudgetMS: Double
    let toolGraphBudgetMS: Double
    let minimumValidatedCanvasLongestEdge: CGFloat

    static let schemeTwoReleaseDefault = HandDrawingSchemeThreeDecisionThresholds(
        interactionFrameBudgetMS: 16.7,
        previewPipelineBudgetMS: 120,
        toolGraphBudgetMS: 8,
        minimumValidatedCanvasLongestEdge: 4096
    )

    init(
        interactionFrameBudgetMS: Double,
        previewPipelineBudgetMS: Double,
        toolGraphBudgetMS: Double,
        minimumValidatedCanvasLongestEdge: CGFloat
    ) {
        self.interactionFrameBudgetMS = max(interactionFrameBudgetMS, 0.1)
        self.previewPipelineBudgetMS = max(previewPipelineBudgetMS, 0.1)
        self.toolGraphBudgetMS = max(toolGraphBudgetMS, 0.1)
        self.minimumValidatedCanvasLongestEdge = max(minimumValidatedCanvasLongestEdge, 1)
    }
}

struct HandDrawingSchemeTwoReleaseAssessment: Equatable {
    let boundaryAudit: HandDrawingSchemeTwoBoundaryAudit
    let capabilitySnapshot: HandDrawingSchemeTwoCapabilitySnapshot
    let measurements: HandDrawingSchemeThreeDecisionMeasurements
    let thresholds: HandDrawingSchemeThreeDecisionThresholds
    let decision: HandDrawingSchemeThreeDecision

    var isSchemeTwoReleaseReady: Bool {
        decision == .stayOnSchemeTwo
    }
}

enum HandDrawingSchemeTwoReleaseGate {
    static func currentBoundaryAudit() -> HandDrawingSchemeTwoBoundaryAudit {
        HandDrawingSchemeTwoBoundaryAudit(
            historyTruthSource: HandDrawingHistoryController.schemeTwoTruthSource,
            persistenceTruthSource: HandDrawingDocumentStore.schemeTwoTruthSource,
            canonicalPreviewTruthSource: HandDrawingPreviewRenderer.schemeTwoTruthSource,
            parityJudgeTruthSource: HandDrawingPreviewRenderer.schemeTwoParityJudge,
            toolTruthSources: [
                .lasso: HandDrawingLassoToolController.schemeTwoTruthSource,
                .pixelEraser: HandDrawingPixelEraserToolController.schemeTwoTruthSource,
                .moveSelection: HandDrawingMoveSelectionController.schemeTwoTruthSource
            ]
        )
    }

    static func currentCapabilitySnapshot() -> HandDrawingSchemeTwoCapabilitySnapshot {
        HandDrawingSchemeTwoCapabilitySnapshot(
            supportedRealtimeDraftBackends: [.cpu, .gpuPreferred],
            supportedCommittedCanvasBackends: [.cpu, .gpuPrototype],
            canonicalPreviewTruthSource: HandDrawingPreviewRenderer.schemeTwoTruthSource
        )
    }

    static func assess(
        measurements: HandDrawingSchemeThreeDecisionMeasurements,
        thresholds: HandDrawingSchemeThreeDecisionThresholds = .schemeTwoReleaseDefault
    ) -> HandDrawingSchemeTwoReleaseAssessment {
        assess(
            boundaryAudit: currentBoundaryAudit(),
            capabilitySnapshot: currentCapabilitySnapshot(),
            measurements: measurements,
            thresholds: thresholds
        )
    }

    static func assess(
        boundaryAudit: HandDrawingSchemeTwoBoundaryAudit,
        capabilitySnapshot: HandDrawingSchemeTwoCapabilitySnapshot = currentCapabilitySnapshot(),
        measurements: HandDrawingSchemeThreeDecisionMeasurements,
        thresholds: HandDrawingSchemeThreeDecisionThresholds = .schemeTwoReleaseDefault
    ) -> HandDrawingSchemeTwoReleaseAssessment {
        let decision = resolveDecision(
            boundaryAudit: boundaryAudit,
            measurements: measurements,
            thresholds: thresholds
        )
        return HandDrawingSchemeTwoReleaseAssessment(
            boundaryAudit: boundaryAudit,
            capabilitySnapshot: capabilitySnapshot,
            measurements: measurements,
            thresholds: thresholds,
            decision: decision
        )
    }

    private static func resolveDecision(
        boundaryAudit: HandDrawingSchemeTwoBoundaryAudit,
        measurements: HandDrawingSchemeThreeDecisionMeasurements,
        thresholds: HandDrawingSchemeThreeDecisionThresholds
    ) -> HandDrawingSchemeThreeDecision {
        let regressions = boundaryAudit.regressions
        guard regressions.isEmpty else {
            return .blockedByBoundaryRegression(regressions: regressions)
        }

        var hardeningReasons: Set<HandDrawingSchemeTwoHardeningReason> = []
        if measurements.realtimeDraftP95FrameDurationMS > thresholds.interactionFrameBudgetMS {
            hardeningReasons.insert(.realtimeDraftPerformance)
        }
        if
            measurements.validatedLargestCanvasLongestEdge
                < thresholds.minimumValidatedCanvasLongestEdge
        {
            hardeningReasons.insert(.largeCanvasValidationCoverage)
        }
        if hardeningReasons.isEmpty == false {
            return .continueSchemeTwoHardening(reasons: hardeningReasons)
        }

        var investigationReasons: Set<HandDrawingSchemeThreeInvestigationReason> = []
        if measurements.committedCanvasP95FrameDurationMS > thresholds.interactionFrameBudgetMS {
            investigationReasons.insert(.committedCanvasPerformance)
        }
        if measurements.previewPipelineP95DurationMS > thresholds.previewPipelineBudgetMS {
            investigationReasons.insert(.previewPipelinePerformance)
        }
        if measurements.toolGraphP95DurationMS > thresholds.toolGraphBudgetMS {
            investigationReasons.insert(.toolGraphPerformance)
        }
        if investigationReasons.isEmpty == false {
            return .openSchemeThreePlan(reasons: investigationReasons)
        }

        return .stayOnSchemeTwo
    }
}

extension HandDrawingHistoryController {
    static let schemeTwoTruthSource: HandDrawingCanonicalModelTruthSource = .documentModel
}

extension HandDrawingDocumentStore {
    static let schemeTwoTruthSource: HandDrawingCanonicalModelTruthSource = .documentModel
}

extension HandDrawingPreviewRenderer {
    static let schemeTwoTruthSource: HandDrawingPreviewGoldenPath = .cpuPreviewRenderer
    static let schemeTwoParityJudge: HandDrawingPreviewGoldenPath = .cpuPreviewRenderer
}

extension HandDrawingStrokeGeometry {
    static let schemeTwoTruthSource: HandDrawingToolGraphSemanticSource = .vectorRenderGraphSnapshots
}

extension HandDrawingLassoToolController {
    static let schemeTwoTruthSource: HandDrawingToolGraphSemanticSource = .vectorRenderGraphSnapshots
}

extension HandDrawingPixelEraserToolController {
    static let schemeTwoTruthSource: HandDrawingToolGraphSemanticSource = .vectorRenderGraphSnapshots
}

extension HandDrawingMoveSelectionController {
    static let schemeTwoTruthSource: HandDrawingToolGraphSemanticSource = .vectorRenderGraphSnapshots
}
