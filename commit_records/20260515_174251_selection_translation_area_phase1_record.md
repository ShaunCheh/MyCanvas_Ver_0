# 20260515_174251_selection_translation_area_phase1_record

## 记录范围

- 记录内容：
  - 为 `selectionTranslationArea` 补齐 `Phase 1` 所需的共享契约，包含 hit target 枚举、pointer target 枚举、resolver metrics 字段。
  - 在 `CanvasContextResolver` 中补齐日志 branch、内部 target 映射，以及对上下文菜单的兼容折叠策略。
  - 在 `CanvasClickSelectionResolver` 中为新 target 预留点击语义，占位返回 `.none`。
  - 在 iOS / macOS 控制器中接入新的 resolver metric，并补齐 `switch` 分支，保证当前阶段可编译，但不提前接入真实拖动行为。
  - 更新测试辅助里的 `CanvasContextResolverMetrics` 构造参数，保持测试代码与主代码契约一致。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasPointerPressContext.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift`
  - `MyCanvas_Ver_0/Canvas/Input/CanvasClickSelectionResolver.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift`
- 当前 working tree 的附带变更：
  - `MyCanvas_Ver_0.xcodeproj/project.xcworkspace/xcuserdata/shaun.xcuserdatad/UserInterfaceState.xcuserstate`
  - 该文件为 IDE 状态文件，属于二进制用户态变化；本记录如实注明，但不展开源码片段。
- 本记录不包含：
  - `Phase 2` 的 `selectionTranslationArea` 几何命中实现
  - `Phase 3` 的真实 move 分发接线
  - 任何 `.md` 计划文件内容调整

## 当前 changes 摘要

- 当前源码层面的变更，全部围绕 `selectionTranslationArea` 的“类型契约补齐”和“编译安全占位”展开。
- 当前没有把 `selectionTranslationArea` 接入真实交互，因此这一轮不会改变 UI 行为。
- iOS / macOS 控制器中的新增分支，当前是显式取消事务并回到 `.idle`，其作用是：
  - 让 `switch` 在新增枚举后保持穷尽；
  - 避免在 `Phase 2 / 3` 之前出现未定义行为；
  - 明确表达“契约已建，行为尚未接通”。

## 修改一：在共享 hit target 契约中引入 `selectionTranslationArea`

### 修改前

- `CanvasEditOverlayHitTargetKind` 只有 selection handle、group selection handle、crop handle、crop translation 等既有语义。
- 共享命中层还没有 `selectionTranslationArea` 这个内部 target 名称。
- 因此后续即便要做 selection overlay 的平移热区，也没有统一的内部命名承载点。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// 函数名: CanvasEditOverlayHitTargetKind.debugName（类型定义与调试文本同块展示）
// 功能说明: 修改前共享命中层只有 selection/crop 的既有 target，没有 selectionTranslationArea。
enum CanvasEditOverlayHitTargetKind {
    case rotateHandle
    case groupRotateHandle
    case selectionHandle(role: CanvasSelectionHandleRole)
    case groupSelectionHandle(role: CanvasSelectionHandleRole)
    case cropHandle(role: CanvasCropHandleRole)
    case cropTranslationArea

    var debugName: String {
        switch self {
        case .rotateHandle:
            return "rotateHandle"
        case .groupRotateHandle:
            return "groupRotateHandle"
        case let .selectionHandle(role):
            return "selectionHandle(\(String(describing: role)))"
        case let .groupSelectionHandle(role):
            return "groupSelectionHandle(\(String(describing: role)))"
        case let .cropHandle(role):
            return "cropHandle(\(String(describing: role)))"
        case .cropTranslationArea:
            return "cropTranslationArea"
        }
    }
}
```

### 修改后

- 新增 `selectionTranslationArea` case。
- 同时给 `debugName` 补上 `"selectionTranslationArea"`。
- 到这一阶段为止，它只是一条共享命中层契约，还没有进入真实 hit test 判定。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// 函数名: CanvasEditOverlayHitTargetKind.debugName（类型定义与调试文本同块展示）
// 功能说明: 修改后共享命中层已经拥有 selectionTranslationArea 这个内部命中语义名，供后续 Phase 2 / 3 接线使用。
enum CanvasEditOverlayHitTargetKind {
    case rotateHandle
    case groupRotateHandle
    case selectionHandle(role: CanvasSelectionHandleRole)
    case groupSelectionHandle(role: CanvasSelectionHandleRole)
    case selectionTranslationArea
    case cropHandle(role: CanvasCropHandleRole)
    case cropTranslationArea

