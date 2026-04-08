# 20260408_143604_toolbar_transition_phase4_layout_reconcile_record

## 记录范围

- 记录内容：`Phase 4` 的布局竞争与 completion 收口。
- 涉及业务代码文件：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 写入本记录前的代码状态依据：
  - `git status --short` 仅显示两份已修改文件：
    - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
    - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `git diff -- "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"` 显示本次改动只集中在双端控制器，主题是：
    - 收口 `viewDidLayout*` 对动画轨迹的打断
    - 收口 `updateChromeOverlayLayout()` 的重入
    - 让 `updateContextMenuPresentation()` 在过渡期间改用冻结的 chrome layout context，而不是再次重解 steady layout
- 本记录文件是随后新增的说明材料，不属于本次业务代码改动本身。
- 本记录不包含：
  - `Phase 0` 的共享过渡 contract / geometry
  - `Phase 1` 的 Host 改造
  - `Phase 2` / `Phase 3` 的双端基础动画接通
  - `Phase 5` 的最终验收与参数微调
  - git commit / push

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数名/命令名: date
# 功能说明: 生成本记录文件名使用的时间戳前缀。
date +"%Y%m%d_%H%M%S"
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git status / git diff
# 功能说明: 在写入本记录前确认当前工作区只包含 Phase 4 的双端控制器改动，并据此抽取本次“修改前 / 修改后”的真实基线。
git status --short
git diff -- "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"
```

## 修改一：`updateContextMenuPresentation()` 不再在动画期间重解 steady overlay layout

### 修改前

- 双端控制器的 `updateContextMenuPresentation()` 都直接调用 `performOverlayLayoutPass()`。
- 这会在工具栏过渡期间再次重解 toolbar placement、miniMap frame 和 chrome blockers。
- 对 `Phase 4` 来说，这正是要收口的竞争源之一：context menu 的展示刷新会顺便把正在跑动画的工具栏轨迹重新带回 steady layout。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: updateContextMenuPresentation()
// 功能说明: 修改前 iOS 侧每次刷新 context menu 都会直接重跑 performOverlayLayoutPass()，动画期间会重算 toolbar steady frame。
private func updateContextMenuPresentation() {
    guard isViewLoaded else {
        return
    }

    let layoutContext = performOverlayLayoutPass()
    if let contextMenuState {
        logContextMenuPresentation(
            state: contextMenuState,
            layoutContext: layoutContext
        )
    }
    contextMenuHostView.apply(
        state: contextMenuState,
        layoutContext: layoutContext
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: updateContextMenuPresentation()
// 功能说明: 修改前 macOS 侧同样会在 context menu 刷新时直接走 performOverlayLayoutPass()，动画中的 toolbar 几何会被 steady layout 再解一次。
private func updateContextMenuPresentation() {
    guard isViewLoaded else {
        return
    }

    let layoutContext = performOverlayLayoutPass()
    if let contextMenuState {
        logContextMenuPresentation(
            state: contextMenuState,
            layoutContext: layoutContext
        )
    }
    contextMenuHostView.apply(
        state: contextMenuState,
        layoutContext: layoutContext
    )
}
```

### 修改后

- 双端都新增：
  - `contextMenuLayoutContextForCurrentChromeState()`
  - `transitionContextMenuLayoutContext(for:)`
- steady-state 仍走 `performOverlayLayoutPass()`。
- 只有在 `toolbarTransitionRuntime` 存在时，才改为用当前 transition runtime 推导冻结的 `CanvasChromeLayoutContext`：
  - toolbar blocker 不再来自 steady placement solver，而是来自当前动画帧
  - `toolbarMeasuredSize` 固定使用 `visibleFrame.size`
  - `miniMapFrame` 直接复用当前 `miniMapMountView.frame`
- 这样 context menu 仍能更新布局，但不会再把工具栏轨迹拉回 steady layout。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: updateContextMenuPresentation() / contextMenuLayoutContextForCurrentChromeState() / transitionContextMenuLayoutContext(for:)
// 功能说明: 修改后 iOS 侧在工具栏过渡期间不再重跑 overlay placement，而是从当前 transition presentation 构造冻结的 layoutContext。
private func updateContextMenuPresentation() {
    guard isViewLoaded else {
        return
    }

    let layoutContext = contextMenuLayoutContextForCurrentChromeState()
    if let contextMenuState {
        logContextMenuPresentation(
            state: contextMenuState,
            layoutContext: layoutContext
        )
    }
    contextMenuHostView.apply(
        state: contextMenuState,
        layoutContext: layoutContext
    )
}

