# 20260820_084017_CST_ios_pinch_release_jump_root_fix_record

## 记录范围

本记录如实对应 iOS 画布双指缩放收尾跳移的根因修复，内容来自创建记录前的：

- `git status --short`
- `git diff --stat`
- `iOSCanvasViewportView.swift` 与 `iOSViewController.swift` 的实际 diff
- 4 个新增 Swift 文件的当前内容
- 定向单元测试、完整测试、iOS Simulator build、iOS 真机 build/install 输出
- IDE lint 与 `git diff --check`

本文不粘贴原始 git diff，而是按当前 changes 整理修改前后的真实代码和行为。

本次实际修改包括：

1. 新增平台无关的 direct-touch pinch 连续性跟踪器。
2. direct-touch transform 只允许来自前后相同的两根触点。
3. pinch 结束后进入残余触摸 drain 状态，不再把剩余单指接成 pointer/tap。
4. 连续 pinch camera refresh 改为 `CADisplayLink` 合帧。
5. 新增 refresh generation，避免旧 board 的延迟帧覆盖新 runtime。
6. 新增 pinch session/sequence 日志和 canvas refresh 分阶段耗时。
7. 新增连续性跟踪器与刷新合帧单元测试。

本次没有修改：

- `CanvasCamera.swift` 的 pan/zoom/transform 数学。
- macOS 手势链路。
- board document schema、持久化格式或 autosave 数据结构。
- 现有 `.md` 文件；本文件是用户明确要求新增的修改记录。

## 时间戳来源

时间戳来自系统 `date` 命令。

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：生成“年月日_时分秒_CST”格式的记录时间戳。
date '+%Y%m%d_%H%M%S_CST'
```

实际输出：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# date 命令实际输出
20260820_084017_CST
```

记录文件名：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0/commit_records
# 功能注释：使用“年月日_时分秒_其他部分”格式命名本次记录。
20260820_084017_CST_ios_pinch_release_jump_root_fix_record.md
```

## 创建记录前的当前 changes

`git status --short` 的实际结果：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：记录创建前共有 2 个已跟踪修改文件和 4 个未跟踪新增文件。
 M MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
 M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
?? MyCanvas_Ver_0/Canvas/Core/CanvasRefreshFrameCoalescer.swift
?? MyCanvas_Ver_0/Canvas/Input/CanvasDirectPinchContinuityTracker.swift
?? MyCanvas_Ver_0Tests/CanvasDirectPinchContinuityTrackerTests.swift
?? MyCanvas_Ver_0Tests/CanvasRefreshFrameCoalescerTests.swift
```

已跟踪文件的 `git diff --stat`：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：该统计不包含 4 个未跟踪新增文件。
.../iOS/Canvas/iOSCanvasViewportView.swift | 410 ++++++++++++++++-----
.../Platform/iOS/iOSViewController.swift   | 214 +++++++++--
2 files changed, 505 insertions(+), 119 deletions(-)
```

4 个未跟踪新增文件当前分别为 87、29、151、44 行，共 311 行。

## 已确认的根因

真机修复前日志出现过以下事件链：

- pinch `.changed` 已经只有 `touches=1`、`activeTouches=1`。
- recognizer 的 anchor 从双指中心跳到剩余单指位置。
- viewport 仍派发 `scaleDelta=1` 的纯 translation。
- 实际错误 translation 包括 `{79,19}`、`{93,25}`。
- camera center 被真实修改。
- 同一刷新偶发阻塞 `106–108ms`，所以错误位移在抬手后才显示。

因此根因不是 camera 浮点误差，也不是结束动画，而是：

1. direct-touch pinch 没有验证触点数量和触点身份连续性。
2. pinch 结束后普通 touch reconcile 会接管残余单指。
3. 每个 pinch 事件都同步执行完整 canvas refresh，放大了错误帧的视觉延迟。

## 修改一：新增双指连续性跟踪器

涉及文件：

- `MyCanvas_Ver_0/Canvas/Input/CanvasDirectPinchContinuityTracker.swift`
- `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`

### 修改前

`handlePinch(_:)` 只保存上一帧 anchor。即使当前 recognizer 已经只剩一根触点，也会直接计算平移。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift（修改前）
// 函数名: handlePinch(_:)
// 功能注释: 修改前没有触点数量和触点身份连续性校验。
let previousAnchor = session.lastAnchor
session.lastAnchor = anchor

let translation = CGPoint(
    x: anchor.x - previousAnchor.x,
    y: anchor.y - previousAnchor.y
)
let scaleDelta = normalizedScaleDelta ?? 1
onDirectTouchTransform?(
    CanvasDirectTouchTransformDelta(
        translationInViewport: translation,
        scaleDelta: scaleDelta,
        anchorInViewport: anchor
    )
)
```

