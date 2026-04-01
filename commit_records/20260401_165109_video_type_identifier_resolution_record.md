# 20260401_165109_video_type_identifier_resolution_record

## 记录范围

- 记录内容：修复 iOS 导入链路对 `UTType(importedAs:)` 的误用，消除 `public.jpeg`、`public.mpeg-4` 与 Photos 私有 thumbnail 类型触发的 `Info.plist` 声明警告。
- 记录内容：在共享导入模型中新增统一的 type identifier 解析器，将“系统公共类型解析”“Photos 私有类型忽略”“文件扩展名回退”收敛到一个入口。
- 记录内容：新增自动化测试，验证公共 UTI 正常解析、私有 Photos thumbnail 标识被忽略后可回退到真实图片/视频类型。
- 涉及文件：`MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/iOSCanvasImportAdapter.swift`
- 涉及文件：`MyCanvas_Ver_0Tests/CanvasImportTypeIdentifierResolutionTests.swift`
- 本记录不包含：阶段 9 的测试 target / scheme / 存储验证主体改动。
- 本记录不包含：git commit / push。

## 修改一：在共享导入模型中新增统一的 type identifier 解析器

### 修改前

- `CanvasImportedImageSource.contentType`、`CanvasImportedVideoSource.contentType` 直接使用 `UTType(importedAs:)`。
- `CanvasResolvedImportImage` 在构造 `contentType` 时也直接把解析出的 type identifier 送进 `UTType(importedAs:)`。
- 这会把 `public.jpeg`、`public.mpeg-4` 这类系统公共类型，以及 `com.apple.private.photos.thumbnail.*` 这类私有类型，都错误地当成“需要在 app 的 `Info.plist` 中声明 imported type”的类型处理。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 类型/函数: CanvasImportedImageSource.contentType / CanvasImportedVideoSource.contentType / CanvasResolvedImportImage.init(data:typeIdentifier:filenameHint:)
// 功能说明: 修改前共享导入模型直接使用 UTType(importedAs:) 解析外部传入的 type identifier，会把系统公共类型误判为本 app 需要声明的 imported type。
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct CanvasImportedImageSource: Equatable {
    let data: Data
    let typeIdentifier: String?
    let filenameHint: String?

    var contentType: UTType? {
        guard let typeIdentifier else {
            return nil
        }

        return UTType(importedAs: typeIdentifier)
    }
}

struct CanvasImportedVideoSource: Equatable {
    let localFileURL: URL
    let typeIdentifier: String?
    let filenameHint: String?
    let shouldDeleteAfterImport: Bool

    var contentType: UTType? {
        if let typeIdentifier, typeIdentifier.isEmpty == false {
            return UTType(importedAs: typeIdentifier)
        }

        guard localFileURL.pathExtension.isEmpty == false else {
            return nil
        }

        return UTType(filenameExtension: localFileURL.pathExtension)
    }
}

