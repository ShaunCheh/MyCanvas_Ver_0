# 20260326_183055_boardlist_thumbnail_version_stage3_record

## 记录范围

- 记录目标：记录本次 `boardlist` 缩略图版本治理阶段 3 的实现。
- 阶段目标：为 `BoardCatalogItem` 补一个“按 persisted 语义生成高分辨率缩略图”的独立入口，给后续阶段 4 的回写链路做准备。
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
- 本记录不包含：阶段 4 的 `BoardPreviewProvider` 回写接线。
- 本记录不包含：原始 GIF diff。
- 本记录不包含：git commit。

## 修改前：只有列表尺寸 fresh-render 和 runtimeState persisted-write

- 修改前，`BoardThumbnailRenderer.renderThumbnail(for: BoardCatalogItem, ...)` 直接承载列表侧的 `catalog-fresh` 渲染逻辑。
- 修改前，能生成 persisted 缩略图的入口只有 `renderPersistedThumbnail(for runtimeState: BoardRuntimeState, ...)`。
- 这意味着如果后续要在 `BoardPreviewProvider` 里基于 `BoardCatalogItem` 做高分辨率 persisted 重生，就没有一条现成的、与 persisted 语义一致的生成入口。
- 同时，也不能直接把列表 cell-size 的 `renderThumbnail(for:item,targetPixelSize:)` 结果拿去写 `thumbnail.png`，否则会把 persisted 图降成低分辨率。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: renderThumbnail(for:targetPixelSize:animatedImagePreviewMode:contentInset:cancellationCheck:)
// 功能说明: 修改前，BoardCatalogItem 的列表渲染逻辑直接写在这个公开入口里。
// 关键限制: 这里生成的是列表目标尺寸的图，不适合直接作为 persisted thumbnail 落盘。
func renderThumbnail(
    for item: BoardCatalogItem,
    targetPixelSize: CGSize,
    animatedImagePreviewMode: CanvasAnimatedImagePreviewMode =
        BoardPreviewContent.animatedImagePreviewMode,
    contentInset: CGFloat = 10,
    cancellationCheck: () throws -> Void = {}
) throws -> CGImage? {
    var cachedImagesByFilename: [String: CGImage] = [:]
    var decodeMaxPixelSizesByFilename: [String: Int] = [:]
    let traceContext = makeTraceContext(
        mode: "catalog-fresh",
        boardID: item.boardID,
        itemRecords: item.document.items
    )
    return try renderThumbnail(
        itemRecords: item.document.items,
        previewSeed: item.previewSeed,
        targetPixelSize: targetPixelSize,
        contentInset: contentInset,
        cancellationCheck: cancellationCheck,
        traceContext: traceContext
    ) { itemRecord, geometry, itemRecords in
        // ... 省略图片解码与缓存逻辑 ...
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: renderPersistedThumbnail(for:animatedImagePreviewMode:maximumLongestSide:cancellationCheck:)
// 功能说明: 修改前，只有 runtimeState 版本的 persisted-write 入口会按高分辨率 persisted 语义生成缩略图。
// 关键限制: BoardCatalogItem 没有对应入口，后续无法直接在列表链路重用这套“persisted 尺寸 + persisted 预览模式”的生成语义。
func renderPersistedThumbnail(
    for runtimeState: BoardRuntimeState,
    animatedImagePreviewMode: CanvasAnimatedImagePreviewMode =
        BoardPersistedThumbnailStore.animatedImagePreviewMode,
    maximumLongestSide: CGFloat = BoardPersistedThumbnailStore.maximumLongestSide,
    cancellationCheck: () throws -> Void = {}
) throws -> CGImage? {
    guard runtimeState.items.isEmpty == false else {
        return nil
    }

    let document = BoardDocumentMapper.makeDocument(from: runtimeState)
    let previewSeed = geometryPreviewBuilder.makeSeed(from: document)
    let snapshot = geometryPreviewBuilder.makeSnapshot(from: previewSeed)
    let targetPixelSize = BoardPersistedThumbnailStore.pixelSize(
        forDisplayWorldRect: snapshot.displayWorldRect,
        maximumLongestSide: maximumLongestSide
    )
    // ... 省略后续 runtimeItem poster 渲染逻辑 ...
}
```

## 修改后：抽取 catalog 渲染 helper，并新增 BoardCatalogItem 的 persisted 重生入口

- 修改后，列表侧 `renderThumbnail(for item: BoardCatalogItem, ...)` 只是一个薄封装，真正逻辑被收敛到 `renderCatalogItemThumbnail(...)`。
- 修改后，新增 `renderPersistedThumbnail(for item: BoardCatalogItem, ...)`，它会：
  - 使用 `BoardPersistedThumbnailStore.maximumLongestSide`
  - 通过 `persistedTargetPixelSize(...)` 计算 persisted 目标尺寸
  - 使用 `contentInset = 0`
  - 使用 persisted 预览模式
- 修改后，`runtimeState` 版本的 persisted-write 入口也复用了统一的 `persistedTargetPixelSize(...)` 尺寸计算，避免 persisted 尺寸语义分叉。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: renderThumbnail(for:targetPixelSize:animatedImagePreviewMode:contentInset:cancellationCheck:) / renderCatalogItemThumbnail(...)
// 功能说明: 修改后把 BoardCatalogItem 的通用渲染逻辑抽到私有 helper，方便列表 fresh-render 和 persisted 重生共用同一套资产解码/绘制实现。
// 修复结果: 后续阶段 4 可以复用这个 helper 生成高分辨率 persisted 图，而不是复制一套列表渲染逻辑。
func renderThumbnail(
    for item: BoardCatalogItem,
    targetPixelSize: CGSize,
    animatedImagePreviewMode: CanvasAnimatedImagePreviewMode =
        BoardPreviewContent.animatedImagePreviewMode,
    contentInset: CGFloat = 10,
    cancellationCheck: () throws -> Void = {}
) throws -> CGImage? {
    try renderCatalogItemThumbnail(
        item,
        targetPixelSize: targetPixelSize,
        animatedImagePreviewMode: animatedImagePreviewMode,
        contentInset: contentInset,
        traceMode: "catalog-fresh",
        cancellationCheck: cancellationCheck
    )
}

private func renderCatalogItemThumbnail(
    _ item: BoardCatalogItem,
    targetPixelSize: CGSize,
    animatedImagePreviewMode: CanvasAnimatedImagePreviewMode,
    contentInset: CGFloat,
    traceMode: String,
    cancellationCheck: () throws -> Void
) throws -> CGImage? {
    var cachedImagesByFilename: [String: CGImage] = [:]
    var decodeMaxPixelSizesByFilename: [String: Int] = [:]
    let traceContext = makeTraceContext(
        mode: traceMode,
        boardID: item.boardID,
        itemRecords: item.document.items
    )
    return try renderThumbnail(
        itemRecords: item.document.items,
        previewSeed: item.previewSeed,
        targetPixelSize: targetPixelSize,
        contentInset: contentInset,
        cancellationCheck: cancellationCheck,
        traceContext: traceContext
    ) { itemRecord, geometry, itemRecords in
        // ... 省略图片解码与缓存逻辑 ...
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: renderPersistedThumbnail(for:animatedImagePreviewMode:maximumLongestSide:cancellationCheck:)
// 功能说明: 修改后新增 BoardCatalogItem 版本的 persisted 重生入口，专门用于按 persisted 语义生成高分辨率缩略图。
// 修复结果: 后续列表链路不需要把 cell-size fresh-render 直接写回磁盘，而是可以走这条高分辨率入口。
func renderPersistedThumbnail(
    for item: BoardCatalogItem,
    animatedImagePreviewMode: CanvasAnimatedImagePreviewMode =
        BoardPersistedThumbnailStore.animatedImagePreviewMode,
    maximumLongestSide: CGFloat = BoardPersistedThumbnailStore.maximumLongestSide,
    cancellationCheck: () throws -> Void = {}
) throws -> CGImage? {
    let targetPixelSize = persistedTargetPixelSize(
        for: item.previewSeed,
        maximumLongestSide: maximumLongestSide
    )
    guard targetPixelSize.width > 0, targetPixelSize.height > 0 else {
        return nil
    }

    return try renderCatalogItemThumbnail(
        item,
        targetPixelSize: targetPixelSize,
        animatedImagePreviewMode: animatedImagePreviewMode,
        contentInset: 0,
        traceMode: "persist-rebuild",
        cancellationCheck: cancellationCheck
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: persistedTargetPixelSize(for:maximumLongestSide:) / renderPersistedThumbnail(for runtimeState:...)
// 功能说明: 修改后把 persisted 目标尺寸计算收敛成一个 helper，并让 runtimeState 的 persisted-write 入口复用它。
// 修复结果: persisted 缩略图尺寸语义集中在一个位置，避免 BoardCatalogItem 路径和 runtimeState 路径各算各的。
private func persistedTargetPixelSize(
    for previewSeed: BoardPreviewSeed,
    maximumLongestSide: CGFloat
) -> CGSize {
    let snapshot = geometryPreviewBuilder.makeSnapshot(from: previewSeed)
    return BoardPersistedThumbnailStore.pixelSize(
        forDisplayWorldRect: snapshot.displayWorldRect,
        maximumLongestSide: maximumLongestSide
    )
}

func renderPersistedThumbnail(
    for runtimeState: BoardRuntimeState,
    animatedImagePreviewMode: CanvasAnimatedImagePreviewMode =
        BoardPersistedThumbnailStore.animatedImagePreviewMode,
    maximumLongestSide: CGFloat = BoardPersistedThumbnailStore.maximumLongestSide,
    cancellationCheck: () throws -> Void = {}
) throws -> CGImage? {
    guard runtimeState.items.isEmpty == false else {
        return nil
    }

    let document = BoardDocumentMapper.makeDocument(from: runtimeState)
    let previewSeed = geometryPreviewBuilder.makeSeed(from: document)
    let targetPixelSize = persistedTargetPixelSize(
        for: previewSeed,
        maximumLongestSide: maximumLongestSide
    )
    // ... 省略后续 runtimeItem poster 渲染逻辑 ...
}
```

## 本次修改后的实际行为

- `BoardThumbnailRenderer` 现在已经具备两条清晰分工的 `BoardCatalogItem` 路径：
  - 列表即时预览：`renderThumbnail(for item: targetPixelSize: ...)`
  - 高分辨率 persisted 重生：`renderPersistedThumbnail(for item: ...)`
- 高分辨率 persisted 重生入口已经和 persisted 尺寸/预览模式语义对齐，不会错误复用列表 cell-size 输出。
- 当前阶段仍然没有把这条入口接进 `BoardPreviewProvider.loadBestAvailableThumbnail(...)`，所以 fresh-render 之后还不会自动写回新的 `thumbnail.png`。

## 验证情况

- 已检查 `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift` 的 lint / 语法诊断：无新增错误。
- 已复核本次 diff：阶段 3 只收敛在 renderer 内部能力抽取与新入口增加，没有提前进入阶段 4 的 Provider 回写链路。
