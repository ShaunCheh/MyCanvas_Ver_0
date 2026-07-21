# 20260721_095358_CST_boardlist_trace_logs_temporary_mute_record

## 记录范围

- 记录内容：
  - 暂时屏蔽 BoardList / Canvas 调试日志噪音，避免控制台被 `RenameTrace`、`ThumbnailTrace`、`SelectionTrace`、`ViewportLifecycle` 刷屏。
  - 做法是在各日志入口用注释 + `#if false` 包住原有 `print(...)`（及部分采样逻辑），不删除调用点，便于后续恢复。
  - 业务行为不变：只停输出，不改缩略图渲染、重命名、选中同步等逻辑。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift`
- 本记录不包含：
  - 任何 git commit / push。
  - 原始 `git diff` 全文粘贴。
  - iOS 侧 `RenameTrace`（本次未改）。
  - `macOSCanvasViewportView.apply(_:)` 里的 `ViewportApply` 日志（本次未改）。

## 命名与当前 changes 证据

```sh
# 文件路径: 无（终端命令）
# 函数名: date "+%Y%m%d_%H%M%S_%Z"
# 功能说明: 使用系统 date 命令生成本记录文件的时间戳前缀。
20260721_095358_CST
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short
# 功能说明: 确认本次仅上述 7 个 Swift 文件处于已修改状态。
 M MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift
 M MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift
 M MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
 M MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
 M MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
 M MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
 M MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --stat -- . ':(exclude)*.md'
# 功能说明: 汇总 tracked changes 体量；全部为插入（+69），无删除，符合“用 #if false 包住原 print”的改法。
 .../Storage/BoardPersistedThumbnailStore.swift     |  3 +++
 .../BoardList/BoardGeometryPreviewBuilder.swift    |  6 ++++++
 .../Shared/BoardList/BoardPreviewProvider.swift    |  9 ++++++++
 .../Shared/BoardList/BoardThumbnailRenderer.swift  | 24 ++++++++++++++++++++++
 .../macOS/BoardList/macOSBoardCollectionItem.swift | 12 +++++++++++
 .../BoardList/macOSBoardListViewController.swift   |  9 ++++++++
 .../macOS/Canvas/macOSCanvasViewportView.swift     |  6 ++++++
 7 files changed, 69 insertions(+)
```

## 统一改法说明

- 修改前：日志入口直接执行 `print(...)`（部分入口还会先做签名采样再打印）。
- 修改后：在入口顶部增加 `// Temporarily muted: ...` 注释，并用 `#if false` / `#endif` 包住原实现体；编译期剔除打印，调用点保持不动。
- 恢复方式：去掉对应入口的 `#if false` / `#endif`（及临时注释）即可。

---

## 修改一：macOS BoardList Controller 日志入口

### 修改前

- `logSelectionTrace` / `logRenameTrace` / `logThumbnailTrace` 会直接向控制台输出：
  - `[BoardList][macOS][SelectionTrace]`
  - `[BoardList][macOS][RenameTrace]`
  - `[BoardList][macOS][ThumbnailTrace][Controller]`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名: macOSBoardListViewController.logSelectionTrace(_:extra:)