let resolvedTypeIdentifier = Self.resolvedTypeIdentifier(
    explicitTypeIdentifier: typeIdentifier,
    imageSource: imageSource
)
let contentType = resolvedTypeIdentifier.map { UTType(importedAs: $0) }
```

### 修改后

- 新增 `CanvasTypeIdentifierResolver`，统一负责：
- 规范化字符串
- 用 `UTType(identifier)` 解析系统已声明的公共类型
- 忽略 `com.apple.private.photos.thumbnail.*` 这类私有 Photos thumbnail 标识
- 在需要时根据文件扩展名回退到公共类型 identifier
- `CanvasImportedImageSource`、`CanvasImportedVideoSource`、`CanvasResolvedImportImage`、`CanvasResolvedImportVideo` 全部改接这套共享解析路径。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 类型/函数: CanvasTypeIdentifierResolver / CanvasImportedImageSource.contentType / CanvasImportedVideoSource.contentType
// 功能说明: 修改后共享导入模型统一通过 CanvasTypeIdentifierResolver 解析外部 type identifier，避免把系统公共 UTI 错误当成需要在 Info.plist 中声明的 imported type。
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum CanvasTypeIdentifierResolver {
    private static let ignoredIdentifierPrefixes = [
        "com.apple.private.photos.thumbnail."
    ]

    static func contentType(for typeIdentifier: String?) -> UTType? {
        guard let normalizedTypeIdentifier = normalizedTypeIdentifier(typeIdentifier) else {
            return nil
        }
        guard ignoredIdentifierPrefixes.contains(where: normalizedTypeIdentifier.hasPrefix) == false else {
            return nil
        }
        return UTType(normalizedTypeIdentifier)
    }

    static func resolvedIdentifier(
        preferredTypeIdentifier: String?,
        fallbackFilenameExtension: String? = nil
    ) -> String? {
        if let contentType = contentType(for: preferredTypeIdentifier) {
            return contentType.identifier
        }

        guard
            let fallbackFilenameExtension,
            fallbackFilenameExtension.isEmpty == false,
            let contentType = UTType(filenameExtension: fallbackFilenameExtension)
        else {
            return nil
        }

        return contentType.identifier
    }
}

struct CanvasImportedImageSource: Equatable {
    let data: Data
    let typeIdentifier: String?
    let filenameHint: String?

    var contentType: UTType? {
        CanvasTypeIdentifierResolver.contentType(for: typeIdentifier)
    }
}

struct CanvasImportedVideoSource: Equatable {
    let localFileURL: URL
    let typeIdentifier: String?
    let filenameHint: String?
    let shouldDeleteAfterImport: Bool

    var contentType: UTType? {
        if let contentType = CanvasTypeIdentifierResolver.contentType(
            for: typeIdentifier
        ) {
            return contentType
        }

        guard localFileURL.pathExtension.isEmpty == false else {
            return nil
        }

        return UTType(filenameExtension: localFileURL.pathExtension)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 类型/函数: CanvasResolvedImportImage.init(data:typeIdentifier:filenameHint:) / CanvasResolvedImportImage.resolvedTypeIdentifier(...) / CanvasResolvedImportVideo.init(localFileURL:typeIdentifier:filenameHint:shouldDeleteAfterImport:posterTimeSeconds:)
// 功能说明: 修改后图片和视频导入路径都会先做公共类型解析与兜底回退，再把稳定的公开 identifier 写回导入模型。
let resolvedTypeIdentifier = Self.resolvedTypeIdentifier(
    explicitTypeIdentifier: typeIdentifier,
    imageSource: imageSource
)
let contentType = CanvasTypeIdentifierResolver.contentType(
    for: resolvedTypeIdentifier
)

private static func resolvedTypeIdentifier(
    explicitTypeIdentifier: String?,
    imageSource: CGImageSource
) -> String? {
    if let resolvedIdentifier = CanvasTypeIdentifierResolver.resolvedIdentifier(
        preferredTypeIdentifier: explicitTypeIdentifier
    ) {
        return resolvedIdentifier
    }

    let imageSourceTypeIdentifier = CGImageSourceGetType(imageSource) as String?
    return CanvasTypeIdentifierResolver.resolvedIdentifier(
        preferredTypeIdentifier: imageSourceTypeIdentifier
    ) ?? imageSourceTypeIdentifier
}

let resolvedTypeIdentifier = CanvasTypeIdentifierResolver.resolvedIdentifier(
    preferredTypeIdentifier: typeIdentifier,
    fallbackFilenameExtension: localFileURL.pathExtension
)
self.source = CanvasImportedVideoSource(
    localFileURL: localFileURL,
    typeIdentifier: resolvedTypeIdentifier,
    filenameHint: filenameHint,
    shouldDeleteAfterImport: shouldDeleteAfterImport
)
```

## 修改二：iOS 导入适配层改为依赖共享 resolver，不再直接走 `importedAs`

### 修改前

- `preferredOwnedFileExtension(...)`
- `preferredImageTypeIdentifier(from:)`
- `preferredVideoTypeIdentifier(from:)`
- `resolvedFilenameHint(_:typeIdentifier:)`

