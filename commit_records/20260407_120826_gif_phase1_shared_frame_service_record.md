# 20260407_120826_gif_phase1_shared_frame_service_record

## 记录范围

- 记录内容：新增共享 `CanvasGIFFrameService`，统一处理 GIF 的 `ImageIO` 数据源创建、动画元数据解析、播放元数据回退，以及按帧缩略图 / 全尺寸解码。
- 记录内容：把 `CanvasResolvedImportImage` 的 GIF 首帧解码和元数据提取改成复用共享服务，不再在导入类型里直接维护 GIF 解析细节。
- 记录内容：把 `CanvasGIFPlaybackController` 的 GIF 数据源创建、播放元数据解析和逐帧解码改成复用共享服务，不再在播放控制器里复制一套 `ImageIO` 逻辑。
- 记录内容：新增 `CanvasGIFFrameServiceTests`，覆盖共享服务的元数据读取、按帧解码、缩略图解码与 playback metadata 回退策略。
- 涉及文件：`MyCanvas_Ver_0/Canvas/GIF/CanvasGIFFrameService.swift`
- 涉及文件：`MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasAnimatedImagePlayback.swift`
- 涉及文件：`MyCanvas_Ver_0Tests/CanvasGIFFrameServiceTests.swift`
- 本记录不包含：`CanvasImportRequest` / `CanvasImportLayout` 扩展。
- 本记录不包含：GIF 菜单入口、iOS / macOS 多选帧页面、图板网格排布。
- 本记录不包含：git commit / push。

## 修改一：新增共享 GIF 帧服务，统一 `ImageIO` 解析入口

### 修改前

- shared Canvas 层还没有一个统一的 GIF 帧服务文件。
- GIF 元数据读取和逐帧解码逻辑分别散落在导入层与播放层，后续如果要做“多选帧导入静态图”，还会继续复制第三份逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/GIF/CanvasGIFFrameService.swift
// 类型/函数: 文件级新增前
// 功能说明: 修改前该文件不存在，shared Canvas 层没有统一的 GIF 数据源、元数据和按帧解码服务。
// 无
```

### 修改后

- 新增 `CanvasGIFFrameService`，把 GIF 阶段 1 需要复用的底层能力统一收口到 shared 层。
- 统一暴露：
  - `makeImageSource(from:)`：把 `Data` 转成 `CGImageSource`
  - `animatedMetadata(from:)`：读取帧数、每帧延时和循环次数
  - `playbackMetadata(from:importedMetadata:)`：优先使用形状匹配的 imported metadata，不匹配时回退到源 GIF
  - `decodeFrame(at:from:maxPixelSize:)`：按帧索引解码全尺寸图或缩略图

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/GIF/CanvasGIFFrameService.swift
// 类型/函数: CanvasGIFFrameService.makeImageSource(from:) / animatedMetadata(from:) / playbackMetadata(from:importedMetadata:) / decodeFrame(at:from:maxPixelSize:)
// 功能说明: 修改后 shared 层统一承接 GIF 的数据源创建、元数据读取、播放元数据回退和按帧缩略图/全尺寸解码。
enum CanvasGIFFrameService {
    private static let defaultFrameDelay: TimeInterval = 0.1
    private static let minimumAcceptedFrameDelay: TimeInterval = 0.011
    private static let minimumThumbnailPixelSize = 64

    static func makeImageSource(from data: Data) -> CGImageSource? {
        CGImageSourceCreateWithData(data as CFData, nil)
    }

    static func animatedMetadata(
        from imageSource: CGImageSource
    ) -> CanvasAnimatedImageMetadata? {
        let frameCount = CGImageSourceGetCount(imageSource)
        guard frameCount > 1 else {
            return nil
        }

        let frameDelayTimes = (0..<frameCount).map { frameIndex in
            sanitizedFrameDelay(
                forFrameAt: frameIndex,
                imageSource: imageSource
            )
        }
        return CanvasAnimatedImageMetadata(
            frameCount: frameCount,
            frameDelayTimes: frameDelayTimes,
            loopCount: gifLoopCount(from: imageSource)
        )
    }

    static func playbackMetadata(
        from imageSource: CGImageSource,
        importedMetadata: CanvasAnimatedImageMetadata?
    ) -> CanvasAnimatedImageMetadata? {
        let frameCount = CGImageSourceGetCount(imageSource)
        guard frameCount > 1 else {
            return nil
        }

        if let importedMetadata,
           importedMetadata.frameCount == frameCount,
           importedMetadata.frameDelayTimes.count == frameCount
        {
            return importedMetadata
        }

        return animatedMetadata(from: imageSource)
    }

    static func decodeFrame(
        at frameIndex: Int,
        from imageSource: CGImageSource,
        maxPixelSize: Int? = nil
    ) -> CGImage? {
        // 先按需走 thumbnail 解码，选择页后续可以直接复用这条低成本路径。
        if let maxPixelSize, maxPixelSize > 0 {
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: max(
                    maxPixelSize,
                    minimumThumbnailPixelSize
                )
            ]
            if let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                imageSource,
                frameIndex,
                thumbnailOptions as CFDictionary
            ) {
                return thumbnail
            }
        }

        let imageOptions: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateImageAtIndex(
            imageSource,
            frameIndex,
            imageOptions as CFDictionary
        )
    }
}
```

