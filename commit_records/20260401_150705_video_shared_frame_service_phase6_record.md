# 20260401_150705_video_shared_frame_service_phase6_record

## 记录范围

- 记录内容：新增共享 `AVFoundation` 视频帧服务，统一处理视频编辑页所需的抽帧、帧条缩略图和 poster 落盘。
- 记录内容：把视频导入阶段的首帧 poster 生成改成复用共享服务，不再在导入类型里直接操作 `AVAssetImageGenerator`。
- 记录内容：把视频 poster 更新链路从“只接收 `CGImage` 并回写 transient asset”改成“先持久化 poster 文件，再把 persisted asset 回写到运行时 item”。
- 记录内容：给 `CanvasEditorSession` 增加阶段 7 / 8 直接可复用的视频编辑上下文、抽帧、帧条和 commit 接口。
- 记录内容：让 iOS / macOS 视频编辑页壳子接入统一 `CanvasVideoEditorContext`，并在打开失败时给出平台原生错误提示。
- 涉及文件：`MyCanvas_Ver_0/Canvas/Video/CanvasVideoFrameService.swift`
- 涉及文件：`MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift`
- 涉及文件：`MyCanvas_Ver_0/Canvas/Import/CanvasMediaImportService.swift`
- 涉及文件：`MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift`
- 涉及文件：`MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift`
- 涉及文件：`MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift`
- 本记录不包含：阶段 7 的 iOS 完整播放区、滑杆、帧条和提交按钮布局。
- 本记录不包含：阶段 8 的 macOS 完整视频编辑 sheet UI。
- 本记录不包含：git commit / push。

## 修改一：新增共享视频帧服务，统一抽帧、帧条与 poster 落盘

### 修改前

