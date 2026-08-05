# 20260805_152359_batch_import_grid_phase6_platform_entry_regression_record

## 记录范围

本记录如实对应 `batch import grid` 计划的阶段 6：回归 iOS、macOS 和分享扩展的媒体导入入口，确认普通导入继续进入 `.automatic`，同时保证 GIF 帧显式 `.grid` 与程序化 `.diagonal` 不受默认策略影响。

本阶段实际修改：

- 新增 `CanvasTransferImportPipelineTests.swift`。
- 新增 `macOSCanvasImportAdapterTests.swift`。
- 新增 `CanvasPlatformImportSourceContractTests.swift`。
- 使用真实 PNG、animated GIF 和 H.264 MOV fixture 回归 macOS adapter。
- 验证 URL、pasteboard、import service、command lowerer 和 session 的完整数据流。
- 通过源码契约测试保护当前 macOS-only XCTest target 无法直接执行的 iOS 和分享扩展入口 wiring。
- 没有修改 production Swift 代码。

本记录参考了创建记录前的 `git status --short`、三个新增文件的 `git diff --no-index`、当前 changes、差异统计、IDE lint 结果和最终测试输出。下文不粘贴原始 diff，而是根据实际代码整理修改前后的情况。

## 时间戳来源

文件名前缀和本文标题中的时间戳由系统 `date` 命令生成。

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：生成“年月日_时分秒”格式的阶段 6 记录时间戳。
date "+%Y%m%d_%H%M%S"
```

命令实际输出：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# date 命令实际输出
20260805_152359
```

记录文件名：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0/commit_records
# 功能注释：使用“年月日_时分秒_其他部分”格式命名阶段 6 修改记录。
20260805_152359_batch_import_grid_phase6_platform_entry_regression_record.md
```

## 创建记录前的当前 changes

`git status --short` 的实际结果：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# git status --short 的实际输出
?? MyCanvas_Ver_0Tests/CanvasPlatformImportSourceContractTests.swift
?? MyCanvas_Ver_0Tests/CanvasTransferImportPipelineTests.swift
?? MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests.swift
```

三个新增文件的独立统计：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：阶段 6 新增共享导入流水线测试。
 .../CanvasTransferImportPipelineTests.swift        | 251 +++++++++++++++++++++
 1 file changed, 251 insertions(+)
```

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：阶段 6 新增 macOS 平台 adapter、pasteboard 和真实媒体 fixture 测试。
 .../macOSCanvasImportAdapterTests.swift            | 653 +++++++++++++++++++++
 1 file changed, 653 insertions(+)
```

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：阶段 6 新增 iOS、macOS、分享扩展和 GIF 的入口源码契约测试。
 .../CanvasPlatformImportSourceContractTests.swift  | 251 +++++++++++++++++++++
 1 file changed, 251 insertions(+)
