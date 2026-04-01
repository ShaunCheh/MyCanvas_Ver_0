# 20260401_162901_video_validation_phase9_record

## 记录范围

- 记录内容：为工程补齐阶段 9 所需的 macOS 单元测试 target、`Frameworks` 分组与共享 scheme。
- 记录内容：新增 `BoardVideoStorageTests`，覆盖视频 poster 元数据映射、双资产 save/load/cleanup、poster 变更后的持久化缩略图刷新，以及 board list poster 解析。
- 记录内容：根据真实 `xcodebuild` 结果修复 5 个编译兼容问题，打通 macOS 测试与 iOS Simulator 构建。
- 涉及文件：`MyCanvas_Ver_0.xcodeproj/project.pbxproj`
- 涉及文件：`MyCanvas_Ver_0.xcodeproj/xcshareddata/xcschemes/MyCanvas_Ver_0.xcscheme`
- 涉及文件：`MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift`
- 涉及文件：`MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift`
- 涉及文件：`MyCanvas_Ver_0/Canvas/Import/CanvasMediaImportService.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift`
- 本记录不包含：git commit / push。
- 本记录不包含：Swift 6 actor-isolation warning 清理。

## 修改一：Xcode 工程补齐测试 target 与 `Frameworks` 分组

### 修改前

- 工程只有应用 target 和应用 product。
- 工程根分组里没有 `Frameworks` 分组，也没有 `MyCanvas_Ver_0Tests` 的 product / target / build settings。

```text
/* 文件路径: MyCanvas_Ver_0.xcodeproj/project.pbxproj */
/* 类型/函数: PBXGroup / PBXNativeTarget / PBXProject */
/* 功能说明: 修改前工程只声明应用目标，没有可运行的测试 bundle，也没有显式的 Frameworks 分组。 */
		2861054F2F4C51A4005B952A = {
			isa = PBXGroup;
			children = (
				2861055A2F4C51A4005B952A /* MyCanvas_Ver_0 */,
				286105592F4C51A4005B952A /* Products */,
			);
			sourceTree = "<group>";
		};
		286105592F4C51A4005B952A /* Products */ = {
			isa = PBXGroup;
			children = (
				286105582F4C51A4005B952A /* MyCanvas_Ver_0.app */,
			);
			name = Products;
			sourceTree = "<group>";
		};
		286105572F4C51A4005B952A /* MyCanvas_Ver_0 */ = {
			isa = PBXNativeTarget;
			name = MyCanvas_Ver_0;
			productReference = 286105582F4C51A4005B952A /* MyCanvas_Ver_0.app */;
			productType = "com.apple.product-type.application";
		};
		targets = (
			286105572F4C51A4005B952A /* MyCanvas_Ver_0 */,
		);
```

### 修改后

- `project.pbxproj` 新增 `MyCanvas_Ver_0Tests.xctest`、`XCTest.framework`、`MyCanvas_Ver_0Tests` root group、test target、target dependency 和 macOS 测试 build settings。
- `Recovered References` 被改回正常的 `Frameworks` 分组，`XCTest.framework` 不再悬空显示。

```text
/* 文件路径: MyCanvas_Ver_0.xcodeproj/project.pbxproj */
/* 类型/函数: PBXFileReference / PBXGroup / PBXNativeTarget / PBXProject */
/* 功能说明: 修改后工程显式接入测试 bundle、XCTest.framework 与测试 target，CLI 和 Xcode 都能稳定识别阶段 9 的测试入口。 */
		9A9B9C012F600001005B952A /* MyCanvas_Ver_0Tests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = MyCanvas_Ver_0Tests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
		9A9B9C022F600001005B952A /* XCTest.framework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = XCTest.framework; path = Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework; sourceTree = DEVELOPER_DIR; };
		9A9B9C042F600001005B952A /* MyCanvas_Ver_0Tests */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = MyCanvas_Ver_0Tests;
			sourceTree = "<group>";
		};
		28BA821A2F7D0526004BBBD4 /* Frameworks */ = {
			isa = PBXGroup;
			children = (
				9A9B9C022F600001005B952A /* XCTest.framework */,
			);
			name = Frameworks;
			sourceTree = "<group>";
		};
		9A9B9C052F600001005B952A /* MyCanvas_Ver_0Tests */ = {
			isa = PBXNativeTarget;
			buildPhases = (
				9A9B9C082F600001005B952A /* Sources */,
				9A9B9C062F600001005B952A /* Frameworks */,
				9A9B9C072F600001005B952A /* Resources */,
			);
			dependencies = (
				9A9B9C0A2F600001005B952A /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				9A9B9C042F600001005B952A /* MyCanvas_Ver_0Tests */,
			);
			name = MyCanvas_Ver_0Tests;
			productReference = 9A9B9C012F600001005B952A /* MyCanvas_Ver_0Tests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		};
		targets = (
			286105572F4C51A4005B952A /* MyCanvas_Ver_0 */,
			9A9B9C052F600001005B952A /* MyCanvas_Ver_0Tests */,
		);
```

