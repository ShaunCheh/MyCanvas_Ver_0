# 20260325_214536_toolbar_phase3_shared_placement_pass_record

## 记录范围

- 记录内容：
  1. 实施 `toolbar` 平台对称收敛计划的 `Phase 3`，把“两阶段 toolbar placement 数据流”从 `iOS/macOS` 控制器中抽取到共享 `Toolbar` 层。
  2. 让 `iOS/macOS` 控制器改为消费共享 placement pass，只保留平台必需差异、`frame` 赋值以及 `miniMap/context menu` 的坐标转换。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementPass.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 本记录不包含：
  - 原始 gif diff
  - git commit / push
  - `Phase 4` 的 `safeBounds/blocker` 平台差异显式收口

## 修改一：抽取共享的两阶段 `toolbar placement` 数据流

### 修改前

- `macOSViewController` 与 `iOSViewController` 都各自维护同一条两阶段布局链：
  1. `makeChromeLayoutContext(toolbarFrame: nil)`
  2. `applyToolbarPlacement(using:)`
  3. `makeChromeLayoutContext(toolbarFrame: toolbarFrame)`
- 这条链在两个控制器里都重复存在，只是 `baseChromeBlockers` 和 `safeBounds` 的平台差异不同。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: performOverlayLayoutPass() / applyToolbarPlacement(using:) / makeChromeLayoutContext(toolbarFrame:)
// 功能说明: 修改前 macOS 控制器完整持有两阶段 toolbar placement 数据流，既要组上下文，又要求 frame，还要再构造第二次 chromeLayoutContext。
private func performOverlayLayoutPass() -> CanvasChromeLayoutContext {
    let toolbarPlacementContext = makeChromeLayoutContext(
        toolbarFrame: nil
    )
    let toolbarFrame = applyToolbarPlacement(
        using: toolbarPlacementContext
    )
    let chromeLayoutContext = makeChromeLayoutContext(
        toolbarFrame: toolbarFrame
    )
    let miniMapFrame = resolveMiniMapFrame(
        in: chromeLayoutContext
    )
    applyMiniMapFrame(miniMapFrame)
    return makeContextMenuLayoutContext(
        chromeLayoutContext: chromeLayoutContext,
        miniMapFrame: miniMapFrame
    )
}

private func applyToolbarPlacement(
    using layoutContext: CanvasChromeLayoutContext
) -> CGRect {
    let resolvedFrame = toolbarPlacementSolver.resolveFrame(
        in: layoutContext
    ).flatMap { frame in
        CanvasChromeLayoutGeometry.pixelAlignedRectPreservingSize(
            frame,
            scale: toolbarPlacementScale()
        )
    } ?? .zero

    if toolbarHostView.frame != resolvedFrame {
        toolbarHostView.frame = resolvedFrame
    }

    return resolvedFrame
}

