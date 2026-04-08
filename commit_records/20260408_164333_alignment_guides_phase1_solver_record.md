# 20260408_164333_alignment_guides_phase1_solver_record

## 记录范围

- 记录内容：
  1. 为“图片拖动对齐辅助线”实现 `Phase 1` 共享 solver 的真实求解逻辑，不再停留在 `passthrough` 占位。
  2. 新增 `CanvasAlignmentGuideSolverTests.swift`，用定向单测覆盖吸附、候选冲突、缩放阈值、旋转语义与 board 参考线。
  3. 在测试层补上与项目现有测试模式一致的生命周期保护，避免 `CanvasScene` 在 XCTest 内存检查阶段提前释放导致崩溃。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasAlignmentGuideSolver.swift`
  - `MyCanvas_Ver_0Tests/CanvasAlignmentGuideSolverTests.swift`
- 当前 changes 依据：
  - `git status --short` 当前仅显示两项变化：
    - `M MyCanvas_Ver_0/Canvas/Core/CanvasAlignmentGuideSolver.swift`
    - `?? MyCanvas_Ver_0Tests/CanvasAlignmentGuideSolverTests.swift`
  - `git diff -- MyCanvas_Ver_0/Canvas/Core/CanvasAlignmentGuideSolver.swift` 显示：solver 从 `passthrough` 占位实现扩展为完整的候选搜索、阈值换算、最优候选判定和 guide 生成。
  - `CanvasAlignmentGuideSolverTests.swift` 当前是新增未跟踪文件，因此普通 `git diff` 不会展示其内容；本记录对该文件的描述直接依据当前工作区文件内容。
  - 当前 `git status` 中已经不包含 `Phase 0` 的契约层文件，因此本记录只覆盖本次 `Phase 1` 的 solver 与测试改动，不追溯此前已不在当前 changes 中的内容。
- 验证依据：
  - `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=macOS" test -only-testing:MyCanvas_Ver_0Tests/CanvasAlignmentGuideSolverTests`
  - `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=macOS" build`
  - `ReadLints` 对本次修改文件未报告新增问题。
- 本记录不包含：
  - `Phase 2` 的 `CanvasEditorSession` / `CanvasRenderer` 接线
  - `Phase 3` / `Phase 4` 的 iOS/macOS 控制器接入
  - `Phase 5` 的 viewport 辅助线渲染
  - git commit / push

## 修改一：共享 solver 从占位实现变为真实求解器

### 修改前

- `CanvasAlignmentGuideSolver.solve(_:)` 只是简单返回 `passthrough`，不会做任何候选搜索、阈值判定、中心修正或辅助线生成。
- 这意味着即便 `Phase 0` 已经把 contract 落了下来，当前共享层仍然没有任何“吸附求解”能力。
- 按当前 `git diff` 可以明确看到，修改前 `solve(_:)` 的主体只有一行 `CanvasAlignmentSolveResult.passthrough(...)`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasAlignmentGuideSolver.swift
// 函数名: CanvasAlignmentGuideSolver.solve(_:)
// 功能说明: 修改前 solver 只有占位返回；输入 request 后直接透传 proposedCenter，不做对齐参考搜索、阈值换算、候选比较，也不会产出 interactionState。
struct CanvasAlignmentGuideSolver {
    var configuration: CanvasAlignmentSolverConfiguration = .default

