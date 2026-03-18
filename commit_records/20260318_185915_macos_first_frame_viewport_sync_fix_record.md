# 20260318_185915_macos_first_frame_viewport_sync_fix_record

## 记录范围

- 记录目标：
  1. 修复 `macOS` 冷启动后首次交互仍使用 `camera.viewportSize == .zero` 的问题。
  2. 避免首次右键才触发第一轮有效 `viewportSize` 同步，导致可视区域跳变、命中上下文错位、菜单位置和内容不正确。
  3. 将 `macOS` 的视口同步入口收敛为“`viewport layout` 主驱动 + 生命周期兜底 + 刷新延迟消费”。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：
  - 之前为定位该问题而添加的完整日志链路说明
  - 其他 `iOS` / `ContextMenu` 策略变更
  - git commit

## 修改一：`viewport view` 在真实布局完成后主动回传有效尺寸

### 修改前

- `macOSCanvasViewportView.layout()` 只负责更新 layer frame 和打印日志。
- controller 只能在生命周期或输入事件里被动读取 `canvasViewportView.bounds.size`，没有像 `iOS` 那样的 `viewport size change` 主动通知。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名/类型名: macOSCanvasViewportView.layout()
// 功能说明: 修改前 layout 只更新图层 frame，不会把有效视口尺寸主动回传给 controller。
private var snapshot: CanvasRenderSnapshot = .empty
private var lastPrimaryPointerLocation: CGPoint?
var onPointerDown: ((CGPoint) -> Void)?
var onPointerMove: ((CGPoint, CGPoint) -> Void)?
var onPointerUp: ((CGPoint) -> Void)?
var onPointerCancel: (() -> Void)?
var onSecondaryClick: ((CGPoint) -> Void)?
var onPan: ((CGPoint) -> Void)?
var onZoom: ((CGFloat, CGPoint) -> Void)?

override func layout() {
    super.layout()
    print(
        "[Canvas macOS][ViewportLifecycle] " +
        "action=layout " +
        "viewBounds=\(macOSViewportDescribe(bounds)) " +
        "viewFrame=\(macOSViewportDescribe(frame)) " +
        "windowFrame=\(window.map { macOSViewportDescribe($0.frame) } ?? "nil")"
    )
    performWithoutLayerActions {
        updateLayerFrames()
    }
}
```

### 修改后

- 新增 `lastReportedViewportSize` 和 `onViewportSizeChange`。
- `layout()` 在拿到真实 `bounds.size` 后调用 `reportViewportSizeIfNeeded()`，仅在尺寸变化时回传。
- 这样 `macOS` 终于具备了和 `iOS` 对齐的首帧有效尺寸上报机制。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名/类型名: macOSCanvasViewportView.layout() / reportViewportSizeIfNeeded()
// 功能说明: 修改后 layout 会在真实布局完成后上报 viewport size，只在尺寸变化时通知 controller。
private var lastReportedViewportSize: CGSize?
private var snapshot: CanvasRenderSnapshot = .empty
private var lastPrimaryPointerLocation: CGPoint?
var onPointerDown: ((CGPoint) -> Void)?
var onPointerMove: ((CGPoint, CGPoint) -> Void)?
var onPointerUp: ((CGPoint) -> Void)?
var onPointerCancel: (() -> Void)?
var onSecondaryClick: ((CGPoint) -> Void)?
var onPan: ((CGPoint) -> Void)?
var onZoom: ((CGFloat, CGPoint) -> Void)?
var onViewportSizeChange: ((CGSize) -> Void)?

override func layout() {
    super.layout()
    print(
        "[Canvas macOS][ViewportLifecycle] " +
        "action=layout " +
        "viewBounds=\(macOSViewportDescribe(bounds)) " +
        "viewFrame=\(macOSViewportDescribe(frame)) " +
        "windowFrame=\(window.map { macOSViewportDescribe($0.frame) } ?? "nil")"
    )
    performWithoutLayerActions {
        updateLayerFrames()
    }
    reportViewportSizeIfNeeded()
}

private func reportViewportSizeIfNeeded() {
    let viewportSize = bounds.size
    guard viewportSize != lastReportedViewportSize else {
        return
    }

    lastReportedViewportSize = viewportSize
    onViewportSizeChange?(viewportSize)
}
```

