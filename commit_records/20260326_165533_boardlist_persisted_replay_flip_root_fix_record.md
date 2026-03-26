# 20260326_165533_boardlist_persisted_replay_flip_root_fix_record

## 记录范围

- 记录目标：记录本次 `boardlist` 缩略图“图片之间上下位置颠倒”的根因修复。
- 根因结论：`persisted-replay` 路径把已经成图的持久化位图，又画进了一个带全局 `y:-1` 翻转的 `CGContext`，导致整张缩略图二次上下翻转。
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
- 本记录不包含：原始 GIF diff。
- 本记录不包含：git commit。

## 修改前：`persisted-replay` 复用统一的翻转上下文

- 修改前，`renderThumbnail(fromPersistedThumbnail:...)` 和矢量渲染路径共用 `prepareContext(...)`。
- `prepareContext(...)` 会对整个 `CGContext` 执行 `translateBy + scaleBy(y: -1)`。
- 这对 `fresh-render` / `persist-write` 是正确的，因为它们输入的是 world-space 几何和逐项绘制元素。
- 但对 `persisted-replay` 不正确，因为它的输入已经是最终方向正确的整张位图。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: renderThumbnail(fromPersistedThumbnail:previewSeed:boardID:targetPixelSize:contentInset:cancellationCheck:)
// 功能说明: 修改前 persisted-replay 复用统一的 prepareContext()，直接把已持久化位图画进 preview-space rect。
// 关键问题: prepareContext() 已经对 context 做了全局 y 轴翻转，导致整张 persisted thumbnail 在 replay 时再次上下翻转。
func renderThumbnail(
    fromPersistedThumbnail persistedThumbnail: CGImage,
    previewSeed: BoardPreviewSeed,
    boardID: UUID? = nil,
    targetPixelSize: CGSize,
    contentInset: CGFloat = 10,
    cancellationCheck: () throws -> Void = {}
) throws -> CGImage? {
    let normalizedTargetPixelSize = normalizedPixelSize(targetPixelSize)
    // ... 省略 geometry / context 初始化 ...

    prepareContext(
        context,
        pixelSize: normalizedTargetPixelSize
    )
    logRenderSurface(
        traceContext: traceContext,
        previewSeed: previewSeed,
        targetPixelSize: targetPixelSize,
        contentInset: contentInset,
        geometry: geometry,
        context: context
    )
    try cancellationCheck()
    logPersistedReplayDraw(
        traceContext: traceContext,
        previewRect: geometry.contentRect,
        persistedThumbnail: persistedThumbnail,
        context: context
    )
    // 这里直接使用 preview-space rect 重画位图。
    context.draw(persistedThumbnail, in: geometry.contentRect)
    try cancellationCheck()
    return context.makeImage()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: prepareContext(_:pixelSize:)
// 功能说明: 修改前所有缩略图路径统一走这个上下文准备函数。
// 关键问题: 它会把整个 CGContext 翻成 top-left / y-down 坐标系，不适合重放已经栅格化完成的 persisted bitmap。
private func prepareContext(
    _ context: CGContext,
    pixelSize: CGSize
) {
    context.interpolationQuality = .high
    context.setShouldAntialias(true)
    context.clear(
        CGRect(
            x: 0,
            y: 0,
            width: pixelSize.width,
            height: pixelSize.height
        )
    )

    // 统一把上下文翻转成预览坐标系。
    context.translateBy(x: 0, y: pixelSize.height)
    context.scaleBy(x: 1, y: -1)
}
```

## 修改后：拆分矢量渲染上下文和位图回放上下文

- 修改后，`fresh-render` / `persist-write` 继续走 `prepareVectorRenderContext(...)`，保持原有 top-left / y-down 语义不变。
- `persisted-replay` 改走 `prepareBitmapReplayContext(...)`，只做基础清理，不再施加全局 `y:-1` 翻转。
- 同时新增 `bitmapReplayRect(...)`，把 `geometry.contentRect` 从 preview-space 转成 bitmap-space，确保 replay 只做位置适配，不再做整图镜像。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: renderThumbnail(fromPersistedThumbnail:previewSeed:boardID:targetPixelSize:contentInset:cancellationCheck:)
// 功能说明: 修改后 persisted-replay 改走 bitmap-space 上下文；先换算 replay rect，再直接绘制持久化位图。
// 修复结果: 避免对已经成图的 persisted thumbnail 再次施加全局 y 轴翻转。
func renderThumbnail(
    fromPersistedThumbnail persistedThumbnail: CGImage,
    previewSeed: BoardPreviewSeed,
    boardID: UUID? = nil,
    targetPixelSize: CGSize,
    contentInset: CGFloat = 10,
    cancellationCheck: () throws -> Void = {}
) throws -> CGImage? {
    let normalizedTargetPixelSize = normalizedPixelSize(targetPixelSize)
    // ... 省略 geometry / context 初始化 ...

    // 已持久化缩略图本身方向正确，这里只按位图坐标回放，不再复用全局翻转 CTM。
    prepareBitmapReplayContext(
        context,
        pixelSize: normalizedTargetPixelSize
    )
    let bitmapReplayRect = bitmapReplayRect(
        fromPreviewRect: geometry.contentRect,
        pixelSize: normalizedTargetPixelSize
    )
    logRenderSurface(
        traceContext: traceContext,
        previewSeed: previewSeed,
        targetPixelSize: targetPixelSize,
        contentInset: contentInset,
        geometry: geometry,
        context: context
    )
    try cancellationCheck()
    logPersistedReplayDraw(
        traceContext: traceContext,
        previewRect: geometry.contentRect,
        bitmapReplayRect: bitmapReplayRect,
        persistedThumbnail: persistedThumbnail,
        context: context
    )
    context.draw(persistedThumbnail, in: bitmapReplayRect)
    try cancellationCheck()
    return context.makeImage()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: prepareVectorRenderContext(_:pixelSize:) / prepareBitmapReplayContext(_:pixelSize:) / prepareBaseContext(_:pixelSize:) / bitmapReplayRect(fromPreviewRect:pixelSize:)
// 功能说明: 修改后显式区分“矢量渲染”和“位图回放”的上下文语义，根因修复点集中在 replay 分支。
private func prepareVectorRenderContext(
    _ context: CGContext,
    pixelSize: CGSize
) {
    prepareBaseContext(
        context,
        pixelSize: pixelSize
    )

    // 仅矢量渲染路径继续切到 preview-space 的 top-left / y-down 坐标系。
    context.translateBy(x: 0, y: pixelSize.height)
    context.scaleBy(x: 1, y: -1)
}

private func prepareBitmapReplayContext(
    _ context: CGContext,
    pixelSize: CGSize
) {
    // 位图回放路径只做基础准备，不再对整张 persisted bitmap 做全局翻转。
    prepareBaseContext(
        context,
        pixelSize: pixelSize
    )
}

private func prepareBaseContext(
    _ context: CGContext,
    pixelSize: CGSize
) {
    context.interpolationQuality = .high
    context.setShouldAntialias(true)
    context.clear(
        CGRect(
            x: 0,
            y: 0,
            width: pixelSize.width,
            height: pixelSize.height
        )
    )
}

private func bitmapReplayRect(
    fromPreviewRect previewRect: CGRect,
    pixelSize: CGSize
) -> CGRect {
    let standardizedPreviewRect = previewRect.standardized
    return CGRect(
        x: standardizedPreviewRect.minX,
        y: pixelSize.height - standardizedPreviewRect.maxY,
        width: standardizedPreviewRect.width,
        height: standardizedPreviewRect.height
    ).standardized
}
```

## 本次修改后的实际行为

- `fresh-render`：仍然逐项绘制 image / text，并继续使用翻转后的 preview-space CTM。
- `persist-write`：仍然沿用矢量渲染路径，生成 `thumbnail.png` 的逻辑不变。
- `persisted-replay`：不再复用全局翻转 CTM，而是把 `contentRect` 转成 bitmap-space 的 `bitmapReplayRect` 后直接绘制持久化位图。
- 修改范围只收敛在 `BoardThumbnailRenderer` 内部，不影响：
- `CanvasMiniMapViewGeometry` 的 world-to-minimap 几何映射；
- `BoardPreviewRenderer` / `iOSBoardPreviewView` 的展示层；
- `BoardPersistedThumbnailStore` 的读写协议。

## 验证情况

- 已检查 `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift` 的 lint / 语法诊断：无新增错误。
- 已确认工作区最终只落下这一个共享渲染文件修改。
- 未执行 `xcodebuild`：当前环境的 active developer directory 指向 `CommandLineTools`，缺少完整 Xcode。