    func solve(
        _ request: CanvasAlignmentSolveRequest
    ) -> CanvasAlignmentSolveResult {
        CanvasAlignmentSolveResult.passthrough(
            proposedCenter: request.proposedCenter
        )
    }
}
```

### 修改后

- `solve(_:)` 现在已经实现完整的 `Phase 1` 共享求解流程：
  - 先拿到被拖拽项的 `worldFrame`
  - 基于 viewport 是否可用决定搜索范围
  - 在 `scene.visibleBoardItems(in:)` 内收集 item 参考项，并可选追加 board 参考项
  - 按 `x` / `y` 两轴分别计算最佳候选
  - 用“屏幕阈值 -> world 阈值”的换算控制命中
  - 生成修正后的 `resolvedCenter`
  - 同时构造 `guides` 和 `CanvasAlignmentInteractionState`
- 第一版求解语义依然严格保持在计划里定义的边界内：
  - 只做 `left/centerX/right` 与 `top/centerY/bottom`
  - 参考项统一基于 `worldFrame`
  - 不用旋转后的 `worldBounds` / 斜边做精确边对齐

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasAlignmentGuideSolver.swift
// 函数名: CanvasAlignmentGuideSolver.solve(_:)
// 功能说明: 修改后 solve(_:) 已经是共享层真实求解入口；它负责收集参考项、换算阈值、分别求 x/y 轴最佳候选，并在命中时返回修正后的 center 与 transient interaction state。
struct CanvasAlignmentGuideSolver {
    var configuration: CanvasAlignmentSolverConfiguration = .default

    func solve(
        _ request: CanvasAlignmentSolveRequest
    ) -> CanvasAlignmentSolveResult {
        guard let movingItem = request.scene.boardItem(withID: request.movingItemID) else {
            return CanvasAlignmentSolveResult.passthrough(
                proposedCenter: request.proposedCenter
            )
        }

        let proposedFrame = worldFrame(
            size: movingItem.size,
            centeredAt: request.proposedCenter
        )
        let searchRect = searchWorldRect(
            movingFrame: proposedFrame,
            camera: request.camera
        )
        let references = alignmentReferences(
            in: request.scene,
            boardState: request.boardState,
            searchRect: searchRect,
            excluding: request.movingItemID
        )
        guard references.isEmpty == false else {
            return CanvasAlignmentSolveResult.passthrough(
                proposedCenter: request.proposedCenter
            )
        }

        let thresholdInWorld = max(
            request.camera.worldDistance(
                forViewportDistance: configuration.snapThresholdInViewport
            ),
            0
        )
        let xCandidate = bestCandidate(
            for: proposedFrame,
            axis: .x,
            references: references,
            thresholdInWorld: thresholdInWorld
        )
        let yCandidate = bestCandidate(
            for: proposedFrame,
            axis: .y,
            references: references,
            thresholdInWorld: thresholdInWorld
        )
        guard xCandidate != nil || yCandidate != nil else {
            return CanvasAlignmentSolveResult.passthrough(
                proposedCenter: request.proposedCenter
            )
        }

        let resolvedCenter = CGPoint(
            x: request.proposedCenter.x + (xCandidate?.deltaInWorld ?? 0),
            y: request.proposedCenter.y + (yCandidate?.deltaInWorld ?? 0)
        )
        let resolvedFrame = worldFrame(
            size: movingItem.size,
            centeredAt: resolvedCenter
        )
        let guides = [
            xCandidate.map { guide(for: $0, movingFrame: resolvedFrame) },
            yCandidate.map { guide(for: $0, movingFrame: resolvedFrame) }
        ].compactMap { $0 }
        let interactionState = CanvasAlignmentInteractionState(
            itemID: request.movingItemID,
            guides: guides,
            xMatch: xCandidate?.match,
            yMatch: yCandidate?.match
        )
        return CanvasAlignmentSolveResult(
            resolvedCenter: resolvedCenter,
            interactionState: interactionState.isActive ? interactionState : nil
        )
    }
}
```

## 修改二：补齐候选搜索、最优候选判定与 guide 生成 helper

### 修改前