这些分支都直接调用 `UTType(importedAs:)`。当 `NSItemProvider` 暴露 `public.jpeg`、`public.mpeg-4` 或 `com.apple.private.photos.thumbnail.*` 时，会触发那串 “expected to be declared and imported in the Info.plist” 警告。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSCanvasImportAdapter.swift
// 类型/函数: preferredOwnedFileExtension(...) / preferredImageTypeIdentifier(from:) / preferredVideoTypeIdentifier(from:) / resolvedFilenameHint(_:typeIdentifier:)
// 功能说明: 修改前 iOS 导入适配层在多个入口上都直接使用 UTType(importedAs:) 解析 item provider 的 type identifier，导致系统公共类型和私有 thumbnail 标识都走错了解析语义。
private static func preferredOwnedFileExtension(
    filenameHint: String?,
    typeIdentifier: String,
    fallbackURL: URL
) -> String {
    let contentType = UTType(importedAs: typeIdentifier)
    if let preferredFilenameExtension = contentType
        .preferredFilenameExtension?
        .lowercased(),
       preferredFilenameExtension.isEmpty == false
    {
        return preferredFilenameExtension
    }
    return "mov"
}

private static func preferredImageTypeIdentifier(
    from itemProvider: NSItemProvider
) -> String? {
    let specificImageTypeIdentifier = itemProvider.registeredTypeIdentifiers.first {
        $0 != UTType.image.identifier &&
            UTType(importedAs: $0).conforms(to: .image)
    }
    return specificImageTypeIdentifier
}

private static func preferredVideoTypeIdentifier(
    from itemProvider: NSItemProvider
) -> String? {
    let specificVideoTypeIdentifier = itemProvider.registeredTypeIdentifiers.first {
        let importedType = UTType(importedAs: $0)
        return importedType.conforms(to: .movie) ||
            importedType.conforms(to: .video)
    }
    return specificVideoTypeIdentifier
}

private static func resolvedFilenameHint(
    _ filenameHint: String?,
    typeIdentifier: String
) -> String? {
    if let preferredFilenameExtension = UTType(importedAs: typeIdentifier)
        .preferredFilenameExtension
    {
        return "video.\(preferredFilenameExtension)"
    }
    return filenameHint
}
```

### 修改后

- 这些入口全部改为依赖 `CanvasTypeIdentifierResolver.contentType(for:)`。
- 公共类型会被正常识别，私有 thumbnail 标识会自然被忽略，不再逼着 app 去 `Info.plist` 里声明不存在的 imported type。
- 文件扩展名和文件名 hint 推导也因此回到稳定的公共 UTI 语义上。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSCanvasImportAdapter.swift
// 类型/函数: preferredOwnedFileExtension(...) / preferredImageTypeIdentifier(from:) / preferredVideoTypeIdentifier(from:) / resolvedFilenameHint(_:typeIdentifier:)
// 功能说明: 修改后 iOS 导入适配层统一改用共享 resolver 识别公共 UTI，并跳过 Photos 私有 thumbnail 标识，避免导入链路继续制造 Info.plist 声明警告。
private static func preferredOwnedFileExtension(
    filenameHint: String?,
    typeIdentifier: String,
    fallbackURL: URL
) -> String {
    let contentType = CanvasTypeIdentifierResolver.contentType(
        for: typeIdentifier
    )
    if let preferredFilenameExtension = contentType?
        .preferredFilenameExtension?
        .lowercased(),
       preferredFilenameExtension.isEmpty == false
    {
        return preferredFilenameExtension
    }
    return "mov"
}

private static func preferredImageTypeIdentifier(
    from itemProvider: NSItemProvider
) -> String? {
    let specificImageTypeIdentifier = itemProvider.registeredTypeIdentifiers.first {
        $0 != UTType.image.identifier &&
            CanvasTypeIdentifierResolver.contentType(for: $0)?
            .conforms(to: .image) == true
    }
    return specificImageTypeIdentifier
}

private static func preferredVideoTypeIdentifier(
    from itemProvider: NSItemProvider
) -> String? {
    let specificVideoTypeIdentifier = itemProvider.registeredTypeIdentifiers.first {
        guard let contentType = CanvasTypeIdentifierResolver.contentType(
            for: $0
        ) else {
            return false
        }
        return contentType.conforms(to: .movie) ||
            contentType.conforms(to: .video)
    }
    return specificVideoTypeIdentifier
}

private static func resolvedFilenameHint(
    _ filenameHint: String?,
    typeIdentifier: String
) -> String? {
    if let preferredFilenameExtension = CanvasTypeIdentifierResolver
        .contentType(for: typeIdentifier)?
        .preferredFilenameExtension
    {
        return "video.\(preferredFilenameExtension)"
    }
    return filenameHint
}
```

## 修改三：新增回归测试，锁住公共类型与私有类型的解析边界