```

本阶段共新增 1155 行测试代码，没有 production file diff。

## 阶段 6 的测试分层

当前 `MyCanvas_Ver_0Tests` target 的 `SDKROOT` 和 `SUPPORTED_PLATFORMS` 都是 macOS，因此阶段 6 分成三层：

1. 共享运行时流水线：直接运行 `CanvasTransferRequest → CanvasMediaImportService → CanvasTransferCommandLowerer → CanvasCommandExecutor → CanvasEditorSession`。
2. macOS 平台运行时：直接执行 URL adapter、pasteboard adapter、paste payload resolver，并使用真实图片、视频和 GIF。
3. iOS、macOS controller 和分享扩展 wiring：读取源码并验证入口仍调用 adapter/import service，普通入口没有私自切换为 `.grid` 或 `.diagonal`。

iOS 模拟器构建、分享扩展 target 构建和双端 product build 按计划属于阶段 7，本阶段没有把源码契约测试描述成 iOS 运行时测试。

## 修改一：新增共享 Transfer 到 Session 流水线测试

### 修改前

阶段 5 已分别覆盖 solver 和 session placement，但没有一个测试从普通平台请求的 `CanvasTransferRequest` 默认值开始，连续经过：

- `CanvasMediaImportService`
- `CanvasTransferCommandLowerer`
- `CanvasCommandExecutor`
- `CanvasEditorSession`

因此 adapter 即使生成 `.automatic`，中间层是否持续保留 placement、layout 和 source description 仍缺少完整闭环。

```swift
// MyCanvas_Ver_0Tests/CanvasTransferImportPipelineTests.swift
// 测试类：CanvasTransferImportPipelineTests
// 功能注释：修改前该文件和测试类均不存在。
```

### 修改后：普通单项和五项保持 automatic

新增 `testOrdinaryImageTransferDefaultsRemainAutomaticThroughSession()`：

- 使用默认 initializer 构造 `CanvasTransferRequest`。
- 分别输入 1 项和 5 项。
- 请求层断言 `.cameraCenter + .automatic`。
- import service 层断言 items、placement、layout 和 source description 不变。
- lowerer 层断言命令仍携带同一个 automatic request contract。
- command executor 真正执行到 session。
- 单项最终中心等于 camera center。
- 五项最终形成固定 4 列、第二行从 column 0 开始的居中网格。

```swift
// MyCanvas_Ver_0Tests/CanvasTransferImportPipelineTests.swift
// 函数名：testOrdinaryImageTransferDefaultsRemainAutomaticThroughSession()
// 功能注释：从普通平台 transfer request 的默认值开始，验证 automatic 一直保留到 session solver。
for itemCount in [1, 5] {
    let sourceDescription = "ordinary platform batch \(itemCount)"
    let transferRequest = CanvasTransferRequest(
        images: Array(repeating: image, count: itemCount),
        sourceDescription: sourceDescription
    )

    XCTAssertEqual(transferRequest.placement, .cameraCenter)
    XCTAssertEqual(transferRequest.layout, .automatic)

    let importRequest = try XCTUnwrap(
        CanvasMediaImportService.makeImportRequest(
            from: transferRequest
        )
    )
    XCTAssertEqual(importRequest.items.count, itemCount)
    XCTAssertEqual(importRequest.placement, .cameraCenter)
    XCTAssertEqual(importRequest.layout, .automatic)
    XCTAssertEqual(
        importRequest.sourceDescription,
        sourceDescription
    )
}
```

lowerer 和 command executor 闭环：

```swift
// MyCanvas_Ver_0Tests/CanvasTransferImportPipelineTests.swift
// 函数名：testOrdinaryImageTransferDefaultsRemainAutomaticThroughSession()
// 功能注释：验证 import request 被降级为 importMedia command，并真正进入 session 落板。
let command = try XCTUnwrap(
    CanvasTransferCommandLowerer.loweredCommand(
        for: importRequest
    )
)
guard case let .importMedia(loweredRequest) = command else {
    return XCTFail("Expected importMedia command.")
}
XCTAssertEqual(loweredRequest.placement, .cameraCenter)
XCTAssertEqual(loweredRequest.layout, .automatic)

let session = makeTransferPipelineTestSession()
session.camera = CanvasCamera(
    center: cameraCenter,
    zoomScale: 2,
    viewportSize: CGSize(width: 1000, height: 700)
)
let executor = CanvasCommandExecutor(session: session)
CanvasTransferImportPipelineTestRetainer.executors.append(executor)
XCTAssertNotNil(executor.execute(command))
```

五项 automatic 的最终断言不是只检查模式枚举，而是检查实际 cell：

```swift
// MyCanvas_Ver_0Tests/CanvasTransferImportPipelineTests.swift
// 函数名：assertTransferPipelineFourColumnGrid(_:centeredAt:file:line:)
// 功能注释：验证前四项同一行、第五项进入第二行，并且完整网格以 camera center 为中心。
let configuration = CanvasBatchImportLayoutConfiguration.current.grid
let cellWidth = items.map(\.size.width).max() ?? 0
let cellHeight = items.map(\.size.height).max() ?? 0
let horizontalPitch = cellWidth + configuration.horizontalSpacing
let verticalPitch = cellHeight + configuration.verticalSpacing

XCTAssertEqual(
    items[3].center,
    CGPoint(
        x: items[0].center.x + 3 * horizontalPitch,
        y: items[0].center.y
    )
)
XCTAssertEqual(
    items[4].center,
    CGPoint(
        x: items[0].center.x,
        y: items[0].center.y + verticalPitch
    )
)
XCTAssertEqual(
    (items[0].center.x + items[3].center.x) / 2,
    expectedCenter.x
)
XCTAssertEqual(
    (items[0].center.y + items[4].center.y) / 2,
    expectedCenter.y
)
```

### 修改后：程序化 diagonal 保持独立

新增 `testProgrammaticDiagonalSurvivesTransferServiceAndCommandLane()`：

- 显式传入 `.worldPoint`。
- 显式传入负 x、正 y 的 diagonal step。
- import service 和 command lowerer 都必须原样保留。
- session 最终中心严格为 `placement + index × step`。
- 该测试证明 ordinary automatic 改为 grid 后，没有把程序化 diagonal 一并改成 grid。

```swift
// MyCanvas_Ver_0Tests/CanvasTransferImportPipelineTests.swift
// 函数名：testProgrammaticDiagonalSurvivesTransferServiceAndCommandLane()
// 功能注释：验证程序化 diagonal 从 transfer 到最终落板始终保持显式 step。
let placement = CGPoint(x: 45, y: 75)
let step = CGPoint(x: -14, y: 22)
let transferRequest = CanvasTransferRequest(
    images: Array(repeating: image, count: 3),
    placement: .worldPoint(placement),
    layout: .diagonal(stepInWorld: step),
    sourceDescription: "programmatic diagonal regression"
)