- 修改前 `CanvasAlignmentGuideSolver.swift` 除了 `solve(_:)` 占位以外，并没有 solver 内部需要的辅助函数和内部数据结构。
- 也就是说，项目里还没有：
  - 搜索矩形的计算
  - board / item 参考项收集
  - 每轴的候选筛选
  - 同距离情况下的 tie-break 规则
  - guide 线段生成

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasAlignmentGuideSolver.swift
// 函数名: searchWorldRect(...) / alignmentReferences(...) / bestCandidate(...) / guide(for:movingFrame:)
// 功能说明: 修改前这些 solver 内部 helper 和临时候选结构都还不存在；共享层还没有真正的对齐搜索管线。
```

### 修改后

- 新增了一整套共享 helper，把求解逻辑彻底收口到 solver 内部，而没有散落到平台层：
  - `searchWorldRect(...)`
  - `alignmentReferences(...)`
  - `bestCandidate(...)`
  - `guide(for:movingFrame:)`
  - `anchors(for:)`
  - `isBetter(_:than:)`
  - `orthogonalOverlap(...)`
  - `orthogonalCenterDistance(...)`
  - `overlapLength(...)`
  - `worldFrame(size:centeredAt:)`
- 同时新增两个 solver 私有结构：
  - `CanvasAlignmentReference`
  - `CanvasAlignmentAxisCandidate`
- 当前 tie-break 策略已经写死为：
  1. 先比 `distanceInWorld`
  2. 再比正交方向重叠长度
  3. 再比正交中心距离
- 这意味着多候选冲突时，solver 现在已经有明确、稳定的共享决策顺序。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasAlignmentGuideSolver.swift
// 函数名: searchWorldRect(...) / alignmentReferences(...) / bestCandidate(...) / isBetter(_:than:)
// 功能说明: 修改后这些 helper 负责把“搜索范围、参考源收集、每轴筛选、候选比较”的逻辑都固定在共享 solver 内部，避免后续 iOS/macOS 各自实现一套。
private func searchWorldRect(
    movingFrame: CGRect,
    camera: CanvasCamera
) -> CGRect {
    let viewportBounds = camera.viewportBounds
    guard viewportBounds.width > 0, viewportBounds.height > 0 else {
        let paddingInWorld = max(
            camera.worldDistance(
                forViewportDistance: configuration.searchPaddingInViewport
            ),
            0
        )
        return movingFrame
            .insetBy(dx: -paddingInWorld, dy: -paddingInWorld)
            .standardized
    }

    return camera.expandedVisibleWorldRect(
        paddingInViewport: configuration.searchPaddingInViewport
    ).standardized
}

private func alignmentReferences(
    in scene: CanvasScene,
    boardState: CanvasBoardState?,
    searchRect: CGRect,
    excluding movingItemID: CanvasItemID
) -> [CanvasAlignmentReference] {
    var references = scene
        .visibleBoardItems(in: searchRect)
        .filter { $0.id != movingItemID }
        .map {
            CanvasAlignmentReference(
                source: .item($0.id),
                frame: $0.worldFrame.standardized
            )
        }

    if let boardState {
        references.append(
            CanvasAlignmentReference(
                source: .board,
                frame: boardState.worldRect.standardized
            )
        )
    }

    return references
}

private func isBetter(
    _ candidate: CanvasAlignmentAxisCandidate,
    than currentBest: CanvasAlignmentAxisCandidate?
) -> Bool {
    guard let currentBest else {
        return true
    }

    if candidate.match.distanceInWorld < currentBest.match.distanceInWorld - canvasAlignmentComparisonEpsilon {
        return true
    }
    if candidate.match.distanceInWorld > currentBest.match.distanceInWorld + canvasAlignmentComparisonEpsilon {
        return false
    }

    if candidate.orthogonalOverlap > currentBest.orthogonalOverlap + canvasAlignmentComparisonEpsilon {
        return true
    }
    if candidate.orthogonalOverlap < currentBest.orthogonalOverlap - canvasAlignmentComparisonEpsilon {
        return false
    }

    if candidate.orthogonalCenterDistance < currentBest.orthogonalCenterDistance - canvasAlignmentComparisonEpsilon {
        return true
    }
    if candidate.orthogonalCenterDistance > currentBest.orthogonalCenterDistance + canvasAlignmentComparisonEpsilon {
        return false
    }

    return false
}
```

## 修改三：新增 solver 单测文件

### 修改前

- 当前工作区中还没有专门针对 `CanvasAlignmentGuideSolver` 的测试文件。
- 也就是说，在本次 `Phase 1` 之前，还没有自动化验证来证明：
  - 会发生吸附
  - 多个候选会选谁
  - 缩放阈值是否按 viewport 像素换算
  - 旋转对象是否仍按 `worldFrame` 语义处理
  - board 边界是否也能作为参考源

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasAlignmentGuideSolverTests.swift
// 函数名: 无（修改前该测试文件不存在）
// 功能说明: 修改前项目里没有 alignment solver 的定向单测，solver 的候选选择、阈值换算和旋转语义都没有自动化保护。
```

### 修改后

- 新增 `CanvasAlignmentGuideSolverTests.swift`，当前已经落下 6 个用例：
  - `testSolveSnapsOnBothAxesAndReturnsCenterGuides`
  - `testSolvePrefersNearestReferenceWhenMultipleCandidatesExist`
  - `testSolveReturnsPassthroughWhenNoCandidateFallsWithinThreshold`
  - `testSolveUsesViewportDistanceThresholdAcrossZoomLevels`
  - `testSolveUsesWorldFrameInsteadOfWorldBoundsForRotatedReference`
  - `testSolveCanSnapAgainstBoardReference`
- 测试类加了 `@MainActor`，和主目标默认隔离策略保持一致。
- 测试文件同时引入了简洁的构造 helper：
  - `makeAlignmentTestScene(...)`
  - `makeAlignmentTestCamera(...)`
  - `makeAlignmentTestTextItem(...)`

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasAlignmentGuideSolverTests.swift
// 函数名: testSolveSnapsOnBothAxesAndReturnsCenterGuides() / testSolveUsesViewportDistanceThresholdAcrossZoomLevels() / testSolveUsesWorldFrameInsteadOfWorldBoundsForRotatedReference()
// 功能说明: 修改后新增 alignment solver 的定向单测，直接验证吸附命中、缩放阈值和旋转语义是否满足 Phase 1 约束。
@MainActor
final class CanvasAlignmentGuideSolverTests: XCTestCase {
    func testSolveSnapsOnBothAxesAndReturnsCenterGuides() {
        let movingItem = makeAlignmentTestTextItem(
            center: CGPoint(x: 0, y: 0),
            size: CGSize(width: 40, height: 40)
        )
        let referenceItem = makeAlignmentTestTextItem(
            center: CGPoint(x: 100, y: 200),
            size: CGSize(width: 60, height: 60),
            zIndex: 1
        )
        let scene = makeAlignmentTestScene(
            items: [
                .text(movingItem),
                .text(referenceItem)
            ]
        )
        let solver = CanvasAlignmentGuideSolver(
            configuration: CanvasAlignmentSolverConfiguration(
                snapThresholdInViewport: 5,
                searchPaddingInViewport: 160
            )
        )

        let result = solver.solve(
            CanvasAlignmentSolveRequest(
                movingItemID: movingItem.id,
                proposedCenter: CGPoint(x: 104, y: 204),
                scene: scene,
                boardState: nil,
                camera: makeAlignmentTestCamera()
            )
        )

        XCTAssertEqual(result.resolvedCenter, CGPoint(x: 100, y: 200))
        XCTAssertEqual(result.interactionState?.guides.count, 2)
    }

    func testSolveUsesViewportDistanceThresholdAcrossZoomLevels() {
        // ... 同文件内继续验证 zoom=1 时命中、zoom=2 时不命中 ...
    }

    func testSolveUsesWorldFrameInsteadOfWorldBoundsForRotatedReference() {
        // ... 同文件内继续验证旋转 reference 仍按 worldFrame 语义吸附 ...
    }
}
```