### 影响

- 首次有效 `bounds.size` 不再只能等到第一次右键链路里才被发现。
- `camera.viewportSize` 可以在布局完成后立即进入正确同步路径，避免后续点击 / 右键基于错误世界坐标工作。

## 修改二：controller 收敛 `viewport sync` 入口，并保留生命周期兜底

### 修改前

- `setupCanvasViewport()` 只有输入事件绑定，没有 `viewportSize` 回调绑定。
- `viewDidAppear()` 只打印日志，不主动补一次同步兜底。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController.viewDidAppear() / setupCanvasViewport()
// 功能说明: 修改前 controller 没有接收 viewport size change 回调，只能依赖生命周期和输入事件被动读 bounds。
override func viewDidAppear() {
    super.viewDidAppear()
    print(
        "[Canvas macOS][ControllerLifecycle] " +
        "action=viewDidAppear " +
        "viewBounds=\(describe(rect: view.bounds)) " +
        "viewFrame=\(describe(rect: view.frame)) " +
        "windowFrame=\(view.window.map { describe(rect: $0.frame) } ?? "nil") " +
        "canvasHostBounds=\(describe(rect: canvasHostView.bounds)) " +
        "canvasHostFrame=\(describe(rect: canvasHostView.frame)) " +
        "canvasViewportBounds=\(describe(rect: canvasViewportView.bounds)) " +
        "canvasViewportFrame=\(describe(rect: canvasViewportView.frame)) " +
        "cameraViewportSize=\(describe(size: camera.viewportSize))"
    )
}

private func setupCanvasViewport() {
    canvasViewportView.onPointerDown = { [weak self] location in
        self?.handlePrimaryPointerDown(at: location)
    }
    canvasViewportView.onPointerMove = { [weak self] location, previousLocation in
        self?.handlePrimaryPointerMove(to: location, from: previousLocation)
    }
    canvasViewportView.onPointerUp = { [weak self] location in
        self?.handlePrimaryPointerUp(at: location)
    }
    canvasViewportView.onPointerCancel = { [weak self] in
        self?.handlePrimaryPointerCancel()
    }
    canvasViewportView.onSecondaryClick = { [weak self] location in
        self?.handleSecondaryClick(at: location)
    }
    canvasViewportView.onPan = { [weak self] translation in
        self?.handleIndirectPan(translation)
    }
    canvasViewportView.onZoom = { [weak self] scaleDelta, anchor in
        self?.handleZoom(scaleDelta, around: anchor)
    }

    installCanvasContentView(canvasViewportView)
    refreshCanvas(reason: "initial setup")
}
```

### 修改后

- `setupCanvasViewport()` 新增 `onViewportSizeChange` 绑定，把 layout 后的有效尺寸直接送进同步入口。
- `viewDidAppear()` 追加 `updateCameraViewportSizeIfNeeded(trigger: "viewDidAppear")` 作为生命周期兜底。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController.viewDidAppear() / setupCanvasViewport()
// 功能说明: 修改后 controller 以 viewport layout 回调为主驱动，同步保留 viewDidAppear 的生命周期兜底。
override func viewDidAppear() {
    super.viewDidAppear()
    print(
        "[Canvas macOS][ControllerLifecycle] " +
        "action=viewDidAppear " +
        "viewBounds=\(describe(rect: view.bounds)) " +
        "viewFrame=\(describe(rect: view.frame)) " +
        "windowFrame=\(view.window.map { describe(rect: $0.frame) } ?? "nil") " +
        "canvasHostBounds=\(describe(rect: canvasHostView.bounds)) " +
        "canvasHostFrame=\(describe(rect: canvasHostView.frame)) " +
        "canvasViewportBounds=\(describe(rect: canvasViewportView.bounds)) " +
        "canvasViewportFrame=\(describe(rect: canvasViewportView.frame)) " +
        "cameraViewportSize=\(describe(size: camera.viewportSize))"
    )
    updateCameraViewportSizeIfNeeded(trigger: "viewDidAppear")
}

private func setupCanvasViewport() {
    canvasViewportView.onPointerDown = { [weak self] location in
        self?.handlePrimaryPointerDown(at: location)
    }
    canvasViewportView.onPointerMove = { [weak self] location, previousLocation in
        self?.handlePrimaryPointerMove(to: location, from: previousLocation)
    }
    canvasViewportView.onPointerUp = { [weak self] location in
        self?.handlePrimaryPointerUp(at: location)
    }
    canvasViewportView.onPointerCancel = { [weak self] in
        self?.handlePrimaryPointerCancel()
    }
    canvasViewportView.onSecondaryClick = { [weak self] location in
        self?.handleSecondaryClick(at: location)
    }
    canvasViewportView.onPan = { [weak self] translation in
        self?.handleIndirectPan(translation)
    }
    canvasViewportView.onZoom = { [weak self] scaleDelta, anchor in
        self?.handleZoom(scaleDelta, around: anchor)
    }
    canvasViewportView.onViewportSizeChange = { [weak self] viewportSize in
        self?.syncCameraViewportSizeIfNeeded(
            viewportSize,
            source: "viewport layout"
        )
    }

    installCanvasContentView(canvasViewportView)
    refreshCanvas(reason: "initial setup")
}
```

