# 20260316_122948_phase_c_stage4_scene_resize_api_record

## 记录范围

- 记录内容：
  1. 为 `CanvasScene` 新增统一的几何级 resize 入口 `resizeItem(withID:to:)`。
  2. 将 iOS / macOS controller 的 resize 路径从“自己改 item 再 `scene.upsert(item)`”收敛为调用 scene 级 API。
  3. 保持既有的扩板、刷新画布和 autosave 链路不变，只下沉图元尺寸更新职责。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：原始 gif diff、阶段五验证、额外的持久化 schema 变更。

## 修改一：为 CanvasScene 新增统一的 resize 入口

### 修改前

- `CanvasScene` 已经有 `moveItem(withID:by:)`，但没有对应的“按目标 frame 调整图元”的 API。
- scene 内部唯一的更新入口 `updateItem(withID:_:)` 只接受 `Void` 闭包，无法顺手把更新后的 item 返回给上层调用方。
- 这导致 controller 在 resize 时只能先拿到 item，自行改 `center + size`，再回写到 scene。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数名: moveItem(withID:by:) / updateItem(withID:_:)
// 功能说明: 修改前 scene 只有 moveItem，没有统一的 resizeItem；updateItem 也不能把更新结果返回给上层。
func moveItem(withID id: CanvasImageItemID, by deltaInWorld: CGPoint) {
    guard deltaInWorld != .zero else {
        return
    }

    updateItem(withID: id) { item in
        item.center.x += deltaInWorld.x
        item.center.y += deltaInWorld.y
    }
}

private func updateItem(
    withID id: CanvasImageItemID,
    _ mutate: (inout CanvasImageItem) -> Void
) {
    guard let index = items.firstIndex(where: { $0.id == id }) else {
        return
    }

    mutate(&items[index])
}
```

### 修改后

- 新增 `resizeItem(withID:to:)`，把“把某个图元改到目标 `worldFrame`”的职责下沉到 scene。
- 该方法会先标准化 `worldFrame`，并拒绝宽高无效的输入，避免 controller 各自做重复防御。
- `updateItem(withID:_:)` 改成泛型返回值形式，scene 可以在更新完成后把最新 `CanvasImageItem` 返回给上层，用于后续扩板等流程。
- 这样 scene 对“如何从目标 frame 回写到 `center + size`”拥有唯一实现，controller 只保留交互编排职责。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数名: resizeItem(withID:to:) / updateItem(withID:_:)
// 功能说明: 修改后 scene 提供统一的 resize 入口，并允许把更新后的 item 返回给调用方复用。
@discardableResult
func resizeItem(withID id: CanvasImageItemID, to worldFrame: CGRect) -> CanvasImageItem? {
    let standardizedFrame = worldFrame.standardized
    guard standardizedFrame.width > 0, standardizedFrame.height > 0 else {
        return nil
    }

    return updateItem(withID: id) { item in
        item.center = CGPoint(
            x: standardizedFrame.midX,
            y: standardizedFrame.midY
        )
        item.size = standardizedFrame.size
        return item
    }
}

@discardableResult
private func updateItem<T>(
    withID id: CanvasImageItemID,
    _ mutate: (inout CanvasImageItem) -> T
) -> T? {
    guard let index = items.firstIndex(where: { $0.id == id }) else {
        return nil
    }

    return mutate(&items[index])
}
```

## 修改二：让 iOS controller 改为调用 scene 级 resize API

### 修改前