### 修改后

新增泛型 tracker，用 recognizer touch count、UIView active touch IDs、scale、timestamp 和 anchor 共同建立连续性合同。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasDirectPinchContinuityTracker.swift
// 类型名: CanvasDirectPinchContinuityTracker
// 功能注释: 只有前后两帧完全相同的两根触点才能产生 transform。
struct CanvasDirectPinchContinuityTracker<TouchID: Hashable> {
    private struct Baseline {
        let touchIDs: Set<TouchID>
        let rawScale: CGFloat
        let timestamp: TimeInterval
        let anchor: CGPoint
    }

    private var baseline: Baseline?

    mutating func consume(
        _ sample: CanvasDirectPinchSample<TouchID>
    ) -> CanvasDirectPinchDecision {
        guard sample.rawScale.isFinite, sample.rawScale > 0 else {
            baseline = nil
            return .suppressed(.invalidScale)
        }

        guard
            sample.recognizerTouchCount == 2,
            sample.activeTouchIDs.count == 2
        else {
            baseline = nil
            return .suppressed(.unstableTouchCount)
        }

        let nextBaseline = Baseline(
            touchIDs: sample.activeTouchIDs,
            rawScale: sample.rawScale,
            timestamp: sample.timestamp,
            anchor: sample.anchorInViewport
        )
        guard
            let previousBaseline = baseline,
            previousBaseline.touchIDs == sample.activeTouchIDs
        else {
            baseline = nextBaseline
            return .rebaselined
        }

        baseline = nextBaseline
        return .transform(
            CanvasDirectPinchContinuousDelta(
                translationInViewport: CGPoint(
                    x: sample.anchorInViewport.x - previousBaseline.anchor.x,
                    y: sample.anchorInViewport.y - previousBaseline.anchor.y
                ),
                rawScaleDelta: sample.rawScale / max(previousBaseline.rawScale, 0.0001),
                sampleInterval: max(sample.timestamp - previousBaseline.timestamp, 0),
                anchorInViewport: sample.anchorInViewport
            )
        )
    }
}
```

当前行为：

- `2 -> 1`、`2 -> 3`、非法 scale：清空 baseline 并 suppress。
- 两根触点被替换：第一帧只 rebaseline。
- 只有 `.transform` 决策会进入 controller。
- 缩放 deadzone 仍由 iOS viewport 原有 normalization 处理，tracker 只负责连续性。

## 修改二：重构 pinch session 和日志关联

涉及文件：

- `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`

### 修改前

session 共用 `source/lastRawScale/lastTimestamp/lastAnchor`，direct touch 和 Mirroring 没有类型隔离；transform payload 也没有手势关联字段。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift（修改前）
// 类型名: PinchGestureSession / CanvasDirectTouchTransformDelta
// 功能注释: 修改前无法稳定关联一次手势内的输入与 controller 日志。
private struct PinchGestureSession {
    var source: PinchInputSource
    var lastRawScale: CGFloat
    var lastTimestamp: TimeInterval
    var lastAnchor: CGPoint
}

struct CanvasDirectTouchTransformDelta: Equatable {
    let translationInViewport: CGPoint
    let scaleDelta: CGFloat
    let anchorInViewport: CGPoint
}
```

