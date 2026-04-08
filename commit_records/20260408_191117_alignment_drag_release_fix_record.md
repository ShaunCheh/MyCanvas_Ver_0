# 20260408_191117_alignment_drag_release_fix_record

## 记录范围

- 记录内容：
  1. 新增共享 `selected-item drag session`，把拖拽起点和吸附锁定状态从 controller 局部增量逻辑里抽出来。
  2. 将 `CanvasAlignmentGuideSolver` 从单一吸附阈值模型升级为“进入阈值 + 释放阈值 + per-axis lock”模型。
  3. 改造 `iOSViewController` / `macOSViewController` 的拖拽链路，改为使用累计原始位移求解 `proposedCenter`。
  4. 补齐 solver 与 drag session 的自动化测试，覆盖保持锁定、释放锁定、单轴释放与缩放一致性。
  5. 如实记录当前工作区中附带存在的 plan frontmatter 状态变化。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasSelectedItemDragState.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasAlignmentGuideSolver.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0Tests/CanvasAlignmentGuideSolverTests.swift`
  - `MyCanvas_Ver_0Tests/CanvasSelectedItemDragStateTests.swift`
  - `.cursor/plans/对齐拖离修复_d8907cdc.plan.md`
- 当前 changes 依据：
  - `date +"%Y%m%d_%H%M%S"`：`20260408_191117`
  - `git status --short` 当前显示：
    - `M .cursor/plans/对齐拖离修复_d8907cdc.plan.md`
    - `M MyCanvas_Ver_0/Canvas/Core/CanvasAlignmentGuideSolver.swift`
    - `M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
    - `M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
    - `M MyCanvas_Ver_0Tests/CanvasAlignmentGuideSolverTests.swift`
    - `?? MyCanvas_Ver_0/Canvas/Editing/CanvasSelectedItemDragState.swift`
    - `?? MyCanvas_Ver_0Tests/CanvasSelectedItemDragStateTests.swift`
  - `git diff --stat` 当前显示：
    - `5 files changed, 622 insertions(+), 73 deletions(-)`
  - 如实说明：
    - 上面的 `git diff --stat` 只统计 tracked 文件，不包含两个新建但尚未纳入版本控制的 Swift 文件。
    - 新建文件内容依据 `git diff --no-index -- /dev/null <path>` 核对。
- 验证依据：
  - `ReadLints`：本次改动涉及的 Swift 文件无新增诊断问题。
  - `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=macOS" test -only-testing:MyCanvas_Ver_0Tests/CanvasAlignmentGuideSolverTests -only-testing:MyCanvas_Ver_0Tests/CanvasSelectedItemDragStateTests -only-testing:MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests`：通过。
  - `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=macOS" build`：通过。
  - `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "generic/platform=iOS Simulator" build`：通过。
- 本记录不包含：
  - 原始 `git diff` 全文
  - `git commit` / `git push`
  - 人工拖拽手验结论

## 修改一：新增共享 `CanvasSelectedItemDragState`，把拖拽基线从 controller 的帧间增量切到“拖拽起点 + 累计原始位移”

### 修改前