```text
/* 文件路径: MyCanvas_Ver_0.xcodeproj/project.pbxproj */
/* 类型/函数: XCBuildConfiguration(Debug/Release) */
/* 功能说明: 修改后测试 target 固定为 macOS 单元测试配置，通过 TEST_HOST 与 BUNDLE_LOADER 挂到应用程序产物之上。 */
		9A9B9C0B2F600001005B952A /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				ENABLE_TESTING_SEARCH_PATHS = YES;
				MACOSX_DEPLOYMENT_TARGET = 12.4;
				PRODUCT_BUNDLE_IDENTIFIER = "shaunyu.MyCanvas-Ver-0Tests";
				SDKROOT = macosx;
				SUPPORTED_PLATFORMS = macosx;
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/MyCanvas_Ver_0.app/Contents/MacOS/MyCanvas_Ver_0";
				TEST_TARGET_NAME = MyCanvas_Ver_0;
			};
			name = Debug;
		};
```

## 修改二：新增共享 scheme，使 `xcodebuild` 能稳定看到测试入口

### 修改前

- 仓库内没有共享的 `MyCanvas_Ver_0.xcscheme`。
- 阶段 9 的 CLI 测试入口无法随仓库一起落地。

```xml
<!-- 文件路径: MyCanvas_Ver_0.xcodeproj/xcshareddata/xcschemes/MyCanvas_Ver_0.xcscheme -->
<!-- 类型/函数: 文件不存在 -->
<!-- 功能说明: 修改前工程内没有 shared scheme，测试入口不受版本控制。 -->
```

### 修改后

- Shared scheme 同时构建应用 target 和测试 target。
- `TestAction` 明确把 `MyCanvas_Ver_0Tests.xctest` 接到 `MyCanvas_Ver_0` 的宏展开之下。

```xml
<!-- 文件路径: MyCanvas_Ver_0.xcodeproj/xcshareddata/xcschemes/MyCanvas_Ver_0.xcscheme -->
<!-- 类型/函数: Scheme / BuildAction / TestAction -->
<!-- 功能说明: 修改后 shared scheme 将应用与测试入口一起纳入版本控制，xcodebuild -list 与 xcodebuild test 都能直接使用。 -->
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2610"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "286105572F4C51A4005B952A"
               BuildableName = "MyCanvas_Ver_0.app"
               BlueprintName = "MyCanvas_Ver_0"
               ReferencedContainer = "container:MyCanvas_Ver_0.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "9A9B9C052F600001005B952A"
               BuildableName = "MyCanvas_Ver_0Tests.xctest"
               BlueprintName = "MyCanvas_Ver_0Tests"
               ReferencedContainer = "container:MyCanvas_Ver_0.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <MacroExpansion>
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "286105572F4C51A4005B952A"
            BuildableName = "MyCanvas_Ver_0.app"
            BlueprintName = "MyCanvas_Ver_0"
            ReferencedContainer = "container:MyCanvas_Ver_0.xcodeproj">
         </BuildableReference>
      </MacroExpansion>
      <Testables>
         <TestableReference
            skipped = "NO"
            parallelizable = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "9A9B9C052F600001005B952A"
               BuildableName = "MyCanvas_Ver_0Tests.xctest"
               BlueprintName = "MyCanvas_Ver_0Tests"
               ReferencedContainer = "container:MyCanvas_Ver_0.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
</Scheme>
```

## 修改三：新增视频存储阶段 9 自动化测试文件

### 修改前