### 修改前

- 工程内没有专门验证 type identifier 解析策略的测试。
- 这意味着 `UTType(importedAs:)` 的误用即使被修掉，也没有自动化保障，后续容易再次回归。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasImportTypeIdentifierResolutionTests.swift
// 类型/函数: 文件不存在
// 功能说明: 修改前工程内没有专门验证公共 UTI 解析和私有 Photos thumbnail 类型过滤策略的测试文件。
// 文件不存在。
```

### 修改后

- 新增 `CanvasImportTypeIdentifierResolutionTests.swift`
- 覆盖三类边界：
- 公共图片类型 `public.jpeg` 能被正常解析
- 私有图片 thumbnail 标识会回退到真实 `png`
- 私有视频 thumbnail 标识会回退到文件扩展名 `mp4`

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasImportTypeIdentifierResolutionTests.swift
// 类型/函数: CanvasImportTypeIdentifierResolutionTests.testImportedImageSourceResolvesDeclaredPublicTypeIdentifier() / testResolvedImportImageFallsBackFromIgnoredPrivateThumbnailType() / testImportedVideoSourceFallsBackToFilenameExtensionWhenIdentifierIsIgnored()
// 功能说明: 修改后测试直接锁定公共 UTI、私有 Photos thumbnail 标识与文件扩展名回退之间的边界，防止导入类型解析再次回归。
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MyCanvas_Ver_0

final class CanvasImportTypeIdentifierResolutionTests: XCTestCase {
    func testImportedImageSourceResolvesDeclaredPublicTypeIdentifier() {
        let source = CanvasImportedImageSource(
            data: Data(),
            typeIdentifier: UTType.jpeg.identifier,
            filenameHint: "photo.jpg"
        )

        XCTAssertEqual(source.contentType?.identifier, UTType.jpeg.identifier)
    }

    func testResolvedImportImageFallsBackFromIgnoredPrivateThumbnailType() throws {
        let resolvedImage = try XCTUnwrap(
            CanvasResolvedImportImage(
                data: try makePNGData(),
                typeIdentifier: "com.apple.private.photos.thumbnail.low",
                filenameHint: "thumbnail"
            )
        )

        XCTAssertEqual(
            resolvedImage.importedSource?.typeIdentifier,
            UTType.png.identifier
        )
        XCTAssertEqual(
            resolvedImage.importedContentType?.identifier,
            UTType.png.identifier
        )
    }

    func testImportedVideoSourceFallsBackToFilenameExtensionWhenIdentifierIsIgnored() {
        let source = CanvasImportedVideoSource(
            localFileURL: URL(fileURLWithPath: "/tmp/example-video.mp4"),
            typeIdentifier: "com.apple.private.photos.thumbnail.standard",
            filenameHint: nil,
            shouldDeleteAfterImport: false
        )

        XCTAssertEqual(
            source.contentType?.identifier,
            UTType(filenameExtension: "mp4")?.identifier
        )
    }
}
```

## 验证结果

- `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS Simulator" -derivedDataPath "/tmp/MyCanvas_Ver_0-ios-uti-fix-2"` 通过。
- 上述 iOS 构建输出中，已不再出现：
- `Type "public.jpeg" was expected to be declared and imported in the Info.plist...`
- `Type "public.mpeg-4" was expected to be declared and imported in the Info.plist...`
- `Type "com.apple.private.photos.thumbnail.low" was expected to be declared and imported in the Info.plist...`
- `Type "com.apple.private.photos.thumbnail.standard" was expected to be declared and imported in the Info.plist...`
- `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -derivedDataPath "/tmp/MyCanvas_Ver_0-macos-uti-fix"` 通过。
- 新增测试通过：
- `CanvasImportTypeIdentifierResolutionTests.testImportedImageSourceResolvesDeclaredPublicTypeIdentifier()`
- `CanvasImportTypeIdentifierResolutionTests.testResolvedImportImageFallsBackFromIgnoredPrivateThumbnailType()`
- `CanvasImportTypeIdentifierResolutionTests.testImportedVideoSourceFallsBackToFilenameExtensionWhenIdentifierIsIgnored()`
- 阶段 9 原有 `BoardVideoStorageTests` 也继续通过，说明这次共享导入解析修复没有打断已有视频存储链路。