## 修改四：测试层补上生命周期保护，避免 `CanvasScene` 提前释放导致崩溃

### 修改前

- 在本次 `Phase 1` 落地过程中，单测第一次执行时发生了运行时崩溃。
- 崩溃并不是 solver 算法本身断言失败，而是在 XCTest 内存检查阶段，`CanvasScene` 释放触发了 `abort()`。
- 从最终测试文件现状可以反推出：修改前测试里是直接 `let scene = CanvasScene(items: ...)`，没有任何 retainer。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasAlignmentGuideSolverTests.swift
// 函数名: makeAlignmentTestScene(...)
// 功能说明: 修改前没有测试级对象保留器；scene 在测试结束后的释放时机与项目现有测试模式不一致，导致 XCTest 内存检查阶段发生崩溃。
```

### 修改后

- 测试文件新增了：
  - `CanvasAlignmentGuideSolverTestRetainer`
  - `makeAlignmentTestScene(...)`
- 现在所有测试都通过 `makeAlignmentTestScene(...)` 创建并保留 `CanvasScene`，把生命周期处理方式对齐到项目里已有的测试模式。
- 这一步并不改变 solver 功能，只是让测试运行环境稳定下来。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasAlignmentGuideSolverTests.swift
// 函数名: CanvasAlignmentGuideSolverTestRetainer / makeAlignmentTestScene(...)
// 功能说明: 修改后通过静态 retainer 保留测试用 scene，避免 scene 在 XCTest 内存检查阶段提前释放，从而消除运行时 abort。
private enum CanvasAlignmentGuideSolverTestRetainer {
    static var scenes: [CanvasScene] = []
}

private func makeAlignmentTestScene(
    items: [CanvasBoardItem]
) -> CanvasScene {
    let scene = CanvasScene(items: items)
    CanvasAlignmentGuideSolverTestRetainer.scenes.append(scene)
    return scene
}
```

## 本次修改后的实际状态

- 已经落下来的能力：
  - 共享 solver 的真实求解逻辑
  - `board + item` 参考源收集
  - 基于 viewport 像素的阈值换算
  - 多候选 tie-break 规则
  - world guide 生成
  - solver 定向单测
- 还没有落下来的能力：
  - `EditorSession` 中持有和清理 `alignmentInteractionState`
  - `CanvasRenderer` 把 interaction state 转成 `CanvasInteractionRenderOverlay`
  - iOS/macOS 控制器在拖拽链路里实际调用 solver
  - viewport 真实绘制 alignment line

## 验证结果

- 单测已通过：
  - `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=macOS" test -only-testing:MyCanvas_Ver_0Tests/CanvasAlignmentGuideSolverTests`
- 主目标构建已通过：
  - `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=macOS" build`
- `ReadLints` 未发现本次修改文件新增问题。