- 修改前没有专门的共享 drag session 类型。
- `selected item` 拖拽的起点信息和吸附锁定语义没有独立数据结构承载，controller 只能依赖每帧输入增量与当前中心点临时拼出下一帧的 `proposedCenter`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasSelectedItemDragState.swift
// 函数名: N/A（新增文件，修改前不存在）
// 功能说明: 修改前项目里没有共享的 selected-item drag session 类型，拖拽基线与锁定态没有单独的跨帧状态容器。
// 修改前：无此文件
```

### 修改后

- 新增 `CanvasSelectedItemDragState`，显式记录：
  - `itemID`
  - `dragStartWorldLocation`
  - `dragStartCenter`
  - `alignmentLock`
- `proposedCenter(for:)` 统一用“当前世界坐标 - 拖拽起点世界坐标”的累计原始位移求解，不再依赖上一帧已吸附后的中心点。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasSelectedItemDragState.swift
// 函数名: CanvasSelectedItemDragState.init(...) / proposedCenter(for:) / replacingAlignmentLock(_:)
// 功能说明: 修改后新增共享拖拽会话类型，专门保存拖拽起点中心、拖拽起点世界坐标以及当前吸附锁定态，供 iOS/macOS 双端 controller 与 solver 共用。
struct CanvasSelectedItemDragState: Equatable {
    let itemID: CanvasItemID
    let dragStartWorldLocation: CGPoint
    let dragStartCenter: CGPoint
    var alignmentLock: CanvasAlignmentLockState

    func proposedCenter(
        for currentWorldLocation: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: dragStartCenter.x + (currentWorldLocation.x - dragStartWorldLocation.x),
            y: dragStartCenter.y + (currentWorldLocation.y - dragStartWorldLocation.y)
        )
    }

    func replacingAlignmentLock(
        _ alignmentLock: CanvasAlignmentLockState
    ) -> CanvasSelectedItemDragState {
        var updatedState = self
        updatedState.alignmentLock = alignmentLock
        return updatedState
    }
}
```

## 修改二：`CanvasAlignmentGuideSolver` 从“单阈值吸附”升级为“进入阈值 + 释放阈值 + per-axis lock”

### 修改前

- solver 只有单一 `snapThresholdInViewport`。
- `CanvasAlignmentSolveRequest` 不携带上一帧锁定信息。
- `CanvasAlignmentSolveResult` 不返回下一帧可复用的 lock 状态。
- 一旦对象已经吸附，下一帧仍在同一个阈值带内时，solver 会继续把它拉回参考线，没有单独的 release 语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasAlignmentGuideSolver.swift
// 函数名: CanvasAlignmentSolverConfiguration / CanvasAlignmentSolveRequest / CanvasAlignmentGuideSolver.solve(_:)
// 功能说明: 修改前 solver 只有单一吸附阈值，没有跨帧锁定态，也没有 release threshold；只要仍落在阈值带里，就会继续回吸。
struct CanvasAlignmentSolverConfiguration: Equatable {
    let snapThresholdInViewport: CGFloat
    let searchPaddingInViewport: CGFloat

    static let `default` = CanvasAlignmentSolverConfiguration(
        snapThresholdInViewport: 8,
        searchPaddingInViewport: 160
    )
}

