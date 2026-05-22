# 20260522_152939_CST_hand_drawing_scheme2_phase7_release_gate_record

## 记录范围

- 记录内容：
  - 实施手绘方案二升级计划中的 `phase 7`，把方案二的发布边界与“是否进入方案三”的决策门槛正式收口成代码。
  - 新增 `HandDrawingSchemeTwoReleaseGate.swift`，集中表达：
    - `document / history / persistence` 的真相源边界
    - `preview parity` 的 CPU golden path
    - `lasso / pixel eraser / move selection` 的向量语义边界
    - 进入方案三前的性能 / 覆盖度判据
  - 新增 `HandDrawingSchemeTwoReleaseGateTests.swift`，覆盖 stay / hardening / open / blocked 四类决策路径。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingSchemeTwoReleaseGate.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingSchemeTwoReleaseGateTests.swift`
- 如实说明：
  - 本轮 `phase 7` 对应的 current changes 只有上面两个新增未跟踪文件。
  - 由于文件尚未加入索引，常规 `git diff -- <path>` 不会给出正文差异；因此下面用 `git status --short` 记录 current changes，并用 `git diff --no-index --stat -- /dev/null <file>` 记录新增规模。
  - 当前工作区还存在其他与本轮任务无关的修改，本记录不展开，只按路径过滤聚焦 `phase 7` 文件。
- 本记录不包含：
  - 任何提交操作。
  - 把 release gate 接到真实 runtime profiling 采样入口。
  - 将方案二的 CPU truth 切换为 GPU / bitmap truth。

## 命名与当前 changes 证据

```sh
# 文件路径: 无（终端命令）
# 函数名: date +"%Y%m%d_%H%M%S_CST_hand_drawing_scheme2_phase7_release_gate_record"
# 功能说明: 使用系统自带 date 命令生成本次 phase 7 记录文件的时间戳前缀。
20260522_152939_CST_hand_drawing_scheme2_phase7_release_gate_record
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short -- MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingSchemeTwoReleaseGate.swift MyCanvas_Ver_0Tests/HandDrawingSchemeTwoReleaseGateTests.swift
# 功能说明: 按路径过滤 current changes，确认本轮 phase 7 只新增了 release gate 主文件与对应测试文件。
?? MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingSchemeTwoReleaseGate.swift
?? MyCanvas_Ver_0Tests/HandDrawingSchemeTwoReleaseGateTests.swift
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --no-index --stat -- /dev/null MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingSchemeTwoReleaseGate.swift
# 功能说明: 因为主文件当前还是 untracked，所以使用 /dev/null 对比记录新增规模，而不贴原始 diff。
.../Core/HandDrawingSchemeTwoReleaseGate.swift     | 285 +++++++++++++++++++++
1 file changed, 285 insertions(+)
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --no-index --stat -- /dev/null MyCanvas_Ver_0Tests/HandDrawingSchemeTwoReleaseGateTests.swift
# 功能说明: 因为测试文件当前还是 untracked，所以使用 /dev/null 对比记录新增规模，而不贴原始 diff。
.../HandDrawingSchemeTwoReleaseGateTests.swift     | 129 +++++++++++++++++++++
1 file changed, 129 insertions(+)
```

## 当前 changes 摘要

- 新增 `HandDrawingSchemeTwoReleaseGate.swift`，首次把方案二收口需要守住的三条系统边界变成代码里的显式合同，而不是只存在于计划文字中。
- 新增 `HandDrawingSchemeThreeDecisionMeasurements` 与 `HandDrawingSchemeThreeDecisionThresholds`，把“是否继续留在方案二 / 是否应该单开方案三计划”变成明确输入与明确阈值。
- 新增 `HandDrawingSchemeThreeDecision` 四类结果：
  - `stayOnSchemeTwo`
  - `continueSchemeTwoHardening`
  - `openSchemeThreePlan`
  - `blockedByBoundaryRegression`
- 在现有组件上通过 extension 显式挂出方案二 truth source / parity judge / tool semantic source，避免后续边界悄悄漂移却没有集中审查点。
- 新增 `HandDrawingSchemeTwoReleaseGateTests.swift`，覆盖当前边界合同与四种决策分支，确保 phase 7 不是“只加结构不加护栏”。

## 修改一：新增方案二收口与 go/no-go Release Gate

### 修改前

- 项目里不存在专门的 `scheme two release gate` 文件。
- 方案二的边界虽然已经在前几个 phase 里逐步实现出来，但还没有集中代码能回答下面这些问题：
  - `history / persistence` 是否仍然是 document truth
  - `preview parity` 是否仍由 CPU preview 裁决
  - tool graph 是否仍然使用向量语义
  - 指标满足什么条件时停在方案二，什么条件下才应该单开方案三计划

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingSchemeTwoReleaseGate.swift（修改前）
// 函数名: 无
// 功能说明: phase 7 之前项目中不存在统一的方案二收口 / 方案三决策门槛文件。
// 本文件不存在。
```

