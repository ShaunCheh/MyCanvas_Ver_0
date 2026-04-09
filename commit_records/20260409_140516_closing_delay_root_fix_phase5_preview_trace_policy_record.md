# 20260409_140516_closing_delay_root_fix_phase5_preview_trace_policy_record

## 记录范围

- 记录内容：`closing_delay_root_fix` 计划的 `Phase 5` 实施记录。
- 记录目标：把 `BoardPreviewProvider` 中会放大 target-ready / trace 成本的诊断副作用收口为可控策略，默认不再因为 cache-hit 日志读取源图或做高成本图像签名采样。
- 记录依据：本记录基于当前工作树的 `git diff -- MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift` 与修改后的源码内容整理。
- 对应计划文件：`.cursor/plans/closing_delay_root_fix_97b39f82.plan.md`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift`
- 本记录不包含：`Phase 4` 中已经落地的 `BoardListPreviewWorkPolicy.geometryOnly` 与 target-ready 局部 mutation。
- 本记录不包含：`Phase 6` 的 closing trace 回归验证与性能护栏。
- 本记录不包含：git commit。

## 问题背景

- `Phase 4` 之后，closing target-ready 的几何准备链已经从整页 `reloadData()` 中脱离出来。
- 但 `BoardPreviewProvider` 在 cache-hit 场景下仍然会执行两类高成本诊断逻辑：
  - `logBoardThumbnailTraceImageRegions(...)`
  - `logBoardPreviewProviderSourceImagesIfNeeded(...)`
- 这两条路径分别会触发：
  - 对缓存图再做图像签名 / 采样
  - 在 verbose 诊断里读取源图或 poster frame
- 结果是：即使目标架构已经修正，开启 trace 时仍可能因为“观测行为本身”把主线程与 IO 成本重新放大。
- `Phase 5` 的目标就是把这些副作用改成显式策略控制，默认只保留轻量元数据级日志。

## 修改一：新增 `BoardPreviewTracePolicy`，把 trace 成本模型显式化

### 修改前

- `BoardPreviewProvider` 内没有独立的 trace policy 概念。
- cache-hit 分支一旦进入详细日志，就会直接执行后续 image snapshot / source image 诊断路径。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名/符号名: BoardPreviewProvider
// 功能说明: 修改前 provider 没有显式的 trace policy，cache-hit 日志是否进入高成本路径完全由调用点固定决定。
import CoreGraphics
import Foundation

final class BoardPreviewProvider {
    private let thumbnailCache: BoardThumbnailCache
    private let thumbnailRenderer: BoardThumbnailRenderer
    private let mediaPosterImageResolver: BoardMediaPosterImageResolver
    private let renderQueue: OperationQueue
    private let callbackQueue: DispatchQueue
    private let userDefaults: UserDefaults

    init(
        thumbnailCache: BoardThumbnailCache = BoardThumbnailCache(),
        thumbnailRenderer: BoardThumbnailRenderer = BoardThumbnailRenderer(),
        mediaPosterImageResolver: BoardMediaPosterImageResolver = BoardMediaPosterImageResolver(),
        userDefaults: UserDefaults = .standard,
        callbackQueue: DispatchQueue = .main
    ) {
        self.thumbnailCache = thumbnailCache
        self.thumbnailRenderer = thumbnailRenderer
        self.mediaPosterImageResolver = mediaPosterImageResolver
        self.userDefaults = userDefaults
        self.callbackQueue = callbackQueue

        let renderQueue = OperationQueue()
        renderQueue.name = "BoardPreviewProvider.renderQueue"
        renderQueue.maxConcurrentOperationCount = 2
        renderQueue.qualityOfService = .userInitiated
        self.renderQueue = renderQueue
    }
}
```

### 修改后

- 新增 `BoardPreviewTracePolicy`：
  - `.disabled`
  - `.metadataOnly`
  - `.verbose`
- 通过 `UserDefaults` 中的 `BoardPreviewTracePolicy` 字符串键解析当前策略。
- 默认值是 `.metadataOnly`，这意味着即使没有显式配置，也不会再自动进入最重的源图 / 图像采样诊断路径。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名/符号名: BoardPreviewTracePolicy
// 功能说明: 修改后 provider 引入显式 trace 策略，默认走 metadataOnly，只有显式 verbose 才进入高成本诊断路径。
import CoreGraphics
import Foundation

private enum BoardPreviewTracePolicy: String {
    case disabled = "disabled"
    case metadataOnly = "metadata-only"
    case verbose = "verbose"

    private static let userDefaultsKey = "BoardPreviewTracePolicy"