struct CanvasAlignmentSolveRequest {
    let movingItemID: CanvasItemID
    let proposedCenter: CGPoint
    let scene: CanvasScene
    let boardState: CanvasBoardState?
    let camera: CanvasCamera
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
```

### 修改后

- 新增 `CanvasAlignmentAxisLock` 与 `CanvasAlignmentLockState`。
- 配置改为：
  - `snapEnterThresholdInViewport`
  - `snapReleaseThresholdInViewport`
- `CanvasAlignmentSolveRequest` 增加 `lockState`。
- `CanvasAlignmentSolveResult` 增加 `lockState`，供 controller 回写到下一帧 drag session。
- `bestCandidate(...)` 变成两阶段：
  1. 先尝试延续上一帧已锁定轴，并用 `releaseThresholdInWorld` 判定是否释放。
  2. 只有未锁定或锁定被释放后，才会重新走 entering snap 候选搜索。
- 诊断日志保留但默认关闭，避免常驻噪音。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasAlignmentGuideSolver.swift
// 函数名: CanvasAlignmentAxisLock / CanvasAlignmentLockState / CanvasAlignmentSolverConfiguration / CanvasAlignmentSolveRequest / CanvasAlignmentSolveResult
// 功能说明: 修改后 solver 的输入输出都带上了 per-axis lock，阈值拆分为 enter/release 两阶段，为“吸附后可稳定拖离”提供跨帧语义基础。
struct CanvasAlignmentAxisLock: Equatable {
    let movingAnchor: CanvasAlignmentAnchor
    let referenceAnchor: CanvasAlignmentAnchor
    let referenceSource: CanvasAlignmentReferenceSource
}

struct CanvasAlignmentLockState: Equatable {
    let xAxis: CanvasAlignmentAxisLock?
    let yAxis: CanvasAlignmentAxisLock?

    static let none = CanvasAlignmentLockState()
}

struct CanvasAlignmentSolverConfiguration: Equatable {
    let snapEnterThresholdInViewport: CGFloat
    let snapReleaseThresholdInViewport: CGFloat
    let searchPaddingInViewport: CGFloat
}

struct CanvasAlignmentSolveRequest {
    let movingItemID: CanvasItemID
    let proposedCenter: CGPoint
    let scene: CanvasScene
    let boardState: CanvasBoardState?
    let camera: CanvasCamera
    let lockState: CanvasAlignmentLockState
}

struct CanvasAlignmentSolveResult {
    let resolvedCenter: CGPoint
    let interactionState: CanvasAlignmentInteractionState?
    let lockState: CanvasAlignmentLockState
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasAlignmentGuideSolver.swift
// 函数名: CanvasAlignmentGuideSolver.solve(_:) / bestCandidate(...) / lockedCandidate(...)
// 功能说明: 修改后 solver 先按 release threshold 判断当前锁定轴是否还能维持，再决定是否重新进入候选搜索；这样对象进入吸附后不会被单一阈值永久“钉死”。
let enterThresholdInWorld = max(
    request.camera.worldDistance(
        forViewportDistance: configuration.snapEnterThresholdInViewport
    ),
    0
)
let releaseThresholdInWorld = max(
    request.camera.worldDistance(
        forViewportDistance: configuration.snapReleaseThresholdInViewport
    ),
    enterThresholdInWorld
)

let xCandidate = bestCandidate(
    for: proposedFrame,
    axis: .x,
    references: references,
    enterThresholdInWorld: enterThresholdInWorld,
    releaseThresholdInWorld: releaseThresholdInWorld,
    previousLock: request.lockState.xAxis
)

private func bestCandidate(
    for movingFrame: CGRect,
    axis: CanvasAlignmentCoordinateAxis,
    references: [CanvasAlignmentReference],
    enterThresholdInWorld: CGFloat,
    releaseThresholdInWorld: CGFloat,
    previousLock: CanvasAlignmentAxisLock?
) -> CanvasAlignmentAxisCandidate? {
    if let previousLock,
       let lockedCandidate = lockedCandidate(
            for: movingFrame,
            axis: axis,
            references: references,
            previousLock: previousLock,
            releaseThresholdInWorld: releaseThresholdInWorld
       )
    {
        return lockedCandidate
    }

    return bestEnteringCandidate(
        for: movingFrame,
        axis: axis,
        references: references,
        thresholdInWorld: enterThresholdInWorld
    )
}

private let canvasAlignmentDiagnosticLoggingEnabled = false
```

## 修改三：`iOSViewController` 改为基于 drag session 的累计位移拖拽

### 修改前

- `PointerDragState.draggingSelectedItem` 只保存 `itemID`。
- 进入拖拽后立刻执行 `moveSelectedItem(withID:from:to:)`。
- `moveSelectedItem` 每帧基于 `previousLocation -> currentLocation` 的增量求 `rawDeltaInWorld`，再叠加到当前 `movingItem.center` 上。
- 这意味着一旦当前 `center` 已经被 solver 吸附修正，下一帧会继续用被修正后的中心点作为输入基线。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: PointerDragState / handlePrimaryPointerMove(to:from:) / moveSelectedItem(withID:from:to:)
// 功能说明: 修改前 iOS 端拖拽状态只保留 itemID，每帧按“上一帧中心 + 本帧 delta”求 proposedCenter，容易把已吸附位置重新喂回 solver。
private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressContext: CanvasPointerPressContext
    )
    case draggingSelectedItem(itemID: CanvasItemID)
}

