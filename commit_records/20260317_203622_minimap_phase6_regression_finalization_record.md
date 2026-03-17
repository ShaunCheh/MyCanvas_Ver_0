# 20260317_203622_minimap_phase6_regression_finalization_record

## 记录范围

- 记录内容：
  1. 修正 `CanvasMiniMapRenderer` 中 `displayWorldRect` 的合成逻辑，解决 minimap 视口框在相机移出 board 边界时被裁掉甚至消失的问题。
  2. 收尾本次 `Phase 6` 的回归验证，确认这次修正没有引入新的静态诊断或 macOS 编译错误。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift`
- 本记录不包含：
  - 原始 git diff
  - 新的 commit / push
  - 新的功能性 UI 改版

## 问题背景

- `Phase 5` 之后，minimap 已经能根据 `boardWorldRect`、预览态节点范围和 `visibleWorldRect` 绘制整板与视口框。
- 但 `displayWorldRect` 的计算仍然偏向“画板内容范围”，没有把当前相机的 `visibleWorldRect` 强制纳入显示区域。
- 这会导致一个边界问题：
  - 当用户拖动画板，让当前视口部分或全部移出 `boardWorldRect`，而 `boardState` 还没来得及扩张时，minimap 的 `contentRect` 仍然只基于 board + preview 计算。
  - 此时 `visibleWorldRect` 投影到 minimap 后可能落到 `contentRect` 之外，结果就是视口框被裁掉，严重时看起来像“minimap 视口框消失”。

## 修改一：补上 `visibleWorldRect` 到 `displayWorldRect` 的调用链参数

### 修改前

- `makeSnapshot(...)` 在调用 `resolveDisplayWorldRect(...)` 时，只传入了 `boardWorldRect`、`nodes` 和 fallback。
- 这样 `resolveDisplayWorldRect(...)` 根本拿不到当前相机的真实视口范围。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift
// 函数名: makeSnapshot(scene:boardState:camera:inlineEditState:rotationPreviewState:)
// 功能说明: 修改前 displayWorldRect 的合成逻辑无法直接感知当前 camera.visibleWorldRect。
let boardWorldRect = resolveBoardWorldRect(
    boardState: boardState,
    nodes: nodes,
    fallbackVisibleWorldRect: visibleWorldRect
)
let displayWorldRect = resolveDisplayWorldRect(
    boardWorldRect: boardWorldRect,
    nodes: nodes,
    fallbackVisibleWorldRect: visibleWorldRect
)
```

### 修改后

- `makeSnapshot(...)` 现在把 `visibleWorldRect` 显式传给 `resolveDisplayWorldRect(...)`。
- 后续 `displayWorldRect` 的合成就能同时考虑：
  - board 范围
  - 预览态越界范围
  - 当前相机真实视口范围

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift
// 函数名: makeSnapshot(scene:boardState:camera:inlineEditState:rotationPreviewState:)
// 功能说明: 修改后 displayWorldRect 会把当前相机视口也纳入合成输入，避免 minimap 视口框丢失。
let boardWorldRect = resolveBoardWorldRect(
    boardState: boardState,
    nodes: nodes,
    fallbackVisibleWorldRect: visibleWorldRect
)
let displayWorldRect = resolveDisplayWorldRect(
    boardWorldRect: boardWorldRect,
    visibleWorldRect: visibleWorldRect,
    nodes: nodes,
    fallbackVisibleWorldRect: visibleWorldRect
)
```

## 修改二：从“只合并 preview”改成“统一合并 board / preview / viewport”

### 修改前

- `resolveDisplayWorldRect(...)` 的旧逻辑只做两件事：
  1. 如果有预览态节点范围，就把它和 `boardWorldRect` 做 `union`
  2. 如果没有预览态，就直接返回 `boardWorldRect`
- 旧逻辑没有把 `visibleWorldRect` 纳入 `displayWorldRect`，因此一旦相机离开 board，可见区域就不保证能被 minimap 内容区域覆盖。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift
// 函数名: resolveDisplayWorldRect(boardWorldRect:nodes:fallbackVisibleWorldRect:)
// 功能说明: 修改前 displayWorldRect 只考虑 board 与 preview 越界，不考虑当前 viewport 是否已经移出 board。
private func resolveDisplayWorldRect(
    boardWorldRect: CGRect,
    nodes: [CanvasMiniMapNode],
    fallbackVisibleWorldRect: CGRect
) -> CGRect {
    guard let previewWorldBounds = combinedWorldBounds(
        of: nodes.filter(\.isPreviewActive)
    ) else {
        return sanitizedWorldRect(boardWorldRect) ?? fallbackVisibleWorldRect
    }

    guard let sanitizedBoardWorldRect = sanitizedWorldRect(boardWorldRect) else {
        return previewWorldBounds
    }

    return sanitizedBoardWorldRect.union(previewWorldBounds).standardized
}
```

