# 20260522_160023_CST_ios_direct_touch_pinch_transform_record

## 记录范围

- 记录内容：
  1. 为 `CanvasCamera` 新增原子 `transform(by:around:translatingBy:)`，把双指中心位移与缩放同帧收口到相机层。
  2. 将 `iOSCanvasViewportView.handlePinch(_:)` 的 direct touch 分支从“只派发缩放”改为“派发平移 + 缩放 + anchor 的 transform delta”，解决 iOS 上双指缩放后不抬手改成双指平移时画布不跟随的问题。
  3. 在 `iOSViewController` 中新增 `handleDirectTouchTransform(_:)`，并将 pinch 生命周期的脏标记、autosave 原因和日志时间基线统一到整个 pinch 手势，而不再只覆盖 zoom-only 路径。
  4. 新增 `CanvasCameraTransformTests`，锁定纯平移、平移+缩放同帧、无效缩放回退为纯平移三条几何合同。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasCamera.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0Tests/CanvasCameraTransformTests.swift`
- 参考现状：
  - 生成本记录前，执行 `date '+%Y%m%d_%H%M%S_CST'` 得到时间戳：`20260522_160023_CST`，本文件按该时间戳命名。
  - 生成本记录前，执行 `git diff --stat -- "MyCanvas_Ver_0/Canvas/Core/CanvasCamera.swift" "MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift" "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift"`，结果为：`3 files changed, 164 insertions(+), 14 deletions(-)`。
  - 生成本记录前，执行 `git status --short -- "MyCanvas_Ver_0/Canvas/Core/CanvasCamera.swift" "MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift" "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" "MyCanvas_Ver_0Tests/CanvasCameraTransformTests.swift"`，结果为：`M MyCanvas_Ver_0/Canvas/Core/CanvasCamera.swift`、`M MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`、`M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`、`?? MyCanvas_Ver_0Tests/CanvasCameraTransformTests.swift`。
  - 生成本记录前，执行 `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS,arch=arm64' -only-testing:MyCanvas_Ver_0Tests/CanvasCameraTransformTests`，结果为：`CanvasCameraTransformTests` 共 3 条用例通过。
- 本记录不包含：
  - iPhone / iPad 真机上的手势回归截图或录屏。
  - `CanvasRawInputIntent`、输入指示器文案或统计语义的进一步扩展。
  - `macOS` 侧的对称手势改造。

## 当前 changes 摘要

- `CanvasCamera` 现在可以在同一帧里统一消费 viewport 平移和 anchor 缩放，controller 不再需要自己拼接两段几何逻辑。
- `iOSCanvasViewportView` 为 direct touch pinch 新增 `CanvasDirectTouchTransformDelta` 和 `onDirectTouchTransform`，并在 `handlePinch(_:)` 中根据双指中心点前后位置计算 `translationInViewport`。
- `iOSViewController` 新增 `handleDirectTouchTransform(_:)` 和 `logDirectTouchTransformDispatch(...)`，并将 `didMutateCameraDuringPinchGesture` / `lastPinchDispatchTimestamp` 收口为整个 pinch 手势的公共状态。
- `CanvasCameraTransformTests` 新增 3 条回归测试，用数学合同验证这次根因修复没有退化成只修表象。

## 修改一：为 `CanvasCamera` 增加原子 transform 入口

### 修改前

- 相机层只暴露分离的 `pan(by:)` 和 `zoom(by:around:)`。
- controller 如果想表达“同一帧既发生双指中心位移、又发生缩放”，只能在控制器层手工拼接调用顺序。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasCamera.swift（修改前）
// 函数名: pan(by:) / zoom(by:around:)
// 功能说明: 修改前相机层只有分离的平移与缩放入口，没有原子 transform API 承接同一帧双指变换。
mutating func pan(by deltaInViewport: CGPoint) {
    center.x -= deltaInViewport.x / zoomScale
    center.y -= deltaInViewport.y / zoomScale
}

mutating func zoom(by scaleDelta: CGFloat, around anchorInViewport: CGPoint) {
    zoom(to: zoomScale * scaleDelta, around: anchorInViewport)
}
```

### 修改后

- 新增 `transform(by:around:translatingBy:)`。
- 该函数会先消费双指中心位移，再围绕当前 `anchorInViewport` 做缩放。
- 对无效 `scaleDelta` 做 `1` 的降级处理，保证“纯两指平移”不会被错误拦截。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasCamera.swift
// 函数名: transform(by:around:translatingBy:)
// 功能说明: 修改后相机层可以用一个统一入口承接“同一帧同时平移和缩放”的双指变换，controller 不再自己拆分几何步骤。
mutating func transform(
    by scaleDelta: CGFloat,
    around anchorInViewport: CGPoint,
    translatingBy translationInViewport: CGPoint
) {
    if translationInViewport != .zero {
        pan(by: translationInViewport)
    }

    let resolvedScaleDelta =
        scaleDelta.isFinite && scaleDelta > 0 ? scaleDelta : 1
    if resolvedScaleDelta != 1 {
        zoom(by: resolvedScaleDelta, around: anchorInViewport)
    }
}
```

