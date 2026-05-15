# 20260515_221810_selection_translation_area_phase5_validation_record

## 记录范围

- 记录内容：
  - 记录 `selectionTranslationArea` 方案 `phase 5` 的双平台构建与启动验证结果。
  - 如实说明本阶段没有新增源码改动，`git diff` 在本次引用的源码文件上为空。
  - 如实记录验证过程中额外出现的 `UserInterfaceState.xcuserstate` 状态文件变动，并按用户选择保留该变动。
- 涉及源码/状态文件：
  - `MyCanvas_Ver_0/App/AppLaunchCoordinator.swift`
  - `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift`
  - `MyCanvas_Ver_0.xcodeproj/project.xcworkspace/xcuserdata/shaun.xcuserdatad/UserInterfaceState.xcuserstate`
- 参考现状：
  - 生成本记录前，`git status --short --untracked-files=all` 只显示 `UserInterfaceState.xcuserstate` 处于修改状态。
  - 对本记录引用的 4 个源码文件执行 `git diff -- ...`，结果为空，说明 `phase 5` 没有新增源码 diff。
- 本记录不包含：
  - 新的 `selectionTranslationArea` 命中/分发实现
  - 新的测试代码修改
  - 对 `UserInterfaceState.xcuserstate` 的清理或恢复

## 当前 changes 摘要

- `phase 5` 这一轮没有新增业务源码或测试源码变更。
- 当前工作区里，和本轮验证直接相关的额外变动只有：
  - `MyCanvas_Ver_0.xcodeproj/project.xcworkspace/xcuserdata/shaun.xcuserdatad/UserInterfaceState.xcuserstate`
- 这次验证实际完成了：
  - `macOS` 构建通过
  - `iOS Simulator` 构建通过
  - `macOS` App 成功启动到 `Board List`
  - `iOS Simulator` App 成功启动到 `Board List`
- 这次验证没有完成的部分是深层人工交互：
  - 单选文字/图片拖拽
  - 多选整体拖拽
  - 旋转、裁剪、阅读模式的手工回归
- 原因不是代码报错，而是：
  - `iOS Simulator` 当前停在 `No Folder Selected`，没有进入可操作画布
  - `macOS` 继续用桌面自动化深入点击会干扰当前桌面焦点，因此在启动级验证后停止

## 代码状态一：启动入口在 `phase 5` 前后保持不变

### 修改前

- `phase 5` 开始前，App 启动入口仍然固定先落到 `Board List`。
- 这也是本次双平台启动验证会先看到 `Board List` 的直接原因。

```swift
// 文件路径: MyCanvas_Ver_0/App/AppLaunchCoordinator.swift（修改前）
// 函数名: initialDestination()
// 功能说明: phase 5 验证前，应用启动路由仍然固定先进入 Board List，而不是直接进入 Canvas。
struct AppLaunchCoordinator {
    func initialDestination() -> AppLaunchDestination {
        // Storage and restoration are not wired yet, so start from the board list.
        .boardList
    }
}
```

### 修改后

- `phase 5` 只做验证，没有改这个启动入口。
- 因此构建和启动之后，双端仍然会先进入 `Board List`，前后状态一致。

```swift
// 文件路径: MyCanvas_Ver_0/App/AppLaunchCoordinator.swift（修改后）
// 函数名: initialDestination()
// 功能说明: phase 5 结束后该启动入口保持不变；本轮仅验证它仍然会把 App 带到 Board List。
struct AppLaunchCoordinator {
    func initialDestination() -> AppLaunchDestination {
        // Storage and restoration are not wired yet, so start from the board list.
        .boardList
    }
}
```

## 代码状态二：macOS Board List 的打开语义在 `phase 5` 前后保持不变

### 修改前

- `macOS` 侧已有画板走“双击打开”。
- `New Board` 占位项走“选中后立即执行主动作”。
- 这也是本次验证里观察到“已有 board 不是单击立即打开”的代码依据。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift（修改前）
// 函数名: handleCollectionViewDoubleClick(_:) / collectionView(_:didSelectItemsAt:)
// 功能说明: phase 5 验证前，macOS Board List 保持“已有 board 双击打开、New Board 占位项单击即触发主动作”的交互语义。
private func handleCollectionViewDoubleClick(_ gestureRecognizer: NSClickGestureRecognizer) {
    guard
        isTransitionInteractionFrozen == false,
        gestureRecognizer.state == .ended
    else {
        return
    }

    let location = gestureRecognizer.location(in: collectionView)
    guard
        let indexPath = collectionView.indexPathForItem(at: location),
        let entry = entry(at: indexPath),
        entry.isPlaceholder == false
    else {
        return
    }

    selectedEntryID = entry.id
    isSyncingSelection = true
    collectionView.selectItems(
        at: Set([indexPath]),
        scrollPosition: []
    )
    isSyncingSelection = false
    performPrimaryAction(for: entry)
}