pointerDragState = .draggingSelectedItem(itemID: itemID)
moveSelectedItem(withID: itemID, from: pressedLocation, to: location)

private func moveSelectedItem(
    withID itemID: CanvasItemID,
    from previousLocation: CGPoint,
    to location: CGPoint
) {
    let previousWorldLocation = camera.viewportToWorld(previousLocation)
    let currentWorldLocation = camera.viewportToWorld(location)
    let rawDeltaInWorld = CGPoint(
        x: currentWorldLocation.x - previousWorldLocation.x,
        y: currentWorldLocation.y - previousWorldLocation.y
    )
    let proposedCenter = CGPoint(
        x: movingItem.center.x + rawDeltaInWorld.x,
        y: movingItem.center.y + rawDeltaInWorld.y
    )
}
```

### 修改后

- `PointerDragState.draggingSelectedItem` 改为直接保存 `CanvasSelectedItemDragState`。
- 从 `.pressed -> .draggingSelectedItem` 的切换点开始，先记录 `dragStartWorldLocation` 与 `dragStartCenter`。
- 每一帧都用 `dragState.proposedCenter(for:)` 计算累计原始位移结果。
- controller 把 `solveResult.lockState` 回写给下一帧的 drag session，形成稳定的跨帧释放语义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: PointerDragState / handlePrimaryPointerMove(to:from:)
// 功能说明: 修改后 iOS 端在进入拖拽时先构造共享 drag session，后续每一帧都把更新后的 lockState 存回 pointerDragState。
private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressContext: CanvasPointerPressContext
    )
    case draggingSelectedItem(CanvasSelectedItemDragState)
}

guard let dragState = makeSelectedItemDragState(
    itemID: itemID,
    initialViewportLocation: pressedLocation
) else {
    pointerDragState = .idle
    return
}

guard let updatedDragState = moveSelectedItem(
    using: dragState,
    to: location
) else {
    pointerDragState = .idle
    return
}

pointerDragState = .draggingSelectedItem(updatedDragState)
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: makeSelectedItemDragState(itemID:initialViewportLocation:) / moveSelectedItem(using:to:)
// 功能说明: 修改后 iOS 端按“拖拽起点 center + 累计原始世界位移”求 proposedCenter，并把 solver 返回的 lockState 写回 drag session。
private func makeSelectedItemDragState(
    itemID: CanvasItemID,
    initialViewportLocation: CGPoint
) -> CanvasSelectedItemDragState? {
    guard let movingItem = scene.boardItem(withID: itemID) else {
        return nil
    }

    return CanvasSelectedItemDragState(
        itemID: itemID,
        dragStartWorldLocation: camera.viewportToWorld(initialViewportLocation),
        dragStartCenter: movingItem.center
    )
}

private func moveSelectedItem(
    using dragState: CanvasSelectedItemDragState,
    to location: CGPoint
) -> CanvasSelectedItemDragState? {
    let currentWorldLocation = camera.viewportToWorld(location)
    let proposedCenter = dragState.proposedCenter(
        for: currentWorldLocation
    )
    let solveResult = alignmentGuideSolver.solve(
        CanvasAlignmentSolveRequest(
            movingItemID: dragState.itemID,
            proposedCenter: proposedCenter,
            scene: scene,
            boardState: boardState,
            camera: camera,
            lockState: dragState.alignmentLock
        )
    )

    return dragState.replacingAlignmentLock(solveResult.lockState)
}
```

## 修改四：`macOSViewController` 同步改为基于 drag session 的累计位移拖拽

### 修改前

- macOS 端与 iOS 端一致，`draggingSelectedItem` 只带 `itemID`。
- `moveSelectedItem(withID:from:to:)` 同样使用帧间增量和当前中心点求解。
- 两端都存在相同的“吸附后继续往法向拖动时难以脱离”的根因。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: PointerDragState / handlePrimaryPointerMove(to:from:) / moveSelectedItem(withID:from:to:)
// 功能说明: 修改前 macOS 端与 iOS 端同构，拖拽状态只存 itemID，每帧都按帧间增量构造 proposedCenter。
private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressContext: CanvasPointerPressContext
    )
    case draggingSelectedItem(itemID: CanvasItemID)
}