    var debugName: String {
        switch self {
        case .rotateHandle:
            return "rotateHandle"
        case .groupRotateHandle:
            return "groupRotateHandle"
        case let .selectionHandle(role):
            return "selectionHandle(\(String(describing: role)))"
        case let .groupSelectionHandle(role):
            return "groupSelectionHandle(\(String(describing: role)))"
        case .selectionTranslationArea:
            return "selectionTranslationArea"
        case let .cropHandle(role):
            return "cropHandle(\(String(describing: role)))"
        case .cropTranslationArea:
            return "cropTranslationArea"
        }
    }
}
```

## 修改二：在 pointer target 契约中同步引入 `selectionTranslationArea`

### 修改前

- `CanvasPointerTargetKind` 里只有 `cropTranslationArea`，没有 selection 对称项。
- 控制器和点击选择层只能识别正文、handle、crop translation 这些既有 target。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasPointerPressContext.swift
// 函数名: CanvasPointerTargetKind.debugName（类型定义与调试文本同块展示）
// 功能说明: 修改前 pointer target 没有 selectionTranslationArea，因此平台控制器无法对这个语义做显式分支。
enum CanvasPointerTargetKind {
    case rotateHandle
    case groupRotateHandle
    case cropHandle(role: CanvasCropHandleRole)
    case cropTranslationArea
    case selectionHandle(role: CanvasSelectionHandleRole)
    case groupSelectionHandle(role: CanvasSelectionHandleRole)
    case selectedItemBody
    case unselectedItemBody
    case blank
}
```

### 修改后

- `CanvasPointerTargetKind` 新增 `selectionTranslationArea`。
- `debugName` 同步补齐，供日志和调试输出使用。
- 这一步把共享层内部 target 和平台层外部 pointer 语义打通了命名。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasPointerPressContext.swift
// 函数名: CanvasPointerTargetKind.debugName（类型定义与调试文本同块展示）
// 功能说明: 修改后 pointer target 已能显式承载 selectionTranslationArea，为控制器和点击选择层预留分发入口。
enum CanvasPointerTargetKind {
    case rotateHandle
    case groupRotateHandle
    case cropHandle(role: CanvasCropHandleRole)
    case cropTranslationArea
    case selectionHandle(role: CanvasSelectionHandleRole)
    case groupSelectionHandle(role: CanvasSelectionHandleRole)
    case selectionTranslationArea
    case selectedItemBody
    case unselectedItemBody
    case blank