    init(userDefaults: UserDefaults) {
        let rawValue = userDefaults.string(
            forKey: Self.userDefaultsKey
        )?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

        switch rawValue {
        case Self.disabled.rawValue:
            self = .disabled
        case Self.verbose.rawValue:
            self = .verbose
        case Self.metadataOnly.rawValue, "metadataonly", "metadata_only", nil, "":
            self = .metadataOnly
        default:
            self = .metadataOnly
        }
    }
}

final class BoardPreviewProvider {
    private let thumbnailCache: BoardThumbnailCache
    private let thumbnailRenderer: BoardThumbnailRenderer
    private let mediaPosterImageResolver: BoardMediaPosterImageResolver
    private let renderQueue: OperationQueue
    private let callbackQueue: DispatchQueue
    private let userDefaults: UserDefaults

    // ... 省略其余实现 ...
}
```

## 修改二：把 cache-hit 详细日志改成策略驱动，而不是固定执行重路径

### 修改前

- `immediatePreview(...)` 和 `requestThumbnail(...)` 的 cache-hit 分支都会直接调用 `logBoardPreviewProviderCacheHit(...)`。
- 旧版 `logBoardPreviewProviderCacheHit(...)` 总会执行：
  - `logBoardThumbnailTraceImageRegions(...)`
  - `logBoardPreviewProviderSourceImagesIfNeeded(...)`
- 这意味着 cache-hit 日志天然携带额外图像采样和可能的源图读取成本。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名/符号名: immediatePreview(for:targetPixelSize:) / requestThumbnail(for:targetPixelSize:completion:) / logBoardPreviewProviderCacheHit(...)
// 功能说明: 修改前 cache-hit 一旦触发详细日志，就会固定进入 image-region 采样和 source-image 读取诊断。
func immediatePreview(
    for item: BoardCatalogItem,
    targetPixelSize: CGSize? = nil
) -> BoardPreviewContent {
    // ... 省略 cacheKey 构造 ...

    if let cachedImage = thumbnailCache.image(for: cacheKey) {
        logBoardPreviewProviderDecision(
            phase: "immediatePreview",
            boardID: item.boardID,
            revisionToken: item.revisionToken,
            targetPixelSize: targetPixelSize,
            source: "cache-hit"
        )
        logBoardPreviewProviderCacheHit(
            phase: "immediatePreview-cache-hit",
            item: item,
            targetPixelSize: targetPixelSize,
            cachedImage: cachedImage,
            mediaPosterImageResolver: mediaPosterImageResolver,
            userDefaults: userDefaults
        )
        return .thumbnail(cachedImage, item.previewSeed)
    }

    // ... 省略其余逻辑 ...
}

func requestThumbnail(
    for item: BoardCatalogItem,
    targetPixelSize: CGSize,
    completion: @escaping (BoardPreviewContent?) -> Void
) -> BoardPreviewRequestToken {
    // ... 省略 cacheKey 构造 ...

    if let cachedImage = thumbnailCache.image(for: cacheKey) {
        logBoardPreviewProviderDecision(
            phase: "requestThumbnail",
            boardID: item.boardID,
            revisionToken: item.revisionToken,
            targetPixelSize: targetPixelSize,
            source: "cache-hit"
        )
        logBoardPreviewProviderCacheHit(
            phase: "requestThumbnail-cache-hit",
            item: item,
            targetPixelSize: targetPixelSize,
            cachedImage: cachedImage,
            mediaPosterImageResolver: mediaPosterImageResolver,
            userDefaults: self.userDefaults
        )
        // ... 省略 callback 交付 ...
    }

    // ... 省略其余逻辑 ...
}

private func logBoardPreviewProviderCacheHit(
    phase: String,
    item: BoardCatalogItem,
    targetPixelSize: CGSize,
    cachedImage: CGImage,
    mediaPosterImageResolver: BoardMediaPosterImageResolver,
    userDefaults: UserDefaults
) {
    logBoardThumbnailTraceImageRegions(
        phase: phase,
        mode: "provider-cache-hit",
        boardID: item.boardID,
        previewSeed: item.previewSeed,
        targetPixelSize: targetPixelSize,
        contentInset: 10,
        image: cachedImage
    )
    logBoardPreviewProviderSourceImagesIfNeeded(
        phase: phase,
        item: item,
        mediaPosterImageResolver: mediaPosterImageResolver,
        userDefaults: userDefaults
    )
}
```

### 修改后