let importRequest = try XCTUnwrap(
    CanvasMediaImportService.makeImportRequest(
        from: transferRequest
    )
)
XCTAssertEqual(
    importRequest.layout,
    .diagonal(stepInWorld: step)
)
```

最终位置断言：

```swift
// MyCanvas_Ver_0Tests/CanvasTransferImportPipelineTests.swift
// 函数名：testProgrammaticDiagonalSurvivesTransferServiceAndCommandLane()
// 功能注释：验证 diagonal 仍使用第一项 placement 和 index × step 公式，不做整组 grid 居中。
XCTAssertEqual(importedItems[0].center, placement)
XCTAssertEqual(
    importedItems[1].center,
    CGPoint(
        x: placement.x + step.x,
        y: placement.y + step.y
    )
)
XCTAssertEqual(
    importedItems[2].center,
    CGPoint(
        x: placement.x + 2 * step.x,
        y: placement.y + 2 * step.y
    )
)
```

## 修改二：新增 macOS Adapter 运行时回归

### 修改前

macOS production 已有：

- Open Panel URL adapter
- Finder/drag pasteboard adapter
- paste payload resolver
- image fallback
- video poster extraction

但测试 target 中没有直接调用 `macOSCanvasImportAdapter` 或 `macOSCanvasPasteboardPayloadResolver` 的测试，也没有真实视频和 animated GIF 输入。

```swift
// MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests.swift
// 测试类：macOSCanvasImportAdapterTests
// 功能注释：修改前该文件和测试类均不存在。
```

### 修改后：Open Panel 等价 URL 输入

新增 `testURLImportsDefaultToAutomaticForSingleMultipleAndMixedMedia()`，使用临时目录创建：

- `static-image.png`
- 两帧 `animated-image.gif`
- 三帧 H.264 `video.mov`

分别验证：

1. 单张图片。
2. 静态图片加 animated GIF。
3. 静态图片、视频、animated GIF 混合。

所有 request 均断言：

- placement 为 `.cameraCenter`
- layout 为 `.automatic`
- source description 保持
- item count 保持
- item 顺序保持
- GIF 被识别为 `.animatedGIF`
- 视频被识别为 `.video`

```swift
// MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests.swift
// 函数名：testURLImportsDefaultToAutomaticForSingleMultipleAndMixedMedia()
// 功能注释：以 Open Panel 实际传递的 URL 数组形式验证单项、多图、视频和 GIF 混合。
let mixedRequest = try XCTUnwrap(
    macOSCanvasImportAdapter.transferRequest(
        from: [
            staticImageURL,
            videoURL,
            animatedGIFURL
        ],
        sourceDescription: "open panel mixed media"
    )
)
assertmacOSImportAdapterRequestMetadata(
    mixedRequest,
    itemCount: 3,
    sourceDescription: "open panel mixed media"
)
XCTAssertTrue(mixedRequest.containsVideo)
XCTAssertEqual(
    macOSImportAdapterTestItemKinds(mixedRequest.items),
    [
        .image(.staticImage),
        .video,
        .image(.animatedGIF)
    ]
)
```

通用 request metadata helper：

```swift
// MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests.swift
// 函数名：assertmacOSImportAdapterRequestMetadata(_:itemCount:sourceDescription:file:line:)
// 功能注释：统一锁定普通 macOS 入口的 cameraCenter、automatic、数量和来源描述。
XCTAssertEqual(request.itemCount, itemCount)
XCTAssertEqual(request.placement, .cameraCenter)
XCTAssertEqual(request.layout, .automatic)
XCTAssertEqual(request.sourceDescription, sourceDescription)
```

### 修改后：Finder 拖放和粘贴

新增 `testPasteboardDropAndPasteDefaultToAutomaticLayout()`：

- 使用唯一命名的 `NSPasteboard`，不污染系统 `.general`。
- 将真实 PNG 和 MOV URL 写入 pasteboard。
- 先按 drag/drop 路径直接调用 `macOSCanvasImportAdapter`。
- 再按 paste 路径调用 `macOSCanvasPasteboardPayloadResolver`。
- 两条路径都必须返回 `.automatic` media request，并保持图片、视频顺序。
- 另建 image pasteboard，验证没有 file URL 时的 `NSImage` fallback 仍生成单项 automatic request。

```swift
// MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests.swift
// 函数名：testPasteboardDropAndPasteDefaultToAutomaticLayout()
// 功能注释：同一个文件 pasteboard 分别验证 Finder 拖放 adapter 和粘贴 payload resolver。
let dropRequest = try XCTUnwrap(
    macOSCanvasImportAdapter.transferRequest(
        from: filePasteboard,
        sourceDescription: "drag and drop"
    )
)
assertmacOSImportAdapterRequestMetadata(
    dropRequest,
    itemCount: 2,
    sourceDescription: "drag and drop"
)

