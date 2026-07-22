# 20260722_080310_CST_ios_bottom_toolbar_hide_minimap_record

## 记录范围

- 本记录如实描述本轮 iOS 画布布局修改：
  - iOS 画布内不显示 minimap。
  - iOS 主工具条从右侧移动到底部。
  - iOS 编辑模式与阅读模式切换时，工具条 transition / 隐藏方向 / chrome blocker 交互边界跟随底边。
- 本记录依据：
  - 系统 `date` 命令生成的时间戳。
  - 当前 `git status --short`。
  - 当前 `git diff --stat` / `git diff --check`。
  - 当前 `git diff -- MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`。
  - iOS Simulator 构建验证结果。
- 本记录不包含：
  - 原始 `git diff` 全文。
  - 任何提交操作。
  - macOS 侧布局行为修改。

## 时间戳与 Changes 证据

```sh
# 文件路径: 无（终端命令）
# 函数名: date "+%Y%m%d_%H%M%S_%Z"
# 功能说明: 使用系统自带 date 命令生成本记录文件名前缀。
20260722_080310_CST
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short
# 功能说明: 记录创建本文档之前的真实工作区改动范围。
 M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --stat && git diff --check
# 功能说明: 汇总本轮 tracked changes，并确认补丁无空白格式错误。
 MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift | 14 ++++++++++++--
 1 file changed, 12 insertions(+), 2 deletions(-)

# git diff --check 退出码为 0，未输出空白错误。
```

## 修改一：iOS 默认工具条从右侧改到底部

### 修改前

- iOS 的 `transientToolbarPlacement` 默认使用 `.trailing`。
- 这会让主工具条以右侧边缘为布局边界。
- 阅读 / 编辑模式切换时，toolbar transition 通过 `makeToolbarState()` 和 `toolbarPreferredPlacement()` 读取同一个 placement，因此切换动画、隐藏 frame、chrome blocker 也按右边计算。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift（修改前）
// 函数名: iOSViewController.transientToolbarPlacement
// 功能说明: 修改前 iOS 主工具条默认锚定在 trailing，也就是右侧竖向工具条。
private var transientToolbarPlacement = CanvasToolbarPlacement(
    preferredEdge: .trailing
) {
    didSet {
        guard isViewLoaded else {
            return
        }

        updatePreparedToolbarPlacement()
    }
}
```

### 修改后

- iOS 的 `transientToolbarPlacement` 默认改为 `.bottom`。
- `CanvasToolbarPlacementPass`、`CanvasToolbarPlacementSolver`、`CanvasToolbarTransitionGeometry` 都已经按 `preferredEdge` 计算 frame，因此该修改会同步影响：
  - 工具条稳定态 frame。
  - 工具条横向/竖向测量方向。
  - 阅读 / 编辑模式切换时的 collapsed frame。
  - 离屏 hidden frame。
  - chrome layout context 中的 toolbar blocker。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: iOSViewController.transientToolbarPlacement
// 功能说明: iOS 主工具条默认锚定到底部；模式切换沿用该 placement 计算视觉位置和交互边界。
private var transientToolbarPlacement = CanvasToolbarPlacement(
    preferredEdge: .bottom
) {
    didSet {
        guard isViewLoaded else {
            return
        }

        updatePreparedToolbarPlacement()
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: makeToolbarState()
// 功能说明: 工具条状态继续从 toolbarPreferredPlacement() 获取 placement；因此底部 placement 会进入编辑/阅读模式切换状态机。
private func makeToolbarState() -> CanvasToolbarState {
    toolbarStateBuilder.mainToolbarState(
        session: editorSession,
        saveState: saveButtonState,
        placement: toolbarPreferredPlacement(),
        supportsHandDrawingEditing: supportsHandDrawingEditing,
        isMultiSelectModeActive: isMultiSelectModeActive,
        includesHistoryItems: true
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: resolvedSteadyToolbarFrame(for:)
// 功能说明: 模式切换进入编辑态时，稳定 frame 由 state.placement 驱动；当前 iOS state.placement 已改为 bottom。
private func resolvedSteadyToolbarFrame(
    for state: CanvasToolbarState
) -> CGRect {
    let placementResult = CanvasToolbarPlacementPass.resolve(
        safeBounds: toolbarLayoutSafeBounds(),
        toolbarPreferredPlacement: state.placement,
        toolbarMeasuredSize: measuredToolbarHostSize(for: state),
        baseChromeBlockers: baseChromeBlockersForToolbarLayout(),
        scale: toolbarPlacementScale(),
        solver: toolbarPlacementSolver
    )

    return normalizedToolbarFrame(
        placementResult.toolbarFrame,
        fallback: placementResult.toolbarFrame
    )
}
```

## 修改二：iOS 显式关闭 minimap

### 修改前

- iOS 每次 overlay layout pass 都会调用 `resolveMiniMapFrame(in:)`。
- 该方法通过 `CanvasOverlayLayoutSolver.resolveMiniMapFrame(...)` 计算 minimap frame。
- 非空 minimap frame 会：
  - 传给 `applyMiniMapFrame` 显示 minimap mount view。
  - 进入 `makeContextMenuLayoutContext(...)`，作为 `.miniMap` chrome blocker 参与菜单和悬浮 UI 避让。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift（修改前）
