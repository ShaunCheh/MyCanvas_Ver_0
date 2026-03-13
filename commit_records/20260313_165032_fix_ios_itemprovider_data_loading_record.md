# 20260313_165032_fix_ios_itemprovider_data_loading_record

## 记录范围

- 记录内容：修复 iOS 相册导入链路对 `NSItemProvider` 临时文件的错误依赖。
- 目标：消除图片选择后因临时文件失效导致的 `open failed` / `imagePNG_error_break` 问题。
- 本次未包含：`UIScene` 生命周期升级、macOS 侧改动、导入按钮 UI 调整。

## 变更 1：iOS 图片导入从临时文件 URL 改为内存数据解码

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: loadSelectedImage(from:)
// 功能说明: 修改前通过 loadFileRepresentation 拿到 NSItemProvider 的临时文件 URL，再用 URL 创建 CGImageSource。
// 根因问题是这个临时文件生命周期很短，后续渲染时可能已经失效，导致 open failed 和 imagePNG_error_break。
private func loadSelectedImage(from result: PHPickerResult) {
    let itemProvider = result.itemProvider
    guard itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
        return
    }

    itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, _ in
        guard
            let url,
            let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            return
        }

        Task { @MainActor [weak self] in
            self?.appendImportedImage(cgImage)
        }
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: loadSelectedImage(from:)
// 功能说明: 修改后直接通过 loadDataRepresentation 读取图片二进制数据，再用 Data 创建 CGImageSource。
// 这样图片内容会先被应用自身持有，不再依赖 NSItemProvider 提供的临时文件 URL。
private func loadSelectedImage(from result: PHPickerResult) {
    let itemProvider = result.itemProvider
    guard itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
        return
    }

    itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
        guard
            let data,
            let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            return
        }

        Task { @MainActor [weak self] in
            self?.appendImportedImage(cgImage)
        }
    }
}
```

## 当前结果

- iOS 相册导入链路不再依赖 `NSItemProvider` 返回的临时文件路径。
- 这次修改针对的是图片导入失败的根因，而不是表面上的日志现象。
- `CanvasScene -> CanvasRenderer -> CanvasViewportView -> CanvasImageLayer` 这条后续渲染链路保持不变，只修正了平台导入边界的数据获取方式。
