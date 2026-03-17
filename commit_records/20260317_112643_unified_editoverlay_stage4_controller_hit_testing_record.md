# 20260317_112643_unified_editoverlay_stage4_controller_hit_testing_record

## 记录范围

- 记录内容：
  1. 在 `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift` 中把 selection handle / rotate handle 的命中统一收口到 `EditHandleHit + hitTestEditHandle(...)`。
  2. 在 `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift` 中同步迁移到统一 `editOverlay` handle 命中与分发。
  3. 让两个平台的 `pointerPressTarget(at:)` 与 pointer-up 阶段的 released handle 判定都改为优先消费 `lastRenderSnapshot.editOverlay`。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：
  - viewport 绘制逻辑修改
  - crop payload / inline session 的 typed 收口
  - 删除旧 overlay 字段
  - 原始 gif diff
  - git commit / push

## 修改一：在 controller 中新增统一 `EditHandleHit` 结果模型

### 修改前

- iOS / macOS controller 只有 `PointerPressTarget`，但没有一个中间结果模型把“命中了 resize handle 还是 rotate handle”先统一表达出来。
- 结果是 selection handle 命中和 rotate handle 命中只能各自独立返回不同类型，然后再分别转成 `PointerPressTarget`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: PointerPressTarget
// 功能说明: 修改前 controller 只有最终 press target，没有统一的 edit handle 命中结果模型，selection / rotate 命中只能分开处理。
private enum PointerPressTarget {
    case rotateHandle(itemID: CanvasImageItemID)
    case cropHandle(role: CanvasCropHandleRole, itemID: CanvasImageItemID)
    case handle(role: CanvasSelectionHandleRole, itemID: CanvasImageItemID)
    case selectedBody(itemID: CanvasImageItemID)
    case unselectedItem(itemID: CanvasImageItemID)
    case blank

    var itemID: CanvasImageItemID? {
        switch self {
        case let .rotateHandle(itemID),
             let .cropHandle(_, itemID),
             let .handle(_, itemID),
             let .selectedBody(itemID),
             let .unselectedItem(itemID):
            return itemID
        case .blank:
            return nil
        }
    }
}
```

### 修改后

- 两个平台都新增了 `EditHandleHit`。
- `EditHandleHit` 先统一表达两类 shared edit handle 命中结果：
  - `.rotate(itemID:)`
  - `.resize(role:itemID:)`
- `EditHandleHit.pressTarget` 再把统一命中结果映射到现有 `PointerPressTarget`，这样可以复用原有 drag state / history transaction / autosave 路径，而不用改动状态机主体。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: EditHandleHit
// 功能说明: 修改后 iOS controller 先把 selection / rotate handle 命中统一表达，再映射回现有 PointerPressTarget，减少入口分叉。
private enum EditHandleHit {
    case rotate(itemID: CanvasImageItemID)
    case resize(role: CanvasSelectionHandleRole, itemID: CanvasImageItemID)

    var itemID: CanvasImageItemID {
        switch self {
        case let .rotate(itemID), let .resize(_, itemID):
            return itemID
        }
    }

    var pressTarget: PointerPressTarget {
        switch self {
        case let .rotate(itemID):
            return .rotateHandle(itemID: itemID)
        case let .resize(role, itemID):
            return .handle(role: role, itemID: itemID)
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: EditHandleHit
// 功能说明: 修改后 macOS controller 与 iOS 对齐，统一以 EditHandleHit 承接 selection / rotate handle 的命中结果。
private enum EditHandleHit {
    case rotate(itemID: CanvasImageItemID)
    case resize(role: CanvasSelectionHandleRole, itemID: CanvasImageItemID)

    var itemID: CanvasImageItemID {
        switch self {
        case let .rotate(itemID), let .resize(_, itemID):
            return itemID
        }
    }

    var pressTarget: PointerPressTarget {
        switch self {
        case let .rotate(itemID):
            return .rotateHandle(itemID: itemID)
        case let .resize(role, itemID):
            return .handle(role: role, itemID: itemID)
        }
    }
}
```

## 修改二：把旧的 `hitTestSelectionHandle(...)` / `hitTestRotateHandle(...)` 收口到 `hitTestEditHandle(...)`