// 功能说明: 修改前直接打印 SelectionTrace，重载列表、同步选中时会持续刷屏。
private func logSelectionTrace(_ phase: String, extra: String = "") {
    let extraSuffix = extra.isEmpty ? "" : " \(extra)"
    print(
        "[BoardList][macOS][SelectionTrace] " +
            "t=\(selectionTraceTimestamp()) " +
            "phase=\(phase) " +
            "displayMode=\(displayMode.title) " +
            "selectedEntryID=\(describeSelectionTraceEntryID(selectedEntryID)) " +
            "collectionSelection=\(describeSelectionTraceIndexPaths(collectionView.selectionIndexPaths))" +
            extraSuffix
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名: macOSBoardListViewController.logRenameTrace(_:extra:)
// 功能说明: 修改前直接打印 RenameTrace，reload / reveal / focus 标题编辑链路会大量输出。
private func logRenameTrace(_ phase: String, extra: String = "") {
    let extraSuffix = extra.isEmpty ? "" : " \(extra)"
    print(
        "[BoardList][macOS][RenameTrace] " +
            "t=\(selectionTraceTimestamp()) " +
            "phase=\(phase) " +
            "editingBoardID=\(editingBoardID?.uuidString ?? "nil") " +
            "pendingRevealBoardID=\(pendingRevealBoardID?.uuidString ?? "nil") " +
            "selectedEntryID=\(describeSelectionTraceEntryID(selectedEntryID)) " +
            "actionPanelBoardID=\(actionPanelState?.boardID.uuidString ?? "nil")" +
            extraSuffix
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名: macOSBoardListViewController.logThumbnailTrace(phase:boardID:revisionToken:targetPixelSize:previewContent:indexPath:reason:)
// 功能说明: 修改前直接打印 ThumbnailTrace[Controller]，configureItem 同步/异步预览决策会持续输出。
private func logThumbnailTrace(
    phase: String,
    boardID: UUID,
    revisionToken: String,
    targetPixelSize: CGSize,
    previewContent: BoardPreviewContent,
    indexPath: IndexPath,
    reason: String?
) {
    var message =
        "[BoardList][macOS][ThumbnailTrace][Controller] " +
        "t=\(selectionTraceTimestamp()) " +
        "phase=\(phase) " +
        // ... boardID / revision / displayMode / indexPath / previewContent ...
        "previewContent=\(describeBoardListPreviewContent(previewContent))"
    if let reason {
        message += " reason=\(reason)"
    }
    print(message)
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名: macOSBoardListViewController.logSelectionTrace(_:extra:)
// 功能说明: 修改后用 #if false 暂时屏蔽 SelectionTrace 输出；调用点与字符串拼装逻辑保留。
private func logSelectionTrace(_ phase: String, extra: String = "") {
    // Temporarily muted: BoardList SelectionTrace noise.
    #if false
    let extraSuffix = extra.isEmpty ? "" : " \(extra)"
    print(
        "[BoardList][macOS][SelectionTrace] " +
            "t=\(selectionTraceTimestamp()) " +
            "phase=\(phase) " +
            "displayMode=\(displayMode.title) " +
            "selectedEntryID=\(describeSelectionTraceEntryID(selectedEntryID)) " +
            "collectionSelection=\(describeSelectionTraceIndexPaths(collectionView.selectionIndexPaths))" +
            extraSuffix
    )
    #endif
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名: macOSBoardListViewController.logRenameTrace(_:extra:)
// 功能说明: 修改后暂时屏蔽 RenameTrace；恢复时去掉 #if false 即可。
private func logRenameTrace(_ phase: String, extra: String = "") {
    // Temporarily muted: BoardList RenameTrace noise.
    #if false
    let extraSuffix = extra.isEmpty ? "" : " \(extra)"
    print(
        "[BoardList][macOS][RenameTrace] " +
            // ... 原字段不变 ...
            extraSuffix
    )
    #endif
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名: macOSBoardListViewController.logThumbnailTrace(phase:boardID:revisionToken:targetPixelSize:previewContent:indexPath:reason:)
// 功能说明: 修改后暂时屏蔽 ThumbnailTrace[Controller]；immediate/async 请求决策日志不再落盘。
private func logThumbnailTrace(
    phase: String,
    boardID: UUID,
    revisionToken: String,
    targetPixelSize: CGSize,
    previewContent: BoardPreviewContent,
    indexPath: IndexPath,
    reason: String?
) {
    // Temporarily muted: BoardList ThumbnailTrace noise.
    #if false
    var message =
        "[BoardList][macOS][ThumbnailTrace][Controller] " +
        // ... 原字段不变 ...
        "previewContent=\(describeBoardListPreviewContent(previewContent))"
    if let reason {
        message += " reason=\(reason)"
    }
    print(message)
    #endif
}
```

---

## 修改二：macOS BoardList Item 日志入口

### 修改前

- Item 侧 `logSelectionTrace` / `logThumbnailTrace` / `logRenameTrace` 直接 `print`。
- 缩略图回调里 `self == nil` 时还有一处内联 `ThumbnailTrace[Item]` 打印。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名: macOSBoardCollectionItem.logRenameTrace(_:extra:)
// 功能说明: 修改前 configure / applyTitleEditingAppearance 等 phase 会持续输出 RenameTrace[Item]。
private func logRenameTrace(_ phase: String, extra: String = "") {
    let extraSuffix = extra.isEmpty ? "" : " \(extra)"
    let isFirstResponder = view.window?.firstResponder === titleTextField
    print(
        "[BoardList][macOS][RenameTrace][Item] " +
            "t=\(boardListSelectionTraceTimestamp()) " +
            "phase=\(phase) " +
            "boardID=\(representedBoardID?.uuidString ?? "nil") " +
            "representedTitle=\"\(representedTitle ?? "")\" " +
            "textFieldText=\"\(titleTextField.stringValue)\" " +
            "editing=\(isTitleEditingActive) " +
            "textFieldHidden=\(titleTextField.isHidden) " +
            "isFirstResponder=\(isFirstResponder) " +
            "isAwaitingInitialFocusStabilization=\(isAwaitingInitialFocusStabilization)" +
            extraSuffix
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名: macOSBoardCollectionItem 缩略图回调闭包（requestThumbnail completion）
// 功能说明: 修改前 item 已释放时仍会 print ThumbnailTrace[Item] requestThumbnailCallbackDropped。
guard let self else {
    print(
        "[BoardList][macOS][ThumbnailTrace][Item] " +
            "t=\(boardListSelectionTraceTimestamp()) " +
            "phase=requestThumbnailCallbackDropped " +
            "requestedBoardID=\(item.boardID.uuidString) " +
            "requestedRevision=\(item.revisionToken) " +
            "reason=item-deallocated"
    )
    return
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名: macOSBoardCollectionItem.logSelectionTrace(_:extra:) / logThumbnailTrace(_:extra:) / logRenameTrace(_:extra:)
// 功能说明: 三个入口统一用 #if false 屏蔽；Item 侧 Selection/Thumbnail/Rename Trace 不再输出。
private func logSelectionTrace(_ phase: String, extra: String = "") {
    // Temporarily muted: BoardList SelectionTrace noise.
    #if false
    // ... 原 print 体保留 ...
    #endif
}

private func logThumbnailTrace(_ phase: String, extra: String = "") {
    // Temporarily muted: BoardList ThumbnailTrace noise.
    #if false
    // ... 原 print 体保留 ...
    #endif
}

private func logRenameTrace(_ phase: String, extra: String = "") {
    // Temporarily muted: BoardList RenameTrace noise.
    #if false
    // ... 原 print 体保留 ...
    #endif
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名: macOSBoardCollectionItem 缩略图回调闭包（requestThumbnail completion）
// 功能说明: 修改后内联 print 也被 #if false 包住；item 释放时不再打 ThumbnailTrace。
guard let self else {
    // Temporarily muted: BoardList ThumbnailTrace noise.
    #if false
    print(
        "[BoardList][macOS][ThumbnailTrace][Item] " +
            "t=\(boardListSelectionTraceTimestamp()) " +
            "phase=requestThumbnailCallbackDropped " +
            "requestedBoardID=\(item.boardID.uuidString) " +
            "requestedRevision=\(item.revisionToken) " +
            "reason=item-deallocated"
    )
    #endif
    return
}
```

---

## 修改三：共享 ThumbnailTrace（渲染 / Provider / Seed / Persisted）

### 修改前

- `BoardThumbnailRenderer` 中 `logRenderSurface` / `logPosterBackedDraw` / `logTextDraw` / `logRenderedImage` 等在 fresh render 与 persisted replay 时逐 item 打印，是刷屏主力。
- `BoardPreviewProvider.logBoardPreviewProviderDecision` 打印 `[Provider] phase=... source=...`。
- `BoardGeometryPreviewBuilder` 的 Seed / SeedNode、`BoardPersistedThumbnailStore.logPersistedThumbnailImage` 同样直接 `print`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: logPosterBackedDraw(...)
// 功能说明: 修改前每个 image/handDrawing 节点绘制时都会输出 PosterDraw（含 sampleGrid / CTM）。
private func logPosterBackedDraw(
    traceContext: BoardThumbnailTraceContext,
    kind: CanvasMiniMapNodeKind,
    itemID: UUID,
    // ...
    context: CGContext
) {
    print(
        "[BoardList][ThumbnailTrace][PosterDraw] " +
            "mode=\(traceContext.mode) " +
            "boardID=\(traceContext.boardID?.uuidString ?? "nil") " +
            "kind=\(describeBoardThumbnailNodeKind(kind)) " +
            "itemID=\(itemID.uuidString) " +
            // ... worldCenter / previewVisibleRect / imageSignature / contextCTM ...
            "contextCTM=\(describeBoardThumbnailTransform(context.ctm))"
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名: logBoardPreviewProviderDecision(phase:boardID:revisionToken:targetPixelSize:source:reason:)
// 功能说明: 修改前 immediatePreview / loadBestAvailableThumbnail / requestThumbnail 决策一律打印 Provider 行。
private func logBoardPreviewProviderDecision(
    phase: String,
    boardID: UUID,
    revisionToken: String,
    targetPixelSize: CGSize,
    source: String,
    reason: String? = nil
) {
    var message =
        "[BoardList][ThumbnailTrace][Provider] " +
        "phase=\(phase) " +
        "boardID=\(boardID.uuidString) " +
        "revision=\(revisionToken) " +
        "targetPixelSize=\(describeBoardPreviewProviderSize(targetPixelSize)) " +
        "source=\(source)"
    if let reason {
        message += " reason=\(reason)"
    }
    print(message)
}
```

### 修改后

- 下列入口均增加 `// Temporarily muted: BoardList ThumbnailTrace noise.` + `#if false`：
  - `BoardThumbnailRenderer.swift`
    - `logBoardThumbnailTraceImageRegions(...)`
    - `logRenderSurface(...)`
    - `logPersistedReplayDraw(...)`
    - `logPosterBackedDraw(...)`
    - `logPosterBackedRenderedRegion(...)`
    - `logNodeRegionSamples(...)`
    - `logTextDraw(...)`
    - `logRenderedImage(...)`
  - `BoardPreviewProvider.swift`
    - `logBoardPreviewProviderCacheHitMetadata(...)`
    - `logBoardPreviewProviderSourceImagesIfNeeded(...)`（verbose 路径整体包住）
    - `logBoardPreviewProviderDecision(...)`
  - `BoardGeometryPreviewBuilder.swift`
    - `logBoardPreviewSeedSummary(...)`
    - `logBoardPreviewSeedNode(...)`
  - `BoardPersistedThumbnailStore.swift`
    - `BoardPersistedThumbnailStore.logPersistedThumbnailImage(...)`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: logPosterBackedDraw(...)
// 功能说明: 修改后整段 print 被 #if false 剔除；同时避免无用的签名字符串拼装参与编译产物运行路径。
private func logPosterBackedDraw(
    traceContext: BoardThumbnailTraceContext,
    kind: CanvasMiniMapNodeKind,
    itemID: UUID,
    // ...
    context: CGContext
) {
    // Temporarily muted: BoardList ThumbnailTrace noise.
    #if false
    print(
        "[BoardList][ThumbnailTrace][PosterDraw] " +
            // ... 原字段不变 ...
            "contextCTM=\(describeBoardThumbnailTransform(context.ctm))"
    )
    #endif
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名: logBoardPreviewProviderDecision(phase:boardID:revisionToken:targetPixelSize:source:reason:)
// 功能说明: 修改后 Provider 决策日志暂时不输出；persisted-hit / fresh-render / geometry-fallback 等 source 不再刷屏。
private func logBoardPreviewProviderDecision(
    phase: String,
    boardID: UUID,
    revisionToken: String,
    targetPixelSize: CGSize,
    source: String,
    reason: String? = nil
) {
    // Temporarily muted: BoardList ThumbnailTrace noise.
    #if false
    var message =
        "[BoardList][ThumbnailTrace][Provider] " +
        // ... 原字段不变 ...
        "source=\(source)"
    if let reason {
        message += " reason=\(reason)"
    }
    print(message)
    #endif
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名: logBoardPreviewProviderSourceImagesIfNeeded(...)
// 功能说明: 修改后在 tracePolicy == .verbose 之后立刻用 #if false 包住 Guard/SourceImage 全路径；当前默认 metadataOnly 本就不会走到，但恢复 verbose 时仍保持可开关。
guard tracePolicy == .verbose else {
    return
}

// Temporarily muted: BoardList ThumbnailTrace noise.
#if false
print("[BoardList][ThumbnailTrace][Guard] ...")
// ... SourceImage 采样循环与失败日志 ...
#endif
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift
// 函数名: BoardPersistedThumbnailStore.logPersistedThumbnailImage(phase:boardID:image:maxPixelSize:)
// 功能说明: 修改后 PersistedImage load-output 签名日志暂时不输出。
private static func logPersistedThumbnailImage(
    phase: String,
    boardID: UUID?,
    image: CGImage,
    maxPixelSize: Int? = nil
) {
    // Temporarily muted: BoardList ThumbnailTrace noise.
    #if false
    var message =
        "[BoardList][ThumbnailTrace][PersistedImage] " +
        // ... 原字段不变 ...
        "signature=\(BoardThumbnailImageSignature.describe(image))"
    if let maxPixelSize {
        message += " maxPixelSize=\(maxPixelSize)"
    }
    print(message)
    #endif
}
```

---

## 修改四：Canvas ViewportLifecycle 日志

### 修改前

- `layout()` / `viewDidMoveToWindow()` 每次布局与挂窗都会打印 `[Canvas macOS][ViewportLifecycle]`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: macOSCanvasViewportView.layout()
// 功能说明: 修改前每次 layout 都 print ViewportLifecycle，窗口缩放/列表切换时噪音明显。
override func layout() {
    super.layout()
    print(
        "[Canvas macOS][ViewportLifecycle] " +
        "action=layout " +
        "viewBounds=\(macOSViewportDescribe(bounds)) " +
        "viewFrame=\(macOSViewportDescribe(frame)) " +
        "windowFrame=\(window.map { macOSViewportDescribe($0.frame) } ?? "nil")"
    )
    performWithoutLayerActions {
        updateLayerFrames()
    }
    reportViewportSizeIfNeeded()
    updateAnimatedPlaybackState()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: macOSCanvasViewportView.viewDidMoveToWindow()
// 功能说明: 修改前挂到 window 时 print ViewportLifecycle；其后仍执行 refreshItemLayers 等真实逻辑。
override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    print(
        "[Canvas macOS][ViewportLifecycle] " +
        "action=viewDidMoveToWindow " +
        "viewBounds=\(macOSViewportDescribe(bounds)) " +
        "viewFrame=\(macOSViewportDescribe(frame)) " +
        "windowFrame=\(window.map { macOSViewportDescribe($0.frame) } ?? "nil")"
    )
    updateBackgroundAppearance()
    // ... refresh layers / chrome / overlays ...
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: macOSCanvasViewportView.layout()
// 功能说明: 修改后仅屏蔽 print；layout 后续的 updateLayerFrames / reportViewportSizeIfNeeded / updateAnimatedPlaybackState 仍照常执行。
override func layout() {
    super.layout()
    // Temporarily muted: ViewportLifecycle noise.
    #if false
    print(
        "[Canvas macOS][ViewportLifecycle] " +
        "action=layout " +
        "viewBounds=\(macOSViewportDescribe(bounds)) " +
        "viewFrame=\(macOSViewportDescribe(frame)) " +
        "windowFrame=\(window.map { macOSViewportDescribe($0.frame) } ?? "nil")"
    )
    #endif
    performWithoutLayerActions {
        updateLayerFrames()
    }
    reportViewportSizeIfNeeded()
    updateAnimatedPlaybackState()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: macOSCanvasViewportView.viewDidMoveToWindow()
// 功能说明: 修改后暂时屏蔽 ViewportLifecycle 打印；挂窗后的图层刷新逻辑不变。
override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    // Temporarily muted: ViewportLifecycle noise.
    #if false
    print(
        "[Canvas macOS][ViewportLifecycle] " +
        "action=viewDidMoveToWindow " +
        // ... 原字段不变 ...
        "windowFrame=\(window.map { macOSViewportDescribe($0.frame) } ?? "nil")"
    )
    #endif
    updateBackgroundAppearance()
    // ... refresh layers / chrome / overlays 不变 ...
}
```

---

## 结果对照（相对本次改动目标）

| 日志前缀 | 修改前 | 修改后 |
| --- | --- | --- |
| `[BoardList][macOS][RenameTrace]` / `[RenameTrace][Item]` | 直接 `print` | `#if false` 屏蔽 |
| `[BoardList][macOS][SelectionTrace]` | 直接 `print` | `#if false` 屏蔽 |
| `[BoardList][macOS][ThumbnailTrace][Controller|Item]` | 直接 `print` | `#if false` 屏蔽 |
| `[BoardList][ThumbnailTrace][...]`（Provider/Render/Poster/Text/Persisted/Seed 等） | 直接 `print`（部分含采样） | `#if false` 屏蔽 |
| `[Canvas macOS][ViewportLifecycle]` | 直接 `print` | `#if false` 屏蔽 |

## 备注

- 本记录对应工作区未提交 changes；写入本 markdown 后，`commit_records/` 下会多一个 untracked 文件，属预期。
- 未改 `BoardPreviewTracePolicy` 的 UserDefaults 默认值；本次是编译期屏蔽，不是改成 `disabled` 策略。
- 错误类日志如 `[BoardPreviewProvider] Failed to ...` 仍保留，不在本次屏蔽范围。
