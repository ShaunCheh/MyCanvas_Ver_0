# 20260318_173113_ios_context_menu_restore_dynamic_placement_record

## 记录范围

- 记录目标：
  1. 撤销 `iOS` 菜单“固定显示在触点右边 + no-clamp”的运行时策略。
  2. 恢复 `allowChromeOverlap` 路径下的动态选位行为。
  3. 保留此前已经修掉“菜单跳回左上角”的宿主约束化修复。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift`
  - `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift`
- 本记录不包含：
  - `iOS` / `macOS` 坐标桥接逻辑回退
  - 左上角问题修复回退
  - git commit

## 修改一：iOS 宿主不再默认使用 fixed-right 策略

### 修改前

- `CanvasContextMenuHostView` 的 `iOS` 分支把 `layoutConfiguration.placementStyle` 固定为 `.fixedRightOfAnchor`。
- 这意味着菜单默认会从触点右侧展开，而不是回到共享 solver 的动态选位行为。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift
// 函数名/类型名: CanvasContextMenuHostView.layoutConfiguration
// 功能说明: 修改前 iOS 宿主默认使用 allowChromeOverlap + fixedRightOfAnchor，菜单运行时会优先固定在触点右边。
private let layoutSolver = CanvasContextMenuLayoutSolver()
private let layoutConfiguration: CanvasContextMenuLayoutConfiguration = {
    var configuration = CanvasContextMenuLayoutConfiguration()
    configuration.occlusionPolicy = .allowChromeOverlap
    configuration.placementStyle = .fixedRightOfAnchor
    return configuration
}()
```

### 修改后

- `iOS` 宿主把 `placementStyle` 恢复为 `.cursorPreferred`。
- `occlusionPolicy` 继续保持 `.allowChromeOverlap`，因此这次没有同时回退“菜单可覆盖 chrome”的策略。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift
// 函数名/类型名: CanvasContextMenuHostView.layoutConfiguration
// 功能说明: 修改后 iOS 宿主恢复为 cursorPreferred 动态选位，但继续允许菜单覆盖 chrome。
private let layoutSolver = CanvasContextMenuLayoutSolver()
private let layoutConfiguration: CanvasContextMenuLayoutConfiguration = {
    var configuration = CanvasContextMenuLayoutConfiguration()
    configuration.occlusionPolicy = .allowChromeOverlap
    configuration.placementStyle = .cursorPreferred
    return configuration
}()
```

### 影响

- 撤销后，`iOS` 运行时不再把“固定右边”作为默认行为。
- 但如果只做这一处修改还不够，因为共享 solver 在 `allowChromeOverlap` 分支里仍然会直接取首选候选，仍然无法真正回到按空间动态选位。

## 修改二：allowChromeOverlap 分支恢复为动态候选排序

### 修改前

- `CanvasContextMenuLayoutSolver.resolveMenuFrame(...)` 在 `allowChromeOverlap` 分支下会跳过 `candidatePlacements(...)`，直接使用 `preferredPlacements(...)`。
- 当 `blockerRects = []` 时，循环通常会在第一个候选就返回，因此即使宿主不再配置 `.fixedRightOfAnchor`，这里也仍然更像“固定首选方向”，不是旧的动态选位体验。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift
// 函数名/类型名: CanvasContextMenuLayoutSolver.resolveMenuFrame(...)
// 功能说明: 修改前 allowChromeOverlap 分支直接使用 preferredPlacements，忽略动态候选排序。
switch configuration.occlusionPolicy {
case .avoidOverlayChrome:
    blockerRects = occupiedRects
        .map(\.standardized)
        .filter { $0.isEmpty == false }
        .map {
            $0.insetBy(
                dx: -configuration.chromeClearance,
                dy: -configuration.chromeClearance
            )
        }
    placements = candidatePlacements(
        for: configuration.placementStyle,
        around: anchorPoint,
        size: resolvedSize,
        within: layoutBounds,
        anchorSpacing: configuration.anchorSpacing,
        configuration: configuration
    )
case .allowChromeOverlap:
    // Keep safeBounds as the hard boundary, but allow menus to cover
    // floating buttons and the minimap. Placement style still controls
    // whether the menu prefers finger-above or cursor-near behavior.
    blockerRects = []
    placements = preferredPlacements(for: configuration.placementStyle)
}
```

### 修改后