## 修改二：导入层改为复用共享 GIF 服务，不再自管元数据解析

### 修改前

- `CanvasResolvedImportImage.init(data:...)` 自己直接创建 `CGImageSource`、读取首帧、读取 GIF 元数据、按帧遍历 delay。
- 这样一来，导入层对 GIF 的 `ImageIO` 细节有一份自己的实现，和播放层重复。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 类型/函数: CanvasResolvedImportImage.init(data:typeIdentifier:filenameHint:) / animatedMetadata(from:contentType:) / frameDelay(forFrameAt:imageSource:)
// 功能说明: 修改前导入层直接负责创建 GIF 数据源、解首帧、读取动画元数据和遍历每帧 delay。
init?(
    data: Data,
    typeIdentifier: String? = nil,
    filenameHint: String? = nil
) {
    guard
        let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
        let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    else {
        return nil
    }

    let resolvedTypeIdentifier = Self.resolvedTypeIdentifier(
        explicitTypeIdentifier: typeIdentifier,
        imageSource: imageSource
    )
    let contentType = CanvasTypeIdentifierResolver.contentType(
        for: resolvedTypeIdentifier
    )
    let animatedMetadata = Self.animatedMetadata(
        from: imageSource,
        contentType: contentType
    )
    let assetKind: CanvasImageAssetKind =
        contentType?.conforms(to: .gif) == true &&
        animatedMetadata != nil
        ? .animatedGIF
        : .staticImage
}
```

### 修改后

- `CanvasResolvedImportImage` 改为复用 `CanvasGIFFrameService`：
  - 首帧解码走 `decodeFrame(at:from:)`
  - GIF 元数据走 `animatedMetadata(from:)`
- 导入类型只保留“资源种类判定”和“导入源封装”职责，不再直接维护 GIF 帧级解析细节。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 类型/函数: CanvasResolvedImportImage.init(data:typeIdentifier:filenameHint:)
// 功能说明: 修改后导入层只负责判定资源类型与封装导入结果，GIF 的数据源创建、首帧解码和动画元数据读取全部复用共享服务。
init?(
    data: Data,
    typeIdentifier: String? = nil,
    filenameHint: String? = nil
) {
    guard
        let imageSource = CanvasGIFFrameService.makeImageSource(from: data),
        let cgImage = CanvasGIFFrameService.decodeFrame(
            at: 0,
            from: imageSource
        )
    else {
        return nil
    }

    let resolvedTypeIdentifier = Self.resolvedTypeIdentifier(
        explicitTypeIdentifier: typeIdentifier,
        imageSource: imageSource
    )
    let contentType = CanvasTypeIdentifierResolver.contentType(
        for: resolvedTypeIdentifier
    )
    let animatedMetadata = contentType?.conforms(to: .gif) == true
        ? CanvasGIFFrameService.animatedMetadata(from: imageSource)
        : nil
    let assetKind: CanvasImageAssetKind =
        contentType?.conforms(to: .gif) == true &&
        animatedMetadata != nil
        ? .animatedGIF
        : .staticImage
}
```

## 修改三：播放层改为复用共享 GIF 服务，不再自管回退与解码

### 修改前

- `CanvasGIFPlaybackController` 自己直接创建 `CGImageSource`。
- 播放侧自己维护 `makePlaybackMetadata(...)`、`gifLoopCount(...)`、`frameDelay(...)` 和 `decodeFrame(at:)`，与导入层再次重复。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasAnimatedImagePlayback.swift
// 类型/函数: CanvasGIFPlaybackController.init?(source:) / makePlaybackMetadata(...) / decodeFrame(at:)
// 功能说明: 修改前播放层自己创建 GIF 数据源、自己做 imported metadata 回退，并自己按帧解码。
init?(source: CanvasAnimatedImagePlaybackSource) {
    guard
        let imageSource = CGImageSourceCreateWithData(source.data as CFData, nil)
    else {
        return nil
    }

    let frameCount = CGImageSourceGetCount(imageSource)
    guard frameCount > 1 else {
        return nil
    }

    let metadata = Self.makePlaybackMetadata(
        from: source.animatedMetadata,
        imageSource: imageSource,
        frameCount: frameCount
    )
}

