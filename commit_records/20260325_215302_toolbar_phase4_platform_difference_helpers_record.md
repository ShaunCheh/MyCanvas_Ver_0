# 20260325_215302_toolbar_phase4_platform_difference_helpers_record

## 记录范围

- 记录内容：
  1. 实施 `toolbar` 平台对称收敛计划的 `Phase 4`，把 `safeBounds` 来源与 `baseChromeBlockers` 组装从主流程中抽成平台私有 helper。
  2. 让 `iOS/macOS` 两端 `performOverlayLayoutPass()` 只表达共享 placement 主流程，平台差异显式收口到独立入口。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 本记录不包含：
  - 原始 gif diff
  - git commit / push
  - `Phase 5` 的验证收口

## 修改一：在 `macOS` 控制器中显式收口 `safeBounds` 与 `baseChromeBlockers`

### 修改前

- `performOverlayLayoutPass()` 里直接内联 `safeBounds` 的计算逻辑，同时也在同一个函数里拼装 `baseChromeBlockers`。
- 虽然 `Phase 3` 已经把两阶段 placement pass 抽到共享层，但 `macOS` 侧的平台差异仍然混在主流程函数内部。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: performOverlayLayoutPass()
// 功能说明: 修改前 macOS 侧在主流程里同时负责 placement pass 调用、safe area 几何计算和基础 blockers 组装，平台差异还没有显式收口。
private func performOverlayLayoutPass() -> CanvasChromeLayoutContext {
    var baseChromeBlockers: [CanvasChromeBlocker] = []
    appendChromeBlocker(
        kind: .backButton,
        for: backButton,
        to: &baseChromeBlockers
    )
    let toolbarPlacementResult = CanvasToolbarPlacementPass.resolve(
        safeBounds: CGRect(
            x: view.bounds.minX + view.safeAreaInsets.left,
            y: view.bounds.minY + view.safeAreaInsets.top,
            width: max(
                view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right,
                0
            ),
            height: max(
                view.bounds.height - view.safeAreaInsets.top - view.safeAreaInsets.bottom,
                0
            )
        ).standardized,
        toolbarPreferredPlacement: toolbarPreferredPlacement(),
        toolbarMeasuredSize: measuredToolbarHostSize(),
        baseChromeBlockers: baseChromeBlockers,
        scale: toolbarPlacementScale(),
        solver: toolbarPlacementSolver
    )
    applyToolbarFrame(toolbarPlacementResult.toolbarFrame)
    let miniMapFrame = resolveMiniMapFrame(
        in: toolbarPlacementResult.chromeLayoutContext
    )
    applyMiniMapFrame(miniMapFrame)
    return makeContextMenuLayoutContext(
        chromeLayoutContext: toolbarPlacementResult.chromeLayoutContext,
        miniMapFrame: miniMapFrame
    )
}
```

### 修改后

- `safeBounds` 被收口为 `toolbarLayoutSafeBounds()`
- `baseChromeBlockers` 被收口为 `baseChromeBlockersForToolbarLayout()`
- `performOverlayLayoutPass()` 现在只表达共享 placement 主流程，不再直接内联平台差异细节。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: performOverlayLayoutPass() / toolbarLayoutSafeBounds() / baseChromeBlockersForToolbarLayout()
// 功能说明: 修改后 macOS 侧把平台差异显式抽成两个私有 helper，主流程只消费它们的结果并继续走共享 placement pass。
private func performOverlayLayoutPass() -> CanvasChromeLayoutContext {
    let toolbarPlacementResult = CanvasToolbarPlacementPass.resolve(
        safeBounds: toolbarLayoutSafeBounds(),
        toolbarPreferredPlacement: toolbarPreferredPlacement(),
        toolbarMeasuredSize: measuredToolbarHostSize(),
        baseChromeBlockers: baseChromeBlockersForToolbarLayout(),
        scale: toolbarPlacementScale(),
        solver: toolbarPlacementSolver
    )
    applyToolbarFrame(toolbarPlacementResult.toolbarFrame)
    let miniMapFrame = resolveMiniMapFrame(
        in: toolbarPlacementResult.chromeLayoutContext
    )
    applyMiniMapFrame(miniMapFrame)
    return makeContextMenuLayoutContext(
        chromeLayoutContext: toolbarPlacementResult.chromeLayoutContext,
        miniMapFrame: miniMapFrame
    )
}

private func toolbarLayoutSafeBounds() -> CGRect {
    CGRect(
        x: view.bounds.minX + view.safeAreaInsets.left,
        y: view.bounds.minY + view.safeAreaInsets.top,
        width: max(
            view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right,
            0
        ),
        height: max(
            view.bounds.height - view.safeAreaInsets.top - view.safeAreaInsets.bottom,
            0
        )
    ).standardized
}

private func baseChromeBlockersForToolbarLayout() -> [CanvasChromeBlocker] {
    var chromeBlockers: [CanvasChromeBlocker] = []
    appendChromeBlocker(
        kind: .backButton,
        for: backButton,
        to: &chromeBlockers
    )
    return chromeBlockers
}
```

### 结果

