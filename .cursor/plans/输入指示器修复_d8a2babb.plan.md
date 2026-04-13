---
name: 输入指示器修复
overview: 把 macOS 输入指示器从“0 尺寸约束下的 live fitting”重构为与现有 floating chrome 一致的 frame-driven 浮层测量路径，消除 Auto Layout 冲突，同时保留现有 queue/formatter/layout solver 管线。
todos:
  - id: macos-indicator-frame-host
    content: 将 macOS 输入指示器宿主改成 frame-driven 浮层容器，移除 0 尺寸约束测量闭环
    status: pending
  - id: macos-indicator-measure-flow
    content: 重排 macOS 分支的 snapshot/measure/layout 顺序，确保 preferred size 不受 0 尺寸父容器污染
    status: pending
  - id: macos-indicator-verify
    content: 完成双端 build 与 macOS 手工约束告警回归验证
    status: pending
isProject: false
---

# 输入指示器根因修复计划

## 根因锚点

- 当前问题集中在 [MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift](MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift) 的 macOS 分支：`containerView` 先被 `width/height == 0` 约束锁死，再对其内部 `stackView` 调用 `fittingSize` 做首选尺寸测量，形成“0 尺寸容器 -> live fitting -> 求解失败/告警”的闭环。
- 现有仓库里更稳定的范式是：
  - [MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift](MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift)
  - [MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelHostView.swift](MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelHostView.swift)
  - [MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift](MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift)
- 这几处的共同点不是“放松内容约束”，而是避免在被压成 0 的 live 容器里测内容；输入指示器应对齐这条架构。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift
containerWidthConstraint = containerView.widthAnchor.constraint(equalToConstant: 0)
containerHeightConstraint = containerView.heightAnchor.constraint(equalToConstant: 0)

private func preferredContainerSize() -> CGSize {
    CanvasChromeLayoutGeometry.sanitizedSize(stackView.fittingSize)
}
```

## 修改方向

1. 仅重构 [MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift](MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift) 的 macOS 分支，不动 iOS 分支、不改 queue/formatter/layout solver 的语义。
2. 把 macOS 输入指示器宿主从“Auto Layout 管理 0 尺寸容器”改成“host 铺满 overlay，内部 `containerView` 采用 frame-driven 浮层容器”，对齐 context menu / action panel 的浮层写法。
3. 保留 `stackView` 作为内容子树，但不再让其首选尺寸依赖 `containerWidthConstraint/containerHeightConstraint`；`preferredContainerSize()` 应在不受 0 尺寸父容器污染的前提下计算自然尺寸。
4. 对空快照、无 layout context、solver 返回 `nil` 的场景，统一用“隐藏 + `containerView.frame = .zero`”表达，而不是把 live 内容树通过约束压成 0。
5. 如果首帧仍存在早期 layout pass 风险，再借鉴 toolbar 的 bootstrap 思路，在 macOS 分支加入最小合法初始尺寸；不通过降低 item 内部约束优先级来掩盖根因。

## 实施步骤

1. 在 [MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift](MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift) 中删除 macOS 分支里 `containerLeadingConstraint/containerTopConstraint/containerWidthConstraint/containerHeightConstraint` 这组“以常量宽高驱动容器”的约束链，改为由 solver 结果直接设置 `containerView.frame`。
2. 保留 `CanvasInputIndicatorLayoutSolver` 作为唯一位置求解入口，继续消费 [MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorLayoutSolver.swift](MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorLayoutSolver.swift) 与 [MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift](MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift) 的 safe bounds / blockers 语义；只替换 host 的测量与 frame 回写方式。
3. 将 macOS `applySnapshot(...)` / `applyLayout()` / `preferredContainerSize()` 的顺序重新收口：先重建 arranged subviews，再取自然内容尺寸，再由 solver 解 frame，再写回 `containerView.frame`；任何失败分支只隐藏或清零 frame，不把内容树重新压回 0 尺寸约束环境。
4. 如需要提纯测量逻辑，可在同文件 macOS 分支内抽出一个小的 `measuredContainerSize()` helper；优先保持改动局部，不额外扩散新抽象层。
5. 验证时重点回归：首个事件到来前 layout context 尚未就绪、队列从非空衰减到空、toolbar/minimap blocker 并存、文本编辑态/普通画布态切换时的输入胶囊显示。

## 验证策略

- 构建：跑 `macOS` 与 `iOS Simulator` 的 `xcodebuild build`，确认共享文件重构后双端都能编译。
- 日志：在 `macOS` 触发 `Command + C / V`、`Right Click`、滚轮等输入，确认不再出现 `Conflicting constraints detected`。
- 布局：确认输入指示器仍能遵守 [MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorLayoutSolver.swift](MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorLayoutSolver.swift) 的底部避让规则，不与 toolbar / minimap 重叠。
- 回归：不改 `CanvasInputIndicatorQueue` / `CanvasInputIndicatorFormatter` 语义；若重构中需要新增一个纯测量 helper，再补一个针对该 helper 的纯测试，而不是写高噪音的 NSView 约束快照测试。