    var debugName: String {
        switch self {
        case .rotateHandle:
            return "rotateHandle"
        case .groupRotateHandle:
            return "groupRotateHandle"
        case let .cropHandle(role):
            return "cropHandle(\(String(describing: role)))"
        case .cropTranslationArea:
            return "cropTranslationArea"
        case let .selectionHandle(role):
            return "selectionHandle(\(String(describing: role)))"
        case let .groupSelectionHandle(role):
            return "groupSelectionHandle(\(String(describing: role)))"
        case .selectionTranslationArea:
            return "selectionTranslationArea"
        case .selectedItemBody:
            return "selectedItemBody"
        case .unselectedItemBody:
            return "unselectedItemBody"
        case .blank:
            return "blank"
        }
    }
}
```

## 修改三：扩展 resolver metrics，并在 resolver 层补齐新 target 的日志与菜单折叠

### 修改前

- `CanvasContextResolverMetrics` 只有 selection handle / crop handle / crop outline / rotate handle 四类参数。
- `contextResolverBranch(for:)`、`resolvedTarget(from:)`、`contextMenuTargetKind(for:)` 都没有 `selectionTranslationArea` 分支。
- 因此即便新增枚举，也没有 resolver 层的透传和菜单兼容逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数名: CanvasContextResolverMetrics / contextResolverBranch(for:) / resolvedTarget(from:) / contextMenuTargetKind(for:)
// 功能说明: 修改前 resolver 既没有 selectionOutlineHitTargetWidth，也没有对 selectionTranslationArea 的内部映射与菜单折叠。
struct CanvasContextResolverMetrics {
    let selectionHandleHitTargetSize: CGFloat
    let cropHandleHitTargetSize: CGFloat
    let cropOutlineHitTargetWidth: CGFloat
    let rotateHandleHitTargetSize: CGFloat
}

private func contextResolverBranch(
    for hitTarget: CanvasEditOverlayHitTarget
) -> String {
    switch hitTarget.kind {
    case .rotateHandle,
         .groupRotateHandle,
         .selectionHandle,
         .groupSelectionHandle,
         .cropHandle:
        return "editHandle"
    case .cropTranslationArea:
        return hitTarget.kind.debugName
    }
}

private func resolvedTarget(
    from hitTarget: CanvasEditOverlayHitTarget
) -> ResolvedTarget {
    let pointerTargetKind: CanvasPointerTargetKind
    switch hitTarget.kind {
    case .rotateHandle:
        pointerTargetKind = .rotateHandle
    case .groupRotateHandle:
        pointerTargetKind = .groupRotateHandle
    case let .selectionHandle(role):
        pointerTargetKind = .selectionHandle(role: role)
    case let .groupSelectionHandle(role):
        pointerTargetKind = .groupSelectionHandle(role: role)
    case let .cropHandle(role):
        pointerTargetKind = .cropHandle(role: role)
    case .cropTranslationArea:
        pointerTargetKind = .cropTranslationArea
    }
    // ...
}

private func contextMenuTargetKind(
    for pointerTargetKind: CanvasPointerTargetKind
) -> CanvasContextMenuTargetKind {
    switch pointerTargetKind {
    case .rotateHandle:
        return .rotateHandle
    case .groupRotateHandle:
        return .groupRotateHandle
    case let .cropHandle(role):
        return .cropHandle(role: role)
    case .cropTranslationArea:
        return .cropOutline
    case let .selectionHandle(role):
        return .selectionHandle(role: role)
    case let .groupSelectionHandle(role):
        return .groupSelectionHandle(role: role)
    case .selectedItemBody:
        return .selectedItemBody
    case .unselectedItemBody:
        return .unselectedItemBody
    case .blank:
        return .blank
    }
}
```

### 修改后

- `CanvasContextResolverMetrics` 新增 `selectionOutlineHitTargetWidth`，为后续 selection ring / interior blank 命中预留独立参数。
- `contextResolverBranch(for:)` 现在能单独输出 `selectionTranslationArea`，日志语义已补齐。
- `resolvedTarget(from:)` 把内部 hit target 映射到外部 pointer target。
- `contextMenuTargetKind(for:)` 先把 `selectionTranslationArea` 折叠成 `.selectedItemBody`，保证菜单层暂时不膨胀新矩阵。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数名: CanvasContextResolverMetrics / contextResolverBranch(for:) / resolvedTarget(from:) / contextMenuTargetKind(for:)
// 功能说明: 修改后 resolver 既有独立的 selectionOutlineHitTargetWidth，也具备 selectionTranslationArea 的日志、映射和菜单兼容策略。
struct CanvasContextResolverMetrics {
    let selectionHandleHitTargetSize: CGFloat
    let selectionOutlineHitTargetWidth: CGFloat
    let cropHandleHitTargetSize: CGFloat
    let cropOutlineHitTargetWidth: CGFloat
    let rotateHandleHitTargetSize: CGFloat
}

private func contextResolverBranch(
    for hitTarget: CanvasEditOverlayHitTarget
) -> String {
    switch hitTarget.kind {
    case .rotateHandle,
         .groupRotateHandle,
         .selectionHandle,
         .groupSelectionHandle,
         .cropHandle:
        return "editHandle"
    case .selectionTranslationArea,
         .cropTranslationArea:
        return hitTarget.kind.debugName
    }
}

