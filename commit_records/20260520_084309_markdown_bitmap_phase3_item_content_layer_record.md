# 20260520_084309_markdown_bitmap_phase3_item_content_layer_record

## 记录范围

- 记录内容：
  - 实施 `@.cursor/plans/markdown位图重构_bb0734a4.plan.md` 的阶段 3。
  - 本阶段目标是把主画布 markdown 从“单层 `CATextLayer` 按屏幕宽度和 zoom 直接重排”切到“`CanvasMarkdownItemLayer` + `CanvasMarkdownContentLayer`”两层结构，真正切断 camera zoom 参与 markdown 重排的链路。
  - 本次实际改动包括：调整 `CanvasMarkdownRenderPayload` 的语义；删除旧 `CanvasMarkdownLayer`；新增 `CanvasMarkdownItemLayer` 与 `CanvasMarkdownContentLayer`；让 iOS / macOS viewport 改接新 layer；同步更新 markdown 契约测试与 layer 测试。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayer.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownItemLayer.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownContentLayer.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0Tests/CanvasMarkdownContractTests.swift`
  - `MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift`
- 参考现状：
  - `git status --short` 显示本次阶段 3 相关变更为 `6` 个已跟踪修改文件、`1` 个已跟踪删除文件、`2` 个未跟踪新增文件。
  - `git diff --stat` 显示已跟踪文件变化为：`7 files changed, 142 insertions(+), 274 deletions(-)`。
  - 由于 `CanvasMarkdownContentLayer.swift` 与 `CanvasMarkdownItemLayer.swift` 是新增未跟踪文件，它们不会出现在这条 `git diff --stat` 输出里，但已经出现在 `git status --short` 中。
- 本记录不包含：
  - `@.cursor/plans/markdown位图重构_bb0734a4.plan.md` 的内容改动。
  - 任何 git 提交行为。

```bash
# 命令: git status --short
 M MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
 D MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayer.swift
 M MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
 M MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
 M MyCanvas_Ver_0Tests/CanvasMarkdownContractTests.swift
 M MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift
?? MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownContentLayer.swift
?? MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownItemLayer.swift
```

```bash
# 命令: git diff --stat
.../Canvas/Core/CanvasRenderSnapshot.swift         |   9 +-
MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift    |   3 +-
.../Shared/Rendering/CanvasMarkdownLayer.swift     | 134 -----------
.../iOS/Canvas/iOSCanvasViewportView.swift         |   6 +-
.../macOS/Canvas/macOSCanvasViewportView.swift     |   6 +-
.../CanvasMarkdownContractTests.swift              |   3 +-
MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift | 255 ++++++++++-----------
7 files changed, 142 insertions(+), 274 deletions(-)
```

## 当前 changes 摘要

- `CanvasMarkdownRenderPayload` 不再表达“按当前屏幕宽度排版”，而是显式携带 `logicalSize` 与 `cameraZoomScale`；markdown 的语义布局宽度回到 world-space 容器宽度。
- 旧的 `CanvasMarkdownLayer` 已被删除，主画布 markdown 改成“外层 `CanvasMarkdownItemLayer` 管几何、内层 `CanvasMarkdownContentLayer` 管 bitmap contents”。
- `CanvasMarkdownContentLayer` 只在 `markdownSource/style/logicalWidth` 变化时重新布局；`cameraZoomScale` 变化时只提高位图栅格密度，不再改变换行和字号语义。
- iOS / macOS viewport 都改为复用 `CanvasMarkdownItemLayer`，主画布渲染接线统一到同一套 layer 管线。
- `CanvasMarkdownLayerTests` 从“验证 `CATextLayer.string` 的字体变化”切到“验证 `ItemLayer` 的逻辑几何、外层 zoom transform 与 `ContentLayer` 的重排 / 重栅格边界”；`CanvasMarkdownContractTests` 也同步锁定了新的 payload 字段。
- 首轮回归里先后暴露了 `CGFloat.nan` 推断歧义，以及测试代码仍引用旧 `payload.zoomScale` / 直接条件下转 `CGImage` 的编译问题；这些都已在当前 changes 中修正完毕。

## 修改一：调整 markdown render payload 合同

### 1.1 修改前

- `CanvasMarkdownRenderPayload` 只有 `markdownSource`、`style` 和 `zoomScale`。
- `CanvasRenderer.makeMarkdownRenderItem(...)` 直接把 `camera.zoomScale` 塞进 payload，后续 layer 只能基于屏幕宽度与 zoom 做内容布局。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift（修改前）
// 函数名: CanvasMarkdownRenderPayload（类型定义）
// 功能说明: 修改前 markdown payload 只携带 markdownSource、style 和 zoomScale，无法把世界坐标系下的逻辑容器尺寸作为稳定布局输入传给主画布 layer。
struct CanvasMarkdownRenderPayload {
    let markdownSource: String
    let style: CanvasTextStyle
    let zoomScale: CGFloat
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift（修改前）
// 函数名: makeMarkdownRenderItem(for:camera:rotationPreviewState:)
// 功能说明: 修改前 renderer 只把 zoomScale 透传给 markdown payload，主画布无法区分“语义布局宽度”和“当前相机缩放倍率”。
payload: .markdown(
    CanvasMarkdownRenderPayload(
        markdownSource: effectiveMarkdownItem.markdownSource,
        style: effectiveMarkdownItem.style,
        zoomScale: camera.zoomScale
    )
)
```