let pastePayload = try XCTUnwrap(
    macOSCanvasPasteboardPayloadResolver.resolvedPayload(
        from: filePasteboard,
        sourceDescription: "pasteboard"
    )
)
guard case let .media(pasteRequest) = pastePayload else {
    return XCTFail("Expected media paste payload.")
}
assertmacOSImportAdapterRequestMetadata(
    pasteRequest,
    itemCount: 2,
    sourceDescription: "pasteboard"
)
```

bitmap fallback：

```swift
// MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests.swift
// 函数名：testPasteboardDropAndPasteDefaultToAutomaticLayout()
// 功能注释：验证复制的 NSImage 在没有媒体 file URL 时仍走单图 automatic 导入。
let copiedImage = NSImage(
    cgImage: try makemacOSImportAdapterTestImage(
        red: 0.7,
        green: 0.3,
        blue: 0.1
    ),
    size: NSSize(width: 12, height: 12)
)
XCTAssertTrue(imagePasteboard.writeObjects([copiedImage]))

let copiedImageRequest = try XCTUnwrap(
    macOSCanvasImportAdapter.transferRequest(
        from: imagePasteboard,
        sourceDescription: "copied bitmap"
    )
)
XCTAssertEqual(copiedImageRequest.layout, .automatic)
```

### 修改后：混合媒体经过 Import Service 和 Session

新增 `testMixedAdapterRequestStaysAutomaticThroughImportServiceAndSession()`：

- 创建隔离的临时 board workspace 和 `UserDefaults` suite。
- 写入 folder bookmark，使视频 import service 使用真实 BoardStore assets 路径。
- adapter 输入为 PNG、MOV、GIF。
- `CanvasMediaImportService` 真实复制视频源并生成 poster asset。
- import request 继续保持 `.cameraCenter + .automatic`。
- session 最终落板为图片、视频、GIF，顺序不变。
- GIF 最终仍是 `.animatedGIF`。
- 三项在同一行并以 camera center 为整体中心。
- 逐对检查最终 `worldBounds` 不相交。

```swift
// MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests.swift
// 函数名：testMixedAdapterRequestStaysAutomaticThroughImportServiceAndSession()
// 功能注释：验证真实混合媒体从平台 adapter 经过视频持久化到 session 网格的闭环。
let transferRequest = try XCTUnwrap(
    macOSCanvasImportAdapter.transferRequest(
        from: [imageURL, videoURL, gifURL],
        sourceDescription: "mixed platform pipeline"
    )
)
let importRequest = try XCTUnwrap(
    CanvasMediaImportService.makeImportRequest(
        from: transferRequest,
        boardID: UUID(),
        userDefaults: userDefaults
    )
)

XCTAssertEqual(importRequest.placement, .cameraCenter)
XCTAssertEqual(importRequest.layout, .automatic)
XCTAssertEqual(importRequest.items.count, 3)
```

最终媒体语义与几何：

```swift
// MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests.swift
// 函数名：testMixedAdapterRequestStaysAutomaticThroughImportServiceAndSession()
// 功能注释：验证图片、视频、GIF 身份和顺序，并检查完整单行网格中心。
XCTAssertEqual(
    importedItems.map(\.isVideo),
    [false, true, false]
)
XCTAssertNotNil(importedItems[1].sourceVideoFilename)
XCTAssertEqual(
    importedItems.map(\.assetKind),
    [.staticImage, .staticImage, .animatedGIF]
)
XCTAssertTrue(
    importedItems.allSatisfy {
        $0.center.y == cameraCenter.y
    }
)
XCTAssertEqual(
    (firstImportedItem.center.x + lastImportedItem.center.x) / 2,
    cameraCenter.x
)
assertmacOSImportAdapterItemsDoNotOverlap(importedItems)
```

### 修改后：macOS Adapter 不覆盖显式 diagonal

新增 `testAdapterPreservesExplicitProgrammaticDiagonalLayout()`，显式传入 `.worldPoint` 和 `.diagonal`，断言 adapter 只解析媒体，不重写程序化布局。

```swift
// MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests.swift
// 函数名：testAdapterPreservesExplicitProgrammaticDiagonalLayout()
// 功能注释：验证普通默认 automatic 与调用者显式 diagonal 是两条独立语义。
let request = try XCTUnwrap(
    macOSCanvasImportAdapter.transferRequest(
        from: [imageURL, imageURL, imageURL],
        sourceDescription: "programmatic diagonal",
        placement: .worldPoint(placement),
        layout: .diagonal(stepInWorld: step)
    )
)

