# 20260323_105653_canvas_import_phase_b1_shared_batch_core_record

## 记录范围

- 记录内容：
  1. 新增共享 import contract，给后续 `B-2` / `B-3` 的平台入口适配器提供统一输入模型。
  2. 将 `CanvasEditorSession` 的单图导入扩展为批量导入核心，并保留单图兼容包装。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- 本记录不包含：
  - `macOS` 的 `Command+V` / Finder 文件粘贴 / 拖拽接入
  - `iOS` 的外接键盘粘贴 / 拖放接入
  - `CanvasCommand` / `CanvasCommandExecutor` 的导入命令化改造
  - 原始 gif diff
  - git commit / push

## 修改一：新增共享 import contract 文件

### 修改前

- 工程里没有 `Canvas/Import` 目录，也没有平台无关的 import contract。
- 平台层如果要导入图片，只能把单张 `CGImage` 直接传给 `editorSession.appendImportedImage(_:)`。
- 共享层还没有表达“导入图片负载 / 插入位置 / 批量排布策略”的独立类型。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 类型名: CanvasResolvedImportImage / CanvasImportPlacement / CanvasImportLayout
// 功能说明: 修改前该文件不存在；共享层没有统一的导入输入模型，平台入口只能直接把单张 CGImage 传给 session。
// 文件状态: 不存在
```

### 修改后

- 新增 `CanvasResolvedImportImage`，把“平台已解析完成的图片”包装成共享层可消费的负载。
- 新增 `CanvasImportPlacement`，先支持 `.cameraCenter`，同时预留未来“按指定 world point 插入”的扩展位。
- 新增 `CanvasImportLayout`，先支持 `.automatic`、`.stacked`、`.staggered(stepInWorld:)`，为后续批量粘贴和拖拽排布提供统一参数。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 类型名: CanvasResolvedImportImage / CanvasImportPlacement / CanvasImportLayout
// 功能说明: 修改后共享层拥有平台无关的导入载荷、插入位置和批量排布契约，后续 macOS/iOS 入口都可以收敛到这里。
import CoreGraphics

// 平台入口先把系统对象解析成 CGImage，再交给共享 import core。
struct CanvasResolvedImportImage {
    let cgImage: CGImage

    init(cgImage: CGImage) {
        self.cgImage = cgImage
    }
}

// 先固定支持画板中心，同时预留未来的 world point 插入能力。
enum CanvasImportPlacement: Equatable {
    case cameraCenter
    case worldPoint(CGPoint)
}

// 批量导入先支持自动、重叠、错位三种排布策略。
enum CanvasImportLayout: Equatable {
    case automatic
    case stacked
    case staggered(stepInWorld: CGPoint)
}
```

## 修改二：将 `CanvasEditorSession` 的单图导入提升为批量导入核心

### 修改前