- `immediatePreview(...)` 和 `requestThumbnail(...)` 在 cache-hit 分支都会先读取 `currentTracePolicy()`。
- `logBoardPreviewProviderCacheHit(...)` 新增 `tracePolicy` 参数，并按策略分流：
  - `.disabled`：不再打印额外 cache-hit 细节
  - `.metadataOnly`：只打印轻量元数据，不做图像采样
  - `.verbose`：保留原有 `logBoardThumbnailTraceImageRegions(...)`
- `BoardPreviewProvider` 新增 `currentTracePolicy()` helper，把策略读取统一收口到内部。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名/符号名: immediatePreview(for:targetPixelSize:) / requestThumbnail(for:targetPixelSize:completion:) / currentTracePolicy() / logBoardPreviewProviderCacheHit(...)
// 功能说明: 修改后 cache-hit 诊断由 BoardPreviewTracePolicy 驱动，默认 metadataOnly 不再固定进入高成本图像采样路径。
func immediatePreview(
    for item: BoardCatalogItem,
    targetPixelSize: CGSize? = nil
) -> BoardPreviewContent {
    // ... 省略 cacheKey 构造 ...

    if let cachedImage = thumbnailCache.image(for: cacheKey) {
        logBoardPreviewProviderDecision(
            phase: "immediatePreview",
            boardID: item.boardID,
            revisionToken: item.revisionToken,
            targetPixelSize: targetPixelSize,
            source: "cache-hit"
        )
        logBoardPreviewProviderCacheHit(
            phase: "immediatePreview-cache-hit",
            item: item,
            targetPixelSize: targetPixelSize,
            cachedImage: cachedImage,
            tracePolicy: currentTracePolicy(),
            mediaPosterImageResolver: mediaPosterImageResolver,
            userDefaults: userDefaults
        )
        return .thumbnail(cachedImage, item.previewSeed)
    }

    // ... 省略其余逻辑 ...
}

func requestThumbnail(
    for item: BoardCatalogItem,
    targetPixelSize: CGSize,
    completion: @escaping (BoardPreviewContent?) -> Void
) -> BoardPreviewRequestToken {
    // ... 省略 cacheKey 构造 ...

    if let cachedImage = thumbnailCache.image(for: cacheKey) {
        logBoardPreviewProviderDecision(
            phase: "requestThumbnail",
            boardID: item.boardID,
            revisionToken: item.revisionToken,
            targetPixelSize: targetPixelSize,
            source: "cache-hit"
        )
        logBoardPreviewProviderCacheHit(
            phase: "requestThumbnail-cache-hit",
            item: item,
            targetPixelSize: targetPixelSize,
            cachedImage: cachedImage,
            tracePolicy: currentTracePolicy(),
            mediaPosterImageResolver: mediaPosterImageResolver,
            userDefaults: self.userDefaults
        )
        // ... 省略 callback 交付 ...
    }

    // ... 省略其余逻辑 ...
}

private func currentTracePolicy() -> BoardPreviewTracePolicy {
    BoardPreviewTracePolicy(userDefaults: userDefaults)
}

private func logBoardPreviewProviderCacheHit(
    phase: String,
    item: BoardCatalogItem,
    targetPixelSize: CGSize,
    cachedImage: CGImage,
    tracePolicy: BoardPreviewTracePolicy,
    mediaPosterImageResolver: BoardMediaPosterImageResolver,
    userDefaults: UserDefaults
) {
    switch tracePolicy {
    case .disabled:
        return
    case .metadataOnly:
        logBoardPreviewProviderCacheHitMetadata(
            phase: phase,
            item: item,
            targetPixelSize: targetPixelSize,
            cachedImage: cachedImage,
            tracePolicy: tracePolicy
        )
    case .verbose:
        logBoardThumbnailTraceImageRegions(
            phase: phase,
            mode: "provider-cache-hit",
            boardID: item.boardID,
            previewSeed: item.previewSeed,
            targetPixelSize: targetPixelSize,
            contentInset: 10,
            image: cachedImage
        )
    }

    logBoardPreviewProviderSourceImagesIfNeeded(
        phase: phase,
        item: item,
        tracePolicy: tracePolicy,
        mediaPosterImageResolver: mediaPosterImageResolver,
        userDefaults: userDefaults
    )
}
```

## 修改三：默认 cache-hit 日志降级为元数据输出，不再做图像签名采样

### 修改前

- 旧版 cache-hit 日志没有轻量分支。
- 一旦要记录 cache-hit 细节，就会直接把缓存图交给 `logBoardThumbnailTraceImageRegions(...)`，它内部会继续走图像采样和 region signature 计算。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名/符号名: logBoardPreviewProviderCacheHit(...)
// 功能说明: 修改前 cache-hit 的详细日志没有轻量元数据模式，默认就是图像采样路径。
private func logBoardPreviewProviderCacheHit(
    phase: String,
    item: BoardCatalogItem,
    targetPixelSize: CGSize,
    cachedImage: CGImage,
    mediaPosterImageResolver: BoardMediaPosterImageResolver,
    userDefaults: UserDefaults
) {
    logBoardThumbnailTraceImageRegions(
        phase: phase,
        mode: "provider-cache-hit",
        boardID: item.boardID,
        previewSeed: item.previewSeed,
        targetPixelSize: targetPixelSize,
        contentInset: 10,
        image: cachedImage
    )
    logBoardPreviewProviderSourceImagesIfNeeded(
        phase: phase,
        item: item,
        mediaPosterImageResolver: mediaPosterImageResolver,
        userDefaults: userDefaults
    )
}
```