### 影响

- `macOS` 的 `camera viewport sync` 不再依赖“用户先触发某个输入事件”。
- 即便布局时序有波动，`viewDidAppear` 仍能补一次兜底同步，降低冷启动阶段漏同步的概率。

## 修改三：同步函数支持延迟刷新消费，不再让首次右键承担“首刷”职责

### 修改前

- `updateCameraViewportSizeIfNeeded(trigger:)` 直接读取当前 `canvasViewportView.bounds.size`。
- 它只有在 `sizeChanged` 或 `didConfigureBoardState` 时才立即 `refreshCanvas(...)`。
- 如果最早那次 `refreshCanvas(reason: "initial setup")` 发生在 `viewportSize == .zero` 阶段，后续不会保留“待刷新原因”，真正的有效快照只能等下一次交互触发。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController.updateCameraViewportSizeIfNeeded(trigger:)
// 功能说明: 修改前同步函数没有 deferred refresh 概念，首次有效 viewport 出现时无法主动补刷之前被错误时序吞掉的 refresh。
private func updateCameraViewportSizeIfNeeded(
    trigger: String = "unspecified"
) {
    let cameraBeforeSync = camera
    let snapshotBeforeSync = lastRenderSnapshot
    let viewportSize = canvasViewportView.bounds.size
    print(
        "[Canvas macOS][ViewportSync] " +
        "trigger=\(trigger) " +
        "phase=begin " +
        "viewBoundsSize=\(describe(size: view.bounds.size)) " +
        "canvasHostBounds=\(describe(rect: canvasHostView.bounds)) " +
        "canvasViewportBounds=\(describe(rect: canvasViewportView.bounds)) " +
        "canvasViewportFrame=\(describe(rect: canvasViewportView.frame)) " +
        "cameraViewportSizeBefore=\(describe(size: cameraBeforeSync.viewportSize)) " +
        "snapshotViewportBoundsBefore=\(describe(rect: snapshotBeforeSync.viewportBounds))"
    )
    guard viewportSize.width > 0, viewportSize.height > 0 else {
        print(/* skipEmptyViewport */)
        return
    }

    let sizeChanged = viewportSize != camera.viewportSize
    if sizeChanged {
        camera.setViewportSize(viewportSize)
    }

    let didConfigureBoardState = configureBoardStateIfNeeded(for: viewportSize)
    guard sizeChanged || didConfigureBoardState else {
        print(/* noChange */)
        return
    }

    refreshCanvas(
        reason: "viewport sync trigger=\(trigger) sizeChanged=\(sizeChanged) didConfigureBoardState=\(didConfigureBoardState)"
    )
}
```

### 修改后

- `updateCameraViewportSizeIfNeeded(trigger:)` 变成薄包装，把实际同步逻辑收敛到 `syncCameraViewportSizeIfNeeded(_:source:)`。
- 新增 `pendingRefreshReason`，把“之前因为零尺寸而无法执行的 refresh”挂起。
- 一旦 `viewport layout` 或生命周期拿到有效尺寸，`syncCameraViewportSizeIfNeeded` 会优先 `flush deferred refresh`，不再等首次右键去顺带修正整条链路。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController.updateCameraViewportSizeIfNeeded(trigger:) / syncCameraViewportSizeIfNeeded(_:source:)
// 功能说明: 修改后同步入口支持 deferred refresh flush，首次有效 viewport 出现时就能补发正确 snapshot。
private var pendingRefreshReason: String?

private func updateCameraViewportSizeIfNeeded(
    trigger: String = "unspecified"
) {
    syncCameraViewportSizeIfNeeded(
        canvasViewportView.bounds.size,
        source: trigger
    )
}

private func syncCameraViewportSizeIfNeeded(
    _ viewportSize: CGSize,
    source: String
) {
    let cameraBeforeSync = camera
    let snapshotBeforeSync = lastRenderSnapshot
    print(
        "[Canvas macOS][ViewportSync] " +
        "trigger=\(source) " +
        "phase=begin " +
        "viewBoundsSize=\(describe(size: view.bounds.size)) " +
        "canvasHostBounds=\(describe(rect: canvasHostView.bounds)) " +
        "canvasViewportBounds=\(describe(rect: canvasViewportView.bounds)) " +
        "canvasViewportFrame=\(describe(rect: canvasViewportView.frame)) " +
        "cameraViewportSizeBefore=\(describe(size: cameraBeforeSync.viewportSize)) " +
        "snapshotViewportBoundsBefore=\(describe(rect: snapshotBeforeSync.viewportBounds))"
    )
    guard isRenderable(viewportSize: viewportSize) else {
        print(/* skipEmptyViewport */)
        return
    }

    let sizeChanged = viewportSize != camera.viewportSize
    if sizeChanged {
        camera.setViewportSize(viewportSize)
    }

    let didConfigureBoardState = configureBoardStateIfNeeded(for: viewportSize)
    let deferredReason = pendingRefreshReason
    guard sizeChanged || didConfigureBoardState || deferredReason != nil else {
        print(/* noChange */)
        return
    }

    pendingRefreshReason = nil

    if let deferredReason {
        performCanvasRefresh(
            reason: "flush deferred refresh (\(deferredReason)) after \(source) size=\(describe(size: viewportSize))"
        )
    } else {
        performCanvasRefresh(
            reason: "viewport sync trigger=\(source) sizeChanged=\(sizeChanged) didConfigureBoardState=\(didConfigureBoardState)"
        )
    }
}
```