### 修改前

- `hitTestSelectionHandle(...)` 依赖 `lastRenderSnapshot.selectionOverlay`。
- `hitTestRotateHandle(...)` 依赖 `lastRenderSnapshot.rotateOverlay`。
- controller 层与阶段三 viewport 的统一 `editOverlay` 还没有对齐，selection / rotate 命中仍是两条旧链路。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: hitTestSelectionHandle(at:) / hitTestRotateHandle(at:)
// 功能说明: 修改前 iOS controller 仍分别从旧 selectionOverlay / rotateOverlay 命中 handle，controller 尚未切到统一 editOverlay。
private func hitTestSelectionHandle(at viewportLocation: CGPoint) -> (role: CanvasSelectionHandleRole, itemID: CanvasImageItemID)? {
    guard let selectionOverlay = lastRenderSnapshot.selectionOverlay else {
        return nil
    }

    return selectionOverlay.handles.first(where: { handle in
        Self.selectionHandleHitRect(centeredAt: handle.screenCenter).contains(viewportLocation)
    }).map { handle in
        (role: handle.role, itemID: selectionOverlay.itemID)
    }
}

private func hitTestRotateHandle(at viewportLocation: CGPoint) -> CanvasImageItemID? {
    guard let rotateOverlay = lastRenderSnapshot.rotateOverlay else {
        return nil
    }

    guard Self.rotateHandleHitRect(
        centeredAt: rotateOverlay.handle.screenCenter
    ).contains(viewportLocation) else {
        return nil
    }

    return rotateOverlay.itemID
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: hitTestSelectionHandle(at:) / hitTestRotateHandle(at:)
// 功能说明: 修改前 macOS controller 与 iOS 一样，selection / rotate handle 命中仍分散在两套旧 overlay 入口上。
private func hitTestSelectionHandle(at viewportLocation: CGPoint) -> (role: CanvasSelectionHandleRole, itemID: CanvasImageItemID)? {
    guard let selectionOverlay = lastRenderSnapshot.selectionOverlay else {
        return nil
    }

    return selectionOverlay.handles.first(where: { handle in
        Self.selectionHandleHitRect(centeredAt: handle.screenCenter).contains(viewportLocation)
    }).map { handle in
        (role: handle.role, itemID: selectionOverlay.itemID)
    }
}

private func hitTestRotateHandle(at viewportLocation: CGPoint) -> CanvasImageItemID? {
    guard let rotateOverlay = lastRenderSnapshot.rotateOverlay else {
        return nil
    }

    guard Self.rotateHandleHitRect(
        centeredAt: rotateOverlay.handle.screenCenter
    ).contains(viewportLocation) else {
        return nil
    }

    return rotateOverlay.itemID
}
```

### 修改后

- `hitTestEditHandle(...)` 统一从 `lastRenderSnapshot.editOverlay` 取几何。
- `crop` 仍然直接返回 `nil`，因为阶段四只收口 selection / rotate，crop handle 继续走 `hitTestCropHandle(...)`。
- 命中优先级保持“rotate handle 先于 resize handles”，这样在 rotate mode 下旋转手柄仍然是第一优先级入口。
- resize handle 命中仍然使用当前平台的轴对齐热区 `selectionHandleHitRect(centeredAt:)`，符合阶段四“视觉先统一，命中继续宽松”的边界。
- 新增 `selectionHandleRole(for:)`，把 `CanvasEditHandleRole` 映射回旧的 `CanvasSelectionHandleRole`，从而复用现有 resize 状态机和几何求解逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: hitTestEditHandle(at:) / selectionHandleRole(for:)
// 功能说明: 修改后 iOS controller 统一从 editOverlay 做 selection / rotate handle 命中，并把 shared role 映射回现有 resize 逻辑。
private func hitTestEditHandle(at viewportLocation: CGPoint) -> EditHandleHit? {
    guard let editOverlay = lastRenderSnapshot.editOverlay else {
        return nil
    }

    switch editOverlay.kind {
    case .crop:
        return nil
    case .selection, .rotate:
        if
            case let .rotate(payload) = editOverlay.payload,
            Self.rotateHandleHitRect(centeredAt: payload.handle.screenCenter)
                .contains(viewportLocation)
        {
            return .rotate(itemID: editOverlay.itemID)
        }

        guard
            let handle = editOverlay.cornerHandles.first(where: { handle in
                Self.selectionHandleHitRect(centeredAt: handle.screenCenter)
                    .contains(viewportLocation)
            }),
            let role = selectionHandleRole(for: handle.role)
        else {
            return nil
        }

        return .resize(role: role, itemID: editOverlay.itemID)
    }
}

private func selectionHandleRole(
    for editHandleRole: CanvasEditHandleRole
) -> CanvasSelectionHandleRole? {
    switch editHandleRole {
    case .topLeading:
        return .topLeading
    case .topTrailing:
        return .topTrailing
    case .bottomLeading:
        return .bottomLeading
    case .bottomTrailing:
        return .bottomTrailing
    case .rotate:
        return nil
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: hitTestEditHandle(at:) / selectionHandleRole(for:)
// 功能说明: 修改后 macOS controller 与 iOS 对齐，统一从 editOverlay 命中 rotate / resize handles，并保持旧 resize 角色语义不变。
private func hitTestEditHandle(at viewportLocation: CGPoint) -> EditHandleHit? {
    guard let editOverlay = lastRenderSnapshot.editOverlay else {
        return nil
    }

    switch editOverlay.kind {
    case .crop:
        return nil
    case .selection, .rotate:
        if
            case let .rotate(payload) = editOverlay.payload,
            Self.rotateHandleHitRect(centeredAt: payload.handle.screenCenter)
                .contains(viewportLocation)
        {
            return .rotate(itemID: editOverlay.itemID)
        }

        guard
            let handle = editOverlay.cornerHandles.first(where: { handle in
                Self.selectionHandleHitRect(centeredAt: handle.screenCenter)
                    .contains(viewportLocation)
            }),
            let role = selectionHandleRole(for: handle.role)
        else {
            return nil
        }

        return .resize(role: role, itemID: editOverlay.itemID)
    }
}

private func selectionHandleRole(
    for editHandleRole: CanvasEditHandleRole
) -> CanvasSelectionHandleRole? {
    switch editHandleRole {
    case .topLeading:
        return .topLeading
    case .topTrailing:
        return .topTrailing
    case .bottomLeading:
        return .bottomLeading
    case .bottomTrailing:
        return .bottomTrailing
    case .rotate:
        return nil
    }
}
```

## 修改三：让 `pointerPressTarget(...)` 与 pointer-up 的 released handle 判定统一走 `editOverlay`

### 修改前

- `pointerPressTarget(at:)` 在 rotate mode 时先调用 `hitTestRotateHandle(...)`，普通选中态时再调用 `hitTestSelectionHandle(...)`。
- pointer-up 阶段为了决定 `releasedItemID`，也只会检查 `hitTestSelectionHandle(at:)`，不会统一考虑 rotate handle。
- 这意味着 press / release 两个阶段都还没完全切到统一 edit overlay 语义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerUp(at:) / pointerPressTarget(at:)
// 功能说明: 修改前 iOS controller 在按下与释放时仍分别调用旧的 selection / rotate handle 命中入口。
let pressedItemID = pressTarget.itemID
let releasedHandleHit = hitTestSelectionHandle(at: location)
let releasedItemID = hitTestItemID(at: location) ?? releasedHandleHit?.itemID

private func pointerPressTarget(at viewportLocation: CGPoint) -> PointerPressTarget {
    if isInlineCropModeActive {
        if let cropHandleHit = hitTestCropHandle(at: viewportLocation) {
            return .cropHandle(role: cropHandleHit.role, itemID: cropHandleHit.itemID)
        }

        return .blank
    }

    if isInlineRotateModeActive {
        if let rotateHandleItemID = hitTestRotateHandle(at: viewportLocation) {
            return .rotateHandle(itemID: rotateHandleItemID)
        }

        return .blank
    }

    if let handleHit = hitTestSelectionHandle(at: viewportLocation) {
        return .handle(role: handleHit.role, itemID: handleHit.itemID)
    }

    // ... 再 fallback 到 body / blank ...
}
```

### 修改后

- pointer-up 阶段改成使用 `hitTestEditHandle(at:)` 来补充 `releasedItemID`。
- `pointerPressTarget(at:)` 现在在 crop mode 之后，先统一尝试 `hitTestEditHandle(at:)`。
- 若当前是 rotate mode 且没有命中 edit handle，则仍然返回 `.blank`，保持“rotate mode 只允许旋转手柄成为有效编辑入口”的原有交互边界。
- 这样 controller 的“按下命中 -> pressTarget -> 释放校验”已经与 `editOverlay` 对齐，但 scene 写入、resize 几何求解、rotate draft / crop draft 提交流程都没有被改动。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerUp(at:) / pointerPressTarget(at:)
// 功能说明: 修改后 iOS controller 在 press 与 release 两个阶段都统一从 editOverlay 取 handle 几何，selection / rotate 不再各走一套命中入口。
let pressedItemID = pressTarget.itemID
let releasedHandleHit = hitTestEditHandle(at: location)
let releasedItemID = hitTestItemID(at: location) ?? releasedHandleHit?.itemID

private func pointerPressTarget(at viewportLocation: CGPoint) -> PointerPressTarget {
    if isInlineCropModeActive {
        if let cropHandleHit = hitTestCropHandle(at: viewportLocation) {
            return .cropHandle(role: cropHandleHit.role, itemID: cropHandleHit.itemID)
        }

        return .blank
    }

    if let editHandleHit = hitTestEditHandle(at: viewportLocation) {
        return editHandleHit.pressTarget
    }

    if isInlineRotateModeActive {
        return .blank
    }

    // ... 再 fallback 到 body / blank ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handlePrimaryPointerUp(at:) / pointerPressTarget(at:)
// 功能说明: 修改后 macOS controller 与 iOS 对齐，按下与释放阶段都统一从 editOverlay 取 selection / rotate handle 命中结果。
let pressedItemID = pressTarget.itemID
let releasedHandleHit = hitTestEditHandle(at: location)
let releasedItemID = hitTestItemID(at: location) ?? releasedHandleHit?.itemID

private func pointerPressTarget(at viewportLocation: CGPoint) -> PointerPressTarget {
    if isInlineCropModeActive {
        if let cropHandleHit = hitTestCropHandle(at: viewportLocation) {
            return .cropHandle(role: cropHandleHit.role, itemID: cropHandleHit.itemID)
        }

        return .blank
    }

    if let editHandleHit = hitTestEditHandle(at: viewportLocation) {
        return editHandleHit.pressTarget
    }

    if isInlineRotateModeActive {
        return .blank
    }

    // ... 再 fallback 到 body / blank ...
}
```

## 影响与边界

- 阶段四后，iOS / macOS controller 已经把 selection / rotate handle 命中真源切换到 `lastRenderSnapshot.editOverlay`。
- `crop` 命中这一步仍然保留在 `hitTestCropHandle(...)`，没有并进 `hitTestEditHandle(...)`；这是刻意保留给阶段五处理的边界。
- 本阶段没有改动：
  - `PointerDragState`
  - `makePointerResizeState(...)`
  - `makePointerRotateState(...)`
  - `updateCropDraft(...)`
  - `updateRotationDraft(...)`
  - history transaction / autosave 的职责链路
- selection / rotate handle 的热区仍然是轴对齐 `CGRect`，没有升级成严格旋转 path 命中；这符合计划中“第一版命中继续维持宽松手感”的约束。

## 验证

```bash
# 功能说明: 阶段四构建验证命令，用于确认 controller 改成统一 editOverlay 命中入口后，双平台的 pointer / history / inline edit 编译链路仍然通过。
"/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild" \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ".build_editoverlay_stage4_ios" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

"/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild" \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  -derivedDataPath ".build_editoverlay_stage4_macos" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

- 验证结果：
  - `ReadLints` 对 `iOSViewController.swift`、`macOSViewController.swift` 无报错。
  - iOS Simulator Debug build 通过，日志末尾为 `** BUILD SUCCEEDED **`。
  - macOS Debug build 通过，日志末尾为 `** BUILD SUCCEEDED **`。
  - 写记录前执行 `git status --short`，只显示两个 controller 文件被修改，符合阶段四只动平台控制器层的预期。
