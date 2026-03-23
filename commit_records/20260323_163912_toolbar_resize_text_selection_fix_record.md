# 20260323_163912_toolbar_resize_text_selection_fix_record

## 记录范围

- 记录内容：
  1. 修复选中文本项后主 toolbar 从 4 个按钮变为 3 个按钮时，host 尺寸没有同步重算的问题，避免 macOS 上底部 `+` 导入按钮被拉长。
  2. 对齐 `iOS` / `macOS` 的 inline edit 按钮刷新路径：当 toolbar item 集合变化时，不再只做 `renderToolbar()`，而是走完整的 toolbar placement 重排链。
  3. 清理本次排查该问题时临时加入的 `Canvas Toolbar Debug` 调试日志。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`
- 问题背景：
  - 共享 toolbar state 原本就会在选中文本项时隐藏 `crop`，这是正确行为。
  - 真正的问题不在 `CanvasToolbarStateBuilder.shouldShowCropItem(...)`，而在于控制器只刷新了 toolbar 内容，没有同步重测 host 尺寸并更新 placement。
- 本记录不包含：
  - 原始 gif diff
  - git commit / push
  - 新的功能改动（本次仅为 bug fix 与调试清理）

## 根因定位：完整的 toolbar placement 重排链已经存在，但修改前没有复用到 inline edit 刷新路径

- `updatePreparedToolbarPlacement()` 本身已经具备 “`renderToolbar()` + 强制布局 + `updateChromeOverlayLayout()`” 的完整重排能力。
- 修改前 `updateInlineEditButtonsAppearance()` 没有复用这条链，因此当 toolbar item 数变化时，host 可能继续保留旧尺寸。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: updatePreparedToolbarPlacement()
// 功能说明: 这个方法原本就负责完整的 toolbar placement 重排；修复的关键不是新增新逻辑，而是让 toolbar 内容变化路径复用这条现有链路。
private func updatePreparedToolbarPlacement() {
    renderToolbar()
    if view.bounds.isEmpty == false {
        view.layoutSubtreeIfNeeded()
        updateChromeOverlayLayout()
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: updatePreparedToolbarPlacement()
// 功能说明: iOS 侧也已有对等的完整 toolbar placement 重排链，因此本次修复同步对齐两端调用方式。
private func updatePreparedToolbarPlacement() {
    renderToolbar()
    if view.bounds.isEmpty == false {
        view.layoutIfNeeded()
        updateChromeOverlayLayout()
    }
}
```

## 修改一：将 inline edit 按钮刷新从 `renderToolbar()` 升级为完整 placement 重排

### 修改前