### 1.2 修改后

- `CanvasMarkdownRenderPayload` 改为携带 `logicalSize` 和 `cameraZoomScale`，明确分离“逻辑容器尺寸”和“当前栅格倍率”。
- `CanvasRenderer.makeMarkdownRenderItem(...)` 继续保持 `screenQuad/screenFrame/screenCenter` 契约不变，但 markdown payload 现在显式带上世界空间容器尺寸。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: CanvasMarkdownRenderPayload（类型定义）
// 功能说明: 修改后 markdown payload 显式承载逻辑容器尺寸和 camera zoom；主画布可以用 logicalSize 做稳定布局，用 cameraZoomScale 只决定位图清晰度。
struct CanvasMarkdownRenderPayload {
    let markdownSource: String
    let style: CanvasTextStyle
    let logicalSize: CGSize
    let cameraZoomScale: CGFloat
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeMarkdownRenderItem(for:camera:rotationPreviewState:)
// 功能说明: 修改后 renderer 继续输出原有屏幕几何契约，同时把 markdown 的世界空间容器尺寸和当前 camera zoom 一并写入 payload，供 ItemLayer / ContentLayer 分工消费。
payload: .markdown(
    CanvasMarkdownRenderPayload(
        markdownSource: effectiveMarkdownItem.markdownSource,
        style: effectiveMarkdownItem.style,
        logicalSize: effectiveMarkdownItem.size,
        cameraZoomScale: camera.zoomScale
    )
)
```

## 修改二：把主画布 markdown 从单层 `CATextLayer` 替换为 `ItemLayer + ContentLayer`

### 2.1 修改前

- 主画布只有一个 `CanvasMarkdownLayer: CATextLayer`。
- `update(...)` 每次以 `item.screenBoundsSize.width` 作为 `maxLayoutWidth`，并把 `markdownPayload.zoomScale` 直接传给 `CanvasMarkdownLayoutMeasurer.layout(...)`。
- 这意味着 zoom 变化会直接参与 markdown 内容的 reflow 与字号计算，正是阶段 3 要切断的链路。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayer.swift（修改前）
// 函数名: update(with:markdownPayload:contentsScale:) / shouldRefreshAttributedText(markdownPayload:layoutWidth:)
// 功能说明: 修改前单层 CATextLayer 直接按屏幕宽度和 zoomScale 重排 markdown；只要 zoom 或 screen width 改变，就会刷新 attributedText。
final class CanvasMarkdownLayer: CATextLayer {
    func update(
        with item: CanvasRenderItem,
        markdownPayload: CanvasMarkdownRenderPayload,
        contentsScale: CGFloat
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if shouldRefreshAttributedText(
            markdownPayload: markdownPayload,
            layoutWidth: item.screenBoundsSize.width
        ) {
            let layout = CanvasMarkdownLayoutMeasurer.layout(
                markdownSource: markdownPayload.markdownSource,
                style: markdownPayload.style,
                maxLayoutWidth: item.screenBoundsSize.width,
                scale: markdownPayload.zoomScale
            )
            string = layout.attributedText
            lastAppliedMarkdownSource = markdownPayload.markdownSource
            lastAppliedStyle = markdownPayload.style
            lastAppliedZoomScale = markdownPayload.zoomScale
            lastAppliedLayoutWidth = item.screenBoundsSize.width
        }

        CATransaction.commit()
    }
}
```

### 2.2 修改后

- 旧 `CanvasMarkdownLayer.swift` 已删除。
- 新增 `CanvasMarkdownContentLayer`：只在 `markdownSource/style/logicalWidth` 变化时重排；布局宽度固定取 `markdownPayload.logicalSize.width`，且 `scale` 固定为 `1`；zoom 只参与 `rasterScale`。
- 新增 `CanvasMarkdownItemLayer`：只管屏幕几何、裁剪、旋转、`zIndex` 和外层 zoom transform；它把 bitmap 内容委托给内部 `contentLayer`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownContentLayer.swift
// 函数名: update(with:contentsScale:) / makeLayout(from:) / resolvedRasterScale(markdownPayload:contentsScale:)
// 功能说明: 修改后 ContentLayer 只在 markdownSource、style 或 logicalWidth 变化时重排；camera zoom 只影响位图栅格倍率，不再改变 markdown 语义布局。
final class CanvasMarkdownContentLayer: CALayer {
    func update(
        with markdownPayload: CanvasMarkdownRenderPayload,
        contentsScale: CGFloat
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let needsLayoutRefresh = shouldRefreshLayout(
            markdownPayload: markdownPayload
        ) || cachedLayout == nil
        if needsLayoutRefresh {
            cachedLayout = makeLayout(from: markdownPayload)
            lastAppliedMarkdownSource = markdownPayload.markdownSource
            lastAppliedStyle = markdownPayload.style
            lastAppliedLogicalWidth = markdownPayload.logicalSize.width
        }

        if let cachedLayout {
            applyLayoutGeometry(cachedLayout)
            let rasterScale = resolvedRasterScale(
                markdownPayload: markdownPayload,
                contentsScale: contentsScale
            )
            if needsLayoutRefresh || lastAppliedRasterScale != rasterScale || contents == nil {
                contents = bitmapRenderer.render(
                    layout: cachedLayout,
                    rasterScale: rasterScale
                )
                lastAppliedRasterScale = rasterScale
            }
        }

        CATransaction.commit()
    }