private func resolvedTarget(
    from hitTarget: CanvasEditOverlayHitTarget
) -> ResolvedTarget {
    let pointerTargetKind: CanvasPointerTargetKind
    switch hitTarget.kind {
    case .rotateHandle:
        pointerTargetKind = .rotateHandle
    case .groupRotateHandle:
        pointerTargetKind = .groupRotateHandle
    case let .selectionHandle(role):
        pointerTargetKind = .selectionHandle(role: role)
    case let .groupSelectionHandle(role):
        pointerTargetKind = .groupSelectionHandle(role: role)
    case .selectionTranslationArea:
        pointerTargetKind = .selectionTranslationArea
    case let .cropHandle(role):
        pointerTargetKind = .cropHandle(role: role)
    case .cropTranslationArea:
        pointerTargetKind = .cropTranslationArea
    }
    // 这里仍然只是 resolver 级映射，还没有接真实命中几何。
    return ResolvedTarget(
        pointerTargetKind: pointerTargetKind,
        editOverlayHitTargetKind: hitTarget.kind,
        targetItemID: hitTarget.itemID,
        anchorRect: hitTarget.anchorRect
    )
}

private func contextMenuTargetKind(
    for pointerTargetKind: CanvasPointerTargetKind
) -> CanvasContextMenuTargetKind {
    switch pointerTargetKind {
    case .rotateHandle:
        return .rotateHandle
    case .groupRotateHandle:
        return .groupRotateHandle
    case let .cropHandle(role):
        return .cropHandle(role: role)
    case .cropTranslationArea:
        return .cropOutline
    case let .selectionHandle(role):
        return .selectionHandle(role: role)
    case let .groupSelectionHandle(role):
        return .groupSelectionHandle(role: role)
    case .selectionTranslationArea:
        return .selectedItemBody
    case .selectedItemBody:
        return .selectedItemBody
    case .unselectedItemBody:
        return .unselectedItemBody
    case .blank:
        return .blank
    }
}
```

## 修改四：为点击选择层补齐 `selectionTranslationArea` 的占位点击语义

### 修改前

- `CanvasClickSelectionResolver.resolve(...)` 不认识 `selectionTranslationArea`。
- 一旦 pointer target 枚举新增该 case，而这里不补分支，编译期就会因为 `switch` 不穷尽而失败。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasClickSelectionResolver.swift
// 函数名: resolve(pressTargetKind:pressedItemID:releasedItemID:selection:isPersistentMultiSelectModeEnabled:pressedModifiers:releasedModifiers:)
// 功能说明: 修改前点击选择层只处理 cropTranslationArea，没有 selectionTranslationArea 的占位点击策略。
switch pressTargetKind {
case .rotateHandle:
    // ...
case .groupRotateHandle:
    // ...
case .cropHandle:
    // ...
case .cropTranslationArea:
    return CanvasClickSelectionDecision(
        target: "crop_translation_area",
        affectedItemID: pressedItemID,
        action: .none
    )
case .selectionHandle:
    // ...
case .groupSelectionHandle:
    // ...
case .selectedItemBody, .unselectedItemBody:
    // ...
case .blank:
    // ...
}
```

### 修改后