- `iOS` 与 `macOS` 的 `updateInlineEditButtonsAppearance()` 都只调用 `renderToolbar()`。
- 这会刷新按钮内容，但不会保证 host frame 基于新 item 数重新测量，因此选中文本后由 `4 -> 3` 个按钮的尺寸变化可能滞留在旧高度。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: updateInlineEditButtonsAppearance()
// 功能说明: 修改前 iOS 侧只刷新 toolbar 内容，不保证当 item 数变化时同步触发 host 重新测量与重排。
private func updateInlineEditButtonsAppearance() {
    renderToolbar()
    updateHistoryButtonsAppearance()
    syncTextEditorPresentation()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: updateInlineEditButtonsAppearance()
// 功能说明: 修改前 macOS 侧同样只做 renderToolbar()；当 text selection 隐藏 crop 后，toolbar host 可能继续保留旧的 4 按钮高度。
private func updateInlineEditButtonsAppearance() {
    renderToolbar()
    syncTextEditorPresentation()
}
```

### 修改后

- `iOS` 与 `macOS` 的 `updateInlineEditButtonsAppearance()` 都改为调用 `updatePreparedToolbarPlacement()`。
- 这样当 toolbar item 集合变化时，会立即触发完整的 host 重测与 placement 更新，而不是只刷新按钮内容。
- `iOS` 额外保留原来的 `updateHistoryButtonsAppearance()` 调用，不改变既有 undo/redo 刷新路径。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: updateInlineEditButtonsAppearance()
// 功能说明: 修改后 iOS 侧在 inline edit 按钮状态变化时，会走完整的 toolbar placement 重排，再刷新历史按钮与文本编辑浮层。
private func updateInlineEditButtonsAppearance() {
    updatePreparedToolbarPlacement()
    updateHistoryButtonsAppearance()
    syncTextEditorPresentation()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: updateInlineEditButtonsAppearance()
// 功能说明: 修改后 macOS 侧不再只刷新 toolbar 内容，而是立即重新测量并放置 toolbar host，避免 `+` 按钮因旧高度残留而被拉长。
private func updateInlineEditButtonsAppearance() {
    updatePreparedToolbarPlacement()
    syncTextEditorPresentation()
}
```

## 修改二：移除共享 toolbar state builder 中的临时调试日志

### 修改前

- 为了排查“选中文本后 `+` 按钮变长”，`CanvasToolbarStateBuilder.mainToolbarState(...)` 曾临时包了一层 `logMainToolbarStateIfNeeded(...)`。
- 该日志会在文本选择或文本 inline edit 时打印 toolbar item 列表、axis、是否显示 crop 等信息。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数名: mainToolbarState(...) / logMainToolbarStateIfNeeded(...)
// 功能说明: 修改前共享 builder 为排查问题临时插入调试日志；这些日志不属于长期产品逻辑。
func mainToolbarState(
    session: CanvasEditorSession,
    saveState: CanvasSaveState,
    placement: CanvasToolbarPlacement,
    isImportEnabled: Bool = true,
    showsBackground: Bool = true
) -> CanvasToolbarState {
    var itemStates: [CanvasToolbarItemState] = []
    if shouldShowCropItem(session: session) {
        itemStates.append(cropItemState(session: session))
    }
    itemStates.append(saveItemState(saveState: saveState))
    itemStates.append(textItemState(session: session))
    itemStates.append(importItemState(isEnabled: isImportEnabled))

    let toolbarState = CanvasToolbarState(
        placement: placement,
        items: itemStates,
        showsBackground: showsBackground
    )
    logMainToolbarStateIfNeeded(
        toolbarState,
        session: session
    )
    return toolbarState
}

private func logMainToolbarStateIfNeeded(
    _ toolbarState: CanvasToolbarState,
    session: CanvasEditorSession
) {
    guard
        session.selectedBoardItemKind == .text ||
        session.isInlineTextModeActive
    else {
        return
    }

    // ... 省略调试打印拼装 ...
}
```

### 修改后

- `mainToolbarState(...)` 恢复为直接返回 `CanvasToolbarState`。
- 共享 builder 中不再保留任何本次排查加入的 `Canvas Toolbar Debug` 代码。
- `shouldShowCropItem(session:)` 的业务逻辑保持不变，说明本次修复没有回退“文本项隐藏 crop”的产品行为。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数名: mainToolbarState(...) / shouldShowCropItem(session:)
// 功能说明: 修改后共享 builder 恢复为纯状态构建器；保留既有的 text item 隐藏 crop 逻辑，不再输出临时调试日志。
func mainToolbarState(
    session: CanvasEditorSession,
    saveState: CanvasSaveState,
    placement: CanvasToolbarPlacement,
    isImportEnabled: Bool = true,
    showsBackground: Bool = true
) -> CanvasToolbarState {
    var itemStates: [CanvasToolbarItemState] = []
    if shouldShowCropItem(session: session) {
        itemStates.append(cropItemState(session: session))
    }
    itemStates.append(saveItemState(saveState: saveState))
    itemStates.append(textItemState(session: session))
    itemStates.append(importItemState(isEnabled: isImportEnabled))

    return CanvasToolbarState(
        placement: placement,
        items: itemStates,
        showsBackground: showsBackground
    )
}

private func shouldShowCropItem(session: CanvasEditorSession) -> Bool {
    guard session.isInlineCropModeActive == false else {
        return true
    }

    return session.selectedBoardItemKind != .text
}
```

## 修改三：移除 iOS/macOS toolbar host 中的 render/layout 调试钩子

### 修改前

- `iOSCanvasToolbarHostView` 与 `macOSCanvasToolbarHostView` 都曾临时加入两类调试逻辑：
  1. 记录 render signature / layout signature；
  2. 在 `render(_:)`、`layoutSubviews` / `layout()` 中打印 host bounds、stack frame、按钮 frame、约束常量、title/configTitle 等信息。
- 这些调试代码只用于确认“按钮被拉长”究竟是 state 问题还是 layout 问题，不适合长期保留。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: layoutSubviews() / render(_:) / logRenderIfNeeded(_:) / logLayoutIfNeeded(reason:)
// 功能说明: 修改前 iOS host 临时注入了布局与渲染日志，用于观察按钮 frame、intrinsic size 和约束常量。
private var lastLoggedRenderSignature: String?
private var lastLoggedLayoutSignature: String?

override func layoutSubviews() {
    super.layoutSubviews()
    logLayoutIfNeeded(reason: "layoutSubviews")
}

func render(_ state: CanvasToolbarState) {
    preferredAxisOverride = state.preferredAxis
    dockEdge = state.placement.preferredEdge
    backgroundView.isHidden = state.showsBackground == false
    isHidden = state.items.isEmpty
    syncButtons(with: state.items)
    logRenderIfNeeded(state)
}

private func logRenderIfNeeded(_ state: CanvasToolbarState) { /* ... */ }
private func logLayoutIfNeeded(reason: String) { /* ... */ }
private func buttonDebugSummary(_ button: UIButton) -> String { /* ... */ }
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名: layout() / render(_:) / logRenderIfNeeded(_:) / logLayoutIfNeeded(reason:)
// 功能说明: 修改前 macOS host 也临时加入了对等日志，以便确认 host 仍停留在旧高度时，NSStackView 会把哪个按钮拉长。
private var lastLoggedRenderSignature: String?
private var lastLoggedLayoutSignature: String?

override func layout() {
    super.layout()
    logLayoutIfNeeded(reason: "layout")
}

func render(_ state: CanvasToolbarState) {
    preferredAxisOverride = state.preferredAxis
    dockEdge = state.placement.preferredEdge
    backgroundView.isHidden = state.showsBackground == false
    isHidden = state.items.isEmpty
    syncButtons(with: state.items)
    logRenderIfNeeded(state)
}

private func logRenderIfNeeded(_ state: CanvasToolbarState) { /* ... */ }
private func logLayoutIfNeeded(reason: String) { /* ... */ }
private func buttonDebugSummary(_ button: NSButton) -> String { /* ... */ }
```

### 修改后

- 两端 host 都恢复为纯粹的 “render state -> sync buttons -> apply appearance” 视图层实现。
- 不再记录任何与本次排查相关的 `Canvas Toolbar Debug` 输出。
- 这次 bug fix 的长期逻辑只保留在 controller 侧的重排调用方式调整上，而不是把日志或额外判定固化进 host view。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: render(_:) / syncButtons(with:)
// 功能说明: 修改后 iOS host 恢复为纯工具栏宿主视图：接收 state、同步按钮顺序、应用 appearance，不再保留问题排查日志。
private var registeredButtons: [CanvasToolbarItemID: UIButton] = [:]
private var preferredAxisOverride: CanvasToolbarAxis?

func render(_ state: CanvasToolbarState) {
    preferredAxisOverride = state.preferredAxis
    dockEdge = state.placement.preferredEdge
    backgroundView.isHidden = state.showsBackground == false
    isHidden = state.items.isEmpty
    syncButtons(with: state.items)
}

private func syncButtons(with itemStates: [CanvasToolbarItemState]) {
    let orderedButtons: [UIButton] = itemStates.compactMap { itemState in
        guard let button = registeredButtons[itemState.id] else {
            return nil
        }
        applyAppearance(itemState, to: button)
        return button
    }

    buttonsStackView.arrangedSubviews.forEach { arrangedSubview in
        buttonsStackView.removeArrangedSubview(arrangedSubview)
        arrangedSubview.removeFromSuperview()
    }

    orderedButtons.forEach { button in
        buttonsStackView.addArrangedSubview(button)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名: render(_:) / syncButtons(with:)
// 功能说明: 修改后 macOS host 同样恢复为纯工具栏宿主视图；按钮拉伸的根因修复留在 controller 的 placement 重排路径中。
private var registeredButtons: [CanvasToolbarItemID: NSButton] = [:]
private var preferredAxisOverride: CanvasToolbarAxis?

func render(_ state: CanvasToolbarState) {
    preferredAxisOverride = state.preferredAxis
    dockEdge = state.placement.preferredEdge
    backgroundView.isHidden = state.showsBackground == false
    isHidden = state.items.isEmpty
    syncButtons(with: state.items)
}

private func syncButtons(with itemStates: [CanvasToolbarItemState]) {
    let orderedButtons: [NSButton] = itemStates.compactMap { itemState in
        guard let button = registeredButtons[itemState.id] else {
            return nil
        }
        applyAppearance(itemState, to: button)
        return button
    }

    buttonsStackView.arrangedSubviews.forEach { arrangedSubview in
        buttonsStackView.removeArrangedSubview(arrangedSubview)
        arrangedSubview.removeFromSuperview()
    }

    orderedButtons.forEach { button in
        buttonsStackView.addArrangedSubview(button)
    }
}
```

## 验证

### 已执行验证

- `ReadLints` 检查以下文件：无 IDE 诊断错误。
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`
- 使用 `xcrun --sdk macosx swiftc -typecheck -parse-as-library` 对整个 `MyCanvas_Ver_0` 源码树做静态检查：通过。

```sh
# 命令说明: 对整个源码树做 macOS 静态 typecheck，确认 toolbar 修复与日志清理后，shared + macOS 编译面没有语法或类型错误。
python3 - <<'PY'
import pathlib
import subprocess
import sys
root = pathlib.Path('MyCanvas_Ver_0')
files = sorted(str(path) for path in root.rglob('*.swift'))
cmd = ['xcrun', '--sdk', 'macosx', 'swiftc', '-typecheck', '-parse-as-library', *files]
result = subprocess.run(cmd)
sys.exit(result.returncode)
PY
```

```text
# 结果摘要: 退出码 0，无输出。
```

### 当前限制

- 这次记录只包含代码修复与静态验证，不包含新的 UI 运行态截图。
- 由于当前环境无法直接替代完整 Xcode 运行态，本记录中的行为确认仍需以后续人工复现为准：
  - 选中文本项时，toolbar 应从 4 按钮高度收敛到 3 按钮高度；
  - macOS 上 `+` 按钮不应再被拉长；
  - 不应再出现先前那组 `NSLayoutConstraint` 冲突警告。

## 结果小结

- 根因修复落在 controller 侧的 toolbar placement 重排调用方式，而不是回退 text item 隐藏 `crop` 的业务逻辑。
- `iOS` / `macOS` 两端现在都在 toolbar 内容变化时复用完整 placement 重排链，降低了后续同类“内容变了但 host 尺寸没变”的风险。
- 本次排查临时加入的 shared/host 调试日志已经全部清理，最终代码只保留长期需要的修复逻辑。
