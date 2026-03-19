# 20260319_114527_boardlist_display_mode_constraint_conflict_fix_record

## 记录范围

- 记录目标：修复 `BoardList` 在 `Grid` 切换到 `List` 时出现的约束冲突日志。
- 本次目的 1：消除 `macOSBoardCollectionItem` 在展示模式切换期间提前触发 Auto Layout 求解的问题。
- 本次目的 2：同步修复 iOS 对称实现，避免后续在同类切换路径上出现相同风险。
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift`
- 本记录不包含：placeholder 的样式设计调整。
- 本记录不包含：git commit。

## 修改一：移除 macOS 缩略图尺寸计算中的强制布局求解

### 修改前

- `macOSBoardCollectionItem.targetThumbnailPixelSize(...)` 一进入就调用 `view.layoutSubtreeIfNeeded()`。
- 当 collection 在 `Grid -> List` 切换过程中提前询问 thumbnail 尺寸时，item 还可能保留上一种展示模式的约束。
- 这会把旧的 `gridConstraints` 提前拿去求解，和 `List` 模式的 `96` 高度一起触发冲突。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名/类型名: macOSBoardCollectionItem.targetThumbnailPixelSize(for:)
// 功能说明: 修改前 macOS 在计算 thumbnail 像素尺寸前强制执行一次布局，导致展示模式切换中旧约束被提前求解。
func targetThumbnailPixelSize(
    for displayMode: BoardListDisplayMode
) -> CGSize {
    view.layoutSubtreeIfNeeded()

    let previewSize = resolvedPreviewViewSize(for: displayMode)
    let contentsScale = view.window?.backingScaleFactor
        ?? NSScreen.main?.backingScaleFactor
        ?? 2
    return CGSize(
        width: previewSize.width * contentsScale,
        height: previewSize.height * contentsScale
    )
}
```

### 修改后

- `targetThumbnailPixelSize(...)` 改成纯计算方法，不再触发布局求解。
- 方法只依赖：
- `displayMode`
- `resolvedPreviewViewSize(for:)`
- 当前屏幕 scale
- 这样 collection 在切换展示模式时即使提前来询问 thumbnail 尺寸，也不会把上一个模式的约束链硬拉起来求解。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名/类型名: macOSBoardCollectionItem.targetThumbnailPixelSize(for:)
// 功能说明: 修改后 macOS 的 thumbnail 像素尺寸计算不再强制布局，避免 Grid/List 切换时旧展示模式约束被提前求解。
func targetThumbnailPixelSize(
    for displayMode: BoardListDisplayMode
) -> CGSize {
    // Do not force layout here: collection view may ask for thumbnail size
    // before this item finishes switching away from the previous mode.
    let previewSize = resolvedPreviewViewSize(for: displayMode)
    let contentsScale = view.window?.backingScaleFactor
        ?? NSScreen.main?.backingScaleFactor
        ?? 2
    return CGSize(
        width: previewSize.width * contentsScale,
        height: previewSize.height * contentsScale
    )
}
```

## 修改二：同步修复 iOS 对称实现，统一 thumbnail 尺寸计算语义

### 修改前

- iOS 的 `iOSBoardCollectionViewCell.targetThumbnailPixelSize(...)` 也有同样的强制布局调用：`contentView.layoutIfNeeded()`。
- 虽然这次报错出现在 macOS，但双端实现语义相同，继续保留会留下同类切换风险。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名/类型名: iOSBoardCollectionViewCell.targetThumbnailPixelSize(for:)
// 功能说明: 修改前 iOS 也会在尺寸计算前强制布局，和 macOS 共享同一类模式切换时序风险。
func targetThumbnailPixelSize(
    for displayMode: BoardListDisplayMode
) -> CGSize {
    contentView.layoutIfNeeded()

    let previewSize = resolvedPreviewViewSize(for: displayMode)
    let contentsScale = window?.screen.scale ?? UIScreen.main.scale
    return CGSize(
        width: previewSize.width * contentsScale,
        height: previewSize.height * contentsScale
    )
}
```

### 修改后

- iOS 也改成纯计算，不再在这里调用 Auto Layout。
- 双端现在统一为“显示模式切换时，thumbnail 尺寸计算只做数学换算，不参与布局求解”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名/类型名: iOSBoardCollectionViewCell.targetThumbnailPixelSize(for:)
// 功能说明: 修改后 iOS 与 macOS 对齐，thumbnail 尺寸计算保持纯计算语义，避免展示模式切换中触发布局冲突。
func targetThumbnailPixelSize(
    for displayMode: BoardListDisplayMode
) -> CGSize {
    // Keep this purely calculative so display-mode transitions do not force
    // Auto Layout to solve against the previous presentation style.
    let previewSize = resolvedPreviewViewSize(for: displayMode)
    let contentsScale = window?.screen.scale ?? UIScreen.main.scale
    return CGSize(
        width: previewSize.width * contentsScale,
        height: previewSize.height * contentsScale
    )
}
```

## 验证结果

- 已检查文件：
- `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift`
- `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift`
- 已对照本次 `git diff`，确认实际改动只包括移除强制布局调用并补充根因注释。
- 本次相关文件的 `ReadLints` 检查结果：无新增错误。
- 本次未执行项目级编译；因此这里的验证范围以 diff 对照和 lint 为主。