- `appendImportedImage(_:)` 只支持单张图片导入。
- 插入位置被写死为 `camera.center`。
- 历史记录和 autosave 也只按单张图片的 `"append image"` 语义处理。
- 如果后续平台层要支持多图粘贴或多图拖入，只能在 controller 层循环调用这个单图 API，结果会出现多次 history / 多次 autosave，而且没有统一的排布策略。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: appendImportedImage(_:)
// 功能说明: 修改前只支持单图导入；插入点固定为 camera.center，且 history / autosave 按单张图片立即提交。
@discardableResult
func appendImportedImage(_ cgImage: CGImage) -> CanvasImageItem {
    let beforeSnapshot = currentBoardHistorySnapshot()
    let item = CanvasImageItem(
        cgImage: cgImage,
        center: camera.center,
        size: normalizedDisplaySize(for: cgImage),
        zIndex: nextImageZIndex()
    )

    scene.append(item)
    expandBoardIfNeeded(toInclude: item.worldFrame)
    _ = recordImmediateHistoryChange(
        from: beforeSnapshot,
        reason: "append image",
        autosaveReason: "append image"
    )
    return item
}
```

### 修改后

- 新增 `resolvedImportCenter(...)`、`resolvedImportLayout(...)`、`importOffset(...)`、`importedImageChangeReason(...)`，把导入位置、默认排布和批量 reason 统一封装到 session 内部。
- 新增 `appendImportedImages(...)` 作为批量导入核心：一批图片只做一次 `beforeSnapshot`，统一生成 item、递增 `zIndex`、扩展 board，并在最后一次性记录 history / autosave。
- 保留 `appendImportedImage(_:, placement:)` 作为兼容包装：单图路径继续返回 `CanvasImageItem`，但内部已经复用批量导入核心。
- 默认行为仍然保持兼容：单图时还是等价于落到 `camera.center`；多图时 `.automatic` 会解析成基于 `duplicateOffsetInWorld()` 的错位排布。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: resolvedImportCenter(for:) / resolvedImportLayout(_:imageCount:) / importOffset(forImageAt:layout:) / appendImportedImages(_:placement:layout:) / appendImportedImage(_:placement:)
// 功能说明: 修改后 session 内部拥有批量导入核心；平台层后续只要提供已解析图片数组，就能统一获得 placement、layout、一次 history、一次 autosave。
private func resolvedImportCenter(
    for placement: CanvasImportPlacement
) -> CGPoint {
    switch placement {
    case .cameraCenter:
        return camera.center
    case let .worldPoint(point):
        return point
    }
}

private func resolvedImportLayout(
    _ layout: CanvasImportLayout,
    imageCount: Int
) -> CanvasImportLayout {
    switch layout {
    case .automatic:
        if imageCount <= 1 {
            return .stacked
        }

        return .staggered(stepInWorld: duplicateOffsetInWorld())
    case .stacked:
        return .stacked
    case let .staggered(stepInWorld):
        return .staggered(stepInWorld: stepInWorld)
    }
}

private func importOffset(
    forImageAt index: Int,
    layout: CanvasImportLayout
) -> CGPoint {
    switch layout {
    case .automatic, .stacked:
        return .zero
    case let .staggered(stepInWorld):
        let multiplier = CGFloat(index)
        return CGPoint(
            x: stepInWorld.x * multiplier,
            y: stepInWorld.y * multiplier
        )
    }
}

private func importedImageChangeReason(for imageCount: Int) -> String {
    guard imageCount > 1 else {
        return "append image"
    }

    return "append \(imageCount) images"
}

@discardableResult
func appendImportedImages(
    _ images: [CanvasResolvedImportImage],
    placement: CanvasImportPlacement = .cameraCenter,
    layout: CanvasImportLayout = .automatic
) -> [CanvasImageItem] {
    guard images.isEmpty == false else {
        return []
    }

    let beforeSnapshot = currentBoardHistorySnapshot()
    let importCenter = resolvedImportCenter(for: placement)
    let resolvedLayout = resolvedImportLayout(
        layout,
        imageCount: images.count
    )
    let startingZIndex = nextImageZIndex()
    var importedItems: [CanvasImageItem] = []
    importedItems.reserveCapacity(images.count)

    for (index, image) in images.enumerated() {
        let offset = importOffset(
            forImageAt: index,
            layout: resolvedLayout
        )
        let item = CanvasImageItem(
            cgImage: image.cgImage,
            center: CGPoint(
                x: importCenter.x + offset.x,
                y: importCenter.y + offset.y
            ),
            size: normalizedDisplaySize(for: image.cgImage),
            zIndex: startingZIndex + CGFloat(index)
        )

        scene.append(item)
        expandBoardIfNeeded(toInclude: item.worldFrame)
        importedItems.append(item)
    }

    let changeReason = importedImageChangeReason(
        for: importedItems.count
    )
    _ = recordImmediateHistoryChange(
        from: beforeSnapshot,
        reason: changeReason,
        autosaveReason: changeReason
    )
    return importedItems
}

@discardableResult
func appendImportedImage(
    _ cgImage: CGImage,
    placement: CanvasImportPlacement = .cameraCenter
) -> CanvasImageItem {
    let importedItems = appendImportedImages(
        [CanvasResolvedImportImage(cgImage: cgImage)],
        placement: placement,
        layout: .stacked
    )
    guard let item = importedItems.first else {
        preconditionFailure("Expected a single imported image result.")
    }

    return item
}
```

## 影响说明

- 当前 `macOS` / `iOS` 入口还没有改写；它们仍然可以继续调用 `appendImportedImage(_:)`，不会被这次 B-1 改动打断。
- 新增的 `CanvasImportPlacement.worldPoint(...)` 只是提前把 contract 预留出来，本阶段还没有接入最后点击点或拖拽落点。
- 新增的 `CanvasImportLayout.automatic` 当前的默认策略是：
  - 单图时退化为 `.stacked`
  - 多图时退化为 `.staggered(stepInWorld: duplicateOffsetInWorld())`
- 这次改动仍然保持“不自动选中新导入项”的现有语义。

## 校验说明

- 已检查 `MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift` 与 `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`，当前未发现新增 lint 报错。
- 已使用 `swiftc -typecheck` 对非 iOS Swift 源码集合进行静态类型检查，当前通过。
- 本次未运行完整 `xcodebuild`；原因是当前 active developer directory 指向 `CommandLineTools`，不是完整 Xcode 环境。