pointerDragState = .draggingSelectedItem(itemID: itemID)
moveSelectedItem(withID: itemID, from: pressedLocation, to: location)

private func moveSelectedItem(
    withID itemID: CanvasItemID,
    from previousLocation: CGPoint,
    to location: CGPoint
) {
    let previousWorldLocation = camera.viewportToWorld(previousLocation)
    let currentWorldLocation = camera.viewportToWorld(location)
    let rawDeltaInWorld = CGPoint(
        x: currentWorldLocation.x - previousWorldLocation.x,
        y: currentWorldLocation.y - previousWorldLocation.y
    )
    let proposedCenter = CGPoint(
        x: movingItem.center.x + rawDeltaInWorld.x,
        y: movingItem.center.y + rawDeltaInWorld.y
    )
}
```

### 修改后

- macOS 端与 iOS 端保持同一套共享 drag session 与 solver request 语义。
- `moveSelectedItem(using:to:)` 同样按累计原始位移求 `proposedCenter`。
- `solveResult.lockState` 也会回写到 macOS 下一帧拖拽状态，保证两端脱离手感一致。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: PointerDragState / handlePrimaryPointerMove(to:from:)
// 功能说明: 修改后 macOS 端也改为保存完整 drag session，而不是只保存 itemID，避免双端行为再次分叉。
private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressContext: CanvasPointerPressContext
    )
    case draggingSelectedItem(CanvasSelectedItemDragState)
}

guard let dragState = makeSelectedItemDragState(
    itemID: itemID,
    initialViewportLocation: pressedLocation
) else {
    pointerDragState = .idle
    return
}

guard let updatedDragState = moveSelectedItem(
    using: dragState,
    to: location
) else {
    pointerDragState = .idle
    return
}

pointerDragState = .draggingSelectedItem(updatedDragState)
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: makeSelectedItemDragState(itemID:initialViewportLocation:) / moveSelectedItem(using:to:)
// 功能说明: 修改后 macOS 端与 iOS 端一致，通过共享 drag session + solver lockState 回写实现“吸附后可稳定拖离”。
private func makeSelectedItemDragState(
    itemID: CanvasItemID,
    initialViewportLocation: CGPoint
) -> CanvasSelectedItemDragState? {
    guard let movingItem = scene.boardItem(withID: itemID) else {
        return nil
    }

    return CanvasSelectedItemDragState(
        itemID: itemID,
        dragStartWorldLocation: camera.viewportToWorld(initialViewportLocation),
        dragStartCenter: movingItem.center
    )
}

private func moveSelectedItem(
    using dragState: CanvasSelectedItemDragState,
    to location: CGPoint
) -> CanvasSelectedItemDragState? {
    let currentWorldLocation = camera.viewportToWorld(location)
    let proposedCenter = dragState.proposedCenter(
        for: currentWorldLocation
    )
    let solveResult = alignmentGuideSolver.solve(
        CanvasAlignmentSolveRequest(
            movingItemID: dragState.itemID,
            proposedCenter: proposedCenter,
            scene: scene,
            boardState: boardState,
            camera: camera,
            lockState: dragState.alignmentLock
        )
    )

    return dragState.replacingAlignmentLock(solveResult.lockState)
}
```

## 修改五：扩展 `CanvasAlignmentGuideSolverTests`，补齐保持锁定 / 释放锁定 / 单轴释放 / 缩放一致性

### 修改前

- 原测试只覆盖：
  - 双轴吸附
  - 多候选取最近
  - 超阈值不吸附
  - `zoom` 对 enter 阈值的影响
  - 旋转对象按 `worldFrame` 语义吸附
  - board 参考源吸附