- `iOSViewController.resizeSelectedItem(...)` 在拿到新的 `resizedWorldFrame` 后，会自己取出 item，直接改写 `center` 和 `size`，然后再 `scene.upsert(item)`。
- 这样 controller 持有了本应属于 scene 的几何写入逻辑，scene 只成了一个“数组回写容器”。
- 如果后续别的交互路径也要 resize，同样会倾向于复制这段“改 item 再 upsert”的模式。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: resizeSelectedItem(using:to:)
// 功能说明: 修改前 iOS controller 自己改写 item.center / item.size，再通过 scene.upsert(item) 回写。
private func resizeSelectedItem(
    using resizeState: PointerResizeState,
    to viewportLocation: CGPoint
) {
    guard
        let resizedWorldFrame = makeResizedWorldFrame(
            using: resizeState,
            draggedViewportLocation: viewportLocation
        ),
        var item = scene.item(withID: resizeState.itemID)
    else {
        return
    }

    guard item.worldFrame.standardized != resizedWorldFrame else {
        return
    }

    item.center = CGPoint(x: resizedWorldFrame.midX, y: resizedWorldFrame.midY)
    item.size = resizedWorldFrame.size
    scene.upsert(item)
    expandBoardIfNeeded(toInclude: resizedWorldFrame)
    requestCanvasRefresh(reason: "resize selected item to \(describe(rect: resizedWorldFrame))")
    scheduleAutosave(reason: "resize item")
}
```

### 修改后

- `iOSViewController.resizeSelectedItem(...)` 现在只负责：
  - 计算新的 `resizedWorldFrame`
  - 判断 frame 是否真的变化
  - 调用 `scene.resizeItem(withID:to:)`
  - 继续走扩板、刷新和 autosave
- scene 成为唯一的图元尺寸写入入口，controller 不再直接篡改 `center + size`。
- 同时，controller 继续复用返回的 `resizedItem.worldFrame` 来触发 `expandBoardIfNeeded(...)`，避免额外重复查找。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: resizeSelectedItem(using:to:)
// 功能说明: 修改后 iOS controller 只负责编排 resize 流程，真正的尺寸写入改由 scene.resizeItem(withID:to:) 完成。
private func resizeSelectedItem(
    using resizeState: PointerResizeState,
    to viewportLocation: CGPoint
) {
    guard
        let resizedWorldFrame = makeResizedWorldFrame(
            using: resizeState,
            draggedViewportLocation: viewportLocation
        ),
        let currentItem = scene.item(withID: resizeState.itemID)
    else {
        return
    }

    guard currentItem.worldFrame.standardized != resizedWorldFrame else {
        return
    }

    guard let resizedItem = scene.resizeItem(withID: resizeState.itemID, to: resizedWorldFrame) else {
        return
    }

    expandBoardIfNeeded(toInclude: resizedItem.worldFrame)
    requestCanvasRefresh(reason: "resize selected item to \(describe(rect: resizedWorldFrame))")
    scheduleAutosave(reason: "resize item")
}
```

## 修改三：让 macOS controller 同步走 scene 级 resize 入口

### 修改前

- `macOSViewController.resizeSelectedItem(...)` 和 iOS 一样，也是在 controller 里直接改 `item.center`、`item.size`，然后 `scene.upsert(item)`。
- 这让两端 controller 都持有一份重复的几何写回逻辑，违背了阶段四“把 resize 变更入口补齐到 scene 层”的目标。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: resizeSelectedItem(using:to:)
// 功能说明: 修改前 macOS controller 也直接改 item 的 center / size，再用 scene.upsert(item) 回写。
private func resizeSelectedItem(
    using resizeState: PointerResizeState,
    to viewportLocation: CGPoint
) {
    guard
        let resizedWorldFrame = makeResizedWorldFrame(
            using: resizeState,
            draggedViewportLocation: viewportLocation
        ),
        var item = scene.item(withID: resizeState.itemID)
    else {
        return
    }

    guard item.worldFrame.standardized != resizedWorldFrame else {
        return
    }

    item.center = CGPoint(x: resizedWorldFrame.midX, y: resizedWorldFrame.midY)
    item.size = resizedWorldFrame.size
    scene.upsert(item)
    expandBoardIfNeeded(toInclude: resizedWorldFrame)
    refreshCanvas()
    scheduleAutosave(reason: "resize item")
}
```

### 修改后

- `macOSViewController.resizeSelectedItem(...)` 同样改成先判断 frame 是否变化，再调用 `scene.resizeItem(withID:to:)`。
- 之后仍然保持 macOS 自己原有的 `refreshCanvas()` 和 `scheduleAutosave(reason: "resize item")` 路径。
- 这样 iOS / macOS 两端关于“resize 如何写回 scene”的实现方式终于统一到了 scene 层。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: resizeSelectedItem(using:to:)
// 功能说明: 修改后 macOS controller 也只保留 resize 编排，实际图元尺寸回写统一走 scene.resizeItem(withID:to:)。
private func resizeSelectedItem(
    using resizeState: PointerResizeState,
    to viewportLocation: CGPoint
) {
    guard
        let resizedWorldFrame = makeResizedWorldFrame(
            using: resizeState,
            draggedViewportLocation: viewportLocation
        ),
        let currentItem = scene.item(withID: resizeState.itemID)
    else {
        return
    }

    guard currentItem.worldFrame.standardized != resizedWorldFrame else {
        return
    }

    guard let resizedItem = scene.resizeItem(withID: resizeState.itemID, to: resizedWorldFrame) else {
        return
    }

    expandBoardIfNeeded(toInclude: resizedItem.worldFrame)
    refreshCanvas()
    scheduleAutosave(reason: "resize item")
}
```

## 结果

- 现在 `CanvasScene` 已经具备统一的 resize 变更入口，controller 不再直接改图元 `center + size` 再 `upsert`。
- iOS / macOS 两端的 resize 交互路径都统一成了：计算目标 frame -> 调用 `scene.resizeItem(...)` -> 扩板 -> 刷新 -> autosave。
- 这一步没有改动持久化模型，也没有改变阶段三 already 接通的 handle 命中与等比缩放几何，只是把图元尺寸写回职责从 controller 收敛到了 scene 层。