    private func makeLayout(
        from markdownPayload: CanvasMarkdownRenderPayload
    ) -> CanvasMarkdownLayoutResult {
        CanvasMarkdownLayoutMeasurer.layout(
            markdownSource: markdownPayload.markdownSource,
            style: markdownPayload.style,
            maxLayoutWidth: markdownPayload.logicalSize.width,
            scale: 1,
            includeCompatibilityCodeBlockBackgrounds: false
        )
    }

    private func resolvedRasterScale(
        markdownPayload: CanvasMarkdownRenderPayload,
        contentsScale: CGFloat
    ) -> CGFloat {
        let resolvedContentsScale =
            contentsScale.isFinite && contentsScale > 0 ? contentsScale : 1
        let resolvedZoomScale =
            markdownPayload.cameraZoomScale.isFinite && markdownPayload.cameraZoomScale > 0
            ? markdownPayload.cameraZoomScale
            : 1
        return max(resolvedContentsScale * resolvedZoomScale, 1)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownItemLayer.swift
// 函数名: update(with:markdownPayload:contentsScale:) / makeItemTransform(rotationRadians:zoomScale:)
// 功能说明: 修改后 ItemLayer 只管理主画布上的逻辑容器几何和外层缩放/旋转，把 markdown 内容绘制职责委托给内部的 CanvasMarkdownContentLayer。
final class CanvasMarkdownItemLayer: CALayer {
    func update(
        with item: CanvasRenderItem,
        markdownPayload: CanvasMarkdownRenderPayload,
        contentsScale: CGFloat
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if lastAppliedLogicalSize != markdownPayload.logicalSize {
            bounds = CGRect(origin: .zero, size: markdownPayload.logicalSize)
            lastAppliedLogicalSize = markdownPayload.logicalSize
        }

        if lastAppliedPosition != item.screenCenter {
            position = item.screenCenter
            lastAppliedPosition = item.screenCenter
        }

        if
            lastAppliedRotationRadians != item.rotationRadians ||
            lastAppliedCameraZoomScale != markdownPayload.cameraZoomScale
        {
            transform = makeItemTransform(
                rotationRadians: item.rotationRadians,
                zoomScale: markdownPayload.cameraZoomScale
            )
            lastAppliedRotationRadians = item.rotationRadians
            lastAppliedCameraZoomScale = markdownPayload.cameraZoomScale
        }

        if lastAppliedZIndex != item.zIndex {
            zPosition = item.zIndex
            lastAppliedZIndex = item.zIndex
        }

        contentLayer.update(
            with: markdownPayload,
            contentsScale: contentsScale
        )

        CATransaction.commit()
    }

    private func makeItemTransform(
        rotationRadians: CGFloat,
        zoomScale: CGFloat
    ) -> CATransform3D {
        let resolvedZoomScale =
            zoomScale.isFinite && zoomScale > 0 ? zoomScale : 1
        let rotationTransform = CATransform3DMakeRotation(rotationRadians, 0, 0, 1)
        return CATransform3DScale(
            rotationTransform,
            resolvedZoomScale,
            resolvedZoomScale,
            1
        )
    }
}
```

## 修改三：让 iOS / macOS viewport 改接新的 markdown item layer

### 3.1 修改前

- iOS / macOS viewport 都维护 `markdownLayers: [CanvasItemID: CanvasMarkdownLayer]`。
- `markdownLayer(for:)` 直接创建旧的 `CanvasMarkdownLayer` 并挂到 `itemsLayer` 下。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift（修改前）
// 函数名: markdownLayer(for:)
// 功能说明: 修改前 iOS viewport 直接复用旧的 CanvasMarkdownLayer，主画布 markdown 仍然走单层 CATextLayer 方案。
private var markdownLayers: [CanvasItemID: CanvasMarkdownLayer] = [:]

private func markdownLayer(for itemID: CanvasItemID) -> CanvasMarkdownLayer {
    if let markdownLayer = markdownLayers[itemID] {
        return markdownLayer
    }

    let markdownLayer = CanvasMarkdownLayer(itemID: itemID)
    itemsLayer.addSublayer(markdownLayer)
    markdownLayers[itemID] = markdownLayer
    return markdownLayer
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift（修改前）
// 函数名: markdownLayer(for:)
// 功能说明: 修改前 macOS viewport 与 iOS 同构，markdown layer 生命周期同样绑定旧的 CanvasMarkdownLayer。
private var markdownLayers: [CanvasItemID: CanvasMarkdownLayer] = [:]

private func markdownLayer(for itemID: CanvasItemID) -> CanvasMarkdownLayer {
    if let markdownLayer = markdownLayers[itemID] {
        return markdownLayer
    }

    let markdownLayer = CanvasMarkdownLayer(itemID: itemID)
    itemsLayer.addSublayer(markdownLayer)
    markdownLayers[itemID] = markdownLayer
    return markdownLayer
}
```

### 3.2 修改后

- iOS / macOS viewport 都改为持有 `CanvasMarkdownItemLayer`。
- 主画布层树不再直接依赖 `CATextLayer` 风格的 markdown 实现，而是统一走新的 `ItemLayer + ContentLayer` 结构。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: markdownLayer(for:)
// 功能说明: 修改后 iOS viewport 直接复用 CanvasMarkdownItemLayer，让主画布 markdown 的几何层与内容层分工在 iOS 端生效。
private var markdownLayers: [CanvasItemID: CanvasMarkdownItemLayer] = [:]

private func markdownLayer(for itemID: CanvasItemID) -> CanvasMarkdownItemLayer {
    if let markdownLayer = markdownLayers[itemID] {
        return markdownLayer
    }

    let markdownLayer = CanvasMarkdownItemLayer(itemID: itemID)
    itemsLayer.addSublayer(markdownLayer)
    markdownLayers[itemID] = markdownLayer
    return markdownLayer
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: markdownLayer(for:)
// 功能说明: 修改后 macOS viewport 与 iOS 端保持同一套 markdown layer 生命周期，双端都改接 CanvasMarkdownItemLayer。
private var markdownLayers: [CanvasItemID: CanvasMarkdownItemLayer] = [:]

private func markdownLayer(for itemID: CanvasItemID) -> CanvasMarkdownItemLayer {
    if let markdownLayer = markdownLayers[itemID] {
        return markdownLayer
    }

    let markdownLayer = CanvasMarkdownItemLayer(itemID: itemID)
    itemsLayer.addSublayer(markdownLayer)
    markdownLayers[itemID] = markdownLayer
    return markdownLayer
}
```

## 修改四：同步调整 markdown 契约测试与 layer 测试

### 4.1 修改前

- `CanvasMarkdownContractTests` 仍然断言旧字段 `payload.zoomScale`。
- `CanvasMarkdownLayerTests` 仍围绕 `CanvasMarkdownLayer.string as? NSAttributedString` 做断言，测试目标还是“zoom 驱动字体变化”，而不是“ItemLayer / ContentLayer 分工”。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownContractTests.swift（修改前）
// 函数名: testCanvasSnapshotMapsMarkdownWorldGeometryIntoSharedScreenContract()
// 功能说明: 修改前契约测试仍然假设 markdown payload 上只有 zoomScale 字段，没有覆盖新的 logicalSize / cameraZoomScale 合同。
XCTAssertEqual(payload.markdownSource, item.markdownSource)
XCTAssertEqual(payload.style, item.style)
XCTAssertEqual(payload.zoomScale, session.camera.zoomScale)
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift（修改前）
// 函数名: testUpdateBuildsAttributedMarkdownUsingZoomScaledFonts()
// 功能说明: 修改前 layer 测试直接读取 CanvasMarkdownLayer 的 attributedText，关注点仍是 CATextLayer 下的字体缩放和富文本内容。
func testUpdateBuildsAttributedMarkdownUsingZoomScaledFonts() throws {
    let itemID = CanvasItemID()
    let layer = CanvasMarkdownLayer(itemID: itemID)
    let payload = CanvasMarkdownRenderPayload(
        markdownSource: """
        ## Title

        Body with `code`
        """,
        style: CanvasTextStyle(fontSize: 18),
        zoomScale: 1.5
    )

    layer.update(
        with: renderItem,
        markdownPayload: payload,
        contentsScale: 2
    )

    let attributedText = try XCTUnwrap(layer.string as? NSAttributedString)
    // ...
}
```

### 4.2 修改后

- `CanvasMarkdownContractTests` 改为断言 `logicalSize` 与 `cameraZoomScale`。
- `CanvasMarkdownLayerTests` 改为验证：
  - `CanvasMarkdownItemLayer` 使用逻辑容器尺寸和外层 zoom transform；
  - `CanvasMarkdownContentLayer` 改宽会重排；
  - 只改高或只改 zoom 时，逻辑布局尺寸保持不变，但位图像素尺寸会随 rasterScale 提升。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownContractTests.swift
// 函数名: testCanvasSnapshotMapsMarkdownWorldGeometryIntoSharedScreenContract()
// 功能说明: 修改后契约测试锁定新的 markdown payload 语义，确保 renderer 同时输出逻辑尺寸和 camera zoom。
XCTAssertEqual(payload.markdownSource, item.markdownSource)
XCTAssertEqual(payload.style, item.style)
XCTAssertEqual(payload.logicalSize, item.size)
XCTAssertEqual(payload.cameraZoomScale, session.camera.zoomScale)
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift
// 函数名: testItemLayerUsesLogicalBoundsAndCameraScaleTransform() / testContentLayerReflowsWhenLogicalWidthChanges() / testContentLayerKeepsLogicalLayoutSizeWhenOnlyHeightOrZoomChanges()
// 功能说明: 修改后 layer 测试直接验证 ItemLayer / ContentLayer 的职责边界，确保 zoom 只影响 outer transform 与 raster density，不再触发 markdown 语义布局漂移。
final class CanvasMarkdownLayerTests: XCTestCase {
    func testItemLayerUsesLogicalBoundsAndCameraScaleTransform() throws {
        let itemID = CanvasItemID()
        let layer = CanvasMarkdownItemLayer(itemID: itemID)
        let payload = CanvasMarkdownRenderPayload(
            markdownSource: """
            ## Title

            Body with `code`
            """,
            style: CanvasTextStyle(fontSize: 18),
            logicalSize: CGSize(width: 220, height: 120),
            cameraZoomScale: 1.5
        )

        layer.update(
            with: renderItem,
            markdownPayload: payload,
            contentsScale: 2
        )

        let contentImage = try markdownContentImage(from: layer.contentLayer)
        let expectedLayout = makeExpectedMarkdownLayout(for: payload)
        let affineTransform = CATransform3DGetAffineTransform(layer.transform)

        XCTAssertEqual(layer.bounds.size, payload.logicalSize)
        XCTAssertEqual(layer.contentLayer.bounds.size, expectedLayout.contentSize)
        XCTAssertEqual(contentImage.width, Int(ceil(expectedLayout.contentSize.width * 3)))
        XCTAssertEqual(markdownLayerTransformScale(affineTransform), 1.5, accuracy: 0.001)
    }
}
```

## 验证记录

- 本次已对阶段 3 相关文件执行 `ReadLints`，没有新增 linter 问题。
- 第一轮 macOS 定向回归里，`CanvasMarkdownContentLayer.swift` / `CanvasMarkdownItemLayer.swift` 中的 `.nan` 写法触发了 Swift 推断歧义。
- 第二轮回归里，测试代码仍残留对旧 `payload.zoomScale` 的断言，以及对 `CGImage` 的条件下转写法，随后在当前 changes 中一并修正。
- 修正后重新执行阶段 3 的 macOS 定向回归与 iOS simulator 构建，全部通过。

```bash
# 命令: xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:'MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests' -only-testing:'MyCanvas_Ver_0Tests/CanvasMarkdownContractTests' -only-testing:'MyCanvas_Ver_0Tests/CanvasMarkdownLayoutMeasurerTests' -only-testing:'MyCanvas_Ver_0Tests/CanvasMarkdownBitmapRendererTests' -only-testing:'MyCanvas_Ver_0Tests/MarkdownPreviewParityTests' -only-testing:'MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests' -only-testing:'MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests'
Testing failed:
Ambiguous use of 'nan'
```

```bash
# 命令: xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:'MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests' -only-testing:'MyCanvas_Ver_0Tests/CanvasMarkdownContractTests' -only-testing:'MyCanvas_Ver_0Tests/CanvasMarkdownLayoutMeasurerTests' -only-testing:'MyCanvas_Ver_0Tests/CanvasMarkdownBitmapRendererTests' -only-testing:'MyCanvas_Ver_0Tests/MarkdownPreviewParityTests' -only-testing:'MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests' -only-testing:'MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests'
Testing failed:
Value of type 'CanvasMarkdownRenderPayload' has no member 'zoomScale'
Conditional downcast to CoreFoundation type 'CGImage' will always succeed
```

```bash
# 命令: xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:'MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests' -only-testing:'MyCanvas_Ver_0Tests/CanvasMarkdownContractTests' -only-testing:'MyCanvas_Ver_0Tests/CanvasMarkdownLayoutMeasurerTests' -only-testing:'MyCanvas_Ver_0Tests/CanvasMarkdownBitmapRendererTests' -only-testing:'MyCanvas_Ver_0Tests/MarkdownPreviewParityTests' -only-testing:'MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests' -only-testing:'MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests'
** TEST SUCCEEDED **
Test case 'CanvasMarkdownLayoutMeasurerTests.testCodeBlockDecorationPaddingClampsToMinimumAndMaximumBounds()' passed
Test case 'MarkdownPreviewParityTests.testBoardThumbnailRendererKeepsEmptyCodeBlockPanelVisibleInThumbnail()' passed
Test case 'CanvasMarkdownLayerTests.testContentLayerKeepsLogicalLayoutSizeWhenOnlyHeightOrZoomChanges()' passed
Test case 'CanvasMarkdownLayerTests.testContentLayerReflowsWhenLogicalWidthChanges()' passed
Test case 'CanvasMarkdownLayerTests.testItemLayerUsesLogicalBoundsAndCameraScaleTransform()' passed
Test case 'CanvasSelectionTransformStateTests.testResizedMemberItemsKeepMarkdownFontSizeAndStretchContainerGeometry()' passed
Test case 'CanvasMarkdownContractTests.testCanvasSnapshotMapsMarkdownWorldGeometryIntoSharedScreenContract()' passed
Test case 'CanvasMarkdownBitmapRendererTests.testRenderDrawsCodeBlockDecorationWhenCompatibilityBackgroundsDisabled()' passed
```

```bash
# 命令: xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'generic/platform=iOS Simulator'
** BUILD SUCCEEDED **
```

## 结论

- 本次阶段 3 已经把 markdown 主画布链路正式切到 `CanvasMarkdownItemLayer + CanvasMarkdownContentLayer`，并把“逻辑布局”和“相机缩放”拆成两个独立职责。
- 到这一阶段为止，markdown 的 `screenQuad/screenFrame/screenCenter` 契约保持不变；selection outline、handles、rotation preview 和 accessory 锚点仍然可以继续依赖 renderer 现有的屏幕几何输出。
- 和阶段 2 相比，这一步已经不是只在 thumbnail 上验证位图链路，而是把主画布本体也切到了“世界空间布局 + zoom 只做外层几何/栅格”的方向，为阶段 4 的 raster bucket/cache 做好了边界准备。