- shared 层还没有独立的视频服务文件。
- 导入、编辑、平台页如果都要做视频抽帧，只能各自直接使用 `AVFoundation`，无法形成统一规则。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Video/CanvasVideoFrameService.swift
// 类型/函数: 文件级新增前
// 功能说明: 修改前无此文件，shared Canvas 层没有统一的视频抽帧、帧条和 poster 持久化服务。
// 无
```

### 修改后

- 新增 `CanvasVideoFrameService`。
- 统一暴露：
  - `editorContext(...)`：解析 board assets 里的本地视频、当前 poster 和时长信息
  - `frameImage(...)`：按时间点抽取高质量或低成本帧
  - `previewStrip(...)`：批量生成底部帧条
  - `persistPosterAsset(...)`：把最终 poster 统一写回 `board assets`
- poster 文件名统一成 `video-poster-...png`，为后续替换 / 清理提供稳定语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Video/CanvasVideoFrameService.swift
// 类型/函数: CanvasVideoFrameService.editorContext(...) / frameImage(...) / previewStrip(...) / persistPosterAsset(...)
// 功能说明: 修改后 shared 层统一承接视频编辑页所需的上下文解析、按时间点抽帧、帧条生成和最终 poster 落盘。
enum CanvasVideoFrameRenderQuality {
    case posterCommit
    case previewStripThumbnail(maxPixelSize: Int)
}

struct CanvasVideoEditorContext {
    let boardID: UUID
    let itemID: CanvasItemID
    let sourceVideoURL: URL
    let sourceVideoFilename: String
    let currentPosterFilename: String
    let currentPosterTimeSeconds: Double
    let durationSeconds: Double
    let naturalPixelSize: CGSize
}

enum CanvasVideoFrameService {
    static func editorContext(
        for item: CanvasImageItem,
        boardID: UUID,
        userDefaults: UserDefaults = .standard
    ) throws -> CanvasVideoEditorContext {
        guard let sourceVideoFilename = item.sourceVideoFilename else {
            throw CanvasVideoFrameServiceError.missingSourceVideoFilename(
                itemID: item.id
            )
        }

        let assetsDirectoryURL = try BoardStore.ensureAssetsDirectoryURL(
            for: boardID,
            userDefaults: userDefaults
        )
        let sourceVideoURL = assetsDirectoryURL.appendingPathComponent(
            sourceVideoFilename
        )
        let asset = AVURLAsset(url: sourceVideoURL)
        return CanvasVideoEditorContext(
            boardID: boardID,
            itemID: item.id,
            sourceVideoURL: sourceVideoURL,
            sourceVideoFilename: sourceVideoFilename,
            currentPosterFilename: item.assetReference.stableAssetFilename,
            currentPosterTimeSeconds: item.posterTimeSeconds ?? 0,
            durationSeconds: sanitizedDurationSeconds(asset.duration),
            naturalPixelSize: naturalVideoPixelSize(for: asset) ?? item.logicalPixelSize
        )
    }

    static func frameImage(
        from localFileURL: URL,
        at timeSeconds: Double,
        quality: CanvasVideoFrameRenderQuality
    ) throws -> CanvasVideoFrameImage {
        let asset = AVURLAsset(url: localFileURL)
        let imageGenerator = makeImageGenerator(
            for: asset,
            quality: quality
        )
        return try makeFrameImage(
            from: asset,
            filename: localFileURL.lastPathComponent,
            at: timeSeconds,
            imageGenerator: imageGenerator
        )
    }

    static func previewStrip(
        from localFileURL: URL,
        frameCount: Int,
        maxPixelSize: Int
    ) throws -> CanvasVideoPreviewStrip {
        let asset = AVURLAsset(url: localFileURL)
        let sampleTimes = previewSampleTimes(
            durationSeconds: sanitizedDurationSeconds(asset.duration),
            frameCount: max(frameCount, 1)
        )
        let imageGenerator = makeImageGenerator(
            for: asset,
            quality: .previewStripThumbnail(maxPixelSize: maxPixelSize)
        )
        let frames = try sampleTimes.map { sampleTime in
            let frameImage = try makeFrameImage(
                from: asset,
                filename: localFileURL.lastPathComponent,
                at: sampleTime,
                imageGenerator: imageGenerator
            )
            return CanvasVideoPreviewStripFrame(
                cgImage: frameImage.cgImage,
                timeSeconds: frameImage.actualTimeSeconds
            )
        }
        return CanvasVideoPreviewStrip(
            durationSeconds: sanitizedDurationSeconds(asset.duration),
            frames: frames
        )
    }

    static func persistPosterAsset(
        cgImage: CGImage,
        logicalPixelSize: CGSize,
        posterTimeSeconds: Double,
        itemID: CanvasItemID? = nil,
        to assetsDirectoryURL: URL
    ) throws -> CanvasPersistedVideoPoster {
        let posterFilename = makePosterFilename(for: itemID)
        let posterAssetURL = assetsDirectoryURL.appendingPathComponent(
            posterFilename
        )
        try CoordinatedFileIO.writeData(
            makePNGData(for: cgImage, filename: posterFilename),
            to: posterAssetURL
        )
        return CanvasPersistedVideoPoster(
            asset: CanvasImageAsset.persistedStaticImage(
                filename: posterFilename,
                cgImage: cgImage,
                logicalPixelSize: logicalPixelSize
            ),
            assetURL: posterAssetURL,
            posterTimeSeconds: sanitizedTimeSeconds(posterTimeSeconds)
        )
    }
}
```

## 修改二：视频导入类型不再自己直连 `AVFoundation`，而是复用共享抽帧服务

### 修改前

- `CanvasResolvedImportVideo` 自己在 `CanvasImportTypes.swift` 里直接 new `AVURLAsset` / `AVAssetImageGenerator`。
- 抽帧时间、实际返回时间和尺寸信息都停留在这个导入类型内部，后续阶段 7 / 8 无法直接复用这套逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 类型/函数: CanvasResolvedImportVideo.init(...) / posterCGImage(from:at:) / sanitizedPosterTimeSeconds(_:)
// 功能说明: 修改前导入视频时的首帧 poster 生成直接写在导入类型里，shared 层没有统一抽帧入口。
struct CanvasResolvedImportVideo {
    let source: CanvasImportedVideoSource
    let posterCGImage: CGImage
    let posterTimeSeconds: Double
    let logicalPixelSize: CGSize