XCTAssertEqual(request.itemCount, 3)
XCTAssertEqual(
    request.placement,
    .worldPoint(placement)
)
XCTAssertEqual(
    request.layout,
    .diagonal(stepInWorld: step)
)
```

## 真实媒体 Fixtures

### PNG 和 GIF

PNG 使用 `CGImageDestination` 写入真实 `.png` 文件。

animated GIF 使用两个不同颜色的 frame、loop count 0 和 frame delay 0.1 秒，确保 adapter 和 `CanvasResolvedImportImage` 实际识别 animated metadata，而不是只依赖 `.gif` 扩展名。

```swift
// MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests.swift
// 函数名：writemacOSImportAdapterTestGIF(to:)
// 功能注释：生成两帧 animated GIF，供普通文件导入和混合媒体回归使用。
let frameProperties = [
    kCGImagePropertyGIFDictionary as String: [
        kCGImagePropertyGIFDelayTime as String: 0.1
    ]
] as CFDictionary
CGImageDestinationAddImage(
    destination,
    try makemacOSImportAdapterTestImage(
        red: 0.9,
        green: 0.1,
        blue: 0.2
    ),
    frameProperties
)
CGImageDestinationAddImage(
    destination,
    try makemacOSImportAdapterTestImage(
        red: 0.1,
        green: 0.8,
        blue: 0.3
    ),
    frameProperties
)
```

### H.264 MOV

视频 fixture 使用 `AVAssetWriter` 生成三个 `24 × 24` frame：

- codec 为 H.264。
- file type 为 MOV。
- 每帧颜色不同。
- `isReadyForMoreMediaData` 等待带 5 秒 deadline。
- `finishWriting` 等待带 10 秒 timeout。
- 不使用空文件或只伪造扩展名，因此 adapter 会真实调用 poster frame service。

```swift
// MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests.swift
// 函数名：writemacOSImportAdapterTestVideo(to:)
// 功能注释：生成可由 CanvasVideoFrameService 解码的最小真实 MOV。
let writer = try AVAssetWriter(url: videoURL, fileType: .mov)
let input = AVAssetWriterInput(
    mediaType: .video,
    outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: 24,
        AVVideoHeightKey: 24
    ]
)
input.expectsMediaDataInRealTime = false
```

```swift
// MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests.swift
// 函数名：writemacOSImportAdapterTestVideo(to:)
// 功能注释：等待 writer 输入可写并追加三个有确定 presentation time 的 frame。
for frameIndex in 0..<3 {
    let deadline = Date().addingTimeInterval(5)
    while input.isReadyForMoreMediaData == false {
        guard Date() < deadline else {
            throw macOSCanvasImportAdapterTestError.videoInputTimedOut
        }
        Thread.sleep(forTimeInterval: 0.001)
    }

    let pixelBuffer = try makemacOSImportAdapterTestPixelBuffer(
        red: UInt8(70 + frameIndex * 40),
        green: UInt8(120 + frameIndex * 20),
        blue: UInt8(180 - frameIndex * 30)
    )
    guard adaptor.append(
        pixelBuffer,
        withPresentationTime: CMTime(
            value: CMTimeValue(frameIndex),
            timescale: 10
        )
    ) else {
        throw macOSCanvasImportAdapterTestError.failedToAppendVideoFrame
    }
}
```

### 隔离 Workspace

视频 import service 需要 destination board assets directory。测试创建唯一临时目录、唯一 `UserDefaults` suite 和 macOS security-scoped bookmark，结束后清理 suite 与目录。

```swift
// MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests.swift
// 函数名：withmacOSImportAdapterTestBoardWorkspace(_:)
// 功能注释：为真实视频 import service 提供隔离的 BoardStore folder bookmark。
let bookmarkData = try directoryURL.bookmarkData(
    options: [.withSecurityScope],
    includingResourceValuesForKeys: nil,
    relativeTo: nil
)
FolderBookmarkStore.save(
    bookmarkData,
    userDefaults: userDefaults
)
defer {
    userDefaults.removePersistentDomain(forName: suiteName)
}
```

## 修改三：新增平台入口源码契约测试

### 修改前

当前 unit test target 仅支持 macOS，无法直接引用：

- `UIKit`
- `PhotosUI`
- `PHPickerResult`
- `UIDropSession`
- `UIPasteboard`
- 独立分享扩展 target 内部的 `ShareImportViewModel`

修改前没有自动测试保护 iOS controller、iOS adapter 和分享扩展是否仍进入统一 automatic pipeline。

```swift
// MyCanvas_Ver_0Tests/CanvasPlatformImportSourceContractTests.swift
// 测试类：CanvasPlatformImportSourceContractTests
// 功能注释：修改前该文件和源码入口契约测试均不存在。
```

### 源码读取方式

测试使用编译时 `#filePath` 推导 repository root，读取指定 production source。读取后只移除空白字符，使断言不依赖换行和缩进。