### 修改后

- 新增一组枚举和审查模型，把边界问题拆成可组合、可测试的领域对象。
- `HandDrawingSchemeTwoBoundaryAudit.regressions` 会直接输出三类边界回退：
  - `documentHistoryPersistenceTruth`
  - `cpuPreviewGoldenPath`
  - `vectorToolGraph`
- `currentBoundaryAudit()` 负责从现有 hand drawing 组件采集当前边界声明，形成统一审查快照。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingSchemeTwoReleaseGate.swift
// 函数名: HandDrawingSchemeTwoBoundaryAudit.regressions / HandDrawingSchemeTwoReleaseGate.currentBoundaryAudit()
// 功能说明: 把方案二发布边界收口成显式审查模型，并从已有组件聚合出当前 truth source / parity judge / tool semantics。
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
}
```

- 新增能力快照、测量输入、阈值和最终评估结果，正式表达“什么时候留在方案二，什么时候该开方案三计划”。
- `assess(...)` 先守边界，再判 realtime 与大画布覆盖度是否还需继续打磨方案二，最后才判 committed / preview / tool graph 是否已经形成方案三级别瓶颈。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingSchemeTwoReleaseGate.swift
// 函数名: HandDrawingSchemeTwoReleaseGate.assess(...) / HandDrawingSchemeTwoReleaseGate.resolveDecision(...)
// 功能说明: 用统一测量输入和阈值输出 go/no-go 结论；先阻断边界回退，再区分“继续打磨方案二”与“单开方案三计划”。
struct HandDrawingSchemeThreeDecisionMeasurements: Equatable {
    let realtimeDraftP95FrameDurationMS: Double
    let committedCanvasP95FrameDurationMS: Double
    let previewPipelineP95DurationMS: Double
    let toolGraphP95DurationMS: Double
    let validatedLargestCanvasSize: CGSize
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
}

enum HandDrawingSchemeThreeDecision: Equatable {
    case stayOnSchemeTwo
    case continueSchemeTwoHardening(reasons: Set<HandDrawingSchemeTwoHardeningReason>)
    case openSchemeThreePlan(reasons: Set<HandDrawingSchemeThreeInvestigationReason>)
    case blockedByBoundaryRegression(regressions: Set<HandDrawingSchemeTwoBoundaryRegression>)
}

enum HandDrawingSchemeTwoReleaseGate {
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
        if measurements.validatedLargestCanvasLongestEdge < thresholds.minimumValidatedCanvasLongestEdge {
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
```

- 新增一组 extension，把现有组件在方案二下的边界声明显式挂出来。
- 这一步的意义不是新增功能，而是避免“边界只靠人记住”，以后如果有人把 preview 或 tool graph 真相偷偷切走，会先在 release gate 审查处暴露出来。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingSchemeTwoReleaseGate.swift
// 函数名: HandDrawingHistoryController.schemeTwoTruthSource / HandDrawingDocumentStore.schemeTwoTruthSource / HandDrawingPreviewRenderer.schemeTwoTruthSource / HandDrawingLassoToolController.schemeTwoTruthSource
// 功能说明: 把现有 hand drawing 组件在方案二下的 truth source / parity judge / tool semantic source 显式挂到类型上，作为 release gate 的统一采样入口。
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

extension HandDrawingLassoToolController {
    static let schemeTwoTruthSource: HandDrawingToolGraphSemanticSource = .vectorRenderGraphSnapshots
}

extension HandDrawingPixelEraserToolController {
    static let schemeTwoTruthSource: HandDrawingToolGraphSemanticSource = .vectorRenderGraphSnapshots
}

extension HandDrawingMoveSelectionController {
    static let schemeTwoTruthSource: HandDrawingToolGraphSemanticSource = .vectorRenderGraphSnapshots
}
```

## 修改二：新增 Release Gate 回归测试

### 修改前

- 项目里不存在专门验证 `phase 7 release gate` 的测试文件。
- 也不存在专门断言下面四类决策路径的单元测试：
  - 保持在方案二
  - 继续打磨方案二
  - 单开方案三计划
  - 因边界回退而阻断发布

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingSchemeTwoReleaseGateTests.swift（修改前）
// 函数名: 无
// 功能说明: phase 7 之前项目中不存在 release gate 的专用测试文件。
// 本文件不存在。
```