private func makeChromeLayoutContext(
    toolbarFrame: CGRect?
) -> CanvasChromeLayoutContext {
    var chromeBlockers: [CanvasChromeBlocker] = []
    appendChromeBlocker(
        kind: .backButton,
        for: backButton,
        to: &chromeBlockers
    )
    if let toolbarFrame {
        appendChromeBlocker(
            kind: .toolbar,
            rect: toolbarFrame,
            to: &chromeBlockers
        )
    }

    return CanvasChromeLayoutContext(
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
        chromeBlockers: chromeBlockers
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: performOverlayLayoutPass() / applyToolbarPlacement(using:) / makeChromeLayoutContext(toolbarFrame:)
// 功能说明: 修改前 iOS 控制器也重复维护同一条数据流，只是额外把 historyButtons 加入 chromeBlockers。
private func performOverlayLayoutPass() -> CanvasChromeLayoutContext {
    let toolbarPlacementContext = makeChromeLayoutContext(
        toolbarFrame: nil
    )
    let toolbarFrame = applyToolbarPlacement(
        using: toolbarPlacementContext
    )
    let chromeLayoutContext = makeChromeLayoutContext(
        toolbarFrame: toolbarFrame
    )
    let miniMapFrame = resolveMiniMapFrame(
        in: chromeLayoutContext
    )
    applyMiniMapFrame(miniMapFrame)
    return makeContextMenuLayoutContext(
        chromeLayoutContext: chromeLayoutContext,
        miniMapFrame: miniMapFrame
    )
}

private func applyToolbarPlacement(
    using layoutContext: CanvasChromeLayoutContext
) -> CGRect {
    let resolvedFrame = toolbarPlacementSolver.resolveFrame(
        in: layoutContext
    ).flatMap { frame in
        CanvasChromeLayoutGeometry.pixelAlignedRectPreservingSize(
            frame,
            scale: toolbarPlacementScale()
        )
    } ?? .zero

    if toolbarHostView.frame != resolvedFrame {
        toolbarHostView.frame = resolvedFrame
    }

    return resolvedFrame
}

private func makeChromeLayoutContext(
    toolbarFrame: CGRect?
) -> CanvasChromeLayoutContext {
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
    if let toolbarFrame {
        appendChromeBlocker(
            kind: .toolbar,
            rect: toolbarFrame,
            to: &chromeBlockers
        )
    }

    return CanvasChromeLayoutContext(
        safeBounds: chromeOverlayView.safeAreaLayoutGuide.layoutFrame,
        toolbarPreferredPlacement: toolbarPreferredPlacement(),
        toolbarMeasuredSize: measuredToolbarHostSize(),
        chromeBlockers: chromeBlockers
    )
}
```

### 修改后

- 新增共享 `CanvasToolbarPlacementPass`，把“两阶段 context 构造 + solver 求 frame + 像素对齐 + 补上 `.toolbar` blocker”统一抽到共享层。
- 控制器不再自己维护整条 placement 数据流。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementPass.swift
// 函数名: resolve(...) / makeChromeLayoutContext(...)
// 功能说明: 新增共享 placement pass，统一承载 toolbar 的两阶段布局数据流：先基于基础 blockers 求 toolbarFrame，再产出带 toolbar blocker 的 chromeLayoutContext。
struct CanvasToolbarPlacementPassResult: Hashable, Sendable {
    var toolbarFrame: CGRect
    var chromeLayoutContext: CanvasChromeLayoutContext
}

enum CanvasToolbarPlacementPass {
    static func resolve(
        safeBounds: CGRect,
        toolbarPreferredPlacement: CanvasToolbarPlacement,
        toolbarMeasuredSize: CGSize,
        baseChromeBlockers: [CanvasChromeBlocker],
        scale: CGFloat,
        solver: CanvasToolbarPlacementSolver = CanvasToolbarPlacementSolver(),
        configuration: CanvasToolbarPlacementConfiguration = CanvasToolbarPlacementConfiguration()
    ) -> CanvasToolbarPlacementPassResult {
        let toolbarPlacementContext = makeChromeLayoutContext(
            safeBounds: safeBounds,
            toolbarPreferredPlacement: toolbarPreferredPlacement,
            toolbarMeasuredSize: toolbarMeasuredSize,
            chromeBlockers: baseChromeBlockers
        )
        let toolbarFrame = solver.resolveFrame(
            in: toolbarPlacementContext,
            configuration: configuration
        ).flatMap { frame in
            CanvasChromeLayoutGeometry.pixelAlignedRectPreservingSize(
                frame,
                scale: scale
            )
        } ?? .zero

        var chromeBlockers = baseChromeBlockers
        if let toolbarRect = CanvasChromeLayoutGeometry.sanitizedRect(
            toolbarFrame
        ) {
            chromeBlockers.append(
                CanvasChromeBlocker(
                    kind: .toolbar,
                    rect: toolbarRect
                )
            )
        }

        return CanvasToolbarPlacementPassResult(
            toolbarFrame: toolbarFrame,
            chromeLayoutContext: makeChromeLayoutContext(
                safeBounds: safeBounds,
                toolbarPreferredPlacement: toolbarPreferredPlacement,
                toolbarMeasuredSize: toolbarMeasuredSize,
                chromeBlockers: chromeBlockers
            )
        )
    }

    private static func makeChromeLayoutContext(
        safeBounds: CGRect,
        toolbarPreferredPlacement: CanvasToolbarPlacement,
        toolbarMeasuredSize: CGSize,
        chromeBlockers: [CanvasChromeBlocker]
    ) -> CanvasChromeLayoutContext {
        CanvasChromeLayoutContext(
            safeBounds: safeBounds,
            toolbarPreferredPlacement: toolbarPreferredPlacement,
            toolbarMeasuredSize: toolbarMeasuredSize,
            chromeBlockers: chromeBlockers
        )
    }
}
```

### 结果

- 共享层现在显式拥有一条可复用的 `toolbar placement` 数据流。
- `CanvasToolbarPlacementSolver` 仍保持纯求解职责，没有被改成平台逻辑容器。
- `Phase 3` 的目标达成：重复的两阶段 placement 编排不再散落在两个控制器里。

## 修改二：让 `macOS` 控制器改为消费共享 placement pass

### 修改前

- `macOSViewController` 同时承担：
  - 组装第一遍 `chromeLayoutContext`
  - 求 `toolbarFrame`
  - 组装第二遍 `chromeLayoutContext`
  - 给 `toolbarHostView.frame` 赋值
- 这让控制器在平台差异之外，还额外承担了一整段共享布局流程。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: performOverlayLayoutPass() / applyToolbarPlacement(using:)
// 功能说明: 修改前 macOS 控制器既负责平台 blocker/safeBounds，也负责共享 placement 数据流本身。
private func performOverlayLayoutPass() -> CanvasChromeLayoutContext {
    let toolbarPlacementContext = makeChromeLayoutContext(
        toolbarFrame: nil
    )
    let toolbarFrame = applyToolbarPlacement(
        using: toolbarPlacementContext
    )
    let chromeLayoutContext = makeChromeLayoutContext(
        toolbarFrame: toolbarFrame
    )
    let miniMapFrame = resolveMiniMapFrame(
        in: chromeLayoutContext
    )
    applyMiniMapFrame(miniMapFrame)
    return makeContextMenuLayoutContext(
        chromeLayoutContext: chromeLayoutContext,
        miniMapFrame: miniMapFrame
    )
}

private func applyToolbarPlacement(
    using layoutContext: CanvasChromeLayoutContext
) -> CGRect {
    let resolvedFrame = toolbarPlacementSolver.resolveFrame(
        in: layoutContext
    ).flatMap { frame in
        CanvasChromeLayoutGeometry.pixelAlignedRectPreservingSize(
            frame,
            scale: toolbarPlacementScale()
        )
    } ?? .zero

    if toolbarHostView.frame != resolvedFrame {
        toolbarHostView.frame = resolvedFrame
    }

    return resolvedFrame
}
```

### 修改后

- `macOSViewController` 只负责：
  - 收集 `baseChromeBlockers`
  - 提供 `safeBounds`
  - 调用共享 `CanvasToolbarPlacementPass.resolve(...)`
  - 消费 `toolbarFrame` 与第二遍 `chromeLayoutContext`
- 原来的 `applyToolbarPlacement(using:)`、`makeChromeLayoutContext(toolbarFrame:)` 已移除，控制器只保留一个轻量的 `applyToolbarFrame(_:)`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: performOverlayLayoutPass() / applyToolbarFrame(_:)
// 功能说明: 修改后 macOS 控制器只保留平台特定输入与结果消费，重复的两阶段 placement 编排已转移到共享 ToolbarPlacementPass。
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

private func applyToolbarFrame(_ toolbarFrame: CGRect) {
    if toolbarHostView.frame != toolbarFrame {
        toolbarHostView.frame = toolbarFrame
    }
}
```

### 结果

- `macOS` 控制器不再重复维护 placement 主流程。
- `safeBounds` 的平台来源与 `.backButton` blocker 仍然留在 `macOS` 侧，符合当前阶段边界。

## 修改三：让 `iOS` 控制器改为消费共享 placement pass

### 修改前

- `iOSViewController` 也重复维护与 `macOS` 同构的 placement 主流程，只是多了 `.historyButtons` blocker。
- 平台差异和共享流程逻辑混在同一个控制器里。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: performOverlayLayoutPass() / applyToolbarPlacement(using:)
// 功能说明: 修改前 iOS 控制器在维护自身平台差异的同时，也重复持有完整的两阶段 placement 数据流。
private func performOverlayLayoutPass() -> CanvasChromeLayoutContext {
    let toolbarPlacementContext = makeChromeLayoutContext(
        toolbarFrame: nil
    )
    let toolbarFrame = applyToolbarPlacement(
        using: toolbarPlacementContext
    )
    let chromeLayoutContext = makeChromeLayoutContext(
        toolbarFrame: toolbarFrame
    )
    let miniMapFrame = resolveMiniMapFrame(
        in: chromeLayoutContext
    )
    applyMiniMapFrame(miniMapFrame)
    return makeContextMenuLayoutContext(
        chromeLayoutContext: chromeLayoutContext,
        miniMapFrame: miniMapFrame
    )
}

private func applyToolbarPlacement(
    using layoutContext: CanvasChromeLayoutContext
) -> CGRect {
    let resolvedFrame = toolbarPlacementSolver.resolveFrame(
        in: layoutContext
    ).flatMap { frame in
        CanvasChromeLayoutGeometry.pixelAlignedRectPreservingSize(
            frame,
            scale: toolbarPlacementScale()
        )
    } ?? .zero

    if toolbarHostView.frame != resolvedFrame {
        toolbarHostView.frame = resolvedFrame
    }

    return resolvedFrame
}
```

### 修改后

- `iOSViewController` 和 `macOSViewController` 现在消费同一个共享 pass。
- `iOS` 侧只保留自身平台特有输入：
  - `chromeOverlayView.safeAreaLayoutGuide.layoutFrame`
  - `.historyButtons` blocker
- 原来的 `applyToolbarPlacement(using:)`、`makeChromeLayoutContext(toolbarFrame:)` 也一并移除。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: performOverlayLayoutPass() / applyToolbarFrame(_:)
// 功能说明: 修改后 iOS 控制器只负责提供 safeBounds 和 baseChromeBlockers，再消费共享 placement 结果；historyButtons 差异仍留在 iOS 本地。
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

private func applyToolbarFrame(_ toolbarFrame: CGRect) {
    if toolbarHostView.frame != toolbarFrame {
        toolbarHostView.frame = toolbarFrame
    }
}
```

### 结果

- `iOS` 控制器不再和 `macOS` 并行维护一整段共享布局链。
- `historyButtons` 这类平台/产品差异仍然明确留在 `iOS` 侧，没有在当前阶段被错误统一。

## 结构变化总结

- `Phase 1`：共享了测量常量 `CanvasToolbarChromeMetrics`
- `Phase 2`：共享了测量公式 `CanvasToolbarMeasurement`
- `Phase 3`：共享了两阶段 placement 编排 `CanvasToolbarPlacementPass`

截至当前，`toolbar` 收敛链已经演进为：

1. 平台 host 测得 `stackSize`
2. 共享 `CanvasToolbarMeasurement` 计算内容尺寸
3. 平台控制器提供 `safeBounds` 与 `baseChromeBlockers`
4. 共享 `CanvasToolbarPlacementPass` 产出 `toolbarFrame` 与第二遍 `chromeLayoutContext`
5. 平台控制器消费结果，继续做 `miniMap/context menu` 的本地坐标系处理

## 验证记录

- `ReadLints` 检查以下文件，结果为无错误：
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementPass.swift`
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