### 修改后

session 改为 source-specific state，并增加递增的 session ID 和 event sequence。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 类型名: PinchGestureSession / PinchSessionInputState
// 功能注释: direct touch 与 Mirroring 使用不同状态，并为日志提供稳定关联键。
private enum PinchSessionInputState {
    case directTouch(CanvasDirectPinchContinuityTracker<ObjectIdentifier>)
    case indirectMirroringLike(IndirectPinchBaseline)
}

private struct PinchGestureSession {
    let id: UInt64
    var eventSequence: UInt64
    var inputState: PinchSessionInputState
}

struct CanvasDirectTouchTransformDelta: Equatable {
    let pinchSessionID: UInt64
    let eventSequence: UInt64
    let translationInViewport: CGPoint
    let scaleDelta: CGFloat
    let anchorInViewport: CGPoint
}
```

`[Canvas iOS][PinchInput]` 当前新增：

- `sessionID`
- `seq`
- `decision`
- 原有 state/source/scale/velocity/anchor/touches/activeTouches

`[Canvas iOS][ControllerPinchTransform]` 同时记录相同的 `sessionID` 和 `seq`。

## 修改三：隔离 pinch 残余单指

涉及文件：

- `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`

### 修改前

recognizer 结束后立即执行普通 reconcile。只要 `activeTouchCount == 1`，就会调用 `beginPrimaryPointerTracking`，随后可能产生幽灵 tap 或 pan。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift（修改前）
// 函数名: handlePinch(_:)
// 功能注释: 修改前 pinch 结束后会立即把残余单指交给普通 pointer 状态机。
case .ended, .cancelled, .failed:
    let hadActiveZoomGesture = pinchGestureSession != nil
    pinchGestureSession = nil
    reconcileTouchInteractionState()
    if hadActiveZoomGesture {
        onZoomGestureEnded?()
    }
```

### 修改后

新增 `drainingPinchResidualTouches`。只要 pinch 结束时仍有 active touch，就保持 drain，直到触点全部离开。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: finishPinchGestureSession() / reconcileTouchInteractionState()
// 功能注释: drain 期间禁止 pointerDown、pointerMove、pointerUp 和 long press 接管。
private func finishPinchGestureSession() {
    let hadActiveZoomGesture = pinchGestureSession != nil
    pinchGestureSession = nil
    interactionState = activeTouchCount == 0
        ? .idle
        : .drainingPinchResidualTouches
    if hadActiveZoomGesture {
        onZoomGestureEnded?()
    }
}

private func reconcileTouchInteractionState() {
    if case .drainingPinchResidualTouches = interactionState {
        if activeTouchCount == 0 {
            interactionState = .idle
        }
        return
    }

    // 其余既有 pointer/context-menu/pinch 分支继续执行。
}
```

`trackedTouchForContextMenuPresentation()` 对 drain 状态返回 `nil`，避免残余触点触发 long press。

## 修改四：pinch camera refresh 按显示帧合并

涉及文件：

- `MyCanvas_Ver_0/Canvas/Core/CanvasRefreshFrameCoalescer.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`

### 修改前

每一个 pinch transform 都同步执行完整 canvas refresh。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift（修改前）
// 函数名: requestCanvasRefresh(reason:)
// 功能注释: 修改前输入事件与 snapshot/layer 刷新一一同步绑定。
private func requestCanvasRefresh(reason: String) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        pendingRefreshReason = reason
        return
    }

    pendingRefreshReason = nil
    performCanvasRefresh(reason: reason)
}
```

### 修改后

新增纯状态 coalescer，只保留当前 display frame 最新的 refresh reason 和 runtime generation。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRefreshFrameCoalescer.swift
// 类型名: CanvasRefreshFrameCoalescer
// 功能注释: 多个连续 pinch 请求只安排一次帧回调，并消费最新请求。
struct CanvasRefreshFrameCoalescer {
    struct Pending: Equatable {
        let reason: String
        let generation: UInt64
    }

