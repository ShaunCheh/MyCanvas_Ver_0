# 20260407_132654_gif_phase4_request_builder_record

## 记录范围

- 记录内容：新增共享 `CanvasGIFFrameImportBuilder`，把“源 GIF + 选中帧 + 源 item 几何”收口成自包含的 `CanvasImportRequest`。
- 记录内容：在 `CanvasEditorSession` 中新增 `gifFrameImportRequest(...)` 入口，优先读取 transient payload，失败时回退到持久化 GIF asset data。
- 记录内容：显式保证 GIF 派生帧产物为静态图片，不携带原 GIF 的动画元数据。
- 记录内容：新增阶段 4 定向测试，覆盖 builder 直接构造、session 的 transient 路径、session 的 persisted 回退路径。
- 涉及文件：`MyCanvas_Ver_0/Canvas/GIF/CanvasGIFFrameImportBuilder.swift`
- 涉及文件：`MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- 涉及文件：`MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests.swift`
- 本记录不包含：GIF 上下文菜单动作接线。
- 本记录不包含：iOS / macOS 选帧页面。
- 本记录不包含：git commit / push。

## 修改一：新增共享 GIF 派生导入 builder

### 修改前

- 阶段 3 之后，工程里只有通用 `CanvasImportRequest` 与 `appendImportedMedia(...)` 执行能力。
- 还没有一条共享能力能把“选中的 GIF 帧”构造成静态图片导入请求。
- 也没有集中处理以下规则：
  - 选中帧下标去重 / 排序 / 越界检查
  - 按帧全尺寸解码
  - `placement = .worldPoint(gridOrigin)`
  - `layout = .grid(...)`
  - `presentationTemplate.size = sourceItem.size`
  - `presentationTemplate.cropRectNormalized = sourceItem.cropRectNormalized`
  - `presentationTemplate.rotation = 0`

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/GIF/CanvasGIFFrameImportBuilder.swift
// 类型/函数: （新增前不存在）
// 功能说明: 修改前共享层没有 GIF 派生导入 builder，无法从已选 GIF + frameIndex 列表直接生成 CanvasImportRequest。
// 修改前：暂无文件。
```

### 修改后

- 新增 `CanvasGIFFrameImportBuilderError`，集中表达无效 GIF item、缺失源数据、空选择、越界帧、解码失败等错误。
- 新增 `CanvasGIFFrameImportBuilder.makeImportRequest(...)`，把 builder 输入收口成一条自包含 request。
- builder 内部会：
  - 确认源 item 必须是 `animatedGIF` 且不是视频。
  - 校验 GIF 数据可解码且帧数大于 1。
  - 对 `selectedFrameIndices` 去重、排序并做越界检查。
  - 逐帧解码成 `CanvasResolvedImportImage`，并强制产物为 `.staticImage`。
  - 根据 `CanvasGIFFrameImportConfiguration.current.boardPlacementGrid` 计算网格起点。
  - 构造 `CanvasImportRequest`，把尺寸与 crop 继承自源 item，并强制旋转为 `0`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/GIF/CanvasGIFFrameImportBuilder.swift
// 类型/函数: CanvasGIFFrameImportBuilderError / CanvasGIFFrameImportBuilder.makeImportRequest(...)
// 功能说明: 修改后共享层提供 GIF 派生导入 builder，负责把源 GIF 和选中帧构造成可直接执行的 CanvasImportRequest。
import CoreGraphics
import Foundation
import ImageIO

enum CanvasGIFFrameImportBuilderError: LocalizedError {
    case invalidAnimatedGIFItem(itemID: UUID)
    case missingBoardIdentity
    case missingAnimatedImageSource(itemID: UUID)
    case invalidGIFData
    case emptyFrameSelection
    case frameIndexOutOfBounds(frameIndex: Int, frameCount: Int)
    case failedToDecodeFrame(frameIndex: Int)
}

enum CanvasGIFFrameImportBuilder {
    static let defaultSourceDescription = "gif-derived frames"