- 工程内没有 `BoardVideoStorageTests.swift`。
- 视频文档映射、双资产持久化、poster 变更后的缩略图刷新，以及 board list poster 解析都没有自动化覆盖。

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift
// 类型/函数: 文件不存在
// 功能说明: 修改前工程内没有阶段 9 的视频存储自动化测试文件，也没有对应的测试辅助搭建逻辑。
```

### 修改后

- 新增 4 个测试方法，覆盖视频素材在 document / store / board list 三层的关键存储链路。
- 辅助方法负责创建临时 board 工作空间、伪造视频文件与 poster PNG，避免测试依赖真实视频素材。

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift
// 类型/函数: BoardVideoStorageTests.testBoardDocumentMapperRoundTripsVideoPosterMetadata() / testBoardStoreSaveLoadAndCleanupPreservesVideoPosterAndSourceAssets() / testBoardStoreRefreshesPersistedThumbnailWhenVideoPosterChanges() / testBoardMediaPosterImageResolverLoadsVideoPosterWithoutReadingVideoBytes()
// 功能说明: 修改后新增阶段 9 的核心存储验证，直接覆盖视频 poster 元数据 round-trip、双资产保存清理、缩略图失效刷新和 poster-only 预览解析。
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MyCanvas_Ver_0

final class BoardVideoStorageTests: XCTestCase {
    func testBoardDocumentMapperRoundTripsVideoPosterMetadata() throws {
        let boardID = UUID()
        let itemID = UUID()
        let posterImage = try makeSolidColorImage(red: 1, green: 0, blue: 0)
        let item = makeVideoItem(
            id: itemID,
            posterAsset: .persistedStaticImage(
                filename: "video-poster.png",
                cgImage: posterImage
            ),
            sourceVideoFilename: "clip.mov",
            posterTimeSeconds: 12.5
        )
        // 验证视频 item 的 poster 文件名、source video 文件名和 poster 时间能否在 document 中往返。
        let document = BoardDocumentMapper.makeDocument(from: makeRuntimeState(
            boardID: boardID,
            now: Date(timeIntervalSince1970: 1_710_000_000),
            item: item
        ))
        let imageRecord = try XCTUnwrap(document.imageItemRecords.first)
        XCTAssertEqual(imageRecord.posterImageFilename, "video-poster.png")
        XCTAssertEqual(imageRecord.sourceVideoFilename, "clip.mov")
        XCTAssertEqual(imageRecord.posterTimeSeconds, 12.5)
    }

    func testBoardStoreSaveLoadAndCleanupPreservesVideoPosterAndSourceAssets() throws { /* ... */ }
    func testBoardStoreRefreshesPersistedThumbnailWhenVideoPosterChanges() throws { /* ... */ }
    func testBoardMediaPosterImageResolverLoadsVideoPosterWithoutReadingVideoBytes() throws { /* ... */ }
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift
// 类型/函数: withTemporaryBoardWorkspace(_:) / makeVideoItem(...) / writeDummyVideoAsset(to:)
// 功能说明: 修改后测试通过临时 board 工作目录和伪造视频/图片素材构造可重复环境，保证清理逻辑和缩略图逻辑都能稳定复现。
private func withTemporaryBoardWorkspace(
    _ body: (URL, UserDefaults) throws -> Void
) throws {
    let fileManager = FileManager.default
    let identifier = UUID().uuidString
    let selectedFolderURL = fileManager.temporaryDirectory.appendingPathComponent(
        "MyCanvasBoardStoreTests-\(identifier)",
        isDirectory: true
    )
    try fileManager.createDirectory(
        at: selectedFolderURL,
        withIntermediateDirectories: true
    )
    // 为测试注入独立 UserDefaults suite 和 folder bookmark，避免污染真实工程数据。
    let suiteName = "MyCanvasBoardStoreTests.\(identifier)"
    guard let userDefaults = UserDefaults(suiteName: suiteName) else {
        XCTFail("Failed to create isolated UserDefaults suite.")
        return
    }
    let bookmarkData = try selectedFolderURL.bookmarkData(
        options: bookmarkCreationOptions(),
        includingResourceValuesForKeys: nil,
        relativeTo: nil
    )
    FolderBookmarkStore.save(bookmarkData, userDefaults: userDefaults)
    defer {
        userDefaults.removePersistentDomain(forName: suiteName)
        try? fileManager.removeItem(at: selectedFolderURL)
    }
    try body(selectedFolderURL, userDefaults)
}
```

## 修改四：根据真实 `xcodebuild` 结果修复返回值与类型推断问题

### 修改前