```swift
// MyCanvas_Ver_0Tests/CanvasPlatformImportSourceContractTests.swift
// 函数名：normalizedPlatformImportSource(at:)
// 功能注释：从测试源文件位置推导仓库根目录，再读取目标平台入口源码。
let testFileURL = URL(fileURLWithPath: #filePath)
let repositoryRootURL = testFileURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let sourceURL = repositoryRootURL.appendingPathComponent(relativePath)
let source = try String(contentsOf: sourceURL, encoding: .utf8)
return normalizedPlatformImportFragment(source)
```

```swift
// MyCanvas_Ver_0Tests/CanvasPlatformImportSourceContractTests.swift
// 函数名：normalizedPlatformImportFragment(_:)
// 功能注释：移除格式空白，避免仅因 Swift 代码换行或缩进变化导致入口契约失败。
source.replacingOccurrences(
    of: #"\s+"#,
    with: "",
    options: .regularExpression
)
```

### iOS Photo Picker、视频、混合媒体、拖放和粘贴

`testIOSPhotoPickerDropAndPasteRemainAutomaticMediaEntries()` 检查：

- adapter 仍有 PHPicker、UIPasteboard、UIDropSession 三个入口。
- 三个入口的 default layout 都是 `.automatic`。
- item providers 仍按输入顺序逐项 append。
- video type 仍优先解析成 `.video`。
- image/GIF 仍通过 `CanvasResolvedImportImage` 解析。
- adapter 中没有显式 `.diagonal` 或 `.grid`。
- Photo Picker 仍允许 images 和 videos，selection limit 为 0。
- controller 的 photo picker、drag and drop、pasteboard source description 保持存在。
- controller 仍调用 `performTransferRequest`、lowerer 和 import service。

```swift
// MyCanvas_Ver_0Tests/CanvasPlatformImportSourceContractTests.swift
// 函数名：testIOSPhotoPickerDropAndPasteRemainAutomaticMediaEntries()
// 功能注释：保护 iOS 三个普通入口的 automatic 默认值、视频优先解析和 provider 顺序。
assertPlatformImportSource(
    adapterSource,
    contains: [
        "from results: [PHPickerResult]",
        "from pasteboard: UIPasteboard",
        "from dropSession: UIDropSession",
        "for itemProvider in itemProviders",
        "resolvedItems.append(resolvedItem)",
        "preferredVideoTypeIdentifier(from: itemProvider)",
        "return .video(resolvedVideo)",
        "CanvasResolvedImportImage(",
        "return .image(resolvedImage)"
    ]
)
XCTAssertEqual(
    platformImportOccurrenceCount(
        of: "layout: CanvasImportLayout = .automatic",
        in: adapterSource
    ),
    3
)
XCTAssertFalse(adapterSource.contains(".diagonal("))
XCTAssertFalse(adapterSource.contains("layout:.grid("))
```

iOS controller 契约：

```swift
// MyCanvas_Ver_0Tests/CanvasPlatformImportSourceContractTests.swift
// 函数名：testIOSPhotoPickerDropAndPasteRemainAutomaticMediaEntries()
// 功能注释：验证相册、拖放、粘贴仍由平台 controller 进入统一 transfer pipeline。
assertPlatformImportSource(
    controllerSource,
    contains: [
        "configuration.filter = .any(of: [.images, .videos])",
        "configuration.selectionLimit = 0",
        "iOSCanvasImportAdapter.transferRequest",
        "sourceDescription: \"photo picker\"",
        "sourceDescription: \"drag and drop\"",
        "iOSCanvasPasteboardPayloadResolver.resolvedPayload",
        "sourceDescription: \"pasteboard\"",
        "performTransferRequest(transferRequest)",
        "CanvasTransferCommandLowerer.loweredCommand",
        "CanvasMediaImportService.makeImportRequest"
    ]
)
```

### macOS Open Panel、Finder 拖放和粘贴 Wiring

`testMacOSOpenPanelDropAndPasteRemainAutomaticMediaEntries()` 在运行时 adapter 测试之外继续保护 controller wiring：