- 新增 `case .selectionTranslationArea`。
- 当前阶段显式返回 `.none`，表示“契约已经存在，但真实 selection translation 点击/拖动语义尚未接通”。
- 这样不会误伤 `selectedItemBody` 的单选文字点击编辑逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasClickSelectionResolver.swift
// 函数名: resolve(pressTargetKind:pressedItemID:releasedItemID:selection:isPersistentMultiSelectModeEnabled:pressedModifiers:releasedModifiers:)
// 功能说明: 修改后点击选择层对 selectionTranslationArea 采用显式 no-op，占位但不冒然改变现有正文点击语义。
switch pressTargetKind {
case .rotateHandle:
    // ...
case .groupRotateHandle:
    // ...
case .cropHandle:
    // ...
case .cropTranslationArea:
    return CanvasClickSelectionDecision(
        target: "crop_translation_area",
        affectedItemID: pressedItemID,
        action: .none
    )
case .selectionHandle:
    // ...
case .groupSelectionHandle:
    // ...
case .selectionTranslationArea:
    return CanvasClickSelectionDecision(
        target: "selection_translation_area",
        affectedItemID: pressedItemID,
        action: .none
    )
case .selectedItemBody, .unselectedItemBody:
    // 现有 selectedItemBody -> attemptTextEdit 逻辑保持不变。
    // ...
case .blank:
    // ...
}
```

## 修改五：在 iOS 控制器中接入 metric 并补齐占位分支

### 修改前

- iOS 只有 `selectionHandleHitTargetSize`，没有独立的 `selectionOutlineHitTargetWidth`。
- `contextResolverMetrics` 构造也没有传这个参数。
- `handlePrimaryPointerMove(...)` 与 `beginPointerHistoryTransactionIfNeeded(...)` 没有 `selectionTranslationArea` 分支。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: contextResolverMetrics / handlePrimaryPointerMove(to:from:) / beginPointerHistoryTransactionIfNeeded(for:)
// 功能说明: 修改前 iOS 控制器只知道既有的 handle/body/crop target，没有 selectionTranslationArea 的 metric 与显式分支。
private static let selectionHandleHitTargetSize: CGFloat = 28
private static let cropHandleHitTargetSize: CGFloat = 28
private static let cropOutlineHitTargetWidth: CGFloat = 20
private static let rotateHandleHitTargetSize: CGFloat = 32

private var contextResolverMetrics: CanvasContextResolverMetrics {
    CanvasContextResolverMetrics(
        selectionHandleHitTargetSize: Self.selectionHandleHitTargetSize,
        cropHandleHitTargetSize: Self.cropHandleHitTargetSize,
        cropOutlineHitTargetWidth: Self.cropOutlineHitTargetWidth,
        rotateHandleHitTargetSize: Self.rotateHandleHitTargetSize
    )
}

switch pressContext.targetKind {
case let .selectionHandle(handleRole):
    // ...
case let .groupSelectionHandle(handleRole):
    // ...
case .selectedItemBody:
    // ...
case .unselectedItemBody, .blank:
    // ...
}
```

### 修改后

- iOS 新增 `selectionOutlineHitTargetWidth = 20`，并传入 `contextResolverMetrics`。
- `handlePrimaryPointerMove(...)` 新增 `case .selectionTranslationArea`，当前显式取消事务并回到 `.idle`。
- `beginPointerHistoryTransactionIfNeeded(...)` 也新增对应分支，当前直接 `return`，避免提前把它当 move 语义提交历史。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: contextResolverMetrics / handlePrimaryPointerMove(to:from:) / beginPointerHistoryTransactionIfNeeded(for:)
// 功能说明: 修改后 iOS 先完成 phase 1 契约接线；selectionTranslationArea 目前只做编译安全占位，不触发真实移动。
private static let selectionHandleHitTargetSize: CGFloat = 28
private static let selectionOutlineHitTargetWidth: CGFloat = 20
private static let cropHandleHitTargetSize: CGFloat = 28
private static let cropOutlineHitTargetWidth: CGFloat = 20
private static let rotateHandleHitTargetSize: CGFloat = 32

private var contextResolverMetrics: CanvasContextResolverMetrics {
    CanvasContextResolverMetrics(
        selectionHandleHitTargetSize: Self.selectionHandleHitTargetSize,
        selectionOutlineHitTargetWidth: Self.selectionOutlineHitTargetWidth,
        cropHandleHitTargetSize: Self.cropHandleHitTargetSize,
        cropOutlineHitTargetWidth: Self.cropOutlineHitTargetWidth,
        rotateHandleHitTargetSize: Self.rotateHandleHitTargetSize
    )
}

switch pressContext.targetKind {
case let .selectionHandle(handleRole):
    // ...
case let .groupSelectionHandle(handleRole):
    // ...
case .selectionTranslationArea:
    // Phase 1 只补齐占位分支，明确当前还未接 move 语义。
    editorSession.cancelPendingHistoryTransaction()
    pointerDragState = .idle
case .selectedItemBody:
    // ...
case .unselectedItemBody, .blank:
    // ...
}