### 影响

- 首帧有效视口一旦出现，就会把之前因为零尺寸错过的 refresh 补回来。
- `first right click` 不再承担“第一次把 camera / snapshot / hit test 拉回正确状态”的副作用角色。

## 修改四：`refreshCanvas` 改为可延迟消费，杜绝 zero-viewport snapshot 继续流入后续链路

### 修改前

- `refreshCanvas(reason:)` 每次都会直接生成 `CanvasRenderSnapshot` 并下发到 viewport 和 minimap。
- 这意味着当 `camera.viewportSize` 仍为 `.zero` 时，仍然会产出错误快照，并把错误状态继续传播给渲染、命中、菜单链路。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController.refreshCanvas(reason:)
// 功能说明: 修改前 refreshCanvas 不校验 viewport 是否可渲染，零尺寸状态也会直接产出 snapshot。
private func refreshCanvas(reason: String = "unspecified") {
    let snapshot = editorSession.makeCanvasSnapshot()
    logCanvasState(reason: reason, snapshot: snapshot)
    canvasViewportView.apply(snapshot)
    refreshMiniMap()
}
```

### 修改后

- `refreshCanvas(reason:)` 先尝试从当前 `bounds` 补同步一次 `camera.viewportSize`。
- 若仍不可渲染，则记录 `pendingRefreshReason` 并打印 `phase=deferred` 日志，直接返回。
- 真正的快照生成被拆到 `performCanvasRefresh(reason:)`，只在存在有效 viewport 时执行。
- 新增 `hasRenderableViewportSize`、`isRenderable(viewportSize:)` 和 `logDeferredCanvasRefresh(...)` 辅助方法。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController.refreshCanvas(reason:) / syncCameraViewportSizeFromCurrentBoundsIfPossible() / performCanvasRefresh(reason:)
// 功能说明: 修改后 refreshCanvas 只有在 viewport 可渲染时才真正生成 snapshot，否则把 refresh 延迟到首个有效 viewport 出现时消费。
private func refreshCanvas(reason: String = "unspecified") {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        pendingRefreshReason = reason
        logDeferredCanvasRefresh(
            reason: reason,
            actualViewportSize: canvasViewportView.bounds.size
        )
        return
    }

    pendingRefreshReason = nil
    performCanvasRefresh(reason: reason)
}

private func syncCameraViewportSizeFromCurrentBoundsIfPossible() {
    let viewportSize = canvasViewportView.bounds.size
    guard
        isRenderable(viewportSize: viewportSize),
        viewportSize != camera.viewportSize
    else {
        return
    }

    camera.setViewportSize(viewportSize)
    _ = configureBoardStateIfNeeded(for: viewportSize)
}

private func performCanvasRefresh(reason: String) {
    let snapshot = editorSession.makeCanvasSnapshot()
    logCanvasState(reason: reason, snapshot: snapshot)
    canvasViewportView.apply(snapshot)
    refreshMiniMap()
}

private var hasRenderableViewportSize: Bool {
    isRenderable(viewportSize: camera.viewportSize)
}

private func isRenderable(viewportSize: CGSize) -> Bool {
    viewportSize.width > 0 && viewportSize.height > 0
}

private func logDeferredCanvasRefresh(
    reason: String,
    actualViewportSize: CGSize
) {
    print(
        "[Canvas macOS][CanvasRefresh] " +
        "phase=deferred " +
        "reason=\(reason) " +
        "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
        "viewBoundsSize=\(describe(size: actualViewportSize))"
    )
}
```

### 影响

- 初始 `refreshCanvas(reason: "initial setup")` 即使发生在布局尚未稳定之前，也不会再产出错误 snapshot。
- 这次修复不是“把第一次右键里的偏移结果再纠正回来”，而是从根因上阻止 zero-viewport 状态进入后续链路。

## 验证结果

- 已对本次修改文件执行 `ReadLints`，无新增诊断。
- 已通过 `macOS` Debug 编译。
- 已通过 `iOS Simulator` Debug 编译。
- 本轮交互中，问题现象已按用户反馈确认恢复正常。

## 最终结论

- 根因不是右键菜单本身，而是 `macOS` 平台层在冷启动阶段没有像 `iOS` 一样及时回传真实 `viewportSize`。
- 本次修复把 `macOS` 的首帧视口同步机制对齐到 `iOS`：`viewport layout` 主驱动、生命周期兜底、`refreshCanvas` 延迟消费。
- 因此首次左键 / 右键不再承担“第一次把 camera 和 snapshot 拉回正确状态”的副作用职责。