- Open Panel 仍允许 image 和 movie。
- 仍允许 multiple selection。
- Open Panel 和 drag/drop 仍调用 `macOSCanvasImportAdapter`。
- paste 仍调用 `macOSCanvasPasteboardPayloadResolver`。
- request 仍进入 lowerer 和 import service。
- adapter 的 URL 和 pasteboard 两个入口默认 layout 都是 `.automatic`。

```swift
// MyCanvas_Ver_0Tests/CanvasPlatformImportSourceContractTests.swift
// 函数名：testMacOSOpenPanelDropAndPasteRemainAutomaticMediaEntries()
// 功能注释：保护 macOS controller 到 adapter、lowerer 和 import service 的入口连线。
assertPlatformImportSource(
    controllerSource,
    contains: [
        "openPanel.allowedContentTypes = [.image, .movie]",
        "openPanel.allowsMultipleSelection = true",
        "macOSCanvasImportAdapter.transferRequest",
        "sourceDescription: \"open panel\"",
        "sourceDescription: \"drag and drop\"",
        "macOSCanvasPasteboardPayloadResolver.resolvedPayload",
        "sourceDescription: \"pasteboard\"",
        "performTransferRequest(transferRequest)",
        "CanvasTransferCommandLowerer.loweredCommand",
        "CanvasMediaImportService.makeImportRequest"
    ]
)
```

### 分享扩展

`testShareExtensionUsesAutomaticSharedImportPipeline()` 使用有序 marker 检查：

1. `CanvasTransferRequest` 从 `resolvedImages` 创建。
2. placement 显式为 `.cameraCenter`。
3. layout 显式为 `.automatic`。
4. request 进入 `CanvasMediaImportService`。
5. session append 使用 import request 返回的 items、placement 和 layout。

同时断言分享扩展没有 `.diagonal` 或显式 `.grid`。

```swift
// MyCanvas_Ver_0Tests/CanvasPlatformImportSourceContractTests.swift
// 函数名：testShareExtensionUsesAutomaticSharedImportPipeline()
// 功能注释：验证分享扩展显式使用 automatic，并按顺序进入共享 import service 和 session。
assertPlatformImportSourceInOrder(
    shareSource,
    markers: [
        "let transferRequest = CanvasTransferRequest(",
        "images: resolvedImages",
        "placement: .cameraCenter",
        "layout: .automatic",
        "CanvasMediaImportService.makeImportRequest(",
        "from: transferRequest",
        "session.appendImportedMedia(",
        "importRequest.items",
        "placement: importRequest.placement",
        "layout: importRequest.layout"
    ]
)
XCTAssertFalse(shareSource.contains(".diagonal("))
XCTAssertFalse(shareSource.contains("layout:.grid("))
```

分享扩展多图自动获得 4 列、单图不变的行为由以下两部分共同保护：

- 本源码契约证明分享扩展生成 `.cameraCenter + .automatic` 的 transfer request。
- `CanvasTransferImportPipelineTests` 证明同一共享 service/session 路径下，1 项位于 camera center，5 项形成 4 列网格。

### GIF 帧显式 Grid

`testGIFFramesKeepExplicitGridSeparateFromOrdinaryImports()` 检查：

- `CanvasGIFFrameImportBuilder` 仍使用 `.worldPoint(gridCenter(...))`。
- request layout 仍显式为 `.grid`。
- grid center 仍由 `CanvasImportLayoutSolver` 使用显式 grid 求解。
- iOS adapter、macOS adapter 和分享扩展都没有显式 grid。

```swift
// MyCanvas_Ver_0Tests/CanvasPlatformImportSourceContractTests.swift
// 函数名：testGIFFramesKeepExplicitGridSeparateFromOrdinaryImports()
// 功能注释：验证只有 GIF 帧派生入口使用显式 grid，普通平台入口继续 automatic。
assertPlatformImportSource(
    gifBuilderSource,
    contains: [
        "placement: .worldPoint(",
        "gridCenter(",
        "layout: .grid(",
        "CanvasImportLayoutSolver().resolve(",
        "requestedLayout: .grid("
    ]
)

for source in ordinarySources {
    XCTAssertFalse(source.contains("layout:.grid("))
}
```

## 自动验证

### 阶段 6 新增测试