func collectionView(
    _ collectionView: NSCollectionView,
    didSelectItemsAt indexPaths: Set<IndexPath>
) {
    guard
        isTransitionInteractionFrozen == false,
        isSyncingSelection == false,
        let indexPath = indexPaths.first,
        let entry = entry(at: indexPath)
    else {
        return
    }

    selectedEntryID = entry.id
    if entry.isPlaceholder {
        performPrimaryAction(for: entry)
        clearPlaceholderSelectionAfterAction()
    }
}
```

### 修改后

- `phase 5` 没有改动 macOS Board List 控制器。
- 本轮验证只是确认这套打开语义仍然存在，并基于这套既有语义判断当前自动化阻塞点。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift（修改后）
// 函数名: handleCollectionViewDoubleClick(_:) / collectionView(_:didSelectItemsAt:)
// 功能说明: phase 5 结束后该交互代码保持不变；本轮只是验证 Board List 仍然沿用这套打开规则。
private func handleCollectionViewDoubleClick(_ gestureRecognizer: NSClickGestureRecognizer) {
    guard
        isTransitionInteractionFrozen == false,
        gestureRecognizer.state == .ended
    else {
        return
    }

    let location = gestureRecognizer.location(in: collectionView)
    guard
        let indexPath = collectionView.indexPathForItem(at: location),
        let entry = entry(at: indexPath),
        entry.isPlaceholder == false
    else {
        return
    }

    selectedEntryID = entry.id
    isSyncingSelection = true
    collectionView.selectItems(
        at: Set([indexPath]),
        scrollPosition: []
    )
    isSyncingSelection = false
    performPrimaryAction(for: entry)
}

func collectionView(
    _ collectionView: NSCollectionView,
    didSelectItemsAt indexPaths: Set<IndexPath>
) {
    guard
        isTransitionInteractionFrozen == false,
        isSyncingSelection == false,
        let indexPath = indexPaths.first,
        let entry = entry(at: indexPath)
    else {
        return
    }

    selectedEntryID = entry.id
    if entry.isPlaceholder {
        performPrimaryAction(for: entry)
        clearPlaceholderSelectionAfterAction()
    }
}
```

## 代码状态三：iOS 端手工验证入口在 `phase 5` 前后保持不变

### 修改前

- `iOS` 端进入这次手工验证时，文字、裁剪、多选这几个入口仍然分别挂在现有 toolbar handler 上。
- `multiSelect` 仍然保留“内联编辑/阅读模式下不允许切换”的 guard。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift（修改前）
// 函数名: handleCropButtonTap() / handleMultiSelectButtonTap() / handleTextButtonTap()
// 功能说明: phase 5 验证前，iOS 端手工验证入口仍然是既有 toolbar handlers，没有为 selectionTranslationArea 再新增新的入口代码。
@objc
private func handleCropButtonTap() {
    performCommand(.crop)
}

@objc
private func handleMultiSelectButtonTap() {
    guard
        editorSession.isInlineEditModeActive == false,
        editorSession.isReadingModeActive == false
    else {
        return
    }

    isMultiSelectModeActive.toggle()
}

@objc
private func handleTextButtonTap() {
    if isInlineTextModeActive {
        performCommand(.commitTextEdit)
    } else {
        performCommand(.addTextItem)
    }
}
```

### 修改后

- `phase 5` 结束后，这些入口代码没有变化。
- 本次只验证了 App 能启动到正确入口；更深一层的点击/拖拽回归仍需人工继续执行。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift（修改后）
// 函数名: handleCropButtonTap() / handleMultiSelectButtonTap() / handleTextButtonTap()
// 功能说明: phase 5 结束后这些 iOS toolbar 入口保持不变；本轮没有新增任何手工验证专用逻辑。
@objc
private func handleCropButtonTap() {
    performCommand(.crop)
}

@objc
private func handleMultiSelectButtonTap() {
    guard
        editorSession.isInlineEditModeActive == false,
        editorSession.isReadingModeActive == false
    else {
        return
    }

    isMultiSelectModeActive.toggle()
}

@objc
private func handleTextButtonTap() {
    if isInlineTextModeActive {
        performCommand(.commitTextEdit)
    } else {
        performCommand(.addTextItem)
    }
}
```

## 代码状态四：阅读模式与多选门控在 `phase 5` 前后保持不变

### 修改前

