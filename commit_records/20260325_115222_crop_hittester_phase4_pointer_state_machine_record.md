# 20260325_115222_crop_hittester_phase4_pointer_state_machine_record

## 记录范围

- 记录内容：
  - 在 `iOS/macOS` 控制器中新增本地 `PointerPressTargetKind` 语义适配层。
  - 让控制器状态机从直接消费 `CanvasContextMenuContext.targetKind`，切换为先消费 `editOverlayHitTargetKind` / `PointerPressTargetKind`，再决定拖拽分支。
  - 把点击日志与历史事务语义同步切到 `cropTranslationArea`。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：
  - `Phase 5` 的 pointer / menu 彻底解耦
  - `CanvasEditorSession` / `CanvasContextResolver` 入口改造
  - 其它共享层命中逻辑修改

## 修改一：给双端控制器增加本地 `PointerPressTargetKind` 适配层

### 修改前

- `iOS/macOS` 控制器里的 `PointerDragState.pressed` 直接保存 `CanvasContextMenuContext`。
- 后续拖拽分支、点击日志、history transaction 都直接 `switch pressContext.targetKind`。
- 这意味着虽然共享层已经有了 `editOverlayHitTargetKind` 和 `cropTranslationArea`，控制器仍然只认识旧的 `.cropOutline`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerMove(to:from:)
// 功能说明: 修改前 iOS 控制器直接根据 pressContext.targetKind 决定输入分支，仍然依赖旧的菜单 target 语义。
switch pressContext.targetKind {
case .rotateHandle:
    // ...
case let .cropHandle(handleRole):
    // ...
case .cropOutline:
    guard let itemID = pressContext.targetItemID else {
        editorSession.cancelPendingHistoryTransaction()
        pointerDragState = .idle
        return
    }

    guard let translationState = makePointerCropTranslationState(
        itemID: itemID,
        initialViewportLocation: pressedLocation
    ) else {
        editorSession.cancelPendingHistoryTransaction()
        pointerDragState = .idle
        return
    }

    pointerDragState = .movingCropFrame(translationState)
    updateTranslatedCropDraft(using: translationState, to: location)
case let .selectionHandle(handleRole):
    // ...
case .selectedItemBody:
    // ...
case .unselectedItemBody, .blank:
    // ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handlePrimaryPointerMove(to:from:)
// 功能说明: 修改前 macOS 控制器和 iOS 一样，仍然只通过 pressContext.targetKind 识别 cropOutline，而不会直接消费共享层的 cropTranslationArea。
switch pressContext.targetKind {
case .rotateHandle:
    // ...
case let .cropHandle(handleRole):
    // ...
case .cropOutline:
    guard let itemID = pressContext.targetItemID else {
        editorSession.cancelPendingHistoryTransaction()
        pointerDragState = .idle
        return
    }

    guard let translationState = makePointerCropTranslationState(
        itemID: itemID,
        initialViewportLocation: pressedLocation
    ) else {
        editorSession.cancelPendingHistoryTransaction()
        pointerDragState = .idle
        return
    }

    pointerDragState = .movingCropFrame(translationState)
    updateTranslatedCropDraft(using: translationState, to: location)
case let .selectionHandle(handleRole):
    // ...
case .selectedItemBody:
    // ...
case .unselectedItemBody, .blank:
    // ...
}
```

### 修改后

- 双端控制器都新增了本地 `PointerPressTargetKind`。
- 新增 `pointerPressTargetKind(for:)`，优先消费 `pressContext.editOverlayHitTargetKind`，在共享层没有提供内部 target 时再回退到旧的 `pressContext.targetKind`。
- 这样 `Phase 4` 不需要提前改 `CanvasEditorSession` / `resolveContext` 返回类型，就能让控制器真正按新的输入语义运行。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: PointerPressTargetKind / pointerPressTargetKind(for:)
// 功能说明: 修改后 iOS 控制器会先把 CanvasContextMenuContext 翻译成控制器自己的指针语义，再驱动状态机。
private enum PointerPressTargetKind {
    case rotateHandle
    case cropHandle(CanvasCropHandleRole)
    case cropTranslationArea
    case selectionHandle(CanvasSelectionHandleRole)
    case selectedItemBody
    case unselectedItemBody
    case blank
}

private func pointerPressTargetKind(
    for pressContext: CanvasContextMenuContext
) -> PointerPressTargetKind {
    if let editOverlayHitTargetKind = pressContext.editOverlayHitTargetKind {
        switch editOverlayHitTargetKind {
        case .rotateHandle:
            return .rotateHandle
        case let .selectionHandle(role):
            return .selectionHandle(role)
        case let .cropHandle(role):
            return .cropHandle(role)
        case .cropTranslationArea:
            return .cropTranslationArea
        }
    }

    switch pressContext.targetKind {
    case .rotateHandle:
        return .rotateHandle
    case let .cropHandle(role):
        return .cropHandle(role)
    case .cropOutline:
        return .cropTranslationArea
    case let .selectionHandle(role):
        return .selectionHandle(role)
    case .selectedItemBody:
        return .selectedItemBody
    case .unselectedItemBody:
        return .unselectedItemBody
    case .blank:
        return .blank
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: PointerPressTargetKind / pointerPressTargetKind(for:)
// 功能说明: 修改后 macOS 控制器与 iOS 保持镜像实现，同样先把共享上下文翻译成控制器自己的指针目标语义。
private enum PointerPressTargetKind {
    case rotateHandle
    case cropHandle(CanvasCropHandleRole)
    case cropTranslationArea
    case selectionHandle(CanvasSelectionHandleRole)
    case selectedItemBody
    case unselectedItemBody
    case blank
}

private func pointerPressTargetKind(
    for pressContext: CanvasContextMenuContext
) -> PointerPressTargetKind {
    if let editOverlayHitTargetKind = pressContext.editOverlayHitTargetKind {
        switch editOverlayHitTargetKind {
        case .rotateHandle:
            return .rotateHandle
        case let .selectionHandle(role):
            return .selectionHandle(role)
        case let .cropHandle(role):
            return .cropHandle(role)
        case .cropTranslationArea:
            return .cropTranslationArea
        }
    }

    switch pressContext.targetKind {
    case .rotateHandle:
        return .rotateHandle
    case let .cropHandle(role):
        return .cropHandle(role)
    case .cropOutline:
        return .cropTranslationArea
    case let .selectionHandle(role):
        return .selectionHandle(role)
    case .selectedItemBody:
        return .selectedItemBody
    case .unselectedItemBody:
        return .unselectedItemBody
    case .blank:
        return .blank
    }
}
```

## 修改二：把拖拽分支正式切到 `cropTranslationArea`

### 修改前

- `handlePrimaryPointerMove(to:from:)` 只有 `.cropOutline` 才会进入 `movingCropFrame`。
- 即便共享层已经把裁剪框内部识别成 `cropTranslationArea`，控制器在这一步仍不会直接按新语义分支。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerMove(to:from:)
// 功能说明: 修改前 iOS 控制器只有旧的 cropOutline 分支会进入 movingCropFrame。
switch pressContext.targetKind {
case .rotateHandle:
    // ...
case let .cropHandle(handleRole):
    // ...
case .cropOutline:
    guard let itemID = pressContext.targetItemID else {
        editorSession.cancelPendingHistoryTransaction()
        pointerDragState = .idle
        return
    }
    // ...
    pointerDragState = .movingCropFrame(translationState)
    updateTranslatedCropDraft(using: translationState, to: location)
case let .selectionHandle(handleRole):
    // ...
case .selectedItemBody:
    // ...
case .unselectedItemBody, .blank:
    // ...
}
```

### 修改后

- `handlePrimaryPointerMove(to:from:)` 现在改为 `switch pointerPressTargetKind(for: pressContext)`。
- `cropTranslationArea` 会直接进入现有的 `movingCropFrame` 路径。
- `cropHandle` 仍然只负责 resize，`blank` 仍然保持画布 pan。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerMove(to:from:)
// 功能说明: 修改后 iOS 控制器直接按 cropTranslationArea 语义进入现有 movingCropFrame 流程，不再依赖旧的 cropOutline 分支名。
switch pointerPressTargetKind(for: pressContext) {
case .rotateHandle:
    // ...
case let .cropHandle(handleRole):
    // ...
case .cropTranslationArea:
    guard let itemID = pressContext.targetItemID else {
        editorSession.cancelPendingHistoryTransaction()
        pointerDragState = .idle
        return
    }
    // ...
    pointerDragState = .movingCropFrame(translationState)
    updateTranslatedCropDraft(using: translationState, to: location)
case let .selectionHandle(handleRole):
    // ...
case .selectedItemBody:
    // ...
case .unselectedItemBody, .blank:
    // ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handlePrimaryPointerMove(to:from:)
// 功能说明: 修改后 macOS 控制器与 iOS 一样，已经按 cropTranslationArea 语义进入 movingCropFrame，而不是继续依赖旧的 cropOutline case。
switch pointerPressTargetKind(for: pressContext) {
case .rotateHandle:
    // ...
case let .cropHandle(handleRole):
    // ...
case .cropTranslationArea:
    guard let itemID = pressContext.targetItemID else {
        editorSession.cancelPendingHistoryTransaction()
        pointerDragState = .idle
        return
    }
    // ...
    pointerDragState = .movingCropFrame(translationState)
    updateTranslatedCropDraft(using: translationState, to: location)
case let .selectionHandle(handleRole):
    // ...
case .selectedItemBody:
    // ...
case .unselectedItemBody, .blank:
    // ...
}
```

## 修改三：同步点击日志和 history transaction 语义

### 修改前

- 点击日志里的 `clickTarget` 仍然写成 `"crop_outline"`。
- `beginPointerHistoryTransactionIfNeeded` 也还是把 `.cropOutline` 归到 `"crop item"`。
- 这会导致运行时已经按 `cropTranslationArea` 工作，但埋点和历史语义仍然停留在旧名字上。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerUp(at:)
// 功能说明: 修改前 iOS 点击日志仍然只认识 cropOutline，clickTarget 会记录为 crop_outline。
switch pressContext.targetKind {
case .rotateHandle:
    clickTarget = "rotate_handle"
case .cropHandle:
    clickTarget = "crop_handle"
case .cropOutline:
    clickTarget = "crop_outline"
case .selectionHandle:
    clickTarget = "handle"
case .selectedItemBody, .unselectedItemBody:
    // ...
case .blank:
    // ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: beginPointerHistoryTransactionIfNeeded(for:)
// 功能说明: 修改前 iOS 历史事务仍通过旧的 cropOutline case 决定 crop item 事务语义。
switch pressContext.targetKind {
case .rotateHandle:
    reason = "rotate item"
case .cropHandle, .cropOutline:
    reason = "crop item"
case .selectionHandle:
    reason = "resize item"
case .selectedItemBody:
    reason = "move item"
case .unselectedItemBody, .blank:
    return
}
```

### 修改后

- 点击日志改成记录 `"crop_translation_area"`。
- 历史事务改为按 `.cropTranslationArea` 归类到 `"crop item"`。
- 两端 `iOS/macOS` 都做了同样的镜像修改。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerUp(at:)
// 功能说明: 修改后 iOS 点击日志会按新的控制器语义记录 crop_translation_area，而不是继续沿用旧的 crop_outline。
switch pointerPressTargetKind(for: pressContext) {
case .rotateHandle:
    clickTarget = "rotate_handle"
case .cropHandle:
    clickTarget = "crop_handle"
case .cropTranslationArea:
    clickTarget = "crop_translation_area"
case .selectionHandle:
    clickTarget = "handle"
case .selectedItemBody, .unselectedItemBody:
    // ...
case .blank:
    // ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: beginPointerHistoryTransactionIfNeeded(for:)
// 功能说明: 修改后 macOS 历史事务和 iOS 保持一致，cropTranslationArea 会进入 crop item 事务。
switch pointerPressTargetKind(for: pressContext) {
case .rotateHandle:
    reason = "rotate item"
case .cropHandle, .cropTranslationArea:
    reason = "crop item"
case .selectionHandle:
    reason = "resize item"
case .selectedItemBody:
    reason = "move item"
case .unselectedItemBody, .blank:
    return
}
```

## 本次修改结果

- 双端控制器已经真正按 `cropTranslationArea` 语义驱动输入状态机。
- 裁剪框内部命中现在会直接复用现有的 `movingCropFrame` 流程。
- 点击日志和 history transaction 也同步切到了新的语义命名，不再继续残留 `crop_outline`。
- 这一步仍然没有做 `Phase 5` 的彻底解耦；控制器仍然接收 `CanvasContextMenuContext`，只是先本地翻译成了 `PointerPressTargetKind`。

## 本次验证

- 已检查改动范围，仅涉及：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 已通过 IDE lint 检查，当前无新增 linter 报错。
- 未执行完整 Xcode build；当前命令行环境下 `xcodebuild` 不能直接使用完整 Xcode 构建链路。
