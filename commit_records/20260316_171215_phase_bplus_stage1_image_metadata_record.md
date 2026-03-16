# 20260316_171215_phase_bplus_stage1_image_metadata_record

## 记录范围

- 记录内容：
  1. 为图片实例补齐非破坏性裁切与旋转所需的基础元数据。
  2. 新增一个非持久化的 inline 编辑态容器，为后续画布内裁切 / 旋转子模式预留共享状态。
  3. 扩展 `board.json` 的图片记录结构与运行时映射逻辑，使旧文档在缺失新字段时仍按“完整图 + 零旋转”兼容打开。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
- 本记录不包含：
  - 原始 gif diff
  - 裁切 / 旋转渲染与命中测试实现
  - undo / redo 历史控制器
  - 平台侧交互状态机改造

## 修改一：为图片实例增加裁切与旋转元数据

### 修改前

- `CanvasImageItem` 只承载 `cgImage`、`center`、`size`、`zIndex`。
- 当前图片实例没有独立的“裁切区域”或“旋转角度”表达，后续无法在不改原图的前提下持久化这些编辑状态。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 函数名/类型名: CanvasImageItem
// 功能说明: 修改前图片实例只保存原图引用与轴对齐显示几何，没有非破坏性裁切/旋转元数据。
struct CanvasImageItem {
    let id: CanvasImageItemID
    let cgImage: CGImage
    var center: CGPoint
    var size: CGSize
    var zIndex: CGFloat

    init(
        id: CanvasImageItemID = UUID(),
        cgImage: CGImage,
        center: CGPoint,
        size: CGSize,
        zIndex: CGFloat = 0
    ) {
        self.id = id
        self.cgImage = cgImage
        self.center = center
        self.size = size
        self.zIndex = zIndex
    }