## 修改二：`iOSCanvasViewportView` 将 direct touch pinch 从 zoom-only 改为 transform delta

### 修改前

- viewport 只有 `onPan` 和 `onZoom` 两类高层回调。
- direct touch pinch 没有独立的数据载荷，双指平移只能被迫落在“没有缩放输出时就什么都不发”的空档里。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift（修改前）
// 函数名: 属性声明区
// 功能说明: 修改前 viewport 没有 direct touch transform 的独立载荷和回调，只能把两指手势拆成 indirect pan 或 zoom。
var onPointerCancel: (() -> Void)?
var onLongPress: ((CGPoint) -> Void)?
var onPan: ((CGPoint, CGPoint) -> Void)?
var onZoom: ((CGFloat, CGPoint) -> Void)?
var onZoomGestureBegan: (() -> Void)?
var onZoomGestureEnded: (() -> Void)?
```

### 修改后

- 新增 `CanvasDirectTouchTransformDelta`，显式携带 `translationInViewport`、`scaleDelta` 和 `anchorInViewport`。
- 新增 `onDirectTouchTransform`，把 direct touch pinch 和 indirect pan / zoom-only 分开。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: CanvasDirectTouchTransformDelta / 属性声明区
// 功能说明: 修改后 viewport 为 direct touch pinch 单独定义 transform 载荷，并暴露专用回调，避免语义混入 scroll 或 zoom-only 通道。
struct CanvasDirectTouchTransformDelta: Equatable {
    let translationInViewport: CGPoint
    let scaleDelta: CGFloat
    let anchorInViewport: CGPoint
}

var onPan: ((CGPoint, CGPoint) -> Void)?
var onDirectTouchTransform: ((CanvasDirectTouchTransformDelta) -> Void)?
var onZoom: ((CGFloat, CGPoint) -> Void)?
```

### 修改前

- `handlePinch(_:)` 的 `.changed` 分支只计算 `normalizedPinchScaleDelta(...)`。
- 无论是 direct touch 还是 `indirectMirroringLike`，最后都只有 `onZoom?(scaleDelta, anchor)` 这一条出口。
- 结果是：当双指中心点在移动，但缩放量接近 `1` 时，画布不会收到任何平移命令。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift（修改前）
// 函数名: handlePinch(_:)
// 功能说明: 修改前 pinch changed 分支只派发缩放，不派发双指中心点位移，因此“缩放中改成双指平移”不会驱动画布跟随。
let rawScaleDelta = rawScale / max(session.lastRawScale, 0.0001)
let dt = max(now - session.lastTimestamp, 0)
session.lastRawScale = rawScale
session.lastTimestamp = now
session.lastAnchor = anchor
pinchGestureSession = session

guard let scaleDelta = normalizedPinchScaleDelta(
    rawDelta: rawScaleDelta,
    source: session.source,
    dt: dt
) else {
    return
}

onZoom?(scaleDelta, anchor)
```

### 修改后

- 在更新 `session.lastAnchor` 之前，先保存 `previousAnchor`。
- 对 direct touch 分支，新增 `translation = anchor - previousAnchor` 的计算。
- 即使 `normalizedScaleDelta` 被 deadzone 归零，也会以 `scaleDelta = 1` 的形式继续派发 direct touch transform。
- `indirectMirroringLike` 仍保持原有 zoom-only 行为，不把这次 iOS 触屏修复扩散到 Mirroring 输入链路。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: handlePinch(_:)
// 功能说明: 修改后 direct touch pinch 会同时派发双指中心位移与缩放；即使缩放量落入 deadzone，也能继续输出纯两指平移。
let previousAnchor = session.lastAnchor
let rawScaleDelta = rawScale / max(session.lastRawScale, 0.0001)
let dt = max(now - session.lastTimestamp, 0)
session.lastRawScale = rawScale
session.lastTimestamp = now
session.lastAnchor = anchor
pinchGestureSession = session

let normalizedScaleDelta = normalizedPinchScaleDelta(
    rawDelta: rawScaleDelta,
    source: session.source,
    dt: dt
)

switch session.source {
case .directTouch:
    let translation = CGPoint(
        x: anchor.x - previousAnchor.x,
        y: anchor.y - previousAnchor.y
    )
    let scaleDelta = normalizedScaleDelta ?? 1
    guard translation != .zero || scaleDelta != 1 else {
        return
    }
    onDirectTouchTransform?(
        CanvasDirectTouchTransformDelta(
            translationInViewport: translation,
            scaleDelta: scaleDelta,
            anchorInViewport: anchor
        )
    )
case .indirectMirroringLike:
    guard let scaleDelta = normalizedScaleDelta else {
        return
    }
    onZoom?(scaleDelta, anchor)
}
```