    private(set) var pending: Pending?

    mutating func request(reason: String, generation: UInt64) -> Bool {
        let needsSchedule = pending == nil
        pending = Pending(reason: reason, generation: generation)
        return needsSchedule
    }

    mutating func takePending(currentGeneration: UInt64) -> Pending? {
        defer { pending = nil }
        guard pending?.generation == currentGeneration else {
            return nil
        }
        return pending
    }
}
```

controller 增加两种 delivery：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: requestCanvasRefresh(reason:delivery:)
// 功能注释: 只有 pinch camera 连续刷新走 CADisplayLink，其余刷新仍同步执行。
private enum CanvasRefreshDelivery {
    case synchronous
    case coalescedPinchCameraFrame
}

private func requestCanvasRefresh(
    reason: String,
    delivery: CanvasRefreshDelivery = .synchronous
) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        cancelPendingPinchRefresh()
        pendingRefreshReason = reason
        return
    }

    switch delivery {
    case .synchronous:
        cancelPendingPinchRefresh()
        performCanvasRefresh(reason: reason)
    case .coalescedPinchCameraFrame:
        let needsSchedule = pinchRefreshCoalescer.request(
            reason: reason,
            generation: canvasPresentationGeneration
        )
        if needsSchedule {
            schedulePinchRefreshDisplayLink()
        }
    }
}
```

补充生命周期处理：

- `handleZoom` 和 `handleDirectTouchTransform` 走 `.coalescedPinchCameraFrame`。
- 普通同步 refresh 会取消 pending pinch frame，并按最新 camera 立即渲染。
- controller `deinit` 会 invalidate display link。
- board load/new/restore/history runtime apply 前会递增 `canvasPresentationGeneration`。
- transition freeze 前会同步消费 pending pinch frame，避免 transition 捕获旧 layer 状态。

## 修改五：增加 canvas refresh 分阶段指标

涉及文件：

- `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`

### 修改前

direct touch 日志只有 controller 侧聚合 `refreshMs`，`RenderZoom` 只覆盖 zoom reason，无法区分 snapshot、viewport apply、minimap 和 accessory。

### 修改后

viewport apply 返回可见 item 与 layer 变更指标。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 类型名: CanvasViewportApplyMetrics
// 功能注释: 记录本次 viewport apply 的 item layer 数量和热路径耗时。
struct CanvasViewportApplyMetrics {
    let visibleItemCount: Int
    let createdItemLayerCount: Int
    let removedItemLayerCount: Int
    let updatedItemLayerCount: Int
    let itemLayerRefreshMs: TimeInterval
}
```

`performCanvasRefresh` 现在分别测量：

- `snapshotMs`
- `applyMs`
- `itemLayerMs`
- `miniMapMs`
- `accessoryMs`
- `totalMs`
- `sceneItems` / `visibleItems`
- `createdLayers` / `removedLayers` / `updatedLayers`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: performCanvasRefresh(reason:)
// 功能注释: 将原先聚合的 refresh 拆成可定位的阶段指标。
let snapshot = editorSession.makeCanvasSnapshot()
let afterSnapshotBuild = ProcessInfo.processInfo.systemUptime
let viewportApplyMetrics = canvasViewportView.apply(snapshot)
let afterViewportApply = ProcessInfo.processInfo.systemUptime
refreshMiniMap()
let afterMiniMapRefresh = ProcessInfo.processInfo.systemUptime
syncSelectionAccessoryPresentation()
let afterSelectionAccessorySync = ProcessInfo.processInfo.systemUptime
```

新的日志标签是 `[Canvas iOS][CameraGestureRefresh]`，同时覆盖 direct touch transform 与 zoom。

## 修改六：新增回归测试

新增：

- `MyCanvas_Ver_0Tests/CanvasDirectPinchContinuityTrackerTests.swift`
- `MyCanvas_Ver_0Tests/CanvasRefreshFrameCoalescerTests.swift`

