import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

final class HandDrawingSchemeTwoReleaseGateTests: XCTestCase {
    func testCurrentBoundaryAuditPreservesSchemeTwoTruthContracts() {
        let audit = HandDrawingSchemeTwoReleaseGate.currentBoundaryAudit()
        let capabilitySnapshot = HandDrawingSchemeTwoReleaseGate.currentCapabilitySnapshot()

        XCTAssertTrue(audit.preservesPublishableSchemeTwoBoundary)
        XCTAssertEqual(audit.historyTruthSource, .documentModel)
        XCTAssertEqual(audit.persistenceTruthSource, .documentModel)
        XCTAssertEqual(audit.canonicalPreviewTruthSource, .cpuPreviewRenderer)
        XCTAssertEqual(audit.parityJudgeTruthSource, .cpuPreviewRenderer)
        XCTAssertEqual(
            audit.toolTruthSources,
            [
                .lasso: .vectorRenderGraphSnapshots,
                .pixelEraser: .vectorRenderGraphSnapshots,
                .moveSelection: .vectorRenderGraphSnapshots
            ]
        )
        XCTAssertTrue(capabilitySnapshot.hasGpuRealtimeDraftPath)
        XCTAssertTrue(capabilitySnapshot.hasReplaceableCommittedBackend)
    }

    func testAssessStaysOnSchemeTwoWhenMetricsFitReleaseThresholds() {
        let assessment = HandDrawingSchemeTwoReleaseGate.assess(
            measurements: HandDrawingSchemeThreeDecisionMeasurements(
                realtimeDraftP95FrameDurationMS: 9.4,
                committedCanvasP95FrameDurationMS: 12.8,
                previewPipelineP95DurationMS: 64,
                toolGraphP95DurationMS: 3.5,
                validatedLargestCanvasSize: CGSize(width: 4096, height: 3072)
            )
        )

        XCTAssertTrue(assessment.isSchemeTwoReleaseReady)
        XCTAssertEqual(assessment.decision, .stayOnSchemeTwo)
    }

    func testAssessRequestsMoreSchemeTwoHardeningWhenRealtimeOrLargeCanvasGateFails() {
        let thresholds = HandDrawingSchemeThreeDecisionThresholds(
            interactionFrameBudgetMS: 16.7,
            previewPipelineBudgetMS: 120,
            toolGraphBudgetMS: 8,
            minimumValidatedCanvasLongestEdge: 4096
        )
        let assessment = HandDrawingSchemeTwoReleaseGate.assess(
            measurements: HandDrawingSchemeThreeDecisionMeasurements(
                realtimeDraftP95FrameDurationMS: 19.6,
                committedCanvasP95FrameDurationMS: 12,
                previewPipelineP95DurationMS: 80,
                toolGraphP95DurationMS: 4,
                validatedLargestCanvasSize: CGSize(width: 2048, height: 1536)
            ),
            thresholds: thresholds
        )

        XCTAssertEqual(
            assessment.decision,
            .continueSchemeTwoHardening(
                reasons: [
                    .realtimeDraftPerformance,
                    .largeCanvasValidationCoverage
                ]
            )
        )
    }

    func testAssessOpensSchemeThreePlanWhenCommittedPreviewAndToolGraphAreBottlenecks() {
        let assessment = HandDrawingSchemeTwoReleaseGate.assess(
            measurements: HandDrawingSchemeThreeDecisionMeasurements(
                realtimeDraftP95FrameDurationMS: 10.2,
                committedCanvasP95FrameDurationMS: 24.1,
                previewPipelineP95DurationMS: 148,
                toolGraphP95DurationMS: 11.4,
                validatedLargestCanvasSize: CGSize(width: 6144, height: 4096)
            )
        )

        XCTAssertEqual(
            assessment.decision,
            .openSchemeThreePlan(
                reasons: [
                    .committedCanvasPerformance,
                    .previewPipelinePerformance,
                    .toolGraphPerformance
                ]
            )
        )
    }

    func testAssessBlocksReleaseWhenBoundaryAuditRegressesTruthSources() {
        let regressedAudit = HandDrawingSchemeTwoBoundaryAudit(
            historyTruthSource: .bitmapTiles,
            persistenceTruthSource: .documentModel,
            canonicalPreviewTruthSource: .gpuFramebuffer,
            parityJudgeTruthSource: .gpuFramebuffer,
            toolTruthSources: [
                .lasso: .vectorRenderGraphSnapshots,
                .pixelEraser: .bitmapMask,
                .moveSelection: .vectorRenderGraphSnapshots
            ]
        )
        let assessment = HandDrawingSchemeTwoReleaseGate.assess(
            boundaryAudit: regressedAudit,
            measurements: HandDrawingSchemeThreeDecisionMeasurements(
                realtimeDraftP95FrameDurationMS: 8,
                committedCanvasP95FrameDurationMS: 8,
                previewPipelineP95DurationMS: 40,
                toolGraphP95DurationMS: 2,
                validatedLargestCanvasSize: CGSize(width: 4096, height: 4096)
            )
        )

        XCTAssertEqual(
            assessment.decision,
            .blockedByBoundaryRegression(
                regressions: [
                    .documentHistoryPersistenceTruth,
                    .cpuPreviewGoldenPath,
                    .vectorToolGraph
                ]
            )
        )
        XCTAssertFalse(assessment.boundaryAudit.preservesPublishableSchemeTwoBoundary)
    }
}