    static func makeImportRequest(
        from sourceItem: CanvasImageItem,
        gifData: Data,
        selectedFrameIndices: [Int],
        configuration: CanvasGIFFrameImportConfiguration = .current,
        sourceDescription: String = defaultSourceDescription
    ) throws -> CanvasImportRequest {
        guard sourceItem.isVideo == false, sourceItem.assetKind == .animatedGIF else {
            throw CanvasGIFFrameImportBuilderError.invalidAnimatedGIFItem(
                itemID: sourceItem.id
            )
        }

        guard let imageSource = CanvasGIFFrameService.makeImageSource(from: gifData) else {
            throw CanvasGIFFrameImportBuilderError.invalidGIFData
        }

        let frameCount = CGImageSourceGetCount(imageSource)
        guard frameCount > 1 else {
            throw CanvasGIFFrameImportBuilderError.invalidGIFData
        }

        let resolvedFrameIndices = try normalizedFrameIndices(
            selectedFrameIndices,
            frameCount: frameCount
        )
        let importedImages = try resolvedFrameIndices.map { frameIndex in
            try makeResolvedImportImage(
                frameIndex: frameIndex,
                imageSource: imageSource
            )
        }

        let boardPlacementGrid = configuration.boardPlacementGrid
        let presentationTemplate = CanvasImportPresentationTemplate(
            size: sourceItem.size,
            cropRectNormalized: sourceItem.cropRectNormalized,
            rotationPolicy: .fixed(0)
        )
        return CanvasImportRequest(
            images: importedImages,
            placement: .worldPoint(
                gridOrigin(
                    for: sourceItem,
                    presentationSize: presentationTemplate.size,
                    gridConfiguration: boardPlacementGrid
                )
            ),
            layout: .grid(
                columns: boardPlacementGrid.columns,
                horizontalSpacing: boardPlacementGrid.horizontalSpacing,
                verticalSpacing: boardPlacementGrid.verticalSpacing
            ),
            presentationTemplate: presentationTemplate,
            sourceDescription: sourceDescription
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/GIF/CanvasGIFFrameImportBuilder.swift
// 类型/函数: normalizedFrameIndices(_:frameCount:) / makeResolvedImportImage(frameIndex:imageSource:) / gridOrigin(for:presentationSize:gridConfiguration:)
// 功能说明: 修改后 builder 在内部统一处理帧索引清洗、静态帧解码和基于 worldBounds 的网格起点计算。
private static func normalizedFrameIndices(
    _ frameIndices: [Int],
    frameCount: Int
) throws -> [Int] {
    let uniqueFrameIndices = Array(Set(frameIndices)).sorted()
    guard uniqueFrameIndices.isEmpty == false else {
        throw CanvasGIFFrameImportBuilderError.emptyFrameSelection
    }

    if let invalidFrameIndex = uniqueFrameIndices.first(where: {
        $0 < 0 || $0 >= frameCount
    }) {
        throw CanvasGIFFrameImportBuilderError.frameIndexOutOfBounds(
            frameIndex: invalidFrameIndex,
            frameCount: frameCount
        )
    }

    return uniqueFrameIndices
}

private static func makeResolvedImportImage(
    frameIndex: Int,
    imageSource: CGImageSource
) throws -> CanvasResolvedImportImage {
    guard let cgImage = CanvasGIFFrameService.decodeFrame(
        at: frameIndex,
        from: imageSource
    ) else {
        throw CanvasGIFFrameImportBuilderError.failedToDecodeFrame(
            frameIndex: frameIndex
        )
    }

    return CanvasResolvedImportImage(
        cgImage: cgImage,
        assetKind: .staticImage,
        importedSource: nil,
        animatedMetadata: nil,
        logicalPixelSize: CGSize(
            width: cgImage.width,
            height: cgImage.height
        )
    )
}

private static func gridOrigin(
    for sourceItem: CanvasImageItem,
    presentationSize: CGSize,
    gridConfiguration: CanvasGIFFrameImportGridConfiguration
) -> CGPoint {
    let sourceBounds = sourceItem.worldBounds
    return CGPoint(
        x: sourceBounds.minX
            + gridConfiguration.contentInsets.leading
            + presentationSize.width / 2,
        y: sourceBounds.maxY
            + gridConfiguration.contentInsets.top
            + presentationSize.height / 2
    )
}
```

## 修改二：在 `CanvasEditorSession` 中增加 GIF request 构造入口，并打通 transient / persisted 源数据回退

### 修改前

- `CanvasEditorSession` 只有视频编辑相关的上下文读取能力，没有 GIF 派生导入 request 构造入口。
- 也没有统一封装“优先读 transient payload，读不到再回退到持久化 GIF asset data”的流程。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 类型/函数: videoEditorContext(for:)
// 功能说明: 修改前 session 只暴露视频编辑上下文能力，还没有 GIF 多选帧导入 request 的共享构造入口。
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
```

### 修改后

- 新增 `gifFrameImportRequest(...)`，供后续上下文菜单 / 选帧页直接调用。
- 新增 `gifFrameImportSourceData(...)`，优先使用 transient payload 中保留的原始 GIF 数据；拿不到时再从 `BoardStore` 读取持久化 asset data。
- 如果当前 item 不是 GIF、没有活动 board、或无法拿到原始 GIF 数据，会返回 builder 专用错误而不是静默失败。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 类型/函数: gifFrameImportRequest(for:frameIndices:configuration:userDefaults:)
// 功能说明: 修改后 session 提供 GIF 多选帧导入 request 构造入口，统一对 scene item 与 builder 调用做收口。
func gifFrameImportRequest(
    for itemID: CanvasItemID,
    frameIndices: [Int],
    configuration: CanvasGIFFrameImportConfiguration = .current,
    userDefaults: UserDefaults = .standard
) throws -> CanvasImportRequest {
    guard
        let sourceItem = scene.item(withID: itemID),
        sourceItem.isVideo == false,
        sourceItem.assetKind == .animatedGIF
    else {
        throw CanvasGIFFrameImportBuilderError.invalidAnimatedGIFItem(
            itemID: itemID
        )
    }

    let sourceData = try gifFrameImportSourceData(
        for: sourceItem,
        userDefaults: userDefaults
    )
    return try CanvasGIFFrameImportBuilder.makeImportRequest(
        from: sourceItem,
        gifData: sourceData,
        selectedFrameIndices: frameIndices,
        configuration: configuration
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 类型/函数: gifFrameImportSourceData(for:userDefaults:)
// 功能说明: 修改后 session 会优先读取 transient payload 中的 GIF 原始数据，失败时再回退到持久化 board asset data。
private func gifFrameImportSourceData(
    for sourceItem: CanvasImageItem,
    userDefaults: UserDefaults = .standard
) throws -> Data {
    if let sourceData = transientImageAssetPayload(
        for: sourceItem.assetReference
    )?.source?.data {
        return sourceData
    }

    guard let activeBoardID else {
        throw CanvasGIFFrameImportBuilderError.missingBoardIdentity
    }

    do {
        return try BoardStore.loadImageAssetData(
            boardID: activeBoardID,
            filename: sourceItem.assetReference.stableAssetFilename,
            userDefaults: userDefaults
        )
    } catch let error as FolderBookmarkStoreError {
        throw error
    } catch {
        throw CanvasGIFFrameImportBuilderError.missingAnimatedImageSource(
            itemID: sourceItem.id
        )
    }
}
```

## 修改三：新增阶段 4 定向测试，覆盖 builder 输出与 session 两条源数据路径

### 修改前

- 工程里还没有专门覆盖 GIF 派生 request builder 的测试文件。
- 没有自动验证以下关键路径：
  - builder 是否产出静态图片 item
  - builder 是否按 `worldBounds` + 配置生成 `placement`
  - session 是否优先走 transient payload
  - session 是否能从 persisted GIF asset 回退

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests.swift
// 类型/函数: （新增前不存在）
// 功能说明: 修改前没有阶段 4 的专用测试文件，无法自动验证 builder 输出与 transient / persisted 回退链路。
// 修改前：暂无文件。
```

### 修改后

- 新增 `CanvasGIFFrameImportBuilderTests`，覆盖 builder 本身以及 session 的两条数据路径。
- 测试里显式验证：
  - 产物 `CanvasResolvedImportImage` 必须是 `.staticImage`
  - `importedSource` / `animatedMetadata` 不再携带 GIF 动画语义
  - `presentationTemplate` 继承源 item 的 `size` 与 `cropRectNormalized`
  - `rotation` 被强制写成 `0`
  - `placement` 基于 `worldBounds` 和 board placement 配置计算
- 与阶段 1 一致，颜色判断使用“目标颜色通道占主导”的断言，而不是绝对通道值，避免 GIF 量化带来的测试抖动。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests.swift
// 类型/函数: CanvasGIFFrameImportBuilderTests.testBuilderCreatesStaticGridRequestFromSelectedGIFFrames()
// 功能说明: 修改后测试直接验证 builder 输出的 request 结构、静态帧产物和导入模板继承是否正确。
@MainActor
final class CanvasGIFFrameImportBuilderTests: XCTestCase {
    func testBuilderCreatesStaticGridRequestFromSelectedGIFFrames() throws {
        let request = try CanvasGIFFrameImportBuilder.makeImportRequest(
            from: sourceItem,
            gifData: gifData,
            selectedFrameIndices: [2, 0, 2],
            configuration: configuration
        )

        let importedImages = try request.resolvedImagesForTesting()
        XCTAssertEqual(importedImages.count, 2)
        XCTAssertEqual(importedImages[0].assetKind, .staticImage)
        XCTAssertNil(importedImages[0].importedSource)
        XCTAssertNil(importedImages[0].animatedMetadata)

        let firstPixel = try sampleGIFFrameImportPixelColor(
            in: importedImages[0].cgImage
        )
        let secondPixel = try sampleGIFFrameImportPixelColor(
            in: importedImages[1].cgImage
        )
        XCTAssertGreaterThan(firstPixel.red, firstPixel.green)
        XCTAssertGreaterThan(firstPixel.red, firstPixel.blue)
        XCTAssertGreaterThan(secondPixel.blue, secondPixel.red)
        XCTAssertGreaterThan(secondPixel.blue, secondPixel.green)

        let template = try XCTUnwrap(request.presentationTemplate)
        XCTAssertEqual(template.size, sourceItem.size)
        XCTAssertEqual(template.cropRectNormalized, cropRect)
        XCTAssertEqual(
            template.resolvedRotationRadians(
                assetDefaultRadians: sourceItem.rotationRadians
            ),
            0,
            accuracy: 0.0001
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests.swift
// 类型/函数: testSessionGIFFrameImportRequestUsesTransientPayloadSourceData() / testSessionGIFFrameImportRequestFallsBackToPersistedGIFAssetData()
// 功能说明: 修改后测试覆盖 session 的 transient payload 优先路径，以及从持久化 GIF asset 回退读取源数据的链路。
func testSessionGIFFrameImportRequestUsesTransientPayloadSourceData() throws {
    let session = makeGIFFrameImportTestSession()
    let sourceImage = try XCTUnwrap(
        CanvasResolvedImportImage(
            data: gifData,
            typeIdentifier: UTType.gif.identifier,
            filenameHint: "transient-source.gif"
        )
    )
    let importedItem = try XCTUnwrap(
        session.appendImportedMedia(
            [.image(sourceImage)],
            placement: .worldPoint(CGPoint(x: 60, y: 80)),
            layout: .stacked,
            presentationTemplate: CanvasImportPresentationTemplate(
                size: CGSize(width: 160, height: 110),
                cropRectNormalized: cropRect,
                rotationPolicy: .fixed(.pi / 3)
            )
        ).first
    )

    let request = try session.gifFrameImportRequest(
        for: importedItem.id,
        frameIndices: [1, 2]
    )
    let importedImages = try request.resolvedImagesForTesting()
    XCTAssertEqual(importedImages.count, 2)
}

func testSessionGIFFrameImportRequestFallsBackToPersistedGIFAssetData() throws {
    try withTemporaryGIFFrameImportWorkspace { _, userDefaults in
        let session = makeGIFFrameImportTestSession()
        session.startNewBoard(
            now: Date(timeIntervalSince1970: 1_710_001_000)
        )
        let boardID = try XCTUnwrap(session.activeBoardID)
        let persistedFilename = "persisted-source.gif"
        let sourceItem = CanvasImageItem(
            asset: CanvasImageAsset(
                reference: .persistedAnimatedGIF(filename: persistedFilename),
                poster: CanvasImagePoster(cgImage: posterImage),
                logicalPixelSize: CGSize(
                    width: posterImage.width,
                    height: posterImage.height
                )
            ),
            center: CGPoint(x: 45, y: 70),
            size: CGSize(width: 140, height: 90),
            zIndex: 0
        )
        session.scene.append(sourceItem)

        let assetsDirectoryURL = try BoardStore.ensureAssetsDirectoryURL(
            for: boardID,
            userDefaults: userDefaults
        )
        try CoordinatedFileIO.writeData(
            gifData,
            to: assetsDirectoryURL.appendingPathComponent(persistedFilename)
        )

        let request = try session.gifFrameImportRequest(
            for: sourceItem.id,
            frameIndices: [1],
            userDefaults: userDefaults
        )
        let importedImages = try request.resolvedImagesForTesting()
        XCTAssertEqual(importedImages.count, 1)
    }
}
```

## 验证结果

- 已执行：`xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:"MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasImportRequestModelTests"`
- 结果：`CanvasGIFFrameImportBuilderTests` 通过。
- 结果：`CanvasImportedMediaPlacementTests` 通过。
- 结果：`CanvasImportRequestModelTests` 通过。
- 已检查：`CanvasGIFFrameImportBuilder.swift`、`CanvasEditorSession.swift`、`CanvasGIFFrameImportBuilderTests.swift` 无新增 linter 问题。