// 函数名: resolveMiniMapFrame(in:)
// 功能说明: 修改前 iOS 会照常计算 minimap frame，默认可显示并参与 chrome blocker。
private func resolveMiniMapFrame(
    in layoutContext: CanvasChromeLayoutContext
) -> CGRect {
    miniMapLayoutSolver.resolveMiniMapFrame(
        safeBounds: layoutContext.safeBounds,
        occupiedRects: layoutContext.occupiedRects,
        configuration: miniMapConfiguration
    )?.integral ?? .zero
}
```

### 修改后

- 新增 iOS 私有开关 `showsMiniMap = false`。
- `resolveMiniMapFrame(in:)` 在 iOS 直接返回 `.zero`。
- `applyMiniMapFrame(.zero)` 会保持 `miniMapMountView.isHidden = true`。
- 因为传入 `makeContextMenuLayoutContext(...)` 的 frame 为空，`CanvasChromeLayoutGeometry.sanitizedRect(miniMapFrame)` 返回 `nil`，minimap 不再追加为 chrome blocker。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: iOSViewController.showsMiniMap
// 功能说明: iOS 专属 minimap 显示开关；当前需求下固定关闭，不影响 macOS。
private static let showsMiniMap = false
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: resolveMiniMapFrame(in:)
// 功能说明: iOS minimap 关闭时返回 zero frame，让 minimap 不显示且不参与后续 chrome blocker。
private func resolveMiniMapFrame(
    in layoutContext: CanvasChromeLayoutContext
) -> CGRect {
    guard Self.showsMiniMap else {
        return .zero
    }

    return miniMapLayoutSolver.resolveMiniMapFrame(
        safeBounds: layoutContext.safeBounds,
        occupiedRects: layoutContext.occupiedRects,
        configuration: miniMapConfiguration
    )?.integral ?? .zero
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: applyMiniMapFrame(_:)
// 功能说明: zero frame 会隐藏 mount view；本函数本身未改，但这里说明它接收 zero frame 后的实际显示结果。
private func applyMiniMapFrame(_ miniMapFrame: CGRect) {
    if miniMapMountView.frame != miniMapFrame {
        miniMapMountView.frame = miniMapFrame
    }
    miniMapMountView.isHidden = miniMapFrame.isEmpty
    if miniMapView.frame != miniMapMountView.bounds {
        miniMapView.frame = miniMapMountView.bounds
    }
}
```

## 修改三：iOS 不再持续刷新 minimap 内容

### 修改前

- 每次 `performCanvasRefresh(reason:)` 都会调用 `refreshMiniMap()`。
- `refreshMiniMap()` 会构造 `editorSession.makeMiniMapSnapshot()` 并 apply 到 minimap view。
- 即便后续隐藏 minimap，如果不短路该方法，仍会进行无用快照构建。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift（修改前）
// 函数名: refreshMiniMap()
// 功能说明: 修改前 iOS 每次画布刷新都会重新生成并应用 minimap snapshot。
private func refreshMiniMap() {
    let snapshot = editorSession.makeMiniMapSnapshot()
    miniMapView.apply(snapshot)
}
```

### 修改后

- `refreshMiniMap()` 读取同一个 `showsMiniMap` 开关。
- 关闭时 apply `.empty` 后直接返回。
- 这样可以保证 UI 不显示，同时避免继续计算可见 minimap 内容。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: refreshMiniMap()
// 功能说明: iOS minimap 关闭时清空 minimap view 状态并跳过 snapshot 构建。
private func refreshMiniMap() {
    guard Self.showsMiniMap else {
        miniMapView.apply(.empty)
        return
    }

    let snapshot = editorSession.makeMiniMapSnapshot()
    miniMapView.apply(snapshot)
}
```

## 验证记录

### iOS 构建

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild build
# 功能说明: 验证 iOS 底部工具条、隐藏 minimap 和相关 controller 代码可编译。
xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "generic/platform=iOS Simulator" \
  CODE_SIGNING_ALLOWED=NO

** BUILD SUCCEEDED **
```

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild build 输出摘要
# 功能说明: 构建期间存在 Xcode 元数据提取警告；该警告与本次 iOS 布局修改无直接关系，构建最终成功。
warning: Metadata extraction skipped. No AppIntents.framework dependency found.
** BUILD SUCCEEDED **
```

### Lint 与格式检查

```sh
# 文件路径: 无（终端命令）
# 函数名: ReadLints / git diff --check
# 功能说明: 检查本轮 iOS 修改没有 IDE lint 报错，也没有 diff 空白格式错误。
ReadLints(MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift): No linter errors found.
git diff --check: exit code 0, no output.
```

## 结论

- iOS minimap 已通过 `showsMiniMap = false` 在布局和刷新两个入口关闭。
- iOS 工具条默认 placement 已从右侧 `.trailing` 改为底部 `.bottom`。
- 由于阅读 / 编辑模式切换沿用 `makeToolbarState()`、`toolbarPreferredPlacement()`、`CanvasToolbarPlacementPass` 和 `CanvasToolbarTransitionGeometry`，交互边界与过渡 frame 会跟随底部 placement 计算。
- macOS 文件未改，macOS minimap 与右侧工具条行为不受影响。
- 本次只新增记录文件，未执行 Git 提交。