- `allowChromeOverlap` 仍然不把 `occupiedRects` 作为 overlap blocker。
- 但它重新走 `candidatePlacements(...)`，恢复按真实空间进行候选排序。
- 这使得菜单重新回到“动态选位 + 允许覆盖 chrome”的组合，而不是“固定右边 + no-clamp”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift
// 函数名/类型名: CanvasContextMenuLayoutSolver.resolveMenuFrame(...)
// 功能说明: 修改后 allowChromeOverlap 分支仍忽略 chrome blocker，但恢复为动态候选排序。
switch configuration.occlusionPolicy {
case .avoidOverlayChrome:
    blockerRects = occupiedRects
        .map(\.standardized)
        .filter { $0.isEmpty == false }
        .map {
            $0.insetBy(
                dx: -configuration.chromeClearance,
                dy: -configuration.chromeClearance
            )
        }
    placements = candidatePlacements(
        for: configuration.placementStyle,
        around: anchorPoint,
        size: resolvedSize,
        within: layoutBounds,
        anchorSpacing: configuration.anchorSpacing,
        configuration: configuration
    )
case .allowChromeOverlap:
    // Keep safeBounds as the hard boundary, but allow menus to cover
    // floating buttons and the minimap. Placement style still controls
    // the dynamic candidate ordering, but occupied chrome no longer
    // participates in overlap scoring for this branch.
    blockerRects = []
    placements = candidatePlacements(
        for: configuration.placementStyle,
        around: anchorPoint,
        size: resolvedSize,
        within: layoutBounds,
        anchorSpacing: configuration.anchorSpacing,
        configuration: configuration
    )
}
```

### 影响

- 菜单不再只吃 `preferredPlacements(...)` 的第一个候选。
- 在 `cursorPreferred` 下，菜单会重新在共享 solver 的候选列表中按空间排序选位。
- `fixedRightOfAnchor` 的枚举和 `shouldClamp(...)` 里的 no-clamp 特判没有被删除，但在这次运行时路径下不再被 `iOS` 默认使用。

## 保留不变：左上角修复没有被回退

- 这次没有回退 `CanvasContextMenuHostView` 中为了解决“菜单跳回左上角”而增加的宿主约束化修复。
- 这些代码继续负责保证外层 `menuContainerView` 的位置和尺寸由一套明确的约束控制，而不是重新落回“frame 与 Auto Layout 混用”的状态。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift
// 函数名/类型名: CanvasContextMenuHostView.init(frame:)
// 功能说明: 这部分宿主约束化修复保持不变，继续让外层菜单容器由四个约束负责定位与尺寸。
addSubview(menuContainerView)
menuContainerView.contentView.addSubview(commandStackView)
menuLeadingConstraint = menuContainerView.leadingAnchor.constraint(equalTo: leadingAnchor)
menuTopConstraint = menuContainerView.topAnchor.constraint(equalTo: topAnchor)
menuWidthConstraint = menuContainerView.widthAnchor.constraint(equalToConstant: 0)
menuHeightConstraint = menuContainerView.heightAnchor.constraint(equalToConstant: 0)
NSLayoutConstraint.activate([
    menuLeadingConstraint,
    menuTopConstraint,
    menuWidthConstraint,
    menuHeightConstraint,
    commandStackView.topAnchor.constraint(equalTo: menuContainerView.contentView.topAnchor, constant: 10),
    commandStackView.leadingAnchor.constraint(equalTo: menuContainerView.contentView.leadingAnchor, constant: 10),
    commandStackView.trailingAnchor.constraint(equalTo: menuContainerView.contentView.trailingAnchor, constant: -10),
    commandStackView.bottomAnchor.constraint(equalTo: menuContainerView.contentView.bottomAnchor, constant: -10)
])
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift
// 函数名/类型名: CanvasContextMenuHostView.updateLayout(safeBounds:occupiedRects:) / updateMenuContainerConstraints(_:)
// 功能说明: 这部分左上角修复保持不变，继续在更新布局时通过约束常量同步外层菜单 frame，并立即触发布局。
updateMenuContainerConstraints(menuFrame.integral)
layoutIfNeeded()
logRuntimeState(reason: "updateLayout")
DispatchQueue.main.async { [weak self] in
    self?.logRuntimeState(reason: "asyncAfterUpdateLayout")
}

private func updateMenuContainerConstraints(_ frame: CGRect) {
    let standardizedFrame = frame.standardized
    menuLeadingConstraint.constant = standardizedFrame.minX
    menuTopConstraint.constant = standardizedFrame.minY
    menuWidthConstraint.constant = max(0, standardizedFrame.width)
    menuHeightConstraint.constant = max(0, standardizedFrame.height)
}
```

## 预期行为变化

- `iOS` 上下文菜单不再“永远固定在触点右侧”。
- 菜单恢复为基于 `cursorPreferred` 的动态选位行为。
- 菜单仍可覆盖悬浮按钮和 minimap，因为 `.allowChromeOverlap` 没有被回退。
- 左上角问题的根因修复仍然保留，因此这次策略回退不应重新引入“菜单跳回左上角”的 bug。

## 验证

- 已完成：
  - `ReadLints` 检查通过，没有新增静态错误。
  - `xcodebuild` 的 `iOS Simulator` 目标编译通过。
  - `xcodebuild` 的 `macOS` 目标编译通过。
- 尚未由本记录直接包含：
  - `iOS` 真机或模拟器上的手动交互回归日志。