## 修改三：`iOSViewController` 新增 direct touch transform 消费链路，并统一 pinch 生命周期状态

### 修改前

- `setupCanvasViewport()` 只接 `onPan` 和 `onZoom`。
- 生命周期状态和 autosave 原因名也都偏向 zoom-only：`lastZoomDispatchTimestamp`、`didMutateCameraDuringZoomGesture`、`"zoom canvas"`。
- 这意味着 controller 只能在“确实发生缩放”时标记相机发生变化，无法覆盖“纯两指平移但不抬手”的那部分 pinch 手势。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift（修改前）
// 函数名: setupCanvasViewport() / handleZoomGestureBegan() / handleZoomGestureEnded()
// 功能说明: 修改前 controller 只消费 indirect pan 和 zoom，pinch 生命周期状态与 autosave 语义都围绕 zoom-only 路径命名。
private var lastZoomDispatchTimestamp: TimeInterval?
private var didMutateCameraDuringZoomGesture = false

canvasViewportView.onPan = { [weak self] translation, location in
    self?.observeContinuousRawInput(
        .pointerScrollGesture,
        sourceDescription: RawInputDeliverySource.scrollGesture.debugName,
        kind: .scroll
    )
    self?.handleIndirectPan(translation, at: location)
}
canvasViewportView.onZoom = { [weak self] scaleDelta, anchor in
    self?.handleZoom(scaleDelta, around: anchor)
}

private func handleZoomGestureBegan() {
    didMutateCameraDuringZoomGesture = false
}

private func handleZoomGestureEnded() {
    guard didMutateCameraDuringZoomGesture else {
        return
    }

    scheduleAutosave(
        reason: "zoom canvas",
        updateKind: .viewStateOnly
    )
    didMutateCameraDuringZoomGesture = false
}
```

### 修改后

- `setupCanvasViewport()` 新增 `onDirectTouchTransform` 接线。
- 将生命周期状态收口为 `lastPinchDispatchTimestamp` 和 `didMutateCameraDuringPinchGesture`。
- 手势收尾 autosave 原因从 `"zoom canvas"` 改为 `"pinch canvas"`，明确覆盖缩放和平移混合手势。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: setupCanvasViewport() / handleZoomGestureBegan() / handleZoomGestureEnded()
// 功能说明: 修改后 controller 在 pinch 生命周期内同时覆盖 direct touch transform 与 zoom-only 路径，autosave 语义提升为整个 pinch 手势级别。
private var lastPinchDispatchTimestamp: TimeInterval?
private var didMutateCameraDuringPinchGesture = false

canvasViewportView.onDirectTouchTransform = { [weak self] delta in
    guard self?.isTransitionInteractionFrozen == false else {
        return
    }
    self?.handleDirectTouchTransform(delta)
}

private func handleZoomGestureBegan() {
    didMutateCameraDuringPinchGesture = false
}

private func handleZoomGestureEnded() {
    guard didMutateCameraDuringPinchGesture else {
        return
    }

    scheduleAutosave(
        reason: "pinch canvas",
        updateKind: .viewStateOnly
    )
    didMutateCameraDuringPinchGesture = false
}
```

### 修改前

- controller 没有 `handleDirectTouchTransform(_:)`。
- 也没有一套专门的 pinch transform 诊断日志来记录平移量、缩放量、anchor 和相机中心变化。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift（修改前）
// 函数名: handleDirectTouchTransform(_:) / logDirectTouchTransformDispatch(...)
// 功能说明: 修改前 controller 没有 direct touch transform 的消费入口和对应日志，双指中心位移无法进入相机更新链路。
// 该函数不存在。
```

### 修改后

- 新增 `handleDirectTouchTransform(_:)`，统一走 `camera.transform(...)`。
- 新增 `logDirectTouchTransformDispatch(...)`，并与 `logZoomDispatch(...)` 共用 `lastPinchDispatchTimestamp` 这一套时间基线。
- `didMutateCameraDuringPinchGesture` 会在纯平移、纯缩放、平移+缩放三种场景下都被正确置位。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handleDirectTouchTransform(_:) / logDirectTouchTransformDispatch(...)
// 功能说明: 修改后 controller 用统一的相机 transform API 消费 direct touch pinch，并新增与之对应的性能/几何日志。
private func handleDirectTouchTransform(_ delta: CanvasDirectTouchTransformDelta) {
    let eventTime = ProcessInfo.processInfo.systemUptime
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput(
            "direct touch transform translation=\(describe(point: delta.translationInViewport)) " +
                "scaleDelta=\(String(format: "%.4f", delta.scaleDelta)) " +
                "anchor=\(describe(point: delta.anchorInViewport))"
        )
        return
    }

    let cameraCenterBeforeTransform = camera.center
    let zoomBefore = camera.zoomScale
    camera.transform(
        by: delta.scaleDelta,
        around: delta.anchorInViewport,
        translatingBy: delta.translationInViewport
    )

    didMutateCameraDuringPinchGesture = true
    // ...
}

private func logDirectTouchTransformDispatch(
    eventTime: TimeInterval,
    translation: CGPoint,
    scaleDelta: CGFloat,
    anchor: CGPoint,
    cameraCenterBeforeTransform: CGPoint,
    cameraCenterAfterTransform: CGPoint,
    zoomBefore: CGFloat,
    zoomAfter: CGFloat,
    applyCostMs: TimeInterval,
    refreshCostMs: TimeInterval,
    autosaveCostMs: TimeInterval,
    totalCostMs: TimeInterval
) {
    let deltaSinceLastEventMs =
        lastPinchDispatchTimestamp.map { (eventTime - $0) * 1000 } ?? 0
    lastPinchDispatchTimestamp = eventTime
    // ...
}
```