switch pressContext.targetKind {
case .rotateHandle:
    reason = "rotate item"
case .groupRotateHandle:
    reason = "rotate selection"
case .cropHandle, .cropTranslationArea:
    reason = "crop item"
case .selectionHandle:
    reason = "resize item"
case .groupSelectionHandle:
    reason = "resize selection"
case .selectionTranslationArea:
    // Phase 1 不提前把它并入 move item / move selection 的历史事务。
    return
case .selectedItemBody:
    reason = interactionState.selectionCount > 1 ? "move selection" : "move item"
case .unselectedItemBody, .blank:
    return
}
```

## 修改六：在 macOS 控制器中做与 iOS 对称的占位接线

### 修改前

- macOS 和 iOS 一样，只有 `selectionHandleHitTargetSize`，没有 `selectionOutlineHitTargetWidth`。
- 也没有 `selectionTranslationArea` 的占位 `switch` 分支。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: contextResolverMetrics / handlePrimaryPointerMove(to:from:) / beginPointerHistoryTransactionIfNeeded(for:)
// 功能说明: 修改前 macOS 控制器与 iOS 一样，还没有 selectionTranslationArea 的 metric 与显式占位分支。
private static let selectionHandleHitTargetSize: CGFloat = 18
private static let cropHandleHitTargetSize: CGFloat = 18
private static let cropOutlineHitTargetWidth: CGFloat = 14
private static let rotateHandleHitTargetSize: CGFloat = 22

private var contextResolverMetrics: CanvasContextResolverMetrics {
    CanvasContextResolverMetrics(
        selectionHandleHitTargetSize: Self.selectionHandleHitTargetSize,
        cropHandleHitTargetSize: Self.cropHandleHitTargetSize,
        cropOutlineHitTargetWidth: Self.cropOutlineHitTargetWidth,
        rotateHandleHitTargetSize: Self.rotateHandleHitTargetSize
    )
}
```

### 修改后

- macOS 新增 `selectionOutlineHitTargetWidth = 14`，与现有 `cropOutlineHitTargetWidth` 数量级对齐，但语义独立。
- `handlePrimaryPointerMove(...)` 和 `beginPointerHistoryTransactionIfNeeded(...)` 也补了 `selectionTranslationArea` 占位分支。
- 这样 iOS / macOS 两个平台的 shared contract 已经保持对称。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: contextResolverMetrics / handlePrimaryPointerMove(to:from:) / beginPointerHistoryTransactionIfNeeded(for:)
// 功能说明: 修改后 macOS 与 iOS 同步完成 phase 1 契约接线，仍然保持“只占位、不提前接 move 行为”的边界。
private static let selectionHandleHitTargetSize: CGFloat = 18
private static let selectionOutlineHitTargetWidth: CGFloat = 14
private static let cropHandleHitTargetSize: CGFloat = 18
private static let cropOutlineHitTargetWidth: CGFloat = 14
private static let rotateHandleHitTargetSize: CGFloat = 22

private var contextResolverMetrics: CanvasContextResolverMetrics {
    CanvasContextResolverMetrics(
        selectionHandleHitTargetSize: Self.selectionHandleHitTargetSize,
        selectionOutlineHitTargetWidth: Self.selectionOutlineHitTargetWidth,
        cropHandleHitTargetSize: Self.cropHandleHitTargetSize,
        cropOutlineHitTargetWidth: Self.cropOutlineHitTargetWidth,
        rotateHandleHitTargetSize: Self.rotateHandleHitTargetSize
    )
}

switch pressContext.targetKind {
case let .groupSelectionHandle(handleRole):
    // ...
case .selectionTranslationArea:
    // Phase 1 先占位，避免新枚举进入未定义行为。
    editorSession.cancelPendingHistoryTransaction()
    pointerDragState = .idle
case .selectedItemBody:
    // ...
case .unselectedItemBody, .blank:
    // ...
// 其它既有分支（rotate / crop / selectionHandle）保持不变。
}

switch pressContext.targetKind {
case .rotateHandle:
    reason = "rotate item"
case .groupRotateHandle:
    reason = "rotate selection"
case .cropHandle, .cropTranslationArea:
    reason = "crop item"
case .selectionHandle:
    reason = "resize item"
case .groupSelectionHandle:
    reason = "resize selection"
case .selectionTranslationArea:
    return
case .selectedItemBody:
    reason = interactionState.selectionCount > 1 ? "move selection" : "move item"
case .unselectedItemBody, .blank:
    return
}
```

## 修改七：更新测试辅助的 metrics 构造

### 修改前

- `CanvasEditorSessionAlignmentOverlayTests` 中的测试辅助 `CanvasContextResolverMetrics` 构造没有 `selectionOutlineHitTargetWidth`。
- 一旦主代码的 metrics 结构体新增字段，测试构造若不更新，就会直接编译失败。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数名: makeAlignmentOverlayTestContextResolverMetrics()
// 功能说明: 修改前测试辅助只构造旧版 metrics，没有 selectionOutlineHitTargetWidth。
private func makeAlignmentOverlayTestContextResolverMetrics() -> CanvasContextResolverMetrics {
    CanvasContextResolverMetrics(
        selectionHandleHitTargetSize: 28,
        cropHandleHitTargetSize: 28,
        cropOutlineHitTargetWidth: 24,
        rotateHandleHitTargetSize: 28
    )
}
```