- `CanvasImageItem.duplicated(offsetInWorld:)` 末尾直接写表达式，在当前构建链路下会报缺失 `return`。
- `CanvasMediaImportService.makeImportRequest(...)` 中的 `compactMap` 依赖隐式类型推断，当前工具链无法推断 `URL` 结果类型。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 类型/函数: CanvasImageItem.duplicated(offsetInWorld:)
// 功能说明: 修改前视频 item 的复制逻辑构造了新对象，但没有显式 return，xcodebuild 会在当前配置下报缺失返回值。
func duplicated(offsetInWorld: CGPoint) -> CanvasImageItem {
    let duplicatedAsset: CanvasImageAsset
    if isVideo {
        duplicatedAsset = CanvasImageAsset.transientStaticImage(
            cgImage: asset.posterCGImage,
            logicalPixelSize: asset.logicalPixelSize
        )
    } else {
        duplicatedAsset = asset
    }

    CanvasImageItem(
        asset: duplicatedAsset,
        videoSource: videoSource,
        posterTimeSeconds: posterTimeSeconds,
        center: CGPoint(
            x: center.x + offsetInWorld.x,
            y: center.y + offsetInWorld.y
        ),
        size: size,
        zIndex: zIndex,
        cropRectNormalized: cropRectNormalized,
        rotationRadians: rotationRadians
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasMediaImportService.swift
// 类型/函数: CanvasMediaImportService.makeImportRequest(from:boardID:)
// 功能说明: 修改前待删除临时视频 URL 的 compactMap 完全依赖闭包推断，当前工具链会报 ElementOfResult 无法推导。
let temporaryVideoURLsToDelete = transferRequest.items.compactMap { item in
    guard case let .video(video) = item,
          video.source.shouldDeleteAfterImport
    else {
        return nil
    }

    return video.source.localFileURL
}
```

### 修改后

- `duplicated(offsetInWorld:)` 明确 `return CanvasImageItem(...)`。
- `temporaryVideoURLsToDelete` 明确声明为 `[URL]`，并给闭包返回值补上 `URL?`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 类型/函数: CanvasImageItem.duplicated(offsetInWorld:)
// 功能说明: 修改后复制逻辑显式返回新建的 CanvasImageItem，确保视频 item 的 poster 独立复制路径可以稳定通过编译。
func duplicated(offsetInWorld: CGPoint) -> CanvasImageItem {
    let duplicatedAsset: CanvasImageAsset
    if isVideo {
        duplicatedAsset = CanvasImageAsset.transientStaticImage(
            cgImage: asset.posterCGImage,
            logicalPixelSize: asset.logicalPixelSize
        )
    } else {
        duplicatedAsset = asset
    }

    return CanvasImageItem(
        asset: duplicatedAsset,
        videoSource: videoSource,
        posterTimeSeconds: posterTimeSeconds,
        center: CGPoint(
            x: center.x + offsetInWorld.x,
            y: center.y + offsetInWorld.y
        ),
        size: size,
        zIndex: zIndex,
        cropRectNormalized: cropRectNormalized,
        rotationRadians: rotationRadians
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasMediaImportService.swift
// 类型/函数: CanvasMediaImportService.makeImportRequest(from:boardID:)
// 功能说明: 修改后临时视频清理列表显式声明为 URL 数组，避免 Swift 在 compactMap 闭包上丢失结果类型。
let temporaryVideoURLsToDelete: [URL] = transferRequest.items.compactMap {
    item -> URL? in
    guard case let .video(video) = item,
          video.source.shouldDeleteAfterImport
    else {
        return nil
    }

    return video.source.localFileURL
}
```

## 修改五：修复 macOS 视频编辑页在新 SDK 下暴露的 API 兼容问题

### 修改前

- `NSCollectionView.selectItems` 使用了旧调用形式，少了 `at:` 参数标签。
- `presentedViewControllers` 直接当成非可选数组访问 `isEmpty`，当前 SDK 下会报可选展开错误。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: macOSVideoDisplayFrameEditorViewController.updateSelectedPreviewFrameIndex(for:shouldScrollToSelection:)
// 功能说明: 修改前帧条选中状态同步调用了旧的 selectItems 形式，在当前 AppKit SDK 下会触发参数标签错误。
previewStripCollectionView.selectItems(
    Set([indexPath]),
    scrollPosition: scrollPosition
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 类型/函数: macOSViewController.presentVideoDisplayFrameEditor(for:)
// 功能说明: 修改前直接访问 presentedViewControllers.isEmpty，当前 SDK 将该属性视为可选数组，需要先做判空。
private func presentVideoDisplayFrameEditor(for itemID: CanvasItemID) {
    guard presentedViewControllers.isEmpty else {
        return
    }
    // ...
}
```

### 修改后

- 帧条选中 API 改为 `selectItems(at:scrollPosition:)`。
- 打开视频展示画面编辑页前先以可选方式判断 `presentedViewControllers` 是否为空。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: macOSVideoDisplayFrameEditorViewController.updateSelectedPreviewFrameIndex(for:shouldScrollToSelection:)
// 功能说明: 修改后使用当前 AppKit 要求的 at: 参数标签，保证帧条高亮同步和滚动定位都能正常编译执行。
let indexPath = IndexPath(item: nextIndex, section: 0)
let scrollPosition: NSCollectionView.ScrollPosition = shouldScrollToSelection
    ? [.centeredHorizontally]
    : []
previewStripCollectionView.selectItems(
    at: Set([indexPath]),
    scrollPosition: scrollPosition
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 类型/函数: macOSViewController.presentVideoDisplayFrameEditor(for:)
// 功能说明: 修改后兼容当前 SDK 对 presentedViewControllers 的可选声明，避免尚未展示 sheet 时出现可选访问报错。
private func presentVideoDisplayFrameEditor(for itemID: CanvasItemID) {
    guard presentedViewControllers?.isEmpty != false else {
        return
    }

    do {
        let editorContext = try editorSession.videoEditorContext(for: itemID)
        // ...
    }
}
```

## 修改六：修复 iOS 视频编辑页的同名参数遮蔽问题

### 修改前

- `seekPreview(..., pausePlayback: Bool, ...)` 的布尔参数和实例方法 `pausePlayback()` 同名。
- 条件分支里直接调用 `pausePlayback()` 时，编译器会把它当成 `Bool` 值而不是方法。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: iOSVideoDisplayFrameEditorViewController.seekPreview(to:pausePlayback:updateSlider:updateSelection:)
// 功能说明: 修改前 pausePlayback 布尔参数遮蔽了同名实例方法，调用时会报 “Cannot call value of non-function type 'Bool'”。
private func seekPreview(
    to timeSeconds: Double,
    pausePlayback: Bool,
    updateSlider: Bool,
    updateSelection: Bool
) {
    let clampedTimeSeconds = clampedTimeSeconds(timeSeconds)
    if pausePlayback {
        pausePlayback()
    }
    currentTimeSecondsDidChange(
        clampedTimeSeconds,
        updateSlider: updateSlider,
        updateSelection: updateSelection
    )
}
```

### 修改后

- 通过 `self.pausePlayback()` 显式指向实例方法，保留现有参数命名并消除命名遮蔽造成的编译错误。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: iOSVideoDisplayFrameEditorViewController.seekPreview(to:pausePlayback:updateSlider:updateSelection:)
// 功能说明: 修改后显式调用控制器实例方法，避免布尔参数与方法同名时的调用歧义。
private func seekPreview(
    to timeSeconds: Double,
    pausePlayback: Bool,
    updateSlider: Bool,
    updateSelection: Bool
) {
    let clampedTimeSeconds = clampedTimeSeconds(timeSeconds)
    if pausePlayback {
        self.pausePlayback()
    }
    currentTimeSecondsDidChange(
        clampedTimeSeconds,
        updateSlider: updateSlider,
        updateSelection: updateSelection
    )
}
```

## 验证结果

- `xcodebuild -list -project "MyCanvas_Ver_0.xcodeproj"` 已识别 `MyCanvas_Ver_0Tests` target 和 `MyCanvas_Ver_0` shared scheme。
- `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -derivedDataPath "/tmp/MyCanvas_Ver_0-phase9-run3"` 通过。
- `BoardVideoStorageTests` 的 4 个测试全部通过：
- `testBoardDocumentMapperRoundTripsVideoPosterMetadata()`
- `testBoardMediaPosterImageResolverLoadsVideoPosterWithoutReadingVideoBytes()`
- `testBoardStoreRefreshesPersistedThumbnailWhenVideoPosterChanges()`
- `testBoardStoreSaveLoadAndCleanupPreservesVideoPosterAndSourceAssets()`
- `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS Simulator" -derivedDataPath "/tmp/MyCanvas_Ver_0-ios-fix-check"` 通过。
- 验证阶段一度将 `DerivedData` 放在工程目录内 `.cursor` 路径，因项目位于 iCloud Drive 导致生成物带有 `com.apple.provenance` 扩展属性，`CodeSign` 被拒；最终验证切换为 `/tmp` 本地 `DerivedData` 路径完成。