连续性测试实际覆盖：

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasDirectPinchContinuityTrackerTests.swift
// 测试函数: testDroppingToOneTouchSuppressesTransformAndRequiresRebaseline()
// 功能注释: 锁定“2 根触点降为 1 根”不得产生 transform。
XCTAssertEqual(
    tracker.consume(
        makeSample(
            recognizerTouchCount: 1,
            touchIDs: [2],
            rawScale: 1,
            timestamp: 0.01,
            anchor: CGPoint(x: 180, y: 130)
        )
    ),
    .suppressed(.unstableTouchCount)
)
```

合帧测试实际覆盖：

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasRefreshFrameCoalescerTests.swift
// 测试函数: testMultipleRequestsScheduleOnceAndKeepLatestReason()
// 功能注释: 同一帧多次请求只首次要求 schedule，并消费最新 reason。
XCTAssertTrue(
    coalescer.request(reason: "first", generation: 4)
)
XCTAssertFalse(
    coalescer.request(reason: "latest", generation: 4)
)
XCTAssertEqual(
    coalescer.takePending(currentGeneration: 4)?.reason,
    "latest"
)
```

当前新增测试总计 7 条：

- tracker 4 条。
- coalescer 3 条。

## 验证结果

### 已通过

1. 定向单元测试：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：运行新增 tracker 与 coalescer 测试。
CanvasDirectPinchContinuityTrackerTests：4 条通过
CanvasRefreshFrameCoalescerTests：3 条通过
```

2. iOS Simulator build：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：最终日志字段调整后重新编译 iOS Simulator。
xcodebuild build ... -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO
结果：BUILD SUCCEEDED
```

3. iOS 真机 build：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：为连接的 iPhone 构建已签名 Debug app。
xcodebuild build ... -destination "id=00008140-000A55021893C01C"
结果：BUILD SUCCEEDED
```

4. 真机安装：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：安装当前修复版本，bundle ID 为 shaunyu.MyCanvas-Ver-0。
结果：App installed
```

5. 静态检查：

- IDE lint：本次 6 个 Swift 文件没有 lint error。
- `git diff --check`：通过。
- iOS build 只有 AppIntents metadata extraction skipped 提示，没有本次 Swift 编译 warning/error。

### 未完成或未通过

1. 修复版真机日志回归尚未完成。

尝试启动安装后的 app 时，设备处于锁定状态：

```text
# 真机启动结果
# 功能注释：如实记录未完成真机复测的直接原因。
Unable to launch shaunyu.MyCanvas-Ver-0 because the device was not, or could not be, unlocked.
```

因此当前还没有修复后的真机证据来确认：

- `touches=1` 只出现 `decision=suppressedUnstableTouchCount`。
- 同一 `sessionID/seq` 不再出现 `ControllerPinchTransform`。
- pinch 结束后不再出现幽灵 tap。
- `CameraGestureRefresh` 的 106–108ms 尖峰具体落在哪个阶段。

2. 完整 macOS test suite 未全绿。

新增的 7 条测试均通过，但完整 suite 中仍有未通过用例，涉及：

- `CanvasToolbarStateBuilderTests`
- `BoardHandDrawingStorageTests`
- `CanvasInputIndicatorQueueTests`

本次 changes 没有修改这些模块；本记录不把完整 suite 描述为通过，也没有擅自修改这些无关失败。

## 当前结论

- 代码层已经从“位移阈值规避”改为触点集合连续性合同，直接阻断已确认的 `2 -> 1` anchor 跳变。
- pinch 残余单指已与普通 pointer 生命周期隔离。
- pinch camera model 仍逐事件更新，但昂贵的 canvas refresh 改为每显示帧最多一次。
- 新日志已具备继续定位多元素 refresh 尖峰的字段。
- 最终真机行为验收仍需设备解锁后执行，当前不能如实标记为已完成。
- 本记录创建过程中没有继续修改任何 Swift 代码，也没有执行 git commit。