    init?(
        localFileURL: URL,
        typeIdentifier: String? = nil,
        filenameHint: String? = nil,
        shouldDeleteAfterImport: Bool = false,
        posterTimeSeconds: Double = 0
    ) {
        let sanitizedPosterTimeSeconds = Self.sanitizedPosterTimeSeconds(
            posterTimeSeconds
        )
        guard let posterCGImage = Self.posterCGImage(
            from: localFileURL,
            at: sanitizedPosterTimeSeconds
        ) else {
            return nil
        }

        self.source = CanvasImportedVideoSource(
            localFileURL: localFileURL,
            typeIdentifier: typeIdentifier,
            filenameHint: filenameHint,
            shouldDeleteAfterImport: shouldDeleteAfterImport
        )
        self.posterCGImage = posterCGImage
        self.posterTimeSeconds = sanitizedPosterTimeSeconds
        self.logicalPixelSize = CGSize(
            width: posterCGImage.width,
            height: posterCGImage.height
        )
    }

    private static func posterCGImage(
        from localFileURL: URL,
        at posterTimeSeconds: Double
    ) -> CGImage? {
        let asset = AVURLAsset(url: localFileURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        let requestedTime = CMTime(
            seconds: posterTimeSeconds,
            preferredTimescale: 600
        )
        return try? imageGenerator.copyCGImage(
            at: requestedTime,
            actualTime: nil
        )
    }
}
```

### 修改后

- `CanvasResolvedImportVideo` 直接调用 `CanvasVideoFrameService.frameImage(...)`。
- `posterTimeSeconds` 不再盲目沿用请求时间，而是使用共享服务返回的 `actualTimeSeconds`。
- `logicalPixelSize` 也跟着共享服务统一走视频真实尺寸推导。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 类型/函数: CanvasResolvedImportVideo.init(...)
// 功能说明: 修改后导入阶段的首帧 poster 生成复用共享视频帧服务，并把实际命中的时间点与尺寸一并带出。
struct CanvasResolvedImportVideo {
    let source: CanvasImportedVideoSource
    let posterCGImage: CGImage
    let posterTimeSeconds: Double
    let logicalPixelSize: CGSize

    init?(
        localFileURL: URL,
        typeIdentifier: String? = nil,
        filenameHint: String? = nil,
        shouldDeleteAfterImport: Bool = false,
        posterTimeSeconds: Double = 0
    ) {
        guard let posterFrame = try? CanvasVideoFrameService.frameImage(
            from: localFileURL,
            at: posterTimeSeconds,
            quality: .posterCommit
        ) else {
            return nil
        }

        self.source = CanvasImportedVideoSource(
            localFileURL: localFileURL,
            typeIdentifier: typeIdentifier,
            filenameHint: filenameHint,
            shouldDeleteAfterImport: shouldDeleteAfterImport
        )
        self.posterCGImage = posterFrame.cgImage
        self.posterTimeSeconds = posterFrame.actualTimeSeconds
        self.logicalPixelSize = posterFrame.logicalPixelSize
    }
}
```

## 修改三：导入写盘统一走共享 poster 持久化服务，并补齐局部回滚

### 修改前

- `CanvasMediaImportService.importVideo(...)` 自己生成 `posterImageFilename`、自己把 `CGImage` 编码成 PNG。
- 这会形成第二套 poster 落盘逻辑。
- 如果视频文件已经 copy 成功，但后续 poster 写盘失败，`importVideo(...)` 自身没有立即回滚已复制的 `sourceVideoAssetURL`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasMediaImportService.swift
// 类型/函数: CanvasMediaImportService.importVideo(...) / makePosterFilename() / makePNGData(for:)
// 功能说明: 修改前导入服务自己负责编码和写入 poster 文件，且 importVideo 内部没有独立的局部回滚收口。
private static func importVideo(
    _ video: CanvasResolvedImportVideo,
    into assetsDirectoryURL: URL
) throws -> ImportedVideoResult {
    let sourceVideoFilename = makeUniqueVideoFilename(for: video.source)
    let posterImageFilename = makePosterFilename()
    let sourceVideoAssetURL = assetsDirectoryURL.appendingPathComponent(
        sourceVideoFilename
    )
    let posterImageAssetURL = assetsDirectoryURL.appendingPathComponent(
        posterImageFilename
    )

    try CoordinatedFileIO.copyItem(
        at: video.source.localFileURL,
        to: sourceVideoAssetURL
    )
    try CoordinatedFileIO.writeData(
        makePNGData(for: video.posterCGImage),
        to: posterImageAssetURL
    )

    let posterAsset = CanvasImageAsset.persistedStaticImage(
        filename: posterImageFilename,
        cgImage: video.posterCGImage,
        logicalPixelSize: video.logicalPixelSize
    )
    let videoSource = CanvasVideoSource(
        assetReference: .persisted(filename: sourceVideoFilename)
    )
    return ImportedVideoResult(
        item: CanvasImportedVideoAsset(
            asset: posterAsset,
            videoSource: videoSource,
            posterTimeSeconds: video.posterTimeSeconds
        ),
        createdAssetURLs: [
            sourceVideoAssetURL,
            posterImageAssetURL
        ]
    )
}
```

### 修改后

- `importVideo(...)` 改成复用 `CanvasVideoFrameService.persistPosterAsset(...)`。
- 导入和编辑页之后都会走同一套 poster 落盘语义。
- `importVideo(...)` 自己维护 `createdAssetURLs`，失败时会优先清理本次已创建的文件，再把错误向上抛出。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasMediaImportService.swift
// 类型/函数: CanvasMediaImportService.importVideo(...)
// 功能说明: 修改后视频导入与后续编辑页共用同一套 poster 持久化逻辑，并在局部失败时立即回滚已创建的资产。
private static func importVideo(
    _ video: CanvasResolvedImportVideo,
    into assetsDirectoryURL: URL
) throws -> ImportedVideoResult {
    let sourceVideoFilename = makeUniqueVideoFilename(for: video.source)
    let sourceVideoAssetURL = assetsDirectoryURL.appendingPathComponent(
        sourceVideoFilename
    )

    var createdAssetURLs: [URL] = []
    do {
        try CoordinatedFileIO.copyItem(
            at: video.source.localFileURL,
            to: sourceVideoAssetURL
        )
        createdAssetURLs.append(sourceVideoAssetURL)
        let persistedPoster = try CanvasVideoFrameService.persistPosterAsset(
            cgImage: video.posterCGImage,
            logicalPixelSize: video.logicalPixelSize,
            posterTimeSeconds: video.posterTimeSeconds,
            to: assetsDirectoryURL
        )
        createdAssetURLs.append(persistedPoster.assetURL)
        let videoSource = CanvasVideoSource(
            assetReference: .persisted(filename: sourceVideoFilename)
        )
        return ImportedVideoResult(
            item: CanvasImportedVideoAsset(
                asset: persistedPoster.asset,
                videoSource: videoSource,
                posterTimeSeconds: persistedPoster.posterTimeSeconds
            ),
            createdAssetURLs: createdAssetURLs
        )
    } catch {
        cleanupImportedAssetURLs(createdAssetURLs)
        throw error
    }
}
```

## 修改四：视频 poster 更新链路从 `CGImage -> transient asset` 改成 `persisted asset -> item`

### 修改前

- `CanvasImageItem.updatingVideoPoster(...)` 只接收 `CGImage` 和可选尺寸。
- 它会无条件把视频 item 的素材重建成 `CanvasImageAsset.transientStaticImage(...)`。
- `CanvasScene` / `CanvasEditorSession` 也都沿用这个签名，所以阶段 7 / 8 即使生成了最终 poster 文件，也没有地方把“persisted poster asset”直接回写到运行时。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 类型/函数: CanvasImageItem.updatingVideoPoster(...)
// 功能说明: 修改前视频 poster 更新只接受 CGImage，并把结果写成 transientStaticImage，无法直接承接已落盘的 poster 资产。
func updatingVideoPoster(
    posterCGImage: CGImage,
    logicalPixelSize: CGSize? = nil,
    posterTimeSeconds: Double,
    assetID: UUID = UUID()
) -> CanvasImageItem? {
    guard isVideo else {
        return nil
    }

    var updatedItem = self
    updatedItem.asset = CanvasImageAsset.transientStaticImage(
        cgImage: posterCGImage,
        logicalPixelSize: logicalPixelSize ?? asset.logicalPixelSize,
        assetID: assetID
    )
    updatedItem.posterTimeSeconds = Self.sanitizedPosterTimeSeconds(
        posterTimeSeconds,
        isVideo: true
    )
    return updatedItem
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 类型/函数: CanvasEditorSession.updateVideoPoster(withID:posterCGImage:logicalPixelSize:posterTimeSeconds:)
// 功能说明: 修改前 Session 只把 CGImage 往 Scene 里传，缺少“先持久化 poster 文件，再写回 persisted asset”的正式 commit 入口。
@discardableResult
func updateVideoPoster(
    withID itemID: CanvasItemID,
    posterCGImage: CGImage,
    logicalPixelSize: CGSize? = nil,
    posterTimeSeconds: Double
) -> CanvasVideoPosterUpdateResult? {
    guard canUpdateVideoPoster(withID: itemID) else {
        return nil
    }

    let beforeSnapshot = currentBoardHistorySnapshot()
    guard let updatedItem = scene.updateVideoPoster(
        withID: itemID,
        posterCGImage: posterCGImage,
        logicalPixelSize: logicalPixelSize,
        posterTimeSeconds: posterTimeSeconds
    ) else {
        return nil
    }

    let changeReason = "update video poster"
    _ = recordImmediateHistoryChange(
        from: beforeSnapshot,
        reason: changeReason,
        autosaveReason: changeReason
    )
    return CanvasVideoPosterUpdateResult(
        item: updatedItem,
        refreshReason: changeReason
    )
}
```

### 修改后

- `CanvasImageItem` / `CanvasScene` / `CanvasEditorSession` 的更新签名统一改为接收 `posterAsset: CanvasImageAsset`。
- `CanvasEditorSession` 新增 `commitVideoPosterFrame(...)`：
  1. 先用共享服务把最终帧写成 persisted poster 文件
  2. 再把 `persistedPoster.asset` 回写进 scene
  3. 最后沿用现有 history + autosave 流程
- 这样阶段 7 / 8 提交 poster 时，不会再绕回临时资产语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 类型/函数: CanvasImageItem.updatingVideoPoster(...)
// 功能说明: 修改后 item 级更新直接接收已落盘或已构造好的 CanvasImageAsset，使视频 poster 的运行时状态和持久化状态对齐。
func updatingVideoPoster(
    posterAsset: CanvasImageAsset,
    posterTimeSeconds: Double
) -> CanvasImageItem? {
    guard isVideo else {
        return nil
    }

    var updatedItem = self
    updatedItem.asset = posterAsset
    updatedItem.posterTimeSeconds = Self.sanitizedPosterTimeSeconds(
        posterTimeSeconds,
        isVideo: true
    )
    return updatedItem
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 类型/函数: CanvasScene.updateVideoPoster(withID:posterAsset:posterTimeSeconds:)
// 功能说明: 修改后 Scene 作为共享 mutation 入口，接收完整 poster asset，而不是只接收一张临时 CGImage。
@discardableResult
func updateVideoPoster(
    withID id: CanvasImageItemID,
    posterAsset: CanvasImageAsset,
    posterTimeSeconds: Double
) -> CanvasImageItem? {
    var updatedItem: CanvasImageItem?
    updateImageItem(withID: id) { item in
        guard let nextItem = item.updatingVideoPoster(
            posterAsset: posterAsset,
            posterTimeSeconds: posterTimeSeconds
        ) else {
            return
        }

        item = nextItem
        updatedItem = nextItem
    }
    return updatedItem
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 类型/函数: CanvasEditorSession.commitVideoPosterFrame(...) / updateVideoPoster(withID:posterAsset:posterTimeSeconds:)
// 功能说明: 修改后 Session 先持久化最终 poster，再把 persisted asset 回写到 scene，保证历史、自动保存和文件清理都围绕真实 poster 资产工作。
@discardableResult
func commitVideoPosterFrame(
    withID itemID: CanvasItemID,
    frameImage: CanvasVideoFrameImage
) throws -> CanvasVideoPosterUpdateResult {
    let editorContext = try videoEditorContext(for: itemID)
    let persistedPoster = try CanvasVideoFrameService.persistPosterAsset(
        cgImage: frameImage.cgImage,
        logicalPixelSize: frameImage.logicalPixelSize,
        posterTimeSeconds: frameImage.actualTimeSeconds,
        boardID: editorContext.boardID,
        itemID: itemID
    )
    guard let updateResult = updateVideoPoster(
        withID: itemID,
        posterAsset: persistedPoster.asset,
        posterTimeSeconds: persistedPoster.posterTimeSeconds
    ) else {
        throw CanvasVideoFrameServiceError.invalidVideoItem(itemID: itemID)
    }

    return updateResult
}

@discardableResult
func updateVideoPoster(
    withID itemID: CanvasItemID,
    posterAsset: CanvasImageAsset,
    posterTimeSeconds: Double
) -> CanvasVideoPosterUpdateResult? {
    guard canUpdateVideoPoster(withID: itemID) else {
        return nil
    }

    let beforeSnapshot = currentBoardHistorySnapshot()
    guard let updatedItem = scene.updateVideoPoster(
        withID: itemID,
        posterAsset: posterAsset,
        posterTimeSeconds: posterTimeSeconds
    ) else {
        return nil
    }

    let changeReason = "update video poster"
    _ = recordImmediateHistoryChange(
        from: beforeSnapshot,
        reason: changeReason,
        autosaveReason: changeReason
    )
    return CanvasVideoPosterUpdateResult(
        item: updatedItem,
        refreshReason: changeReason
    )
}
```

## 修改五：给阶段 7 / 8 预先补齐共享编辑上下文、抽帧和帧条入口

### 修改前

- `CanvasEditorSession` 只有 `canUpdateVideoPoster(...)` 和 `updateVideoPoster(...)` 这类纯 mutation 接口。
- 平台页如果要拿视频 URL、当前 poster 文件名、时长、帧条和指定时间点预览，都只能自己再拼一层逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 类型/函数: canUpdateVideoPoster(withID:) / updateVideoPoster(...)
// 功能说明: 修改前 Session 没有统一的视频编辑上下文和帧提取能力，平台页只能看到最终 mutation 入口。
func canUpdateVideoPoster(withID itemID: CanvasItemID) -> Bool {
    scene.item(withID: itemID)?.isVideo == true
}

@discardableResult
func updateVideoPoster(
    withID itemID: CanvasItemID,
    posterCGImage: CGImage,
    logicalPixelSize: CGSize? = nil,
    posterTimeSeconds: Double
) -> CanvasVideoPosterUpdateResult? {
    // 省略已有实现
    nil
}
```

### 修改后

- `CanvasEditorSession` 新增四个阶段 7 / 8 直接可用的共享入口：
  - `videoEditorContext(...)`
  - `videoFrameImage(...)`
  - `videoPreviewStrip(...)`
  - `commitVideoPosterFrame(...)`
- 这样平台控制器和编辑页只需要关心 UI，不需要自己碰 `board assets` 路径和 `AVFoundation`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 类型/函数: videoEditorContext(...) / videoFrameImage(...) / videoPreviewStrip(...) / commitVideoPosterFrame(...)
// 功能说明: 修改后 Session 对平台层暴露完整的视频编辑服务入口，阶段 7 / 8 可以直接复用这些接口做预览与提交。
func videoEditorContext(
    for itemID: CanvasItemID
) throws -> CanvasVideoEditorContext {
    guard let activeBoardID else {
        throw CanvasVideoFrameServiceError.missingBoardIdentity
    }
    guard let item = scene.item(withID: itemID), item.isVideo else {
        throw CanvasVideoFrameServiceError.invalidVideoItem(itemID: itemID)
    }

    return try CanvasVideoFrameService.editorContext(
        for: item,
        boardID: activeBoardID
    )
}

func videoFrameImage(
    for itemID: CanvasItemID,
    at timeSeconds: Double,
    quality: CanvasVideoFrameRenderQuality = .posterCommit
) throws -> CanvasVideoFrameImage {
    let editorContext = try videoEditorContext(for: itemID)
    return try CanvasVideoFrameService.frameImage(
        from: editorContext.sourceVideoURL,
        at: timeSeconds,
        quality: quality
    )
}

func videoPreviewStrip(
    for itemID: CanvasItemID,
    frameCount: Int = 9,
    maxPixelSize: Int = 160
) throws -> CanvasVideoPreviewStrip {
    let editorContext = try videoEditorContext(for: itemID)
    return try CanvasVideoFrameService.previewStrip(
        from: editorContext.sourceVideoURL,
        frameCount: frameCount,
        maxPixelSize: maxPixelSize
    )
}
```

## 修改六：iOS / macOS 编辑页不再只吃 `itemID`，而是接统一 `editorContext`

### 修改前

- 两个平台控制器打开编辑页时，直接把 `itemID` 塞给壳子页面。
- 壳子页内部只能显示 `itemID`，没有视频文件名、当前 poster、时长、尺寸这些后续 UI 必须要的数据。
- 如果解析视频上下文失败，也没有平台原生错误提示。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 类型/函数: presentVideoDisplayFrameEditor(for:)
// 功能说明: 修改前 iOS 端打开视频编辑页时只传 itemID，页面本身没有共享的视频上下文。
private func presentVideoDisplayFrameEditor(for itemID: CanvasItemID) {
    guard presentedViewController == nil else {
        return
    }

    let editorViewController = iOSVideoDisplayFrameEditorViewController(
        itemID: itemID
    )
    editorViewController.modalPresentationStyle = .fullScreen
    present(editorViewController, animated: true)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: init(itemID:) / viewDidLoad()
// 功能说明: 修改前 iOS 壳子页只有 itemID，没有接到后续阶段需要的 source video / poster / duration 等共享信息。
final class iOSVideoDisplayFrameEditorViewController: UIViewController {
    private let itemID: CanvasItemID

    init(itemID: CanvasItemID) {
        self.itemID = itemID
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        detailLabel.text =
            "Video item: \(itemID.uuidString)\n" +
            "The platform-specific frame controls will be added in the next phase."
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 类型/函数: presentVideoDisplayFrameEditor(for:)
// 功能说明: 修改前 macOS 端也只把 itemID 传给 sheet，失败时没有独立的视频编辑错误提示。
private func presentVideoDisplayFrameEditor(for itemID: CanvasItemID) {
    guard presentedViewControllers.isEmpty else {
        return
    }

    let editorViewController = macOSVideoDisplayFrameEditorViewController(
        itemID: itemID
    )
    presentAsSheet(editorViewController)
}
```

### 修改后

- `iOSViewController` / `macOSViewController` 打开编辑页前，先调用 `editorSession.videoEditorContext(...)`。
- 如果上下文解析失败，会弹出平台原生“Unable to Open Video Editor”错误。
- 两个平台壳子页都改成接收 `CanvasVideoEditorContext`，并把共享层已准备好的基础数据直接展示出来，作为阶段 7 / 8 的起点。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 类型/函数: presentVideoDisplayFrameEditor(for:) / presentVideoEditorError(message:)
// 功能说明: 修改后 iOS 端先解析统一 editorContext，再决定展示全屏页；若共享层拿不到上下文，则用 UIKit alert 直接提示。
private func presentVideoDisplayFrameEditor(for itemID: CanvasItemID) {
    guard presentedViewController == nil else {
        return
    }

    do {
        let editorContext = try editorSession.videoEditorContext(for: itemID)
        let editorViewController = iOSVideoDisplayFrameEditorViewController(
            editorContext: editorContext
        )
        editorViewController.modalPresentationStyle = .fullScreen
        present(editorViewController, animated: true)
    } catch {
        presentVideoEditorError(message: error.localizedDescription)
    }
}

private func presentVideoEditorError(message: String) {
    let alertController = UIAlertController(
        title: "Unable to Open Video Editor",
        message: message,
        preferredStyle: .alert
    )
    alertController.addAction(UIAlertAction(title: "OK", style: .default))
    present(alertController, animated: true)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: init(editorContext:) / viewDidLoad()
// 功能说明: 修改后 iOS 壳子页直接消费共享 editorContext，后续完整 UI 可继续沿用这份上下文而不再重复解析视频资源。
final class iOSVideoDisplayFrameEditorViewController: UIViewController {
    private let editorContext: CanvasVideoEditorContext

    init(editorContext: CanvasVideoEditorContext) {
        self.editorContext = editorContext
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        detailLabel.text =
            "Video item: \(editorContext.itemID.uuidString)\n" +
            "Source video: \(editorContext.sourceVideoFilename)\n" +
            "Current poster: \(editorContext.currentPosterFilename)\n" +
            "Poster time: \(formatVideoDisplayFrameEditorSeconds(editorContext.currentPosterTimeSeconds))\n" +
            "Duration: \(formatVideoDisplayFrameEditorSeconds(editorContext.durationSeconds))\n" +
            "Video size: \(Int(editorContext.naturalPixelSize.width)) x \(Int(editorContext.naturalPixelSize.height))\n" +
            "The shared frame extraction and poster persistence services are ready. The full platform UI will be added in the next phase."
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 类型/函数: presentVideoDisplayFrameEditor(for:) / presentVideoEditorError(message:)
// 功能说明: 修改后 macOS 端与 iOS 一样先解析统一 editorContext，再决定展示 sheet；失败时给出 AppKit 原生提示。
private func presentVideoDisplayFrameEditor(for itemID: CanvasItemID) {
    guard presentedViewControllers.isEmpty else {
        return
    }

    do {
        let editorContext = try editorSession.videoEditorContext(for: itemID)
        let editorViewController = macOSVideoDisplayFrameEditorViewController(
            editorContext: editorContext
        )
        presentAsSheet(editorViewController)
    } catch {
        presentVideoEditorError(message: error.localizedDescription)
    }
}

private func presentVideoEditorError(message: String) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Unable to Open Video Editor"
    alert.informativeText = message
    alert.addButton(withTitle: "OK")

    if let window = view.window {
        alert.beginSheetModal(for: window)
    } else {
        alert.runModal()
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: init(editorContext:) / viewDidLoad()
// 功能说明: 修改后 macOS 壳子页也直接消费共享 editorContext，阶段 8 可以在此基础上继续扩展播放区和帧条。
final class macOSVideoDisplayFrameEditorViewController: NSViewController {
    private let editorContext: CanvasVideoEditorContext

    init(editorContext: CanvasVideoEditorContext) {
        self.editorContext = editorContext
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        detailLabel.stringValue =
            "Video item: \(editorContext.itemID.uuidString)\n" +
            "Source video: \(editorContext.sourceVideoFilename)\n" +
            "Current poster: \(editorContext.currentPosterFilename)\n" +
            "Poster time: \(formatVideoDisplayFrameEditorSeconds(editorContext.currentPosterTimeSeconds))\n" +
            "Duration: \(formatVideoDisplayFrameEditorSeconds(editorContext.durationSeconds))\n" +
            "Video size: \(Int(editorContext.naturalPixelSize.width)) x \(Int(editorContext.naturalPixelSize.height))\n" +
            "The shared frame extraction and poster persistence services are ready. The full platform UI will be added in the next phase."
    }
}
```

## 验证

- 已对阶段 6 相关 Swift 文件执行静态诊断，`ReadLints` 返回无报错。
- 本次记录生成前，已复核 `git diff --stat` 与相关文件内容，确认变更边界集中在共享视频服务、导入写盘、poster 更新链和平台编辑页接线。
- 本次未执行整项目 `xcodebuild` 编译验证。
