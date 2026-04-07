# 20260407_145925_boardlist_thumbnail_scoped_access_fix_record

## 记录范围

- 记录内容：针对 iOS `BoardList` 缩略图不显示的问题，整理这次排查中新增的日志分析、根因判断与共享层修复。
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift`
- 关联背景：问题首先在 iOS 侧暴露，但根因位于共享 `BoardPreviewProvider`，因此修复同时覆盖 iOS 与 macOS。
- 本记录包含：关键日志信号、问题原因、修改前后代码说明、验证结果。
- 本记录不包含：`.cursor/plans/*.md` 计划文件状态变化。
- 本记录不包含：git commit / push。

## 问题现象

- iOS `BoardList` 能正常列出 board 条目，但缩略图回退为几何预览，真实图片不显示。
- 用户提供的那批 `AutoLayout` 警告并不是根因，因为 `BoardList` 缩略图链路已经进入了真实渲染阶段。
- 问题不是单个 board 损坏，因为同一批 board 后续仍然可以被 `BoardStore.loadBoard` 正常打开。

## 日志分析

### 关键日志信号

- `FolderBookmark` 已经显示存在 bookmark 数据，说明“用户目录选择状态”本身仍在。
- `BoardList` 先进入 `geometry-fallback`，随后进入 `fresh-render`，说明 UI 层已经正常发起缩略图请求。
- fresh-render 过程中出现 `NSCocoaErrorDomain Code=260`，说明真正失败点落在后台素材读取，而不是 cell 绑定或主线程回调。
- 同一份 board 后面又能被 `BoardStore.loadBoard` 成功读取，说明“文件整体不存在”并不是更合理的解释。

```text
# 来源: 用户提供的 iOS 运行日志与排查期间提炼出的关键日志信号
[FolderBookmark] UserDefaults has bookmark data: true
[BoardList][ThumbnailTrace][Provider] phase=immediatePreview ... source=geometry-fallback
[BoardList][ThumbnailTrace][Provider] phase=loadBestAvailableThumbnail ... source=fresh-render
NSCocoaErrorDomain Code=260 "The file couldn’t be opened because it doesn’t exist."
BoardStore.loadBoard ... success
```

### 日志结论

- `BoardList` 不是“没触发缩略图渲染”，而是“已经触发了渲染，但后台读文件失败”。
- `Code=260` 在这里更符合 security-scoped access 生命周期失效后的读盘失败表现，而不是素材真的被统一删除。
- 根因不在 iOS 专属 UI，而在共享预览提供器对磁盘读取边界的管理方式。

## 问题原因

- `SelectedFolderAccess.withBoardsDirectoryURL(...)` 会在闭包期间显式开启并在结束时关闭 `security-scoped resource` 访问。
- `BoardStore.loadBoard` 的文件 I/O 发生在这个闭包内部，所以它仍能正常读取 board 与 assets。
- 但 `BoardPreviewProvider` 在修改前直接拿 `BoardCatalogItem` 上的 `persistedThumbnailURL` / `assetsDirectoryURL` 去做 persisted thumbnail 读取、fresh render、以及 cache-hit 诊断图片读取。
- 这些读取动作中，尤其是 `requestThumbnail` 的后台 `OperationQueue` 渲染任务，执行时已经不处于最初 catalog 构建阶段的 access scope 内。
- 于是共享预览链路在读取 `thumbnail.png`、静态图片、GIF poster frame、视频 poster 图时，会在后台统一触发 `Code=260`。

```swift
// 文件路径: MyCanvas_Ver_0/App/SelectedFolderAccess.swift
// 类型/函数: withBoardsDirectoryURL(userDefaults:_:)
// 功能说明: 共享层真正有效的文件访问边界来自这里；只有在闭包执行期间，选中文件夹的 security-scoped access 才处于开启状态。
static func withBoardsDirectoryURL<T>(
    userDefaults: UserDefaults = .standard,
    _ body: (URL) throws -> T
) throws -> T {
    try withWorkspaceURL(userDefaults: userDefaults) { workspaceURL in
        let boardsDirectoryURL = workspaceURL.appendingPathComponent(
            boardsDirectoryName,
            isDirectory: true
        )
        return try body(boardsDirectoryURL)
    }
}
```

## 修改一：给 `BoardPreviewProvider` 增加统一的 scoped 文件访问入口

### 修改前

- `BoardPreviewProvider` 没有保存 `UserDefaults`。
- `immediatePreview` 直接读取 persisted thumbnail。
- 读取发生时没有重新进入 `SelectedFolderAccess.withBoardsDirectoryURL(...)`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 类型/函数: init(...) / immediatePreview(for:targetPixelSize:)
// 功能说明: 修改前 provider 只有 cache、renderer、resolver 和队列；immediatePreview 直接读取 persisted thumbnail，没有统一的 scoped access 包装。
final class BoardPreviewProvider {
    private let thumbnailCache: BoardThumbnailCache
    private let thumbnailRenderer: BoardThumbnailRenderer
    private let mediaPosterImageResolver: BoardMediaPosterImageResolver
    private let renderQueue: OperationQueue
    private let callbackQueue: DispatchQueue

    init(
        thumbnailCache: BoardThumbnailCache = BoardThumbnailCache(),
        thumbnailRenderer: BoardThumbnailRenderer = BoardThumbnailRenderer(),
        mediaPosterImageResolver: BoardMediaPosterImageResolver = BoardMediaPosterImageResolver(),
        callbackQueue: DispatchQueue = .main
    ) {
        self.thumbnailCache = thumbnailCache
        self.thumbnailRenderer = thumbnailRenderer
        self.mediaPosterImageResolver = mediaPosterImageResolver
        self.callbackQueue = callbackQueue
    }

    func immediatePreview(
        for item: BoardCatalogItem,
        targetPixelSize: CGSize? = nil
    ) -> BoardPreviewContent {
        // ... 前置 cacheKey 判断省略 ...
        do {
            if let persistedThumbnail = try loadPersistedThumbnailPreview(
                for: item,
                cacheKey: cacheKey
            ) {
                thumbnailCache.insert(persistedThumbnail, for: cacheKey)
                return .thumbnail(persistedThumbnail, item.previewSeed)
            }
        } catch {
            print(
                "[BoardPreviewProvider] Failed to load persisted thumbnail " +
                "boardID=\(item.boardID.uuidString) " +
                "revision=\(item.revisionToken) " +
                "error=\(error)"
            )
        }

        return .geometry(item.previewSeed)
    }
}
```

### 修改后

- `BoardPreviewProvider` 新增 `userDefaults` 依赖，用于在共享层内部主动重建访问边界。
- 新增 `withScopedPreviewFileAccess(for:_:)`，把预览链路里的文件读取统一收口到一个 helper 中。
- `immediatePreview` 现在在 scoped access 内读取 persisted thumbnail，不再直接在闭包外碰磁盘。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 类型/函数: init(...) / immediatePreview(for:targetPixelSize:) / withScopedPreviewFileAccess(for:_:)
// 功能说明: 修改后 provider 通过统一 helper 在有效的 boards access scope 内完成 persisted thumbnail 读取。
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
    }

    func immediatePreview(
        for item: BoardCatalogItem,
        targetPixelSize: CGSize? = nil
    ) -> BoardPreviewContent {
        // ... 前置 cacheKey 判断省略 ...
        do {
            let persistedThumbnail = try withScopedPreviewFileAccess(
                for: item
            ) {
                try loadPersistedThumbnailPreview(
                    for: item,
                    cacheKey: cacheKey
                )
            }
            if let persistedThumbnail {
                thumbnailCache.insert(persistedThumbnail, for: cacheKey)
                return .thumbnail(persistedThumbnail, item.previewSeed)
            }
        } catch {
            print(
                "[BoardPreviewProvider] Failed to load persisted thumbnail " +
                "boardID=\(item.boardID.uuidString) " +
                "revision=\(item.revisionToken) " +
                "persistedThumbnailURL=\(item.persistedThumbnailURL.path) " +
                "assetsDirectoryURL=\(item.assetsDirectoryURL.path) " +
                "error=\(error)"
            )
        }

        return .geometry(item.previewSeed)
    }

    private func withScopedPreviewFileAccess<T>(
        for item: BoardCatalogItem,
        _ body: () throws -> T
    ) throws -> T {
        try SelectedFolderAccess.withBoardsDirectoryURL(
            userDefaults: userDefaults
        ) { _ in
            try body()
        }
    }
}
```

## 修改二：把异步 `requestThumbnail` 的 persisted / fresh render 都放回同一个 access boundary

### 修改前

- `requestThumbnail` 的后台 `OperationQueue` 任务直接执行 `loadBestAvailableThumbnail(...)`。
- `loadBestAvailableThumbnail(...)` 又会继续读取 persisted thumbnail 或进入 fresh render。
- 这条异步链路没有重新建立 `SelectedFolderAccess`，最容易在后台读盘时触发 `Code=260`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 类型/函数: requestThumbnail(for:targetPixelSize:completion:)
// 功能说明: 修改前后台渲染任务直接调用 loadBestAvailableThumbnail，异步读文件时不在 scoped access 内。
operation.addExecutionBlock { [weak operation] in
    guard
        let operation,
        operation.isCancelled == false,
        requestToken.isCancelled == false
    else {
        return
    }

    do {
        let cancellationCheck: () throws -> Void = {
            if operation.isCancelled || requestToken.isCancelled {
                throw BoardThumbnailRendererError.cancelled
            }
        }

        guard let renderedImage = try self.loadBestAvailableThumbnail(
            for: item,
            cacheKey: cacheKey,
            cancellationCheck: cancellationCheck
        ) else {
            logBoardPreviewProviderDecision(
                phase: "requestThumbnail",
                boardID: item.boardID,
                revisionToken: item.revisionToken,
                targetPixelSize: cacheKey.pixelSize,
                source: "render-miss",
                reason: "load-best-available-returned-nil"
            )
            return
        }

        self.thumbnailCache.insert(renderedImage, for: cacheKey)
        self.callbackQueue.async { [weak requestToken] in
            guard let requestToken, requestToken.isCancelled == false else {
                return
            }
            completion(.thumbnail(renderedImage, item.previewSeed))
        }
    } catch {
        print(
            "[BoardPreviewProvider] Failed to render thumbnail " +
            "boardID=\(item.boardID.uuidString) " +
            "revision=\(item.revisionToken) " +
            "error=\(error)"
        )
    }
}
```

### 修改后

- `requestThumbnail` 的后台渲染入口先经过 `withScopedPreviewFileAccess(for:_:)`。
- persisted replay 与 fresh render 现在共享同一个有效的 access lifecycle。
- 失败日志补上 `persistedThumbnailURL` 与 `assetsDirectoryURL`，便于继续追踪残留问题。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 类型/函数: requestThumbnail(for:targetPixelSize:completion:)
// 功能说明: 修改后后台渲染任务在统一的 scoped access 内执行 persisted/fresh 两条真实读盘路径。
operation.addExecutionBlock { [weak operation] in
    guard
        let operation,
        operation.isCancelled == false,
        requestToken.isCancelled == false
    else {
        return
    }

    do {
        let cancellationCheck: () throws -> Void = {
            if operation.isCancelled || requestToken.isCancelled {
                throw BoardThumbnailRendererError.cancelled
            }
        }

        let renderedImage = try self.withScopedPreviewFileAccess(
            for: item
        ) {
            try self.loadBestAvailableThumbnail(
                for: item,
                cacheKey: cacheKey,
                cancellationCheck: cancellationCheck
            )
        }
        guard let renderedImage else {
            logBoardPreviewProviderDecision(
                phase: "requestThumbnail",
                boardID: item.boardID,
                revisionToken: item.revisionToken,
                targetPixelSize: cacheKey.pixelSize,
                source: "render-miss",
                reason: "load-best-available-returned-nil"
            )
            return
        }

        self.thumbnailCache.insert(renderedImage, for: cacheKey)
        self.callbackQueue.async { [weak requestToken] in
            guard let requestToken, requestToken.isCancelled == false else {
                return
            }
            completion(.thumbnail(renderedImage, item.previewSeed))
        }
    } catch {
        print(
            "[BoardPreviewProvider] Failed to render thumbnail " +
            "boardID=\(item.boardID.uuidString) " +
            "revision=\(item.revisionToken) " +
            "persistedThumbnailURL=\(item.persistedThumbnailURL.path) " +
            "assetsDirectoryURL=\(item.assetsDirectoryURL.path) " +
            "error=\(error)"
        )
    }
}
```

## 修改三：把 cache-hit 诊断图片读取也纳入 scoped access，并补精确路径日志

### 修改前

- `logBoardPreviewProviderCacheHit(...)` 只把 `mediaPosterImageResolver` 传给 `logBoardPreviewProviderSourceImagesIfNeeded(...)`。
- `logBoardPreviewProviderSourceImagesIfNeeded(...)` 在闭包外直接读取素材图片。
- 日志只打印 `assetFilename`，没有打印 `assetURL`，定位具体读盘路径仍然不够直接。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 类型/函数: logBoardPreviewProviderCacheHit(...) / logBoardPreviewProviderSourceImagesIfNeeded(...)
// 功能说明: 修改前 cache-hit 诊断图片读取没有重新进入 scoped access，也没有输出 assetURL。
private func logBoardPreviewProviderCacheHit(
    phase: String,
    item: BoardCatalogItem,
    targetPixelSize: CGSize,
    cachedImage: CGImage,
    mediaPosterImageResolver: BoardMediaPosterImageResolver
) {
    logBoardPreviewProviderSourceImagesIfNeeded(
        phase: phase,
        item: item,
        mediaPosterImageResolver: mediaPosterImageResolver
    )
}

private func logBoardPreviewProviderSourceImagesIfNeeded(
    phase: String,
    item: BoardCatalogItem,
    mediaPosterImageResolver: BoardMediaPosterImageResolver,
    maxImageCount: Int = 8,
    maxPixelSize: Int = 128
) {
    for imageItemRecord in item.document.imageItemRecords {
        let previewAssetFilename = mediaPosterImageResolver.previewAssetFilename(
            for: imageItemRecord
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
                    "signature=\(BoardThumbnailImageSignature.describe(image))"
            )
        } catch {
            print(
                "[BoardList][ThumbnailTrace][SourceImage] " +
                    "phase=\(phase) " +
                    "boardID=\(item.boardID.uuidString) " +
                    "itemID=\(imageItemRecord.id.uuidString) " +
                    "assetFilename=\(previewAssetFilename) " +
                    "status=read-failed " +
                    "error=\(error)"
            )
        }
    }
}
```

### 修改后

- `logBoardPreviewProviderCacheHit(...)` 新增 `userDefaults` 参数，把诊断读取也纳入统一 access 策略。
- `logBoardPreviewProviderSourceImagesIfNeeded(...)` 在 `SelectedFolderAccess.withBoardsDirectoryURL(...)` 内读取素材。
- 成功与失败日志都增加 `assetURL`，并补一个 `scope-failed` 分支，后续可以直接区分“权限边界失败”和“具体素材失败”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 类型/函数: logBoardPreviewProviderCacheHit(...) / logBoardPreviewProviderSourceImagesIfNeeded(...)
// 功能说明: 修改后 cache-hit 诊断读图与真实预览读图一样，统一受 boards scoped access 保护，并输出 assetURL。
private func logBoardPreviewProviderCacheHit(
    phase: String,
    item: BoardCatalogItem,
    targetPixelSize: CGSize,
    cachedImage: CGImage,
    mediaPosterImageResolver: BoardMediaPosterImageResolver,
    userDefaults: UserDefaults
) {
    logBoardPreviewProviderSourceImagesIfNeeded(
        phase: phase,
        item: item,
        mediaPosterImageResolver: mediaPosterImageResolver,
        userDefaults: userDefaults
    )
}

private func logBoardPreviewProviderSourceImagesIfNeeded(
    phase: String,
    item: BoardCatalogItem,
    mediaPosterImageResolver: BoardMediaPosterImageResolver,
    userDefaults: UserDefaults,
    maxImageCount: Int = 8,
    maxPixelSize: Int = 128
) {
    do {
        try SelectedFolderAccess.withBoardsDirectoryURL(
            userDefaults: userDefaults
        ) { _ in
            for imageItemRecord in item.document.imageItemRecords {
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
                    print(
                        "[BoardList][ThumbnailTrace][SourceImage] " +
                            "phase=\(phase) " +
                            "boardID=\(item.boardID.uuidString) " +
                            "itemID=\(imageItemRecord.id.uuidString) " +
                            "assetFilename=\(previewAssetFilename) " +
                            "assetURL=\(assetURL.path) " +
                            "status=read-failed " +
                            "error=\(error)"
                    )
                }
            }
        }
    } catch {
        print(
            "[BoardList][ThumbnailTrace][SourceImage] " +
                "phase=\(phase) " +
                "boardID=\(item.boardID.uuidString) " +
                "assetsDirectoryURL=\(item.assetsDirectoryURL.path) " +
                "status=scope-failed " +
                "error=\(error)"
        )
    }
}
```

## 实施结果

- 这次修复最终只改动了一个共享文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift`。
- 没有在 iOS `BoardList` cell、controller 或平台专属 UI 上打补丁。
- 方案收口在共享预览提供器，符合“从根因修复，而不是最小补丁”的原则。
- 预估中曾考虑过进一步收紧 `BoardCatalogItem` 对裸 URL 的依赖，但本次实际实施后，共享 provider 收口已经足以恢复 iOS 缩略图显示，因此没有额外扩散改动面。

## 验证结果

- 构建验证通过：`xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" build`
- 构建验证通过：`xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS" build`
- 用户已确认：iOS 上的 `BoardList` 缩略图问题已经修复。

## 结论

- 这次问题的根因不是 `BoardList` UI，也不是 `AutoLayout` 警告，而是共享缩略图读取链路缺少稳定的 `security-scoped access` 生命周期。
- 修复后的 `BoardPreviewProvider` 把 persisted thumbnail、fresh render、cache-hit 诊断图片读取统一放回 `SelectedFolderAccess.withBoardsDirectoryURL(...)` 边界内执行，消除了后台读盘阶段的 `Code=260` 失败点。