### 修改后

- 新增 `HandDrawingSchemeTwoReleaseGateTests`。
- 第一类测试直接校验“当前工程状态下的边界合同”是否成立。
- 后续测试分别校验：
  - 指标达标时停在方案二
  - realtime / 大画布覆盖度不足时继续打磨方案二
  - committed / preview / tool graph 成为瓶颈时开启方案三计划
  - truth source 回退时直接阻断发布

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingSchemeTwoReleaseGateTests.swift
// 函数名: testCurrentBoundaryAuditPreservesSchemeTwoTruthContracts() / testAssessStaysOnSchemeTwoWhenMetricsFitReleaseThresholds()
// 功能说明: 验证当前代码状态仍然守住方案二的系统边界，并在指标达标时给出 stayOnSchemeTwo 结论。
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
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingSchemeTwoReleaseGateTests.swift
// 函数名: testAssessRequestsMoreSchemeTwoHardeningWhenRealtimeOrLargeCanvasGateFails() / testAssessOpensSchemeThreePlanWhenCommittedPreviewAndToolGraphAreBottlenecks() / testAssessBlocksReleaseWhenBoundaryAuditRegressesTruthSources()
// 功能说明: 下面片段摘自同一个 XCTestCase 内部的方法实现，分别验证“继续打磨方案二”“单开方案三计划”“边界回退直接阻断发布”三类分支。
func testAssessRequestsMoreSchemeTwoHardeningWhenRealtimeOrLargeCanvasGateFails() {
    let assessment = HandDrawingSchemeTwoReleaseGate.assess(
        measurements: HandDrawingSchemeThreeDecisionMeasurements(
            realtimeDraftP95FrameDurationMS: 19.6,
            committedCanvasP95FrameDurationMS: 12,
            previewPipelineP95DurationMS: 80,
            toolGraphP95DurationMS: 4,
            validatedLargestCanvasSize: CGSize(width: 2048, height: 1536)
        )
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
}
```

## 验证记录

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/HandDrawingSchemeTwoReleaseGateTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingRenderGraphTests
# 功能说明: 验证 phase 7 新增 release gate 与已有 hand drawing 渲染契约 / render graph 测试共同通过，没有引入回归。
** TEST SUCCEEDED **

Test case 'HandDrawingSchemeTwoReleaseGateTests.testAssessBlocksReleaseWhenBoundaryAuditRegressesTruthSources()' passed
Test case 'HandDrawingSchemeTwoReleaseGateTests.testAssessOpensSchemeThreePlanWhenCommittedPreviewAndToolGraphAreBottlenecks()' passed
Test case 'HandDrawingSchemeTwoReleaseGateTests.testAssessRequestsMoreSchemeTwoHardeningWhenRealtimeOrLargeCanvasGateFails()' passed
Test case 'HandDrawingSchemeTwoReleaseGateTests.testAssessStaysOnSchemeTwoWhenMetricsFitReleaseThresholds()' passed
Test case 'HandDrawingSchemeTwoReleaseGateTests.testCurrentBoundaryAuditPreservesSchemeTwoTruthContracts()' passed
Test case 'HandDrawingRenderingContractsTests.testHandDrawingCommittedCanvasRenderRequestClipsDirtyRegionToIntegralPaperBounds()' passed
Test case 'HandDrawingRenderingContractsTests.testHandDrawingCommittedCanvasRenderRequestTreatsNilDirtyRegionAsFullRedraw()' passed
Test case 'HandDrawingRenderingContractsTests.testHandDrawingRealtimeDraftPacketCarriesCommittedTailAndPredictedTailSeparately()' passed
Test case 'HandDrawingRenderingContractsTests.testHandDrawingRealtimeDraftRenderStateExposesRenderSnapshotsForCommittedAndPredictedSegments()' passed
Test case 'HandDrawingRenderGraphTests.testHandDrawingRenderGraphBuilderPreservesVisibleLayerOrderAndFiltersSnapshotsByRenderRegion()' passed
Test case 'HandDrawingRenderGraphTests.testHandDrawingRenderGraphBuilderResolvesEraseMaskIntoDocumentSpace()' passed
```

## 结果

- `phase 7` 的修改已经如实记录到 `commit_records/20260522_152939_CST_hand_drawing_scheme2_phase7_release_gate_record.md`。
- 本次记录反映的是：
  - 方案二的系统边界已被收口成可审查、可测试的代码合同
  - 是否进入方案三已有明确技术判据
  - 当前实现仍然守住 `CPU/document truth`，没有越界切到 GPU / bitmap 真相