### 修改后

- 测试辅助补入 `selectionOutlineHitTargetWidth: 24`。
- 这一改动本身不新增测试行为，只是让测试代码与主代码契约保持同步。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数名: makeAlignmentOverlayTestContextResolverMetrics()
// 功能说明: 修改后测试辅助已经同步新版 metrics 契约，后续 phase 2 / 4 的命中测试可以直接复用这个入口。
private func makeAlignmentOverlayTestContextResolverMetrics() -> CanvasContextResolverMetrics {
    CanvasContextResolverMetrics(
        selectionHandleHitTargetSize: 28,
        selectionOutlineHitTargetWidth: 24,
        cropHandleHitTargetSize: 28,
        cropOutlineHitTargetWidth: 24,
        rotateHandleHitTargetSize: 28
    )
}
```

## 结果边界

- 本次修改完成后，工程已经具备了 `selectionTranslationArea` 的基础契约。
- 但当前 `resolveSelectionHitTarget(...)` 仍然保持原样，真实 selection translation hit test 还没有开始。
- 因此当前行为边界是：
  - 编译通过；
  - resolver / click resolver / controller 已能识别新枚举；
  - 但它们目前只做占位处理，不会让 UI 出现新的拖动行为。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// 函数名: resolveSelectionHitTarget(at:editOverlay:metrics:)
// 功能说明: 到本次 phase 1 结束时，selection hit test 仍然只处理 rotate 与 selection handles，还没有 selectionTranslationArea 的真实几何判定。
private func resolveSelectionHitTarget(
    at viewportPoint: CGPoint,
    editOverlay: CanvasEditRenderOverlay,
    metrics: CanvasContextResolverMetrics
) -> CanvasEditOverlayHitTarget? {
    guard case let .selection(payload) = editOverlay.payload else {
        return nil
    }

    let rotateHitRect = rect(
        centeredAt: payload.rotateAffordance.handle.screenCenter,
        size: metrics.rotateHandleHitTargetSize
    )
    if rotateHitRect.contains(viewportPoint) {
        return CanvasEditOverlayHitTarget(
            kind: payload.subject.isGroupSelection ? .groupRotateHandle : .rotateHandle,
            itemID: editOverlay.itemID,
            anchorRect: rotateHitRect
        )
    }

    for handle in editOverlay.handles {
        guard let role = handle.role.selectionHandleRole else {
            continue
        }
        let hitRect = rect(
            centeredAt: handle.screenCenter,
            size: metrics.selectionHandleHitTargetSize
        )
        if hitRect.contains(viewportPoint) {
            return CanvasEditOverlayHitTarget(
                kind: payload.subject.isGroupSelection
                    ? .groupSelectionHandle(role: role)
                    : .selectionHandle(role: role),
                itemID: editOverlay.itemID,
                anchorRect: hitRect
            )
        }
    }

    return nil
}
```

## 验证情况

- 已按当前改动范围完成源码记录整理，依据来自：
  - `git status --short`
  - 当前 working tree
  - 本次源码文件的 `git diff`
- 本次代码实现阶段的验证结果为：
  - `ReadLints` 无错误
  - `xcodebuild -destination "generic/platform=iOS" build` 通过
  - `xcodebuild -destination "generic/platform=macOS" build` 通过

## 当前工作区状态备注

- 当前源码改动正好对应本记录列出的 7 个源码/测试文件。
- 当前还额外保留了 `MyCanvas_Ver_0.xcodeproj/project.xcworkspace/xcuserdata/shaun.xcuserdatad/UserInterfaceState.xcuserstate` 的二进制状态变化。
- 该文件不是业务源码变更，但它确实存在于当前 `changes` 中，因此这里如实记录。