- 本次验证计划要求阅读模式、多选、裁剪不回归。
- 但 `phase 5` 并没有再改共享 toolbar state builder；这里仍沿用现有门控：
  - 阅读模式下直接隐藏整条 toolbar
  - 多选按钮是否可用继续由 `canToggleMultiSelectMode(session:)` 决定

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift（修改前）
// 函数名: mainToolbarState(...) / canToggleMultiSelectMode(session:)
// 功能说明: phase 5 验证前，共享层仍用现有门控控制阅读模式下工具条隐藏，以及多选按钮启用态。
func mainToolbarState(
    session: CanvasEditorSession,
    saveState: CanvasSaveState,
    placement: CanvasToolbarPlacement,
    isMultiSelectModeActive: Bool = false,
    isImportEnabled: Bool = true,
    showsBackground: Bool = true,
    includesHistoryItems: Bool = false
) -> CanvasToolbarState {
    guard session.isReadingModeActive == false else {
        return CanvasToolbarState(
            placement: placement,
            items: [],
            showsBackground: showsBackground
        )
    }

    var itemStates: [CanvasToolbarItemState] = []
    if includesHistoryItems {
        itemStates.append(contentsOf: historyItemStates(session: session))
    }
    if shouldShowCropItem(session: session) {
        itemStates.append(cropItemState(session: session))
    }
    itemStates.append(
        multiSelectItemState(
            isActive: isMultiSelectModeActive,
            isEnabled: canToggleMultiSelectMode(session: session)
        )
    )
    // ... 其余工具条项省略 ...
}

private func canToggleMultiSelectMode(
    session: CanvasEditorSession
) -> Bool {
    session.isInlineEditModeActive == false
}
```

### 修改后

- `phase 5` 没有改动这层门控代码。
- 因此这次验证只是在运行层确认：手工回归仍应基于这套现有条件展开，而不是引入新的工具条逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift（修改后）
// 函数名: mainToolbarState(...) / canToggleMultiSelectMode(session:)
// 功能说明: phase 5 结束后，共享工具条门控逻辑保持不变；本轮只是验证它仍然是当前回归边界的一部分。
func mainToolbarState(
    session: CanvasEditorSession,
    saveState: CanvasSaveState,
    placement: CanvasToolbarPlacement,
    isMultiSelectModeActive: Bool = false,
    isImportEnabled: Bool = true,
    showsBackground: Bool = true,
    includesHistoryItems: Bool = false
) -> CanvasToolbarState {
    guard session.isReadingModeActive == false else {
        return CanvasToolbarState(
            placement: placement,
            items: [],
            showsBackground: showsBackground
        )
    }

    var itemStates: [CanvasToolbarItemState] = []
    if includesHistoryItems {
        itemStates.append(contentsOf: historyItemStates(session: session))
    }
    if shouldShowCropItem(session: session) {
        itemStates.append(cropItemState(session: session))
    }
    itemStates.append(
        multiSelectItemState(
            isActive: isMultiSelectModeActive,
            isEnabled: canToggleMultiSelectMode(session: session)
        )
    )
    // ... 其余工具条项省略 ...
}

private func canToggleMultiSelectMode(
    session: CanvasEditorSession
) -> Bool {
    session.isInlineEditModeActive == false
}
```

## 验证情况

- 构建验证：
  - `macOS` 构建通过：
    - `xcodebuild -scheme "MyCanvas_Ver_0" -project ".../MyCanvas_Ver_0.xcodeproj" -destination 'platform=macOS' build`
  - `iOS Simulator` 构建通过：
    - `xcodebuild -scheme "MyCanvas_Ver_0" -project ".../MyCanvas_Ver_0.xcodeproj" -destination 'platform=iOS Simulator,id=D71F3801-D496-43A0-BE46-CACF8B2D0322' build`
- 启动验证：
  - `macOS` App 已成功启动到 `Board List`，首屏可见已有存储目录 `MyCanvas` 与现成 board 列表
  - `iOS Simulator` App 已成功启动到 `Board List`，但首屏状态为 `No Folder Selected`
- 自动化探测过程中发现：
  - `macOS` 若继续深入用桌面自动化去选板卡/拖画布，会开始干扰当前桌面环境
  - 因此本阶段在“构建 + 启动 + 首屏状态确认”处收口，没有继续冒进做系统级桌面操作
- 额外文件状态：
  - `UserInterfaceState.xcuserstate` 在验证后发生变动
  - 已按用户明确选择保留该状态文件变动，不在本阶段清理

## 结论

- `phase 5` 本次只完成了启动级与构建级验证，没有新增源码改动。
- 当前可以确认：
  - `selectionTranslationArea` 相关改动没有把双端应用的构建与启动链路打坏。
- 当前仍待人工完成的验证项：
  - 单选文字：拖边框移动、点正文进入编辑、拖角点缩放
  - 单选图片：拖边框移动、正文拖动移动、空白处拖动画布
  - 多选：拖群组选框边框、成员之间空白整体移动
  - 旋转手柄、裁剪模式、阅读模式不回归
