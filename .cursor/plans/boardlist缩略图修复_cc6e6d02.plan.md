---
name: boardlist缩略图修复
overview: 基于当前日志与代码结构，本次修复以 security-scoped access 生命周期为主线，统一 BoardList 的 persisted/fresh 缩略图文件读取路径，并保留现有 `poster/asset` 字段语义不变。
todos:
  - id: scope-boundary
    content: 在预览链路建立统一的 security-scoped access 边界，覆盖 immediatePreview 与 requestThumbnail 两条磁盘读取路径
    status: pending
  - id: provider-refactor
    content: 改造 BoardPreviewProvider，使 persisted thumbnail 与 fresh-render 都在同一 access closure 内完成文件读取
    status: pending
  - id: catalog-flow
    content: 收紧 BoardCatalogItem 对裸 URL 的依赖，避免后台缩略图任务长期直接消费闭包外派生的目录 URL
    status: pending
  - id: targeted-logging
    content: 补精确的 boardID、filename、resolved path 失败日志，并保留现有 Provider/Controller/Item 级诊断日志用于修复验证
    status: pending
  - id: regression-verify
    content: 在 iOS 与 macOS 上验证静态图、GIF、视频封面、空板与含文本 board 的缩略图路径全部恢复
    status: pending
isProject: false
---

# 修复 BoardList 缩略图访问链路

## 根因判断

- 当前最可能的根因不是 `BoardList` UI 自己不显示，而是 **缩略图异步渲染发生在 security-scoped access 生命周期之外**。
- 证据链已经比较完整：
  - `BoardStore.loadBoard(...)` 能成功读取同一批素材。
  - `BoardPreviewProvider` 的 `fresh-render` 已经进入真实渲染，但随后在读素材时报 `NSCocoaErrorDomain Code=260`。
  - `BoardList` 的 catalog 只是在有权限的闭包里生成了 `URL`，后续异步缩略图任务却在闭包外直接使用这些 `URL`。
- `posterImageFilename / assetFilename / sourceVideoFilename / assetKind` 这组字段的当前语义是自洽的，属于次级排查线，不是本次主修复目标。

```3:7:MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogItem.swift
struct BoardCatalogItem {
    let document: BoardDocument
    let persistedThumbnailURL: URL
    let assetsDirectoryURL: URL
    let previewSeed: BoardPreviewSeed
```

```7:23:MyCanvas_Ver_0/App/SelectedFolderAccess.swift
static func withSelectedFolderURL<T>(
    userDefaults: UserDefaults = .standard,
    _ body: (URL) throws -> T
) throws -> T {
    let resolvedBookmark = try FolderBookmarkStore.resolveStoredFolderBookmark(
        userDefaults: userDefaults
    )
    let url = resolvedBookmark.url
    let didStartAccessing = url.startAccessingSecurityScopedResource()
    defer {
        if didStartAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }
```

## 修复方向

- 以 **根因修复** 为原则，把所有 BoardList 缩略图相关的磁盘读取重新收敛到统一的 access boundary 内。
- 推荐做法：在 [MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift](MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift) 建立预览侧的统一访问入口，让以下两条路径都在同一次 scoped access 中完成：
  - persisted thumbnail 读取：`thumbnail.png`
  - fresh-render 读取：`assets/` 下 poster / GIF / video poster
- 不再把 `BoardCatalogItem.assetsDirectoryURL` / `persistedThumbnailURL` 当作可长期直接读取的权限载体，而是在真正读文件时重新基于 board 目录解析实际路径。

## 实施步骤

### 1. 收敛 BoardList 预览 I/O 的访问边界

- 在 [MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift](MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift) 增加一个预览专用的文件访问入口，例如围绕 `loadBestAvailableThumbnail(...)` 和 `immediatePreview(...)` 的磁盘分支统一包裹 `SelectedFolderAccess.withBoardsDirectoryURL(...)`。
- 目标是让 `requestThumbnail` 的后台 `OperationQueue`、以及同步 `immediatePreview` 的磁盘访问，都在有效 scope 内执行。
- [MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift](MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift) 保持为参考基线：与 board 目录相关的 I/O 继续遵循它现有的访问模式。

### 2. 改造预览链路的数据流，降低裸 URL 依赖

- 重新审视 [MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogItem.swift](MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogItem.swift) 的职责。
- 推荐方案：
  - 保留 `document`、`previewSeed`、`boardID`、`updatedAt` 等稳定信息。
  - 将 `assetsDirectoryURL` / `persistedThumbnailURL` 视为临时派生值，避免后台渲染长期直接消费它们。
- 如需最小化结构波动，可先在 provider 内部忽略 `BoardCatalogItem` 上的裸 URL，统一按 `boardID` 重新计算 board 目录与 assets 路径；如果后续代码仍频繁误用，再继续收紧 `BoardCatalogItem` 字段。

### 3. 让 persisted thumbnail 与 fresh-render 共享同一访问语义

- [MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift](MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift) 的 `loadThumbnailIfFresh(...)` 当前默认直接 `readData`。
- [MyCanvas_Ver_0/Platform/Shared/BoardList/BoardMediaPosterImageResolver.swift](MyCanvas_Ver_0/Platform/Shared/BoardList/BoardMediaPosterImageResolver.swift) 也直接读 `assetsDirectoryURL`。
- 本次修复不要分别打补丁，而是从 provider 这一层保证：
  - persisted 读图
  - asset poster 读图
  - fresh-render 中的所有素材解析
  都在同一套 board access closure 内完成。
- 这样可以避免一部分路径修了、另一部分路径继续在闭包外读文件的“半修复”状态。

### 4. 保持当前素材字段语义稳定，不混入额外存储改造

- [MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift](MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift) 与 [MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift](MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift) 当前的字段含义先不动：
  - `posterImageFilename` 仍是 BoardList / Canvas 可渲染封面
  - `sourceVideoFilename` 仍只代表视频源文件
  - GIF / 静态图继续由 `assetKind` 区分
- 这次修复的目标是先恢复读取链路，不在同一轮里混入新的文档字段迁移或资产命名规则调整。

### 5. 保留定向日志做一次修复后验证

- 继续保留当前已经补上的 `Provider / Controller / Item` 级日志，直到验证完成。
- 另外建议补一条更精确的失败日志：把最终尝试读取的 `boardID + filename + resolved URL path` 打出来，方便确认是否还有个别板子是真缺文件，而不是 scope 问题。
- 验证稳定后，再决定降级或移除高噪声日志。

## 验证范围

- iOS `BoardList`：
  - 含文本的 board（会走 `geometry-fallback -> fresh-render`）
  - 无文本但有 persisted thumbnail 的 board
  - 空白 board
- macOS `BoardList`：重复同样场景，确保修复不只对 iOS 生效。
- 素材类型覆盖：
  - 静态图
  - GIF
  - 视频封面
- 回归确认：
  - `BoardStore.loadBoard` 行为不变
  - `persisted thumbnail` 命中路径不退化
  - 当前 GIF 多选帧导入相关改动不受影响

## 非目标

- 这次计划不处理你日志里的 iOS `UIVisualEffectView` / toolbar host AutoLayout 警告，那是另一条独立问题线。
- 这次计划不引入新的文档结构迁移，也不做提交。
