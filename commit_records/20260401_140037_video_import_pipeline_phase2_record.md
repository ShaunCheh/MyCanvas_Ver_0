# 20260401_140037_video_import_pipeline_phase2_record

## 记录范围

- 记录内容：
  1. 把共享导入契约从 `image-only` 扩成 `media-aware`，让 transfer/request/command 可以携带视频条目。
  2. 新增共享 `CanvasMediaImportService`，导入视频时立即复制原视频到当前 board 的 `assets`，并生成本地 poster PNG。
  3. 改造 `CanvasEditorSession`，让导入布局逻辑同时接住 transient image 与 persisted video item。
  4. 改造 iOS 导入入口：`PHPicker`、粘贴、拖放均支持视频，视频走 `file representation + 临时 staging + 统一复制服务`。
  5. 改造 macOS 导入入口：`NSOpenPanel`、粘贴、拖放均支持视频文件 URL，并复用同一套导入构建逻辑。
  6. 补齐 `BoardStore.ensureAssetsDirectoryURL(...)` 与 `CoordinatedFileIO.copyItem(...)`，作为“导入即持久化”底座。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift`
  - `MyCanvas_Ver_0/Canvas/Import/CanvasMediaImportService.swift`
  - `MyCanvas_Ver_0/Canvas/Transfer/CanvasTransferTypes.swift`
  - `MyCanvas_Ver_0/Canvas/Transfer/CanvasTransferCommandLowerer.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/CoordinatedFileIO.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSCanvasImportAdapter.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSCanvasImportAdapter.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
  - `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift`
- 本记录不包含：
  - 阶段 1 的双资产存储契约改造
  - 阶段 3 的画板 poster-only 渲染收口
  - 阶段 4 的 BoardList / thumbnail / persisted thumbnail
  - 阶段 5 的右键菜单“设置展示画面”
  - 阶段 7 / 8 的视频展示画面编辑页
  - git commit / push

## 修改一：共享导入契约从 `image-only` 扩成 `media-aware`

### 修改前

- `CanvasTransferItem` 只能表示图片。
- `CanvasImportRequest` 只能携带 `[CanvasResolvedImportImage]`。
- `CanvasCommand` 也只有 `.importImages(...)`，平台层即使拿到了视频 URL，也没有合法的共享命令入口往下传。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Transfer/CanvasTransferTypes.swift
// 函数名: CanvasTransferItem / CanvasTransferRequest.init(images:placement:layout:sourceDescription:)
// 功能说明: 修改前 transfer 层只能承载图片导入结果，无法表达视频条目，更没有“当前请求是否包含视频”的语义。
enum CanvasTransferItem {
    case image(CanvasResolvedImportImage)
}

struct CanvasTransferRequest {
    let items: [CanvasTransferItem]
    let placement: CanvasImportPlacement
    let layout: CanvasImportLayout
    let sourceDescription: String