private func decodeFrame(at frameIndex: Int) -> CGImage? {
    let options = [
        kCGImageSourceShouldCacheImmediately: true
    ] as CFDictionary
    return CGImageSourceCreateImageAtIndex(
        imageSource,
        frameIndex,
        options
    )
}
```

### 修改后

- `CanvasGIFPlaybackController` 改为复用 `CanvasGIFFrameService`：
  - 数据源创建走 `makeImageSource(from:)`
  - playback metadata 回退走 `playbackMetadata(from:importedMetadata:)`
  - 逐帧解码走 `decodeFrame(at:from:maxPixelSize:)`
- 播放层保留“绑定 layer / tick 推进 / 播放状态机”职责，不再直接实现 `ImageIO` 解析细节。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasAnimatedImagePlayback.swift
// 类型/函数: CanvasGIFPlaybackController.init?(source:) / decodeFrame(at:)
// 功能说明: 修改后播放层只负责播放状态推进，GIF 数据源创建、播放元数据回退和按帧解码全部复用共享服务。
init?(source: CanvasAnimatedImagePlaybackSource) {
    guard
        let imageSource = CanvasGIFFrameService.makeImageSource(
            from: source.data
        ),
        let metadata = CanvasGIFFrameService.playbackMetadata(
            from: imageSource,
            importedMetadata: source.animatedMetadata
        )
    else {
        return nil
    }

    assetReference = source.assetReference
    self.imageSource = imageSource
    self.frameCount = metadata.frameCount
    self.frameDelayTimes = metadata.frameDelayTimes
    self.loopCount = metadata.loopCount
}

private func decodeFrame(at frameIndex: Int) -> CGImage? {
    CanvasGIFFrameService.decodeFrame(
        at: frameIndex,
        from: imageSource,
        maxPixelSize: nil
    )
}
```

## 修改四：新增针对共享 GIF 服务的阶段 1 单测

### 修改前

- 测试目标里还没有专门覆盖 GIF shared frame service 的测试文件。
- 即使后续 UI 开始依赖“按帧缩略图 / 全尺寸解码”，也没有针对共享层能力的最小保障。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasGIFFrameServiceTests.swift
// 类型/函数: 文件级新增前
// 功能说明: 修改前该文件不存在，项目里没有针对共享 GIF 帧服务的单元测试。
// 无
```

### 修改后

- 新增 `CanvasGIFFrameServiceTests`，覆盖阶段 1 的 shared GIF 能力：
  - 读取动画元数据
  - 按帧返回正确颜色帧
  - 按需生成缩略图
  - playback metadata 优先使用 imported metadata / 不匹配时回退
- 测试里同时补了一个最小 GIF 生成辅助，避免依赖外部资源文件。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasGIFFrameServiceTests.swift
// 类型/函数: testAnimatedMetadataReadsFrameCountDelayTimesAndLoopCount / testDecodeFrameReturnsRequestedFrame / testDecodeFrameThumbnailUsesRequestedMaxPixelSize / testPlaybackMetadataPrefersImportedMetadataWhenShapeMatches / testPlaybackMetadataFallsBackWhenImportedMetadataShapeMismatches
// 功能说明: 修改后用聚焦单测验证共享 GIF 服务的元数据解析、按帧解码、缩略图解码和播放元数据回退规则。
final class CanvasGIFFrameServiceTests: XCTestCase {
    func testAnimatedMetadataReadsFrameCountDelayTimesAndLoopCount() throws {
        let gifData = try makeGIFData(
            frames: [
                GIFFrameSpec(
                    image: try makeSolidColorImage(
                        red: 1,
                        green: 0,
                        blue: 0
                    ),
                    delayTime: 0.2
                ),
                GIFFrameSpec(
                    image: try makeSolidColorImage(
                        red: 0,
                        green: 0,
                        blue: 1
                    ),
                    delayTime: 0.05
                )
            ],
            loopCount: 2
        )

        let imageSource = try XCTUnwrap(
            CanvasGIFFrameService.makeImageSource(from: gifData)
        )
        let metadata = try XCTUnwrap(
            CanvasGIFFrameService.animatedMetadata(from: imageSource)
        )

        XCTAssertEqual(metadata.frameCount, 2)
        XCTAssertEqual(metadata.frameDelayTimes.count, 2)
        XCTAssertEqual(metadata.loopCount, 2)
    }

    func testDecodeFrameThumbnailUsesRequestedMaxPixelSize() throws {
        let imageSource = try XCTUnwrap(
            CanvasGIFFrameService.makeImageSource(from: gifData)
        )
        let thumbnailFrame = try XCTUnwrap(
            CanvasGIFFrameService.decodeFrame(
                at: 1,
                from: imageSource,
                maxPixelSize: 80
            )
        )

        XCTAssertLessThanOrEqual(
            max(thumbnailFrame.width, thumbnailFrame.height),
            80
        )
    }
}
```

## 验证情况

- 已检查本次涉及文件的 IDE lints，未发现新增问题。
- 已执行 `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" test -only-testing:"MyCanvas_Ver_0Tests/CanvasGIFFrameServiceTests"`，测试通过。