    var worldFrame: CGRect {
        CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
```

### 修改后

- 新增 `CanvasImageCropRect`，统一用归一化图片坐标表达“原图里哪一块可见”。
- `CanvasImageItem` 增加 `cropRectNormalized` 与 `rotationRadians`，同时保持 `cgImage` 继续指向原始完整图。
- `CanvasImageCropRect` 在初始化时会做裁切区域规整，避免非法或越界的 normalized rect 把后续渲染链路搞坏。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 函数名/类型名: CanvasImageCropRect / CanvasImageItem
// 功能说明: 修改后图片实例可以保存非破坏性裁切区域与旋转角度，同时仍保留原始完整图引用。
// Crop stays in normalized image space so later editing can change what is shown
// without mutating the original image asset in memory or on disk.
struct CanvasImageCropRect: Equatable {
    private static let fullImageRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    static let fullImage = CanvasImageCropRect(fullImageRect)

    let cgRect: CGRect

    init(_ cgRect: CGRect = CanvasImageCropRect.fullImageRect) {
        self.cgRect = Self.sanitizedRect(from: cgRect)
    }

    var isFullImage: Bool {
        cgRect == Self.fullImage.cgRect
    }

    private static func sanitizedRect(from cgRect: CGRect) -> CGRect {
        guard cgRect.isNull == false, cgRect.isInfinite == false else {
            return fullImageRect
        }

        let standardized = cgRect.standardized
        let minX = min(max(standardized.minX, fullImageRect.minX), fullImageRect.maxX)
        let minY = min(max(standardized.minY, fullImageRect.minY), fullImageRect.maxY)
        let maxX = min(max(standardized.maxX, fullImageRect.minX), fullImageRect.maxX)
        let maxY = min(max(standardized.maxY, fullImageRect.minY), fullImageRect.maxY)
        let width = maxX - minX
        let height = maxY - minY

        guard width > 0, height > 0 else {
            return fullImageRect
        }

        return CGRect(
            x: minX,
            y: minY,
            width: width,
            height: height
        )
    }
}

struct CanvasImageItem {
    let id: CanvasImageItemID
    let cgImage: CGImage
    var center: CGPoint
    var size: CGSize
    var zIndex: CGFloat
    var cropRectNormalized: CanvasImageCropRect
    var rotationRadians: CGFloat

    init(
        id: CanvasImageItemID = UUID(),
        cgImage: CGImage,
        center: CGPoint,
        size: CGSize,
        zIndex: CGFloat = 0,
        cropRectNormalized: CanvasImageCropRect = .fullImage,
        rotationRadians: CGFloat = 0
    ) {
        self.id = id
        self.cgImage = cgImage
        self.center = center
        self.size = size
        self.zIndex = zIndex
        self.cropRectNormalized = cropRectNormalized
        self.rotationRadians = rotationRadians
    }
}
```

## 修改二：新增非持久化的 inline 编辑态文件

### 修改前

- 项目里没有专门承载“画布内裁切 / 旋转草稿”的 shared 状态类型。
- 如果后面直接把临时编辑态塞进 `CanvasInteractionState` 或 `BoardRuntimeState`，就容易把本应短暂存在的草稿状态错误地带进 `board.json`。

```text
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift
// 函数名/类型名: 文件原先不存在
// 功能说明: 修改前项目中没有独立的 inline 编辑态文件，后续 crop/rotate 草稿没有共享的非持久化状态容器。
// before: file did not exist
```

### 修改后

- 新增 `CanvasInlineEditMode` 与 `CanvasInlineEditState`。
- 该状态只表达“当前正在编辑哪个 item、是什么模式、草稿中的裁切区域和旋转角度”，并且显式保持为非持久化状态。
- `init(item:mode:)` 允许后续平台控制器从现有图元实例快速进入 crop / rotate 子模式。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift
// 函数名/类型名: CanvasInlineEditMode / CanvasInlineEditState
// 功能说明: 修改后新增一个非持久化的 inline 编辑态容器，为画布内裁切与旋转子模式预留共享草稿状态。
enum CanvasInlineEditMode {
    case crop
    case rotate
}

// This transient editing state is intentionally kept out of BoardRuntimeState /
// board.json so inline crop and rotate drafts never become persisted document data.
struct CanvasInlineEditState {
    let itemID: CanvasImageItemID
    var mode: CanvasInlineEditMode
    var draftCropRectNormalized: CanvasImageCropRect
    var draftRotationRadians: CGFloat

    init(
        itemID: CanvasImageItemID,
        mode: CanvasInlineEditMode,
        draftCropRectNormalized: CanvasImageCropRect = .fullImage,
        draftRotationRadians: CGFloat = 0
    ) {
        self.itemID = itemID
        self.mode = mode
        self.draftCropRectNormalized = draftCropRectNormalized
        self.draftRotationRadians = draftRotationRadians
    }

    init(
        item: CanvasImageItem,
        mode: CanvasInlineEditMode
    ) {
        self.init(
            itemID: item.id,
            mode: mode,
            draftCropRectNormalized: item.cropRectNormalized,
            draftRotationRadians: item.rotationRadians
        )
    }
}
```

## 修改三：扩展 board.json 的图片记录结构

### 修改前

- `BoardDocument.currentFormatVersion` 仍是 `1`。
- `BoardImageItemRecord` 只保存位置、尺寸、层级和资源文件名；即使运行时以后有 crop / rotation 元数据，也没有地方被写进 `board.json`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名/类型名: BoardDocument / BoardImageItemRecord
// 功能说明: 修改前 board.json 仍是 v1，图片记录没有裁切区域和旋转角度字段。
struct BoardDocument: Codable {
    static let currentFormatVersion = 1
    static let defaultTitle = "Untitled Board"
    // ... 省略未改动代码 ...
}

struct BoardImageItemRecord: Codable {
    let id: UUID
    var center: BoardPointRecord
    var size: BoardSizeRecord
    var zIndex: Double
    var assetFilename: String
}
```

### 修改后

- `BoardDocument.currentFormatVersion` 升到 `2`，为后续文档升级留出明确版本。
- `BoardImageItemRecord` 增加 `cropRectNormalized` 与 `rotationRadians`，都设计成可选字段，方便兼容旧文档。
- 新增 `BoardImageCropRecord`，专门以数值字段持久化 normalized crop rect，并提供与 `CanvasImageCropRect` 的相互转换。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名/类型名: BoardDocument / BoardImageItemRecord / BoardImageCropRecord
// 功能说明: 修改后 board.json 升级到 v2，图片记录可以持久化裁切区域与旋转角度，并保留旧文档的可选字段兼容性。
struct BoardDocument: Codable {
    static let currentFormatVersion = 2
    static let defaultTitle = "Untitled Board"
    // ... 省略未改动代码 ...
}

struct BoardImageItemRecord: Codable {
    let id: UUID
    var center: BoardPointRecord
    var size: BoardSizeRecord
    var zIndex: Double
    var assetFilename: String
    var cropRectNormalized: BoardImageCropRecord?
    var rotationRadians: Double?
}

struct BoardImageCropRecord: Codable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ cropRect: CanvasImageCropRect) {
        let normalizedRect = cropRect.cgRect
        self.init(
            x: Double(normalizedRect.origin.x),
            y: Double(normalizedRect.origin.y),
            width: Double(normalizedRect.width),
            height: Double(normalizedRect.height)
        )
    }