    init(
        images: [CanvasResolvedImportImage],
        placement: CanvasImportPlacement = .cameraCenter,
        layout: CanvasImportLayout = .automatic,
        sourceDescription: String = "external source"
    ) {
        self.init(
            items: images.map { .image($0) },
            placement: placement,
            layout: layout,
            sourceDescription: sourceDescription
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 函数名: CanvasImportRequest.init(images:placement:layout:sourceDescription:)
// 功能说明: 修改前 import request 仍然是 image-only，EditorSession 和 CommandExecutor 只能消费图片数组。
struct CanvasImportRequest {
    let images: [CanvasResolvedImportImage]
    let placement: CanvasImportPlacement
    let layout: CanvasImportLayout
    let sourceDescription: String

    init(
        images: [CanvasResolvedImportImage],
        placement: CanvasImportPlacement = .cameraCenter,
        layout: CanvasImportLayout = .automatic,
        sourceDescription: String = "external source"
    ) {
        self.images = images
        self.placement = placement
        self.layout = layout
        self.sourceDescription = sourceDescription
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 函数名: CanvasCommandID / CanvasCommand
// 功能说明: 修改前命令层只有 importImages，名称和负载都把导入限定为图片。
enum CanvasCommandID: String {
    case importImages
}

enum CanvasCommand {
    case importImages(CanvasImportRequest)
}
```

### 修改后

- `CanvasTransferItem` 新增 `.video(CanvasResolvedImportVideo)`。
- `CanvasImportTypes` 引入了 `CanvasImportedVideoSource`、`CanvasResolvedImportVideo`、`CanvasImportedVideoAsset`、`CanvasImportItem`。
- `CanvasImportRequest` 从 `images` 升级为 `items`，图片与视频可以共用同一条 command 主链。
- `CanvasCommand` 从 `.importImages` 统一改为 `.importMedia`，同时带动 command catalog、toolbar item ID、context menu resolver 的导入术语一起收口。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 函数名: CanvasResolvedImportVideo.init(...) / CanvasImportRequest.init(items:placement:layout:sourceDescription:)
// 功能说明: 修改后共享导入模型可以同时承载图片与视频；视频会在解析阶段就带上本地源文件、poster 图和 poster 时间点。
struct CanvasImportedVideoSource: Equatable {
    let localFileURL: URL
    let typeIdentifier: String?
    let filenameHint: String?
    let shouldDeleteAfterImport: Bool
}

struct CanvasResolvedImportVideo {
    let source: CanvasImportedVideoSource
    let posterCGImage: CGImage
    let posterTimeSeconds: Double
    let logicalPixelSize: CGSize
}

struct CanvasImportedVideoAsset {
    let asset: CanvasImageAsset
    let videoSource: CanvasVideoSource
}

enum CanvasImportItem {
    case image(CanvasResolvedImportImage)
    case video(CanvasImportedVideoAsset)
}

struct CanvasImportRequest {
    let items: [CanvasImportItem]
    let placement: CanvasImportPlacement
    let layout: CanvasImportLayout
    let sourceDescription: String
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Transfer/CanvasTransferTypes.swift
// 函数名: CanvasTransferItem / CanvasTransferRequest.containsVideo
// 功能说明: 修改后 transfer 层会显式区分图片和视频，并能让上层快速判断当前导入请求是否包含视频，从而决定是否需要先准备 board assets。
enum CanvasTransferItem {
    case image(CanvasResolvedImportImage)
    case video(CanvasResolvedImportVideo)
}

struct CanvasTransferRequest {
    let items: [CanvasTransferItem]

    var containsVideo: Bool {
        items.contains { item in
            if case .video = item {
                return true
            }

            return false
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 函数名: CanvasCommandID / CanvasCommand.id / CanvasCommand.shouldCancelActiveRotation
// 功能说明: 修改后导入命令从 importImages 统一更名为 importMedia，命令层对导入内容不再预设“只可能是图片”。
enum CanvasCommandID: String {
    case importMedia
}

enum CanvasCommand {
    case importMedia(CanvasImportRequest)

    var id: CanvasCommandID {
        switch self {
        case .importMedia:
            return .importMedia
        }
    }
}
```

## 修改二：新增共享视频导入服务，把“复制到 board assets + 生成 poster”从平台层收口到 shared service

### 修改前

- 平台 adapter 最多只能把内容解析成 `CanvasResolvedImportImage`，没有一层共享服务负责“复制视频源文件到 board assets + 写 poster PNG”。
- `BoardStore` 没有一个导入阶段可直接调用的 `assets` 目录准备入口。
- `CoordinatedFileIO` 只有读写和删除，没有安全协调下的文件复制能力。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/CoordinatedFileIO.swift
// 函数名: writeData(_:to:fileManager:) / removeItemIfExists(at:fileManager:)
// 功能说明: 修改前文件 IO 只有写入和删除能力，没有“把一个外部视频文件复制进 board assets”的原子复制入口。
enum CoordinatedFileIO {
    static func writeData(
        _ data: Data,
        to url: URL,
        fileManager: FileManager = .default
    ) throws {
        try ensureDirectory(at: url.deletingLastPathComponent(), fileManager: fileManager)
        try coordinateWriting(at: url) { coordinatedURL in
            try data.write(to: coordinatedURL, options: .atomic)
        }
    }

    static func removeItemIfExists(
        at url: URL,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try coordinateWriting(at: url, options: .forDeleting) { coordinatedURL in
            try fileManager.removeItem(at: coordinatedURL)
        }
    }
}
```

### 修改后

- 新增 `CanvasMediaImportService.makeImportRequest(...)`，把视频导入时的持久化准备统一收口。
- 如果请求里包含视频，服务会先通过 `BoardStore.ensureAssetsDirectoryURL(...)` 确保当前 board 的 `assets` 目录存在。
- 然后 `importVideo(...)` 会复制原视频、写 poster PNG、构造持久化 `CanvasImageAsset + CanvasVideoSource`，失败时还会回滚已创建的资产文件。
- iOS 临时 staging 出来的临时视频文件也会在导入完成后统一清理。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasMediaImportService.swift
// 函数名: makeImportRequest(from:boardID:) / importVideo(_:into:)
// 功能说明: 新增共享媒体导入服务，负责把 transfer 层解析出来的视频真正落到 board assets，并返回运行时可直接插入画板的持久化 video item 负载。
enum CanvasMediaImportService {
    static func makeImportRequest(
        from transferRequest: CanvasTransferRequest,
        boardID: UUID? = nil
    ) throws -> CanvasImportRequest? {
        guard transferRequest.isEmpty == false else {
            return nil
        }

        let assetsDirectoryURL: URL?
        if transferRequest.containsVideo {
            guard let boardID else {
                throw CanvasMediaImportServiceError.missingBoardIDForVideoImport
            }

            assetsDirectoryURL = try BoardStore.ensureAssetsDirectoryURL(
                for: boardID
            )
        } else {
            assetsDirectoryURL = nil
        }

        var importItems: [CanvasImportItem] = []
        for item in transferRequest.items {
            switch item {
            case let .image(image):
                importItems.append(.image(image))
            case let .video(video):
                guard let assetsDirectoryURL else {
                    throw CanvasMediaImportServiceError.missingBoardIDForVideoImport
                }

                let importedVideo = try importVideo(
                    video,
                    into: assetsDirectoryURL
                )
                importItems.append(.video(importedVideo.item))
            }
        }

        return CanvasImportRequest(
            items: importItems,
            placement: transferRequest.placement,
            layout: transferRequest.layout,
            sourceDescription: transferRequest.sourceDescription
        )
    }

    private static func importVideo(
        _ video: CanvasResolvedImportVideo,
        into assetsDirectoryURL: URL
    ) throws -> ImportedVideoResult {
        let sourceVideoFilename = makeUniqueVideoFilename(for: video.source)
        let posterImageFilename = makePosterFilename()

        try CoordinatedFileIO.copyItem(
            at: video.source.localFileURL,
            to: assetsDirectoryURL.appendingPathComponent(sourceVideoFilename)
        )
        try CoordinatedFileIO.writeData(
            makePNGData(for: video.posterCGImage),
            to: assetsDirectoryURL.appendingPathComponent(posterImageFilename)
        )

        return ImportedVideoResult(
            item: CanvasImportedVideoAsset(
                asset: CanvasImageAsset.persistedStaticImage(
                    filename: posterImageFilename,
                    cgImage: video.posterCGImage,
                    logicalPixelSize: video.logicalPixelSize
                ),
                videoSource: CanvasVideoSource(
                    assetReference: .persisted(filename: sourceVideoFilename),
                    posterTimeSeconds: video.posterTimeSeconds
                )
            ),
            createdAssetURLs: []
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: ensureAssetsDirectoryURL(for:userDefaults:)
// 功能说明: 修改后导入链可以在真正插入 item 之前，先安全地准备好当前 board 的 assets 目录，满足“导入即复制到 board assets”的要求。
static func ensureAssetsDirectoryURL(
    for boardID: UUID,
    userDefaults: UserDefaults = .standard
) throws -> URL {
    try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
        try CoordinatedFileIO.ensureDirectory(at: boardsDirectoryURL)
        let boardDirectoryURL = self.boardDirectoryURL(
            for: boardID,
            boardsDirectoryURL: boardsDirectoryURL
        )
        let assetsDirectoryURL = boardDirectoryURL.appendingPathComponent(
            assetsDirectoryName,
            isDirectory: true
        )
        try CoordinatedFileIO.ensureDirectory(at: boardDirectoryURL)
        try CoordinatedFileIO.ensureDirectory(at: assetsDirectoryURL)
        return assetsDirectoryURL
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/CoordinatedFileIO.swift
// 函数名: copyItem(at:to:fileManager:) / coordinateReadingAndWriting(from:to:writingOptions:accessor:)
// 功能说明: 修改后导入视频时可以在 NSFileCoordinator 保护下把外部文件安全复制到目标 board assets。
static func copyItem(
    at sourceURL: URL,
    to destinationURL: URL,
    fileManager: FileManager = .default
) throws {
    try ensureDirectory(
        at: destinationURL.deletingLastPathComponent(),
        fileManager: fileManager
    )
    try coordinateReadingAndWriting(
        from: sourceURL,
        to: destinationURL
    ) { coordinatedSourceURL, coordinatedDestinationURL in
        if fileManager.fileExists(atPath: coordinatedDestinationURL.path) {
            try fileManager.removeItem(at: coordinatedDestinationURL)
        }

        try fileManager.copyItem(
            at: coordinatedSourceURL,
            to: coordinatedDestinationURL
        )
    }
}
```

## 修改三：`CanvasEditorSession` 从 `appendImportedImages` 扩成 `appendImportedMedia`

### 修改前

- `CanvasEditorSession` 只会追加图片。
- 每个导入项都会走 `makeTransientImageAssetRegistration()`，天然假设导入资源是“还能被当作 transient image payload 保存”的图片或 GIF。
- 视频没有入口把“已持久化 poster 资产 + videoSource”接进现有几何布局逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: appendImportedImages(_:placement:layout:)
// 功能说明: 修改前 EditorSession 只接受图片数组，并且固定把每个导入资源都注册成 transient image asset。
@discardableResult
func appendImportedImages(
    _ images: [CanvasResolvedImportImage],
    placement: CanvasImportPlacement = .cameraCenter,
    layout: CanvasImportLayout = .automatic
) -> [CanvasImageItem] {
    guard images.isEmpty == false else {
        return []
    }

    for (index, image) in images.enumerated() {
        let importRegistration = image.makeTransientImageAssetRegistration()
        let asset = importRegistration.asset
        if let payload = importRegistration.payload {
            transientImageAssetPayloads[payload.assetReference] = payload
        }
        let item = CanvasImageItem(
            asset: asset,
            center: CGPoint(x: 0, y: 0),
            size: normalizedDisplaySize(for: asset.logicalPixelSize),
            zIndex: CGFloat(index)
        )
        scene.append(item)
    }

    return []
}
```

### 修改后

- `appendImportedMedia(...)` 统一处理 `CanvasImportItem`。
- 图片仍走原来的 transient image payload 路线。
- 视频则直接使用已经持久化好的 `CanvasImportedVideoAsset`，把 `poster asset + videoSource` 一起挂到 `CanvasImageItem` 上，同时继续复用现有导入布局、尺寸归一化和历史记录逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: appendImportedMedia(_:placement:layout:)
// 功能说明: 修改后 EditorSession 会在不改动既有几何布局算法的前提下，同时接住 transient image 和 persisted video item。
@discardableResult
func appendImportedMedia(
    _ items: [CanvasImportItem],
    placement: CanvasImportPlacement = .cameraCenter,
    layout: CanvasImportLayout = .automatic
) -> [CanvasImageItem] {
    guard items.isEmpty == false else {
        return []
    }

    let importCenter = resolvedImportCenter(for: placement)
    let resolvedLayout = resolvedImportLayout(
        layout,
        itemCount: items.count
    )
    let startingZIndex = nextImageZIndex()
    var importedItems: [CanvasImageItem] = []

    for (index, item) in items.enumerated() {
        let offset = importOffset(
            forItemAt: index,
            layout: resolvedLayout
        )
        let importedItem: CanvasImageItem
        switch item {
        case let .image(image):
            let importRegistration = image.makeTransientImageAssetRegistration()
            let asset = importRegistration.asset
            if let payload = importRegistration.payload {
                transientImageAssetPayloads[payload.assetReference] = payload
            }
            importedItem = CanvasImageItem(
                asset: asset,
                center: CGPoint(
                    x: importCenter.x + offset.x,
                    y: importCenter.y + offset.y
                ),
                size: normalizedDisplaySize(for: asset.logicalPixelSize),
                zIndex: startingZIndex + CGFloat(index)
            )
        case let .video(video):
            importedItem = CanvasImageItem(
                asset: video.asset,
                videoSource: video.videoSource,
                center: CGPoint(
                    x: importCenter.x + offset.x,
                    y: importCenter.y + offset.y
                ),
                size: normalizedDisplaySize(for: video.asset.logicalPixelSize),
                zIndex: startingZIndex + CGFloat(index)
            )
        }

        scene.append(importedItem)
        expandBoardIfNeeded(toInclude: importedItem.worldFrame)
        importedItems.append(importedItem)
    }

    return importedItems
}
```

## 修改四：iOS 导入链从“只收图片字节”升级为“图片 + 视频文件表示”

### 修改前

- `PHPicker` 只允许图片。
- `iOSCanvasImportAdapter` 只查 `UTType.image`，并且只走 `loadDataRepresentation(...)`。
- 控制器拿到 `CanvasTransferRequest` 后会直接 lower 成 command，没有“先准备 board assets 再构造导入请求”的环节。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handleImportButtonTap()
// 功能说明: 修改前 iOS 工具栏导入按钮只允许用户选择图片，视频在入口层就被排除了。
@objc
private func handleImportButtonTap() {
    guard isReadingModeActive == false else {
        return
    }

    commitActiveTextEditIfNeeded()
    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .images
    configuration.selectionLimit = 0

    let pickerViewController = PHPickerViewController(configuration: configuration)
    pickerViewController.delegate = self
    present(pickerViewController, animated: true)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSCanvasImportAdapter.swift
// 函数名: resolvedImage(from:) / loadImageData(from:typeIdentifier:)
// 功能说明: 修改前 adapter 只支持图片 provider，视频既不会被识别，也不会走文件表示加载。
private static func resolvedImage(
    from itemProvider: NSItemProvider
) async -> CanvasResolvedImportImage? {
    let preferredTypeIdentifier =
        preferredImageTypeIdentifier(from: itemProvider) ??
        UTType.image.identifier
    guard
        itemProvider.hasItemConformingToTypeIdentifier(
            UTType.image.identifier
        ),
        let data = await loadImageData(
            from: itemProvider,
            typeIdentifier: preferredTypeIdentifier
        ),
        let resolvedImage = CanvasResolvedImportImage(
            data: data,
            typeIdentifier: preferredTypeIdentifier,
            filenameHint: itemProvider.suggestedName
        )
    else {
        return nil
    }

    return resolvedImage
}
```

### 修改后

- `PHPicker` 改成 `.any(of: [.images, .videos])`。
- iOS adapter 现在能同时解析图片和视频，视频优先走 `loadFileRepresentation(...)`，先复制到临时 staging，避免 provider 回调结束后文件失效。
- 控制器新增 `buildImportRequest(...)`，如果请求包含视频，会先确保当前 board identity，再调用 `CanvasMediaImportService` 生成真正的 media import request。
- 缺少保存目录时，会弹出明确的导入失败提示，而不是静默失败。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSCanvasImportAdapter.swift
// 函数名: resolvedTransferItem(from:) / resolvedVideo(from:) / loadOwnedFileURL(from:typeIdentifier:filenameHint:)
// 功能说明: 修改后 iOS adapter 会优先识别视频 provider，并把 file representation 拷贝成自己拥有的临时文件，再交给共享导入服务做持久化复制。
private static func resolvedTransferItem(
    from itemProvider: NSItemProvider
) async -> CanvasTransferItem? {
    if preferredVideoTypeIdentifier(from: itemProvider) != nil {
        guard let resolvedVideo = await resolvedVideo(from: itemProvider) else {
            return nil
        }

        return .video(resolvedVideo)
    }

    if let resolvedImage = await resolvedImage(from: itemProvider) {
        return .image(resolvedImage)
    }

    return nil
}

private static func resolvedVideo(
    from itemProvider: NSItemProvider
) async -> CanvasResolvedImportVideo? {
    guard
        let preferredTypeIdentifier = preferredVideoTypeIdentifier(
            from: itemProvider
        ),
        let ownedFileURL = await loadOwnedFileURL(
            from: itemProvider,
            typeIdentifier: preferredTypeIdentifier,
            filenameHint: itemProvider.suggestedName
        )
    else {
        return nil
    }

    return CanvasResolvedImportVideo(
        localFileURL: ownedFileURL,
        typeIdentifier: preferredTypeIdentifier,
        filenameHint: resolvedFilenameHint(
            itemProvider.suggestedName,
            typeIdentifier: preferredTypeIdentifier
        ),
        shouldDeleteAfterImport: true
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handleImportButtonTap() / performTransferRequest(_:) / buildImportRequest(from:) / handleImportError(_:)
// 功能说明: 修改后 iOS 控制器会先把 transfer request 提升为真正的 media import request；如果导入里含视频，会先准备 board identity 和 board assets，再进入 command 主链。
@objc
private func handleImportButtonTap() {
    guard isReadingModeActive == false else {
        return
    }

    commitActiveTextEditIfNeeded()
    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .any(of: [.images, .videos])
    configuration.selectionLimit = 0

    let pickerViewController = PHPickerViewController(configuration: configuration)
    pickerViewController.delegate = self
    present(pickerViewController, animated: true)
}

@discardableResult
private func performTransferRequest(
    _ request: CanvasTransferRequest
) -> Bool {
    do {
        guard let importRequest = try buildImportRequest(from: request),
              let command = CanvasTransferCommandLowerer.loweredCommand(
                  for: importRequest
              )
        else {
            return false
        }

        performCommand(command)
        return true
    } catch {
        handleImportError(error)
        return false
    }
}

private func buildImportRequest(
    from request: CanvasTransferRequest
) throws -> CanvasImportRequest? {
    let boardID: UUID?
    if request.containsVideo {
        guard editorSession.ensureActiveBoardIdentityIfNeeded() else {
            return nil
        }

        boardID = editorSession.activeBoardID
    } else {
        boardID = nil
    }

    return try CanvasMediaImportService.makeImportRequest(
        from: request,
        boardID: boardID
    )
}
```

## 修改五：macOS 导入链从“只收图片 URL”升级为“图片 + 视频 URL”

### 修改前

- `NSOpenPanel.allowedContentTypes` 只有 `.image`。
- `macOSCanvasImportAdapter` 的 pasteboard URL 读取条件只允许图片。
- URL 导入分支只会把文件按图片数据读进来，不会区分视频，也没有共享导入准备步骤。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handleImportButtonClick()
// 功能说明: 修改前 macOS 打开面板只允许选图片文件，视频在系统文件选择层就无法进入导入流程。
@objc
private func handleImportButtonClick() {
    commitActiveTextEditIfNeeded()
    guard let window = view.window else {
        return
    }

    let openPanel = NSOpenPanel()
    openPanel.allowedContentTypes = [.image]
    openPanel.allowsMultipleSelection = true
    openPanel.canChooseDirectories = false
    openPanel.canChooseFiles = true
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSCanvasImportAdapter.swift
// 函数名: imageFileURLs(from:) / makeResolvedImportImage(from:)
// 功能说明: 修改前 macOS adapter 只从 pasteboard / drop 中读取图片 URL，并且默认把 URL 内容当成图片字节解析。
private static let imageFileURLReadingOptions: [NSPasteboard.ReadingOptionKey: Any] = [
    .urlReadingFileURLsOnly: true,
    .urlReadingContentsConformToTypes: [UTType.image.identifier]
]

private static func imageFileURLs(from pasteboard: NSPasteboard) -> [URL] {
    let objects = pasteboard.readObjects(
        forClasses: [NSURL.self],
        options: imageFileURLReadingOptions
    ) as? [NSURL] ?? []
    return objects.map { $0 as URL }
}
```

### 修改后

- `NSOpenPanel.allowedContentTypes` 扩成 `[.image, .movie]`。
- macOS adapter 的 URL 读取条件扩成 image + movie + video，并在 URL 解析阶段区分图片和视频。
- 图片仍按原路径走 `CanvasResolvedImportImage`，视频则会直接构造成 `CanvasResolvedImportVideo`，再交给共享导入服务持久化。
- 控制器和 iOS 一样，先 `buildImportRequest(...)`，再 lower command；如果缺少保存目录，会弹出导入错误。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSCanvasImportAdapter.swift
// 函数名: mediaFileURLs(from:) / makeResolvedTransferItem(from:) / resolvedContentType(from:)
// 功能说明: 修改后 macOS adapter 会在 URL 层区分图片和视频，并把视频 URL 直接构造成共享的视频导入模型。
private static let mediaFileURLReadingOptions: [NSPasteboard.ReadingOptionKey: Any] = [
    .urlReadingFileURLsOnly: true,
    .urlReadingContentsConformToTypes: [
        UTType.image.identifier,
        UTType.movie.identifier,
        UTType.video.identifier
    ]
]

private static func makeResolvedTransferItem(
    from url: URL
) -> CanvasTransferItem? {
    let contentType = resolvedContentType(from: url)
    if contentType?.conforms(to: .image) == true {
        guard let resolvedImage = makeResolvedImportImage(
            from: url,
            typeIdentifier: contentType?.identifier
        ) else {
            return nil
        }

        return .image(resolvedImage)
    }

    if contentType.map(isVideoContentType) == true || isLikelyVideoURL(url) {
        guard let resolvedVideo = CanvasResolvedImportVideo(
            localFileURL: url,
            typeIdentifier: contentType?.identifier,
            filenameHint: url.lastPathComponent
        ) else {
            return nil
        }

        return .video(resolvedVideo)
    }

    return nil
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handleImportButtonClick() / performTransferRequest(_:) / buildImportRequest(from:) / handleImportError(_:)
// 功能说明: 修改后 macOS 控制器会先通过共享服务准备视频导入所需的持久化资产，再进入统一的 importMedia command。
@objc
private func handleImportButtonClick() {
    commitActiveTextEditIfNeeded()
    guard let window = view.window else {
        return
    }

    let openPanel = NSOpenPanel()
    openPanel.allowedContentTypes = [.image, .movie]
    openPanel.allowsMultipleSelection = true
    openPanel.canChooseDirectories = false
    openPanel.canChooseFiles = true
}

@discardableResult
private func performTransferRequest(
    _ request: CanvasTransferRequest
) -> Bool {
    do {
        guard let importRequest = try buildImportRequest(from: request),
              let command = CanvasTransferCommandLowerer.loweredCommand(
                  for: importRequest
              )
        else {
            return false
        }

        performCommand(command)
        return true
    } catch {
        handleImportError(error)
        return false
    }
}

private func buildImportRequest(
    from request: CanvasTransferRequest
) throws -> CanvasImportRequest? {
    let boardID: UUID?
    if request.containsVideo {
        guard editorSession.ensureActiveBoardIdentityIfNeeded() else {
            return nil
        }

        boardID = editorSession.activeBoardID
    } else {
        boardID = nil
    }

    return try CanvasMediaImportService.makeImportRequest(
        from: request,
        boardID: boardID
    )
}
```

## 本次结果

- 导入主链已经从“图片导入”升级为“媒体导入”，共享 transfer / import / command 三层都能表达视频。
- iOS 和 macOS 的工具栏导入、粘贴、拖放三条主入口都已经具备视频接入能力。
- 视频在导入阶段就会被复制到当前 board 的 `assets`，同时生成本地 poster PNG，不再依赖外部 URL。
- `CanvasEditorSession` 已经能够在不重写现有几何布局算法的前提下，把视频 item 像图片一样插入画板。

## 当前边界

- 这一步还没有把视频 item 的画板渲染、BoardList 缩略图、右键菜单入口、展示画面编辑页全部接完，那些仍属于后续阶段。
- 当前 poster 仍然是导入时生成的初始封面，后续“切换展示帧”还需要阶段 5 / 6 / 7 / 8 继续完成。
- 这一步的重点是“跨平台导入链 + board assets 复制落盘”，不是完整视频编辑体验。

## 验证情况

- 已对本次改动文件执行 `ReadLints`，未发现新的诊断问题。
- 没有执行项目级 `xcodebuild`；当前环境仍是 Command Line Tools，不是完整 Xcode。
