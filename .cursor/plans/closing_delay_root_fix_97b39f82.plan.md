---
name: closing_delay_root_fix
overview: 把 iOS 返回缩小时的前置卡顿，从“返回时全量 refresh/reload 全列表”改成“常驻 BoardList 缓存 + 单板更新 + 无预览 target-ready 快路径”。这样动画开始前只做目标板必要的数据同步与 rect 解析，不再被无关卡片的 catalog/thumbnail 工作阻塞。
todos:
  - id: collapse-closing-refresh-entrypoint
    content: 移除 closing 链里的重复 refresh，让 target geometry 准备成为唯一前置同步入口
    status: pending
  - id: add-single-board-catalog-load
    content: 在 BoardStore / BoardCatalogLoader 增加单板 catalog 加载能力
    status: pending
  - id: switch-boardlist-to-targeted-upsert
    content: 在 BoardList 用 returning board 的单条 upsert + 重排替代全量 availableBoards 重建
    status: pending
  - id: suppress-preview-during-target-resolution
    content: target-ready 期间跳过无关卡片 preview，geometry 只依赖布局和目标卡片位置
    status: pending
  - id: detach-thumbnail-trace-side-effects
    content: 把 ThumbnailTrace 中的源图读取从同步主路径剥离，避免 profiling 干扰真实性能
    status: pending
  - id: verify-with-closing-trace
    content: 用同一套 closing trace 再次验证 target-ready、reveal queueing 和动画前置耗时
    status: pending
isProject: false
---

# Closing Delay Root Fix

## 根因结论

- 当前 closing 链在 `[MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift](MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift)` 的 `beginClosingTransition()` 里，先调用 `prepareForDisplay()`，后调用 `prepareTransitionTargetGeometry(...)`；这两处都会落到 `[MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift](MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift)` 的 `refreshBookmarkStatus()`。
- `refreshBookmarkStatus()` 会调用 `[MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift](MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift)` 的 `loadCatalog()`，而后者又依赖 `[MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift](MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift)` 的 `listBoardDocumentEntries()` 做全量目录扫描与每个 `board.json` 解码。
- `reloadBoardList()` 会触发 `collectionView.reloadData()`，随后 `cellForItemAt()` 同步调用 `[MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift](MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift)` 的 `immediatePreview(...)`；所以 target geometry completion 之前，所有可见卡片都会参与主线程上的 preview 工作。
- `BoardPreviewProvider` 里的 `logBoardPreviewProviderCacheHit()` / `logBoardPreviewProviderSourceImagesIfNeeded()` 还把缩略图诊断和真实图片读取绑在了一起，debug/trace 模式下会额外放大主线程耗时。

## 修复原则

- 不再把“从 Canvas 返回”当作一次冷启动的 BoardList 进入流程，而是把常驻的 `boardListViewController` 视为长生命周期缓存容器。
- returning board 只需要两件事：
  1. 让目标 board 的列表模型是最新的。
  2. 尽快拿到目标卡片的 `cardRect`。
- closing 动画开始前不需要全量刷新所有 board，也不需要让无关卡片先生成完整 preview。

## 实施方案

### 1. 把 closing 链改成“单入口 target-prep”

- 在 `[MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift](MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift)` 中移除 closing 时对 `destinationViewController.prepareForDisplay()` 的前置调用。
- 让 `prepareTransitionTargetGeometry(...)` 成为 closing 期间唯一的数据同步入口，避免一次 return 里出现两次 `refreshBookmarkStatus()`。
- 若仍需要做全量一致性校准，把它延后到 `completeClosingTransition()` 之后异步执行，而不是放在 `carrierAnimateBegin` 之前阻塞动画。

### 2. 为 BoardList 增加单板更新能力，替代全量 catalog 拉取

- 在 `[MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift](MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift)` 增加 `loadBoardDocumentEntry(id:)` 或等价单板 API，复用现有 `boardDirectoryURL(...)` 和 `readBoardDocument(at:)`，避免 `contentsOfDirectory` + 全量遍历。
- 在 `[MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift](MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift)` 增加 `loadCatalogItem(boardID:)`，把单条 `BoardDocumentCatalogEntry` 映射成 `BoardCatalogItem`。
- 在 `[MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift](MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift)` 为 `availableBoards` 增加 `upsert`、重排和索引定位逻辑，只更新 returning board，而不是重建整个数组。

### 3. 让 target-ready 路径只做“几何就绪”，不做“预览就绪”

- 在 `[MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift](MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift)` 的 `prepareTransitionTargetGeometry(...)` 中，引入 closing target-resolution 模式。
- 在该模式下：
  - 只确保目标 board 的条目存在并排到正确位置。
  - 只刷新目标 index path，必要时插入/移动目标项；避免调用 `reloadBoardList()` / `collectionView.reloadData()`。
  - geometry 优先来自 `layoutAttributes` / `transitionCardRect(at:)`，不是来自 preview 是否渲染完成。
- 在 `[MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift](MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift)` 和 `cellForItemAt()` 路径里，closing target-resolution 期间对无关卡片直接使用 `.geometry` 占位，跳过 `immediatePreview(...)` 与 `requestThumbnail(...)`。

### 4. 把诊断副作用从运行时路径里拆出去

- 在 `[MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift](MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift)` 里，把 `logBoardPreviewProviderCacheHit()` / `logBoardPreviewProviderSourceImagesIfNeeded()` 放到显式 debug 开关之后，或改成完全不读源素材的轻量日志。
- 目标是保证“开启 trace 只会多打印，不会多做图片读取与解码”，避免 profiling 本身改变 closing 链的时序。

## 预期收益

- 一次 closing 不再出现两轮 `refreshBookmarkStatus()` / `loadCatalog()`。
- `requestTargetGeometry -> targetGeometryResolved` 不再被全量列表刷新和无关卡片 preview 阻塞，应该从当前约 `0.506s` 明显下降到“单板读取 + 排序/布局 + reveal”级别。
- `revealBoardBegin local` 应接近 0，因为主线程前面不再被 `reloadData()` 和同步 preview 压满。
- `carrierPrepareFinished` 也会同步下降，因为 BoardList mount 后不再立刻驱动所有可见卡片走同步 preview 配置。

## 关键文件

- `[MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift](MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift)`
- `[MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift](MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift)`
- `[MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift](MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift)`
- `[MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift](MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift)`
- `[MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift](MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift)`
- `[MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift](MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift)`