### 修改后

- 新逻辑改成“逐步合并”的统一路径：
  1. 先用 `boardWorldRect` 或 fallback 初始化 `resolvedDisplayWorldRect`
  2. 如果存在 preview 越界范围，则做一次 `union`
  3. 再把当前 `visibleWorldRect` 合并进去，保证 minimap 始终能容纳当前视口框
- 这样修复之后：
  - crop / rotate 预览仍然能扩展 minimap 显示范围
  - 仅仅是相机拖出 board，也不会让视口框丢失
  - 根因修复集中在 shared renderer，而不是去 iOS/macOS 视图层分别打补丁

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift
// 函数名: resolveDisplayWorldRect(boardWorldRect:visibleWorldRect:nodes:fallbackVisibleWorldRect:)
// 功能说明: 修改后统一合并 board、preview 和当前 viewport，确保 minimap 视口框始终可表示。
private func resolveDisplayWorldRect(
    boardWorldRect: CGRect,
    visibleWorldRect: CGRect,
    nodes: [CanvasMiniMapNode],
    fallbackVisibleWorldRect: CGRect
) -> CGRect {
    var resolvedDisplayWorldRect = sanitizedWorldRect(boardWorldRect)
        ?? sanitizedWorldRect(fallbackVisibleWorldRect)

    if let previewWorldBounds = combinedWorldBounds(
        of: nodes.filter(\.isPreviewActive)
    ) {
        if let currentDisplayWorldRect = resolvedDisplayWorldRect {
            resolvedDisplayWorldRect = currentDisplayWorldRect
                .union(previewWorldBounds)
                .standardized
        } else {
            resolvedDisplayWorldRect = previewWorldBounds
        }
    }

    // Keep the viewport frame representable even if the user pans outside the
    // committed board bounds before any board expansion happens.
    if let sanitizedVisibleWorldRect = sanitizedWorldRect(visibleWorldRect) {
        if let currentDisplayWorldRect = resolvedDisplayWorldRect {
            resolvedDisplayWorldRect = currentDisplayWorldRect
                .union(sanitizedVisibleWorldRect)
                .standardized
        } else {
            resolvedDisplayWorldRect = sanitizedVisibleWorldRect
        }
    }

    return resolvedDisplayWorldRect ?? fallbackVisibleWorldRect
}
```

## 修改结果

- 修复后，minimap 的 `displayWorldRect` 不再只是“内容边界”，而是“当前 minimap 必须能表达的总范围”。
- 这意味着以下场景的语义会保持正确：
  - 用户拖动画板，让视口暂时移出 board
  - crop / rotate draft 让预览内容超出当前 board
  - board 尚未扩张完成，但 minimap 仍要先把当前 viewport 框正确显示出来

## 回归校验

- 已使用 `ReadLints` 检查本次相关文件，未发现新增诊断。
- 已执行 macOS 全链路 `swiftc -typecheck`：
  - `MyCanvas_Ver_0/Canvas/Core/*.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/*.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/*.swift`
  - `MyCanvas_Ver_0/App/*.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/*.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/*.swift`
  - `MyCanvas_Ver_0/Platform/macOS/*.swift`
  - `MyCanvas_Ver_0/Platform/macOS/AppRoot/*.swift`
  - `MyCanvas_Ver_0/Platform/macOS/BoardList/*.swift`
- 上述 typecheck 已通过。
- 由于当前环境没有完整 Xcode 可用，未执行 iOS 端完整项目编译；iOS 侧以 `ReadLints` 结果作为本阶段静态校验补充。