- 还没有覆盖：
  - 已锁定状态的保持
  - 超过 release threshold 后释放
  - 双轴锁定后只释放单轴
  - release threshold 在不同 `zoomScale` 下的一致性

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasAlignmentGuideSolverTests.swift
// 函数名: CanvasAlignmentGuideSolverTests
// 功能说明: 修改前测试主要覆盖 entering snap 的基础行为，还没有覆盖锁定态与释放态的跨帧语义。
@MainActor
final class CanvasAlignmentGuideSolverTests: XCTestCase {
    func testSolveSnapsOnBothAxesAndReturnsCenterGuides() { ... }
    func testSolvePrefersNearestReferenceWhenMultipleCandidatesExist() { ... }
    func testSolveReturnsPassthroughWhenNoCandidateFallsWithinThreshold() { ... }
    func testSolveUsesViewportDistanceThresholdAcrossZoomLevels() { ... }
    func testSolveUsesWorldFrameInsteadOfWorldBoundsForRotatedReference() { ... }
    func testSolveCanSnapAgainstBoardReference() { ... }
}
```

### 修改后

- 现有配置用例改为显式使用 `snapEnterThresholdInViewport` / `snapReleaseThresholdInViewport`。
- 新增 4 个关键用例：
  - `testSolveKeepsExistingLockWhilePointerStaysWithinReleaseThreshold()`
  - `testSolveReleasesExistingLockAfterCrossingReleaseThreshold()`
  - `testSolveCanReleaseSingleAxisWhileKeepingOtherAxisLocked()`
  - `testSolveUsesViewportDistanceForReleaseThresholdAcrossZoomLevels()`

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasAlignmentGuideSolverTests.swift
// 函数名: testSolveKeepsExistingLockWhilePointerStaysWithinReleaseThreshold() / testSolveReleasesExistingLockAfterCrossingReleaseThreshold() / testSolveCanReleaseSingleAxisWhileKeepingOtherAxisLocked() / testSolveUsesViewportDistanceForReleaseThresholdAcrossZoomLevels()
// 功能说明: 修改后测试直接覆盖“进入锁定 -> 保持锁定 -> 超过 release 后释放 -> 单轴释放 -> zoom 一致性”这条新语义链路。
let solver = CanvasAlignmentGuideSolver(
    configuration: CanvasAlignmentSolverConfiguration(
        snapEnterThresholdInViewport: 5,
        snapReleaseThresholdInViewport: 12,
        searchPaddingInViewport: 160
    )
)

let result = solver.solve(
    CanvasAlignmentSolveRequest(
        movingItemID: movingItem.id,
        proposedCenter: CGPoint(x: 108, y: 0),
        scene: scene,
        boardState: nil,
        camera: makeAlignmentTestCamera(),
        lockState: CanvasAlignmentLockState(
            xAxis: CanvasAlignmentAxisLock(
                movingAnchor: .centerX,
                referenceAnchor: .centerX,
                referenceSource: .item(referenceItem.id)
            )
        )
    )
)

XCTAssertEqual(result.resolvedCenter, CGPoint(x: 100, y: 0))
XCTAssertEqual(result.lockState, .none)
XCTAssertEqual(zoomScaleTwoResult.resolvedCenter, CGPoint(x: 108, y: 0))
```

## 修改六：新增 `CanvasSelectedItemDragStateTests`，把累计原始位移逻辑单独锁住

### 修改前