private func contextMenuLayoutContextForCurrentChromeState() -> CanvasChromeLayoutContext {
    if let runtime = toolbarTransitionRuntime {
        return transitionContextMenuLayoutContext(for: runtime)
    }

    return performOverlayLayoutPass()
}

private func transitionContextMenuLayoutContext(
    for runtime: CanvasToolbarTransitionRuntime
) -> CanvasChromeLayoutContext {
    var chromeBlockers = baseChromeBlockersForToolbarLayout()
    let transitionFrame = normalizedToolbarFrame(
        currentToolbarAnimatedFrame(fallback: runtime.currentPresentation.frame),
        fallback: runtime.currentPresentation.frame
    )
    appendChromeBlocker(
        kind: .toolbar,
        rect: transitionFrame,
        to: &chromeBlockers
    )

    let chromeLayoutContext = CanvasChromeLayoutContext(
        safeBounds: toolbarLayoutSafeBounds(),
        toolbarPreferredPlacement: runtime.context.visibleSnapshot.state.placement,
        toolbarMeasuredSize: CanvasChromeLayoutGeometry.sanitizedSize(
            runtime.context.frames.visibleFrame.size
        ),
        chromeBlockers: chromeBlockers
    )
    return makeContextMenuLayoutContext(
        chromeLayoutContext: chromeLayoutContext,
        miniMapFrame: miniMapMountView.frame
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: updateContextMenuPresentation() / contextMenuLayoutContextForCurrentChromeState() / transitionContextMenuLayoutContext(for:)
// 功能说明: 修改后 macOS 侧与 iOS 对称，context menu 刷新在动画期间改用冻结的 transition layoutContext，而不是再次调用 placement pass。
private func updateContextMenuPresentation() {
    guard isViewLoaded else {
        return
    }

    let layoutContext = contextMenuLayoutContextForCurrentChromeState()
    if let contextMenuState {
        logContextMenuPresentation(
            state: contextMenuState,
            layoutContext: layoutContext
        )
    }
    contextMenuHostView.apply(
        state: contextMenuState,
        layoutContext: layoutContext
    )
}

private func contextMenuLayoutContextForCurrentChromeState() -> CanvasChromeLayoutContext {
    if let runtime = toolbarTransitionRuntime {
        return transitionContextMenuLayoutContext(for: runtime)
    }

    return performOverlayLayoutPass()
}

private func transitionContextMenuLayoutContext(
    for runtime: CanvasToolbarTransitionRuntime
) -> CanvasChromeLayoutContext {
    var chromeBlockers = baseChromeBlockersForToolbarLayout()
    let transitionFrame = normalizedToolbarFrame(
        currentToolbarAnimatedFrame(fallback: runtime.currentPresentation.frame),
        fallback: runtime.currentPresentation.frame
    )
    appendChromeBlocker(
        kind: .toolbar,
        rect: transitionFrame,
        to: &chromeBlockers
    )

    let chromeLayoutContext = CanvasChromeLayoutContext(
        safeBounds: toolbarLayoutSafeBounds(),
        toolbarPreferredPlacement: runtime.context.visibleSnapshot.state.placement,
        toolbarMeasuredSize: CanvasChromeLayoutGeometry.sanitizedSize(
            runtime.context.frames.visibleFrame.size
        ),
        chromeBlockers: chromeBlockers
    )
    return makeContextMenuLayoutContext(
        chromeLayoutContext: chromeLayoutContext,
        miniMapFrame: miniMapMountView.frame
    )
}
```

## 修改二：`viewDidLayoutSubviews` / `viewDidLayout` 不再在动画期间直接打断轨迹

### 修改前

- 双端在 `viewDidLayout*` 里都会在同步 camera viewport 之后直接调用 `updateChromeOverlayLayout()`。
- 一旦动画期间发生 safe area 变化、窗口变化或普通 layout re-entry，这条路径就会把 overlay layout 重新跑一遍。
- `Phase 4` 计划明确要求，这种情况只能记 `pendingLayoutReconcile`，不能立即改写当前轨迹。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: viewDidLayoutSubviews()
// 功能说明: 修改前 iOS 侧在每次 layout 回调里都会直接走 updateChromeOverlayLayout()，动画期间没有额外保护。
override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    syncCameraViewportSizeIfNeeded(
        canvasViewportView.bounds.size,
        source: "controller layout fallback"
    )
    updateChromeOverlayLayout()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: viewDidLayout()
// 功能说明: 修改前 macOS 侧在 viewDidLayout 里也会直接重跑 updateChromeOverlayLayout()，动画期间窗口变化会打断当前 toolbar 轨迹。
override func viewDidLayout() {
    super.viewDidLayout()
    print(
        "[Canvas macOS][ControllerLifecycle] " +
        "action=viewDidLayout.begin " +
        "viewBounds=\(describe(rect: view.bounds)) " +
        "viewFrame=\(describe(rect: view.frame)) " +
        "canvasHostBounds=\(describe(rect: canvasHostView.bounds)) " +
        "canvasHostFrame=\(describe(rect: canvasHostView.frame)) " +
        "canvasViewportBounds=\(describe(rect: canvasViewportView.bounds)) " +
        "canvasViewportFrame=\(describe(rect: canvasViewportView.frame)) " +
        "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
        "snapshotViewportBounds=\(describe(rect: lastRenderSnapshot.viewportBounds))"
    )
    updateCameraViewportSizeIfNeeded(trigger: "viewDidLayout")
    updateChromeOverlayLayout()
    print(
        "[Canvas macOS][ControllerLifecycle] " +
        "action=viewDidLayout.end " +
        "viewBounds=\(describe(rect: view.bounds)) " +
        "canvasViewportBounds=\(describe(rect: canvasViewportView.bounds)) " +
        "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
        "snapshotViewportBounds=\(describe(rect: lastRenderSnapshot.viewportBounds))"
    )
}
```

### 修改后

- 双端在 `viewDidLayout*` 里现在都先检查 `isToolbarTransitionActive`。
- 如果工具栏过渡还在进行：
  - 只调用 `markToolbarTransitionLayoutReconcilePending()`
  - 立刻 `return`
- 这保证了 viewport 同步仍可发生，但 overlay layout 不会在动画期间回写工具栏 / miniMap / context menu 的 steady 几何。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: viewDidLayoutSubviews()
// 功能说明: 修改后 iOS 侧在动画期间遇到 layout re-entry 时，只记录 pending reconcile，不再立即重跑 overlay layout。
override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    syncCameraViewportSizeIfNeeded(
        canvasViewportView.bounds.size,
        source: "controller layout fallback"
    )
    guard isToolbarTransitionActive == false else {
        markToolbarTransitionLayoutReconcilePending()
        return
    }
    updateChromeOverlayLayout()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: viewDidLayout()
// 功能说明: 修改后 macOS 侧在动画期间遇到窗口或布局重入时，也只记 pending reconcile，不再让 updateChromeOverlayLayout() 打断当前轨迹。
override func viewDidLayout() {
    super.viewDidLayout()
    print(
        "[Canvas macOS][ControllerLifecycle] " +
        "action=viewDidLayout.begin " +
        "viewBounds=\(describe(rect: view.bounds)) " +
        "viewFrame=\(describe(rect: view.frame)) " +
        "canvasHostBounds=\(describe(rect: canvasHostView.bounds)) " +
        "canvasHostFrame=\(describe(rect: canvasHostView.frame)) " +
        "canvasViewportBounds=\(describe(rect: canvasViewportView.bounds)) " +
        "canvasViewportFrame=\(describe(rect: canvasViewportView.frame)) " +
        "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
        "snapshotViewportBounds=\(describe(rect: lastRenderSnapshot.viewportBounds))"
    )
    updateCameraViewportSizeIfNeeded(trigger: "viewDidLayout")
    guard isToolbarTransitionActive == false else {
        markToolbarTransitionLayoutReconcilePending()
        return
    }
    updateChromeOverlayLayout()
    print(
        "[Canvas macOS][ControllerLifecycle] " +
        "action=viewDidLayout.end " +
        "viewBounds=\(describe(rect: view.bounds)) " +
        "canvasViewportBounds=\(describe(rect: canvasViewportView.bounds)) " +
        "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
        "snapshotViewportBounds=\(describe(rect: lastRenderSnapshot.viewportBounds))"
    )
}
```

## 修改三：`updateChromeOverlayLayout()` 在动画期间统一退化为“只记 reconcile”

### 修改前

- 虽然双端此前已经给 `renderToolbar()`、`applyToolbarFrame(_:)` 加了 guard，但 `updateChromeOverlayLayout()` 自己仍会直接调用 `performOverlayLayoutPass()`。
- 这意味着只要别的路径绕开前两个 guard，还是可以在动画期间触发 overlay layout pass。
- `Phase 4` 的这一层收口，就是把 guard 提升到 overlay layout 入口本身。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: updateChromeOverlayLayout()
// 功能说明: 修改前 iOS 侧 updateChromeOverlayLayout() 自身没有过渡保护，会直接重跑 performOverlayLayoutPass()。
private func updateChromeOverlayLayout() {
    let contextMenuLayoutContext = performOverlayLayoutPass()
    updateContextMenuLayout(using: contextMenuLayoutContext)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: updateChromeOverlayLayout()
// 功能说明: 修改前 macOS 侧 updateChromeOverlayLayout() 也会直接进入 performOverlayLayoutPass()，动画期仍存在入口级重入。
private func updateChromeOverlayLayout() {
    let contextMenuLayoutContext = performOverlayLayoutPass()
    updateContextMenuLayout(using: contextMenuLayoutContext)
}
```

### 修改后

- 双端 `updateChromeOverlayLayout()` 现在先统一判断 `isToolbarTransitionActive`。
- 动画期间不再进入 `performOverlayLayoutPass()`，而是只记 `pendingLayoutReconcile`。
- 这和 `finishToolbarModeTransition(applying:)` 里已有的 completion 收口逻辑配合，形成“动画期只累积请求，completion 后只做一次最终 reconcile”的链路。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: updateChromeOverlayLayout()
// 功能说明: 修改后 iOS 侧把 overlay layout 的 guard 提升到入口级，动画期间统一只标记 pending reconcile。
private func updateChromeOverlayLayout() {
    guard isToolbarTransitionActive == false else {
        markToolbarTransitionLayoutReconcilePending()
        return
    }

    let contextMenuLayoutContext = performOverlayLayoutPass()
    updateContextMenuLayout(using: contextMenuLayoutContext)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: updateChromeOverlayLayout()
// 功能说明: 修改后 macOS 侧与 iOS 对称，动画期间 updateChromeOverlayLayout() 不再直接重跑 placement pass。
private func updateChromeOverlayLayout() {
    guard isToolbarTransitionActive == false else {
        markToolbarTransitionLayoutReconcilePending()
        return
    }

    let contextMenuLayoutContext = performOverlayLayoutPass()
    updateContextMenuLayout(using: contextMenuLayoutContext)
}
```

## 修改四：保持 `Phase 4` 边界只在双端控制器，不改共享 contract

### 修改前

- `Phase 4` 计划明确要求：
  - 继续复用同一份 `CanvasToolbarTransitionRuntime`
  - 唯一允许继续写入的共享状态是 `pendingLayoutReconcile`
  - 不新增共享 transition 字段

### 修改后

- 结合当前 `git status --short` 和本次 `git diff` 可以确认：
  - 只有 `iOSViewController.swift`、`macOSViewController.swift` 两个文件发生修改
  - `CanvasToolbarTransitionState.swift`
  - `CanvasToolbarTransitionGeometry.swift`
  - `CanvasToolbarPlacementPass.swift`
  - 双端 Host 文件
  - 计划 `.md` 文件
    都没有被本次业务代码改动触碰
- 因此本次变更仍严格落在 `Phase 4` 边界内：
  - 解决的是布局竞争与 completion 收口
  - 没有改 contract 命名、字段和阶段语义

## 验证情况

- `ReadLints` 检查：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - 结果：无 linter 报错。
- 已执行双端工程构建校验，结果均通过。

```bash
# 文件路径: 系统命令 /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
# 函数名/命令名: xcodebuild
# 功能说明: 对 Phase 4 的 iOS 控制器收口改动执行工程级构建校验。
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "/tmp/MyCanvas_Ver_0-toolbar-phase4-ios" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

```bash
# 文件路径: 系统命令 /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
# 函数名/命令名: xcodebuild
# 功能说明: 对 Phase 4 的 macOS 控制器收口改动执行工程级构建校验。
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS" \
  -derivedDataPath "/tmp/MyCanvas_Ver_0-toolbar-phase4-macos" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

- 本次没有附带肉眼动画验收记录。

## 当前结论

- 本次改动如实对应 `Phase 4`：
  - `viewDidLayout*` 不再在动画期间打断当前轨迹
  - `updateChromeOverlayLayout()` 不再在动画期间重跑 overlay placement
  - `updateContextMenuPresentation()` 在动画期间改用冻结的 transition layout context
  - completion 后仍沿用已有 `pendingLayoutReconcile` 收口到最终 steady layout
- 当前业务代码改动仍只落在两份控制器文件：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