### 修改后

- 新增 `logBoardPreviewProviderCacheHitMetadata(...)`。
- 在默认 `.metadataOnly` 下，现在只输出：
  - `phase`
  - `boardID`
  - `tracePolicy`
  - `targetPixelSize`
  - `cachedPixels`
  - `imageItemCount`
  - `textItemCount`
- 这样默认 trace 仍然保留“发生了 cache-hit”这一观测信息，但不再触发图像级采样成本。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名/符号名: logBoardPreviewProviderCacheHitMetadata(...)
// 功能说明: 修改后默认 metadataOnly 只输出轻量元数据级 cache-hit 诊断，不再对缓存图做签名采样。
private func logBoardPreviewProviderCacheHitMetadata(
    phase: String,
    item: BoardCatalogItem,
    targetPixelSize: CGSize,
    cachedImage: CGImage,
    tracePolicy: BoardPreviewTracePolicy
) {
    print(
        "[BoardList][ThumbnailTrace][CacheHit] " +
            "phase=\(phase) " +
            "boardID=\(item.boardID.uuidString) " +
            "tracePolicy=\(tracePolicy.rawValue) " +
            "targetPixelSize=\(describeBoardPreviewProviderSize(targetPixelSize)) " +
            "cachedPixels={\(cachedImage.width), \(cachedImage.height)} " +
            "imageItemCount=\(item.document.imageItemRecords.count) " +
            "textItemCount=\(item.document.textItemRecords.count)"
    )
}
```

## 修改四：把源图读取诊断限制为显式 `verbose` 模式

### 修改前

- `logBoardPreviewProviderSourceImagesIfNeeded(...)` 没有策略参数。
- 只要 cache-hit 诊断走到这里，就可能：
  - 进入 `SelectedFolderAccess.withBoardsDirectoryURL(...)`
  - 遍历 `imageItemRecords`
  - 通过 `mediaPosterImageResolver.resolvePreviewImage(...)` 实际读取源图或 poster frame
- 也就是说，trace 本身会放大 IO 与 decode 成本。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名/符号名: logBoardPreviewProviderSourceImagesIfNeeded(...)
// 功能说明: 修改前 source-image 诊断没有策略门控，会在 cache-hit 详细日志里读取源图做签名输出。
private func logBoardPreviewProviderSourceImagesIfNeeded(
    phase: String,
    item: BoardCatalogItem,
    mediaPosterImageResolver: BoardMediaPosterImageResolver,
    userDefaults: UserDefaults,
    maxImageCount: Int = 8,
    maxPixelSize: Int = 128
) {
    let imageItemRecords = item.document.imageItemRecords
    guard imageItemRecords.count <= maxImageCount else {
        print(
            "[BoardList][ThumbnailTrace][SourceImage] " +
                "phase=\(phase) " +
                "boardID=\(item.boardID.uuidString) " +
                "status=skipped " +
                "reason=image-count-exceeds-limit " +
                "imageCount=\(imageItemRecords.count)"
        )
        return
    }

    do {
        try SelectedFolderAccess.withBoardsDirectoryURL(
            userDefaults: userDefaults
        ) { _ in
            for imageItemRecord in imageItemRecords {
                let previewAssetFilename = mediaPosterImageResolver.previewAssetFilename(
                    for: imageItemRecord
                )
                let assetURL = item.assetsDirectoryURL.appendingPathComponent(
                    previewAssetFilename
                )
                do {
                    let image = try mediaPosterImageResolver.resolvePreviewImage(
                        for: imageItemRecord,
                        assetsDirectoryURL: item.assetsDirectoryURL,
                        animatedImagePreviewMode: BoardPreviewContent.animatedImagePreviewMode,
                        maxPixelSize: maxPixelSize
                    )

                    print(
                        "[BoardList][ThumbnailTrace][SourceImage] " +
                            "phase=\(phase) " +
                            "boardID=\(item.boardID.uuidString) " +
                            "itemID=\(imageItemRecord.id.uuidString) " +
                            "assetFilename=\(previewAssetFilename) " +
                            "assetURL=\(assetURL.path) " +
                            "signature=\(BoardThumbnailImageSignature.describe(image))"
                    )
                } catch {
                    // ... 省略错误日志 ...
                }
            }
        }
    } catch {
        // ... 省略 scope-failed 日志 ...
    }
}
```