- `macOS` 的平台差异现在有了明确修改入口。
- 后续如果要调整 `safeBounds` 规则或新增/修改 blocker，不需要再进主流程里拆逻辑。

## 修改二：在 `iOS` 控制器中显式收口 `safeBounds` 与 `baseChromeBlockers`

### 修改前

- `iOS` 侧和 `macOS` 一样，虽然已经接入共享 `CanvasToolbarPlacementPass`，但 `safeBounds` 与 `.historyButtons` blocker 仍然内联在主流程里。
- 这使得 `iOS` 的平台差异和共享 placement 主流程仍然耦合在一个函数中。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: performOverlayLayoutPass()
// 功能说明: 修改前 iOS 侧在主流程中同时承担 shared pass 调用、safeAreaLayoutGuide 读取和 back/history blockers 拼装。
private func performOverlayLayoutPass() -> CanvasChromeLayoutContext {
    var baseChromeBlockers: [CanvasChromeBlocker] = []
    appendChromeBlocker(
        kind: .backButton,
        for: backButton,
        to: &baseChromeBlockers
    )
    appendChromeBlocker(
        kind: .historyButtons,
        for: historyButtonsStackView,
        to: &baseChromeBlockers
    )
    let toolbarPlacementResult = CanvasToolbarPlacementPass.resolve(
        safeBounds: chromeOverlayView.safeAreaLayoutGuide.layoutFrame,
        toolbarPreferredPlacement: toolbarPreferredPlacement(),
        toolbarMeasuredSize: measuredToolbarHostSize(),
        baseChromeBlockers: baseChromeBlockers,
        scale: toolbarPlacementScale(),
        solver: toolbarPlacementSolver
    )
    applyToolbarFrame(toolbarPlacementResult.toolbarFrame)
    let miniMapFrame = resolveMiniMapFrame(
        in: toolbarPlacementResult.chromeLayoutContext
    )
    applyMiniMapFrame(miniMapFrame)
    return makeContextMenuLayoutContext(
        chromeLayoutContext: toolbarPlacementResult.chromeLayoutContext,
        miniMapFrame: miniMapFrame
    )
}
```

### 修改后

- `safeBounds` 被收口为 `toolbarLayoutSafeBounds()`
- `baseChromeBlockers` 被收口为 `baseChromeBlockersForToolbarLayout()`
- `.historyButtons` 这类平台/产品差异仍然明确保留在 `iOS` 本地，没有被错误抽进共享层。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: performOverlayLayoutPass() / toolbarLayoutSafeBounds() / baseChromeBlockersForToolbarLayout()
// 功能说明: 修改后 iOS 侧把 safeAreaLayoutGuide 和 back/history blockers 收口为平台私有 helper，主流程只负责串联共享 placement 结果。
private func performOverlayLayoutPass() -> CanvasChromeLayoutContext {
    let toolbarPlacementResult = CanvasToolbarPlacementPass.resolve(
        safeBounds: toolbarLayoutSafeBounds(),
        toolbarPreferredPlacement: toolbarPreferredPlacement(),
        toolbarMeasuredSize: measuredToolbarHostSize(),
        baseChromeBlockers: baseChromeBlockersForToolbarLayout(),
        scale: toolbarPlacementScale(),
        solver: toolbarPlacementSolver
    )
    applyToolbarFrame(toolbarPlacementResult.toolbarFrame)
    let miniMapFrame = resolveMiniMapFrame(
        in: toolbarPlacementResult.chromeLayoutContext
    )
    applyMiniMapFrame(miniMapFrame)
    return makeContextMenuLayoutContext(
        chromeLayoutContext: toolbarPlacementResult.chromeLayoutContext,
        miniMapFrame: miniMapFrame
    )
}

private func toolbarLayoutSafeBounds() -> CGRect {
    chromeOverlayView.safeAreaLayoutGuide.layoutFrame
}

private func baseChromeBlockersForToolbarLayout() -> [CanvasChromeBlocker] {
    var chromeBlockers: [CanvasChromeBlocker] = []
    appendChromeBlocker(
        kind: .backButton,
        for: backButton,
        to: &chromeBlockers
    )
    appendChromeBlocker(
        kind: .historyButtons,
        for: historyButtonsStackView,
        to: &chromeBlockers
    )
    return chromeBlockers
}
```

### 结果

- `iOS` 侧平台差异已经从主流程中分离出来。
- 后续如果要调整 `historyButtons` 的占位策略或 safe area 来源，修改点已经固定。

## 结构变化总结

- `Phase 3` 解决的是“共享 placement 编排重复”
- `Phase 4` 解决的是“平台差异入口不明确”

截至当前，`performOverlayLayoutPass()` 的职责已经进一步收敛为：

1. 读取平台私有的 `safeBounds`
2. 读取平台私有的 `baseChromeBlockers`
3. 调共享 `CanvasToolbarPlacementPass`
4. 消费 `toolbarFrame` 与 `chromeLayoutContext`
5. 继续走 `miniMap/context menu` 本地坐标系逻辑

## 验证记录

- `ReadLints` 检查以下文件，结果为无错误：
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `swiftc -frontend -parse` 解析以下文件通过：
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarChromeMetrics.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarMeasurement.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementPass.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