执行命令：

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：运行共享流水线、macOS adapter 和跨平台入口契约测试。
xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS,arch=arm64" -only-testing:"MyCanvas_Ver_0Tests/CanvasTransferImportPipelineTests" -only-testing:"MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasPlatformImportSourceContractTests"
```

最终实际结果：

- 命令退出码为 `0`。
- `TEST SUCCEEDED`。
- `CanvasTransferImportPipelineTests`：2 个测试通过。
- `macOSCanvasImportAdapterTests`：4 个测试通过。
- `CanvasPlatformImportSourceContractTests`：4 个测试通过。
- 阶段 6 新增测试共 10 个通过。

### 阶段 1 至阶段 6 联合回归

执行命令：

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：联合运行模型、类型解析、solver、session、GIF、共享流水线和平台入口测试。
xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS,arch=arm64" -only-testing:"MyCanvas_Ver_0Tests/CanvasImportRequestModelTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasImportTypeIdentifierResolutionTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasImportLayoutSolverTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasTransferImportPipelineTests" -only-testing:"MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasPlatformImportSourceContractTests"
```

最终实际结果：

- 命令退出码为 `0`。
- `TEST SUCCEEDED`。
- `CanvasImportRequestModelTests`：5 个测试通过。
- `CanvasImportTypeIdentifierResolutionTests`：3 个测试通过。
- `CanvasImportLayoutSolverTests`：5 个测试通过。
- `CanvasImportedMediaPlacementTests`：10 个测试通过。
- `CanvasGIFFrameImportBuilderTests`：5 个测试通过。
- `CanvasTransferImportPipelineTests`：2 个测试通过。
- `macOSCanvasImportAdapterTests`：4 个测试通过。
- `CanvasPlatformImportSourceContractTests`：4 个测试通过。
- 联合回归共 38 个测试通过。

测试输出中的 warning 仅为当前工程既有的 macOS 12.4 deployment target 与较新 XCTest dylib 链接提示，以及没有 AppIntents dependency 时跳过 metadata extraction；没有 Swift 编译 warning 或测试失败。

### IDE lint

检查文件：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：阶段 6 IDE lint 检查范围。
MyCanvas_Ver_0Tests/CanvasTransferImportPipelineTests.swift
MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests.swift
MyCanvas_Ver_0Tests/CanvasPlatformImportSourceContractTests.swift
```

实际结果：`No linter errors found.`。

### 差异格式检查

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：检查当前 tracked diff 是否包含空白错误。
git diff --check
```

实际结果：命令退出码为 `0`，没有输出。三个新增文件均已成功通过 Swift 编译和定向测试。

## 阶段 6 最终覆盖的入口契约

- iOS Photo Picker 继续同时接受图片和视频，并允许多选。
- iOS PHPicker、drop session 和 pasteboard adapter 默认使用 `.automatic`。
- iOS provider 顺序保持，视频优先解析为 video，图片/GIF 解析为 image。
- macOS Open Panel 继续接受 image/movie 并允许多选。
- macOS URL adapter 覆盖单图、多图、真实视频和 animated GIF 混合。
- Finder drag/drop pasteboard 默认使用 `.automatic`。
- macOS paste payload resolver 保持 media 优先。
- 复制位图 fallback 仍是单项 automatic。
- 图片、真实视频、GIF 混合请求经过 import service 后仍为 automatic。
- 分享扩展显式使用 `.cameraCenter + .automatic`。
- 分享扩展共享路径下单图不变，多图使用 4 列网格。
- GIF 帧派生入口继续使用显式 `.grid`。
- 程序化 `.diagonal` 从 adapter/transfer 到最终 session 保持 `index × step`。
- 普通入口没有私自硬编码 `.grid` 或 `.diagonal`。

## 明确未修改的范围

- 未修改 iOS controller。
- 未修改 macOS controller。
- 未修改 iOS/macOS import adapter。
- 未修改 iOS/macOS pasteboard resolver。
- 未修改 `ShareImportViewModel.swift`。
- 未修改 `CanvasMediaImportService.swift`。
- 未修改 `CanvasTransferCommandLowerer.swift`。
- 未修改 `CanvasEditorSession.swift`。
- 未修改 `CanvasImportLayoutSolver.swift`。
- 未修改 GIF builder production 代码。
- 未修改拖放 placement 语义；拖放仍使用 camera center。
- 未修改文档 schema、storage mapper 或 autosave。
- 未修改 `.cursor/plans/batch_import_grid_fc6b804f.plan.md`。
- 未执行阶段 7 的 iOS、macOS、分享扩展完整 product build。

## 当前状态

创建本记录后，预期 `git status --short` 为：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 创建记录后的预期工作区状态
?? MyCanvas_Ver_0Tests/CanvasPlatformImportSourceContractTests.swift
?? MyCanvas_Ver_0Tests/CanvasTransferImportPipelineTests.swift
?? MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests.swift
?? commit_records/20260805_152359_batch_import_grid_phase6_platform_entry_regression_record.md
```

本次没有创建 Git commit，也没有暂存文件。