- 修改前没有专门针对 `CanvasSelectedItemDragState` 的纯逻辑测试文件。
- 拖拽基线是否正确只能间接依赖 controller 行为或 solver 结果推断。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasSelectedItemDragStateTests.swift
// 函数名: N/A（新增文件，修改前不存在）
// 功能说明: 修改前没有单独验证 dragStartCenter 与 dragStartWorldLocation 的累计位移计算逻辑。
// 修改前：无此文件
```

### 修改后

- 新增独立测试文件，直接验证：
  - `proposedCenter(for:)` 是否按照累计原始位移计算。
  - `replacingAlignmentLock(_:)` 是否只更新 lock，不破坏拖拽基线。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasSelectedItemDragStateTests.swift
// 函数名: testProposedCenterUsesDragStartCenterAndAccumulatedWorldDelta() / testReplacingAlignmentLockDoesNotChangeDragBaseline()
// 功能说明: 修改后 drag session 的核心计算不再依赖 controller 集成测试，而是由纯单测直接约束住。
final class CanvasSelectedItemDragStateTests: XCTestCase {
    func testProposedCenterUsesDragStartCenterAndAccumulatedWorldDelta() {
        let dragState = CanvasSelectedItemDragState(
            itemID: CanvasItemID(),
            dragStartWorldLocation: CGPoint(x: 200, y: 300),
            dragStartCenter: CGPoint(x: 40, y: 60)
        )

        let proposedCenter = dragState.proposedCenter(
            for: CGPoint(x: 215, y: 282)
        )

        XCTAssertEqual(proposedCenter, CGPoint(x: 55, y: 42))
    }

    func testReplacingAlignmentLockDoesNotChangeDragBaseline() {
        let updatedState = dragState.replacingAlignmentLock(...)
        XCTAssertEqual(updatedState.proposedCenter(for: CGPoint(x: 16, y: 12)), CGPoint(x: 106, y: 112))
    }
}
```

## 附带变化：`.cursor/plans/对齐拖离修复_d8907cdc.plan.md` 的 frontmatter todo 状态发生同步更新

### 修改前

- 当前 tracked changes 中，这个 plan 文件的 frontmatter todo 状态原本仍是 `pending`。
- 这部分不是生产代码逻辑，也不是本次 root-cause fix 的实现主体，但它确实存在于当前工作区变更里。

```yaml
# 文件路径: .cursor/plans/对齐拖离修复_d8907cdc.plan.md
# 函数名: frontmatter.todos
# 功能说明: 修改前 plan frontmatter 中的 todo 状态仍停留在 pending。
todos:
  - id: shared-drag-session
    status: pending
  - id: solver-hysteresis
    status: pending
  - id: controller-cumulative-center
    status: pending
  - id: tests-validation
    status: pending
  - id: log-cleanup
    status: pending
```

### 修改后

- 当前工作区里，这个 plan 文件的 frontmatter 状态已经同步为：
  - `shared-drag-session: completed`
  - `solver-hysteresis: completed`
  - `controller-cumulative-center: completed`
  - `tests-validation: in_progress`
  - `log-cleanup: completed`
- 本记录只如实记录该状态变化，不把它计入生产代码实现。

```yaml
# 文件路径: .cursor/plans/对齐拖离修复_d8907cdc.plan.md
# 函数名: frontmatter.todos
# 功能说明: 修改后 plan frontmatter 中的 todo 状态已同步更新到当前实施进度；这是当前工作区的一部分变化，但不是本次生产逻辑修复主体。
todos:
  - id: shared-drag-session
    status: completed
  - id: solver-hysteresis
    status: completed
  - id: controller-cumulative-center
    status: completed
  - id: tests-validation
    status: in_progress
  - id: log-cleanup
    status: completed
```

## 结论

- 这次修改的核心不是“调阈值”，而是同时修正了两层根因：
  1. controller 不再把“上一帧已吸附后的 center”当作下一帧位移基线。
  2. solver 不再用单一阈值同时承担“进入吸附”和“离开吸附”的判定。
- 当前自动化验证可以确认：
  - 共享求解器语义已升级为 enter/release 双阈值模型。
  - iOS/macOS 双端都已经接入同一套 drag session + lockState 语义。
  - 新增的纯逻辑测试已覆盖累计原始位移与 lockState 替换行为。
- 当前尚未在本记录中给出人工拖拽验收结论，因此“体感完全符合预期”仍需手验补充。