    var canvasImageCropRect: CanvasImageCropRect {
        CanvasImageCropRect(
            CGRect(
                x: x,
                y: y,
                width: width,
                height: height
            )
        )
    }
}
```

## 修改四：补齐运行时与文档模型之间的新字段映射

### 修改前

- `BoardDocumentMapper.makeRuntimeState(...)` 恢复 `CanvasImageItem` 时，只传入 `id/cgImage/center/size/zIndex`。
- `makeImageRecord(from:)` 保存时也只写原有五个字段。
- 这意味着即使运行时补了 crop / rotation 字段，也会在“保存 -> 重开”后丢失。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeRuntimeState(from:imageLoader:) / makeImageRecord(from:)
// 功能说明: 修改前 Mapper 只映射原有位置尺寸数据，没有裁切和旋转字段，也没有旧文档默认值策略。
static func makeRuntimeState(
    from document: BoardDocument,
    imageLoader: (BoardImageItemRecord) throws -> CGImage
) throws -> BoardRuntimeState {
    let items = try document.items.map { itemRecord in
        CanvasImageItem(
            id: itemRecord.id,
            cgImage: try imageLoader(itemRecord),
            center: itemRecord.center.cgPoint,
            size: itemRecord.size.cgSize,
            zIndex: CGFloat(itemRecord.zIndex)
        )
    }
    // ... 省略未改动代码 ...
}

private static func makeImageRecord(from item: CanvasImageItem) -> BoardImageItemRecord {
    BoardImageItemRecord(
        id: item.id,
        center: BoardPointRecord(item.center),
        size: BoardSizeRecord(item.size),
        zIndex: Double(item.zIndex),
        assetFilename: "\(item.id.uuidString).png"
    )
}
```

### 修改后

- 恢复运行时时，`cropRectNormalized` 缺失则默认回退到 `.fullImage`，`rotationRadians` 缺失则默认回退到 `0`。
- 写回文档时，同步把 `CanvasImageItem` 上的裁切与旋转元数据写进 `BoardImageItemRecord`。
- 这样阶段一就把“运行时字段存在”与“保存恢复不丢失”两条链路补齐了。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeRuntimeState(from:imageLoader:) / makeImageRecord(from:)
// 功能说明: 修改后 Mapper 负责裁切与旋转元数据的双向映射，并为旧文档缺失字段提供默认值。
static func makeRuntimeState(
    from document: BoardDocument,
    imageLoader: (BoardImageItemRecord) throws -> CGImage
) throws -> BoardRuntimeState {
    let items = try document.items.map { itemRecord in
        CanvasImageItem(
            id: itemRecord.id,
            cgImage: try imageLoader(itemRecord),
            center: itemRecord.center.cgPoint,
            size: itemRecord.size.cgSize,
            zIndex: CGFloat(itemRecord.zIndex),
            cropRectNormalized: itemRecord.cropRectNormalized?.canvasImageCropRect ?? .fullImage,
            rotationRadians: CGFloat(itemRecord.rotationRadians ?? 0)
        )
    }
    // ... 省略未改动代码 ...
}

private static func makeImageRecord(from item: CanvasImageItem) -> BoardImageItemRecord {
    BoardImageItemRecord(
        id: item.id,
        center: BoardPointRecord(item.center),
        size: BoardSizeRecord(item.size),
        zIndex: Double(item.zIndex),
        assetFilename: "\(item.id.uuidString).png",
        cropRectNormalized: BoardImageCropRecord(item.cropRectNormalized),
        rotationRadians: Double(item.rotationRadians)
    )
}
```

## 校验情况

- 已对以下文件执行 `ReadLints`：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
- lint 结果：`No linter errors found.`
- 已执行 iOS Simulator 构建校验：
  - `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -sdk iphonesimulator -destination "generic/platform=iOS Simulator" -derivedDataPath ".build/DerivedData-stage1-iOSSim" CODE_SIGNING_ALLOWED=NO build`
- 构建结果：`BUILD SUCCEEDED`
- 本次记录对应阶段一模型与持久化扩展，不包含阶段二的渲染 / 命中升级。
