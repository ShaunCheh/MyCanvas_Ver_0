# 20260407_115905_gif_phase0_configuration_record

## 记录范围

- 记录内容：为 GIF 多选帧导入的阶段 0 新增共享配置源，集中定义选帧页网格、图板排布网格和缩略图最大像素。
- 涉及文件：`MyCanvas_Ver_0/Canvas/GIF/CanvasGIFFrameImportConfiguration.swift`
- 本记录不包含：GIF 帧元数据解析、按帧缩略图/全尺寸解码、`CanvasImportRequest` 扩展、菜单接线、iOS/macOS 选帧页 UI。
- 本记录不包含：git commit / push。

## 修改一：新增 GIF 阶段 0 共享配置文件

### 修改前

- shared Canvas 层还没有 GIF 多选帧导入的专用配置入口。
- “选帧页列数”、“图板排布列数”、“缩略图最大像素”、“网格间距”和“内容内边距”还没有统一收口到一个类型里。
- 如果后续阶段直接推进实现，这些默认值只能散落在各个控制器、布局器或导入逻辑中，难以保证 iOS / macOS 与 shared 层使用同一套默认语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/GIF/CanvasGIFFrameImportConfiguration.swift
// 类型/函数: 文件级新增前
// 功能说明: 修改前该文件不存在，GIF 多选帧导入阶段 0 没有统一的共享配置源。
// 无
```

### 修改后

- 新增 `CanvasGIFFrameImportConfiguration.swift`，作为 GIF 多选帧导入阶段 0 的共享配置入口。
- 用 `CanvasGIFFrameImportInsets` 表达统一的内容内边距，避免调用点各自处理四边取值和非负约束。
- 用 `CanvasGIFFrameImportGridConfiguration` 表达网格配置，统一约束列数、横向间距、纵向间距和内边距。
- 用 `CanvasGIFFrameImportConfiguration.current` 暴露当前默认配置，先把选帧页与图板排布的默认列数统一成 `4`，同时给出缩略图像素和两套网格间距默认值。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/GIF/CanvasGIFFrameImportConfiguration.swift
// 类型/函数: CanvasGIFFrameImportInsets.uniform(_:)
// 功能说明: 统一表达四边内容内边距，并在初始化时收口为非负值，避免后续布局直接处理脏数据。
struct CanvasGIFFrameImportInsets: Equatable {
    var top: CGFloat
    var leading: CGFloat
    var bottom: CGFloat
    var trailing: CGFloat

    init(
        top: CGFloat,
        leading: CGFloat,
        bottom: CGFloat,
        trailing: CGFloat
    ) {
        self.top = max(top, 0)
        self.leading = max(leading, 0)
        self.bottom = max(bottom, 0)
        self.trailing = max(trailing, 0)
    }

    static func uniform(_ value: CGFloat) -> CanvasGIFFrameImportInsets {
        CanvasGIFFrameImportInsets(
            top: value,
            leading: value,
            bottom: value,
            trailing: value
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/GIF/CanvasGIFFrameImportConfiguration.swift
// 类型/函数: CanvasGIFFrameImportGridConfiguration.init(...)
// 功能说明: 把列数、横纵间距和内容内边距收口为统一网格配置，并对列数/间距做最小值保护。
struct CanvasGIFFrameImportGridConfiguration: Equatable {
    var columns: Int
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat
    var contentInsets: CanvasGIFFrameImportInsets

    init(
        columns: Int,
        horizontalSpacing: CGFloat,
        verticalSpacing: CGFloat,
        contentInsets: CanvasGIFFrameImportInsets
    ) {
        self.columns = max(columns, 1)
        self.horizontalSpacing = max(horizontalSpacing, 0)
        self.verticalSpacing = max(verticalSpacing, 0)
        self.contentInsets = contentInsets
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/GIF/CanvasGIFFrameImportConfiguration.swift
// 类型/函数: CanvasGIFFrameImportConfiguration.current
// 功能说明: 修改后集中定义 GIF 阶段 0 的当前默认值；选帧页与图板排布共享 4 列默认列数，并统一给出缩略图像素和两套网格布局参数。
struct CanvasGIFFrameImportConfiguration: Equatable {
    static let sharedDefaultColumnCount = 4

    static let current = CanvasGIFFrameImportConfiguration(
        selectionGrid: CanvasGIFFrameImportGridConfiguration(
            columns: sharedDefaultColumnCount,
            horizontalSpacing: 12,
            verticalSpacing: 12,
            contentInsets: .uniform(16)
        ),
        boardPlacementGrid: CanvasGIFFrameImportGridConfiguration(
            columns: sharedDefaultColumnCount,
            horizontalSpacing: 24,
            verticalSpacing: 24,
            contentInsets: .uniform(24)
        ),
        thumbnailMaxPixelSize: 240
    )

    var selectionGrid: CanvasGIFFrameImportGridConfiguration
    var boardPlacementGrid: CanvasGIFFrameImportGridConfiguration
    var thumbnailMaxPixelSize: Int
}
```

## 验证情况

- 已检查新文件的 IDE lints，未发现问题。
- 已执行 `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" build`，编译通过。