## 修改四：新增 `CanvasCameraTransformTests` 锁定几何合同

### 修改前

- 仓库中没有专门验证 direct touch pinch transform 几何合同的测试文件。
- 这意味着“代码能编译”并不能证明双指中心点保持在当前 anchor 下方的数学约束真的成立。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasCameraTransformTests.swift（修改前）
// 函数名: N/A
// 功能说明: 修改前仓库中不存在专门覆盖双指 transform 几何合同的测试文件。
// 该文件不存在。
```

### 修改后

- 新增 `CanvasCameraTransformTests.swift`。
- 三条测试分别覆盖：
  - 纯平移时，上一帧 anchor 下方的世界点应移动到当前 anchor；
  - 平移+缩放同帧时，上一帧 anchor 下方的世界点仍应稳定落在当前 anchor；
  - 无效 `scaleDelta` 时，应退化为纯平移，不改变 `zoomScale`。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasCameraTransformTests.swift
// 函数名: testTransformWithPureTranslationMovesPreviousAnchorToCurrentAnchor() / testTransformWithTranslationAndScaleKeepsPreviousAnchorUnderCurrentAnchor() / testTransformWithInvalidScaleFallsBackToPanOnly()
// 功能说明: 修改后新增 3 条回归测试，锁定 transform API 的平移、缩放与非法 scale 降级合同。
final class CanvasCameraTransformTests: XCTestCase {
    func testTransformWithPureTranslationMovesPreviousAnchorToCurrentAnchor() {
        var camera = makeTransformTestCamera()
        let previousAnchor = CGPoint(x: 110, y: 90)
        let currentAnchor = CGPoint(x: 146, y: 128)
        let worldUnderPreviousAnchor = camera.viewportToWorld(previousAnchor)

        camera.transform(
            by: 1,
            around: currentAnchor,
            translatingBy: CGPoint(
                x: currentAnchor.x - previousAnchor.x,
                y: currentAnchor.y - previousAnchor.y
            )
        )

        XCTAssertEqual(camera.zoomScale, 2, accuracy: 0.0001)
        assertPointEqual(
            camera.worldToViewport(worldUnderPreviousAnchor),
            currentAnchor
        )
    }

    func testTransformWithTranslationAndScaleKeepsPreviousAnchorUnderCurrentAnchor() {
        var camera = makeTransformTestCamera()
        let previousAnchor = CGPoint(x: 120, y: 104)
        let currentAnchor = CGPoint(x: 168, y: 126)
        let worldUnderPreviousAnchor = camera.viewportToWorld(previousAnchor)

        camera.transform(
            by: 1.5,
            around: currentAnchor,
            translatingBy: CGPoint(
                x: currentAnchor.x - previousAnchor.x,
                y: currentAnchor.y - previousAnchor.y
            )
        )

        XCTAssertEqual(camera.zoomScale, 3, accuracy: 0.0001)
        assertPointEqual(
            camera.worldToViewport(worldUnderPreviousAnchor),
            currentAnchor
        )
    }
}
```

## 本阶段结果

- iOS 上 direct touch pinch 现在不再是 zoom-only 语义；当双指中心点移动但缩放量接近 `1` 时，画布也会继续收到平移命令。
- 相机层、viewport 层、controller 层的职责边界已经重新收口：viewport 负责提取 transform delta，controller 负责消费，camera 负责执行原子几何变换。
- 当前 `git diff --stat` 中的 3 个 tracked 文件和 `git status --short` 中新增的 1 个测试文件，已经全部在本记录中逐项说明，没有直接贴原始 `git diff`。
- 几何层验证已通过：`CanvasCameraTransformTests` 的 3 条用例在 `My Mac` 目标上执行成功。
