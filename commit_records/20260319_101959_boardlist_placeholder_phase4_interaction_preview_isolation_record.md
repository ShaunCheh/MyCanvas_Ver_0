# 20260319_101959_boardlist_placeholder_phase4_interaction_preview_isolation_record

## 记录范围

- 记录目标：落实 `BoardList` 占位项方案的阶段 4，把 placeholder 的交互动作和 preview / thumbnail 请求链真正收口。
- 本阶段目的 1：点击 `New Board` 后立即创建，并且不让占位项继续停留在“已选中”的 board 语义里。
- 本阶段目的 2：让 controller 明确区分“可请求预览的真实 board entry”和“只负责创建的 placeholder entry”。
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- 本记录不包含：阶段 3 的 placeholder 视觉样式。
- 本记录不包含：阶段 5 的文案统一与回归整理。
- 本记录不包含：git commit。

## 修改一：点击 placeholder 后立即创建，并清理占位项选中态

### 修改前

- 阶段 2 已经把主动作统一收口到 `performPrimaryAction(for:)`，但点击 placeholder 之后，controller 仍会把 `selectedEntryID` 停留在 `.newBoard`。
- 这会导致 `New Board` 被点击后继续呈现为“当前选中项”，和真实 board 的选中语义混在一起。
- 对于占位项来说，这不是根因级语义，它只是创建入口，不应该长期占据 selection 状态。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.collectionView(_:didSelectItemsAt:)
// 功能说明: 修改前 macOS 单击 placeholder 虽然会触发创建，但不会把 selectedEntryID 从占位项上移开，导致创建入口继续停留在选中态。
func collectionView(
    _ collectionView: NSCollectionView,
    didSelectItemsAt indexPaths: Set<IndexPath>
) {
    guard
        isSyncingSelection == false,
        let indexPath = indexPaths.first,
        let entry = entry(at: indexPath)
    else {
        return
    }

    selectedEntryID = entry.id
    if entry.isPlaceholder {
        performPrimaryAction(for: entry)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.collectionView(_:didSelectItemAt:)
// 功能说明: 修改前 iOS 点击任意 entry 都直接走主动作，但 placeholder 创建完成后没有把选中态恢复到真实 board 或空状态。
func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard
        isSyncingSelection == false,
        let entry = entry(at: indexPath)
    else {
        return
    }

    selectedEntryID = entry.id
    performPrimaryAction(for: entry)
}
```

### 修改后

- 双端 controller 都新增 `clearPlaceholderSelectionAfterAction()`。
- 该方法不会让 placeholder 继续占据选中态，而是：
- 优先回到第一个真实 board；
- 如果当前没有真实 board，则回到无选中状态。
- 这样占位项的职责就稳定为“创建入口”，不会再伪装成一个长期被选中的 board。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.clearPlaceholderSelectionAfterAction() / collectionView(_:didSelectItemsAt:)
// 功能说明: 修改后 macOS 在 placeholder 触发创建后立即清理其选中态，避免 New Board 和真实 board 共用同一套持久选中语义。
private func clearPlaceholderSelectionAfterAction() {
    selectedEntryID = entries.first(where: { $0.isPlaceholder == false })?.id
    syncCollectionSelection()
}

func collectionView(
    _ collectionView: NSCollectionView,
    didSelectItemsAt indexPaths: Set<IndexPath>
) {
    guard
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

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.clearPlaceholderSelectionAfterAction() / collectionView(_:didSelectItemAt:)
// 功能说明: 修改后 iOS 在 placeholder 创建完成后同步恢复 selection，使占位项保留“点一下就创建”的入口语义，而不是持续高亮。
private func clearPlaceholderSelectionAfterAction() {
    selectedEntryID = entries.first(where: { $0.isPlaceholder == false })?.id
    syncCollectionSelection()
}

func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard
        isSyncingSelection == false,
        let entry = entry(at: indexPath)
    else {
        return
    }

    selectedEntryID = entry.id
    performPrimaryAction(for: entry)
    if entry.isPlaceholder {
        clearPlaceholderSelectionAfterAction()
    }
}
```

## 修改二：用 `canRequestPreview` 显式隔离 placeholder 与预览/缩略图链

### 修改前

- 阶段 2 和阶段 3 里，controller 是否进入 preview / thumbnail 链，仍然主要依赖 `entry.catalogItem` 是否存在。
- 这虽然在当前数据形态下“碰巧可用”，但本质上还是拿数据承载结果去反推 entry 语义。
- placeholder 的真正边界应该是“不可请求预览”，而不是“当前刚好没有 `catalogItem`”。
- 否则后续一旦 placeholder 扩展更多元数据，controller 仍有可能误入 `immediatePreview(...)` 或 `requestThumbnail(...)`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.collectionView(_:itemForRepresentedObjectAt:)
// 功能说明: 修改前 macOS 仍然通过 entry.catalogItem 是否存在来决定是否进入 preview / thumbnail 流水线，语义边界不够显式。
let previewContent: BoardPreviewContent
if let catalogItem = entry.catalogItem {
    let targetPixelSize = item.targetThumbnailPixelSize(for: displayMode)
    previewContent = previewProvider.immediatePreview(
        for: catalogItem,
        targetPixelSize: targetPixelSize
    )
} else {
    previewContent = .empty
}

item.configure(
    with: entry,
    previewContent: previewContent,
    displayMode: displayMode
)

if let catalogItem = entry.catalogItem,
   previewContent.isThumbnail == false {
    item.requestThumbnail(
        using: previewProvider,
        for: catalogItem,
        displayMode: displayMode
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.collectionView(_:cellForItemAt:)
// 功能说明: 修改前 iOS 也沿用了 catalogItem 判定链，placeholder 跳过预览只是依赖当前数据形态，而不是明确的 entry 能力边界。
let previewContent: BoardPreviewContent
if let catalogItem = entry.catalogItem {
    let targetPixelSize = cell.targetThumbnailPixelSize(for: displayMode)
    previewContent = previewProvider.immediatePreview(
        for: catalogItem,
        targetPixelSize: targetPixelSize
    )
} else {
    previewContent = .empty
}

cell.configure(
    with: entry,
    previewContent: previewContent,
    displayMode: displayMode
)

if let catalogItem = entry.catalogItem,
   previewContent.isThumbnail == false {
    cell.requestThumbnail(
        using: previewProvider,
        for: catalogItem,
        displayMode: displayMode
    )
}
```

### 修改后

- 双端 controller 都改为优先判断 `entry.canRequestPreview`。
- 这让 placeholder 的语义边界从“缺少数据”升级为“明确不可请求预览”。
- 之后即使 entry 模型继续扩展，preview / thumbnail 链也只会服务真实 board。
- iOS 现有的 `didEndDisplaying` 取消逻辑无需改动；对于 placeholder 来说仍然是安全的 no-op。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.collectionView(_:itemForRepresentedObjectAt:)
// 功能说明: 修改后 macOS 通过 entry.canRequestPreview 显式限制只有真实 board 才能进入同步预览和异步缩略图回填链。
let previewContent: BoardPreviewContent
if entry.canRequestPreview,
   let catalogItem = entry.catalogItem {
    let targetPixelSize = item.targetThumbnailPixelSize(for: displayMode)
    previewContent = previewProvider.immediatePreview(
        for: catalogItem,
        targetPixelSize: targetPixelSize
    )
} else {
    previewContent = .empty
}

item.configure(
    with: entry,
    previewContent: previewContent,
    displayMode: displayMode
)

if entry.canRequestPreview,
   let catalogItem = entry.catalogItem,
   previewContent.isThumbnail == false {
    item.requestThumbnail(
        using: previewProvider,
        for: catalogItem,
        displayMode: displayMode
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.collectionView(_:cellForItemAt:)
// 功能说明: 修改后 iOS 与 macOS 统一使用 canRequestPreview 作为 preview 能力边界，placeholder 不会再通过隐式条件误入缩略图请求链。
let previewContent: BoardPreviewContent
if entry.canRequestPreview,
   let catalogItem = entry.catalogItem {
    let targetPixelSize = cell.targetThumbnailPixelSize(for: displayMode)
    previewContent = previewProvider.immediatePreview(
        for: catalogItem,
        targetPixelSize: targetPixelSize
    )
} else {
    previewContent = .empty
}

cell.configure(
    with: entry,
    previewContent: previewContent,
    displayMode: displayMode
)

if entry.canRequestPreview,
   let catalogItem = entry.catalogItem,
   previewContent.isThumbnail == false {
    cell.requestThumbnail(
        using: previewProvider,
        for: catalogItem,
        displayMode: displayMode
    )
}
```

## 验证结果

- 已检查文件：
- `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
- `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- `ReadLints` 结果：无新增 lint 错误。
- 本次未执行项目级编译；因此这里的验证范围以代码审查和 lint 为主。