### 修改后

- `logBoardPreviewProviderSourceImagesIfNeeded(...)` 新增 `tracePolicy` 参数。
- 开头先 `guard tracePolicy == .verbose else { return }`。
- 这样只有显式 verbose 模式才会真的进入源图读取诊断路径；默认 `.metadataOnly` 完全不会碰这段 IO / decode 逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名/符号名: logBoardPreviewProviderSourceImagesIfNeeded(...)
// 功能说明: 修改后 source-image 读取诊断只允许在 verbose 模式执行，默认 metadataOnly 不再触发额外源图读取与解码。
private func logBoardPreviewProviderSourceImagesIfNeeded(
    phase: String,
    item: BoardCatalogItem,
    tracePolicy: BoardPreviewTracePolicy,
    mediaPosterImageResolver: BoardMediaPosterImageResolver,
    userDefaults: UserDefaults,
    maxImageCount: Int = 8,
    maxPixelSize: Int = 128
) {
    guard tracePolicy == .verbose else {
        return
    }

    let imageItemRecords = item.document.imageItemRecords
    guard imageItemRecords.count <= maxImageCount else {
        print(
            "[BoardList][ThumbnailTrace][SourceImage] " +
                "phase=\(phase) " +
                "boardID=\(item.boardID.uuidString) " +
                "status=skipped " +
                "reason=image-count-exceeds-limit " +
                "imageCount=\(imageItemRecords.count)"
        )
        return
    }

    do {
        try SelectedFolderAccess.withBoardsDirectoryURL(
            userDefaults: userDefaults
        ) { _ in
            for imageItemRecord in imageItemRecords {
                let previewAssetFilename = mediaPosterImageResolver.previewAssetFilename(
                    for: imageItemRecord
                )
                let assetURL = item.assetsDirectoryURL.appendingPathComponent(
                    previewAssetFilename
                )
                do {
                    let image = try mediaPosterImageResolver.resolvePreviewImage(
                        for: imageItemRecord,
                        assetsDirectoryURL: item.assetsDirectoryURL,
                        animatedImagePreviewMode: BoardPreviewContent.animatedImagePreviewMode,
                        maxPixelSize: maxPixelSize
                    )

                    print(
                        "[BoardList][ThumbnailTrace][SourceImage] " +
                            "phase=\(phase) " +
                            "boardID=\(item.boardID.uuidString) " +
                            "itemID=\(imageItemRecord.id.uuidString) " +
                            "assetFilename=\(previewAssetFilename) " +
                            "assetURL=\(assetURL.path) " +
                            "signature=\(BoardThumbnailImageSignature.describe(image))"
                    )
                } catch {
                    // ... 省略错误日志 ...
                }
            }
        }
    } catch {
        // ... 省略 scope-failed 日志 ...
    }
}
```

## 本阶段结果

- `BoardPreviewProvider` 现在有了显式 `BoardPreviewTracePolicy`。
- 默认 trace 成本模型已降到 `.metadataOnly`：
  - 保留 cache-hit 元数据观测
  - 不再默认做 `ImageSnapshot` 图像采样
  - 不再默认读取源图 / poster frame
- 只有显式 `verbose` 模式才会恢复原本的重诊断路径。
- 这样 `Phase 4` 已经建立的 `geometryOnly` target-ready 快路径，在开启普通 trace 时不会再被 provider 内部的额外诊断 IO 放大。

## 仍留给后续阶段的工作

- 本阶段没有新增 closing trace 的回归验证日志，也没有补“误用 guardrail”。
- `Phase 6` 仍需要继续完成：
  - 重新测量 `backButtonTap -> carrierAnimateBegin`
  - 重新测量 `requestTargetGeometry -> targetGeometryResolved`
  - 重新测量 `revealPendingBoardEnqueued -> revealBoardBegin`
  - 对关键路径增加“不要重新引入全量 reload / 双 refresh / trace 读源图”的护栏日志

## 验证

- 已对 `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift` 执行 `ReadLints`。
- 当前结果：无 linter 报错。
- 本次未执行完整 iOS 构建；因此这里记录的是源码级与静态检查级确认结果。
