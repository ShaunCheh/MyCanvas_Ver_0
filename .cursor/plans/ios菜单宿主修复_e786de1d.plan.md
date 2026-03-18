---
name: iOS菜单宿主修复
overview: 修复 iOS 上上下文菜单在异步布局后跳回左上角的问题，收敛 `CanvasContextMenuHostView` 内部的布局责任，并保留现有共享求解器与 controller 坐标桥接不变。
todos:
  - id: lock-ios-menu-container-layout
    content: 收敛 iOS `menuContainerView` 的布局机制，消除 frame 与 Auto Layout 的混用
    status: completed
  - id: stabilize-menu-measurement
    content: 稳定 `preferredMenuSize()` 与内部内容布局时序，避免首帧与最终帧尺寸漂移
    status: completed
  - id: trim-runtime-logs
    content: 保留证明修复有效的关键日志，移除过深的逐按钮诊断输出
    status: pending
  - id: verify-ios-macos-context-menu
    content: 回归 iOS 定位/命中/覆盖行为，并做 macOS 共享层冒烟验证
    status: completed
isProject: false
---

# iOS 菜单宿主定位修复计划

## 根因确认

当前 `iOS` 菜单位置计算链路已经正确：`CanvasContextMenuLayoutSolver` 给出的 `resolvedMenuFrame` 与 `updateLayout` 当帧写入的 `menuContainerView.frame` 一致；问题出在下一轮 UIKit 布局后，`menuContainerView` 被重新放回 `(0, 0)`。

关键冲突位于 [MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift](MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift)：

```26:50:MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift
    menuContainerView.translatesAutoresizingMaskIntoConstraints = false
    // ...
    addSubview(menuContainerView)
    menuContainerView.contentView.addSubview(commandStackView)
    NSLayoutConstraint.activate([
        commandStackView.topAnchor.constraint(equalTo: menuContainerView.contentView.topAnchor, constant: 10),
        commandStackView.leadingAnchor.constraint(equalTo: menuContainerView.contentView.leadingAnchor, constant: 10),
        commandStackView.trailingAnchor.constraint(equalTo: menuContainerView.contentView.trailingAnchor, constant: -10),
        commandStackView.bottomAnchor.constraint(equalTo: menuContainerView.contentView.bottomAnchor, constant: -10)
    ])
```

```133:145:MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift
        logContextMenuLayout(
            platform: "iOS",
            state: currentState,
            hostBounds: bounds,
            safeBounds: safeBounds,
            occupiedRects: occupiedRects,
            preferredSize: preferredSize,
            resolvedMenuFrame: menuFrame
        )
        menuContainerView.frame = menuFrame.integral
        logRuntimeState(reason: "updateLayout")
        DispatchQueue.main.async { [weak self] in
            self?.logRuntimeState(reason: "asyncAfterUpdateLayout")
        }
```

这说明外层容器同时处于“手动 frame 定位”和“Auto Layout 接管”的混合状态，下一轮布局时 frame 被系统覆盖。

## 实施范围

只改 [MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift](MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift) 的 `iOS` 分支；[MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift](MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift) 继续只负责 `state/safeBounds/occupiedRects` 的传入，不新增平台特判。

## 实施步骤

1. 收敛 `menuContainerView` 的布局责任。

将外层菜单容器改成单一布局机制：要么纯手动 frame，要么纯约束驱动。基于现有共享 solver 已直接产出目标 `CGRect`，优先保留外层 pure-frame 模式，让 `menuContainerView` 不再被 UIKit 后续回写到 `(0,0)`。

1. 保留内部内容使用 Auto Layout。

`commandStackView` 和按钮仍然挂在 `menuContainerView.contentView` 上，通过现有约束生成内容尺寸；必要时在 `updateLayout` / `layoutSubviews` 的时序里显式触发布局，使“外层 frame 已定、内层内容随后铺满”成为稳定链路。

1. 稳定尺寸测量路径。

校正 `preferredMenuSize()` 的测量时机，避免在按钮刚重建、父容器尚未布局时得到不完整的中间值；确保测量值与最终显示尺寸一致，不再出现首帧 `181x393`、下一帧跳成 `168x392` 这种不稳定结果。

1. 收敛和保留诊断日志。

保留能证明修复生效的关键日志：`resolvedMenuFrame`、`updateLayout`、异步/后续布局后的 `menuFrame`。如果修复后位置稳定，可删掉过深的逐按钮运行时日志，避免污染后续排查。

## 验证

- iOS 长按已选中 item body，确认 `resolvedMenuFrame`、`updateLayout menuFrame`、后续布局后的 `menuFrame` 三者保持一致，不再跳回 `(0,0)`。
- iOS 长按空白区域、未选中 item、靠近屏幕边缘的位置，确认菜单仍遵守当前 `fixedRightOfAnchor + allowChromeOverlap` 策略。
- 回归菜单按钮点击、点外 dismiss、覆盖浮动按钮和 minimap 的层级与命中。
- macOS 不改逻辑，只做冒烟确认，确保共享文件变更未影响现有菜单展示。

